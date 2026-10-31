$ErrorActionPreference='Stop'
try {
    . (Join-Path $PSScriptRoot 'SunoMastering.ps1')
} catch {
    $startupError=$_
    $details=($startupError | Out-String)+[Environment]::NewLine+$startupError.ScriptStackTrace
    $log=Join-Path $PSScriptRoot 'startup-error.log'
    try { [IO.File]::WriteAllText($log,$details) } catch { $log='Log could not be written.' }
    Add-Type -AssemblyName PresentationFramework
    [Windows.MessageBox]::Show("OG Mastering could not start.`n`n$($startupError.Exception.Message)`n`nDetails: $log",'OG Mastering startup error') | Out-Null
    exit 1
}
