$ErrorActionPreference = 'Stop'
$bin = Join-Path $PSScriptRoot 'bin'
New-Item -ItemType Directory -Force -Path $bin | Out-Null
if (Test-Path (Join-Path $bin 'ffmpeg.exe')) { Write-Host 'FFmpeg is already installed.'; exit }
Write-Host 'Downloading FFmpeg from gyan.dev. This can take a few minutes...'
$archive = Join-Path $bin 'ffmpeg.zip'
Invoke-WebRequest 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip' -OutFile $archive -UseBasicParsing
Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $bin 'download') -Force
$exe = Get-ChildItem (Join-Path $bin 'download') -Filter ffmpeg.exe -Recurse | Select-Object -First 1
if (!$exe) { throw 'FFmpeg was not found in the downloaded archive.' }
Copy-Item -LiteralPath $exe.FullName -Destination (Join-Path $bin 'ffmpeg.exe')
Write-Host 'Ready. Open Start OG Mastering.cmd to launch the app.'
