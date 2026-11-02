param([switch]$SkipTests)
$ErrorActionPreference='Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$python=Join-Path $PWD '.venv\Scripts\python.exe'
if (!(Test-Path $python)) { throw 'Create .venv and install python_app/requirements.txt first.' }
& $python python_app\app.py --write-splash
if ($LASTEXITCODE) { throw 'Splash generation failed' }
if (!$SkipTests) { & $python python_app\app.py --smoke-test; if ($LASTEXITCODE) { throw 'Python startup check failed' } }
& $python -m PyInstaller --noconfirm --distpath dist --workpath build\python python_app\ogmastering.spec
if ($LASTEXITCODE) { throw 'Python standalone build failed' }
if (!$SkipTests) {
    $env:OG_SMOKE_OUTPUT=Join-Path $PWD ('verification\packaged-startup-'+[guid]::NewGuid().ToString('N'))
    $app=Start-Process -FilePath (Join-Path $PWD 'dist\OG-Studio-Mastering-2.0.0-win-x64.exe') -ArgumentList '--smoke-test' -WindowStyle Hidden -PassThru
    $null=$app.Handle
    if (!$app.WaitForExit(180000)) { Stop-Process -Id $app.Id; throw 'Packaged startup timed out' }
    if ($app.ExitCode -ne 0 -or !(Test-Path (Join-Path $env:OG_SMOKE_OUTPUT 'python-smoke.txt'))) { throw 'Packaged Qt startup failed; do not distribute this EXE.' }
    Get-Content (Join-Path $env:OG_SMOKE_OUTPUT 'python-smoke.txt')
    Remove-Item Env:\OG_SMOKE_OUTPUT
}
Get-FileHash dist\OG-Studio-Mastering-2.0.0-win-x64.exe -Algorithm SHA256
