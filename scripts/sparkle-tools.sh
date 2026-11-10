#!/bin/bash
# Prints the folder with Sparkle's command line tools (sign_update, generate_keys), downloading
# them first if needed. The archive must match the SHA-256 pinned in scripts/config.sh, and its
# version must match the Sparkle version Package.swift builds the app with.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

if ! grep -q "exact: \"$SPARKLE_VERSION\"" Package.swift; then
    echo "error: Package.swift does not pin Sparkle $SPARKLE_VERSION; keep it and scripts/config.sh in step." >&2
    exit 1
fi

DIR="$PWD/.build/sparkle-tools/$SPARKLE_VERSION"
if [ ! -x "$DIR/bin/sign_update" ] || [ ! -x "$DIR/bin/generate_keys" ]; then
    WORK=$(mktemp -d)
    trap 'rm -rf "$WORK"' EXIT
    ARCHIVE="$WORK/Sparkle-$SPARKLE_VERSION.tar.xz"
    echo "Downloading Sparkle $SPARKLE_VERSION tools" >&2
    curl -sSfL -o "$ARCHIVE" \
        "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
    if ! echo "$SPARKLE_TOOLS_SHA256  $ARCHIVE" | shasum -a 256 -c - >/dev/null 2>&1; then
        echo "error: the Sparkle $SPARKLE_VERSION archive does not match the pinned SHA-256" >&2
        exit 1
    fi
    mkdir "$WORK/x"
    tar -xJf "$ARCHIVE" -C "$WORK/x" ./bin
    rm -rf "$DIR"
    mkdir -p "$DIR"
    mv "$WORK/x/bin" "$DIR/bin"
fi
echo "$DIR/bin"
