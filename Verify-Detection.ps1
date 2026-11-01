$ErrorActionPreference='Stop'; $env:OG_MASTERING_TEST='1'
. (Join-Path $PSScriptRoot 'SunoMastering.ps1'); $timer.Stop()
if (!(Test-Path -LiteralPath (Join-Path $script:detectRuntime 'ready.json'))) { throw 'Run Setup-Detection.cmd first.' }
$source=Join-Path $PSScriptRoot 'verification\suno-studio\Suno fixture & stereo.wav'
$hash=(Get-FileHash -LiteralPath $source).Hash
$ui.AutoDetect.IsChecked=$true
Import-Songs @($source)
$deadline=[DateTime]::UtcNow.AddMinutes(3)
while (($script:analysisProcess -or $script:detectProcess) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 200; Invoke-AutoAnalysisTick; Invoke-SongDetectionTick; Invoke-WaveTick; Update-ActivityStatus }
if (!$script:detectionResult) { throw $ui.DetectionText.Text }
$result=$script:detectionResult.Result
if ($result.topGenres.Count -ne 3 -or $result.excerpts -lt 1 -or $result.vocals -notin @('Likely vocals','Likely instrumental','Uncertain')) { throw 'Invalid inference result' }
$target=$ui.Loudness.Value
Apply-SongDetection
if ((Get-Settings).Genre -ne $result.genre -or $ui.Loudness.Value -ne $target) { throw 'Applying detection lost settings' }
if ((Get-FileHash -LiteralPath $source).Hash -ne $hash) { throw 'Detection altered the source' }
$out=Join-Path $PSScriptRoot 'verification\detection'; New-Item -ItemType Directory -Force -Path $out | Out-Null
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $out 'result.json') -Encoding UTF8
Stop-SongDetection; Stop-AutoAnalysis; Stop-Waveform; $player.Close(); $env:OG_MASTERING_TEST=$null
Write-Output 'PASS: cached-model offline inference, three ranked genres, vocal result, applying settings, original file preserved.'
Write-Output 'Synthetic fixture validates integration, not genre/vocal classification accuracy.'
