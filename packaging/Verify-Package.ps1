$ErrorActionPreference='Stop'
$packageLog=Join-Path $PSScriptRoot 'package-test.log'
try {
    $env:OG_MASTERING_TEST='1'
    . (Join-Path $PSScriptRoot 'SunoMastering.ps1'); $timer.Stop(); $ui.AutoDetect.IsChecked=$false
    if ($ui.Preset.Items.Count -ne 58) { throw 'Missing genre presets' }
    $folder=Join-Path $PSScriptRoot 'package-test'; New-Item -ItemType Directory -Force -Path $folder | Out-Null
    $source=Join-Path $folder 'input.wav'
    & $script:ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'sine=frequency=440:duration=4:sample_rate=48000' -ac 2 $source
    if ($LASTEXITCODE) { throw 'Bundled FFmpeg failed' }
    Import-Songs @($source);Stop-AutoAnalysis;$ui.ExportType.SelectedIndex=2
    Start-Mastering @(@{Source=$source;Destination=(Join-Path $folder 'master.wav')})
    $deadline=[DateTime]::UtcNow.AddMinutes(3)
    while ($script:busy -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100;Invoke-EngineTick;Invoke-WaveTick;Update-ActivityStatus }
    if ($script:busy -or $script:completed.Count -ne 1) { throw $ui.Status.Text }
    if (!(Test-Path (Join-Path $folder 'master.wav')) -or !(Test-Path (Join-Path $folder 'master.mp3'))) { throw 'Export files missing' }
    Start-AutoAnalysis
    while ($script:analysisProcess -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100;Invoke-AutoAnalysisTick }
    Start-SongDetection
    while ($script:detectProcess -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 200;Invoke-SongDetectionTick }
    if (!$script:detectionResult) { throw $ui.DetectionText.Text }
    Stop-SongDetection;Stop-AutoAnalysis;Stop-Waveform;$player.Close()
    'PASS: extracted package startup, 58 presets, bundled FFmpeg, WAV + MP3 export, local offline model inference.' | Set-Content -LiteralPath $packageLog
    exit 0
} catch { ($_ | Out-String)+$_.ScriptStackTrace | Set-Content -LiteralPath $packageLog; exit 1 }
