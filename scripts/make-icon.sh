#!/bin/bash
# Regenerates Resources/AppIcon.icns from scripts/IconRenderer.swift.
# Only needed when the artwork changes; the generated .icns is committed.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

swift scripts/IconRenderer.swift "$WORK/icon_1024.png"

for size in 16 32 128 256 512; do
    sips -z $size $size "$WORK/icon_1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$WORK/icon_1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

mkdir -p Resources
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
cp "$WORK/icon_1024.png" Resources/AppIcon-1024.png
echo "Wrote Resources/AppIcon.icns and Resources/AppIcon-1024.png"
