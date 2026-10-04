#!/usr/bin/env bash
# #35: a project or scene whose bytes are not on this Mac (0 bytes, or a cloud "online only" placeholder) is never
# snapshotted, packaged, rendered or turned into a job, and is never read.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P); trap 'rm -rf "$TMP"' EXIT
export MJ_STORE_DIR="$TMP/store" MJ_AUDIT_DIR="$TMP/noaudit" MJ_TEST_APPS_DIR="$TMP/apps"
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
has(){ case "$(cat "$1")" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
b64(){ printf '%s' "$1" | base64 | tr -d '\n'; }
run(){ local _out="$1" _cmd="$2"; shift 2; local _f="$TMP/req_$RANDOM$RANDOM.txt"
  { printf 'MOGRAPHJAILED_REQUEST 1\nrequestId=t%s\ncommand=%s\n' "$RANDOM" "$_cmd"; for _a in "$@"; do printf 'arg.%s=%s\n' "${_a%%=*}" "$(b64 "${_a#*=}")"; done; } > "$_f"
  "$CLI" --request "$_f" > "$_out" 2>/dev/null; echo $? > "$_out.rc"; }
mkdir -p "$TMP/p" "$TMP/v" "$TMP/jobs"
: > "$TMP/p/Empty.aep"; : > "$TMP/p/Empty.c4d"; printf 'real bytes' > "$TMP/p/Real.aep"; printf 'cloud placeholder metadata' > "$TMP/p/Cloud.aep"; printf 'real scene' > "$TMP/p/Real.c4d"
SC="$TMP/p/scrape.json"; python3 "$ROOT/tests/support/make_tutorial_fixtures.py" "$TMP/fx" >/dev/null; cp "$TMP/fx/receipts/spring.20261001T163000Z.scrape.json" "$SC"
none_made(){ [ -z "$(find "$TMP/v" "$TMP/jobs" -mindepth 1 2>/dev/null)" ]; }

# ---- empty files: refused, in words, with nothing written
for f in Empty.aep Empty.c4d; do
  run "$TMP/s.json" project.snapshot path="$TMP/p/$f" output="$TMP/v"
  check jq -e '.ok==false and .error.code=="FILE_EMPTY" and (.error.message|test("0 bytes"))' "$TMP/s.json"; check test "$(cat "$TMP/s.json.rc")" = 65
done
check none_made
run "$TMP/h.json" handoff.package path="$TMP/p/Empty.aep" input="$SC" output="$TMP/v" label=x;      check jq -e '.error.code=="FILE_EMPTY"' "$TMP/h.json"
run "$TMP/x.json" project.extract path="$TMP/p/Empty.aep" input="$SC" target=1 output="$TMP/jobs" label=x; check jq -e '.error.code=="FILE_EMPTY"' "$TMP/x.json"
run "$TMP/c.json" project.conform input="$SC" format=job path="$TMP/p/Empty.aep" output="$TMP/jobs" label=x; check jq -e '.error.code=="FILE_EMPTY"' "$TMP/c.json"
run "$TMP/r.json" project.restore path="$TMP/p/Empty.aep" output="$TMP/v";                          check jq -e '.error.code=="FILE_EMPTY"' "$TMP/r.json"
run "$TMP/a.json" ae.render path="$TMP/p/Empty.aep" target=Main output="$TMP/v" label=x;              check jq -e '.error.code=="FILE_EMPTY"' "$TMP/a.json"
check none_made

# ---- cloud placeholders (the test bundle can mark one file as dataless): refused before anything reads it
export MJ_TEST_DATALESS="$TMP/p/Cloud.aep"
run "$TMP/d1.json" project.snapshot path="$TMP/p/Cloud.aep" output="$TMP/v"
check jq -e '.ok==false and .error.code=="FILE_NOT_DOWNLOADED" and (.error.message|test("online only"))' "$TMP/d1.json"; check test "$(cat "$TMP/d1.json.rc")" = 74
run "$TMP/d2.json" handoff.package path="$TMP/p/Cloud.aep" input="$SC" output="$TMP/v" label=x;      check jq -e '.error.code=="FILE_NOT_DOWNLOADED"' "$TMP/d2.json"
run "$TMP/d3.json" project.extract path="$TMP/p/Cloud.aep" input="$SC" target=1 output="$TMP/jobs" label=x; check jq -e '.error.code=="FILE_NOT_DOWNLOADED"' "$TMP/d3.json"
run "$TMP/d4.json" ae.render path="$TMP/p/Cloud.aep" target=Main output="$TMP/v" label=x;            check jq -e '.error.code=="FILE_NOT_DOWNLOADED"' "$TMP/d4.json"
check none_made
# the same file when it is NOT a placeholder, and files that are real, still work
unset MJ_TEST_DATALESS
run "$TMP/ok1.json" project.snapshot path="$TMP/p/Cloud.aep" output="$TMP/v";  check jq -e '.ok and .data.snapshotCreated' "$TMP/ok1.json"
run "$TMP/ok2.json" project.snapshot path="$TMP/p/Real.aep" output="$TMP/v";   check jq -e '.ok and .data.snapshotCreated' "$TMP/ok2.json"
run "$TMP/ok3.json" project.snapshot path="$TMP/p/Real.c4d" output="$TMP/v";   check jq -e '.ok and .data.snapshotCreated' "$TMP/ok3.json"
# a 1-byte project is small but real
printf x > "$TMP/p/One.aep"; run "$TMP/ok4.json" project.snapshot path="$TMP/p/One.aep" output="$TMP/v"; check jq -e '.ok and .data.snapshotCreated' "$TMP/ok4.json"

# ---- in plain words through mj
export MJ_CONFIG="$TMP/cfg" HOME="$TMP/home"; mkdir -p "$HOME"
mjz(){ MJ_CLI="$CLI" zsh -f -c "source '$ROOT/scripts/shell/mj-cli.zsh'; $1" > "$TMP/out.txt" 2>&1; echo $? > "$TMP/rc"; }
mjz "mj config set versions_dir '$TMP/v' >/dev/null; mj config set watch_dir '$TMP/p' >/dev/null; mj snapshot '$TMP/p/Empty.aep'"
check has "$TMP/out.txt" "is empty (0 bytes)"; check has "$TMP/out.txt" "Dropbox or iCloud"; check bash -c "! grep -q 'Saved a verified copy' '$TMP/out.txt'"
check bash -c "! grep -q '\"protocol\"' '$TMP/out.txt'"
echo "Materialized-file tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
