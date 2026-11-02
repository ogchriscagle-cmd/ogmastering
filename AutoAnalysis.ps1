function Get-AdaptiveSettings($base,$m,[double[]]$bands) {
    $s=Test-Settings $base
    if ($bands[1]-$bands[2] -gt 7) { $s.Mud=[math]::Max($s.Mud,1.5) }
    if ($bands[4]-$bands[3] -gt 2) { $s.Harsh=[math]::Max($s.Harsh,1.5); $s.DeEss=[math]::Max($s.DeEss,20) }
    if ([double]::Parse($m.input_lra,[Globalization.CultureInfo]::InvariantCulture) -lt 3) { $s.Glue=0 }
    return $s
}
function Stop-AutoAnalysis {
    if ($script:analysisProcess) { if (!$script:analysisProcess.HasExited) { $script:analysisProcess.Kill(); $script:analysisProcess.WaitForExit() }; $script:analysisProcess.Dispose(); $script:analysisProcess=$null }
    if ($script:analysisTemp) {
        $full=[IO.Path]::GetFullPath($script:analysisTemp); $base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
        if ($full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($full).StartsWith('OGAnalysis-') -and (Test-Path -LiteralPath $full)) { Remove-Item -LiteralPath $full -Recurse -Force }
    }
    $script:analysisTemp=$null
}
function Start-AutoAnalysis {
    Stop-SongDetection; $script:detectionResult=$null; if ($ui.ApplyDetection) { $ui.ApplyDetection.IsEnabled=$false }
    Stop-AutoAnalysis; $script:analysisResult=$null; $ui.ApplyAnalysis.IsEnabled=$false
    if (!$script:source -or $script:busy) { return }
    if (!(Test-Path -LiteralPath $script:ffmpeg)) { $ui.AnalysisText.Text='Run Setup.cmd to install the analysis engine.'; return }
    $script:analysisPath=$script:source; $s=Get-Settings; $script:analysisSignature=$s | ConvertTo-Json -Compress
    $script:analysisTemp=Join-Path ([IO.Path]::GetTempPath()) ('OGAnalysis-'+[guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $script:analysisTemp | Out-Null
    $script:analysisLog=Join-Path $script:analysisTemp 'analysis.log'
    $argsText='-hide_banner -nostdin -nostats -stats_period 0.5 -progress "'+(Join-Path $script:analysisTemp 'progress.txt')+'" -i "'+$script:source+'" -filter_complex "'+(Get-ProfileGraph $s)+'" -map "[main]" -vn -f null NUL'
    try {
        $script:analysisProcess=Start-Process -FilePath $script:ffmpeg -ArgumentList $argsText -WindowStyle Hidden -RedirectStandardError $script:analysisLog -PassThru; $null=$script:analysisProcess.Handle
        $ui.AnalysisText.Text='Analyzing loudness, peaks, dynamics and frequency balance…'
    } catch { $ui.AnalysisText.Text='Analysis could not start: '+$_.Exception.Message; Stop-AutoAnalysis }
}
function Apply-AnalysisSettings {
    if ($script:busy -or !$script:analysisResult -or $script:analysisResult.Path -ne $script:source) { return }
    Set-Settings (Get-AdaptiveSettings (Get-Settings) $script:analysisResult.Measurement $script:analysisResult.Bands)
    $ui.Status.Text='Conservative cleanup applied. Your loudness target, manual EQ and chosen genre were kept. Export to hear the result.'
}
function Invoke-AutoAnalysisTick {
    if (!$script:analysisProcess -or !$script:analysisProcess.HasExited) { return }
    try {
        if ($script:analysisProcess.ExitCode -ne 0) { throw 'Could not decode this song.' }
        $log=Get-Content -LiteralPath $script:analysisLog -Raw; $m=Read-Measurement $log
        if ($m.input_i -notmatch '^-?\d+(\.\d+)?$') { throw 'The song is silent or cannot be measured.' }
        $bands=Read-Bands $log; $script:analysisResult=@{Path=$script:analysisPath;Measurement=$m;Bands=$bands}
        $duration=[regex]::Match($log,'Duration:\s*(\d{2}:\d{2}:\d{2}\.\d+)')
        $script:analysisResult.Duration=if ($duration.Success) { [TimeSpan]::Parse($duration.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture).TotalSeconds } else { 10 }
        if ($script:source -ne $script:analysisPath -or $script:busy) { return }
        $ui.InputMeter.Text="$($m.input_i) LUFS"
        $genre=[regex]::Match($log,'(?im)^\s*genre\s*:\s*(.+)$')
        $genreInfo=if ($genre.Success) { 'Genre tag: '+$genre.Groups[1].Value.Trim()+' (file metadata).' } else { 'Genre uncertain: use Suno Optimized or choose manually.' }
        $tone=if ($bands[1]-$bands[2] -gt 7) { 'Prominent low-mid energy.' } elseif ($bands[4]-$bands[3] -gt 2) { 'Prominent upper-frequency energy.' } else { 'No strong broad-band tonal imbalance detected.' }
        $ui.AnalysisText.Text="Original: $($m.input_i) LUFS | peak $($m.input_tp) dBTP | range $($m.input_lra) LU.`n$tone $genreInfo"
        $ui.ApplyAnalysis.IsEnabled=$true
        if ($ui.AutoTune.IsChecked -and ((Get-Settings | ConvertTo-Json -Compress) -eq $script:analysisSignature)) { Apply-AnalysisSettings }
        elseif ($ui.AutoTune.IsChecked) { $ui.AnalysisText.Text+="`nYour edits were kept. Use Apply to accept suggestions." }
        if ($ui.AutoDetect -and $ui.AutoDetect.IsChecked) { Start-SongDetection }
    } catch { $ui.AnalysisText.Text='Analysis unavailable: '+$_.Exception.Message; $ui.ApplyAnalysis.IsEnabled=$false }
    finally { Stop-AutoAnalysis }
}
function Initialize-AutoAnalysis {
    $script:analysisProcess=$null; $script:analysisTemp=$null; $script:analysisResult=$null
    $border=New-Object Windows.Controls.Border; $border.Background=(Get-AppBrush '#0C1720'); $border.BorderBrush=(Get-AppBrush '#1C3A4B'); $border.BorderThickness='1'; $border.CornerRadius='12'; $border.Padding='13'; $border.Margin='0,0,0,14'
    $stack=New-Object Windows.Controls.StackPanel
    $text=New-Object Windows.Controls.TextBlock; $text.Text='AUTO ANALYSIS · import a song for measurements and cleanup suggestions.'; $text.Foreground=(Get-AppBrush '#90ABC7'); $text.FontSize=11; $text.TextWrapping='Wrap'; $text.Margin='0,0,0,9'; $stack.Children.Add($text) | Out-Null; $ui.AnalysisText=$text
    $row=New-Object Windows.Controls.WrapPanel
    $auto=New-Object Windows.Controls.CheckBox; $auto.Content='Auto-tune conservative cleanup'; $auto.IsChecked=$true; $auto.Margin='0,6,15,4'; $ui.AutoTune=$auto; $row.Children.Add($auto) | Out-Null
    foreach ($spec in @(@('ApplyAnalysis','Apply suggestions'),@('Reanalyze','Re-analyze'))) { $button=New-Object Windows.Controls.Button; $button.Content=$spec[1]; $button.Padding='10,4'; $button.FontSize=10; $ui[$spec[0]]=$button; $row.Children.Add($button) | Out-Null }
    $ui.ApplyAnalysis.IsEnabled=$false; $ui.ApplyAnalysis.Add_Click({ Apply-AnalysisSettings }); $ui.Reanalyze.Add_Click({ Start-AutoAnalysis })
    $stack.Children.Add($row) | Out-Null; $border.Child=$stack; $ui.GenreInfo.Parent.Children.Insert(1,$border)
}
