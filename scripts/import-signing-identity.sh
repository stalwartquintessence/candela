#!/bin/bash
# For GitHub Actions: imports the signing identity stored by scripts/export-signing-identity.sh
# (secrets SIGNING_IDENTITY_P12 and SIGNING_IDENTITY_PASSWORD, passed in as environment
# variables) into a temporary keychain, and tells the later build steps to sign with it.
#
# Without the secrets, for example in pull requests from forks, it does nothing and the build is
# signed ad-hoc. With --required it fails instead, so a release is never signed ad-hoc by mistake.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

if [ -z "${SIGNING_IDENTITY_P12:-}" ] || [ -z "${SIGNING_IDENTITY_PASSWORD:-}" ]; then
    if [ "${1:-}" = "--required" ]; then
        echo "::error::Secrets SIGNING_IDENTITY_P12 and SIGNING_IDENTITY_PASSWORD are not set. Run ./scripts/export-signing-identity.sh once on your Mac."
        exit 1
    fi
    echo "No signing secrets available, the build will be signed ad-hoc."
    exit 0
fi

DIR="${RUNNER_TEMP:?this script is meant for GitHub Actions}"
KEYCHAIN="$DIR/signing.keychain-db"
KEYCHAIN_PASSWORD=$(/usr/bin/openssl rand -hex 24)

trap 'rm -f "$DIR/identity.p12"' EXIT
printf '%s' "$SIGNING_IDENTITY_P12" | base64 --decode > "$DIR/identity.p12"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN" # no auto-lock timeout
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$DIR/identity.p12" -k "$KEYCHAIN" -P "$SIGNING_IDENTITY_PASSWORD" -T /usr/bin/codesign >/dev/null
# Let codesign use the key without a keychain access dialog.
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null

# codesign --keychain still needs the keychain on the user's search list (macOS 26 reports
# "no identity found" otherwise), so put it first, keeping the existing ones.
SEARCH_LIST=()
while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}" # trim leading spaces
    line="${line#\"}"
    SEARCH_LIST+=("${line%\"}")
done < <(security list-keychains -d user)
security list-keychains -d user -s "$KEYCHAIN" ${SEARCH_LIST[@]+"${SEARCH_LIST[@]}"}

security find-identity -p codesigning "$KEYCHAIN"
if ! security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$SIGNING_NAME\""; then
    echo "::error::The secret holds no code signing identity named \"$SIGNING_NAME\"."
    exit 1
fi

# scripts/build-app.sh signs with these.
{
    echo "CODESIGN_IDENTITY=$SIGNING_NAME"
    echo "CODESIGN_KEYCHAIN=$KEYCHAIN"
} >> "${GITHUB_ENV:?this script is meant for GitHub Actions}"
echo "Imported the signing identity \"$SIGNING_NAME\"."
