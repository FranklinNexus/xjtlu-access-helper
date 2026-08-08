[CmdletBinding()]
param(
    [ValidateSet("Menu", "Launch", "Diagnose", "Reset", "SelfTest")]
    [string]$Action = "Menu",

    [ValidateSet("learning-mall", "webmail", "main-site")]
    [string]$Service = "learning-mall",

    [ValidateSet("System", "Direct")]
    [string]$NetworkMode = "System",

    [string]$OutputDirectory,

    [switch]$NoOpenReport,

    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$script:AppName = "XJTLU Access Helper"
$script:AppVersion = "0.2.0"
$script:ConfigPath = Join-Path $PSScriptRoot "services.json"
$script:AppDataRoot = Join-Path $env:LOCALAPPDATA "XJTLU-Access-Helper"
$script:ProfileRoot = Join-Path $script:AppDataRoot "Profiles"
$script:DefaultReportRoot = Join-Path $script:AppDataRoot "Reports"

function New-DirectoryIfMissing {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Protect-ErrorText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $Text
    }

    $protected = $Text
    if (-not [string]::IsNullOrWhiteSpace($env:USERNAME)) {
        $protected = $protected.Replace($env:USERNAME, "<user>")
    }
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $protected = $protected.Replace($env:USERPROFILE, "<user-profile>")
    }
    return $protected
}

function Get-ObjectPropertyValue {
    param(
        [object]$Object,
        [string]$Name,
        [object]$DefaultValue = $null
    )

    if ($null -eq $Object) {
        return $DefaultValue
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $DefaultValue
    }

    return $property.Value
}

function Assert-ServiceDefinition {
    param([Parameter(Mandatory = $true)][object]$ServiceDefinition)

    $id = [string](Get-ObjectPropertyValue -Object $ServiceDefinition -Name "id" -DefaultValue "")
    if ($id -notmatch "^[a-z0-9-]+$") {
        throw "A service id is missing or unsafe: $id"
    }

    $name = [string](Get-ObjectPropertyValue -Object $ServiceDefinition -Name "name" -DefaultValue "")
    if ([string]::IsNullOrWhiteSpace($name)) {
        throw "Service $id is missing a display name."
    }

    $urls = @([string](Get-ObjectPropertyValue -Object $ServiceDefinition -Name "launchUrl" -DefaultValue ""))
    $urls += @((Get-ObjectPropertyValue -Object $ServiceDefinition -Name "probeUrls" -DefaultValue @()) | ForEach-Object { [string]$_ })
    foreach ($urlText in $urls) {
        $uri = $null
        if (-not [Uri]::TryCreate($urlText, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne "https") {
            throw "Service $id contains a non-HTTPS or invalid URL: $urlText"
        }
        if (-not [string]::IsNullOrWhiteSpace($uri.Query) -or -not [string]::IsNullOrWhiteSpace($uri.Fragment)) {
            throw "Service $id contains a query or fragment. Store only stable, non-sensitive entry URLs."
        }
    }

    $allowedHosts = @((Get-ObjectPropertyValue -Object $ServiceDefinition -Name "allowedRedirectHosts" -DefaultValue @()) | ForEach-Object { [string]$_ })
    if ($allowedHosts.Count -eq 0) {
        throw "Service $id does not define allowedRedirectHosts."
    }
    foreach ($hostName in $allowedHosts) {
        if ([Uri]::CheckHostName($hostName) -ne [UriHostNameType]::Dns) {
            throw "Service $id contains an invalid redirect host: $hostName"
        }
    }
}

function Get-AppConfig {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
        throw "Configuration file not found: $script:ConfigPath"
    }

    $config = Get-Content -LiteralPath $script:ConfigPath -Raw | ConvertFrom-Json
    if ((Get-ObjectPropertyValue -Object $config -Name "schemaVersion") -ne 1) {
        throw "Unsupported services.json schema version."
    }

    $services = @(Get-ObjectPropertyValue -Object $config -Name "services")
    if ($services.Count -eq 0) {
        throw "services.json does not contain any services."
    }

    foreach ($serviceDefinition in $services) {
        Assert-ServiceDefinition -ServiceDefinition $serviceDefinition
    }

    return $config
}

function Get-ServiceDefinition {
    param([Parameter(Mandatory = $true)][string]$Id)

    $config = Get-AppConfig
    $match = @($config.services | Where-Object { $_.id -eq $Id })
    if ($match.Count -ne 1) {
        throw "Unknown or duplicated service id: $Id"
    }

    return $match[0]
}

function Get-InstalledChromiumBrowsers {
    $programFiles = [Environment]::GetFolderPath("ProgramFiles")
    $programFilesX86 = [Environment]::GetFolderPath("ProgramFilesX86")
    $localAppData = [Environment]::GetFolderPath("LocalApplicationData")

    $candidates = @(
        [PSCustomObject]@{ Name = "Microsoft Edge"; Path = (Join-Path $programFilesX86 "Microsoft\Edge\Application\msedge.exe") },
        [PSCustomObject]@{ Name = "Microsoft Edge"; Path = (Join-Path $programFiles "Microsoft\Edge\Application\msedge.exe") },
        [PSCustomObject]@{ Name = "Google Chrome"; Path = (Join-Path $localAppData "Google\Chrome\Application\chrome.exe") },
        [PSCustomObject]@{ Name = "Google Chrome"; Path = (Join-Path $programFiles "Google\Chrome\Application\chrome.exe") },
        [PSCustomObject]@{ Name = "Google Chrome"; Path = (Join-Path $programFilesX86 "Google\Chrome\Application\chrome.exe") },
        [PSCustomObject]@{ Name = "Brave"; Path = (Join-Path $localAppData "BraveSoftware\Brave-Browser\Application\brave.exe") },
        [PSCustomObject]@{ Name = "Brave"; Path = (Join-Path $programFiles "BraveSoftware\Brave-Browser\Application\brave.exe") }
    )

    $seen = @{}
    $installed = @()
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate.Path)) {
            continue
        }
        if (-not (Test-Path -LiteralPath $candidate.Path)) {
            continue
        }
        if ($seen.ContainsKey($candidate.Path)) {
            continue
        }

        $seen[$candidate.Path] = $true
        $file = Get-Item -LiteralPath $candidate.Path
        $installed += [PSCustomObject]@{
            Name = $candidate.Name
            Path = $candidate.Path
            Version = $file.VersionInfo.ProductVersion
        }
    }

    return $installed
}

function Get-PreferredBrowser {
    $browsers = @(Get-InstalledChromiumBrowsers)
    if ($browsers.Count -eq 0) {
        throw "No supported Chromium browser was found. Install Microsoft Edge, Google Chrome, or Brave."
    }

    return $browsers[0]
}

function Start-IsolatedBrowser {
    param(
        [Parameter(Mandatory = $true)][object]$ServiceDefinition,
        [Parameter(Mandatory = $true)][ValidateSet("System", "Direct")][string]$Mode
    )

    $browser = Get-PreferredBrowser
    $profileName = $Mode.ToLowerInvariant()
    $profilePath = Join-Path $script:ProfileRoot $profileName
    New-DirectoryIfMissing -Path $profilePath

    $arguments = @(
        "--user-data-dir=`"$profilePath`"",
        "--disable-extensions",
        "--disable-sync",
        "--no-first-run",
        "--no-default-browser-check",
        "--new-window"
    )

    if ($Mode -eq "Direct") {
        $arguments += "--no-proxy-server"
    }

    $arguments += [string]$ServiceDefinition.launchUrl

    Write-Host "Starting $($ServiceDefinition.name) in $($browser.Name)..."
    Write-Host "Profile: $profilePath"
    Write-Host "Network mode: $Mode"
    Start-Process -FilePath $browser.Path -ArgumentList $arguments | Out-Null
}

function Get-ProxySummary {
    $internetSettings = Get-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
    $proxyEnabled = [bool](Get-ObjectPropertyValue -Object $internetSettings -Name "ProxyEnable" -DefaultValue 0)
    $pacConfigured = -not [string]::IsNullOrWhiteSpace([string](Get-ObjectPropertyValue -Object $internetSettings -Name "AutoConfigURL" -DefaultValue ""))
    $autoDetect = [bool](Get-ObjectPropertyValue -Object $internetSettings -Name "AutoDetect" -DefaultValue 0)

    $proxyVariables = @("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY")
    $presentVariables = @()
    foreach ($variable in $proxyVariables) {
        if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($variable))) {
            $presentVariables += $variable
        }
    }

    $vpnKeywords = @("clash", "wireguard", "wintun", "openvpn", "tailscale", "zerotier", "v2ray", "sing-box", "outline", "trojan", "vpn", "tap")
    $vpnHints = @()
    if ($null -ne (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue)) {
        $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" })
        foreach ($adapter in $adapters) {
            $adapterText = ("{0} {1}" -f $adapter.Name, $adapter.InterfaceDescription).ToLowerInvariant()
            foreach ($keyword in $vpnKeywords) {
                if ($adapterText.Contains($keyword)) {
                    $vpnHints += $keyword
                }
            }
        }
    }

    return [PSCustomObject]@{
        WindowsProxyEnabled = $proxyEnabled
        PacConfigured = $pacConfigured
        AutoDetectEnabled = $autoDetect
        ProxyEnvironmentVariablesPresent = @($presentVariables | Sort-Object -Unique)
        ActiveVpnTechnologyHints = @($vpnHints | Sort-Object -Unique)
    }
}

function Test-DnsEndpoint {
    param([Parameter(Mandatory = $true)][string]$HostName)

    $watch = [Diagnostics.Stopwatch]::StartNew()
    $addresses = @()
    $errorText = $null

    try {
        $records = @(Resolve-DnsName -Name $HostName -DnsOnly -ErrorAction Stop)
        foreach ($record in $records) {
            $ipAddress = Get-ObjectPropertyValue -Object $record -Name "IPAddress"
            if (-not [string]::IsNullOrWhiteSpace([string]$ipAddress)) {
                $addresses += [string]$ipAddress
            }
        }
    }
    catch {
        $errorText = Protect-ErrorText $_.Exception.GetBaseException().Message
    }
    finally {
        $watch.Stop()
    }

    return [PSCustomObject]@{
        Success = ($addresses.Count -gt 0)
        Addresses = @($addresses | Sort-Object -Unique)
        DurationMs = $watch.ElapsedMilliseconds
        Error = $errorText
    }
}

function Test-TcpEndpoint {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [int]$Port = 443,
        [int]$TimeoutMs = 5000
    )

    $watch = [Diagnostics.Stopwatch]::StartNew()
    $client = New-Object Net.Sockets.TcpClient
    $errorText = $null
    $success = $false

    try {
        $pending = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $pending.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            throw "TCP connection timed out after $TimeoutMs ms."
        }
        $client.EndConnect($pending)
        $success = $client.Connected
    }
    catch {
        $errorText = Protect-ErrorText $_.Exception.GetBaseException().Message
    }
    finally {
        $client.Dispose()
        $watch.Stop()
    }

    return [PSCustomObject]@{
        Success = $success
        DurationMs = $watch.ElapsedMilliseconds
        Error = $errorText
    }
}

function Test-TlsEndpoint {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [int]$TimeoutMs = 8000
    )

    $watch = [Diagnostics.Stopwatch]::StartNew()
    $tcpClient = New-Object Net.Sockets.TcpClient
    $sslStream = $null
    $success = $false
    $errorText = $null
    $protocol = $null
    $issuer = $null
    $expiresUtc = $null

    try {
        $connect = $tcpClient.BeginConnect($HostName, 443, $null, $null)
        if (-not $connect.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            throw "TLS TCP connection timed out after $TimeoutMs ms."
        }
        $tcpClient.EndConnect($connect)

        $sslStream = New-Object Net.Security.SslStream($tcpClient.GetStream(), $false)
        $authTask = $sslStream.AuthenticateAsClientAsync($HostName)
        if (-not $authTask.Wait($TimeoutMs)) {
            throw "TLS handshake timed out after $TimeoutMs ms."
        }
        [void]$authTask.GetAwaiter().GetResult()

        $certificate = New-Object Security.Cryptography.X509Certificates.X509Certificate2($sslStream.RemoteCertificate)
        $success = $true
        $protocol = [string]$sslStream.SslProtocol
        $issuer = [string]$certificate.Issuer
        $expiresUtc = $certificate.NotAfter.ToUniversalTime().ToString("o")
    }
    catch {
        $errorText = Protect-ErrorText $_.Exception.GetBaseException().Message
    }
    finally {
        if ($null -ne $sslStream) {
            $sslStream.Dispose()
        }
        $tcpClient.Dispose()
        $watch.Stop()
    }

    return [PSCustomObject]@{
        Success = $success
        Protocol = $protocol
        CertificateIssuer = $issuer
        CertificateExpiresUtc = $expiresUtc
        DurationMs = $watch.ElapsedMilliseconds
        Error = $errorText
    }
}

function Get-SanitizedUri {
    param([Parameter(Mandatory = $true)][Uri]$Uri)

    return $Uri.GetLeftPart([UriPartial]::Path)
}

function Test-HttpEndpoint {
    param(
        [Parameter(Mandatory = $true)][Uri]$Uri,
        [Parameter(Mandatory = $true)][ValidateSet("System", "Direct")][string]$Mode,
        [int]$TimeoutSeconds = 12,
        [int]$MaximumRedirects = 8
    )

    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $false
    $handler.UseCookies = $false
    if ($Mode -eq "Direct") {
        $handler.UseProxy = $false
    }

    $client = New-Object Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd("XJTLU-Access-Helper/$($script:AppVersion)")

    $currentUri = $Uri
    $chain = @()
    $errorText = $null
    $finalStatus = $null
    $clockSkewSeconds = $null
    $watch = [Diagnostics.Stopwatch]::StartNew()

    try {
        for ($index = 0; $index -le $MaximumRedirects; $index++) {
            $request = New-Object Net.Http.HttpRequestMessage([Net.Http.HttpMethod]::Get, $currentUri)
            $response = $null
            try {
                $response = $client.SendAsync($request, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
                $status = [int]$response.StatusCode
                $finalStatus = $status
                $location = $response.Headers.Location

                $serverDate = $response.Headers.Date
                if ($null -ne $serverDate) {
                    $clockSkewSeconds = [Math]::Round([Math]::Abs(($serverDate.UtcDateTime - [DateTime]::UtcNow).TotalSeconds), 0)
                }

                $chain += [PSCustomObject]@{
                    Url = Get-SanitizedUri -Uri $currentUri
                    Status = $status
                    RedirectHost = if ($null -ne $location) {
                        $nextForReport = if ($location.IsAbsoluteUri) { $location } else { New-Object Uri($currentUri, $location) }
                        $nextForReport.Host
                    }
                    else { $null }
                }

                if ($status -lt 300 -or $status -ge 400 -or $null -eq $location) {
                    break
                }
                if ($index -eq $MaximumRedirects) {
                    throw "Redirect limit of $MaximumRedirects was reached."
                }

                $currentUri = if ($location.IsAbsoluteUri) { $location } else { New-Object Uri($currentUri, $location) }
            }
            finally {
                if ($null -ne $response) {
                    $response.Dispose()
                }
                $request.Dispose()
            }
        }
    }
    catch {
        $errorText = Protect-ErrorText $_.Exception.GetBaseException().Message
    }
    finally {
        $client.Dispose()
        $handler.Dispose()
        $watch.Stop()
    }

    return [PSCustomObject]@{
        Success = ($null -eq $errorText -and $null -ne $finalStatus)
        FinalStatus = $finalStatus
        RedirectChain = $chain
        ClockSkewSeconds = $clockSkewSeconds
        DurationMs = $watch.ElapsedMilliseconds
        Error = $errorText
    }
}

function Get-UnexpectedRedirectHosts {
    param(
        [Parameter(Mandatory = $true)][object[]]$Endpoints,
        [Parameter(Mandatory = $true)][string[]]$AllowedHosts
    )

    $unexpected = @()
    foreach ($endpoint in $Endpoints) {
        foreach ($hop in @($endpoint.Http.RedirectChain)) {
            $redirectHost = [string]$hop.RedirectHost
            if ([string]::IsNullOrWhiteSpace($redirectHost)) {
                continue
            }

            $allowed = $false
            foreach ($allowedHost in $AllowedHosts) {
                if ($redirectHost.Equals($allowedHost, [StringComparison]::OrdinalIgnoreCase) -or
                    $redirectHost.EndsWith("." + $allowedHost, [StringComparison]::OrdinalIgnoreCase)) {
                    $allowed = $true
                    break
                }
            }

            if (-not $allowed) {
                $unexpected += $redirectHost
            }
        }
    }

    return @($unexpected | Sort-Object -Unique)
}

function Get-Diagnosis {
    param(
        [Parameter(Mandatory = $true)][object[]]$Endpoints,
        [Parameter(Mandatory = $true)][object]$ProxySummary,
        [Parameter(Mandatory = $true)][string[]]$AllowedRedirectHosts
    )

    $recommendations = @()
    $category = "HealthyPreLoginPath"
    $headline = "The pre-login network path looks healthy."
    $unexpectedRedirectHosts = @(Get-UnexpectedRedirectHosts -Endpoints $Endpoints -AllowedHosts $AllowedRedirectHosts)

    if (@($Endpoints | Where-Object { -not $_.Dns.Success }).Count -gt 0) {
        $category = "Dns"
        $headline = "One or more school hostnames did not resolve."
        $recommendations += "Compare System and Direct diagnostics, then try a trusted DNS resolver or contact the network administrator."
    }
    elseif (@($Endpoints | Where-Object { -not $_.Tcp443.Success }).Count -gt 0) {
        $category = "NetworkOrFirewall"
        $headline = "DNS worked, but TCP port 443 could not be reached."
        $recommendations += "Check firewall, captive portal, VPN, proxy, and regional routing. Do not disable endpoint protection globally."
    }
    elseif (@($Endpoints | Where-Object { -not $_.Tls.Success }).Count -gt 0) {
        $category = "Tls"
        $headline = "The TLS handshake or certificate validation failed."
        $recommendations += "Check the system clock and trusted network path. Do not install untrusted root certificates as a workaround."
    }
    elseif (@($Endpoints | Where-Object { -not $_.Http.Success }).Count -gt 0) {
        $category = "HttpTransport"
        $headline = "HTTPS connected, but an HTTP request failed."
        $recommendations += "Compare System and Direct modes and include the sanitized report when contacting IT."
    }
    elseif ($unexpectedRedirectHosts.Count -gt 0) {
        $category = "CaptivePortalOrInterception"
        $headline = "A request was redirected outside the expected school or identity-provider chain."
        $recommendations += "Sign in to any hotel, airport, or campus captive portal, then rerun the diagnosis."
        $recommendations += "If no captive portal is present, review proxy, DNS filtering, and HTTPS inspection."
    }
    else {
        $statuses = @($Endpoints | ForEach-Object { $_.Http.FinalStatus })
        if (@($statuses | Where-Object { $_ -eq 407 }).Count -gt 0) {
            $category = "ProxyAuthentication"
            $headline = "A proxy requires authentication."
            $recommendations += "Use the Direct isolated mode or sign in to the organization proxy."
        }
        elseif (@($statuses | Where-Object { $_ -eq 401 -or $_ -eq 403 -or $_ -eq 451 }).Count -gt 0) {
            $category = "AccessPolicy"
            $headline = "A gateway or server denied the pre-login request."
            $recommendations += "Ask XJTLU IT to check WAF/PASG geo-IP and access-policy logs for the report timestamp."
        }
        elseif (@($statuses | Where-Object { $_ -eq 429 }).Count -gt 0) {
            $category = "RateLimit"
            $headline = "The service is rate limiting this connection."
            $recommendations += "Wait before retrying and ask IT to review the source network if the limit persists."
        }
        elseif (@($statuses | Where-Object { $_ -ge 500 }).Count -gt 0) {
            $category = "SchoolService"
            $headline = "A school or identity service returned a server error."
            $recommendations += "Retry later and report the timestamp to XJTLU IT."
        }
        else {
            $recommendations += "Use the isolated browser first; it avoids extension, cookie, storage, and stale-profile conflicts."
        }
    }

    $clockSkews = @($Endpoints | ForEach-Object { $_.Http.ClockSkewSeconds } | Where-Object { $null -ne $_ })
    if ($clockSkews.Count -gt 0 -and (($clockSkews | Measure-Object -Maximum).Maximum -gt 300)) {
        $recommendations += "The local clock differs from a server by more than five minutes; synchronize Windows time before SSO."
    }

    if ($ProxySummary.WindowsProxyEnabled -or $ProxySummary.PacConfigured -or $ProxySummary.ProxyEnvironmentVariablesPresent.Count -gt 0) {
        $recommendations += "A proxy signal is present. Compare System and Direct modes without changing the global proxy."
    }
    if ($ProxySummary.ActiveVpnTechnologyHints.Count -gt 0) {
        $recommendations += "A VPN-like adapter is active. Direct browser mode cannot bypass TUN-level VPN routing; compare with the official campus VPN or a normal network."
    }

    return [PSCustomObject]@{
        Category = $category
        Headline = $headline
        UnexpectedRedirectHosts = $unexpectedRedirectHosts
        Recommendations = @($recommendations | Sort-Object -Unique)
    }
}

function Invoke-Diagnosis {
    param(
        [Parameter(Mandatory = $true)][object]$ServiceDefinition,
        [Parameter(Mandatory = $true)][ValidateSet("System", "Direct")][string]$Mode,
        [string]$ReportDirectory,
        [switch]$DoNotOpen
    )

    if ([string]::IsNullOrWhiteSpace($ReportDirectory)) {
        $ReportDirectory = $script:DefaultReportRoot
    }
    New-DirectoryIfMissing -Path $ReportDirectory

    $proxySummary = Get-ProxySummary
    $endpointResults = @()

    foreach ($probeUrl in @($ServiceDefinition.probeUrls)) {
        $uri = [Uri]$probeUrl
        Write-Host "Checking $($uri.Host)..."

        $dns = Test-DnsEndpoint -HostName $uri.Host
        $tcp = if ($dns.Success) { Test-TcpEndpoint -HostName $uri.Host } else { [PSCustomObject]@{ Success = $false; DurationMs = 0; Error = "Skipped because DNS failed." } }
        $tls = if ($tcp.Success) { Test-TlsEndpoint -HostName $uri.Host } else { [PSCustomObject]@{ Success = $false; Protocol = $null; CertificateIssuer = $null; CertificateExpiresUtc = $null; DurationMs = 0; Error = "Skipped because TCP failed." } }
        $http = if ($tls.Success) { Test-HttpEndpoint -Uri $uri -Mode $Mode } else { [PSCustomObject]@{ Success = $false; FinalStatus = $null; RedirectChain = @(); ClockSkewSeconds = $null; DurationMs = 0; Error = "Skipped because TLS failed." } }

        $endpointResults += [PSCustomObject]@{
            Url = Get-SanitizedUri -Uri $uri
            Host = $uri.Host
            Dns = $dns
            Tcp443 = $tcp
            Tls = $tls
            Http = $http
        }
    }

    $diagnosis = Get-Diagnosis -Endpoints $endpointResults -ProxySummary $proxySummary -AllowedRedirectHosts @($ServiceDefinition.allowedRedirectHosts)
    $browsers = @(Get-InstalledChromiumBrowsers | ForEach-Object {
        [PSCustomObject]@{ Name = $_.Name; Version = $_.Version }
    })

    $reportId = [Guid]::NewGuid().ToString("N")
    $createdAt = Get-Date
    $report = [PSCustomObject]@{
        ReportSchemaVersion = 1
        ReportId = $reportId
        App = [PSCustomObject]@{ Name = $script:AppName; Version = $script:AppVersion }
        CreatedAtLocal = $createdAt.ToString("o")
        TimeZone = [TimeZoneInfo]::Local.Id
        Privacy = "No credentials, cookies, browser history, public IP, Wi-Fi name, MAC address, or OAuth/SAML query parameters are collected."
        System = [PSCustomObject]@{
            OsVersion = [Environment]::OSVersion.VersionString
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            Browsers = $browsers
        }
        Service = [PSCustomObject]@{ Id = $ServiceDefinition.id; Name = $ServiceDefinition.name }
        NetworkMode = $Mode
        ProxyAndVpnSignals = $proxySummary
        Endpoints = $endpointResults
        Diagnosis = $diagnosis
    }

    $baseName = "xjtlu-access-{0}-{1}" -f $createdAt.ToString("yyyyMMdd-HHmmss"), $reportId.Substring(0, 8)
    $jsonPath = Join-Path $ReportDirectory ($baseName + ".json")
    $textPath = Join-Path $ReportDirectory ($baseName + ".txt")

    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $lines = New-Object Collections.Generic.List[string]
    $lines.Add("$($script:AppName) $($script:AppVersion)")
    $lines.Add("Report ID: $reportId")
    $lines.Add("Created: $($report.CreatedAtLocal) ($($report.TimeZone))")
    $lines.Add("Service: $($report.Service.Name)")
    $lines.Add("Network mode: $Mode")
    $lines.Add("")
    $lines.Add("Result: $($diagnosis.Headline)")
    $lines.Add("Category: $($diagnosis.Category)")
    $lines.Add("")
    $lines.Add("Endpoint checks:")
    foreach ($endpoint in $endpointResults) {
        $lines.Add("- $($endpoint.Url)")
        $lines.Add("  DNS=$($endpoint.Dns.Success) TCP443=$($endpoint.Tcp443.Success) TLS=$($endpoint.Tls.Success) HTTP=$($endpoint.Http.FinalStatus)")
        if (-not [string]::IsNullOrWhiteSpace($endpoint.Http.Error)) {
            $lines.Add("  Error=$($endpoint.Http.Error)")
        }
    }
    $lines.Add("")
    $lines.Add("Recommendations:")
    foreach ($recommendation in @($diagnosis.Recommendations)) {
        $lines.Add("- $recommendation")
    }
    $lines.Add("")
    $lines.Add("Privacy: $($report.Privacy)")
    $lines | Set-Content -LiteralPath $textPath -Encoding UTF8

    Write-Host ""
    Write-Host $diagnosis.Headline
    Write-Host "Text report: $textPath"
    Write-Host "JSON report: $jsonPath"

    if (-not $DoNotOpen) {
        Start-Process -FilePath "notepad.exe" -ArgumentList @($textPath) | Out-Null
    }

    return $report
}

function Reset-IsolatedProfiles {
    param([switch]$SkipConfirmation)

    $target = [IO.Path]::GetFullPath($script:ProfileRoot)
    $expected = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "XJTLU-Access-Helper\Profiles"))
    if ($target -ne $expected) {
        throw "Refusing to reset an unexpected path: $target"
    }

    if (-not (Test-Path -LiteralPath $target)) {
        Write-Host "No isolated profiles exist."
        return
    }

    if (-not $SkipConfirmation) {
        Write-Host "Close all XJTLU Access Helper browser windows first."
        Write-Host "This deletes only isolated browser cookies and sessions under:"
        Write-Host $target
        $answer = Read-Host "Type RESET to continue"
        if ($answer -ne "RESET") {
            Write-Host "Reset cancelled."
            return
        }
    }

    Remove-Item -LiteralPath $target -Recurse -Force
    Write-Host "Isolated browser profiles were reset. Main browser data was not touched."
}

function Invoke-SelfTest {
    $config = Get-AppConfig

    $profilePath = [IO.Path]::GetFullPath($script:ProfileRoot)
    $expectedPrefix = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "XJTLU-Access-Helper"))
    if (-not $profilePath.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Profile path escaped the application data root."
    }

    $browsers = @(Get-InstalledChromiumBrowsers)
    Write-Host "Self-test passed. Services=$(@($config.services).Count) Browsers=$($browsers.Count)"
}

function Pause-Menu {
    Write-Host ""
    [void](Read-Host "Press Enter to continue")
}

function Show-MainMenu {
    while ($true) {
        Clear-Host
        Write-Host "$($script:AppName) $($script:AppVersion)"
        Write-Host "No admin rights. No changes to the main browser or global proxy."
        Write-Host ""
        Write-Host "1  Open Learning Mall (isolated, system network)"
        Write-Host "2  Open XJTLU Webmail (isolated, system network)"
        Write-Host "3  Open XJTLU website (isolated, system network)"
        Write-Host "4  Open Learning Mall (isolated, direct/no browser proxy)"
        Write-Host "5  Open XJTLU Webmail (isolated, direct/no browser proxy)"
        Write-Host "6  Diagnose Learning Mall (system network)"
        Write-Host "7  Diagnose Learning Mall (direct network)"
        Write-Host "8  Diagnose XJTLU Webmail (system network)"
        Write-Host "9  Reset isolated browser profiles"
        Write-Host "0  Exit"
        Write-Host ""

        $choice = Read-Host "Choose an option"
        try {
            switch ($choice) {
                "1" { Start-IsolatedBrowser -ServiceDefinition (Get-ServiceDefinition "learning-mall") -Mode "System" }
                "2" { Start-IsolatedBrowser -ServiceDefinition (Get-ServiceDefinition "webmail") -Mode "System" }
                "3" { Start-IsolatedBrowser -ServiceDefinition (Get-ServiceDefinition "main-site") -Mode "System" }
                "4" { Start-IsolatedBrowser -ServiceDefinition (Get-ServiceDefinition "learning-mall") -Mode "Direct" }
                "5" { Start-IsolatedBrowser -ServiceDefinition (Get-ServiceDefinition "webmail") -Mode "Direct" }
                "6" { [void](Invoke-Diagnosis -ServiceDefinition (Get-ServiceDefinition "learning-mall") -Mode "System") }
                "7" { [void](Invoke-Diagnosis -ServiceDefinition (Get-ServiceDefinition "learning-mall") -Mode "Direct") }
                "8" { [void](Invoke-Diagnosis -ServiceDefinition (Get-ServiceDefinition "webmail") -Mode "System") }
                "9" { Reset-IsolatedProfiles }
                "0" { return }
                default { Write-Host "Unknown option." }
            }
        }
        catch {
            Write-Host "Error: $(Protect-ErrorText $_.Exception.GetBaseException().Message)" -ForegroundColor Red
        }
        Pause-Menu
    }
}

try {
    switch ($Action) {
        "Menu" {
            Show-MainMenu
        }
        "Launch" {
            Start-IsolatedBrowser -ServiceDefinition (Get-ServiceDefinition $Service) -Mode $NetworkMode
        }
        "Diagnose" {
            [void](Invoke-Diagnosis -ServiceDefinition (Get-ServiceDefinition $Service) -Mode $NetworkMode -ReportDirectory $OutputDirectory -DoNotOpen:$NoOpenReport)
        }
        "Reset" {
            Reset-IsolatedProfiles -SkipConfirmation:$Force
        }
        "SelfTest" {
            Invoke-SelfTest
        }
    }
}
catch {
    Write-Error (Protect-ErrorText $_.Exception.GetBaseException().Message)
    exit 1
}
