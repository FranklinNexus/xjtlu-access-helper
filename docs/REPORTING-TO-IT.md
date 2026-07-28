# Reporting an access problem to XJTLU IT

Attach the generated `.txt` report after reviewing it. Keep the `.json` report
for engineering escalation when requested.

## Suggested message

```text
Subject: Unable to access [Learning Mall Core / XJTLU Webmail]

Time of failure (with time zone):
Country/region and network type (home/mobile/campus/hotel):
Visible error or HTTP status:
Does the isolated System mode work? [Yes/No]
Does the isolated Direct mode work? [Yes/No/Not tested]
Does the problem occur on another network? [Yes/No/Not tested]

Please check the WAF/PASG, reverse proxy, identity provider, SAML/OIDC callback,
and geo-IP/access-policy logs for the attached report timestamp and Report ID.

The attached report is generated before credentials are entered and excludes
passwords, MFA codes, cookies, browser history, public IP lookup, and OAuth/SAML
query parameters.
```

## Before sharing screenshots

Redact the username, email address, QR codes, MFA prompts, request parameters,
authorization codes, session IDs, and browser bookmarks. Do not record the
password field or send recovery codes.

## Useful server-side checks

- Confirm GET and POST are permitted across the complete redirect/callback
  chain, not only the public landing page.
- Correlate WAF/PASG, load-balancer, origin, SAML/OIDC, and Microsoft sign-in
  logs using the same timestamp.
- Check geo-IP classification for IPv4 and IPv6 egress addresses.
- Verify `Secure` and `SameSite` cookie behavior during cross-site callbacks.
- Check clock synchronization on the identity provider and service provider.
- Return an explicit error page and request ID instead of an infinite spinner.
- Provide an official remote-access VPN or ZTNA path rather than relying on a
  student's changing residential IP allowlist.
