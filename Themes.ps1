$script:themeBrushes=@{}
$script:themeSources=@{}
$script:appTheme='Midnight Cyan'
$script:themePalettes=[ordered]@{
    'Midnight Cyan'=@('#080910','#13CEE7')
    'Violet Night'=@('#110D1D','#B78AFF')
    'Emerald'=@('#08140F','#36DBA0')
    'Crimson'=@('#180D12','#FF6B87')
    'Amber'=@('#171208','#F6BF43')
    'Ocean Blue'=@('#09121F','#69ADFF')
}
function Get-ThemeColor([string]$hex) {
    $c=[Windows.Media.ColorConverter]::ConvertFromString($hex)
    if ($script:appTheme -eq 'Midnight Cyan') { return $c }
    $key='{0:X2}{1:X2}{2:X2}' -f $c.R,$c.G,$c.B
    # Keep quick-adjust knob colors as stable visual identifiers.
    if ($key -in @('FFAC06','FF4E58','FF963B','0DD3EF','20D5A3','C37DFF','A58AFF','629DFF','25DBB4')) { return $c }
    $palette=$script:themePalettes[$script:appTheme]
    $bg=[Windows.Media.ColorConverter]::ConvertFromString($palette[0]); $accent=[Windows.Media.ColorConverter]::ConvertFromString($palette[1])
    $max=[math]::Max($c.R,[math]::Max($c.G,$c.B)); $min=[math]::Min($c.R,[math]::Min($c.G,$c.B))
    if ($max -lt 106) {
        $delta=[math]::Max(0,($max-16)*0.65)
        return [Windows.Media.Color]::FromArgb($c.A,[byte][math]::Min(255,$bg.R+$delta),[byte][math]::Min(255,$bg.G+$delta),[byte][math]::Min(255,$bg.B+$delta))
    }
    if ($max -gt 105 -and ($max-$min)/[double]$max -gt 0.45 -and $c.B -gt $c.R*1.3 -and $c.G -gt $c.R*1.2) {
        $scale=$max/255.0
        return [Windows.Media.Color]::FromArgb($c.A,[byte]($accent.R*$scale),[byte]($accent.G*$scale),[byte]($accent.B*$scale))
    }
    return $c
}
function Get-AppBrush([string]$hex) {
    $c=[Windows.Media.ColorConverter]::ConvertFromString($hex)
    $key=$c.ToString().ToUpperInvariant()
    if (!$script:themeBrushes.ContainsKey($key)) {
        $source=[Windows.Media.SolidColorBrush]::new((Get-ThemeColor $key))
        $brush=[Windows.Media.SolidColorBrush]::new()
        $binding=[Windows.Data.Binding]::new('Color'); $binding.Source=$source
        [Windows.Data.BindingOperations]::SetBinding($brush,[Windows.Media.SolidColorBrush]::ColorProperty,$binding) | Out-Null
        $script:themeSources[$key]=$source; $script:themeBrushes[$key]=$brush
    }
    return $script:themeBrushes[$key]
}
function Convert-ThemeXaml([string]$text) {
    $colors=[regex]::Matches($text,'="#([0-9A-Fa-f]{6})"') | ForEach-Object { $_.Groups[1].Value.ToUpperInvariant() } | Select-Object -Unique
    $resources=''
    foreach ($hex in $colors) { $resources+='<SolidColorBrush x:Key="Theme_'+$hex+'" Color="#'+$hex+'" />' }
    $converted=[regex]::Replace($text,'="#([0-9A-Fa-f]{6})"',{ param($m) '="{DynamicResource Theme_'+$m.Groups[1].Value.ToUpperInvariant()+'}"' })
    return $converted.Replace('<Window.Resources>','<Window.Resources>'+$resources)
}
function Get-ThemePreferencesPath {
    if ($env:OG_THEME_SETTINGS_PATH) { return $env:OG_THEME_SETTINGS_PATH }
    return (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'OGMastering\preferences.json')
}
function Set-AppTheme([string]$name,[bool]$save=$true) {
    if (!$script:themePalettes.Contains($name)) { return }
    $script:appTheme=$name
    foreach ($key in @($script:themeSources.Keys)) { $script:themeSources[$key].Color=Get-ThemeColor $key }
    if ($save -and (!$env:OG_MASTERING_TEST -or $env:OG_THEME_SETTINGS_PATH)) {
        try {
            $path=Get-ThemePreferencesPath; [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) | Out-Null
            @{Theme=$name} | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding UTF8
        } catch { $ui.Status.Text='Theme applied. Preference could not be saved: '+$_.Exception.Message }
    }
}
function Initialize-Themes {
    # Reuse mutable brush instances in XAML and programmatically-created controls.
    foreach ($key in @($window.Resources.Keys)) { if ([string]$key -like 'Theme_*') { $window.Resources[$key]=Get-AppBrush ('#'+([string]$key).Substring(6)) } }
    $sidebar=$ui.Preset.Parent
    $label=New-Object Windows.Controls.TextBlock; $label.Text='COLOR THEME'; $label.FontSize=9; $label.Foreground=Get-AppBrush '#7D96B2'; $label.Margin='0,0,0,0'
    $combo=New-Object Windows.Controls.ComboBox; foreach ($name in $script:themePalettes.Keys) { $combo.Items.Add($name) | Out-Null }; $ui.ThemePicker=$combo
    $sidebar.Children.Insert(1,$label); $sidebar.Children.Insert(2,$combo)
    $selected='Midnight Cyan'
    try { $path=Get-ThemePreferencesPath; if (Test-Path -LiteralPath $path) { $saved=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json; if ($script:themePalettes.Contains([string]$saved.Theme)) { $selected=[string]$saved.Theme } } } catch { }
    Set-AppTheme $selected $false
    $combo.SelectedItem=$selected
    $combo.Add_SelectionChanged({ if ($this.SelectedItem) { Set-AppTheme ([string]$this.SelectedItem) } })
}
