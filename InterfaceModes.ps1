function Set-InterfaceMode([string]$mode) {
    if ($script:busy -or $mode -eq $script:interfaceMode) { return }
    if ($script:interfaceMode -eq 'simple') { $script:simpleSettings=Get-Settings } else { $script:advancedSettings=Get-Settings }
    $script:interfaceMode=$mode
    if ($mode -eq 'simple') {
        if (!$script:simpleSettings) { $script:simpleSettings=Get-CatalogGenreSettings 0 }
        Set-Settings $script:simpleSettings
        Select-StudioMode 'single'
    } else {
        if ($script:advancedSettings) { Set-Settings $script:advancedSettings }
    }
    $visibility=if ($mode -eq 'simple') { 'Collapsed' } else { 'Visible' }
    foreach ($element in $script:advancedElements) { $element.Visibility=$visibility }
    $ui.SimpleInstructions.Visibility=if ($mode -eq 'simple') { 'Visible' } else { 'Collapsed' }
    foreach ($key in @('SimpleInterface','AdvancedInterface')) { $ui[$key].Background=(Get-AppBrush '#10151E'); $ui[$key].BorderBrush=(Get-AppBrush '#26303A') }
    $key=if ($mode -eq 'simple') { 'SimpleInterface' } else { 'AdvancedInterface' }
    $ui[$key].Background=(Get-AppBrush '#103346'); $ui[$key].BorderBrush=(Get-AppBrush '#0AA9C6')
    $window.Title='OG Mastering · '+(Get-Culture).TextInfo.ToTitleCase($mode)+' Mode'
    $ui.Status.Text=if ($mode -eq 'simple') { 'Choose a song, optionally add a reference, then master and export. Balanced Suno settings are applied.' } else { 'Full studio controls restored. Your advanced settings are preserved separately.' }
}
function Initialize-InterfaceModes {
    $script:interfaceMode=''; $script:simpleSettings=$null; $script:advancedSettings=$null
    $nav=$ui.SingleMode.Parent
    foreach ($spec in @(@('SimpleInterface','Simple'),@('AdvancedInterface','Advanced'))) {
        $button=New-Object Windows.Controls.Button; $button.Content=$spec[1]; $button.Padding='17,7'; $button.Tag=$spec[1].ToLowerInvariant(); $button.Add_Click({ Set-InterfaceMode ([string]$this.Tag) }); $ui[$spec[0]]=$button
    }
    $nav.Children.Insert(0,$ui.AdvancedInterface); $nav.Children.Insert(0,$ui.SimpleInterface)
    $sidebar=$ui.Preset.Parent
    $genreLabel=$sidebar.Children[$sidebar.Children.IndexOf($ui.Preset)-1]
    $styleLabel=$sidebar.Children[$sidebar.Children.IndexOf($ui.StyleButtons)-1]
    $trackTypes=$ui.VocalsType.Parent; $trackLabel=$trackTypes.Parent.Children[$trackTypes.Parent.Children.IndexOf($trackTypes)-1]
    $script:advancedElements=@($ui.Preset,$genreLabel,$ui.StyleButtons,$styleLabel,$ui.AdvancedPanel,$ui.PresetPanel,$trackTypes,$trackLabel,$ui.GenreInfo,$ui.QuickControls.Parent.Parent,$ui.SingleMode,$ui.BulkMode,$ui.PresetsMode)
    $box=New-Object Windows.Controls.Border; $box.Background=(Get-AppBrush '#0B1822'); $box.BorderBrush=(Get-AppBrush '#16475A'); $box.BorderThickness='1'; $box.CornerRadius='12'; $box.Padding='18'; $box.Margin='0,0,0,15'
    $text=New-Object Windows.Controls.TextBlock; $text.Text="SIMPLE MASTERING`n`n1. Choose your Suno song`n2. Add a reference (optional)`n3. Choose loudness and export`n`nUse Advanced for individual processing controls."; $text.TextWrapping='Wrap'; $text.Foreground=(Get-AppBrush '#98B8D5'); $text.FontSize=12; $box.Child=$text
    $ui.SimpleInstructions=$box
    $ui.GenreInfo.Parent.Children.Insert(0,$box)
    Set-InterfaceMode 'simple'
}
