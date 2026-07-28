# Security Policy

## Design boundaries

XJTLU Access Helper must never collect, log, request, upload, or transmit:

- account names, passwords, MFA codes, recovery codes, or session secrets;
- cookies, browser storage, saved passwords, or browser history;
- OAuth authorization codes, OIDC tokens, SAML requests/responses, or RelayState;
- public IP addresses through third-party lookup services without an explicit,
  separately reviewed feature and user consent;
- Wi-Fi SSIDs, MAC addresses, device names, or unrelated browser/profile data.

The project must not disable antivirus, firewall, certificate validation,
Windows security controls, or global proxy/VPN settings. It must not advertise
geo-IP or access-policy bypasses.

## Reporting a vulnerability

Do not include real credentials, tokens, cookies, or private diagnostic reports
in a public issue. When the project is hosted on GitHub, use a private GitHub
Security Advisory for vulnerabilities involving code execution, data exposure,
unsafe deletion, URL injection, or report redaction.

For other defects, open an issue with synthetic inputs and remove personal or
network-identifying information.

## Release review

Before release:

1. Run `tests/Smoke.Tests.ps1` on Windows PowerShell 5.1 and PowerShell 7.
2. Run live diagnostics against official entry points without credentials.
3. Search generated reports for query strings, account identifiers, tokens,
   user-profile paths, proxy addresses, and environment secrets.
4. Confirm Reset can delete only the dedicated profile root.
5. Review every new Chromium flag and every new endpoint for scope expansion.
