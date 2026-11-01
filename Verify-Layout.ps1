$ErrorActionPreference='Stop'
$env:OG_MASTERING_TEST='1'
. (Join-Path $PSScriptRoot 'SunoMastering.ps1')
$timer.Stop()
$out=Join-Path $PSScriptRoot 'verification\layout'
New-Item -ItemType Directory -Path $out -Force | Out-Null
$fixture=Join-Path $PSScriptRoot 'verification\suno-studio\Suno fixture & stereo.wav'
Import-Songs @($fixture)
$deadline=[DateTime]::UtcNow.AddSeconds(30)
while ($script:waveProcess -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100; Invoke-WaveTick }
if (!$ui.WaveImage.Source) { throw 'Waveform generation failed' }
if ($ui.QuickControls.Children.Count -ne 9) { throw 'Missing quick controls' }
$ui.VocalsType.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if ($ui.DeEss.Value -ne 20) { throw 'Vocal control is not wired' }
$ui.InstrumentalType.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
if ($ui.DeEss.Value -ne 0) { throw 'Instrumental control is not wired' }
Set-Style 'Warm'
if ($ui.Bass.Value -ne 1.5 -or $ui.Air.Value -ne -1) { throw 'Style did not update DSP' }
Select-StudioMode 'bulk'
if ($script:importMode -ne 'bulk') { throw 'Bulk mode did not activate' }
Select-StudioMode 'presets'
if (!$ui.PresetPanel.IsExpanded) { throw 'Preset panel did not open' }
$ui.PresetPanel.IsExpanded=$false; Select-StudioMode 'single'; Set-Settings (Get-DefaultSettings)
$ui.TrackName.Text='01 / SUNO STUDIO SESSION'; $ui.TrackInfo.Text='Generated audio test · stereo · local processing'
$ui.Status.Text='Layout and control checks passed. Waveform generated from the audio file.'
foreach ($size in @(@(1500,900),@(1120,740))) {
    $surface=$window.Content; $surface.Background='#080910'
    $surface.Measure([Windows.Size]::new($size[0],$size[1])); $surface.Arrange([Windows.Rect]::new(0,0,$size[0],$size[1])); $surface.UpdateLayout()
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new($size[0],$size[1],96,96,[Windows.Media.PixelFormats]::Pbgra32); $bitmap.Render($surface)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new(); $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream=[IO.File]::Create((Join-Path $out ("studio-"+$size[0]+'.png'))); $encoder.Save($stream); $stream.Close()
}
Stop-SongDetection; Stop-AutoAnalysis; Stop-Waveform; $player.Close(); $env:OG_MASTERING_TEST=$null
Write-Output 'PASS: waveform, nine DSP knobs, vocal/instrumental, styles, single/bulk/preset navigation, two window sizes.'
