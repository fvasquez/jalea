#!/bin/bash
# Turn the split artifacts of the last mkosi build into a signed RAUC bundle.
#
#   mkosi.output/jalea_<v>.esp.raw     -> esp.vfat   (UKI + systemd-boot)
#   mkosi.output/jalea_<v>.usr.raw     -> usr.img    (erofs, verity data)
#   mkosi.output/jalea_<v>.verity.raw  -> verity.img (hash tree)
#   usrhash from the UKI's command line -> roothash  (read by the hook)
#
# Output: mkosi.output/jalea_<v>.raucb, verity format, adaptive updates
# enabled, signed with keys/rauc.key.
set -euo pipefail
cd "$(dirname "$0")/.."

out=mkosi.output
version=${VERSION:-$(./mkosi.version)}
name=jalea_$version
uki=$out/$name.efi
[[ -f $uki ]] || uki=$out/jalea.efi
for f in "$out/$name.esp.raw" "$out/$name.usr.raw" "$out/$name.verity.raw" "$uki"; do
    [[ -f $f ]] || { echo "missing $f; run mkosi build first" >&2; exit 1; }
done
[[ -f keys/rauc.key && -f keys/rauc.crt ]] || { echo "missing keys/rauc.key or keys/rauc.crt" >&2; exit 1; }

# The UKI's .cmdline section carries usrhash=<64 hex>.
usrhash=$(mkosi box -- ukify inspect "$uki" | grep -oE 'usrhash=[0-9a-f]{64}' | head -1 | cut -d= -f2)
[[ -n $usrhash ]] || { echo "could not read usrhash from $uki" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp --reflink=auto "$out/$name.esp.raw" "$tmp/esp.vfat"
cp --reflink=auto "$out/$name.usr.raw" "$tmp/usr.img"
cp --reflink=auto "$out/$name.verity.raw" "$tmp/verity.img"
printf '%s\n' "$usrhash" > "$tmp/roothash"
install -m 0755 rauc/hook "$tmp/hook"
sed "s/@VERSION@/$version/g" rauc/manifest.raucm.in > "$tmp/manifest.raucm"

rm -f "$out/$name.raucb"
mkosi box -- rauc bundle --cert=keys/rauc.crt --key=keys/rauc.key --signing-keyring=keys/rauc.crt \
    "$tmp" "$out/$name.raucb"
mkosi box -- rauc info --keyring=keys/rauc.crt "$out/$name.raucb"
echo "wrote $out/$name.raucb"
