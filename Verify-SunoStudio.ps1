$ErrorActionPreference='Stop'
$env:OG_MASTERING_TEST='1'
. (Join-Path $PSScriptRoot 'SunoMastering.ps1')
$timer.Stop()
$testRoot=Join-Path $PSScriptRoot 'verification\suno-studio'
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
function Assert([bool]$condition,[string]$message) { if (!$condition) { throw $message } }
function Wait-Session {
    $deadline=[DateTime]::UtcNow.AddMinutes(3)
    while ($script:busy -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100; Invoke-EngineTick; Invoke-WaveTick }
    Assert (!$script:busy) 'Session timed out'
    Assert ($ui.Stage.Text -notin @('Mastering stopped','Cancelled')) $ui.Status.Text
}
$src=Join-Path $testRoot 'Suno fixture & stereo.wav'
$ref=Join-Path $testRoot 'Reference.wav'
$mono=Join-Path $testRoot 'Mono.wav'
$silent=Join-Path $testRoot 'Silent.wav'
& $script:ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'anoisesrc=color=pink:amplitude=0.3:duration=5:sample_rate=48000:seed=17' -af 'aformat=channel_layouts=stereo,treble=g=3' $src
Assert ($LASTEXITCODE -eq 0) 'Could not generate source fixture'
& $script:ffmpeg -hide_banner -loglevel error -y -i $src -af 'bass=g=4,treble=g=-3' $ref
& $script:ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'sine=frequency=440:duration=4:sample_rate=44100' $mono
& $script:ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'anullsrc=r=48000:cl=stereo' -t 4 $silent
$sourceHash=(Get-FileHash -LiteralPath $src).Hash
Import-Songs @($src,$mono)
$script:reference=$ref
$s=Get-GenreSettings 1
$s.Repair=$true; $s.Excite=20; $s.Glue=20; $s.MidPresence=1; $s.SideAir=1; $s.Eq0=0.5
Set-Settings $s
$dest1=Join-Path $testRoot 'Master stereo.wav'; $dest2=Join-Path $testRoot 'Master mono.wav'
Start-Mastering @(@{Source=$src;Destination=$dest1},@{Source=$mono;Destination=$dest2})
Wait-Session
Assert ($script:completed.Count -eq 2) 'Batch did not complete'
Assert ((Get-FileHash -LiteralPath $src).Hash -eq $sourceHash) 'Source was modified'
foreach ($report in $script:completed) {
    Assert (Test-Path -LiteralPath $report.Destination) 'Missing export'
    $peak=[double]::Parse($report.OutputMeasurement.input_tp,[Globalization.CultureInfo]::InvariantCulture)
    Assert ($peak -le ($s.Ceiling+0.1)) "Peak ceiling failed: $peak"
    Assert ($report.ReferenceGainsDb.Count -eq 6) 'Missing reference gains'
    foreach ($gain in $report.ReferenceGainsDb) { Assert ([math]::Abs($gain) -le 1.5) 'Reference correction exceeded cap at 50% strength' }
    Write-Output ("PASS export: {0}; {1} LUFS; {2} dBTP" -f [IO.Path]::GetFileName($report.Destination),$report.OutputMeasurement.input_i,$peak)
}
ConvertTo-Json -InputObject @($script:completed) -Depth 8 | Set-Content -LiteralPath (Join-Path $testRoot 'report.json') -Encoding UTF8
# A second format and decimal-comma culture exercise the same app state machine.
$script:reference=$null
Import-Songs @($src)
$s=Get-GenreSettings 7; $s.Format=1; $s.Loudness=-16; $s.Ceiling=-1.5
Set-Settings $s
$beforeCulture=[Threading.Thread]::CurrentThread.CurrentCulture
try {
    [Threading.Thread]::CurrentThread.CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo('de-DE')
    Start-Mastering @(@{Source=$src;Destination=(Join-Path $testRoot 'Master 16bit.wav')})
    Wait-Session
} finally { [Threading.Thread]::CurrentThread.CurrentCulture=$beforeCulture }
Assert ($script:completed.Count -eq 1) '16-bit export failed'
Write-Output 'PASS 16-bit/44.1k export under decimal-comma locale'
# Invalid custom presets cannot pass arbitrary filter text into the DSP graph.
$invalid=Get-DefaultSettings; $invalid.Width='1,evil'
$rejected=$false; try { Test-Settings $invalid | Out-Null } catch { $rejected=$true }
Assert $rejected 'Invalid preset was accepted'
$serialized=Get-Settings | ConvertTo-Json | ConvertFrom-Json
$roundtrip=Test-Settings $serialized
Assert ($roundtrip.Format -eq 1 -and $roundtrip.Loudness -eq -16) 'Preset roundtrip failed'
Write-Output 'PASS preset roundtrip and invalid-value rejection'
$rejected=$false; try { Start-Mastering @(@{Source=$src;Destination=$src}) } catch { $rejected=$true }
Assert $rejected 'Source overwrite was allowed'
Write-Output 'PASS source overwrite protection'
# Cancel must leave a pre-existing export intact.
$oldHash=(Get-FileHash -LiteralPath $dest1).Hash
Start-Mastering @(@{Source=$src;Destination=$dest1})
Stop-Mastering
Assert ((Get-FileHash -LiteralPath $dest1).Hash -eq $oldHash) 'Cancel replaced an existing export'
Assert (!$script:temp) 'Cancel did not clean up session'
Write-Output 'PASS cancel preserves existing export'
Import-Songs @($silent)
Start-Mastering @(@{Source=$silent;Destination=(Join-Path $testRoot 'Must not export.wav')})
while ($script:busy) { Start-Sleep -Milliseconds 100; Invoke-EngineTick }
Assert ($ui.Stage.Text -eq 'Mastering stopped') 'Silence was not rejected'
Assert (!(Test-Path -LiteralPath (Join-Path $testRoot 'Must not export.wav'))) 'Silence created an export'
Write-Output 'PASS silent-source rejection'
Stop-Waveform
$player.Close(); $env:OG_MASTERING_TEST=$null
Write-Output 'ALL SUNO STUDIO CHECKS PASSED'
