#!/usr/bin/env bash
# Creates a self-signed code-signing certificate so package-app.sh can sign
# the app with a STABLE identity. The Input Monitoring (TCC) grant sticks to
# the signature — with a stable one it survives rebuilds; ad-hoc signing
# changes identity every build and silently drops the grant.
#
# Run once:
#   ./scripts/create-signing-cert.sh
#
# No admin/sudo needed. codesign may show a one-time Keychain prompt the
# first time it uses the key — choose "Always Allow".
set -euo pipefail

CERT_NAME="RoBaHUD Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
    echo "Signing certificate '$CERT_NAME' already exists. Nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $CERT_NAME
[v3]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

echo "==> generating self-signed code-signing certificate"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" >/dev/null 2>&1

# -legacy: SHA1 MAC / 3DES so macOS `security import` accepts the bundle
# (openssl 3 defaults to a MAC the security tool rejects). A transient,
# non-empty password is required — empty-password bundles fail MAC verification.
P12_PASS="roba-hud"
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$CERT_NAME" -out "$TMP/cert.p12" -passout "pass:$P12_PASS" >/dev/null 2>&1

echo "==> importing into login keychain (granting codesign access)"
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign

echo
echo "Done. '$CERT_NAME' is installed."
echo "Rebuild with: ./scripts/package-app.sh --install"
