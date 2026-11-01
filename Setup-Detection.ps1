$ErrorActionPreference='Stop'
$runtime=Join-Path $PSScriptRoot 'bin\detection'
New-Item -ItemType Directory -Force -Path $runtime | Out-Null
$nodeRoot=Join-Path $runtime 'node-v24.13.0-win-x64'
if (!(Test-Path (Join-Path $nodeRoot 'node.exe'))) {
    Write-Host 'Downloading the local Node runtime for audio detection...'
    $archive=Join-Path $runtime 'node.zip'
    Invoke-WebRequest 'https://nodejs.org/dist/v24.13.0/node-v24.13.0-win-x64.zip' -OutFile $archive -UseBasicParsing
    Expand-Archive -LiteralPath $archive -DestinationPath $runtime -Force
}
$node=Join-Path $nodeRoot 'node.exe'
$npm=Join-Path $nodeRoot 'node_modules\npm\bin\npm-cli.js'
$package=Join-Path $runtime 'package.json'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'detection\package.json') -Destination $package -Force
Write-Host 'Installing the CPU audio classifier. Runtime and model downloads can take several minutes.'
& $node $npm install --prefix $runtime --no-audit --no-fund
if ($LASTEXITCODE) { throw 'Detection dependencies could not be installed.' }
Write-Host 'Downloading and checking the local CLAP model...'
& $node (Join-Path $PSScriptRoot 'detection\detect.mjs') --setup $runtime
if ($LASTEXITCODE) { throw 'Audio model setup failed.' }
Write-Host 'Auto Detect is ready. Restart OG Mastering.'
