# OG Studio Mastering

A Windows desktop app for mastering exported Suno songs. Part of the **OG Studio** music app family alongside **OG Studio Video**.

[Download the latest Windows EXE](https://github.com/ogchriscagle-cmd/ogstudiomastering/releases/latest) · [Releases](https://github.com/ogchriscagle-cmd/ogstudiomastering/releases)

## Windows app

The Python / PySide6 edition bundles Python, Qt, FFmpeg, the Node detection worker and the offline CLAP model in one EXE. No separate Python or PowerShell installation is needed. Windows 10/11 x64; allow roughly 2 GB free for extraction and processing, plus space for songs and exports. The EXE is currently unsigned.

- Simple and Advanced modes, six saved color themes, blue OG branding and a custom loading splash.
- Automatic song analysis and optional local genre/vocal suggestions; 58 genres including Dark Rap and Dark Country.
- EQ, de-clipping, de-essing, cleanup, glue compression, saturation, excitation, stereo width and M/S tone controls.
- Optional reference tone matching; measured two-pass loudness targeting and an oversampled safety limiter.
- WAV, MP3 320 kbps, or both; batch export with filename collision protection.
- Waveform, seekable original/master comparison with loudness matching, progress/activity panel and export reports.
- Save/open projects and presets; existing PowerShell `.ogmaster` projects and JSON presets remain readable.
- Toolbar links to GitHub releases and update checking.

Detection scores are relative model matches, not calibrated accuracy probabilities. Review genre/vocal suggestions before applying them. Audio processing is local. Measurements do not guarantee streaming compliance or restore detail lost from the source; compare by ear.

## Run from source

See [Python setup and build instructions](python_app/README.md). After installing the Python dependencies and audio/detection runtimes, use **Start OG Studio Mastering.cmd**. The older **Start OG Mastering.cmd** name remains an alias.

Build a standalone EXE with `packaging/Build-Python.ps1`. The build checks source startup and the packaged Qt interface. The release workflow additionally exercises bundled FFmpeg, WAV/MP3 export, reference matching and offline genre/vocal inference before publishing.

The retired WPF/PowerShell implementation has been removed from the current source tree. Older versions remain available in Git history and previous releases. The remaining PowerShell files are setup/build helpers; the desktop app and mastering orchestration run in Python.

## Third-party software

See [third-party notices](THIRD-PARTY-NOTICES.md) and [Python/Qt notices](python_app/PYTHON-NOTICES.md). Notices and licenses accompany the bundled runtimes. Published releases include the corresponding FFmpeg source archive.
