[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$routesPath = Join-Path $PSScriptRoot "routes.json"
$config = Get-Content -LiteralPath $routesPath -Raw | ConvertFrom-Json

foreach ($route in @($config.routes)) {
    $protocolKey = Join-Path "HKCU:\Software\Classes" $route.protocol
    if (Test-Path -LiteralPath $protocolKey) {
        Remove-Item -LiteralPath $protocolKey -Recurse -Force
        Write-Host "Removed $($route.protocol)"
    }
}

Write-Host "XJTLU auto-open protocols removed for the current Windows user."
Write-Host "You can also remove the unpacked extension from Edge at edge://extensions/."
