$ErrorActionPreference='Stop'; $env:OG_MASTERING_TEST='1'
. (Join-Path $PSScriptRoot 'SunoMastering.ps1'); $timer.Stop()
$out=Join-Path $PSScriptRoot 'verification\advanced'; New-Item -ItemType Directory -Force -Path $out | Out-Null
$source=Join-Path $PSScriptRoot 'verification\suno-studio\Suno fixture & stereo.wav'
Import-Songs @($source)
$s=Get-DefaultSettings; $s.NoiseNR=$true; $s.Leveler=$true; $s.FadeIn=$true; $s.FadeOut=$true; $s.SatEnabled=$true; $s.SatDrive=30; $s.SatType=2; $s.Glue=60; $s.GlueRatio=2; $s.GlueThreshold=-24; $s.GlueMix=50; $s.HP=60; $s.SideCut=150; $s.MidMud=-0.75
Set-Settings $s
$roundtrip=Test-Settings ((Get-Settings) | ConvertTo-Json | ConvertFrom-Json)
if (!$roundtrip.FadeOut -or $roundtrip.GlueMix -ne 50 -or $roundtrip.HP -ne 60) { throw 'Advanced preset settings lost' }
$disabled=Get-DefaultSettings; $disabled.EqEnabled=$false; $disabled.WidthEnabled=$false; $disabled.MSEnabled=$false; $disabled.GlueEnabled=$false; $disabled.Glue=80; $disabled.Eq0=5; $disabled.Width=1.5
$chain=Get-ProcessingChain $disabled
foreach ($text in @('equalizer=f=80:', 'stereotools=slev=', 'acompressor=', 'c=FL:')) { if ($chain.Contains($text)) { throw "Bypass failed: $text" } }
$disabled.Dither=$false; if ((Get-Finalizer $disabled) -notmatch 'dither_method=none') { throw 'Dither bypass failed' }
Start-Mastering @(@{Source=$source; Destination=(Join-Path $out 'advanced-master.wav')})
$deadline=[DateTime]::UtcNow.AddMinutes(2)
while ($script:busy -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100; Invoke-EngineTick; Invoke-WaveTick }
if ($script:busy -or $ui.Stage.Text -eq 'Mastering stopped' -or $script:completed.Count -ne 1) { throw $ui.Status.Text }
$script:report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $out 'report.json') -Encoding UTF8
# Validate actual fade endpoints and duration from decoded PCM.
$pcm=Join-Path $out 'advanced-mono.f32'
& $script:ffmpeg -hide_banner -loglevel error -y -i (Join-Path $out 'advanced-master.wav') -ac 1 -f f32le $pcm
$bytes=[IO.File]::ReadAllBytes($pcm); $n=$bytes.Length/4; $first=0.0; $last=0.0; $middle=0.0
for ($i=0;$i -lt 480;$i++) { $first+=[math]::Pow([BitConverter]::ToSingle($bytes,$i*4),2); $last+=[math]::Pow([BitConverter]::ToSingle($bytes,($n-480+$i)*4),2); $middle+=[math]::Pow([BitConverter]::ToSingle($bytes,([int]($n/2)+$i)*4),2) }
if ($first -ge $middle/20 -or $last -ge $middle/20) { throw 'Fade endpoints were not attenuated' }
if ([math]::Abs($n/48000-5) -gt 0.02) { throw 'Processing changed the song duration' }
$ui.AdvancedPanel.IsExpanded=$true; $surface=$window.Content; $surface.Background='#080910'; $surface.Measure([Windows.Size]::new(1500,900)); $surface.Arrange([Windows.Rect]::new(0,0,1500,900)); $surface.UpdateLayout()
$bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(1500,900,96,96,[Windows.Media.PixelFormats]::Pbgra32); $bitmap.Render($surface)
$encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new(); $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap)); $stream=[IO.File]::Create((Join-Path $out 'advanced-layout.png')); $encoder.Save($stream); $stream.Close()
Stop-SongDetection; Stop-AutoAnalysis; Stop-Waveform; $player.Close(); $env:OG_MASTERING_TEST=$null
Write-Output 'PASS: advanced preset roundtrip, bypass, noise NR, leveler, saturation, parallel glue, side EQ, fades, output duration, layout.'
