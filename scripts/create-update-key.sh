#!/bin/bash
# Creates the key that signs Candela's updates. Run it once, on your Mac.
#
# - The private key is kept in your login keychain, where Sparkle's tools store it (account
#   "candela"), and uploaded as the encrypted repository secret SPARKLE_PRIVATE_KEY. The release
#   workflow signs every update with it.
# - The public key is written into scripts/config.sh. Commit that change: the app installs only
#   updates signed with the matching private key.
#
# Running it again reuses the key already in your keychain.
#
# Keep a backup of the private key somewhere safe, such as a password manager:
#   "$(./scripts/sparkle-tools.sh)/generate_keys" --account candela -x candela-update-key.txt
# If the key is lost, installed copies can no longer be updated in place, and every user has to
# download the next version by hand.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

ACCOUNT="candela"
if ! command -v gh >/dev/null; then
    echo "error: the GitHub CLI is required (https://cli.github.com)." >&2
    exit 1
fi
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
TOOLS=$(./scripts/sparkle-tools.sh)

echo "==> Creating the update signing key (or reusing the one in your keychain)"
"$TOOLS/generate_keys" --account "$ACCOUNT" >/dev/null
PUBLIC_KEY=$("$TOOLS/generate_keys" --account "$ACCOUNT" -p)
if ! [[ "$PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
    echo "error: unexpected public key from generate_keys: $PUBLIC_KEY" >&2
    exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
"$TOOLS/generate_keys" --account "$ACCOUNT" -x "$WORK/private.key" >/dev/null
echo "==> Uploading the private key to $REPO as the secret SPARKLE_PRIVATE_KEY"
gh secret set SPARKLE_PRIVATE_KEY --repo "$REPO" < "$WORK/private.key"

echo "==> Writing the public key into scripts/config.sh"
sed -i '' "s|^SPARKLE_PUBLIC_KEY=.*|SPARKLE_PUBLIC_KEY=\"\${SPARKLE_PUBLIC_KEY:-$PUBLIC_KEY}\"|" scripts/config.sh
grep '^SPARKLE_PUBLIC_KEY=' scripts/config.sh
echo "==> Done. Commit scripts/config.sh, and back up the private key (see the top of this script)."
