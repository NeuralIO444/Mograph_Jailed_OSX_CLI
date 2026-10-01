#!/bin/sh
# Write SHA256SUMS: the SHA-256 of every tracked file except SHA256SUMS itself.
#
# The designer installer verifies the unpacked download against this list, which catches
# truncated, corrupted or mixed-up downloads. It is NOT a defence against a compromised
# repository (whoever can change a file can change this list too): for that, pin the zip's
# hash (MJ_INSTALL_SHA256) from a source you trust, or read the installer before running it.
#
# Run it before committing; CI and tests/run_contract_audit.sh fail if it is stale.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
git ls-files | LC_ALL=C sort | while IFS= read -r f; do
    [ "$f" = "SHA256SUMS" ] && continue
    [ -f "$f" ] || continue          # deleted in the working tree but not yet committed
    printf '%s  %s\n' "$(shasum -a 256 -- "$f" | cut -d' ' -f1)" "$f"
done > "$tmp"
if [ "${1:-}" = "--check" ]; then
    cmp -s "$tmp" SHA256SUMS && { echo "SHA256SUMS is current"; exit 0; }
    echo "SHA256SUMS is stale: run  sh scripts/make-manifest.sh" >&2; exit 1
fi
cp "$tmp" SHA256SUMS
echo "wrote SHA256SUMS ($(wc -l < SHA256SUMS | tr -d ' ') files)"
