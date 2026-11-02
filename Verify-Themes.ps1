$ErrorActionPreference='Stop'
$env:OG_MASTERING_TEST='1'
$env:OG_THEME_SETTINGS_PATH=Join-Path $PSScriptRoot 'verification\theme-preferences.json'
try {
    . (Join-Path $PSScriptRoot 'SunoMastering.ps1')
    $timer.Stop()
    $settingsBefore=Get-Settings | ConvertTo-Json -Compress
    $brush=Get-AppBrush '#13D4EC'
    $ui.ThemePicker.SelectedItem='Violet Night'
    foreach ($name in $script:themePalettes.Keys) {
        $ui.ThemePicker.SelectedItem=$name
        if ($script:appTheme -ne $name) { throw "Picker failed for $name" }
        if ($brush.Color -ne (Get-ThemeColor '#13D4EC')) { throw "Accent binding failed for $name" }
        if ($window.Background.Color -ne (Get-ThemeColor '#080910')) { throw "Window background failed for $name" }
        $saved=Get-Content -LiteralPath $env:OG_THEME_SETTINGS_PATH -Raw | ConvertFrom-Json
        if ($saved.Theme -ne $name) { throw "Preference save failed for $name" }
        if ((Get-Settings | ConvertTo-Json -Compress) -ne $settingsBefore) { throw 'Theme changed audio settings' }
    }
    Set-AppTheme 'Midnight Cyan' $false
    if ($brush.Color.ToString() -ne '#FF13D4EC') { throw 'Default accent was not restored' }
    Stop-Waveform; $player.Close()
    Write-Output 'PASS: six theme picker options, live brushes, XAML backgrounds, preference saving, and unchanged audio settings.'
} finally {
    if ($timer) { $timer.Stop() }
    $env:OG_MASTERING_TEST=$null
    $env:OG_THEME_SETTINGS_PATH=$null
}
