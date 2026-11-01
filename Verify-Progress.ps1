$ErrorActionPreference='Stop'; $env:OG_MASTERING_TEST='1'
. (Join-Path $PSScriptRoot 'SunoMastering.ps1'); $timer.Stop()
$src=Join-Path $PSScriptRoot 'verification\suno-studio\Suno fixture & stereo.wav'
$out=Join-Path $PSScriptRoot 'verification\progress'; New-Item -ItemType Directory -Force -Path $out | Out-Null
Import-Songs @($src)
$deadline=[DateTime]::UtcNow.AddMinutes(1)
while ($script:analysisProcess -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100; Invoke-AutoAnalysisTick; Invoke-WaveTick; Update-ActivityStatus }
if (!$script:analysisResult) { throw 'Import analysis failed' }
Start-Mastering @(@{Source=$src;Destination=(Join-Path $out 'progress-master.wav')})
$seen=$false; $deadline=[DateTime]::UtcNow.AddMinutes(1)
while ($script:busy -and [DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 100; Invoke-EngineTick; Invoke-WaveTick; Update-ActivityStatus
    if ($ui.FooterProgress.Value -gt 0 -and $ui.FooterProgress.Value -lt 100) { $seen=$true }
}
Update-ActivityStatus
if ($script:busy -or $ui.Stage.Text -eq 'Mastering stopped') { throw $ui.Status.Text }
if (!$seen -or $ui.FooterProgress.Value -ne 100 -or $ui.FooterPercent.Text -ne 'Complete') { throw 'Progress did not update correctly' }
if ($script:activityEntries.Count -lt 4) { throw 'Activity log is missing processing stages' }
$surface=$window.Content; $surface.Background='#080910'; $surface.Measure([Windows.Size]::new(1500,900)); $surface.Arrange([Windows.Rect]::new(0,0,1500,900)); $surface.UpdateLayout()
$bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(1500,900,96,96,[Windows.Media.PixelFormats]::Pbgra32); $bitmap.Render($surface)
$encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new(); $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap)); $stream=[IO.File]::Create((Join-Path $out 'footer.png')); $encoder.Save($stream); $stream.Close()
Stop-SongDetection; Stop-AutoAnalysis; Stop-Waveform; $player.Close(); $env:OG_MASTERING_TEST=$null
Write-Output 'PASS: analysis, audio-timed processing progress, stage history, completion at 100%, and fixed footer layout.'
