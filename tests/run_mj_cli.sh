#!/usr/bin/env bash
# Phase 10: mj front end (single ops, ops listing, recipes, completion data).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
# Run zsh code with mj loaded against the portable bundle.
mjz(){ MJ_CLI="$ROOT/dist/mograph-jailed-linux-test.sh" zsh -f -c "source '$ROOT/scripts/shell/mj-cli.zsh'; $1"; }

mkdir -p "$TMP/my frames"
printf 'x' > "$TMP/my frames/a file.txt"

# single operation, value with spaces
mjz "mj file.inspect 'path=$TMP/my frames/a file.txt'" > "$TMP/o1.json" || true
check jq -e --arg p "$TMP/my frames/a file.txt" '.ok==true and .data.path==$p' "$TMP/o1.json"
# runtime exit code propagates
set +e; mjz "mj file.inspect path=relative" > "$TMP/o2.json"; rc=$?; set -e
check test "$rc" -ne 0
check jq -e '.error.code=="INVALID_PATH"' "$TMP/o2.json"
# bare `mj` keeps its legacy meaning; an old alias does not shadow the function
mkdir -p "$TMP/root"
check test "$(MOGRAPHJAILED_ROOT="$TMP/root" mjz "alias mj='echo OLD'; source '$ROOT/scripts/shell/mj-cli.zsh'; mj; pwd -P")" = "$(cd "$TMP/root" && pwd -P)"
# argument syntax checked locally
set +e; mjz "mj file.inspect noequals" 2>"$TMP/e1"; rc=$?; set -e
check test "$rc" = 64
# ops listing marks required args
mjz "mj ops" > "$TMP/ops.txt"
check grep -q $'^golden.record\tAVAILABLE\tpath\\* output\\* label\\*$' "$TMP/ops.txt"
check test "$(wc -l < "$TMP/ops.txt" | tr -d ' ')" = 44

# recipe: comments, quoting, placeholders with spaces
cat > "$TMP/check.mjrecipe" <<'R'
# inspect then hash the same file
file.inspect path={{target}}

file.hash "path={{target}}"
R
mjz "mj recipe '$TMP/check.mjrecipe' 'target=$TMP/my frames/a file.txt'" > "$TMP/r1.out" 2>"$TMP/r1.err"
check grep -q '\[2/2\] file.hash' "$TMP/r1.err"
check test "$(grep -c '"ok": *true' "$TMP/r1.out")" = 2
# validation happens before any step runs
printf 'file.inspect path={{target}}\nsystem.shell cmd=rm\n' > "$TMP/bad1.mjrecipe"
set +e; mjz "mj recipe '$TMP/bad1.mjrecipe' target=/tmp" > "$TMP/b1.out" 2>"$TMP/b1.err"; rc=$?; set -e
check test "$rc" = 65
check grep -q 'unknown operation: system.shell' "$TMP/b1.err"
check test ! -s "$TMP/b1.out"
printf 'file.inspect path=/tmp evil=1\n' > "$TMP/bad2.mjrecipe"
set +e; mjz "mj recipe '$TMP/bad2.mjrecipe'" 2>"$TMP/b2.err"; rc=$?; set -e
check grep -q 'does not accept argument: evil' "$TMP/b2.err"
printf 'file.inspect path={{target}}\n' > "$TMP/bad3.mjrecipe"
set +e; mjz "mj recipe '$TMP/bad3.mjrecipe'" 2>"$TMP/b3.err"; rc=$?; set -e
check grep -q 'needs target=<value>' "$TMP/b3.err"
# shell syntax in a recipe is inert data, never executed
printf 'file.inspect "path=$(touch %s/pwned)"\n' "$TMP" > "$TMP/inert.mjrecipe"
mjz "mj recipe '$TMP/inert.mjrecipe'" >/dev/null 2>&1 || true
check test ! -e "$TMP/pwned"
# stops at first failing step
printf 'file.inspect path=relative\nsystem.probe\n' > "$TMP/stop.mjrecipe"
set +e; mjz "mj recipe '$TMP/stop.mjrecipe'" > /dev/null 2>"$TMP/s.err"; rc=$?; set -e
check test "$rc" -ne 0
check grep -q 'step 1 (file.inspect) failed' "$TMP/s.err"
check bash -c "! grep -q '2/2' '$TMP/s.err'"

echo "mj front end tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
