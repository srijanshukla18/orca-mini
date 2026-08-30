# Releasing Orca Mini

This document covers public Apple-silicon releases. Orca Mini supports unsigned community releases and optional Developer ID signed and notarized releases.

## Unsigned release

Unsigned releases require a clean `main` branch, an authenticated GitHub CLI, and the local build requirements from the README.

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, then commit and push the version change.
2. Run `./scripts/build-local.sh`.
3. Verify the app contains `LICENSE` and `THIRD_PARTY_NOTICES.md`, the executable is arm64-only, and the DMG passes `hdiutil verify`.
4. Tag the exact source commit and publish the DMG plus its SHA-256 checksum on GitHub.
5. Label the release unsigned and include the right-click **Open** Gatekeeper instructions.

## Signed and notarized release

## Release requirements

- A clean `main` branch at the commit to be released
- Apple Developer ID Application certificate
- Developer ID provisioning profile for the application bundle ID
- A configured `notarytool` keychain profile
- Authenticated GitHub CLI access to `srijanshukla18/orca-mini`
- `xcodegen`, `create-dmg`, `xcbeautify`, and `gh`

Copy `.env.example` to `.env` and fill in the local values. Never commit `.env`, certificates, profiles, passwords, or notarization output containing account data.

## Preflight

1. Confirm `git status --short` is empty.
2. Confirm `THIRD_PARTY_NOTICES.md` matches `project.yml` and the resolved Swift packages.
3. Confirm user-facing documentation matches the release.
4. Run the Apple-silicon test suite:

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

## Build and publish

```bash
./scripts/release.sh 0.2.15
```

The release script:

1. updates the marketing and build versions
2. archives an arm64 Release build
3. signs and notarizes the application and DMG
4. generates release notes
5. commits and pushes the version change
6. creates the matching GitHub tag and release
7. uploads the DMG and its SHA-256 checksum

Set `ORCA_GITHUB_REPOSITORY=owner/repository` only when testing the release flow in another fork.

## GPL release check

Every distributed DMG must correspond to the source at its release tag. Before announcing a release, verify that:

- the GitHub tag resolves to the commit used to build the DMG
- GitHub's source archives are available from the release page
- `LICENSE` and `THIRD_PARTY_NOTICES.md` are present in the app bundle
- the DMG and `.sha256` files are both attached
- the release notes identify Orca Mini as a modified Ora Browser fork

## Post-release verification

```bash
gh release view "v0.2.15" --repo srijanshukla18/orca-mini
hdiutil verify "build/Orca-Mini-0.2.15-arm64.dmg"
(cd build && shasum -a 256 -c "Orca-Mini-0.2.15-arm64.dmg.sha256")
codesign --verify --deep --strict --verbose=2 "build/Orca Mini.app"
spctl --assess --type open --context context:primary-signature --verbose=2 \
  "build/Orca-Mini-0.2.15-arm64.dmg"
```
