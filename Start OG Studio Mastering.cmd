@echo off
cd /d "%~dp0"
if exist "dist\OG-Studio-Mastering-2.0.3-win-x64.exe" (
  start "" "dist\OG-Studio-Mastering-2.0.3-win-x64.exe"
  exit /b 0
)
if not exist ".venv\Scripts\pythonw.exe" (
  echo Install Python dependencies using python_app\README.md first.
  pause
  exit /b 1
)
start "" ".venv\Scripts\pythonw.exe" "python_app\app.py"
