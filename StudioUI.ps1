function Update-Knob($slider) {
    $t=$slider.Tag; $ratio=($slider.Value-$slider.Minimum)/($slider.Maximum-$slider.Minimum)
    $angle=(135+270*$ratio)*[math]::PI/180
    $x=39+27*[math]::Cos($angle); $y=39+27*[math]::Sin($angle)
    $large=if ($ratio -gt (2.0/3)) { 1 } else { 0 }
    $d='M '+(Format-Number (39+27*[math]::Cos(135*[math]::PI/180)))+','+(Format-Number (39+27*[math]::Sin(135*[math]::PI/180)))+' A 27,27 0 '+$large+' 1 '+(Format-Number $x)+','+(Format-Number $y)
    $t.Arc.Data=[Windows.Media.Geometry]::Parse($d)
    $t.Needle.X2=39+19*[math]::Cos($angle); $t.Needle.Y2=39+19*[math]::Sin($angle)
    $t.Value.Text=('{0:0.##}{1}' -f $slider.Value,$t.Unit)
}
function Add-Knob([string]$panel,[string]$key,[string]$title,[double]$min,[double]$max,[double]$step,[string]$unit,[string]$color) {
    $grid=New-Object Windows.Controls.Grid; $grid.ToolTip="$title · drag left/right, scroll, or use arrow keys"; $grid.Margin='0,0,0,5'
    foreach ($height in @(68,18,14)) { $row=New-Object Windows.Controls.RowDefinition; $row.Height=$height; $grid.RowDefinitions.Add($row) }
    $canvas=New-Object Windows.Controls.Canvas; $canvas.Width=78; $canvas.Height=78; $canvas.HorizontalAlignment='Center'; $canvas.Margin='0,-5,0,0'
    $circle=New-Object Windows.Shapes.Ellipse; $circle.Width=54; $circle.Height=54; $circle.Stroke=(Get-AppBrush '#242633'); $circle.StrokeThickness=4; $circle.Fill=(Get-AppBrush '#0C0E16'); [Windows.Controls.Canvas]::SetLeft($circle,12); [Windows.Controls.Canvas]::SetTop($circle,12); $canvas.Children.Add($circle) | Out-Null
    $arc=New-Object Windows.Shapes.Path; $arc.Stroke=(Get-AppBrush $color); $arc.StrokeThickness=3.5; $arc.StrokeStartLineCap='Round'; $arc.StrokeEndLineCap='Round'; $canvas.Children.Add($arc) | Out-Null
    $needle=New-Object Windows.Shapes.Line; $needle.X1=39; $needle.Y1=39; $needle.Stroke=(Get-AppBrush $color); $needle.StrokeThickness=3; $needle.StrokeEndLineCap='Round'; $canvas.Children.Add($needle) | Out-Null
    $dot=New-Object Windows.Shapes.Ellipse; $dot.Width=7; $dot.Height=7; $dot.Fill=(Get-AppBrush $color); [Windows.Controls.Canvas]::SetLeft($dot,35.5); [Windows.Controls.Canvas]::SetTop($dot,35.5); $canvas.Children.Add($dot) | Out-Null
    $value=New-Object Windows.Controls.TextBlock; $value.HorizontalAlignment='Center'; $value.FontSize=11; $value.FontWeight='Bold'; $value.Foreground=(Get-AppBrush $color); [Windows.Controls.Grid]::SetRow($value,1)
    $label=New-Object Windows.Controls.TextBlock; $label.Text=$title.ToUpperInvariant(); $label.HorizontalAlignment='Center'; $label.FontSize=8; [Windows.Controls.Grid]::SetRow($label,2)
    $slider=New-Object Windows.Controls.Slider; $slider.Minimum=$min; $slider.Maximum=$max; $slider.TickFrequency=$step; $slider.SmallChange=$step; $slider.LargeChange=$step*5; $slider.Opacity=0; $slider.Margin='0'; $slider.Cursor='SizeWE'; $slider.IsMoveToPointEnabled=$true; $slider.HorizontalAlignment='Center'; $slider.Width=76
    [Windows.Automation.AutomationProperties]::SetName($slider,$title)
    $slider.Tag=@{Arc=$arc;Needle=$needle;Value=$value;Unit=$unit}
    $slider.Add_ValueChanged({ Update-Knob $this })
    $slider.Add_PreviewMouseWheel({ $this.Value=[math]::Max($this.Minimum,[math]::Min($this.Maximum,$this.Value+[math]::Sign($_.Delta)*$this.TickFrequency)); $_.Handled=$true })
    foreach ($child in @($canvas,$value,$label,$slider)) { $grid.Children.Add($child) | Out-Null }
    $ui[$panel].Children.Add($grid) | Out-Null; $ui[$key]=$slider; $script:sliderKeys+=$key
    Update-Knob $slider
}
function Stop-Waveform {
    if ($script:waveProcess) { if (!$script:waveProcess.HasExited) { $script:waveProcess.Kill(); $script:waveProcess.WaitForExit() }; $script:waveProcess.Dispose(); $script:waveProcess=$null }
    if ($script:waveTemp -and (Test-Path -LiteralPath $script:waveTemp)) {
        $full=[IO.Path]::GetFullPath($script:waveTemp); $base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
        if ($full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($full).StartsWith('OGWave-')) { Remove-Item -LiteralPath $full -Recurse -Force }
    }
    $script:waveTemp=$null
}
function Start-Waveform([string]$path,[string]$version='original') {
    Stop-Waveform
    $ui.WaveVersion.Text=$version.ToUpperInvariant(); $ui.WaveImage.Source=$null
    if (!$path -or !(Test-Path -LiteralPath $path) -or !(Test-Path -LiteralPath $script:ffmpeg)) { return }
    $script:waveKey=$path+'|'+(Get-Item -LiteralPath $path).LastWriteTimeUtc.Ticks
    $script:waveDuration=0
    if ($script:waveCache.ContainsKey($script:waveKey)) { $cached=$script:waveCache[$script:waveKey]; $ui.WaveImage.Source=$cached.Image; $script:waveDuration=$cached.Duration; $ui.TrackInfo.Text=$cached.Info; $ui.WaveStatus.Text='Click waveform to seek · overview up to 30 min'; return }
    $script:waveTemp=Join-Path ([IO.Path]::GetTempPath()) ('OGWave-'+[guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $script:waveTemp | Out-Null
    $script:wavePng=Join-Path $script:waveTemp 'wave.png'
    $argsText='-hide_banner -nostdin -y -t 1800 -i "'+$path+'" -filter_complex "aformat=channel_layouts=mono,showwavespic=s=1800x240:colors=0x445370:scale=sqrt:draw=full" -frames:v 1 -an "'+$script:wavePng+'"'
    $script:waveProcess=Start-Process -FilePath $script:ffmpeg -ArgumentList $argsText -WindowStyle Hidden -RedirectStandardError (Join-Path $script:waveTemp 'wave.log') -PassThru; $null=$script:waveProcess.Handle
    $ui.WaveStatus.Text='Drawing waveform from audio…'
}
function Invoke-WaveTick {
    if ($script:waveProcess -and $script:waveProcess.HasExited) {
        try {
            if ($script:waveProcess.ExitCode -ne 0 -or !(Test-Path -LiteralPath $script:wavePng)) { throw 'Waveform preview unavailable' }
            $bitmap=New-Object Windows.Media.Imaging.BitmapImage; $bitmap.BeginInit(); $bitmap.CacheOption='OnLoad'; $bitmap.UriSource=[uri]$script:wavePng; $bitmap.EndInit(); $bitmap.Freeze()
            $ui.WaveImage.Source=$bitmap
            $metadata=Get-Content -LiteralPath (Join-Path $script:waveTemp 'wave.log') -Raw
            $duration=[regex]::Match($metadata,'Duration:\s*(\d{2}:\d{2}:\d{2}\.\d+)')
            $audio=[regex]::Match($metadata,'Audio:.*?,\s*(\d+) Hz,\s*([^,\r\n]+)')
            if ($duration.Success) {
                $seconds=[TimeSpan]::Parse($duration.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture).TotalSeconds
                $script:waveDuration=[math]::Min(1800,$seconds)
                if ($audio.Success) { $ui.TrackInfo.Text=('{0:mm\:ss} · {1} Hz · {2}' -f [TimeSpan]::FromSeconds($seconds),$audio.Groups[1].Value,$audio.Groups[2].Value) }
            }
            if ($script:waveCache.Count -ge 6) { $script:waveCache.Clear() }
            $script:waveCache[$script:waveKey]=@{Image=$bitmap;Duration=$script:waveDuration;Info=$ui.TrackInfo.Text}
            $ui.WaveStatus.Text='Click waveform to seek · overview up to 30 min'
        } catch { $ui.WaveStatus.Text='Waveform preview unavailable; audio export is still available' } finally { Stop-Waveform }
    }
    if ($ui.Seek.Maximum -gt 1 -and $ui.WaveHost.ActualWidth -gt 0) {
        $duration=if ($script:waveDuration -gt 0) { $script:waveDuration } else { $ui.Seek.Maximum }
        $ui.Playhead.Margin=[Windows.Thickness]::new([math]::Min(1,$ui.Seek.Value/$duration)*[math]::Max(0,$ui.WaveHost.ActualWidth-1),0,0,0)
    }
}
function Select-StudioMode([string]$mode) {
    $script:importMode=$mode
    foreach ($key in @('SingleMode','BulkMode','PresetsMode')) { $ui[$key].Background=(Get-AppBrush '#10151E'); $ui[$key].BorderBrush=(Get-AppBrush '#26303A') }
    $key= switch ($mode) { 'bulk' {'BulkMode'} 'presets' {'PresetsMode'} default {'SingleMode'} }
    $ui[$key].Background=(Get-AppBrush '#103346'); $ui[$key].BorderBrush=(Get-AppBrush '#0AA9C6')
    if ($mode -eq 'presets') { $ui.PresetPanel.IsExpanded=$true; $ui.PresetPanel.BringIntoView() }
    $ui.Import.Content=if ($mode -eq 'bulk') { '+  Choose songs' } else { '+  Choose song' }
}
function Set-Style([string]$style) {
    if ($script:busy) { return }
    $s=Get-Settings
    # Each style changes a small, audible set of existing DSP parameters.
    switch ($style) {
        'Warm' { $s.Bass=1.5; $s.Air=-1; $s.Excite=0; $s.Harsh=1.5 }
        'Bright' { $s.Air=1.5; $s.Bass=0; $s.Excite=10; $s.Harsh=1 }
        'Punchy' { $s.Glue=20; $s.Bass=1; $s.Mud=1.5; $s.Excite=0 }
        'Transparent' { $s.Bass=0; $s.Air=0; $s.Glue=0; $s.Excite=0; $s.Width=1 }
        'Vintage' { $s.Bass=1; $s.Air=-1.5; $s.Glue=15; $s.Excite=10 }
        'Modern' { $s.Air=1; $s.Mud=1.5; $s.Glue=15; $s.Width=1.1 }
    }
    Set-Settings $s
    foreach ($button in $ui.StyleButtons.Children) { $button.Background=(Get-AppBrush '#14151F'); $button.BorderBrush=(Get-AppBrush '#262733'); if ($button.Content -eq $style) { $button.Background=(Get-AppBrush '#0B303C'); $button.BorderBrush=(Get-AppBrush '#079FB8') } }
    $ui.Status.Text="$style style applied. Master again to hear changed settings."
}
function Initialize-StudioUX {
    $script:waveProcess=$null; $script:waveTemp=$null; $script:waveCache=@{}; $script:importMode='single'
    foreach ($name in @('Warm','Bright','Punchy','Transparent','Vintage','Modern')) {
        $button=New-Object Windows.Controls.Button; $button.Content=$name; $button.FontSize=10; $button.Margin='0,0,5,5'; $button.Padding='6,7'; $button.Add_Click({ Set-Style ([string]$this.Content) }); $ui.StyleButtons.Children.Add($button) | Out-Null
    }
    $ui.SingleMode.Add_Click({ if (!$script:busy) { Select-StudioMode 'single' } })
    $ui.BulkMode.Add_Click({ if (!$script:busy) { Select-StudioMode 'bulk' } })
    $ui.PresetsMode.Add_Click({ if (!$script:busy) { Select-StudioMode 'presets' } })
    $ui.VocalsType.Add_Click({ if (!$script:busy) { $ui.DeEss.Value=20; $ui.Status.Text='Vocal starting point: gentle de-essing enabled. Adjust it by ear.' } })
    $ui.InstrumentalType.Add_Click({ if (!$script:busy) { $ui.DeEss.Value=0; $ui.Status.Text='Instrumental starting point: de-essing is off.' } })
    $ui.ResetQuick.Add_Click({ if (!$script:busy) { Set-Settings (Get-CatalogGenreSettings ([math]::Max(0,$ui.Preset.SelectedIndex))); foreach ($button in $ui.StyleButtons.Children) { $button.Background=(Get-AppBrush '#14151F'); $button.BorderBrush=(Get-AppBrush '#262733') } } })
    $ui.WaveHost.Add_MouseLeftButtonDown({ if ($script:playing -and $ui.Seek.Maximum -gt 1) { $duration=if ($script:waveDuration -gt 0) { $script:waveDuration } else { $ui.Seek.Maximum }; $ui.Seek.Value=($_.GetPosition($ui.WaveHost).X/[math]::Max(1,$ui.WaveHost.ActualWidth))*$duration } })
    $window.Add_PreviewKeyDown({
        if ($_.OriginalSource -is [Windows.Controls.Primitives.TextBoxBase] -or $_.OriginalSource -is [Windows.Controls.Primitives.RangeBase] -or $_.OriginalSource -is [Windows.Controls.ComboBox]) { return }
        switch ($_.Key) { 'A' { Play-Version 'original'; $_.Handled=$true } 'B' { Play-Version 'master'; $_.Handled=$true } 'Space' { $player.Stop(); $_.Handled=$true } }
    })
}
