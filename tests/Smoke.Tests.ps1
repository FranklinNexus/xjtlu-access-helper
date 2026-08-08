$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $projectRoot "XJTLU-Access-Helper.ps1"
$configPath = Join-Path $projectRoot "services.json"

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "PowerShell parser errors: $($parseErrors -join '; ')"
}

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
if ($config.schemaVersion -ne 1 -or @($config.services).Count -lt 1) {
    throw "Invalid services.json schema."
}

$autoOpenRoot = Join-Path $projectRoot "auto-open"
$autoOpenRoutes = Get-Content -LiteralPath (Join-Path $autoOpenRoot "routes.json") -Raw | ConvertFrom-Json
if ($autoOpenRoutes.schemaVersion -ne 1 -or @($autoOpenRoutes.routes).Count -ne 3) {
    throw "Invalid auto-open route schema."
}
$serviceIds = @($config.services | ForEach-Object { [string]$_.id })
foreach ($route in @($autoOpenRoutes.routes)) {
    if ($route.service -notin $serviceIds) {
        throw "Auto-open route references an unknown service: $($route.service)"
    }
    if ($route.protocol -notmatch "^[a-z][a-z0-9+.-]+$") {
        throw "Auto-open route has an unsafe protocol: $($route.protocol)"
    }
    if (@($route.hosts).Count -lt 1 -or @($route.hosts | Where-Object { $_ -match "[*?]" }).Count -gt 0) {
        throw "Auto-open route must use explicit hosts: $($route.service)"
    }
}
$manifest = Get-Content -LiteralPath (Join-Path $autoOpenRoot "extension\manifest.json") -Raw | ConvertFrom-Json
if ($manifest.manifest_version -ne 3 -or $manifest.background.service_worker -ne "background.js") {
    throw "Invalid auto-open extension manifest."
}
if (@($manifest.host_permissions | Where-Object { $_ -match "://[*?]" }).Count -gt 0) {
    throw "Auto-open extension contains a wildcard host permission."
}

. $scriptPath -Action SelfTest

$secretUri = [Uri]"https://login.example.edu/auth/callback?code=secret-code&state=secret-state#fragment"
$sanitized = Get-SanitizedUri -Uri $secretUri
if ($sanitized -ne "https://login.example.edu/auth/callback") {
    throw "URI sanitization failed: $sanitized"
}
if ($sanitized.Contains("secret")) {
    throw "URI sanitization retained a secret."
}

$mockEndpoint = [PSCustomObject]@{
    Http = [PSCustomObject]@{
        RedirectChain = @(
            [PSCustomObject]@{ RedirectHost = "login.example.edu" },
            [PSCustomObject]@{ RedirectHost = "portal.invalid" }
        )
    }
}
$unexpected = @(Get-UnexpectedRedirectHosts -Endpoints @($mockEndpoint) -AllowedHosts @("example.edu"))
if ($unexpected.Count -ne 1 -or $unexpected[0] -ne "portal.invalid") {
    throw "Unexpected redirect detection failed."
}

$unsafeService = [PSCustomObject]@{
    id = "unsafe"
    name = "Unsafe"
    launchUrl = "https://example.edu/?token=secret"
    probeUrls = @("https://example.edu/")
    allowedRedirectHosts = @("example.edu")
}
$unsafeRejected = $false
try {
    Assert-ServiceDefinition -ServiceDefinition $unsafeService
}
catch {
    $unsafeRejected = $true
}
if (-not $unsafeRejected) {
    throw "Unsafe service configuration was accepted."
}

$appDataPrefix = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "XJTLU-Access-Helper"))
$profilePath = [IO.Path]::GetFullPath($script:ProfileRoot)
if (-not $profilePath.StartsWith($appDataPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Profile root escaped the dedicated app-data directory."
}

Write-Host "Smoke tests passed."
