#!/bin/sh
# Build the double-clickable release: MographJailed-<version>.zip
#
#   sh scripts/make-release.sh [output folder]            (default: ./release)
#   MJ_RELEASE_KEY=~/.ssh/mj_release sh scripts/make-release.sh     (also signs the checksum list)
#
# The zip holds: Install/Uninstall MographJailed.command, README-FIRST.txt, allowed_signers (when signed) and
# payload/ (every tracked file except tests, research and CI) with its own SHA256SUMS. Needs git, shasum, zip or ditto.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
out="${1:-$root/release}"
ver=$(sed -n 's/^MographJailed //p' "$root/VERSION" | head -1)
[ -n "$ver" ] || { echo "make-release: cannot read VERSION" >&2; exit 1; }
name="MographJailed-$ver"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
stage="$work/$name"; mkdir -p "$stage/payload" "$out"
git -C "$root" ls-files | while IFS= read -r f; do
  case "$f" in tests/*|research/*|.github/*|.gitignore|SHA256SUMS) continue ;; esac
  [ -f "$root/$f" ] || continue
  mkdir -p "$stage/payload/$(dirname "$f")"; cp -p "$root/$f" "$stage/payload/$f"
done
cp -p "$root/tools/Install MographJailed.command" "$root/tools/Uninstall MographJailed.command" "$root/tools/README-FIRST.txt" "$stage/"
( cd "$stage/payload" && find . -type f ! -name SHA256SUMS | sed 's|^\./||' | LC_ALL=C sort | while IFS= read -r f; do
    printf '%s  %s\n' "$(shasum -a 256 "$f" | cut -d' ' -f1)" "$f"; done > SHA256SUMS )
if [ -n "${MJ_RELEASE_KEY:-}" ]; then
  ssh-keygen -Y sign -q -f "$MJ_RELEASE_KEY" -n file "$stage/payload/SHA256SUMS" >/dev/null
  printf 'release@mographjailed namespaces="file" %s\n' "$(cut -d' ' -f1,2 "$MJ_RELEASE_KEY.pub")" > "$stage/allowed_signers"
  echo "signed with $MJ_RELEASE_KEY.pub"
fi
rm -f "$out/$name.zip"
if command -v ditto >/dev/null 2>&1; then ( cd "$work" && ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$name" "$out/$name.zip" )
else ( cd "$work" && zip -qr -X "$out/$name.zip" "$name" ); fi
echo "built $out/$name.zip"
echo "SHA-256: $(shasum -a 256 "$out/$name.zip" | cut -d' ' -f1)"
