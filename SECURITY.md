# Security policy

## Supported versions

Orca Mini is pre-1.0 software. Security fixes are made on the `main` branch and included in the next release; older builds are not maintained as separate support lines.

## Report a vulnerability

Do not open a public issue for an unpatched vulnerability or include exploit details, credentials, browsing data, or private URLs in a public discussion.

Use GitHub's private vulnerability reporting form:

<https://github.com/srijanshukla18/orca-mini/security/advisories/new>

Include, when possible:

- the affected Orca Mini version or commit
- macOS and hardware versions
- clear reproduction steps
- likely impact and any known mitigations
- logs or screenshots with private data removed

Reports are handled on a best-effort basis. Please allow time to reproduce and assess the issue before public disclosure.

## Scope

Useful reports include vulnerabilities in Orca Mini's application code, browser-data handling, navigation decisions, permissions, downloads, privacy controls, and release pipeline.

Issues in WebKit or macOS itself should also be reported to [Apple Security Research](https://security.apple.com/). Website-specific security issues belong with the affected website.

## Repository safety

- Never commit `.env`, signing certificates, private keys, provisioning profiles, notarization credentials, or exported browser data.
- Treat crash logs, build logs, screenshots, and test fixtures as potentially sensitive.
- Keep Apple release credentials in a local `.env`; `.env.example` contains names only.
- Review `git status` and the staged diff before every commit.
