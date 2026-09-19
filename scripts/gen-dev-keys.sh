#!/bin/bash
# Create a throwaway, self-signed RAUC signing key pair for local builds.
# keys/ is gitignored. Release bundles are signed in CI from the RAUC_KEY
# secret and RAUC_CERT variable instead.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p keys
if [[ -f keys/rauc.key || -f keys/rauc.crt ]]; then
    echo "keys/rauc.key or keys/rauc.crt already exists; not overwriting" >&2
    exit 1
fi
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
    -subj "/O=Jalea/CN=Jalea development bundle signing" \
    -keyout keys/rauc.key -out keys/rauc.crt
chmod 0600 keys/rauc.key
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
    -subj "/CN=Jalea dev VM ssh" -keyout keys/ssh.key -out keys/ssh.crt 2>/dev/null
chmod 0600 keys/ssh.key
echo "wrote keys/rauc.{key,crt} (bundle signing) and keys/ssh.{key,crt} (mkosi ssh)"
