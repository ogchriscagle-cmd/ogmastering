# OG Studio Mastering 2.0.3 — Python release and update-check fix

Bundles the certificate policy file needed by the build runtime, fixing the missing-file error during Check updates. Packaged startup now checks secure HTTPS context creation, and --update-check-test exercises the real GitHub request from the EXE. Background errors also save their traceback to the local app settings folder.

Download **OG-Studio-Mastering-2.0.3-win-x64.exe** to fix older local builds whose update checker cannot run.

The obsolete PowerShell GUI, tests and C# launcher have been removed from the current source tree. Older versions remain in Git history and previous releases. Active setup/build helpers are retained.

# OG Studio Mastering 2.0.2 — update downloads

Check updates now downloads a newer Windows EXE from the official GitHub repository into your Downloads folder. Download progress and cancellation are available in the footer. The EXE is checked against its published SHA-256 digest before offering Open update. The current app stays open so projects can be saved before switching versions.

Download **OG-Studio-Mastering-2.0.2-win-x64.exe** for this update.

# OG Studio Mastering 2.0.1 — export filenames

New audio and report exports use ` - mastered` instead of ` - OG Master`, including WAV, MP3, Both and numbered duplicate exports.

Download **OG-Studio-Mastering-2.0.1-win-x64.exe** for this update.

# OG Studio Mastering 2.0.0 — Python Studio for Windows x64

Download **OG-Studio-Mastering-2.0.0-win-x64.exe**. It bundles Python, PySide6 / Qt, FFmpeg, Node and the offline CLAP model. Python and PowerShell do not need to be installed. The blue OG splash shows while the single-file app extracts and loads.

Windows 10/11 x64. Allow roughly 2 GB free for extraction, processing and the model, plus space for songs and exports. The EXE remains unsigned. No administrator access is needed for normal use.

- Native Python interface with Simple / Advanced modes, six themes, toolbar, projects, update checking and blue OG branding.
- All 58 genres, including Dark Rap and Dark Country; local genre/vocal suggestions and automatic import analysis.
- Direct FFmpeg mastering: EQ, cleanup, dynamics, saturation, stereo/M/S, reference matching and measured two-pass loudness targeting.
- WAV, MP3 320 kbps, or both; batch export, waveform, level-matched playback and reports.
- Existing `.ogmaster` projects and JSON presets remain readable. Fractional EQ gains are preserved instead of rounded to whole decibels.

Genre/vocal matches are suggestions, not guaranteed classifications. MP3 peaks are measured separately. Listen to your own songs before relying on an export. Update checks use the renamed ogstudiomastering repository and fall back to its releases page when unavailable.

The old PowerShell app remains available through **Start OG Mastering Legacy.cmd**. Third-party notices are included in the packaged resources. A corresponding FFmpeg source archive accompanies published releases.
