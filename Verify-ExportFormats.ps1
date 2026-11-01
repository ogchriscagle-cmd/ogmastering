$ErrorActionPreference='Stop'; $env:OG_MASTERING_TEST='1'
. (Join-Path $PSScriptRoot 'SunoMastering.ps1'); $timer.Stop()
$src=Join-Path $PSScriptRoot 'verification\suno-studio\Suno fixture & stereo.wav'
$out=Join-Path $PSScriptRoot 'verification\formats'; New-Item -ItemType Directory -Force -Path $out | Out-Null
Import-Songs @($src); Stop-AutoAnalysis
$sourceHash=(Get-FileHash -LiteralPath $src).Hash
foreach ($index in 0..2) {
    $ui.ExportType.SelectedIndex=$index; $kind=@('wav','mp3','both')[$index]
    $ext=if ($kind -eq 'mp3') { '.mp3' } else { '.wav' }; $dest=Join-Path $out ($kind+'-master'+$ext)
    Start-Mastering @(@{Source=$src;Destination=$dest})
    $deadline=[DateTime]::UtcNow.AddMinutes(2)
    while ($script:busy -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100; Invoke-EngineTick; Invoke-WaveTick; Update-ActivityStatus }
    if ($script:busy -or $ui.Stage.Text -eq 'Mastering stopped' -or $script:completed.Count -ne 1) { throw $ui.Status.Text }
    $paths=@(Get-ExportPaths $dest $kind)
    foreach ($path in $paths) {
        if (!(Test-Path -LiteralPath $path) -or (Get-Item -LiteralPath $path).Length -lt 1000) { throw "Missing export $path" }
        $bytes=[IO.File]::ReadAllBytes($path)
        if ([IO.Path]::GetExtension($path) -eq '.wav' -and [Text.Encoding]::ASCII.GetString($bytes,0,4) -ne 'RIFF') { throw 'Invalid WAV header' }
        if ([IO.Path]::GetExtension($path) -eq '.mp3' -and [Text.Encoding]::ASCII.GetString($bytes,0,3) -ne 'ID3') { throw 'Invalid MP3 header' }
    }
    if ($kind -ne 'wav' -and !$script:report.Mp3Measurement) { throw 'Encoded MP3 was not measured' }
    if ($script:report.ExportedFiles.Count -ne $paths.Count) { throw 'Report is missing exported paths' }
    Write-Output ("PASS $kind export: "+($paths -join ', '))
}
if ((Get-FileHash -LiteralPath $src).Hash -ne $sourceHash) { throw 'Source was modified' }
Stop-SongDetection; Stop-AutoAnalysis; Stop-Waveform; $player.Close(); $env:OG_MASTERING_TEST=$null
Write-Output 'ALL EXPORT FORMAT CHECKS PASSED'
