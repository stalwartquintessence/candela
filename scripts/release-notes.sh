#!/bin/bash
# Prints the CHANGELOG.md section for a version (without its heading).
# Usage: scripts/release-notes.sh 0.1.0
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: release-notes.sh <version>}"

NOTES=$(awk -v v="$VERSION" '
    /^## \[/ { inside = index($0, "[" v "]") > 0; next }
    inside
' CHANGELOG.md)

if [ -z "$(echo "$NOTES" | tr -d '[:space:]')" ]; then
    echo "error: CHANGELOG.md has no section for $VERSION" >&2
    exit 1
fi
echo "$NOTES"
