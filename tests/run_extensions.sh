#!/usr/bin/env bash
# #39: a typed .aep / .c4d picks that kind; an exact name is never mixed with longer names; the two kinds keep
# separate version histories.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P); trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
export HOME="$TMP/home"; mkdir -p "$HOME"; export MJ_CONFIG="$TMP/cfg" MJ_STORE_DIR="$TMP/store" MJ_CLI="$CLI" MJ_AUDIT_DIR="$TMP/noaudit"
mkdir -p "$TMP/proj/Logo" "$TMP/ver"
for f in "Logo.aep" "Logo.c4d" "Logo Sting.c4d" "Logo Sting.aep"; do printf 'bytes of %s' "$f" > "$TMP/proj/Logo/$f"; done
mjz(){ zsh -f -c "source '$ROOT/scripts/shell/mj-cli.zsh'; mj $1" > "$TMP/out.txt" 2> "$TMP/err.txt"; echo $? > "$TMP/rc"; }
mjz "config set watch_dir '$TMP/proj' >/dev/null; mj config set versions_dir '$TMP/ver' >/dev/null; mj config set receipts_dir '$TMP/rep' >/dev/null"

# a plain name that two projects share lists exactly those two, not the longer names
mjz "snapshot Logo"; check test "$(cat "$TMP/rc")" = 65
check grep -q 'matches more than one project' "$TMP/err.txt"
check test "$(grep -c '^  /' "$TMP/err.txt")" = 2
check grep -q 'Logo/Logo.aep' "$TMP/err.txt"; check grep -q 'Logo/Logo.c4d' "$TMP/err.txt"; check bash -c "! grep -q 'Sting' '$TMP/err.txt'"
check test -z "$(ls -A "$TMP/ver")"                                                  # nothing was saved while it asked

# a typed extension picks the kind, in any case
mjz "snapshot Logo.aep"; check test "$(cat "$TMP/rc")" = 0; check grep -q 'Saved a verified copy of Logo.aep' "$TMP/out.txt"
mjz "snapshot Logo.c4d"; check test "$(cat "$TMP/rc")" = 0; check grep -q 'Saved a verified copy of Logo.c4d' "$TMP/out.txt"
mjz "snapshot LOGO.AEP"; check test "$(cat "$TMP/rc")" = 0; check grep -q 'Nothing to save' "$TMP/out.txt"
# the two kinds keep their own histories
check test -f "$TMP/ver/Logo.latest.json" -a -f "$TMP/ver/Logo.c4d.latest.json"
check test "$(ls "$TMP/ver" | grep -c '\.aep$')" = 1; check test "$(ls "$TMP/ver" | grep -c '\.c4d$')" = 1
mjz "versions Logo"; check grep -q 'Logo ' "$TMP/out.txt"; check grep -q 'Logo.c4d' "$TMP/out.txt"
# an exact full name beats longer names that begin with it
mjz "snapshot 'Logo Sting'"; check test "$(cat "$TMP/rc")" = 65                       # two exact (.aep and .c4d)
mjz "snapshot 'Logo Sting.aep'"; check test "$(cat "$TMP/rc")" = 0; check grep -q 'Saved a verified copy of Logo Sting.aep' "$TMP/out.txt"
# a prefix with an extension is limited to that kind
mjz "snapshot 'Logo S.c4d'"; check test "$(cat "$TMP/rc")" = 0; check grep -q 'Logo Sting.c4d' "$TMP/out.txt"
mjz "snapshot 'Log.aep'"; check test "$(cat "$TMP/rc")" = 65; check test "$(grep -c '^  /' "$TMP/err.txt")" = 2; check bash -c "! grep -q '\.c4d' '$TMP/err.txt'"
# a name with no such kind says so
mkdir -p "$TMP/proj/Only"; printf x > "$TMP/proj/Only/Only.aep"
mjz "snapshot Only.c4d"; check test "$(cat "$TMP/rc")" = 66; check grep -q 'no project found' "$TMP/err.txt"
mjz "snapshot Only"; check test "$(cat "$TMP/rc")" = 0
echo "Extension tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
