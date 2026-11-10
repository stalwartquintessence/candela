#!/bin/bash
# Gives GitHub Actions your local signing identity (from scripts/create-signing-identity.sh), so
# every release carries the same signature and macOS keeps the Accessibility permission across
# updates. Run it once on your Mac; CI picks it up through scripts/import-signing-identity.sh.
#
# The identity is exported to a temporary file, uploaded with the GitHub CLI as two encrypted
# repository secrets, and the file is deleted. Nothing is written to the repository.
#
#   SIGNING_IDENTITY_P12        certificate and private key (PKCS#12, base64)
#   SIGNING_IDENTITY_PASSWORD   random password protecting it
#
# Requirements: the GitHub CLI (`gh`), logged in to an account that can change this
# repository's secrets.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

if [ ! -f "$SIGNING_KEYCHAIN" ]; then
    echo "error: no local signing identity. Run ./scripts/create-signing-identity.sh first." >&2
    exit 1
fi
if ! command -v gh >/dev/null; then
    echo "error: the GitHub CLI is required (https://cli.github.com)." >&2
    exit 1
fi
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"; pbcopy < /dev/null' EXIT

security unlock-keychain -p "$(cat "$SIGNING_DIR/keychain-password")" "$SIGNING_KEYCHAIN"
P12_PASSWORD=$(/usr/bin/openssl rand -hex 24)

# macOS asks before a private key leaves a keychain. Its dialog wants the password of the
# signing keychain (a random one, made by create-signing-identity.sh), so put it on the clipboard.
pbcopy < "$SIGNING_DIR/keychain-password"
echo "==> Exporting \"$SIGNING_NAME\""
echo "    If macOS asks for the keychain password, press Cmd-V (it is on your clipboard) and"
echo "    click Allow. The clipboard is cleared afterwards."
security export -k "$SIGNING_KEYCHAIN" -t identities -f pkcs12 -P "$P12_PASSWORD" -o "$WORK/identity.p12"

echo "==> Uploading to $REPO as repository secrets"
base64 -i "$WORK/identity.p12" | gh secret set SIGNING_IDENTITY_P12 --repo "$REPO"
printf '%s' "$P12_PASSWORD" | gh secret set SIGNING_IDENTITY_PASSWORD --repo "$REPO"

echo "==> Done. CI and release builds now sign as \"$SIGNING_NAME\", with this requirement:"
CERT_SHA1=$(security find-certificate -c "$SIGNING_NAME" -Z "$SIGNING_KEYCHAIN" | awk '/SHA-1 hash:/ { print $3 }')
echo "    identifier \"$BUNDLE_ID\" and certificate leaf = H\"$(echo "$CERT_SHA1" | tr 'A-F' 'a-f')\""
