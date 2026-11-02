function Get-ExportPaths([string]$path,[string]$kind) {
    if ($kind -eq 'both') { return @([IO.Path]::ChangeExtension($path,'.wav'),[IO.Path]::ChangeExtension($path,'.mp3')) }
    return @([IO.Path]::ChangeExtension($path,('.'+$kind)))
}
function Initialize-ExportFormats {
    $label=New-Object Windows.Controls.TextBlock; $label.Text='EXPORT FORMAT'; $label.Foreground=(Get-AppBrush '#7D96B2'); $label.FontSize=9; $label.Margin='0,14,0,0'
    $combo=New-Object Windows.Controls.ComboBox; foreach ($name in @('WAV (lossless)','MP3 (320 kbps)','Both WAV + MP3')) { $combo.Items.Add($name) | Out-Null }; $combo.SelectedIndex=0; $ui.ExportType=$combo
    $ui.TargetControl.Parent.Children.Add($label) | Out-Null; $ui.TargetControl.Parent.Children.Add($combo) | Out-Null
}
function Start-Mp3Encoding {
    $script:phase='encode-mp3'; $ui.Stage.Text='Encoding MP3'; $ui.Status.Text='Creating a 320 kbps MP3 from the verified PCM master.'
    $script:log=Join-Path $script:temp 'encode-mp3.log'; $script:engineProgress=Join-Path $script:temp 'encode-progress.txt'; $script:mp3Rendered=Join-Path $script:temp 'master.mp3'
    $argsText='-hide_banner -nostdin -nostats -y -stats_period 0.5 -progress "'+$script:engineProgress+'" -i "'+$script:rendered+'" -map 0:a:0 -vn -c:a libmp3lame -b:a 320k -id3v2_version 3 "'+$script:mp3Rendered+'"'
    $script:process=Start-Process -FilePath $script:ffmpeg -ArgumentList $argsText -WindowStyle Hidden -RedirectStandardError $script:log -PassThru; $null=$script:process.Handle; Update-ActivityStatus
}
function Complete-Export {
    $paths=@(Get-ExportPaths $script:current.Destination $script:exportType)
    if ($script:exportType -in @('wav','both')) { Copy-Item -LiteralPath $script:rendered -Destination $paths[0] -Force }
    if ($script:exportType -in @('mp3','both')) { Copy-Item -LiteralPath $script:mp3Rendered -Destination $paths[$paths.Count-1] -Force }
    $script:output=$paths[0]; $script:report.ExportedFiles=$paths; $script:report.ExportType=$script:exportType
    $script:completed+=,[pscustomobject]$script:report
    $m=$script:report.OutputMeasurement
    $ui.OutputMeter.Text="$($m.input_i) LUFS"; $ui.PeakMeter.Text="$($m.input_tp) dBTP"; $ui.RangeMeter.Text="$($m.input_lra) LU"
    $ui.Advice.Text=$script:report.Advice
    if ($script:exportType -ne 'wav') { $ui.Advice.Text+="`n`nMP3 is lossy and can have higher decoded peaks. The report includes measurements of the encoded MP3." }
    $ui.MatchInfo.Text=if ($script:referenceBands) { 'Reference corrections: '+(($script:gains | ForEach-Object { (Format-Number $_)+' dB' }) -join ', ') } else { 'Reference matching was off for this export.' }
    if ($script:jobs.Count -gt 0) { Start-NextSong } else {
        Set-Busy $false; $ui.Progress.Value=100; $ui.Mastered.IsEnabled=$true; $ui.SaveReport.IsEnabled=$true; $ui.Folder.IsEnabled=$true
        $ui.Stage.Text=if ($script:total -gt 1) { "$script:total masters exported" } else { 'Your Suno master is ready' }
        $ui.Status.Text='Export complete: '+$script:exportType.ToUpperInvariant()+'. Compare original and master at matched loudness.'
        Clear-Session
    }
}
