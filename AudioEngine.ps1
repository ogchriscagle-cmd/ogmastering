# Local, deterministic DSP. No remote services or model claims.
$script:EqFrequencies = @(80, 250, 800, 2500, 6000, 12000)
function Format-Number([double]$value) { $value.ToString('0.########', [Globalization.CultureInfo]::InvariantCulture) }
function Get-DefaultSettings {
    [ordered]@{ Version=3; Genre='Suno / balanced'; Loudness=-14; Ceiling=-1; Format=0; Repair=$false; DeEss=15; Mud=1; Harsh=1; Glue=0; Excite=0; Bass=0; Air=0; Width=1; MonoBass=$true; MidPresence=0; SideAir=0; Eq0=0; Eq1=0; Eq2=0; Eq3=0; Eq4=0; Eq5=0; Match=50; HP=25; NoiseNR=$false; Leveler=$false; FadeIn=$false; FadeOut=$false; EqEnabled=$true; GlueEnabled=$true; GlueThreshold=-20; GlueRatio=1.4; GlueMix=100; WidthEnabled=$true; MSEnabled=$true; SideCut=120; MidMud=0; SatEnabled=$false; SatDrive=20; SatType=0; Dither=$true }
}
function Get-GenreSettings([int]$index) {
    $s = Get-DefaultSettings
    switch ($index) {
        1 { $s.Genre='Pop / vocal'; $s.DeEss=25; $s.Mud=1.5; $s.Harsh=1.5; $s.MidPresence=0.5; $s.Glue=15 }
        2 { $s.Genre='Hip-hop / R&B'; $s.Loudness=-12; $s.Bass=1; $s.Mud=1.5; $s.DeEss=20; $s.Glue=20 }
        3 { $s.Genre='Electronic / dance'; $s.Loudness=-10; $s.Width=1.1; $s.Glue=25; $s.DeEss=10 }
        4 { $s.Genre='Rock / heavy'; $s.Loudness=-12; $s.Harsh=2; $s.Mud=1.5; $s.Glue=20; $s.Width=1.05 }
        5 { $s.Genre='Acoustic / folk'; $s.Loudness=-16; $s.DeEss=10; $s.Mud=0.5; $s.Harsh=0.5; $s.MonoBass=$false }
        6 { $s.Genre='Ambient / cinematic'; $s.Loudness=-16; $s.Width=1.1; $s.DeEss=5; $s.Harsh=0.5; $s.MonoBass=$false }
        7 { $s.Genre='Bypass cleanup / manual'; $s.DeEss=0; $s.Mud=0; $s.Harsh=0; $s.MonoBass=$false }
    }
    return $s
}
function Test-Settings($candidate) {
    $s = Get-DefaultSettings
    $ranges = @{ Loudness=@(-20,-8); Ceiling=@(-3,-0.3); Format=@(0,1); DeEss=@(0,100); Mud=@(0,6); Harsh=@(0,6); Glue=@(0,100); Excite=@(0,100); Bass=@(-6,6); Air=@(-6,6); Width=@(0.5,1.5); MidPresence=@(-4,4); SideAir=@(-4,4); Match=@(0,100) }
    foreach ($i in 0..5) { $ranges['Eq'+$i] = @(-6,6) }
    $ranges.HP=@(20,120); $ranges.GlueThreshold=@(-40,-6); $ranges.GlueRatio=@(1,4); $ranges.GlueMix=@(0,100); $ranges.SideCut=@(40,250); $ranges.MidMud=@(-4,4); $ranges.SatDrive=@(0,100); $ranges.SatType=@(0,2)
    foreach ($key in $ranges.Keys) {
        $value = $candidate.$key
        if ($null -eq $value) { continue }
        $n = 0.0
        if (![double]::TryParse([string]$value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$n) -or [double]::IsNaN($n) -or [double]::IsInfinity($n) -or $n -lt $ranges[$key][0] -or $n -gt $ranges[$key][1]) { throw "Invalid preset value: $key" }
        if ($key -eq 'Format' -and $n -notin @(0,1)) { throw 'Invalid export format.' }
        if ($key -eq 'SatType' -and $n -notin @(0,1,2)) { throw 'Invalid saturation type.' }
        $s[$key] = $n
    }
    foreach ($key in @('Repair','MonoBass','NoiseNR','Leveler','FadeIn','FadeOut','EqEnabled','GlueEnabled','WidthEnabled','MSEnabled','SatEnabled','Dither')) { if ($null -ne $candidate.$key) { if ($candidate.$key -isnot [bool]) { throw "Invalid preset flag: $key" }; $s[$key] = $candidate.$key } }
    if ($candidate.Genre) { $s.Genre = [string]$candidate.Genre }
    return $s
}
function Get-ProcessingChain($s, [double[]]$matchGains = @(0,0,0,0,0,0), [double]$duration=0) {
    $filters = [Collections.Generic.List[string]]::new()
    $filters.Add('aformat=sample_fmts=fltp:channel_layouts=stereo')
    if ($s.Repair) { $filters.Add('adeclip=w=55:o=75:a=8:t=10') }
    $filters.Add('highpass=f='+(Format-Number $s.HP))
    if ($s.NoiseNR) { $filters.Add('afftdn=nr=6:nf=-50:tn=1') }
    if ($s.Leveler) { $filters.Add('dynaudnorm=f=500:g=15:p=0.8:m=2:s=5') }
    if ($s.Mud -gt 0) { $filters.Add('equalizer=f=280:t=q:w=0.8:g=' + (Format-Number (-$s.Mud))) }
    if ($s.Harsh -gt 0) { $filters.Add('equalizer=f=3500:t=q:w=1.1:g=' + (Format-Number (-$s.Harsh))) }
    if ($s.DeEss -gt 0) { $filters.Add('deesser=i=' + (Format-Number ($s.DeEss / 100)) + ':m=0.35:f=0.5') }
    if ($s.EqEnabled) { for ($i=0; $i -lt 6; $i++) {
        $gain = [math]::Max(-9, [math]::Min(9, ($s[('Eq'+$i)] + $matchGains[$i])))
        $filters.Add("equalizer=f=$($script:EqFrequencies[$i]):t=q:w=0.8:g=" + (Format-Number $gain))
    }
    $filters.Add('bass=f=120:g=' + (Format-Number $s.Bass))
    $filters.Add('treble=f=6500:g=' + (Format-Number $s.Air)) }
    if ($s.GlueEnabled -and $s.Glue -gt 0) {
        $threshold = [math]::Pow(10, $s.GlueThreshold / 20)
        $ratio = 1 + (($s.GlueRatio-1) * $s.Glue / 100)
        $filters.Add('acompressor=threshold=' + (Format-Number $threshold) + ':ratio=' + (Format-Number $ratio) + ':mix='+(Format-Number ($s.GlueMix/100))+':attack=25:release=180:makeup=1:knee=2.8:link=maximum:detection=rms')
    }
    if ($s.SatEnabled -and $s.SatDrive -gt 0) { $drive=1+$s.SatDrive/50; $type=@('tanh','atan','cubic')[[int]$s.SatType]; $filters.Add('volume='+(Format-Number $drive)); $filters.Add("asoftclip=type=${type}:threshold=0.8:oversample=4:output="+(Format-Number (1/$drive))) }
    if ($s.Excite -gt 0) { $filters.Add('aexciter=amount=' + (Format-Number ($s.Excite / 100)) + ':drive=2:blend=0:freq=6500:ceil=16000') }
    $filters.Add('stereotools=mode=lr>ms')
    if ($s.MonoBass) { $filters.Add('highpass=f='+(Format-Number $s.SideCut)+':p=2:c=FR') }
    if ($s.MSEnabled) {
    $filters.Add('equalizer=f=2500:t=q:w=0.9:c=FL:g=' + (Format-Number $s.MidPresence))
    $filters.Add('treble=f=6500:c=FR:g=' + (Format-Number $s.SideAir))
    $filters.Add('equalizer=f=280:t=q:w=0.8:c=FL:g='+(Format-Number $s.MidMud)) }
    $filters.Add('stereotools=mode=ms>lr')
    if ($s.WidthEnabled) { $filters.Add('stereotools=slev=' + (Format-Number $s.Width)) }
    if ($s.FadeIn) { $filters.Add('afade=t=in:d=0.8') }
    if ($s.FadeOut) { if ($duration -le 0) { throw 'Fade-out needs a readable track duration.' }; $length=[math]::Min(1.5,$duration/2); $filters.Add('afade=t=out:st='+(Format-Number ($duration-$length))+':d='+(Format-Number $length)) }
    return ($filters -join ',')
}
function Get-Normalizer($s, $measurement = $null) {
    # Headroom protects against the final sample-rate conversion.
    $text = 'loudnorm=I=' + (Format-Number $s.Loudness) + ':TP=' + (Format-Number ($s.Ceiling - 0.2)) + ':LRA=11:print_format=json'
    if ($measurement) {
        foreach ($key in @('input_i','input_tp','input_lra','input_thresh','target_offset')) { if ($measurement.$key -notmatch '^-?\d+(\.\d+)?$') { throw 'Silent or unmeasurable audio. Choose a different song.' } }
        $text += ":measured_I=$($measurement.input_i):measured_TP=$($measurement.input_tp):measured_LRA=$($measurement.input_lra):measured_thresh=$($measurement.input_thresh):offset=$($measurement.target_offset):linear=true"
    }
    return $text
}
function Get-Finalizer($s) {
    $rate = @(48000,44100)[[int]$s.Format]
    $bits = @(24,16)[[int]$s.Format]; $fmt = @('s32','s16')[[int]$s.Format]
    $limit = Format-Number ([math]::Pow(10, ($s.Ceiling - 0.1) / 20))
    $dither=if ($s.Dither) { 'triangular' } else { 'none' }
    return "aresample=$($rate * 8),alimiter=limit=${limit}:level=false:attack=5:release=80:latency=true,aresample=osr=${rate}:osf=${fmt}:dither_method=${dither}:output_sample_bits=${bits}"
}
function Get-ProfileGraph($s) {
    $graph = '[0:a:0]aformat=channel_layouts=stereo,asplit=7[raw][b0][b1][b2][b3][b4][b5];[raw]' + (Get-Normalizer $s) + '[main]'
    for ($i=0; $i -lt 6; $i++) { $graph += ";[b$i]atrim=duration=60,bandpass=f=$($script:EqFrequencies[$i]):width_type=o:w=2,volumedetect@band$i,anullsink" }
    return $graph
}
function Read-Measurement([string]$logText) {
    $found = [regex]::Matches($logText, '(?s)\{\s*"input_i".*?\}')
    if ($found.Count -eq 0) { throw 'The audio engine returned no loudness measurement.' }
    return ($found[$found.Count-1].Value | ConvertFrom-Json)
}
function Read-Bands([string]$logText) {
    $values = @()
    foreach ($i in 0..5) {
        $found = [regex]::Match($logText, ('\[volumedetect@band' + $i + '\s+@[^\]]+\]\s+mean_volume:\s*(-?\d+(?:\.\d+)?)'))
        if (!$found.Success) { throw 'Could not measure frequency balance.' }
        $values += [double]::Parse($found.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
    }
    return ,$values
}
function Get-MatchGains([double[]]$sourceBands, [double[]]$referenceBands, [double]$strength) {
    # Remove average level differences; match spectral shape, not loudness.
    $srcMean = ($sourceBands | Measure-Object -Average).Average
    $refMean = ($referenceBands | Measure-Object -Average).Average
    $gains = @()
    foreach ($i in 0..5) {
        if ($sourceBands[$i] -lt -65 -or $referenceBands[$i] -lt -65) { $gains += 0; continue }
        $delta = ($referenceBands[$i] - $refMean) - ($sourceBands[$i] - $srcMean)
        $gains += [math]::Round(([math]::Max(-3, [math]::Min(3, $delta)) * $strength / 100), 2)
    }
    return ,$gains
}
function Get-Advice($inputMeasure, $outputMeasure, [double[]]$bands, $s) {
    $advice = [Collections.Generic.List[string]]::new()
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $peak = [double]::Parse($outputMeasure.input_tp, $culture)
    $lufs = [double]::Parse($outputMeasure.input_i, $culture)
    $lra = [double]::Parse($outputMeasure.input_lra, $culture)
    if ($peak -gt ($s.Ceiling + 0.1)) { $advice.Add('Peak exceeds your ceiling. Lower the ceiling and remaster.') } else { $advice.Add('PASS: measured true peak is within your chosen ceiling.') }
    if ([math]::Abs($lufs - $s.Loudness) -gt 1) { $advice.Add('Loudness is over 1 LU from target. Try less glue compression or a quieter target.') } else { $advice.Add('PASS: loudness is within 1 LU of target.') }
    if ([double]::Parse($inputMeasure.input_tp, $culture) -ge -0.1) { $advice.Add('Source peaks are near full scale. Listen for clipping; try source repair if distorted. A peak reading alone cannot confirm clipping.') }
    if ($lra -lt 3) { $advice.Add('Low measured loudness range. Try glue at 0 and a quieter target; mastering cannot restore lost dynamics.') }
    if ($lra -gt 12) { $advice.Add('Wide loudness range. Gentle glue may help quiet passages sit more evenly.') }
    if ($bands[1] -gt ($bands[2] + 7)) { $advice.Add('Low-mid energy is prominent. Try 1 dB more mud reduction, then compare by ear.') }
    if ($bands[4] -gt ($bands[3] + 2)) { $advice.Add('Strong upper-frequency energy. Try more de-essing or harshness reduction.') }
    $advice.Add('These are measurement-based suggestions, not a genre classifier or a guarantee of streaming compliance.')
    return ($advice -join "`n`n")
}
