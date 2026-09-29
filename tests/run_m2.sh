#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh"
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check() { if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
req() {
  local id=$1 cmd=$2 path=${3-} out=$4
  {
    echo 'MOGRAPHJAILED_REQUEST 1'
    echo "requestId=$id"
    echo "command=$cmd"
    if [[ -n "$path" ]]; then printf 'arg.path=%s\n' "$(printf '%s' "$path" | base64 -w0)"; fi
  } > "$TMP/$id.req"
  set +e
  "$CLI" --request "$TMP/$id.req" > "$out"
  RC=$?
  set -e
}

WEIRD="$TMP/space ' quote ; dollar \$(touch NEVER) unicode-雪.txt"
printf 'immutable-data\n' > "$WEIRD"
BEFORE=$(sha256sum "$WEIRD" | awk '{print $1}')
req m2-001 file.inspect "$WEIRD" "$TMP/inspect.json"
check test "$RC" -eq 0
check jq -e --arg p "$WEIRD" '.ok==true and .data.path==$p and .data.kind=="file" and .data.sizeBytes>0' "$TMP/inspect.json"
check test ! -e "$TMP/NEVER"

req m2-002 file.hash "$WEIRD" "$TMP/hash.json"
check test "$RC" -eq 0
check jq -e --arg h "$BEFORE" '.ok==true and .data.algorithm=="SHA-256" and .data.hash==$h and .data.stabilityCheck=="device+inode+size+mtime"' "$TMP/hash.json"
AFTER=$(sha256sum "$WEIRD" | awk '{print $1}')
check test "$BEFORE" = "$AFTER"

ln -s "$WEIRD" "$TMP/hash-link"
req m2-002-symlink file.hash "$TMP/hash-link" "$TMP/hash-link.json"
check test "$RC" -eq 0
check jq -e --arg h "$BEFORE" ' .ok==true and .data.hash==$h and .data.stabilityCheck=="device+inode+size+mtime" ' "$TMP/hash-link.json"

req m2-003 volume.inspect "$TMP" "$TMP/volume.json"
check test "$RC" -eq 0
check jq -e '.ok==true and .data.available==true and (.data.freeBytes|type=="number")' "$TMP/volume.json"

req m2-004 temp.create "" "$TMP/temp-create.json"
check test "$RC" -eq 0
TDIR=$(jq -r '.data.path' "$TMP/temp-create.json")
check test -f "$TDIR/.mj_native_owned"
req m2-005 temp.clean "$TDIR" "$TMP/temp-clean.json"
check test "$RC" -eq 0
check test ! -e "$TDIR"

mkdir "$TMP/not-owned"
req m2-006 temp.clean "$TMP/not-owned" "$TMP/refuse.json"
check test "$RC" -ne 0
check jq -e '.error.code=="TEMP_REFUSED"' "$TMP/refuse.json"
check test -d "$TMP/not-owned"

# Traversal-shaped cleanup request must be refused even if a marker exists elsewhere.
mkdir -p "$TMP/MographJailed.fake"
printf 'MOGRAPHJAILED\n' > "$TMP/MographJailed.fake/.mj_native_owned"
req m2-006b temp.clean "$TMP/MographJailed.fake/../not-owned" "$TMP/traversal.json"
check test "$RC" -ne 0
check jq -e '.error.code=="TEMP_REFUSED"' "$TMP/traversal.json"
check test -d "$TMP/not-owned"

req m2-007 file.inspect "$TMP/missing" "$TMP/missing.json"
check test "$RC" -ne 0
check jq -e '.error.code=="NOT_FOUND"' "$TMP/missing.json"



cat > "$TMP/temp-relative.req" <<'REQ'
MOGRAPHJAILED_REQUEST 1
requestId=m2-relative
command=temp.create
REQ
set +e
TMPDIR=relative-temp "$CLI" --request "$TMP/temp-relative.req" > "$TMP/temp-relative.json"
rel_rc=$?
set -e
check test "$rel_rc" -ne 0
check jq -e '.error.code=="TEMP_UNAVAILABLE"' "$TMP/temp-relative.json"



check grep -q '/bin/df -kY' "$ROOT/src/lib/local_fs.zsh"
check sh -c '! grep -q "/usr/bin/stat -f '\''%T'\''" "$1/src/modules/volume.zsh"' sh "$ROOT"

printf 'M2 tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
