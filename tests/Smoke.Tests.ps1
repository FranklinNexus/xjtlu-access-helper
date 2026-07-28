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
