#!/bin/bash
# Builds the app and produces release artifacts in dist/: a zip, a dmg and SHA-256 checksums.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

./scripts/build-app.sh

ZIP="dist/$APP_NAME-$VERSION.zip"
DMG="dist/$APP_NAME-$VERSION.dmg"
rm -f "$ZIP" "$DMG" dist/SHA256SUMS.txt

echo "==> Creating $ZIP"
ditto -c -k --sequesterRsrc --keepParent "dist/$APP_NAME.app" "$ZIP"

echo "==> Creating $DMG"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "dist/$APP_NAME.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

(cd dist && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > SHA256SUMS.txt)
echo "==> Release artifacts:"
ls -lh "$ZIP" "$DMG" dist/SHA256SUMS.txt
