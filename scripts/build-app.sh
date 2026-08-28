#!/bin/bash
# Builds dist/Candela.app and dist/candelactl.
#
# Signing: the Accessibility permission (needed for the brightness keys) is tied to the code
# signature. An ad-hoc signature changes with every build, so macOS forgets the permission each
# time. Set CODESIGN_IDENTITY to a certificate name, or keep one code signing certificate in your
# keychain and it is used automatically. See docs/DISTRIBUTION.md for a free self-signed one.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

FLAGS=(-c release --arch arm64 ${SWIFT_BUILD_FLAGS[@]+"${SWIFT_BUILD_FLAGS[@]}"})

echo "==> Building $APP_NAME $VERSION ($BUILD_NUMBER)"
swift build "${FLAGS[@]}" --product "$APP_PRODUCT"
swift build "${FLAGS[@]}" --product "$CLI_PRODUCT"
BIN=$(swift build "${FLAGS[@]}" --show-bin-path)

APP="dist/$APP_NAME.app"
rm -rf "$APP" "dist/$CLI_NAME"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/$APP_PRODUCT" "$APP/Contents/MacOS/$APP_NAME"
cp "$BIN/$CLI_PRODUCT" "$APP/Contents/MacOS/$CLI_NAME"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

sed -e "s|__APP_NAME__|$APP_NAME|g" \
    -e "s|__BUNDLE_ID__|$BUNDLE_ID|g" \
    -e "s|__VERSION__|$VERSION|g" \
    -e "s|__BUILD__|$BUILD_NUMBER|g" \
    -e "s|__COPYRIGHT__|$COPYRIGHT|g" \
    Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint -s "$APP/Contents/Info.plist"

# Identity, in order of preference:
#   1. CODESIGN_IDENTITY (optionally with CODESIGN_KEYCHAIN)
#   2. the local identity from scripts/create-signing-identity.sh
#   3. the first valid code signing identity in your keychains
#   4. ad-hoc
IDENTITY="${CODESIGN_IDENTITY:-}"
KEYCHAIN_ARGS=()
if [ -n "$IDENTITY" ] && [ -n "${CODESIGN_KEYCHAIN:-}" ]; then
    KEYCHAIN_ARGS=(--keychain "$CODESIGN_KEYCHAIN")
fi
if [ -z "$IDENTITY" ] && [ -f "$SIGNING_KEYCHAIN" ]; then
    security unlock-keychain -p "$(cat "$SIGNING_DIR/keychain-password")" "$SIGNING_KEYCHAIN"
    IDENTITY="$SIGNING_NAME"
    KEYCHAIN_ARGS=(--keychain "$SIGNING_KEYCHAIN")
fi
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' 'NF > 2 { print $2; exit }' || true)
fi
if [ -z "$IDENTITY" ]; then
    IDENTITY="-"
    echo "warning: no code signing identity found, signing ad-hoc." >&2
    echo "         macOS will ask for the Accessibility permission again after every build." >&2
    echo "         Run ./scripts/create-signing-identity.sh once to fix that (free, local)." >&2
fi

echo "==> Signing with: $([ "$IDENTITY" = "-" ] && echo ad-hoc || echo "$IDENTITY")"
# Nested executables first, then the bundle. Hardened runtime, no entitlements needed.
SIGN=(codesign --force --options runtime ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} --sign "$IDENTITY")
"${SIGN[@]}" "$APP/Contents/MacOS/$CLI_NAME"
"${SIGN[@]}" "$APP"
codesign --verify --strict "$APP"
echo "    designated requirement: $(codesign -dr - "$APP" 2>&1 | sed -n 's/^designated => //p')"

cp "$APP/Contents/MacOS/$CLI_NAME" "dist/$CLI_NAME"
echo "==> Built $APP and dist/$CLI_NAME"
