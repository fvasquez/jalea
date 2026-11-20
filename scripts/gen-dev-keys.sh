#!/bin/bash
# Create throwaway, self-signed key pairs for local builds, each one only if
# it does not exist yet. keys/ is gitignored. Release builds are signed in CI
# from repository secrets and variables instead (see .github/workflows).
#
#   keys/rauc.{key,crt}  RAUC bundle signing
#   keys/ssh.{key,crt}   mkosi ssh into the dev VM
#
# Not the Secure Boot key: keys/secureboot.{key,crt} must be the real one,
# the key machines have enrolled as their MOK, or nothing built with it
# boots under Secure Boot. Put it there yourself.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p keys

# gen NAME SUBJECT BITS [openssl req args...]
gen() {
    local name=$1 subj=$2 bits=$3
    shift 3
    if [[ -f keys/$name.key || -f keys/$name.crt ]]; then
        echo "keys/$name.{key,crt}: exists, kept"
        return
    fi
    openssl req -x509 -newkey "rsa:$bits" -sha256 -days 3650 -nodes \
        -subj "$subj" -keyout "keys/$name.key" -out "keys/$name.crt" "$@" 2>/dev/null
    chmod 0600 "keys/$name.key"
    echo "keys/$name.{key,crt}: created"
}

gen rauc "/O=Jalea/CN=Jalea development bundle signing" 4096
gen ssh "/CN=Jalea dev VM ssh" 4096
