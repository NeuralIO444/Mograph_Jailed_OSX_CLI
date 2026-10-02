#!/usr/bin/env bash
# The guides in docs/guides cannot lie:
#   1. every `mj ...` command and every operation name they mention exists;
#   2. the walkthrough they quote is re-run for real and must equal docs/guides/walkthrough.golden
#      (regenerate with: bash tests/run_guides.sh --update, then update the guide text that quotes it).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
GOLDEN="$ROOT/docs/guides/walkthrough.golden"

# ---- 1. names mentioned in the guides exist ----
"$ROOT/scripts/build-linux-test.sh" >/dev/null
printf 'MOGRAPHJAILED_REQUEST 1\nrequestId=g\ncommand=system.describe\n' > "$TMP/d.req"
MJ_STORE_DIR="$TMP/s" "$ROOT/dist/mograph-jailed-linux-test.sh" --request "$TMP/d.req" | jq -r '.data.operations|keys[]' | sort > "$TMP/ops.txt"
VERBS="snapshot versions lint health diff scene bridge explain watch doctor config notify status last open-last ui home cd ops recipe batch help"
python3 "$ROOT/tests/support/check_guides.py" "$ROOT" "$TMP/ops.txt" "$VERBS"
check true
[ -d "$ROOT/docs/guides" ] && check test "$(ls "$ROOT"/docs/guides/*.md | wc -l | tr -d ' ')" -ge 8

# ---- 2. the walkthrough ----
S="$TMP/sandbox"; mkdir -p "$S"
RUNTIME="$ROOT/dist/mograph-jailed.zsh"; sh "$ROOT/scripts/build.zsh" >/dev/null
zsh -f "$ROOT/tests/support/walkthrough.zsh" "$ROOT" "$S" "$RUNTIME" > "$TMP/walk.raw" 2>&1 || true
HOMEREAL=$(cd "$S/home" && pwd -P)
sed -E -e 's|/private/var|/var|g' -e "s|${HOMEREAL#/private}|~|g" -e "s|$S/home|~|g" -e "s|$ROOT|<repo>|g" \
    -e 's/[0-9]{8}T[0-9]{6}Z\.([0-9a-f]{12})\.(aep|c4d)/<time>.\1.\2/g' \
    -e 's/20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]/<date> <time>/g' \
    -e 's/ copied instantly \(copy-on-write\);/ copied;/' -e 's/([0-9][0-9]*s)/(Ns)/g' "$TMP/walk.raw" > "$TMP/walk.norm"
if [ "${1:-}" = "--update" ]; then cp "$TMP/walk.norm" "$GOLDEN"; echo "updated $GOLDEN"; exit 0; fi
check test -s "$TMP/walk.norm"
if ! diff -u "$GOLDEN" "$TMP/walk.norm" > "$TMP/walk.diff"; then echo "walkthrough differs from docs/guides/walkthrough.golden:" >&2; head -40 "$TMP/walk.diff" >&2; fail=$((fail+1)); else pass=$((pass+1)); fi

echo "Guides tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
