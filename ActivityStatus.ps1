function Initialize-ActivityStatus {
    $script:activityEntries=[Collections.Generic.List[string]]::new(); $script:footerKey=''; $script:footerStarted=[DateTime]::UtcNow
    $root=$window.Content; $row=New-Object Windows.Controls.RowDefinition; $row.Height='Auto'; $root.RowDefinitions.Add($row)
    $border=New-Object Windows.Controls.Border; $border.Background='#0D141F'; $border.BorderBrush='#234051'; $border.BorderThickness='0,1,0,0'; $border.Padding='19,10'; [Windows.Controls.Grid]::SetRow($border,2)
    $stack=New-Object Windows.Controls.StackPanel; $head=New-Object Windows.Controls.DockPanel
    $percent=New-Object Windows.Controls.TextBlock; $percent.Text='Ready'; $percent.Foreground='#1BD4EB'; $percent.FontSize=11; [Windows.Controls.DockPanel]::SetDock($percent,'Right'); $head.Children.Add($percent) | Out-Null; $ui.FooterPercent=$percent
    $title=New-Object Windows.Controls.TextBlock; $title.Text='Ready · import a song to begin'; $title.FontWeight='SemiBold'; $title.FontSize=12; $head.Children.Add($title) | Out-Null; $ui.FooterTask=$title; $stack.Children.Add($head) | Out-Null
    $bar=New-Object Windows.Controls.ProgressBar; $bar.Height=5; $bar.Minimum=0; $bar.Maximum=100; $bar.Foreground='#13CEE7'; $bar.Background='#243245'; $bar.Margin='0,8,0,6'; $ui.FooterProgress=$bar; $stack.Children.Add($bar) | Out-Null
    $detail=New-Object Windows.Controls.TextBlock; $detail.Text='Local audio engine is idle.'; $detail.Foreground='#8CA4BF'; $detail.FontSize=10; $detail.TextTrimming='CharacterEllipsis'; $ui.FooterDetail=$detail; $stack.Children.Add($detail) | Out-Null
    $expander=New-Object Windows.Controls.Expander; $expander.Header='Recent activity'; $expander.Margin='0,5,0,0'; $expander.FontSize=10
    $scroll=New-Object Windows.Controls.ScrollViewer; $scroll.Height=92; $scroll.VerticalScrollBarVisibility='Auto'; $log=New-Object Windows.Controls.TextBlock; $log.FontFamily='Consolas'; $log.FontSize=10; $log.Foreground='#8FA8C4'; $log.TextWrapping='Wrap'; $scroll.Content=$log; $expander.Content=$scroll; $ui.ActivityLog=$log; $stack.Children.Add($expander) | Out-Null
    $border.Child=$stack; $root.Children.Add($border) | Out-Null
}
function Get-AudioProgress([string]$progressPath,[string]$logPath,[double]$limit=0) {
    if (!$progressPath -or !(Test-Path -LiteralPath $progressPath)) { return -1 }
    try {
        $progress=(Get-Content -LiteralPath $progressPath -Tail 25 -ErrorAction Stop) -join "`n"
        $time=[regex]::Matches($progress,'out_time_us=(\d+)'); if (!$time.Count) { return -1 }
        $duration=0.0
        if ($logPath -and (Test-Path -LiteralPath $logPath)) {
            $match=[regex]::Match((Get-Content -LiteralPath $logPath -TotalCount 35 -ErrorAction Stop) -join "`n",'Duration:\s*(\d{2}:\d{2}:\d{2}\.\d+)')
            if ($match.Success) { $duration=[TimeSpan]::Parse($match.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture).TotalSeconds }
        }
        if ($limit -gt 0) { $duration=if ($duration -gt 0) { [math]::Min($duration,$limit) } else { $limit } }
        if ($duration -le 0) { return -1 }
        return [math]::Max(0,[math]::Min(1,([double]$time[$time.Count-1].Groups[1].Value/1000000/$duration)))
    } catch { return -1 }
}
function Update-ActivityStatus {
    if (!$ui.FooterTask) { return }
    $fraction=-1.0; $value=$ui.FooterProgress.Value; $active=$false
    if ($script:busy) {
        $active=$true; $key='master|'+$script:trackNumber+'|'+$script:phase
        $task=$ui.Stage.Text; $detail=$ui.Status.Text
        $limit=if ($script:phase -eq 'reference-profile') { 60 } else { 0 }
        $fraction=Get-AudioProgress $script:engineProgress $script:log $limit
        $referencePass=if ($script:reference -and $script:settings.Match -gt 0) { 1 } else { 0 }
        $passes=if ($script:exportType -in @('mp3','both')) { 6 } else { 4 }
        $units=$script:total*$passes+$referencePass
        $offset=if ($script:phase -eq 'reference-profile') { 0 } else { $referencePass+([math]::Max(0,$script:trackNumber-1)*$passes)+@{'source-profile'=0;'measure'=1;'render'=2;'verify'=3;'encode-mp3'=4;'verify-mp3'=5}[$script:phase] }
        $value=100*($offset+[math]::Max(0,$fraction))/[math]::Max(1,$units)
        if ($script:trackNumber -gt 0) { $detail="Song $script:trackNumber/$script:total · $([IO.Path]::GetFileName($script:source)) · $detail" }
    } elseif ($script:analysisProcess) {
        $active=$true; $key='analysis|'+$script:analysisPath; $task='Analyzing imported song'; $detail=$ui.AnalysisText.Text
        $fraction=Get-AudioProgress (Join-Path $script:analysisTemp 'progress.txt') $script:analysisLog
        $value=100*[math]::Max(0,$fraction)
    } elseif ($script:waveProcess) {
        $active=$true; $key='wave|'+$script:waveKey; $task='Drawing audio waveform'; $detail=$ui.WaveStatus.Text
    } elseif ($script:footerKey -like 'analysis|*' -or $script:footerKey -like 'wave|*' -or ($script:footerKey -like 'analysis-finished|*' -and $ui.Stage.Text -eq 'Ready to master')) {
        $key='analysis-finished|'+$script:source; $task=if ($script:analysisResult) { 'Analysis complete' } else { 'Background processing finished' }; $detail=$ui.AnalysisText.Text; $value=if ($script:analysisResult) { 100 } else { 0 }
    } else {
        $task=$ui.Stage.Text; $detail=$ui.Status.Text; $key='idle|'+$task+'|'+$detail
        if ($ui.Progress.Value -eq 100) { $value=100 }
        elseif ($task -eq 'Ready to master' -or !$script:source) { $value=0 }
    }
    if ($key -ne $script:footerKey) {
        $script:footerKey=$key
        $stamp=[TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow,'Pacific Standard Time').ToString('HH:mm:ss')
        $script:activityEntries.Add("[$stamp] $task · $detail")
        while ($script:activityEntries.Count -gt 40) { $script:activityEntries.RemoveAt(0) }
        $ui.ActivityLog.Text=($script:activityEntries.ToArray() | Select-Object -Last 15) -join "`n"
    }
    $ui.FooterTask.Text=$task; $ui.FooterDetail.Text=$detail
    $ui.FooterProgress.IsIndeterminate=$active -and $fraction -lt 0
    $ui.FooterProgress.Value=[math]::Min(100,[math]::Max(0,$value))
    $ui.FooterPercent.Text=if ($active -and $fraction -lt 0) { 'Working…' } elseif ($active) { ('{0:0}% · estimated overall' -f $value) } elseif ($value -ge 100) { 'Complete' } else { 'Idle' }
}
