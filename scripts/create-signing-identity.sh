#!/bin/bash
# Creates a free, self-signed code signing identity for local builds, so macOS keeps the
# Accessibility permission across rebuilds (an ad-hoc signature changes with every build).
#
# The identity lives in its own keychain under ~/Library/Application Support/Candela Signing.
# Nothing is added to your login keychain, no trust settings are changed and no password prompt
# appears. scripts/build-app.sh finds and uses it automatically.
#
# Remove it any time with:  rm -rf "$HOME/Library/Application Support/Candela Signing"
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

if [ -f "$SIGNING_KEYCHAIN" ]; then
    echo "Signing identity already exists: $SIGNING_KEYCHAIN"
    exit 0
fi

OPENSSL=/usr/bin/openssl # macOS LibreSSL: its PKCS#12 output is what `security import` expects
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $SIGNING_NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

echo "==> Generating a self-signed code signing certificate ($SIGNING_NAME, valid 10 years)"
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cert.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
P12_PASSWORD=$("$OPENSSL" rand -hex 16)
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$SIGNING_NAME" \
    -out "$WORK/identity.p12" -passout "pass:$P12_PASSWORD"

echo "==> Creating keychain $SIGNING_KEYCHAIN"
mkdir -p "$SIGNING_DIR"
chmod 700 "$SIGNING_DIR"
KEYCHAIN_PASSWORD=$("$OPENSSL" rand -hex 24)
umask 077
printf '%s' "$KEYCHAIN_PASSWORD" > "$SIGNING_DIR/keychain-password"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN"
security set-keychain-settings "$SIGNING_KEYCHAIN" # no auto-lock timeout
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN"
security import "$WORK/identity.p12" -k "$SIGNING_KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign >/dev/null
# Let codesign use the key without a keychain access dialog.
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN" >/dev/null

echo "==> Done. Identity:"
security find-identity -p codesigning "$SIGNING_KEYCHAIN" | grep "$SIGNING_NAME"
echo "    (\"CSSMERR_TP_NOT_TRUSTED\" is expected and fine: macOS permissions only need a stable signature.)"
echo "    Next: ./scripts/build-app.sh"
