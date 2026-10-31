# OG Mastering — Suno Studio

An offline Windows mastering app for exported Suno songs, inspired by the advanced workflow described by [SunoMaster V3](https://sunomaster.com/mode-comparison). It uses its own DSP chain, matching, presets, and advice rules.

## Start

Double-click **Start OG Mastering.cmd**. After cloning or downloading this repository, run **Setup.cmd** once to install FFmpeg, then use the launcher. FFmpeg binaries are intentionally excluded from Git.

Choose **WAV**, **MP3 (320 kbps)**, or **Both WAV + MP3** in the left-side Export Format selector, available in Simple and Advanced. WAV preserves the selected PCM resolution; MP3 is encoded from the same mastered PCM. Both creates matching `.wav` and `.mp3` files in a chosen folder. Both and batch exports avoid existing filenames with numbered suffixes. The original files are protected for both extensions. Encoding and MP3 verification appear in the bottom progress panel. The selected export format is shared between modes for the current session.

Encoded MP3 is separately decoded and measured because lossy encoding can change loudness and increase true peaks. MP3-only meters and comparison use the MP3; Both uses WAV for comparison and primary meters, with separate MP3 measurements in the saved report. No destination is copied until processing/encoding checks succeed. Copying the two files is sequential; a filesystem error during copying can leave one completed file.

A fixed bottom status panel stays visible while scrolling. It shows the current task, batch song number, progress bar, and an expandable recent-activity log. Percentages use FFmpeg's processed audio time and equal weighting across the analysis/render/verification passes, so overall progress is an estimate rather than a time-remaining prediction. Unknown-duration work shows an indeterminate indicator instead of a fabricated percentage. Completion, cancellation and errors appear in the same panel.

The app starts in **Simple** mode: import a song, optionally add a reference, choose loudness, and master/export using balanced Suno processing. **Advanced** opens the full genre, style, EQ, cleanup, dynamics, stereo, preset, and batch controls. Both modes keep their own settings during the session, so advanced tweaks do not silently carry into Simple. Switching preserves the imported song, reference, and completed export. Mode changes are disabled while mastering. Settings take effect on the next export.

Import now automatically starts background analysis of the first selected song: original integrated loudness, true peak, loudness range, and six broad tone bands. Full-song loudness is measured; tone bands use the first minute. **Auto-tune conservative cleanup** defaults on and adds mild mud/harshness reduction where indicated, modest de-essing for strong upper energy, and disables glue for very low loudness range. It preserves your target, manual EQ and genre, and will not replace edits made while analysis ran. Use **Apply suggestions** to accept suggestions after editing. Turn Auto-tune off to retain full manual processing. Batch mastering remeasures and adapts each song independently. Automatic repair, noise reduction and saturation are never enabled by these rules.

Genre information is read from a file's genre metadata when available; this is labeled as a tag. Audio-based genre, tempo, instrument and vocal classification are not implemented. Untagged songs show genre uncertainty instead of a false genre claim. Re-analysis and mastering remain local; no audio is uploaded.

Windows 10/11 and built-in Windows PowerShell 5.1 are required. No Python, Node, account, subscription, or audio upload is needed. This version uses a Windows desktop launcher rather than a compiled EXE.

## Master a Suno song

1. Import your exported WAV, MP3, FLAC, M4A, AIFF, or OGG. Use the highest-quality source you have.
2. Choose a genre starting point. Balanced Suno processing starts with gentle de-essing and small cuts to mud and harshness.
3. Optionally add a reference song and adjust the **Ref match** knob.
4. Use the nine quick-adjust knobs and style buttons. **Advanced settings** on the left contains cleanup, EQ/mid-side, and output controls. Source repair is optional; enable it if you hear clipping.
5. Choose **Master & export**. Compare the original/master with level matching enabled and review the advisor.

Select **Bulk**, then choose multiple songs for batch mastering to a folder. Each receives the same settings, with separately calculated reference corrections. Existing batch exports receive numbered filenames. Cancellation keeps completed exports and leaves the current unfinished export unsaved. A batch stops on an error and reports how many songs completed. The **Presets** button opens the local save/load panel.

The screenshot-inspired studio layout includes draggable knobs (also adjustable with the mouse wheel and arrow keys), a real audio waveform, click-to-seek during playback, original/master switching, and four measured output cards. The waveform covers up to the first 30 minutes. **Has vocals** starts with gentle de-essing; **Instrumental** turns it off. Automatic detection is visibly unavailable. The quick controls use existing DSP features rather than simulated de-reverb or other unimplemented effects. Changes take effect on the next master/export, not as live audio processing.

## Features

| Area | Implementation |
| --- | --- |
| Repair | Optional FFmpeg autoregressive de-clipping; can change transients and takes longer |
| Cleanup | 25 Hz subsonic filter, adjustable 280 Hz mud and 3.5 kHz harshness cuts, de-essing |
| Tone | Six parametric bands at 80/250/800/2500/6000/12000 Hz, Q 0.8, plus low/high shelves |
| Reference | Six broad energy bands in the first 60 seconds of each song; level-independent correction capped at ±3 dB per band, scaled by match amount |
| Dynamics | Adjustable RMS glue compression, off by default |
| Harmonics | High-frequency exciter, off by default |
| Stereo | Mid presence, side air, side-channel bass reduction below 120 Hz, stereo width |
| Presets | 58 choices including Dark Rap, Dark Country, Suno Optimized, hip-hop/trap/drill, pop subgenres, dance/electronic, rock/metal, acoustic, jazz/classical, lo-fi, cinematic, Latin, reggae, gospel, funk, disco, and manual; custom JSON save/load |
| Loudness | Full-song original measurement, processed measurement, two-pass EBU R128 normalization, independent export verification |
| Limiting | 8× oversampled lookahead safety limiter, no auto makeup, latency compensation, headroom before conversion |
| Export | Triangular-dithered 24-bit/48 kHz or 16-bit/44.1 kHz PCM WAV |
| Playback | Seekable comparison; switching keeps position; integrated-loudness matching attenuates the louder version |
| Advisor | Measurement rules for chosen loudness/peak targets, dynamics, and broad source energy balance |
| Reports | Save completed tracks' settings, measurements, reference corrections, and advice as JSON |

### Expanded Advanced Settings

The left-hand advanced panel now uses screenshot-inspired processing cards and cyan toggle switches. Added functional controls include gentle adaptive FFT noise reduction, a slow dynamic leveler, 0.8-second fade-in, up to 1.5-second fade-out, a 20–120 Hz high-pass, a six-band EQ response plot and bypass, glue threshold/maximum-ratio/wet-mix controls, stereo-width bypass, M/S EQ bypass, adjustable side-bass cutoff and mid-mud EQ, 4× oversampled saturation with three soft-clip characters, exciter/de-esser on/off controls, and optional triangular dither.

The glue amount scales the selected maximum ratio from 1:1, so amount 0 bypasses compression. The EQ switch bypasses the six parametric bands and shelves; high-pass and cleanup cuts remain independent. The M/S EQ switch bypasses mid/side tone shaping; mono bass has its own switch. The safety limiter remains enabled during export. The plot shows the manual six-band response at 48 kHz, excluding shelves, high-pass, cleanup, and reference corrections. Changed parameters apply to the next master/export.

M/S compression, multiband compression, transient shaping, dynamic EQ, and de-reverb appear as explicitly unavailable cards. Local presets are supported; publishing to a marketplace is not. Source repair uses FFmpeg autoregression rather than the screenshot's claimed cubic-spline method, and is enabled manually. The leveler can smooth changing volume but does not reconstruct dynamics already lost in a Suno export.

This is not a reproduction of SunoMaster's proprietary algorithms. Automatic genre/BPM detection, AI advice, community presets, multiband compression, and a packaged installer are not implemented. Repair and excitation cannot guarantee restoration of lost detail or generation artifacts. Checks compare your chosen target and ceiling; they do not certify every platform's requirements.

The expanded genre menu follows the names shown in the supplied photos. Each selection loads an editable starting point for loudness, tone, de-essing, stereo, and compression. These are our own preset choices, not measured genre standards or copies of SunoMaster settings. Reset restores the currently selected genre. The catalog is stored in `GenrePresets.json`; `GenreCatalog.ps1` validates and loads it. Previously saved custom presets retain their saved settings.

Matching is approximate broad tone matching. It does not match arrangement, instruments, dynamics, or a full EQ curve. Bands below -65 dB are ignored. Long intros can bias the opening-minute analysis. Manual EQ and cleanup add to reference corrections; each combined parametric band is capped at ±9 dB.

The source meter measures the untouched input. The output meter measures the actual exported WAV; loudness and peaks can differ slightly from the target after conversion. Loudnorm may use dynamic processing when linear normalization cannot satisfy the constraints. Source repair and oversampling increase render time. Windows audio codecs determine which originals can play; FFmpeg may still be able to master a source that Windows cannot preview.

## Validation

Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\Verify.ps1`.

Checks exercise the app's actual asynchronous pipeline with generated stereo/mono fixtures, repair/excitation/M-S processing, reference correction limits, batch export, both output formats, a decimal-comma locale, preset validation, cancellation, silence rejection, and source protection. Results are under `verification/suno-studio`. Run `Verify-Layout.ps1` with the same PowerShell options to check waveform generation, DSP control wiring, mode navigation, and layout renders at two sizes under `verification/layout`. These checks do not replace listening tests on your songs.

## Files

- `OG-Mastering.ps1`: stable launcher entry point.
- `SunoMastering.ps1`: WPF interface, playback, asynchronous batch workflow.
- `Studio.xaml`: screenshot-inspired desktop layout and visual styles.
- `StudioUI.ps1`: rotary control visuals, waveform generation, style and mode controls.
- `AdvancedUI.ps1`: processing cards, toggle bindings, advanced controls, and EQ response plot.
- `AudioEngine.ps1`: settings, DSP chain, matching, advisor rules.
- `Verify-SunoStudio.ps1`: integration checks.

## FFmpeg

Setup downloads the essentials build from [gyan.dev](https://www.gyan.dev/ffmpeg/builds/). Processing uses [FFmpeg's documented filters](https://ffmpeg.org/ffmpeg-filters.html). Setup retains the downloaded archive and extracted distribution under `bin/download`. Review its licensing requirements before redistribution.
