#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
check_not(){ if "$@"; then echo "FAIL (unexpected success): $*" >&2; fail=$((fail+1)); else pass=$((pass+1)); fi; }

cat > "$TMP/describe.req" <<'REQ'
MOGRAPHJAILED_REQUEST 1
requestId=dev4-describe
command=system.describe
REQ
"$CLI" --request "$TMP/describe.req" > "$TMP/describe.json"

# Registry serialization must be true JSON arrays with one capability per element.
check jq -e '.cliVersion=="0.3.0-dev.2"' "$TMP/describe.json"
check jq -e '.data.operations["file.inspect"].requires.all == ["stat","file","uname"]' "$TMP/describe.json"
check jq -e '.data.operations["image.derivative"].requires.all == ["sips","awk","mktemp","mv","rm","stat","uname"]' "$TMP/describe.json"
check jq -e '.data.operations["package.create"].requires.all == ["ditto","mktemp","rm","mv","stat","uname"]' "$TMP/describe.json"
check jq -e '.data.operations["runtime.verify"].optionalCapabilities == ["sha256","shasum"]' "$TMP/describe.json"
check jq -e '.data.operations["media.inspect"].optionalCapabilities == ["mdls","avmediainfo"]' "$TMP/describe.json"
check jq -e '[.data.operations[] | .requires.all[]?] | all(contains(" ")|not)' "$TMP/describe.json"
check jq -e '[.data.operations[] | .optionalCapabilities[]?] | all(contains(" ")|not)' "$TMP/describe.json"
check jq -e '.data.operations["file.hash"].requires.anyOf == [["sha256","shasum"]]' "$TMP/describe.json"

# Source implementation must not rely on shell-specific scalar word splitting.
check grep -q 'emit_string_array_lines' "$ROOT/src/core/operations.zsh"
check_not grep -Fq 'for _item in $_items' "$ROOT/src/core/operations.zsh"
check grep -q 'operation_required_all "\$_name" | emit_string_array_lines' "$ROOT/src/core/operations.zsh"
check grep -q 'operation_optional_capabilities "\$_name" | emit_string_array_lines' "$ROOT/src/core/operations.zsh"

# Local help topics and render assets exist.
for topic in overview commands protocol safety looper organize terminal troubleshooting recovery; do
  check test -r "$ROOT/docs/man/$topic.md"
done
check test -r "$ROOT/scripts/terminal/mj-md-render.awk"
check test -r "$ROOT/scripts/shell/mj-terminal.zsh"
check test -r "$ROOT/scripts/shell/mj-man.zsh"
check test -r "$ROOT/scripts/shell/mj-top.zsh"
check test -r "$ROOT/scripts/terminal/mj-top-render.js"
check test -r "$ROOT/scripts/terminal/mj-top-run.zsh"
check grep -q 'Dashboard worker is missing' "$ROOT/scripts/shell/install-terminal-ux.sh"

# mj-man is source-safe, lists new topics, and produces plain readable output when redirected.
MOGRAPHJAILED_ROOT="$ROOT" /bin/bash -c 'source "$MOGRAPHJAILED_ROOT/scripts/shell/mj-terminal.zsh"; source "$MOGRAPHJAILED_ROOT/scripts/shell/mj-man.zsh"; mj-man list' > "$TMP/man-list.txt"
check grep -qx 'organize' "$TMP/man-list.txt"
check grep -qx 'terminal' "$TMP/man-list.txt"
MOGRAPHJAILED_ROOT="$ROOT" TERM=dumb /bin/bash -c 'source "$MOGRAPHJAILED_ROOT/scripts/shell/mj-terminal.zsh"; source "$MOGRAPHJAILED_ROOT/scripts/shell/mj-man.zsh"; mj-man commands' > "$TMP/man-commands.txt"
check grep -q '^MOGRAPHJAILED PUBLIC OPERATIONS$' "$TMP/man-commands.txt"
check_not grep -q '^```' "$TMP/man-commands.txt"
check_not grep -q '^#' "$TMP/man-commands.txt"
ESC=$(printf '\033')
check_not grep -Fq "$ESC" "$TMP/man-commands.txt"

# Renderer removes Markdown fences and inline backticks in plain mode.
printf '# Title\n\n```text\nhello\n```\n- `thing`\n' > "$TMP/sample.md"
/usr/bin/awk -v color=0 -f "$ROOT/scripts/terminal/mj-md-render.awk" "$TMP/sample.md" > "$TMP/rendered.txt"
check grep -q '^TITLE$' "$TMP/rendered.txt"
check grep -q '^    hello$' "$TMP/rendered.txt"
check grep -q '^  - thing$' "$TMP/rendered.txt"
BACKTICK=$(printf '\140')
check_not grep -Fq "$BACKTICK" "$TMP/rendered.txt"

# Dashboard remains snapshot-only and consumes the audited protocol rather than native evidence commands.
TOP_RUNNER="$ROOT/scripts/terminal/mj-top-run.zsh"
check grep -q 'system.doctor' "$TOP_RUNNER"
check grep -q 'system.describe' "$TOP_RUNNER"
check grep -q 'runtime.verify' "$TOP_RUNNER"
check grep -q 'storage.preflight' "$TOP_RUNNER"
check_not grep -E 'mdfind|xattr|sips|mdls|ditto|avmediainfo' "$ROOT/scripts/shell/mj-top.zsh" "$TOP_RUNNER"
check_not grep -Ei 'sleep|setInterval|setTimeout' "$ROOT/scripts/shell/mj-top.zsh" "$TOP_RUNNER" "$ROOT/scripts/terminal/mj-top-render.js"
check grep -q 'Usage: mj-top \[--plain|--ascii\]' "$TOP_RUNNER"
check grep -q 'NO_COLOR' "$ROOT/scripts/shell/mj-terminal.zsh"
check grep -q 'MJ_ASCII' "$ROOT/scripts/shell/mj-terminal.zsh"
check grep -q 'mode === '\''modern'\''' "$ROOT/scripts/terminal/mj-top-render.js"
check grep -q 'Math.max(36' "$ROOT/scripts/terminal/mj-top-render.js"
check grep -q 'labelWidth = width >= 70' "$ROOT/scripts/terminal/mj-top-render.js"
check grep -q "mode=plain" "$TOP_RUNNER"
check grep -q "mode=ascii" "$TOP_RUNNER"
check node --check "$ROOT/scripts/terminal/mj-top-render.js"

# Invalid top arguments fail before any native dashboard work.
set +e
MOGRAPHJAILED_ROOT="$ROOT" /bin/bash "$TOP_RUNNER" --bad > "$TMP/top-bad.out" 2> "$TMP/top-bad.err"
RC=$?
set -e
check test "$RC" -eq 64
check grep -q '^Usage: mj-top' "$TMP/top-bad.err"

# Local installer is idempotent and only changes the MJ-local shell helper.
FAKEHOME="$TMP/home"
FAKEROOT="$FAKEHOME/Documents/MographJailed"
mkdir -p "$FAKEROOT/scripts/shell" "$FAKEROOT/scripts/terminal" "$FAKEROOT/docs/man" "$FAKEROOT/config/shell"
cp "$ROOT/scripts/shell/mj-terminal.zsh" "$ROOT/scripts/shell/mj-man.zsh" "$ROOT/scripts/shell/mj-top.zsh" "$ROOT/scripts/shell/mj-cli.zsh" "$ROOT/scripts/shell/install-terminal-ux.sh" "$FAKEROOT/scripts/shell/"
cp "$ROOT/scripts/terminal/mj-md-render.awk" "$ROOT/scripts/terminal/mj-top-render.js" "$ROOT/scripts/terminal/mj-top-run.zsh" "$FAKEROOT/scripts/terminal/"
printf '# helper\n' > "$FAKEROOT/scripts/shell/mj-shell.zsh"
HOME="$FAKEHOME" MOGRAPHJAILED_ROOT="$FAKEROOT" /bin/bash "$FAKEROOT/scripts/shell/install-terminal-ux.sh" > "$TMP/install1.txt"
HOME="$FAKEHOME" MOGRAPHJAILED_ROOT="$FAKEROOT" /bin/bash "$FAKEROOT/scripts/shell/install-terminal-ux.sh" > "$TMP/install2.txt"
check test "$(grep -c 'scripts/shell/mj-terminal.zsh' "$FAKEROOT/scripts/shell/mj-shell.zsh")" -eq 1
check test "$(grep -c 'scripts/shell/mj-man.zsh' "$FAKEROOT/scripts/shell/mj-shell.zsh")" -eq 1
check test "$(grep -c 'scripts/shell/mj-top.zsh' "$FAKEROOT/scripts/shell/mj-shell.zsh")" -eq 1
check test -d "$FAKEROOT/config/shell"

# Distribution remains the CLI only; terminal UX is intentionally outside the bundled runtime.
"$ROOT/scripts/build.zsh" >/dev/null
check grep -q 'MOGRAPHJAILED_CLI_VERSION="0.3.0-dev.2"' "$ROOT/dist/mograph-jailed.zsh"
check_not grep -q 'mj-top' "$ROOT/dist/mograph-jailed.zsh"
check_not grep -q 'mj-man' "$ROOT/dist/mograph-jailed.zsh"

printf 'dev.4 terminal/registry tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
