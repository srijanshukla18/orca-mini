<div align="center">
  <h1>Orca Mini</h1>
  <p>A fast, stripped-down WebKit browser for Apple silicon Macs.</p>
</div>

<p align="center">
  <a href="https://www.apple.com/macos/"><img src="https://badgen.net/badge/macOS/15+/blue" alt="macOS 15+"></a>
  <a href="https://support.apple.com/116943"><img src="https://badgen.net/badge/CPU/Apple%20silicon/black" alt="Apple silicon"></a>
  <a href="https://developer.apple.com/documentation/webkit"><img src="https://badgen.net/badge/Engine/WebKit/blue" alt="WebKit"></a>
  <a href="LICENSE"><img src="https://badgen.net/badge/License/GPL-3.0/green" alt="GPL-3.0"></a>
</p>

Orca Mini is an opinionated fork of [Ora Browser](https://github.com/the-ora/browser). It keeps the parts needed for everyday browsing and removes product surface that adds background work, memory use, or interface noise.

The browser uses the WebKit framework built into macOS. It does not bundle or maintain a separate rendering engine.

> [!IMPORTANT]
> Orca Mini is pre-1.0 software. Keep another browser installed while evaluating it.

## What stays

- Native SwiftUI and AppKit interface
- System WebKit rendering through `WKWebView`
- Vertical tabs, pinned tabs, session restore, and inactive-tab suspension
- One persistent browsing profile with shared history and cookies
- Isolated private windows
- Split-view browsing
- Downloads, history, browser-data import, and find in page
- Content blocking, custom filter lists, tracker protection, and cookie controls
- Custom search engines and keyboard shortcuts
- Safari Web Inspector through <kbd>Command</kbd>+<kbd>Shift</kbd>+<kbd>I</kbd>

## Deliberately left out

- Multiple profile/space management
- A separate favorites system; pinned tabs cover that job
- Password-manager and autofill overlays
- Global media controls and automatic picture-in-picture
- Fingerprint or user-agent spoofing
- A bundled extension platform or auto-updater

## Install

Apple-silicon DMGs are published on the [Releases](https://github.com/srijanshukla18/orca-mini/releases) page and named `Orca-Mini-<version>-arm64.dmg`.

Current releases are unsigned. After copying Orca Mini to Applications, right-click it and choose **Open**, then confirm **Open**. A future Developer ID build may remove this Gatekeeper confirmation, but the browser does not require an Apple developer account to build or use.

## Build locally

Requirements:

- Apple silicon Mac running macOS 15 or later
- Xcode 16 or later
- [Homebrew](https://brew.sh/)

```bash
git clone https://github.com/srijanshukla18/orca-mini.git
cd orca-mini
./scripts/setup.sh
./scripts/build-local.sh
```

The local build script creates:

```text
build/Orca Mini.app
build/Orca-Mini-<version>-arm64.dmg
```

It reuses Xcode build data on later runs. Set `ORCA_CLEAN_BUILD=1` when you explicitly want a cold rebuild.

To work in Xcode instead:

```bash
open Ora.xcodeproj
```

`Ora` remains the internal Xcode project and Swift module name for compatibility with the upstream code and existing local browser data. The shipped product name is Orca Mini.

## Test

```bash
xcodegen
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

## Project map

- `ora/App` — application lifecycle and macOS commands
- `ora/Core/BrowserEngine` — the small WebKit abstraction
- `ora/Features` — tabs, browsing, downloads, privacy, settings, and import
- `oraTests` — browser-host and behavior tests
- `project.yml` — XcodeGen source of truth
- `scripts` — setup, local packaging, and maintainer release tooling

## Privacy and inspection

Orca Mini lets WebKit report its native browser identity. It does not inject navigator, canvas, audio, screen, or WebGL fingerprint overrides. Content blocking and cookie controls use WebKit-native mechanisms.

Web pages can be inspected with Safari Web Inspector from the Developer menu or with <kbd>Command</kbd>+<kbd>Shift</kbd>+<kbd>I</kbd>.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and pull-request guidance. Please report security issues privately using [SECURITY.md](SECURITY.md).

## Attribution and license

Orca Mini is derived from [the-ora/browser](https://github.com/the-ora/browser) and contains work by its contributors. Changes made for Orca Mini are documented in this repository's history. Orca Mini is an independent fork and is not endorsed by the upstream project.

The project is distributed under the [GNU General Public License v3.0](LICENSE). A binary release must have matching source available under GPLv3. Dependency and bundled-code notices are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
