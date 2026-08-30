#!/bin/bash
set -euo pipefail

# Build an ad-hoc-signed Apple-silicon app and DMG without release credentials.
# Public releases must use build.sh so the artifacts are Developer ID signed and notarized.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

for tool in xcodegen xcodebuild codesign hdiutil ditto lipo; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "error: required tool not found: $tool" >&2
        exit 1
    }
done

VERSION=$(awk '/MARKETING_VERSION:/ { print $2; exit }' project.yml)
DERIVED_DATA="$PROJECT_ROOT/build/DerivedData"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/Orca Mini.app"
OUTPUT_APP="$PROJECT_ROOT/build/Orca Mini.app"
DMG_NAME="Orca-Mini-${VERSION}-arm64.dmg"
OUTPUT_DMG="$PROJECT_ROOT/build/$DMG_NAME"
STAGING_DIR=$(mktemp -d /tmp/orca-mini-dmg.XXXXXX)

cleanup() {
    case "$STAGING_DIR" in
        /tmp/orca-mini-dmg.*) rm -rf -- "$STAGING_DIR" ;;
    esac
}
trap cleanup EXIT

mkdir -p build
if [[ "${ORCA_CLEAN_BUILD:-0}" == "1" ]]; then
    rm -rf "$DERIVED_DATA"
fi
rm -rf "$OUTPUT_APP"
rm -f "$OUTPUT_DMG"

echo "Generating Xcode project..."
xcodegen

echo "Building Orca Mini ${VERSION} for Apple silicon..."
BUILD_COMMAND=(
    xcodebuild build
    -scheme ora
    -destination "platform=macOS,arch=arm64"
    -configuration Release
    -derivedDataPath "$DERIVED_DATA"
    ARCHS=arm64
    ONLY_ACTIVE_ARCH=YES
    CODE_SIGN_IDENTITY=
    CODE_SIGNING_REQUIRED=NO
)

if command -v xcbeautify >/dev/null 2>&1; then
    set -o pipefail
    "${BUILD_COMMAND[@]}" | xcbeautify
else
    "${BUILD_COMMAND[@]}"
fi

[[ -d "$BUILT_APP" ]] || {
    echo "error: build did not produce $BUILT_APP" >&2
    exit 1
}

echo "Ad-hoc signing local build..."
codesign --force --deep --sign - --identifier com.orabrowser.app "$BUILT_APP"
codesign --verify --deep --strict --verbose=2 "$BUILT_APP"

ARCHITECTURES=$(lipo -archs "$BUILT_APP/Contents/MacOS/Orca Mini")
[[ "$ARCHITECTURES" == "arm64" ]] || {
    echo "error: expected arm64 executable, found: $ARCHITECTURES" >&2
    exit 1
}

ditto "$BUILT_APP" "$OUTPUT_APP"
ditto "$BUILT_APP" "$STAGING_DIR/Orca Mini.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "Creating $DMG_NAME..."
hdiutil create \
    -volname "Orca Mini" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$OUTPUT_DMG"

hdiutil verify "$OUTPUT_DMG"

echo ""
echo "Local build complete:"
echo "  App: $OUTPUT_APP"
echo "  DMG: $OUTPUT_DMG"
echo "  SHA-256: $(shasum -a 256 "$OUTPUT_DMG" | awk '{print $1}')"
echo ""
echo "This local artifact is ad-hoc signed and is not notarized."
