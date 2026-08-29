#!/bin/bash
#
# Creates a self-signed code signing certificate for Tidewell, once.
#
#   ./Scripts/make-signing-cert.sh
#
# Why this exists
# ---------------
# An ad-hoc signature (`codesign --sign -`) has no certificate, so its designated
# requirement is a bare cdhash — the hash of that exact binary:
#
#     designated => cdhash H"8298256d73b313a84485eb216bceeaf7afe8a370"
#
# macOS keys the Accessibility grant to that requirement. Rebuild the app and the
# hash changes, the grant no longer matches, and Tidewell is silently unauthorised
# again — while still *appearing* switched on in System Settings, because the stale
# entry is still there. That is maddening, and it happens on every single rebuild.
#
# Signing with a certificate instead gives a requirement that survives rebuilds:
#
#     designated => identifier "space.iam-deepak.tidewell" and certificate leaf = H"…"
#
# Grant access once and it stays granted, however many times you rebuild. The same
# applies to the login item, which also needs a stable identity.
#
# This touches your login keychain and nothing else. To undo it, delete the
# "Tidewell Self-Signed" certificate in Keychain Access.
set -euo pipefail
cd "$(dirname "$0")/.."

CERT_NAME="Tidewell Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
    echo "==> '$CERT_NAME' already exists — nothing to do."
    echo "    Build with it:  ./Scripts/build.sh"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Generating certificate"
cat > "$WORK/openssl.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions    = v3
prompt             = no
[dn]
CN = Tidewell Self-Signed
[v3]
basicConstraints     = critical,CA:false
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -config "$WORK/openssl.cnf" 2>/dev/null

openssl pkcs12 -export -legacy \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$CERT_NAME" -out "$WORK/bundle.p12" \
    -passout pass:tidewell 2>/dev/null

echo "==> Importing into the login keychain"
# -T /usr/bin/codesign plus -A stops the keychain prompting for permission on every
# single build.
security import "$WORK/bundle.p12" -k "$KEYCHAIN" -P tidewell -T /usr/bin/codesign -A >/dev/null

echo "==> Trusting it for code signing"
# User-domain trust only. This does not make anything trusted for Gatekeeper — it
# just lets codesign use the identity.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem" 2>/dev/null \
    || echo "    note: trust settings not applied; codesign usually works regardless"

echo "==> Verifying"
if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "    identity is valid for code signing"
else
    echo "    warning: not listed as a valid codesigning identity" >&2
fi

echo
echo "==> Done. Scripts/build.sh picks it up automatically from now on."
