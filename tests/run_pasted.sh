#!/usr/bin/env bash
# #46: text pasted from chat apps, web pages and word processors works: curly quotes around a name, em/en dashes
# for --options, non-breaking and zero-width spaces. Straight quotes and apostrophes inside names are untouched.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P); trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
export HOME="$TMP/home"; mkdir -p "$HOME"; export MJ_CONFIG="$TMP/cfg" MJ_STORE_DIR="$TMP/store" MJ_CLI="$CLI" MJ_AUDIT_DIR="$TMP/noaudit"
python3 "$ROOT/tests/support/make_tutorial_fixtures.py" "$TMP/AE" >/dev/null
mkdir -p "$TMP/ver" "$TMP/my folder/sub dir"; printf 'hello' > "$TMP/my folder/sub dir/file.txt"; printf 'bob' > "$TMP/AE/projects/Bob’s Title.aep"; touch -t 202609210000 "$TMP/AE/projects/Bob’s Title.aep"
# the line is run exactly as a person's pasted text would be: the characters are in the command line itself
mjz(){ zsh -f -c "source '$ROOT/scripts/shell/mj-cli.zsh'; mj $1" > "$TMP/out.txt" 2> "$TMP/err.txt"; echo $? > "$TMP/rc"; }
mjz "config set watch_dir '$TMP/AE/projects' >/dev/null; mj config set versions_dir '$TMP/ver' >/dev/null; mj config set receipts_dir '$TMP/AE/receipts' >/dev/null"
saved(){ check test "$(cat "$TMP/rc")" = 0; check grep -q 'Saved a verified copy\|Nothing to save' "$TMP/out.txt"; }

mjz 'snapshot “Spring Promo”';  saved
mjz 'snapshot ‘Summer Sale’';   saved
mjz 'snapshot „Spring Promo“';  saved
mjz 'snapshot «Spring Promo»';  saved
mjz 'snapshot "Spring Promo"';  saved                                                        # straight quotes still work
mjz 'snapshot “Bob’s Title”';   saved; check grep -q "Bob’s Title" "$TMP/out.txt"           # an apostrophe inside a name is part of the name
mjz 'snapshot “Spring Promo” ';  saved                                                       # trailing space after the quote
mjz 'snapshot “Spring”';        saved                                                        # a one-word quote
# non-breaking and zero-width spaces
mjz $'snapshot Spring Promo';    saved
mjz $'snapshot Sum​mer​ Sale' ; check test "$(cat "$TMP/rc")" -ne 0 -o -n "$(cat "$TMP/out.txt")"
mjz $'snapshot "Summer Sale"';   saved
# dashes
mjz 'conform Spring —apply --label dashA';     check test "$(cat "$TMP/rc")" = 0; check grep -q 'Made a conform job' "$TMP/out.txt"
mjz 'conform Spring –apply --label dashB';     check test "$(cat "$TMP/rc")" = 0; check grep -q 'Made a conform job' "$TMP/out.txt"
mjz 'conform Spring —label dashC —apply';      check test "$(cat "$TMP/rc")" = 0; check test -d "$TMP/ver/dashC.mjjob"
mjz 'conform Spring --apply --label dashD';    check test "$(cat "$TMP/rc")" = 0                  # real double hyphens unchanged
# quoted values after options and inside key=value
mjz 'extract Spring “Lower Third” --label quoted'; check grep -q 'Made an extract job' "$TMP/out.txt"; check test -d "$TMP/ver/quoted.mjjob"
mjz "config set versions_dir “$TMP/my folder/sub dir”"; check test "$(cat "$TMP/rc")" = 0; check test "$(zsh -f -c "source '$ROOT/scripts/shell/mj-config.zsh'; mj_config_get versions_dir")" = "$TMP/my folder/sub dir"
mjz "config set versions_dir '$TMP/ver' >/dev/null"
mjz "file.inspect path=“$TMP/my folder/sub dir/file.txt”"; check test "$(cat "$TMP/rc")" = 0; check grep -q '"ok":true' "$TMP/out.txt"
# a quote that is never closed stops with an explanation and does nothing
mjz 'snapshot “Spring Promo'
check test "$(cat "$TMP/rc")" = 64; check grep -q 'opening curly quote' "$TMP/err.txt"; check grep -q 'normal quote key' "$TMP/err.txt"
n_before=$(ls "$TMP/ver" | wc -l | tr -d ' '); mjz 'snapshot “Summer Sale'; check test "$(ls "$TMP/ver" | wc -l | tr -d ' ')" = "$n_before"
# any locale: cron, launchd and `env -i` shells have no UTF-8 locale, and every command must still run
for loc in C POSIX en_US.UTF-8; do
  env -i HOME="$HOME" PATH=/usr/bin:/bin LC_ALL=$loc MJ_CONFIG="$MJ_CONFIG" MJ_STORE_DIR="$MJ_STORE_DIR" MJ_CLI="$CLI" MJ_AUDIT_DIR="$TMP/noaudit" /bin/zsh -f -c "source '$ROOT/scripts/shell/mj-cli.zsh'; mj versions; mj snapshot “Spring Promo”; mj conform Spring —apply --label loc$loc" > "$TMP/out.txt" 2> "$TMP/err.txt"
  check bash -c "! grep -q 'not in range\|command not found' '$TMP/err.txt'"; check grep -q 'Made a conform job' "$TMP/out.txt"; check test -d "$TMP/ver/loc$loc.mjjob"
done
echo "Pasted-text tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
