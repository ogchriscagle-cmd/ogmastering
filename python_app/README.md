# Python edition · v2.0.0

The new native Python / PySide6 application lives in `python_app`. It runs the existing FFmpeg DSP directly with Python subprocesses; PowerShell is not required at runtime. Offline genre/vocal classification reuses the bundled Node/CLAP worker.

Features carried over: Simple and Advanced modes, six themes, 58 genre presets including Dark Rap / Dark Country, styles, six-band EQ, cleanup/repair, compression, saturation, exciter, stereo/M/S controls, reference matching, automatic analysis and genre/vocal suggestions, waveform, level-matched playback, batch mastering, WAV/MP3/both, reports, projects, toolbar and update checking, blue icon and branded splash. Legacy `.ogmaster` projects and JSON presets can be opened. Releases and source: https://github.com/ogchriscagle-cmd/ogstudiomastering .

Run from source on Windows with Python 3.12:

```
python -m venv .venv
.venv\Scripts\python -m pip install -r python_app\requirements.txt
.venv\Scripts\python python_app\app.py
```

Run the existing `Setup.cmd` and `Setup-Detection.cmd` first if `bin` has not been installed. These are developer setup helpers; the built EXE contains the runtimes.

Build the standalone EXE with `packaging\Build-Python.ps1`. Output: `dist\OG-Studio-Mastering-2.0.0-win-x64.exe`. The standalone EXE includes Python, Qt, FFmpeg, the detection runtime and model; users do not install Python. Its custom splash appears during extraction and initialization. One-file extraction may take longer on the first launch or under antivirus scanning. Windows SmartScreen signing status is unchanged.

The PowerShell source remains as a legacy fallback. The GitHub release workflow builds and tests the Python edition. The Python edition retains fractional EQ gains that the previous PowerShell overload selection rounded to whole dB. Export reports describe measured results; playback listening checks remain essential for real songs.
