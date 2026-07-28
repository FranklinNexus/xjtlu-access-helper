# Contributing

Contributions should preserve three invariants:

1. No administrator privileges or global security/network changes.
2. No credential, browser-session, or identity-token collection.
3. Every remediation is isolated, reversible, and explicit about its scope.

## Development

Run the local checks:

```powershell
.\tests\Smoke.Tests.ps1
.\XJTLU-Access-Helper.ps1 -Action Diagnose -Service learning-mall -NetworkMode System -NoOpenReport
```

The smoke tests must pass on both Windows PowerShell 5.1 and PowerShell 7.
Network tests are intentionally excluded from CI because live school services
and regional routes are not deterministic.

## Service changes

When changing `services.json`:

- use only official HTTPS entry points;
- list every expected top-level redirect host;
- never commit real OAuth, OIDC, or SAML query parameters;
- verify the sanitized report contains no query or fragment data;
- update both README files when behavior changes.

## Pull requests

Describe the failure mode, the affected layer, the safety scope, test evidence,
and any privacy impact. Avoid bundled refactors that obscure security-relevant
changes.
