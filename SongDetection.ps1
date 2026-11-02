function Stop-SongDetection {
    if ($script:detectProcess) {
        if (!$script:detectProcess.HasExited) {
            # Stop this worker and its FFmpeg child together.
            Start-Process -FilePath taskkill.exe -ArgumentList @('/PID',[string]$script:detectProcess.Id,'/T','/F') -WindowStyle Hidden -Wait
            $script:detectProcess.WaitForExit()
        }
        $script:detectProcess.Dispose(); $script:detectProcess=$null
    }
    if ($script:detectTemp) {
        $full=[IO.Path]::GetFullPath($script:detectTemp); $base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
        if ($full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($full).StartsWith('OGDetect-') -and (Test-Path -LiteralPath $full)) { Remove-Item -LiteralPath $full -Recurse -Force }
    }
    $script:detectTemp=$null
}
function Start-SongDetection {
    if ($script:busy -or !$script:source) { return }
    if (!(Test-Path -LiteralPath (Join-Path $script:detectRuntime 'ready.json'))) { $ui.DetectionText.Text='Run Setup-Detection.cmd once to download the local genre/vocal model, then restart.'; return }
    if (!$script:analysisResult -or $script:analysisResult.Path -ne $script:source) { $ui.AutoDetect.IsChecked=$true; Start-AutoAnalysis; return }
    Stop-SongDetection; $script:detectionResult=$null; $ui.ApplyDetection.IsEnabled=$false
    $script:detectTemp=Join-Path ([IO.Path]::GetTempPath()) ('OGDetect-'+[guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $script:detectTemp | Out-Null
    $script:detectPath=$script:source; $script:detectOutput=Join-Path $script:detectTemp 'result.json'; $script:detectStatus=Join-Path $script:detectTemp 'status.json'
    $request=@{runtime=$script:detectRuntime;source=$script:source;ffmpeg=$script:ffmpeg;catalog=(Join-Path $PSScriptRoot 'GenrePresets.json');duration=$script:analysisResult.Duration;output=$script:detectOutput;status=$script:detectStatus}
    $requestPath=Join-Path $script:detectTemp 'request.json'; $request | ConvertTo-Json | Set-Content -LiteralPath $requestPath -Encoding UTF8
    $worker=Join-Path $PSScriptRoot 'detection\detect.mjs'; $node=Join-Path $script:detectRuntime 'node-v24.13.0-win-x64\node.exe'
    try { $script:detectProcess=Start-Process -FilePath $node -ArgumentList ('"'+$worker+'" "'+$requestPath+'"') -WindowStyle Hidden -RedirectStandardError (Join-Path $script:detectTemp 'error.log') -PassThru; $null=$script:detectProcess.Handle; $ui.DetectionText.Text='Loading local genre/vocal detection model…' }
    catch { $ui.DetectionText.Text='Detection could not start: '+$_.Exception.Message; Stop-SongDetection }
}
function Invoke-SongDetectionTick {
    if (!$script:detectProcess) { return }
    if (!$script:detectProcess.HasExited) {
        try { if (Test-Path -LiteralPath $script:detectStatus) { $status=Get-Content -LiteralPath $script:detectStatus -Raw | ConvertFrom-Json; $ui.DetectionText.Text=$status.message } } catch { }
        return
    }
    try {
        if ($script:detectProcess.ExitCode -ne 0 -or !(Test-Path -LiteralPath $script:detectOutput)) { throw 'Local model detection failed. Try again, or rerun Setup-Detection.cmd.' }
        $result=Get-Content -LiteralPath $script:detectOutput -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($script:source -ne $script:detectPath) { return }
        $script:detectionResult=@{Path=$script:detectPath;Result=$result}
        $prefix=if ($result.genreUncertain) { 'Genre uncertain; closest matches' } else { 'Suggested genres' }
        $top=($result.topGenres | ForEach-Object { $_.name+' '+[math]::Round($_.score*100)+'%' }) -join ' / '
        $ui.DetectionText.Text="$prefix`: $top.`n$($result.vocals) · listened to $($result.excerpts) excerpts. Scores are relative model matches, not accuracy probabilities."
        $ui.ApplyDetection.IsEnabled=$true
    } catch { $ui.DetectionText.Text=$_.Exception.Message } finally { Stop-SongDetection }
}
function Apply-SongDetection {
    if ($script:busy -or !$script:detectionResult -or $script:detectionResult.Path -ne $script:source) { return }
    $result=$script:detectionResult.Result; $old=Get-Settings
    foreach ($i in 0..($script:genreCatalog.Count-1)) { if ($script:genreCatalog[$i].Name -eq $result.genre) { $ui.Preset.SelectedIndex=$i; $s=Get-CatalogGenreSettings $i; break } }
    if (!$s) { return }; $s.Loudness=$old.Loudness; $s.Format=$old.Format
    if ($result.vocals -eq 'Likely instrumental') { $s.DeEss=0 } elseif ($result.vocals -eq 'Likely vocals') { $s.DeEss=[math]::Max(20,$s.DeEss) }
    Set-Settings $s; $ui.Status.Text='Applied suggested genre and vocal settings. Your loudness target and export format were kept.'
}
function Initialize-SongDetection {
    $script:detectRuntime=Join-Path $PSScriptRoot 'bin\detection'; $script:detectProcess=$null; $script:detectTemp=$null; $script:detectionResult=$null
    $hostPanel=$ui.AnalysisText.Parent
    $box=New-Object Windows.Controls.CheckBox; $box.Content='Auto-detect genre and vocals on import'; $box.IsChecked=(Test-Path -LiteralPath (Join-Path $script:detectRuntime 'ready.json')); $ui.AutoDetect=$box; $hostPanel.Children.Add($box) | Out-Null
    $text=New-Object Windows.Controls.TextBlock; $text.Foreground=(Get-AppBrush '#86B8CF'); $text.FontSize=11; $text.TextWrapping='Wrap'; $text.Margin='0,5,0,7'; $text.Text=if ($box.IsChecked) { 'Local genre/vocal model ready. Import a song to detect.' } else { 'Run Setup-Detection.cmd once to enable local genre/vocal detection.' }; $ui.DetectionText=$text; $hostPanel.Children.Add($text) | Out-Null
    $row=New-Object Windows.Controls.WrapPanel
    $button=New-Object Windows.Controls.Button; $button.Content='Detect genre + vocals'; $button.FontSize=10; $button.Padding='10,5'; $button.Add_Click({ Start-SongDetection }); $ui.DetectSong=$button; $row.Children.Add($button) | Out-Null
    $apply=New-Object Windows.Controls.Button; $apply.Content='Apply detected settings'; $apply.FontSize=10; $apply.Padding='10,5'; $apply.IsEnabled=$false; $apply.Add_Click({ Apply-SongDetection }); $ui.ApplyDetection=$apply; $row.Children.Add($apply) | Out-Null
    $hostPanel.Children.Add($row) | Out-Null
    $ui.AnalyzeTrack.Add_Click({ Start-SongDetection })
}
