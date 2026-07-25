#!/bin/bash
# One-time setup: create a stable self-signed codesigning identity so the
# Accessibility grant survives rebuilds. Safe to re-run (skips if it exists).
set -euo pipefail

IDENTITY="AdwamTally Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo "Identity '$IDENTITY' already present. Nothing to do."
  security find-identity -v -p codesigning | grep "$IDENTITY"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

cat > cfg <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = AdwamTally Self-Signed
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

echo "==> Generating self-signed codesigning certificate…"
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 -config cfg >/dev/null 2>&1

echo "==> Importing certificate + private key into login keychain…"
# Import as separate PEM files (avoids the OpenSSL 3 / macOS PKCS#12 MAC issue).
# security pairs the matching cert+key into a codesigning identity automatically.
security import cert.pem -k "$KEYCHAIN" -T /usr/bin/codesign -A 2>&1 || true
security import key.pem  -k "$KEYCHAIN" -T /usr/bin/codesign -A

echo ""
echo "Done. Codesigning identities:"
security find-identity -v -p codesigning | grep "$IDENTITY" || {
  echo "WARNING: identity not found after import." >&2
  exit 1
}
echo ""
echo "Next: re-run ./build-app.sh (it will sign with this identity),"
echo "then grant Accessibility once — it will stick from now on."
