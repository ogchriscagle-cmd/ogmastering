function Save-StudioProject([string]$path) {
    if ($script:busy) { throw 'Wait for mastering to finish before saving a project.' }
    $project=@{Kind='OGMasteringProject';Version=1;Sources=@($script:sources);Reference=$script:reference;Settings=(Get-Settings);Mode=$script:interfaceMode;ExportType=$ui.ExportType.SelectedIndex;LevelMatch=[bool]$ui.LevelMatch.IsChecked}
    $project | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
    $ui.Status.Text='Project saved. Audio files remain in their original locations.'
}
function Open-StudioProject([string]$path) {
    if ($script:busy) { throw 'Wait for mastering to finish before opening a project.' }
    $p=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($p.Kind -ne 'OGMasteringProject' -or $p.Version -ne 1 -or $p.Mode -notin @('simple','advanced') -or $p.ExportType -notin @(0,1,2)) { throw 'Unsupported OG Mastering project.' }
    $settings=Test-Settings $p.Settings
    foreach ($file in @($p.Sources)+@($p.Reference)) { if ($file -and !(Test-Path -LiteralPath $file -PathType Leaf)) { throw "Project audio file is missing: $file" } }
    Set-InterfaceMode $p.Mode
    if (@($p.Sources).Count) { Import-Songs @($p.Sources); Stop-AutoAnalysis; Stop-SongDetection }
    $script:reference=$p.Reference
    $ui.ReferenceInfo.Text=if ($p.Reference) { 'Reference: '+[IO.Path]::GetFileName($p.Reference) } else { 'Reference matching off' }
    $ui.ClearReference.IsEnabled=[bool]$p.Reference
    Set-Settings $settings
    $ui.ExportType.SelectedIndex=[int]$p.ExportType; $ui.LevelMatch.IsChecked=[bool]$p.LevelMatch
    $ui.Status.Text='Project restored. Master and export when ready.'
}
function Start-UpdateCheck {
    if ($script:updateTask) { return }
    $ui.CheckUpdates.IsEnabled=$false; $ui.CheckUpdates.Content='Checking...'
    $script:updateClient=New-Object Net.WebClient
    $script:updateClient.Headers['User-Agent']='OG-Mastering'
    $script:updateClient.Headers['Accept']='application/vnd.github+json'
    $script:updateStarted=[DateTime]::UtcNow
    $script:updateTask=$script:updateClient.DownloadStringTaskAsync([uri]'https://api.github.com/repos/ogchriscagle-cmd/ogstudiomastering/releases/latest')
}
function Complete-UpdateCheck([string]$json) {
    $release=$json | ConvertFrom-Json
    $remote=[version]([string]$release.tag_name -replace '^v','')
    $local=[version](Get-Content (Join-Path $PSScriptRoot 'release-version.txt') -Raw).Trim()
    if ($remote -gt $local) {
        $ui.Status.Text="Update available: v$remote. Open GitHub releases to download it."
        $ui.CheckUpdates.Content="Update available: v$remote"
    } else { $ui.Status.Text="You are up to date (v$local)."; $ui.CheckUpdates.Content='Check updates' }
}
function Invoke-UpdateCheckTick {
    if (!$script:updateTask) { return }
    if (!$script:updateTask.IsCompleted -and ([DateTime]::UtcNow-$script:updateStarted).TotalSeconds -lt 15) { return }
    try {
        if (!$script:updateTask.IsCompleted -or $script:updateTask.IsFaulted -or $script:updateTask.IsCanceled) { throw 'Release check unavailable' }
        Complete-UpdateCheck $script:updateTask.Result
    } catch {
        $ui.CheckUpdates.Content='Check updates'
        $ui.Status.Text='Automatic check unavailable. This repository is private; sign in in your browser and open GitHub releases to check for updates.'
        Start-Process 'https://github.com/ogchriscagle-cmd/ogstudiomastering/releases/latest'
    } finally { $script:updateClient.CancelAsync(); $script:updateClient.Dispose(); $script:updateTask=$null; $ui.CheckUpdates.IsEnabled=$true }
}
function Initialize-Toolbar {
    $root=$window.Content
    $row=New-Object Windows.Controls.RowDefinition; $row.Height='Auto'; $root.RowDefinitions.Insert(1,$row)
    foreach ($child in $root.Children) { $index=[Windows.Controls.Grid]::GetRow($child); if ($index -ge 1) { [Windows.Controls.Grid]::SetRow($child,($index+1)) } }
    $bar=New-Object Windows.Controls.Border; $bar.Padding='20,8'; $bar.Background=Get-AppBrush '#101019'; $bar.BorderBrush=Get-AppBrush '#26303A'; $bar.BorderThickness='0,0,0,1'
    $panel=New-Object Windows.Controls.WrapPanel
    $version=New-Object Windows.Controls.TextBlock; $version.Text='v'+(Get-Content (Join-Path $PSScriptRoot 'release-version.txt') -Raw).Trim(); $version.VerticalAlignment='Center'; $version.Margin='0,0,20,0'; $version.FontSize=10; $panel.Children.Add($version) | Out-Null
    foreach ($spec in @(@('GitHubSignIn','Sign in on GitHub / browser'),@('CheckUpdates','Check updates'),@('GitHubReleases','GitHub releases'),@('OpenProject','Open / import'),@('SaveProject','Save project'),@('ToolbarExport','Master / export'))) {
        $button=New-Object Windows.Controls.Button; $button.Content=$spec[1]; $button.FontSize=11; $button.Padding='13,8'; $ui[$spec[0]]=$button; $panel.Children.Add($button) | Out-Null
    }
    $ui.GitHubSignIn.ToolTip='Opens GitHub sign-in in your browser. The app does not store GitHub credentials.'
    $ui.GitHubSignIn.Add_Click({ Start-Process 'https://github.com/login?return_to=%2Fogchriscagle-cmd%2Fogstudiomastering%2Freleases' })
    $ui.GitHubReleases.Add_Click({ Start-Process 'https://github.com/ogchriscagle-cmd/ogstudiomastering/releases' })
    $ui.CheckUpdates.Add_Click({ Start-UpdateCheck })
    $window.Add_Closing({ if ($script:updateClient) { $script:updateClient.CancelAsync(); $script:updateClient.Dispose() } })
    $ui.OpenProject.Add_Click({ try { if ($script:busy) { return }; $d=New-Object Microsoft.Win32.OpenFileDialog; $d.Filter='Songs or OG projects|*.ogmaster;*.wav;*.mp3;*.flac;*.m4a;*.aif;*.aiff;*.ogg|OG Mastering project|*.ogmaster'; if ($d.ShowDialog()) { if ([IO.Path]::GetExtension($d.FileName) -eq '.ogmaster') { Open-StudioProject $d.FileName } else { Import-Songs @($d.FileName) } } } catch { [Windows.MessageBox]::Show($_.Exception.Message,'Open project') | Out-Null } })
    $ui.SaveProject.Add_Click({ try { if ($script:busy) { return }; $d=New-Object Microsoft.Win32.SaveFileDialog; $d.Filter='OG Mastering project|*.ogmaster'; $d.FileName='My mastering project.ogmaster'; if ($d.ShowDialog()) { Save-StudioProject $d.FileName } } catch { [Windows.MessageBox]::Show($_.Exception.Message,'Save project') | Out-Null } })
    $ui.ToolbarExport.Add_Click({ if ($ui.Render.IsEnabled) { $ui.Render.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent)) } })
    $binding=[Windows.Data.Binding]::new('IsEnabled'); $binding.Source=$ui.Render; $ui.ToolbarExport.SetBinding([Windows.Controls.Button]::IsEnabledProperty,$binding) | Out-Null
    $bar.Child=$panel; [Windows.Controls.Grid]::SetRow($bar,1); $root.Children.Add($bar) | Out-Null
}
