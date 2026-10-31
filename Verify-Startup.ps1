$ErrorActionPreference='Stop'
$env:OG_MASTERING_TEST='1'
. (Join-Path $PSScriptRoot 'SunoMastering.ps1')
$timer.Stop()
if ($script:genreCatalog.Count -ne 58) { throw "Expected 58 genres; found $($script:genreCatalog.Count)" }
foreach ($i in 0..($script:genreCatalog.Count-1)) {
    $ui.Preset.SelectedIndex=$i
    if ((Get-Settings).Genre -ne $script:genreCatalog[$i].Name) { throw "Genre selection failed: $i" }
}
$ui.Preset.SelectedIndex=0
Stop-Waveform; $player.Close()
$env:OG_MASTERING_TEST=$null
Write-Output ('PASS: startup and all '+$script:genreCatalog.Count+' genres on PowerShell '+$PSVersionTable.PSVersion)
