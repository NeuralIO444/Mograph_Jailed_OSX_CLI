#!/usr/bin/env bash
# Phase 8 audit log: opt-in hash chain written by the runtime, checked by audit.verify.
# Also checks that system.describe publishes per-operation argument schemas.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
b64(){ printf '%s' "$1" | base64 | tr -d '\n'; }
mkreq(){
  local _f="$1" _cmd="$2"; shift 2
  { printf 'MOGRAPHJAILED_REQUEST 1\nrequestId=t%s\ncommand=%s\n' "$RANDOM" "$_cmd"
    for _a in "$@"; do printf 'arg.%s=%s\n' "${_a%%=*}" "$(b64 "${_a#*=}")"; done; } > "$_f"
}
run(){ local _out="$1"; shift; mkreq "$TMP/r$RANDOM$RANDOM" "$@"; "$CLI" --request "$(ls -t "$TMP"/r* | head -1)" > "$_out" 2>/dev/null || true; }
LOG="$TMP/audit/audit.jsonl"

# Off by default: no directory -> nothing written, response identical.
export MJ_AUDIT_DIR="$TMP/audit"
run "$TMP/p0.json" system.probe
check test ! -e "$TMP/audit"

# On when the directory exists.
mkdir "$TMP/audit"
run "$TMP/p1.json" system.probe
check test "$(jq -c 'del(.requestId)' "$TMP/p0.json")" = "$(jq -c 'del(.requestId)' "$TMP/p1.json")"
run "$TMP/f1.json" file.inspect "path=$TMP/p1.json"
printf 'garbage\n' > "$TMP/bad.req"; "$CLI" --request "$TMP/bad.req" >/dev/null 2>&1 || true
check test "$(wc -l < "$LOG" | tr -d ' ')" = 3
check jq -se '.[0].prev == ("0"*64) and .[0].command=="system.probe" and .[0].exitCode==0' "$LOG"
check jq -se --arg p "$TMP/p1.json" '.[1].command=="file.inspect" and .[1].args.path==$p' "$LOG"
check jq -se '.[2].exitCode==65' "$LOG"

# Concurrent writers keep one line each and an intact chain.
for i in $(seq 1 10); do mkreq "$TMP/c$i" system.probe; done
for i in $(seq 1 10); do "$CLI" --request "$TMP/c$i" >/dev/null 2>&1 & done; wait
check test "$(wc -l < "$LOG" | tr -d ' ')" = 13
check test ! -e "$TMP/audit/.audit.lock"

run "$TMP/v1.json" audit.verify "path=$LOG"
check jq -e '.ok==true and .data.schema=="MJ_AUDIT_VERIFY_1" and .data.valid==true and .data.entriesVerified==13 and (.data.headHash|length)==64' "$TMP/v1.json"

# Tamper: edit a middle line -> chain breaks on the following line.
cp "$LOG" "$TMP/edited.jsonl"
python3 - "$TMP/edited.jsonl" <<'PY'
import sys; p = sys.argv[1]; L = open(p).read().splitlines(True)
L[4] = L[4].replace('"system.probe"', '"system.doctor"'); open(p, "w").writelines(L)
PY
run "$TMP/v2.json" audit.verify "path=$TMP/edited.jsonl"
check jq -e '.data.valid==false and .data.firstBrokenLine==6 and .data.headHash==null' "$TMP/v2.json"
# Delete a middle line.
sed '3d' "$LOG" > "$TMP/deleted.jsonl"
run "$TMP/v3.json" audit.verify "path=$TMP/deleted.jsonl"
check jq -e '.data.valid==false and .data.firstBrokenLine==3' "$TMP/v3.json"
# Not a log.
printf 'nope\n' > "$TMP/x.jsonl"
run "$TMP/v4.json" audit.verify "path=$TMP/x.jsonl"
check jq -e '.data.valid==false and .data.reason=="unparseable line"' "$TMP/v4.json"
run "$TMP/v5.json" audit.verify "path=relative.jsonl"
check jq -e '.error.code=="INVALID_PATH"' "$TMP/v5.json"

# A stale lock from a crashed writer is cleared; logging resumes.
mkdir "$TMP/audit/.audit.lock"; touch -t 202001010000 "$TMP/audit/.audit.lock"
N=$(wc -l < "$LOG" | tr -d ' ')
run "$TMP/p2.json" system.probe
check test "$(wc -l < "$LOG" | tr -d ' ')" = $((N + 1))

# system.describe publishes argument schemas.
unset MJ_AUDIT_DIR
run "$TMP/d.json" system.describe
check jq -e '.data.operations["loop.seams"].args == {"allowed":["path","maxResults","minFrames"],"required":["path"]}' "$TMP/d.json"
check jq -e '.data.operations["system.probe"].args == {"allowed":[],"required":[]}' "$TMP/d.json"
check jq -e '[.data.operations[] | has("args")] | all' "$TMP/d.json"

echo "Audit log tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
