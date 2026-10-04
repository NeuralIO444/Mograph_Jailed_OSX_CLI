#!/usr/bin/env bash
# #40: on a Mac that has not been set up, every command that needs a folder starts its answer with `Run:  mj setup`.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P); trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
export HOME="$TMP/home"; mkdir -p "$HOME/Movies"; export MJ_CONFIG="$TMP/cfg" MJ_STORE_DIR="$TMP/store" MJ_CLI="$CLI" MJ_AUDIT_DIR="$TMP/noaudit"
mjz(){ zsh -f -c "source '$ROOT/scripts/shell/mj-cli.zsh'; mj $1" > "$TMP/out.txt" 2> "$TMP/err.txt"; echo $? > "$TMP/rc"; }

for line in 'check "My Project"' 'snapshot Spring' 'versions' 'lint last' 'lint' 'health last' 'timeline Spring' 'diff last' 'scene last' 'bridge last last' 'explain last' 'extract Spring Main' 'conform Spring'; do
  mjz "$line"
  first=$(head -1 "$TMP/err.txt")
  case "$line" in 'explain last') continue ;; esac          # explain looks for the last render, which is a different first-run story
  check test "$(cat "$TMP/rc")" -ne 0
  check test "$first" = "mj: this is not set up yet. Run:  mj setup"
  check bash -c "! grep -qi 'receipts folder\|scrape receipt' '$TMP/err.txt' '$TMP/out.txt'"
  check bash -c "! grep -q '\"protocol\"' '$TMP/err.txt' '$TMP/out.txt'"
  check grep -q 'mj config set' "$TMP/err.txt"                  # the by-hand way is still offered, second
done

# folders exist but there are no reports yet: the message names what to do, in words
mjz "setup --yes"; check test "$(cat "$TMP/rc")" = 0
mjz "check Spring"
check grep -q 'no project report for "Spring"' "$TMP/err.txt"; check grep -q 'MographJailed script' "$TMP/err.txt"
mjz "lint last"; check grep -q 'no project reports' "$TMP/err.txt"; check grep -q 'mj scraper' "$TMP/err.txt"; check bash -c "! grep -qi 'receipts folder\|scrape receipt' '$TMP/err.txt'"
mjz "diff last"; check grep -q 'mj scraper' "$TMP/err.txt"
# once set up, the not-set-up message is gone
mjz "versions"; check test "$(cat "$TMP/rc")" = 0; check bash -c "! grep -q 'not set up' '$TMP/err.txt' '$TMP/out.txt'"
echo "First-run tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
