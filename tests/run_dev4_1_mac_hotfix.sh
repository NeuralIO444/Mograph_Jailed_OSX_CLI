#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0
check() { if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }

# zsh FUNCTION_ARGZERO compatibility: runtime_self_path must prefer ZSH_ARGZERO.
check grep -q 'ZSH_ARGZERO' "$ROOT/src/modules/runtime.zsh"
check grep -q 'ZSH_VERSION' "$ROOT/src/modules/runtime.zsh"

# Simulate the zsh stable script-name variables in the portable QA shell.
cat > "$TMP/test-runtime-path.sh" <<EOF2
#!/usr/bin/env bash
ZSH_VERSION=5.9
ZSH_ARGZERO="$ROOT/dist/mograph-jailed.zsh"
source "$ROOT/src/modules/runtime.zsh"
runtime_self_path
EOF2
chmod +x "$TMP/test-runtime-path.sh"
PATH_RESULT=$("$TMP/test-runtime-path.sh")
check test "$PATH_RESULT" = "$ROOT/dist/mograph-jailed.zsh"

# mj-top wrapper must launch a clean zsh worker rather than a parent-shell subshell.
check grep -q '/bin/zsh -f "\$runner"' "$ROOT/scripts/shell/mj-top.zsh"
check test -f "$ROOT/scripts/terminal/mj-top-run.zsh"
check grep -q '^#!/bin/zsh -f' "$ROOT/scripts/terminal/mj-top-run.zsh"
check grep -q 'trap cleanup_top_files EXIT HUP INT TERM' "$ROOT/scripts/terminal/mj-top-run.zsh"
check grep -q 'command=runtime.verify' "$ROOT/scripts/terminal/mj-top-run.zsh"
check grep -q 'arg.expectedFilename=' "$ROOT/scripts/terminal/mj-top-run.zsh"

# The wrapper itself must not contain the old whole-function subshell body.
if grep -q '^    ($' "$ROOT/scripts/shell/mj-top.zsh"; then
  echo 'FAIL: old mj-top wrapper subshell body remains' >&2
  fail=$((fail+1))
else
  pass=$((pass+1))
fi

# Release identity.
check grep -q 'MOGRAPHJAILED_CLI_VERSION="0.4.0-dev.1"' "$ROOT/src/core/constants.zsh"
check grep -q '^MographJailed 0.4.0-dev.1$' "$ROOT/VERSION"

printf 'dev.4.1 Mac hotfix tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
