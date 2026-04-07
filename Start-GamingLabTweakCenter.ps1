[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "payload\FirstLogon.ps1"
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Fant ikke tweak-senteret: $scriptPath"
}

& powershell.exe -ExecutionPolicy Bypass -NoProfile -File $scriptPath
