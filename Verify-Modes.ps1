$ErrorActionPreference='Stop'; $env:OG_MASTERING_TEST='1'
. (Join-Path $PSScriptRoot 'SunoMastering.ps1'); $timer.Stop()
if ($script:interfaceMode -ne 'simple' -or $ui.QuickControls.Parent.Parent.Visibility -ne 'Collapsed') { throw 'Simple mode did not start correctly' }
$ui.Loudness.Value=-16
Set-InterfaceMode 'advanced'
$ui.Bass.Value=3; $ui.Loudness.Value=-10; $ui.SatEnabled.IsChecked=$true
Set-InterfaceMode 'simple'
if ($ui.Bass.Value -ne 0 -or $ui.Loudness.Value -ne -16 -or $ui.SatEnabled.IsChecked) { throw 'Advanced settings leaked into simple mode' }
Set-InterfaceMode 'advanced'
if ($ui.Bass.Value -ne 3 -or $ui.Loudness.Value -ne -10 -or !$ui.SatEnabled.IsChecked) { throw 'Advanced settings were not preserved' }
Set-Busy $true; Set-InterfaceMode 'simple'
if ($script:interfaceMode -ne 'advanced') { throw 'Mode changed during mastering' }; Set-Busy $false
$out=Join-Path $PSScriptRoot 'verification\modes'; New-Item -ItemType Directory -Force -Path $out | Out-Null
foreach ($mode in @('simple','advanced')) {
    Set-InterfaceMode $mode
    $surface=$window.Content; $surface.Background='#080910'; $surface.Measure([Windows.Size]::new(1500,900)); $surface.Arrange([Windows.Rect]::new(0,0,1500,900)); $surface.UpdateLayout()
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(1500,900,96,96,[Windows.Media.PixelFormats]::Pbgra32); $bitmap.Render($surface)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new(); $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap)); $stream=[IO.File]::Create((Join-Path $out ($mode+'.png'))); $encoder.Save($stream); $stream.Close()
}
Stop-Waveform; $player.Close(); $env:OG_MASTERING_TEST=$null
Write-Output 'PASS: Simple startup, independent settings, Advanced restore, busy protection, both mode layouts.'
