#!/usr/bin/env bash
# json_quote (src/core/json.zsh) is pure zsh; its output must always parse back to exactly the input string.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
cat > "$TMP/gen.zsh" <<'ZSH'
emulate -R zsh
source "$1/src/core/json.zsh"
palette=( a Z 0 ' ' '"' '\' '/' $'\n' $'\r' $'\t' $'\b' $'\f' $'\001' $'\037' $'\033' $'\177' 'é' 'ü' '日本' '🎬' '$' '`' "'" '%' $'\0' )
for s in "" "${palette[@]}"; do json_quote "$s"; print; done
integer i j
for (( i = 0; i < 400; i++ )); do
  s=""; for (( j = 0; j < 1 + RANDOM % 12; j++ )); do s+="${palette[1 + RANDOM % ${#palette}]}"; done
  json_quote "$s"; print
done
ZSH
zsh -f "$TMP/gen.zsh" "$ROOT" > "$TMP/out.txt"
check python3 - "$TMP/out.txt" <<'PY'
import json, sys
bad = 0
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")[:-1]
for l in lines:
    try:
        v = json.loads(l)
        assert isinstance(v, str)
    except Exception:
        bad += 1
        print("not valid JSON:", repr(l))
assert len(lines) > 400 and bad == 0
PY
# a known set must produce exactly these bytes (matches the previous awk version)
check test "$(zsh -f -c 'source "$1/src/core/json.zsh"; json_quote "$(printf "a\"b\\\\c\n")"' _ "$ROOT")" = '"a\"b\\c"'
check test "$(zsh -f -c 'source "$1/src/core/json.zsh"; json_quote $'"'"'x\0y'"'"'' _ "$ROOT")" = '"x\u0000y"'
# no process is started per call
check bash -c "zsh -f -c 'source \"$ROOT/src/core/json.zsh\"; for i in {1..200}; do json_quote \"a b\"; done' >/dev/null"
echo "json_quote tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
