#!/usr/bin/env bash
# cache.inspect / cache.clean and mj space, against a fake home folder, fake /Applications and a fake process list.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" MJ_STORE_DIR="$TMP/store" MJ_AUDIT_DIR="$TMP/noaudit" MJ_TEST_APPS_DIR="$TMP/Applications" MJ_TEST_PS="$TMP/ps"
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
has(){ case "$(cat "$1")" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
b64(){ printf '%s' "$1" | base64 | tr -d '\n'; }
run(){
  local _out="$1" _cmd="$2"; shift 2
  local _f="$TMP/req_$RANDOM$RANDOM.txt"
  { printf 'MOGRAPHJAILED_REQUEST 1\nrequestId=t%s\ncommand=%s\n' "$RANDOM" "$_cmd"
    for _a in "$@"; do printf 'arg.%s=%s\n' "${_a%%=*}" "$(b64 "${_a#*=}")"; done; } > "$_f"
  set +e; "$CLI" --request "$_f" > "$_out" 2>/dev/null; echo $? > "$_out.rc"; set -e
}
ps_shows(){ printf '%s\n' "$@" > "$TMP/ps.list"; printf '#!/bin/sh\ncat "%s"\n' "$TMP/ps.list" > "$TMP/ps"; chmod +x "$TMP/ps"; }
fill(){ mkdir -p "$1"; head -c "$2" /dev/zero > "$1/a.bin"; mkdir -p "$1/sub"; head -c 1000 /dev/zero > "$1/sub/b.bin"; }

# Installed: After Effects 26.5 and Cinema 4D 2026.
mkdir -p "$MJ_TEST_APPS_DIR/Adobe After Effects 2026/Adobe After Effects 2026.app/Contents" "$MJ_TEST_APPS_DIR/Maxon Cinema 4D 2026"
python3 -c 'import plistlib,sys; plistlib.dump({"CFBundleShortVersionString": "26.5.0"}, open(sys.argv[1], "wb"))' "$MJ_TEST_APPS_DIR/Adobe After Effects 2026/Adobe After Effects 2026.app/Contents/Info.plist"
C="$HOME/Library/Caches/Adobe/After Effects"
fill "$C/26.3/Disk Cache - Mac.noindex" 300000
fill "$C/26.5/Disk Cache - Mac.noindex" 100000
fill "$HOME/Library/Application Support/Adobe/Common/Media Cache Files" 50000
fill "$HOME/Library/Preferences/Maxon/Maxon Cinema 4D 2025_AB12/Redshift/Cache" 40000
fill "$HOME/Library/Preferences/Maxon/_assetcache" 20000
# A custom disk-cache folder chosen in After Effects' preferences, and a symlink inside a cache that points outside it.
fill "$TMP/fastdisk/Adobe/After Effects/26.5/Disk Cache - Mac.noindex" 10000
mkdir -p "$HOME/Library/Preferences/Adobe/After Effects/26.5"
printf '["Disk Cache Controls"]\r\t"Enabled 2" = "1"\r\t"Folder 7" = "%s"\r["Other"]\r' "$TMP/fastdisk" > "$HOME/Library/Preferences/Adobe/After Effects/26.5/Adobe After Effects 26.5 Prefs.txt"
mkdir -p "$TMP/precious"; echo keep > "$TMP/precious/file.txt"
ln -s "$TMP/precious" "$C/26.3/Disk Cache - Mac.noindex/link"
ps_shows launchd Finder

run "$TMP/i.json" cache.inspect
check jq -e '.ok and .data.schema=="MJ_CACHE_INSPECT_1"' "$TMP/i.json"
check jq -e '[.data.caches[].id]|sort==["adobe-media-cache","ae-disk-26.3","ae-disk-26.5","ae-disk-26.5-2","maxon-asset-cache","redshift-2025-ab12"]' "$TMP/i.json"
check jq -e '[.data.caches[]|select(.leftOver)|.id]|sort==["ae-disk-26.3","redshift-2025-ab12"]' "$TMP/i.json"
check jq -e '(.data.caches[]|select(.id=="maxon-asset-cache")|.cleanable)==false' "$TMP/i.json"
check jq -e '.data.caches[0].id=="ae-disk-26.3" and .data.caches[0].bytes>=300000' "$TMP/i.json"     # biggest first
check jq -e '[.data.caches[]|select(.path|startswith("'"$TMP"'/fastdisk"))]|length==1' "$TMP/i.json"
check jq -e '.data.leftOverBytes>=340000 and .data.cleanableBytes>.data.leftOverBytes' "$TMP/i.json"

# Report only (default): nothing deleted.
run "$TMP/r.json" cache.clean target=ae-disk-26.3
check jq -e '.ok and .data.deleted==false and .data.wouldFree>=300000 and .data.bytesFreed==0' "$TMP/r.json"
check test -f "$C/26.3/Disk Cache - Mac.noindex/a.bin"

# Refusals: unknown id, bad id characters, a cache the app manages, a bad format, the owning app running.
run "$TMP/e1.json" cache.clean target=nope-1;               check jq -e '.error.code=="NOT_FOUND"' "$TMP/e1.json"; check test "$(cat "$TMP/e1.json.rc")" = 66
run "$TMP/e2.json" cache.clean target=../../etc;            check jq -e '.error.code=="INVALID_ARGUMENT"' "$TMP/e2.json"; check test "$(cat "$TMP/e2.json.rc")" = 65
run "$TMP/e3.json" cache.clean target=maxon-asset-cache format=delete; check jq -e '.error.code=="POLICY_DENIED"' "$TMP/e3.json"; check test "$(cat "$TMP/e3.json.rc")" = 77
run "$TMP/e4.json" cache.clean target=ae-disk-26.3 format=yes; check jq -e '.error.code=="INVALID_ARGUMENT"' "$TMP/e4.json"
ps_shows launchd "/Applications/Adobe Media Encoder 2026/Adobe Media Encoder 2026.app/Contents/MacOS/Adobe Media Encoder 2026"
run "$TMP/e5.json" cache.clean target=adobe-media-cache format=delete
check jq -e '.error.code=="HOST_BUSY" and (.error.message|test("Adobe Media Encoder"))' "$TMP/e5.json"
check test -f "$HOME/Library/Application Support/Adobe/Common/Media Cache Files/a.bin"
printf '#!/bin/sh\nexit 1\n' > "$TMP/ps"
run "$TMP/e6.json" cache.clean target=adobe-media-cache format=delete; check jq -e '.error.code=="UNSUPPORTED"' "$TMP/e6.json"

# Two folders for one version get distinct ids, and each can be cleaned on its own.
run "$TMP/r2.json" cache.clean target=ae-disk-26.5-2
check jq -e '.data.path|contains("fastdisk") or contains("Library/Caches")' "$TMP/r2.json"
# A left-over cache can be emptied while the installed version runs; the folder stays, a symlink's target survives.
ps_shows launchd "After Effects"
run "$TMP/d.json" cache.clean target=ae-disk-26.3 format=delete
check jq -e '.ok and .data.deleted and .data.bytesFreed>=300000 and .data.entriesRemoved==3' "$TMP/d.json"
check test -d "$C/26.3/Disk Cache - Mac.noindex"
check test -z "$(ls -A "$C/26.3/Disk Cache - Mac.noindex")"
check test -f "$TMP/precious/file.txt"
check test -f "$C/26.5/Disk Cache - Mac.noindex/a.bin"

# mj space
mjz(){ MJ_CLI="$CLI" MJ_CONFIG="$TMP/cfg" zsh -f -c "source '$ROOT/scripts/shell/mj-cli.zsh'; $1" > "$TMP/out.txt" 2>&1 && echo 0 > "$TMP/rc" || echo $? > "$TMP/rc"; }
ps_shows launchd
mjz "mj space"
check has "$TMP/out.txt" "Caches on this Mac:"
check has "$TMP/out.txt" "Cinema 4D 2025 Redshift cache"
check has "$TMP/out.txt" "left over, not installed"
mjz "mj space clean redshift-2025-ab12"
check has "$TMP/out.txt" "Nothing was deleted. To empty it, run:  mj space clean redshift-2025-ab12 --yes"
mjz "mj space clean leftovers --yes"
check has "$TMP/out.txt" "Emptied the Cinema 4D 2025 Redshift cache"
check test ! -e "$HOME/Library/Preferences/Maxon/Maxon Cinema 4D 2025_AB12/Redshift/Cache/a.bin"
mjz "mj space clean leftovers --yes"
check has "$TMP/out.txt" "Nothing left over from old versions."
mjz "mj space clean adobe-media-cache"
check has "$TMP/out.txt" "(quit Adobe video apps first)"
mjz "mj space bogus"
check test "$(cat "$TMP/rc")" = 64

echo "Space tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
