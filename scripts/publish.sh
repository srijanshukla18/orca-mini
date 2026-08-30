#!/bin/bash
set -euo pipefail

# publish.sh — Generate a changelog and create a GitHub release.
#
# Usage: ./scripts/publish.sh
#
# Expects build/Orca-Mini-<version>-arm64.dmg to exist (run build.sh first).
# Reads version from project.yml.
# Optional changelog env vars:
#   ORCA_CHANGELOG_MODEL   Override the Codex model used for changelog rewriting
#   ORCA_CHANGELOG_REVIEW  Set to 1 to open generated notes in $EDITOR
#   ORCA_CHANGELOG_NO_LLM  Set to 1 to force deterministic fallback notes

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

REPO="${ORCA_GITHUB_REPOSITORY:-srijanshukla18/browser}"

VERSION=$(grep "MARKETING_VERSION:" project.yml | sed 's/.*MARKETING_VERSION: //' | tr -d ' ')
DMG_NAME="Orca-Mini-${VERSION}-arm64.dmg"
DMG_FILE="build/${DMG_NAME}"
CHECKSUM_FILE="${DMG_FILE}.sha256"
CHANGELOG_DIR="build/release-notes"
CHANGELOG_FILE="${CHANGELOG_DIR}/Orca-Mini-${VERSION}.md"

[[ -f "$DMG_FILE" ]] || die "DMG not found at $DMG_FILE. Run ./scripts/build.sh first."

rm -rf "$CHANGELOG_DIR"
mkdir -p "$CHANGELOG_DIR"

# --- Changelog generation ---

step "Generating changelog"

LAST_TAG=$(git describe --tags --abbrev=0 --exclude "v$VERSION" 2>/dev/null || true)
[[ -n "$LAST_TAG" ]] || die "No previous tag found. Create a release tag before publishing."

CHANGELOG_ARGS=(
    "$SCRIPT_DIR/generate-changelog.py"
    "$LAST_TAG"
    "v$VERSION"
    "$REPO"
    --output-markdown "$CHANGELOG_FILE"
)

[[ "${ORCA_CHANGELOG_REVIEW:-0}" == "1" ]] && CHANGELOG_ARGS+=(--review)
[[ "${ORCA_CHANGELOG_NO_LLM:-0}" == "1" ]] && CHANGELOG_ARGS+=(--no-llm)

python3 "${CHANGELOG_ARGS[@]}"

(
    cd build
    shasum -a 256 "$DMG_NAME" > "${DMG_NAME}.sha256"
)

# --- Commit & push ---

step "Committing & pushing"

git add project.yml
git commit -m "chore(release): v$VERSION"
git push origin main

# --- GitHub Release ---

step "GitHub release"

if gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then
    gh release edit "v$VERSION" \
        --repo "$REPO" \
        --title "v$VERSION" \
        --notes-file "$CHANGELOG_FILE"
    gh release upload "v$VERSION" "$DMG_FILE" "$CHECKSUM_FILE" --repo "$REPO" --clobber
else
    gh release create "v$VERSION" "$DMG_FILE" "$CHECKSUM_FILE" \
        --repo "$REPO" \
        --title "v$VERSION" \
        --notes-file "$CHANGELOG_FILE"
fi

echo "Release: https://github.com/$REPO/releases/tag/v$VERSION"

green "Published!"
