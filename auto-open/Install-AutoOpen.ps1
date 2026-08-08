[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$programRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$routesPath = Join-Path $PSScriptRoot "routes.json"
$launcherPath = Join-Path $programRoot "XJTLU-Access-Helper.ps1"
$extensionPath = Join-Path $PSScriptRoot "extension"
$registryRoot = "HKCU:\Software\Classes"

if (-not (Test-Path -LiteralPath $launcherPath)) {
    throw "XJTLU-Access-Helper.ps1 was not found next to auto-open."
}
if (-not (Test-Path -LiteralPath $extensionPath)) {
    throw "The extension folder was not found: $extensionPath"
}

$config = Get-Content -LiteralPath $routesPath -Raw | ConvertFrom-Json
if ($config.schemaVersion -ne 1) {
    throw "Unsupported auto-open route schema version."
}

$powershellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
foreach ($route in @($config.routes)) {
    if ($route.protocol -notmatch "^[a-z][a-z0-9+.-]+$") {
        throw "Unsafe protocol name: $($route.protocol)"
    }

    $protocolKey = Join-Path $registryRoot $route.protocol
    $commandKey = Join-Path $protocolKey "shell\open\command"
    $command = "`"$powershellPath`" -NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$launcherPath`" -Action Launch -Service $($route.service) -NetworkMode System"

    New-Item -Path $protocolKey -Force | Out-Null
    New-ItemProperty -Path $protocolKey -Name "(Default)" -Value "URL:XJTLU Access Helper $($route.service)" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $protocolKey -Name "URL Protocol" -Value "" -PropertyType String -Force | Out-Null
    New-Item -Path $commandKey -Force | Out-Null
    New-ItemProperty -Path $commandKey -Name "(Default)" -Value $command -PropertyType String -Force | Out-Null
}

Write-Host "Registered XJTLU auto-open protocols for the current Windows user."
Write-Host "No global proxy, DNS, browser profile, or security setting was changed."
Write-Host "Extension folder: $extensionPath"
Write-Host "Next: open Edge extensions, enable Developer mode, choose Load unpacked, and select that folder."

$edgePaths = @(
    (Join-Path ([Environment]::GetFolderPath("ProgramFilesX86")) "Microsoft\Edge\Application\msedge.exe"),
    (Join-Path ([Environment]::GetFolderPath("ProgramFiles")) "Microsoft\Edge\Application\msedge.exe")
)
$edge = $edgePaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ($edge) {
    Start-Process -FilePath $edge -ArgumentList "edge://extensions/" | Out-Null
}
