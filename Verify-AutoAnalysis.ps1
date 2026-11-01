$ErrorActionPreference='Stop'; $env:OG_MASTERING_TEST='1'
. (Join-Path $PSScriptRoot 'SunoMastering.ps1'); $timer.Stop()
function Wait-Analysis {
    $deadline=[DateTime]::UtcNow.AddMinutes(1)
    while ($script:analysisProcess -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100; Invoke-AutoAnalysisTick; Invoke-WaveTick }
    if ($script:analysisProcess) { throw 'Analysis timed out' }
}
$src=Join-Path $PSScriptRoot 'verification\suno-studio\Suno fixture & stereo.wav'
Set-InterfaceMode 'advanced'; $ui.Glue.Value=40
Import-Songs @($src); $ui.Bass.Value=2
Wait-Analysis
if (!$script:analysisResult -or $ui.InputMeter.Text -eq '— LUFS') { throw 'Automatic import analysis failed' }
if ($ui.Glue.Value -ne 40 -or $ui.Bass.Value -ne 2) { throw 'Analysis replaced user edits' }
Apply-AnalysisSettings
if ($ui.Glue.Value -ne 0 -or $ui.Bass.Value -ne 2) { throw 'Suggestion application failed' }
Import-Songs @($src); Wait-Analysis
if (!$script:analysisResult -or $script:analysisTemp) { throw 'Analysis result or cleanup failed' }
Import-Songs @((Join-Path $PSScriptRoot 'verification\suno-studio\Silent.wav')); Wait-Analysis
if ($script:analysisResult -or $ui.ApplyAnalysis.IsEnabled) { throw 'Silence was accepted as valid analysis' }
Stop-SongDetection; Stop-AutoAnalysis; Stop-Waveform; $player.Close(); $env:OG_MASTERING_TEST=$null
Write-Output 'PASS: automatic import analysis, measurements, edit protection, cleanup application, temp cleanup and silence rejection.'
