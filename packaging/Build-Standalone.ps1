param([string]$OutputDirectory='dist')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$out=if ([IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory } else { Join-Path $root $OutputDirectory }
New-Item -ItemType Directory -Force -Path $out | Out-Null
$runtime=Join-Path $root 'bin\detection'
if (!(Test-Path (Join-Path $root 'bin\ffmpeg.exe')) -or !(Test-Path (Join-Path $runtime 'ready.json'))) { throw 'Run Setup.cmd and Setup-Detection.cmd before building.' }
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$payload=Join-Path $out 'payload.zip'
$entries=[Collections.Generic.List[object]]::new()
foreach ($file in Get-ChildItem -LiteralPath $root -File) { if ($file.Extension -in @('.ps1','.xaml','.json','.md') -and $file.Name -notlike 'Verify-*' -and $file.Name -notlike 'Setup*' -and $file.Name -ne 'Verify.ps1') { $entries.Add(@{Source=$file.FullName;Path=$file.Name}) } }
$entries.Add(@{Source=(Join-Path $PSScriptRoot 'Verify-Package.ps1');Path='Verify-Package.ps1'})
$entries.Add(@{Source=(Join-Path $PSScriptRoot 'CLAP-MODEL-CARD.md');Path='notices/CLAP-MODEL-CARD.md'})
$entries.Add(@{Source=(Join-Path $PSScriptRoot 'APACHE-2.0.txt');Path='notices/CLAP-APACHE-2.0.txt'})
$entries.Add(@{Source=(Join-Path $root 'bin\ffmpeg.exe');Path='bin/ffmpeg.exe'})
foreach ($file in Get-ChildItem (Join-Path $root 'detection') -File) { $entries.Add(@{Source=$file.FullName;Path=('detection/'+$file.Name)}) }
foreach ($file in Get-ChildItem $runtime -Recurse -File) {
    $relative=$file.FullName.Substring($runtime.Length+1).Replace('\','/')
    if ($relative -eq 'node.zip' -or $relative -like 'node-v24.13.0-win-x64/node_modules/*' -or ($relative -like 'node-v24.13.0-win-x64/*' -and $relative -notin @('node-v24.13.0-win-x64/node.exe','node-v24.13.0-win-x64/LICENSE'))) { continue }
    if ($relative -match 'node_modules/onnxruntime-node/bin/napi-v3/(darwin|linux)/' -or $relative -match 'node_modules/onnxruntime-node/bin/napi-v3/win32/arm64/') { continue }
    $entries.Add(@{Source=$file.FullName;Path=('bin/detection/'+$relative)})
}
$distribution=Get-ChildItem (Join-Path $root 'bin\distribution') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
if (!$distribution) { $distribution=Get-ChildItem (Join-Path $root 'bin\download') -Directory | Select-Object -First 1 }
foreach ($file in Get-ChildItem $distribution.FullName -Recurse -File | Where-Object { $_.FullName.Substring($distribution.FullName.Length+1) -notmatch '^bin[\\/]' }) { $entries.Add(@{Source=$file.FullName;Path=('notices/ffmpeg/'+$file.FullName.Substring($distribution.FullName.Length+1).Replace('\','/'))}) }
$stream=[IO.File]::Create($payload)
try {
    $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
    try { $count=0; foreach ($entry in $entries) { [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$entry.Source,$entry.Path,[IO.Compression.CompressionLevel]::Optimal) | Out-Null; $count++; if ($count%200 -eq 0) { Write-Output ("Packed $count / $($entries.Count) files") } } } finally { $zip.Dispose() }
} finally { $stream.Dispose() }
$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$exe=Join-Path $out 'OG-Mastering-1.0.0-win-x64.exe'
& $csc /nologo /target:winexe /platform:x64 /optimize+ /reference:System.Windows.Forms.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll ("/out:"+$exe) (Join-Path $PSScriptRoot 'Launcher.cs')
if ($LASTEXITCODE) { throw 'Launcher compilation failed.' }
$hash=(Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash
$exeStream=[IO.File]::Open($exe,[IO.FileMode]::Append)
try {
    $offset=$exeStream.Position
    $input=[IO.File]::OpenRead($payload);try { $input.CopyTo($exeStream) } finally { $input.Dispose() }
    $writer=[IO.BinaryWriter]::new($exeStream);$writer.Write([long]$offset)
    $bytes=[byte[]]::new(32);for ($i=0;$i -lt 32;$i++) { $bytes[$i]=[Convert]::ToByte($hash.Substring($i*2,2),16) };$writer.Write($bytes);$writer.Write([Text.Encoding]::ASCII.GetBytes('OGPKG001'));$writer.Flush()
} finally { $exeStream.Dispose() }
Write-Output ('EXE '+$exe)
Write-Output ('SIZE '+(Get-Item -LiteralPath $exe).Length)
Get-FileHash -LiteralPath $exe -Algorithm SHA256 | Format-List
