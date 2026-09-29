#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh"
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
b64(){ printf '%s' "$1" | base64 -w0; }

# Twelve concurrent temp.create calls in the same parent must produce distinct
# owned workspaces without shared files.
mkdir "$TMP/root"
for i in $(seq 1 12); do
  cat > "$TMP/create-$i.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=concurrent-create-$i
command=temp.create
REQ
  (TMPDIR="$TMP/root" /bin/bash "$CLI" --request "$TMP/create-$i.req" > "$TMP/create-$i.json") &
done
wait
paths="$TMP/paths.txt"; : > "$paths"
for i in $(seq 1 12); do
  check jq -e '.ok==true and .data.ownerMarker==true' "$TMP/create-$i.json"
  jq -r '.data.path' "$TMP/create-$i.json" >> "$paths"
done
check test "$(sort -u "$paths" | wc -l | tr -d ' ')" -eq 12
while IFS= read -r p; do check test -f "$p/.mj_native_owned"; done < "$paths"

# Clean all created workspaces concurrently. No cleanup may affect a sibling.
i=0
while IFS= read -r p; do
  i=$((i+1))
  cat > "$TMP/clean-$i.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=concurrent-clean-$i
command=temp.clean
arg.path=$(b64 "$p")
REQ
  (TMPDIR="$TMP/root" /bin/bash "$CLI" --request "$TMP/clean-$i.req" > "$TMP/clean-$i.json") &
done < "$paths"
wait
for i in $(seq 1 12); do check jq -e '.ok==true and .data.removed==true' "$TMP/clean-$i.json"; done
while IFS= read -r p; do check test ! -e "$p"; done < "$paths"

# Concurrent hashes of one immutable file must all agree.
TARGET="$TMP/shared-media.bin"; head -c 65536 /dev/urandom > "$TARGET"
EXPECTED=$(sha256sum "$TARGET" | awk '{print $1}')
for i in $(seq 1 12); do
  cat > "$TMP/hash-$i.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=concurrent-hash-$i
command=file.hash
arg.path=$(b64 "$TARGET")
REQ
  (/bin/bash "$CLI" --request "$TMP/hash-$i.req" > "$TMP/hash-$i.json") &
done
wait
for i in $(seq 1 12); do check jq -e --arg h "$EXPECTED" '.ok==true and .data.hash==$h' "$TMP/hash-$i.json"; done
check test "$(sha256sum "$TARGET" | awk '{print $1}')" = "$EXPECTED"

printf 'Concurrency tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
