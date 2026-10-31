function New-AdvancedCard([string]$title,[string]$toggleKey='',[string]$color='#16D7ED',[string]$note='') {
    $border=New-Object Windows.Controls.Border; $border.Background='#101019'; $border.BorderBrush='#252631'; $border.BorderThickness='1'; $border.CornerRadius='13'; $border.Padding='11'; $border.Margin='0,0,0,9'
    $stack=New-Object Windows.Controls.StackPanel; $header=New-Object Windows.Controls.DockPanel
    if ($toggleKey) {
        $check=New-Object Windows.Controls.CheckBox; $check.Margin='0'; $check.VerticalAlignment='Center'; $check.ToolTip="Enable $title"; [Windows.Controls.DockPanel]::SetDock($check,'Right')
        $binding=New-Object Windows.Data.Binding 'IsChecked'; $binding.Source=$ui[$toggleKey]; $binding.Mode='TwoWay'; $check.SetBinding([Windows.Controls.Primitives.ToggleButton]::IsCheckedProperty,$binding) | Out-Null; $header.Children.Add($check) | Out-Null
        $binding=New-Object Windows.Data.Binding 'IsEnabled'; $binding.Source=$ui[$toggleKey]; $check.SetBinding([Windows.UIElement]::IsEnabledProperty,$binding) | Out-Null
    }
    $label=New-Object Windows.Controls.TextBlock; $label.Text=$title.ToUpperInvariant(); $label.Foreground=$color; $label.FontSize=10; $label.FontWeight='Bold'; $header.Children.Add($label) | Out-Null; $stack.Children.Add($header) | Out-Null
    if ($note) { $text=New-Object Windows.Controls.TextBlock; $text.Text=$note; $text.TextWrapping='Wrap'; $text.Foreground='#63738E'; $text.FontSize=9; $text.Margin='0,8,0,2'; $stack.Children.Add($text) | Out-Null }
    $border.Child=$stack; $ui.AdvancedCards.Children.Add($border) | Out-Null
    return $stack
}
function Add-AdvancedSlider($panel,[string]$key,[string]$label,[string]$unit='') {
    $text=New-Object Windows.Controls.TextBlock; $text.FontSize=9; $text.Foreground='#8C9FBE'; $text.Margin='0,11,0,0'
    $b=New-Object Windows.Data.Binding 'Value'; $b.Source=$ui[$key]; $b.StringFormat=$label+'  {0:0.##}'+$unit; $text.SetBinding([Windows.Controls.TextBlock]::TextProperty,$b) | Out-Null
    $slider=New-Object Windows.Controls.Slider; $slider.Minimum=$ui[$key].Minimum; $slider.Maximum=$ui[$key].Maximum; $slider.TickFrequency=$ui[$key].TickFrequency; $slider.SmallChange=$slider.TickFrequency; $slider.Margin='0,5,0,2'
    $b=New-Object Windows.Data.Binding 'Value'; $b.Source=$ui[$key]; $b.Mode='TwoWay'; $slider.SetBinding([Windows.Controls.Primitives.RangeBase]::ValueProperty,$b) | Out-Null
    $b=New-Object Windows.Data.Binding 'IsEnabled'; $b.Source=$ui[$key]; $slider.SetBinding([Windows.UIElement]::IsEnabledProperty,$b) | Out-Null
    $panel.Children.Add($text) | Out-Null; $panel.Children.Add($slider) | Out-Null
}
function Add-UnavailableCard([string]$title,[string]$note) {
    $card=New-AdvancedCard ($title+' · unavailable') '' '#64718A' $note
}
function Add-AmountSwitch($card,[string]$key,[double]$restore) {
    $check=New-Object Windows.Controls.CheckBox; $check.Template=$script:advancedSwitchTemplate; $check.Margin='0'; $check.ToolTip="Enable $key"; $check.Tag=@{Slider=$ui[$key];Last=$restore}; $check.IsChecked=$ui[$key].Value -gt 0
    $check.Add_Checked({ if ($this.Tag.Slider.Value -le 0) { $this.Tag.Slider.Value=$this.Tag.Last } })
    $check.Add_Unchecked({ if ($this.Tag.Slider.Value -gt 0) { $this.Tag.Last=$this.Tag.Slider.Value; $this.Tag.Slider.Value=0 } })
    $binding=New-Object Windows.Data.Binding 'IsEnabled'; $binding.Source=$ui[$key]; $check.SetBinding([Windows.UIElement]::IsEnabledProperty,$binding) | Out-Null
    [Windows.Controls.DockPanel]::SetDock($check,'Right'); $card.Children[0].Children.Insert(0,$check)
    $ui[$key].Tag.AmountSwitch=$check
    $ui[$key].Add_ValueChanged({ $this.Tag.AmountSwitch.IsChecked=$this.Value -gt 0 })
}
function Update-EQCurve {
    if (!$ui.EQCurve) { return }
    $points=New-Object Windows.Media.PointCollection
    foreach ($i in 0..119) {
        $f=20*[math]::Pow(1000,$i/119.0); $omega=2*[math]::PI*$f/48000; $db=0.0
        if ($ui.EqEnabled.IsChecked) { foreach ($j in 0..5) {
            $gain=$ui[('Eq'+$j)].Value; $a=[math]::Pow(10,$gain/40); $w=2*[math]::PI*$script:EqFrequencies[$j]/48000; $alpha=[math]::Sin($w)/1.6
            $b0=1+$alpha*$a; $b1=-2*[math]::Cos($w); $b2=1-$alpha*$a; $a0=1+$alpha/$a; $a1=$b1; $a2=1-$alpha/$a
            $nr=$b0+$b1*[math]::Cos($omega)+$b2*[math]::Cos(2*$omega); $ni=-$b1*[math]::Sin($omega)-$b2*[math]::Sin(2*$omega)
            $dr=$a0+$a1*[math]::Cos($omega)+$a2*[math]::Cos(2*$omega); $di=-$a1*[math]::Sin($omega)-$a2*[math]::Sin(2*$omega)
            $db+=10*[math]::Log10([math]::Max(1e-12,($nr*$nr+$ni*$ni)/($dr*$dr+$di*$di)))
        } }
        $points.Add([Windows.Point]::new($i*2,40-[math]::Max(-12,[math]::Min(12,$db))*2.8))
    }
    $ui.EQCurve.Points=$points
}
function Initialize-AdvancedControls {
    foreach ($spec in @(@('HP',20,120,5),@('GlueThreshold',-40,-6,1),@('GlueRatio',1,4,0.1),@('GlueMix',0,100,5),@('SideCut',40,250,10),@('MidMud',-4,4,0.25),@('SatDrive',0,100,5),@('SatType',0,2,1))) { Add-Control CleanupControls $spec[0] $spec[0] $spec[1] $spec[2] $spec[3] }
    foreach ($key in @('NoiseNR','Leveler','FadeIn','FadeOut','EqEnabled','GlueEnabled','WidthEnabled','MSEnabled','SatEnabled','Dither')) { Add-Check CleanupControls $key $key }
    # The real checkboxes retain their settings identity; visible cards bind to them.
    $switchTemplate=[Windows.Markup.XamlReader]::Parse(@'
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="CheckBox"><Border x:Name="Track" Width="32" Height="17" CornerRadius="9" Background="#282934"><Ellipse x:Name="Dot" Width="13" Height="13" Fill="White" HorizontalAlignment="Left" Margin="2,0"/></Border><ControlTemplate.Triggers><Trigger Property="IsChecked" Value="True"><Setter TargetName="Track" Property="Background" Value="#08B5CF"/><Setter TargetName="Dot" Property="HorizontalAlignment" Value="Right"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter TargetName="Track" Property="Opacity" Value="0.4"/></Trigger></ControlTemplate.Triggers></ControlTemplate>
'@)
    $script:advancedSwitchTemplate=$switchTemplate
    $card=New-AdvancedCard 'Clip repair' Repair '#18D6EF' 'Optional autoregressive repair of clipped peaks. Enable after listening; not automatic spline reconstruction.'
    $card=New-AdvancedCard 'Noise NR' NoiseNR '#18D6EF' 'Gentle adaptive FFT noise reduction. Can alter cymbals and vocal texture.'
    $card=New-AdvancedCard 'Mono bass' MonoBass '#18D6EF' 'Reduce side-channel energy below the selected side-cut frequency.'
    $card=New-AdvancedCard 'Dynamic leveler' Leveler '#18D6EF' 'Smooth slower volume changes; this cannot restore lost dynamics.'
    Add-UnavailableCard 'M/S compression' 'Independent mid/side compression is not implemented.'
    $card=New-AdvancedCard 'Fade in' FadeIn; $card=New-AdvancedCard 'Fade out' FadeOut '#18D6EF' '0.8-second fade in; up to 1.5-second fade out.'
    $card=New-AdvancedCard 'EQ' EqEnabled
    $view=New-Object Windows.Controls.Viewbox; $view.Height=85; $view.Stretch='Fill'; $canvas=New-Object Windows.Controls.Canvas; $canvas.Width=238; $canvas.Height=80; $canvas.Background='#0B0C14'
    $line=New-Object Windows.Shapes.Line; $line.X1=0; $line.X2=238; $line.Y1=40; $line.Y2=40; $line.Stroke='#252D3C'; $canvas.Children.Add($line) | Out-Null
    $curve=New-Object Windows.Shapes.Polyline; $curve.Stroke='#0ED7EB'; $curve.StrokeThickness=1.5; $canvas.Children.Add($curve) | Out-Null; $ui.EQCurve=$curve; $view.Child=$canvas; $card.Children.Add($view) | Out-Null
    $text=New-Object Windows.Controls.TextBlock; $text.Text='Six-band EQ response · 20 Hz–20 kHz'; $text.FontSize=8; $text.Foreground='#62718D'; $card.Children.Add($text) | Out-Null
    Add-AdvancedSlider $card HP 'HP filter' ' Hz'
    foreach ($i in 0..5) { Add-AdvancedSlider $card ('Eq'+$i) ("$($script:EqFrequencies[$i]) Hz") ' dB'; $ui[('Eq'+$i)].Add_ValueChanged({ Update-EQCurve }) }
    $ui.EqEnabled.Add_Checked({ Update-EQCurve }); $ui.EqEnabled.Add_Unchecked({ Update-EQCurve })
    Add-AdvancedSlider $card Bass 'Low shelf' ' dB'; Add-AdvancedSlider $card Air 'Air shelf' ' dB'
    $card=New-AdvancedCard 'Glue compression' GlueEnabled '#15DAEC' 'Amount scales the selected ratio toward 1:1. Wet mix enables parallel compression.'
    Add-AdvancedSlider $card Glue 'Amount' '%'; Add-AdvancedSlider $card GlueThreshold 'Threshold' ' dB'; Add-AdvancedSlider $card GlueRatio 'Maximum ratio' ':1'; Add-AdvancedSlider $card GlueMix 'Wet mix' '%'
    Add-UnavailableCard 'Multiband' 'A dedicated multiband compressor is not implemented.'
    Add-UnavailableCard 'Transient' 'A dedicated attack/sustain shaper is not implemented.'
    $card=New-AdvancedCard 'Limiter / ceiling' '' '#FF675F' '8× oversampled safety limiting stays on for every master.'; Add-AdvancedSlider $card Ceiling 'Ceiling' ' dBTP'
    $card=New-AdvancedCard 'Width' WidthEnabled; Add-AdvancedSlider $card Width 'Amount · 1 = original' '×'
    $card=New-AdvancedCard 'M/S EQ' MSEnabled '#B992FA'; Add-AdvancedSlider $card SideCut 'Side cut (Mono bass switch)' ' Hz'; Add-AdvancedSlider $card SideAir 'Side air' ' dB'; Add-AdvancedSlider $card MidMud 'Mid mud' ' dB'; Add-AdvancedSlider $card MidPresence 'Mid presence' ' dB'
    Add-UnavailableCard 'Dynamic EQ' 'Threshold-driven EQ bands are not implemented. The manual EQ and cleanup cuts are static.'
    $card=New-AdvancedCard 'Saturation' SatEnabled '#FFAE25' 'Soft clipping with 4× oversampling. 0 = tanh, 1 = atan, 2 = cubic character.'; Add-AdvancedSlider $card SatDrive 'Drive' '%'; Add-AdvancedSlider $card SatType 'Character' ''
    $card=New-AdvancedCard 'Exciter' '' '#17D5A4'; Add-AmountSwitch $card Excite 15; Add-AdvancedSlider $card Excite 'High-frequency harmonics' '%'
    $card=New-AdvancedCard 'De-esser' '' '#16D8E9'; Add-AmountSwitch $card DeEss 15; Add-AdvancedSlider $card DeEss 'Intensity · 0 = off' '%'
    Add-UnavailableCard 'De-verb' 'Reverb reduction is not implemented.'
    $card=New-AdvancedCard 'Dither' Dither '#18D6EF' 'Triangular dither during final PCM conversion. Turn off only when you need undithered output.'
    # Use compact cyan toggle switches for every visible advanced-card checkbox.
    foreach ($border in $ui.AdvancedCards.Children) { foreach ($header in $border.Child.Children) { if ($header -is [Windows.Controls.DockPanel]) { foreach ($child in $header.Children) { if ($child -is [Windows.Controls.CheckBox]) { $child.Template=$switchTemplate } } } } }
    Update-EQCurve
}
