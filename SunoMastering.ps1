Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AudioEngine.ps1')
. (Join-Path $PSScriptRoot 'GenreCatalog.ps1')
$script:ffmpeg = Join-Path $PSScriptRoot 'bin\ffmpeg.exe'
if (!(Test-Path -LiteralPath $script:ffmpeg)) { $found = Get-Command ffmpeg -ErrorAction SilentlyContinue; if ($found) { $script:ffmpeg = $found.Source } }
[xml]$xaml = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Studio.xaml') -Raw -Encoding UTF8
$script:window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$script:ui = @{}
foreach ($match in [regex]::Matches($xaml.OuterXml, 'x:Name="([^"]+)"')) { $name=$match.Groups[1].Value; $ui[$name]=$window.FindName($name) }
$script:sliderKeys = @(); $script:checkKeys = @()
. (Join-Path $PSScriptRoot 'StudioUI.ps1')
. (Join-Path $PSScriptRoot 'AdvancedUI.ps1')
. (Join-Path $PSScriptRoot 'InterfaceModes.ps1')
. (Join-Path $PSScriptRoot 'AutoAnalysis.ps1')
. (Join-Path $PSScriptRoot 'ActivityStatus.ps1')
. (Join-Path $PSScriptRoot 'ExportFormats.ps1')
Initialize-GenreMenu
function Add-Note([string]$panel, [string]$text) {
    $item = New-Object Windows.Controls.TextBlock; $item.Text=$text; $item.TextWrapping='Wrap'; $item.Foreground='#91A5C0'; $item.FontSize=11; $item.Margin='0,0,0,14'; $ui[$panel].Children.Add($item) | Out-Null
}
function Add-Control([string]$panel, [string]$key, [string]$title, [double]$min, [double]$max, [double]$step, [string]$unit='') {
    $quick = @{ Bass=@('Bass','#FFAC06'); Excite=@('Harmonics','#FF4E58'); Harsh=@('Smoothness','#FF963B'); Air=@('Brightness','#0DD3EF'); Mud=@('Clarity','#20D5A3'); Glue=@('Glue','#C37DFF'); Width=@('Width','#A58AFF'); DeEss=@('De-esser','#629DFF'); Match=@('Ref match','#25DBB4') }
    if ($key -eq 'Loudness') { Add-Knob TargetControl $key 'Custom' $min $max $step $unit '#12D4EF'; return }
    if ($quick.ContainsKey($key)) { $q=$quick[$key]; Add-Knob QuickControls $key $q[0] $min $max $step $unit $q[1]; return }
    $label = New-Object Windows.Controls.TextBlock
    $slider = New-Object Windows.Controls.Slider; $slider.Minimum=$min; $slider.Maximum=$max; $slider.TickFrequency=$step
    $slider.Tag = @{ Label=$label; Title=$title; Unit=$unit }
    $slider.Add_ValueChanged({ $t=$this.Tag; $t.Label.Text = '{0}   {1:0.##}{2}' -f $t.Title,$this.Value,$t.Unit })
    $ui[$panel].Children.Add($label) | Out-Null; $ui[$panel].Children.Add($slider) | Out-Null
    $ui[$key]=$slider; $label.Text="$title   0$unit"; $script:sliderKeys += $key
}
function Add-Check([string]$panel, [string]$key, [string]$text) {
    $box = New-Object Windows.Controls.CheckBox; $box.Content=$text; $ui[$key]=$box; $ui[$panel].Children.Add($box) | Out-Null; $script:checkKeys += $key
}
Add-Note CleanupControls 'Start gently. Suno exports may already be heavily compressed. Source repair is optional and can change transients.'
Add-Check CleanupControls Repair 'Source repair / de-clip (slower)'
Add-Control CleanupControls DeEss 'De-esser' 0 100 5 '%'
Add-Control CleanupControls Mud 'Mud reduction · 280 Hz' 0 6 0.5 ' dB'
Add-Control CleanupControls Harsh 'Harshness reduction · 3.5 kHz' 0 6 0.5 ' dB'
Add-Control CleanupControls Glue 'Glue compression' 0 100 5 '%'
Add-Control CleanupControls Excite 'Harmonic exciter' 0 100 5 '%'
Add-Note CleanupControls 'The exciter adds harmonics; it does not recover missing detail. Use it sparingly on bright or metallic vocals.'
Add-Check CleanupControls MonoBass 'Reduce side-channel bass below 120 Hz'
Add-Control CleanupControls Width 'Stereo width · 1 = original' 0.5 1.5 0.05 '×'
Add-Note ToneControls 'Six fixed-frequency parametric bands (Q 0.8), shelving EQ, and separate mid/side tone controls.'
foreach ($i in 0..5) { Add-Control ToneControls ('Eq'+$i) ("EQ · $($script:EqFrequencies[$i]) Hz") -6 6 0.5 ' dB' }
Add-Control ToneControls Bass 'Low shelf · 120 Hz' -6 6 0.5 ' dB'
Add-Control ToneControls Air 'High shelf · 6.5 kHz' -6 6 0.5 ' dB'
Add-Control ToneControls MidPresence 'Mid presence · 2.5 kHz' -4 4 0.5 ' dB'
Add-Control ToneControls SideAir 'Side air · 6.5 kHz' -4 4 0.5 ' dB'
Add-Control ToneControls Match 'Reference tone match' 0 100 5 '%'
Add-Note ToneControls 'Reference analysis compares six broad bands in the first 60 seconds. It removes overall level differences and limits correction to ±3 dB at full strength. This is approximate tone matching, not a copy of another mastering engine.'
Add-Control OutputControls Loudness 'Target loudness' -20 -8 0.5 ' LUFS'
Add-Control OutputControls Ceiling 'True-peak ceiling' -3 -0.3 0.1 ' dBTP'
Add-Note OutputControls 'Two-pass EBU R128 normalization, an 8× oversampled safety limiter, triangular dither, and a separate measurement of the exported PCM.'
$format = New-Object Windows.Controls.ComboBox
$format.Items.Add('WAV · 24-bit · 48 kHz') | Out-Null; $format.Items.Add('WAV · 16-bit · 44.1 kHz') | Out-Null; $format.SelectedIndex=0; $ui.Format=$format; $ui.OutputControls.Children.Add($format) | Out-Null
Add-Note OutputControls '−14 LUFS is a useful starting point, not a requirement for every platform. A louder target can reduce dynamics. The final report shows what was actually achieved.'
Add-Note OutputControls 'Batch: select multiple songs, choose an export folder, and the same settings are applied to each song. Existing files receive a new numbered filename.'
$knobOrder=@('Bass','Excite','Harsh','Air','Mud','Glue','Width','DeEss','Match')
$knobViews=@{}; foreach ($key in $knobOrder) { $knobViews[$key]=$ui[$key].Parent }
$ui.QuickControls.Children.Clear(); foreach ($key in $knobOrder) { $ui.QuickControls.Children.Add($knobViews[$key]) | Out-Null }
Initialize-AdvancedControls
function Set-Settings($settings) {
    foreach ($button in $ui.StyleButtons.Children) { $button.Background='#14151F'; $button.BorderBrush='#262733' }
    foreach ($key in $script:sliderKeys) { $ui[$key].Value=[double]$settings[$key] }
    foreach ($key in $script:checkKeys) { $ui[$key].IsChecked=[bool]$settings[$key] }
    $ui.Format.SelectedIndex=[int]$settings.Format
    $script:genre=[string]$settings.Genre
    $ui.GenreInfo.Text='Genre: '+$script:genre+' · settings are editable'
}
function Get-Settings {
    $s=Get-DefaultSettings
    foreach ($key in $script:sliderKeys) { $s[$key]=$ui[$key].Value }
    foreach ($key in $script:checkKeys) { $s[$key]=[bool]$ui[$key].IsChecked }
    $s.Format=$ui.Format.SelectedIndex; $s.Genre=$script:genre
    return $s
}
Set-Settings (Get-CatalogGenreSettings 0)
$script:player = New-Object Windows.Media.MediaPlayer
$script:process=$null; $script:phase=''; $script:temp=$null; $script:sources=@(); $script:source=$null; $script:reference=$null; $script:output=$null; $script:report=$null; $script:busy=$false; $script:playing=''; $script:pendingSeek=0; $script:updatingSeek=$false
function Set-Busy([bool]$busy) {
    $script:busy=$busy
    foreach ($n in (@('Import','Reference','Preset','SavePreset','LoadPreset','Format','SimpleInterface','AdvancedInterface') + $script:sliderKeys + $script:checkKeys)) { if ($ui[$n]) { $ui[$n].IsEnabled=!$busy } }
    $ui.ClearReference.IsEnabled=!$busy -and !!$script:reference
    $ui.Render.IsEnabled=!$busy -and $script:sources.Count -gt 0
    $ui.Cancel.IsEnabled=$busy; $ui.Progress.IsIndeterminate=$busy
    $ui.Original.IsEnabled=!$busy -and !!$script:source
    foreach ($key in @('AutoTune','Reanalyze','ApplyAnalysis','AnalyzeTrack','ExportType')) { if ($ui[$key]) { $ui[$key].IsEnabled=!$busy -and ($key -ne 'ApplyAnalysis' -or !!$script:analysisResult) } }
}
function Clear-Session {
    # Only remove a directory created for this app under the OS temp directory.
    if ($script:temp) {
        $full=[IO.Path]::GetFullPath($script:temp); $base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        if ($full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($full).StartsWith('OGMastering-') -and (Test-Path -LiteralPath $full)) { Remove-Item -LiteralPath $full -Recurse -Force }
    }
    $script:temp=$null
}
function Import-Songs([string[]]$paths) {
    if ($script:busy) { return }
    $valid=@($paths | Where-Object { [IO.Path]::GetExtension($_).ToLowerInvariant() -in @('.wav','.mp3','.flac','.m4a','.aif','.aiff','.ogg') -and (Test-Path -LiteralPath $_ -PathType Leaf) } | ForEach-Object { [IO.Path]::GetFullPath($_) } | Select-Object -Unique)
    if (!$valid.Count) { throw 'Choose WAV, MP3, FLAC, M4A, AIFF, or OGG audio files.' }
    $script:sources=$valid; $script:source=$valid[0]; $player.Close(); $script:playing=''; $script:output=$null; $script:report=$null
    $ui.TrackName.Text=if ($valid.Count -gt 1) { "$($valid.Count) songs in the batch" } else { [IO.Path]::GetFileNameWithoutExtension($valid[0]) }
    $ui.TrackInfo.Text=($valid | ForEach-Object { [IO.Path]::GetFileName($_) }) -join ' · '
    $ui.Original.IsEnabled=$true; $ui.Mastered.IsEnabled=$false; $ui.Folder.IsEnabled=$false; $ui.SaveReport.IsEnabled=$false
    $ui.Stage.Text='Ready to master'; $ui.Status.Text='Choose your sound, then master and export.'
    $ui.InputMeter.Text='— LUFS'; $ui.OutputMeter.Text='— LUFS'; $ui.PeakMeter.Text='— dBTP'; $ui.RangeMeter.Text='— LU'; $ui.Progress.Value=0
    $ui.Advice.Text='Master this song to see fresh measurements and suggestions.'; $ui.MatchInfo.Text=''
    Start-Waveform $script:source 'original'
    Set-Busy $false
    Start-AutoAnalysis
}
function Start-Engine([string]$inputPath,[string]$filters,[string]$destination='', [bool]$complex=$false, [int]$limitSeconds=0) {
    $script:log=Join-Path $script:temp ('engine-'+$script:phase+'.log')
    $script:engineProgress=Join-Path $script:temp ('progress-'+$script:phase+'.txt')
    $argsText='-hide_banner -nostdin -nostats -y -stats_period 0.5 -progress "'+$script:engineProgress+'" '
    if ($limitSeconds -gt 0) { $argsText += "-t $limitSeconds " }
    $argsText += '-i "'+$inputPath+'" '
    if ($complex) { $argsText += '-filter_complex "'+$filters+'" -map "[main]" ' } else { $argsText += '-map 0:a:0 -af "'+$filters+'" ' }
    $argsText += '-vn '
    if (!$destination) { $argsText += '-f null NUL' } else { $argsText += '-ar '+$script:rate+' -c:a '+$script:codec+' "'+$destination+'"' }
    $script:process=Start-Process -FilePath $script:ffmpeg -ArgumentList $argsText -WindowStyle Hidden -RedirectStandardError $script:log -PassThru
    $null=$script:process.Handle
    Update-ActivityStatus
}
function Start-NextSong {
    $script:current=$script:jobs.Dequeue(); $script:source=$script:current.Source
    $script:trackNumber++
    Start-Waveform $script:source 'original'
    $ui.TrackName.Text=[IO.Path]::GetFileNameWithoutExtension($script:source)
    $ui.Stage.Text="Analyzing song $script:trackNumber of $script:total"
    $ui.Status.Text='Measuring original loudness, dynamics, and six frequency bands.'
    $ui.OutputMeter.Text='— LUFS'; $ui.PeakMeter.Text='— dBTP'; $ui.RangeMeter.Text='— LU'; $ui.Mastered.IsEnabled=$false
    $script:phase='source-profile'
    Start-Engine $script:source (Get-ProfileGraph $script:settings) '' $true
}
function Start-Mastering([object[]]$jobs) {
    if ($script:busy) { throw 'A mastering session is already running.' }
    if (!(Test-Path -LiteralPath $script:ffmpeg)) { throw 'FFmpeg is missing. Run Setup.cmd first.' }
    if (!$jobs.Count) { throw 'Choose at least one song.' }
    $destinations=@{}
    $script:exportType=@('wav','mp3','both')[$ui.ExportType.SelectedIndex]
    foreach ($job in $jobs) {
        foreach ($exportPath in @(Get-ExportPaths $job.Destination $script:exportType)) {
        $dest=[IO.Path]::GetFullPath($exportPath)
        foreach ($src in @($script:sources + @($script:reference))) { if ($src -and $dest -eq [IO.Path]::GetFullPath($src)) { throw 'An export cannot replace an input or reference song.' } }
        if ($destinations.ContainsKey($dest)) { throw 'Two songs have the same export path.' }; $destinations[$dest]=$true
        }
    }
    $script:settings=Get-Settings
    Stop-AutoAnalysis
    $script:baseSettings=Test-Settings $script:settings
    $script:autoTuneJob=[bool]$ui.AutoTune.IsChecked
    $script:jobs=[Collections.Generic.Queue[object]]::new(); foreach ($job in $jobs) { $script:jobs.Enqueue($job) }
    $script:total=$jobs.Count; $script:trackNumber=0; $script:completed=@(); $script:referenceBands=$null
    $script:temp=Join-Path ([IO.Path]::GetTempPath()) ('OGMastering-'+[guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $script:temp | Out-Null
    $script:rate=@(48000,44100)[[int]$script:settings.Format]; $script:codec=@('pcm_s24le','pcm_s16le')[[int]$script:settings.Format]
    $player.Close(); $script:playing=''; $script:report=$null; $ui.SaveReport.IsEnabled=$false; $ui.Mastered.IsEnabled=$false
    Set-Busy $true
    if ($script:reference -and $script:settings.Match -gt 0) {
        $script:phase='reference-profile'; $ui.Stage.Text='Analyzing your reference'; $ui.Status.Text='Measuring six broad frequency bands in the first 60 seconds.'
        Start-Engine $script:reference (Get-ProfileGraph $script:settings) '' $true 60
    } else { Start-NextSong }
}
function Update-PlaybackGain {
    $volume=1.0
    if ($ui.LevelMatch.IsChecked -and $script:report) {
        $culture=[Globalization.CultureInfo]::InvariantCulture
        $original=[double]::Parse($script:report.SourceMeasurement.input_i,$culture); $master=[double]::Parse($script:report.OutputMeasurement.input_i,$culture)
        $difference=if ($script:playing -eq 'master') { $original-$master } else { $master-$original }
        $volume=[math]::Min(1,[math]::Pow(10,$difference/20))
    }
    $player.Volume=$volume
}
function Play-Version([string]$version) {
    if ($script:busy) { return }
    $path=if ($version -eq 'master') { $script:output } else { $script:source }
    if (!$path -or !(Test-Path -LiteralPath $path)) { return }
    $script:pendingSeek=$player.Position.TotalSeconds; $script:playing=$version
    $player.Open([uri]$path); Update-PlaybackGain; $player.Play()
    Start-Waveform $path $version
    $ui.Original.Background=if ($version -eq 'original') { '#20222D' } else { '#101019' }
    $ui.Mastered.Background=if ($version -eq 'master') { '#103744' } else { '#101019' }
}
function Invoke-EngineTick {
    if (!$script:process -or !$script:process.HasExited) { return }
    try {
        $code=$script:process.ExitCode; $script:process.Dispose(); $script:process=$null
        $logText=Get-Content -LiteralPath $script:log -Raw
        if ($code -ne 0) { throw ('Audio processing failed: '+$logText.Substring([math]::Max(0,$logText.Length-1400))) }
        switch ($script:phase) {
            'reference-profile' { $script:referenceBands=Read-Bands $logText; Start-NextSong }
            'source-profile' {
                $script:raw=Read-Measurement $logText
                if ($script:raw.input_i -notmatch '^-?\d+(\.\d+)?$') { throw 'This song is silent or cannot be measured.' }
                $script:bands=Read-Bands $logText
                $ui.InputMeter.Text="$($script:raw.input_i) LUFS"
                $script:gains=@(0,0,0,0,0,0)
                if ($script:referenceBands) { $script:gains=Get-MatchGains $script:bands $script:referenceBands $script:settings.Match }
                $durationMatch=[regex]::Match($logText,'Duration:\s*(\d{2}:\d{2}:\d{2}\.\d+)')
                $sourceDuration=if ($durationMatch.Success) { [TimeSpan]::Parse($durationMatch.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture).TotalSeconds } else { 0 }
                $script:settings=Test-Settings $script:baseSettings
                if ($script:autoTuneJob) { $script:settings=Get-AdaptiveSettings $script:settings $script:raw $script:bands }
                $script:chain=Get-ProcessingChain $script:settings $script:gains $sourceDuration
                $script:phase='measure'; $ui.Stage.Text='Measuring the mastering chain'; $ui.Status.Text='Analyzing the processed signal before applying final loudness.'
                Start-Engine $script:source ($script:chain+','+(Get-Normalizer $script:settings))
            }
            'measure' {
                $script:processed=Read-Measurement $logText
                $norm=Get-Normalizer $script:settings $script:processed
                $script:phase='render'; $ui.Stage.Text='Rendering your master'; $ui.Status.Text='Applying the measured gain, 8× safety limiter, and output dither.'
                $script:rendered=Join-Path $script:temp 'master.wav'
                Start-Engine $script:source ($script:chain+','+$norm+','+(Get-Finalizer $script:settings)) $script:rendered
            }
            'render' {
                $script:phase='verify'; $ui.Stage.Text='Checking the exported PCM'; $ui.Status.Text='Measuring actual WAV loudness, true peak, and loudness range.'
                Start-Engine $script:rendered (Get-Normalizer $script:settings)
            }
            'verify' {
                $m=Read-Measurement $logText
                foreach ($key in @('input_i','input_tp','input_lra')) { if ($m.$key -notmatch '^-?\d+(\.\d+)?$') { throw 'The exported audio could not be measured. No export was replaced.' } }
                $script:report=[ordered]@{ App='OG Mastering / Suno Studio'; CreatedUtc=[DateTime]::UtcNow.ToString('o'); Source=$script:source; Reference=$script:reference; Destination=$script:current.Destination; Settings=$script:settings; SourceMeasurement=$script:raw; ProcessedMeasurement=$script:processed; OutputMeasurement=$m; SourceBandsDb=$script:bands; ReferenceGainsDb=$script:gains; Advice=(Get-Advice $script:raw $m $script:bands $script:settings) }
                if ($script:exportType -eq 'wav') { Complete-Export } else { Start-Mp3Encoding }
            }
            'encode-mp3' {
                $script:phase='verify-mp3'; $ui.Stage.Text='Checking encoded MP3'; $ui.Status.Text='Measuring decoded MP3 loudness and true peak.'
                Start-Engine $script:mp3Rendered (Get-Normalizer $script:settings)
            }
            'verify-mp3' {
                $m=Read-Measurement $logText
                foreach ($key in @('input_i','input_tp','input_lra')) { if ($m.$key -notmatch '^-?\d+(\.\d+)?$') { throw 'Encoded MP3 could not be measured.' } }
                $script:report.Mp3Measurement=$m
                if ($script:exportType -eq 'mp3') { $script:report.PcmMeasurement=$script:report.OutputMeasurement; $script:report.OutputMeasurement=$m; $script:report.Advice=Get-Advice $script:raw $m $script:bands $script:settings }
                Complete-Export
            }
        }
    } catch {
        $script:process=$null; Set-Busy $false; $ui.Stage.Text='Mastering stopped'
        $ui.Status.Text=$_.Exception.Message+" Completed exports: $($script:completed.Count)."
        if ($script:completed.Count) { $ui.SaveReport.IsEnabled=$true }
        Clear-Session
    }
}
function Stop-Mastering {
    if ($script:process) { $script:process.Kill(); $script:process.WaitForExit(); $script:process.Dispose(); $script:process=$null }
    Set-Busy $false; $ui.Stage.Text='Cancelled'; $ui.Status.Text="Completed exports: $($script:completed.Count). The current unfinished export was not saved."; $ui.SaveReport.IsEnabled=$script:completed.Count -gt 0; Clear-Session
}
$ui.Import.Add_Click({ try { $d=New-Object Microsoft.Win32.OpenFileDialog; $d.Filter='Audio|*.wav;*.mp3;*.flac;*.m4a;*.aif;*.aiff;*.ogg'; $d.Multiselect=($script:importMode -eq 'bulk'); if ($d.ShowDialog()) { Import-Songs $d.FileNames } } catch { [Windows.MessageBox]::Show($_.Exception.Message) | Out-Null } })
$window.Add_DragOver({ $_.Effects=if (!$script:busy -and $_.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) { [Windows.DragDropEffects]::Copy } else { [Windows.DragDropEffects]::None }; $_.Handled=$true })
$window.Add_Drop({ try { if (!$script:busy -and $_.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) { Import-Songs @($_.Data.GetData([Windows.DataFormats]::FileDrop)) } } catch { [Windows.MessageBox]::Show($_.Exception.Message) | Out-Null } })
$ui.Reference.Add_Click({ $d=New-Object Microsoft.Win32.OpenFileDialog; $d.Filter='Audio|*.wav;*.mp3;*.flac;*.m4a;*.aif;*.aiff;*.ogg'; if ($d.ShowDialog()) { $script:reference=$d.FileName; $ui.ReferenceInfo.Text='Reference: '+[IO.Path]::GetFileName($d.FileName)+' · first 60 seconds'; $ui.ClearReference.IsEnabled=$true } })
$ui.ClearReference.Add_Click({ $script:reference=$null; $ui.ReferenceInfo.Text='Reference matching off'; $ui.ClearReference.IsEnabled=$false })
$ui.Preset.Add_SelectionChanged({ if ($ui.Preset.SelectedIndex -ge 0) { Set-Settings (Get-CatalogGenreSettings $ui.Preset.SelectedIndex) } })
$ui.SavePreset.Add_Click({ $d=New-Object Microsoft.Win32.SaveFileDialog; $d.Filter='OG preset|*.json'; $d.FileName='My Suno preset.json'; if ($d.ShowDialog()) { Get-Settings | ConvertTo-Json | Set-Content -LiteralPath $d.FileName -Encoding UTF8 } })
$ui.LoadPreset.Add_Click({ try { $d=New-Object Microsoft.Win32.OpenFileDialog; $d.Filter='OG preset|*.json'; if ($d.ShowDialog()) { $s=Test-Settings (Get-Content -LiteralPath $d.FileName -Raw -Encoding UTF8 | ConvertFrom-Json); Set-Settings $s; $ui.Status.Text='Custom preset loaded. Genre menu selects a new starting point.' } } catch { [Windows.MessageBox]::Show($_.Exception.Message,'Invalid preset') | Out-Null } })
$ui.Render.Add_Click({
    try {
        $jobs=@()
        $kind=@('wav','mp3','both')[$ui.ExportType.SelectedIndex]
        if ($script:sources.Count -eq 1 -and $kind -ne 'both') {
            $d=New-Object Microsoft.Win32.SaveFileDialog; $d.Filter=if ($kind -eq 'mp3') { 'MP3 audio|*.mp3' } else { 'Wave audio|*.wav' }; $d.DefaultExt=$kind; $d.FileName=[IO.Path]::GetFileNameWithoutExtension($script:source)+' - OG Master.'+$kind
            if (!$d.ShowDialog()) { return }; if ([IO.Path]::GetExtension($d.FileName) -ne ('.'+$kind)) { throw ('Choose a .'+$kind+' filename to match the selected format.') }; $jobs+=@{ Source=$script:source; Destination=$d.FileName }
        } else {
            $d=New-Object Windows.Forms.FolderBrowserDialog; $d.Description='Choose a folder for the batch masters'
            if ($d.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return }
            $reserved=@{}
            foreach ($src in $script:sources) {
                $stem=[IO.Path]::GetFileNameWithoutExtension($src)+' - OG Master'; $ext=if ($kind -eq 'mp3') { '.mp3' } else { '.wav' }; $dest=Join-Path $d.SelectedPath ($stem+$ext); $n=2
                while (@(Get-ExportPaths $dest $kind | Where-Object { (Test-Path -LiteralPath $_) -or $reserved.ContainsKey($_) }).Count -gt 0) { $dest=Join-Path $d.SelectedPath ($stem+" ($n)"+$ext); $n++ }
                foreach ($path in @(Get-ExportPaths $dest $kind)) { $reserved[$path]=$true }; $jobs+=@{ Source=$src; Destination=$dest }
            }
        }
        Start-Mastering $jobs
    } catch { if (!$script:process) { Set-Busy $false; Clear-Session }; [Windows.MessageBox]::Show($_.Exception.Message,'Unable to start') | Out-Null }
})
$ui.Cancel.Add_Click({ Stop-Mastering })
$ui.Original.Add_Click({ Play-Version 'original' }); $ui.Mastered.Add_Click({ Play-Version 'master' })
$ui.Stop.Add_Click({ $player.Stop(); $script:pendingSeek=0 })
$ui.LevelMatch.Add_Click({ Update-PlaybackGain })
$player.Add_MediaOpened({ if ($player.NaturalDuration.HasTimeSpan) { $ui.Seek.Maximum=$player.NaturalDuration.TimeSpan.TotalSeconds; $player.Position=[TimeSpan]::FromSeconds([math]::Min($script:pendingSeek,$ui.Seek.Maximum)) } })
$player.Add_MediaFailed({ $ui.PlaybackStatus.Text='Windows could not play this file. Mastering may still work; try exporting WAV for playback.' })
$ui.Seek.Add_ValueChanged({ if (!$script:updatingSeek -and $script:playing) { $player.Position=[TimeSpan]::FromSeconds($ui.Seek.Value) } })
$ui.Folder.Add_Click({ if ($script:output) { Start-Process explorer.exe -ArgumentList ('/select,"'+$script:output+'"') } })
$ui.SaveReport.Add_Click({ $d=New-Object Microsoft.Win32.SaveFileDialog; $d.Filter='Mastering report|*.json'; $d.FileName='OG mastering report.json'; if ($d.ShowDialog()) { ConvertTo-Json -InputObject @($script:completed) -Depth 8 | Set-Content -LiteralPath $d.FileName -Encoding UTF8 } })
$script:timer=New-Object Windows.Threading.DispatcherTimer; $timer.Interval=[TimeSpan]::FromMilliseconds(250)
$timer.Add_Tick({
    Invoke-EngineTick
    Invoke-WaveTick
    Invoke-AutoAnalysisTick
    Update-ActivityStatus
    if ($script:playing -and $player.NaturalDuration.HasTimeSpan) {
        $script:updatingSeek=$true; $ui.Seek.Value=$player.Position.TotalSeconds; $script:updatingSeek=$false
        $ui.PlaybackTime.Text='{0:mm\:ss} / {1:mm\:ss}' -f $player.Position,$player.NaturalDuration.TimeSpan
    }
})
$window.Add_Closing({ $timer.Stop(); $player.Close(); Stop-Waveform; Stop-AutoAnalysis; if ($script:process) { $script:process.Kill(); $script:process.WaitForExit(); $script:process.Dispose(); $script:process=$null }; Clear-Session })
Initialize-StudioUX
Initialize-InterfaceModes
Initialize-AutoAnalysis
Initialize-ActivityStatus
Initialize-ExportFormats
Update-ActivityStatus
$timer.Start()
if (!$env:OG_MASTERING_TEST) { $window.ShowDialog() | Out-Null }
