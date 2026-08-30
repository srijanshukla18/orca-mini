# Contributing to Orca Mini

Orca Mini is intentionally small. Contributions should improve browsing, compatibility, stability, performance, accessibility, or maintainability without rebuilding the product surface that this fork removed.

## Before you start

- Search existing issues and pull requests.
- Open an issue before investing in a large feature or architecture change.
- Keep pull requests focused and explain their user-visible cost as well as their benefit.
- Do not add analytics, telemetry, remote configuration, or a new background service without prior discussion.

## Requirements

- Apple silicon Mac running macOS 15 or later
- Xcode 16 or later
- Homebrew

## Setup

```bash
git clone https://github.com/srijanshukla18/orca-mini.git
cd browser
./scripts/setup.sh
open Ora.xcodeproj
```

The setup script installs the development tools, installs local git hooks, and generates `Ora.xcodeproj` from `project.yml`.

## Development workflow

1. Create a branch from `main`.
2. Change `project.yml`, not the generated Xcode project, when editing project configuration.
3. Follow the existing SwiftUI, AppKit, WebKit, and SwiftData patterns.
4. Add or update tests when behavior changes.
5. Run the checks below before opening a pull request.

```bash
set -o pipefail
xcodebuild test \
  -scheme ora \
  -destination 'platform=macOS,arch=arm64' \
  -configuration Debug \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY='' \
  CODE_SIGNING_REQUIRED=NO | xcbeautify
```

Use `./scripts/build-local.sh` when you need an installable development DMG. It produces an ad-hoc-signed local artifact; maintainers use the notarized release flow described in [docs/RELEASING.md](docs/RELEASING.md).

## Pull requests

Each pull request should:

- explain what changed and why
- reference related issues when applicable
- include screenshots or recordings for interface changes, with private browsing data removed
- call out CPU, memory, storage, network, or startup impact when relevant
- stay scoped to one coherent change
- preserve GPLv3 notices and update `THIRD_PARTY_NOTICES.md` when adding bundled code or dependencies

## Project principles

- Prefer native WebKit and macOS APIs over page polling or injected scripts.
- Avoid changing the native WebKit user agent or browser fingerprint.
- Keep one persistent profile plus isolated private browsing.
- Keep pinned tabs and split-view browsing.
- Treat background observers, timers, and network work as costs that need justification.
- Do not edit historical database migrations if migrations are introduced later; add forward-only migrations.

## AI assistance

If AI assistance materially contributed code, documentation, issue content, or a pull-request description, disclose its use. Contributors remain responsible for understanding, testing, and licensing everything they submit.

## Security and conduct

- Never commit credentials, signing keys, profiles, browser data, or private screenshots.
- Read [SECURITY.md](SECURITY.md) before reporting a vulnerability.
- Follow [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
