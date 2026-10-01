#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
cat > "$TMP/expected" <<'CMDS'
asset.manifest
asset.verify
file.hash
file.inspect
file.provenance
image.derivative
image.compare
image.inspect
image.stats
media.inspect
media.timing
media.frame
package.create
project.ingest
expression.lint
plugin.audit
project.snapshot
loop.seams
golden.record
golden.check
audit.verify
project.restore
deps.graph
handoff.package
report.tech
runtime.verify
search.candidate
storage.preflight
system.describe
system.doctor
system.probe
temp.clean
temp.create
volume.inspect
CMDS
sort -u "$TMP/expected" -o "$TMP/expected"

awk '/^is_safe_command_name\(\)/,/^}/' "$ROOT/src/core/protocol.zsh" \
  | grep -E '^[[:space:]]+[a-z]+\.[a-z]+(\|[a-z]+\.[a-z]+)+\)' \
  | sed -E 's/^[[:space:]]+//; s/\).*//; s/\|/\n/g' \
  | sort -u > "$TMP/protocol"

sed -n '/case "\$REQUEST_COMMAND" in/,/esac/p' "$ROOT/src/cli/entry.zsh" \
  | sed -nE 's/^[[:space:]]+([a-z]+\.[a-z]+)\).*/\1/p' \
  | sort -u > "$TMP/router"

awk '/var allowed = \[/,/\];/' "$ROOT/integrations/after-effects/MographJailed_Client.jsxinc" \
  | grep -oE '"[a-z]+\.[a-z]+"' | tr -d '"' | sort -u > "$TMP/ae"

sed -n '/^operation_names()/,/^}/p' "$ROOT/src/core/operations.zsh" \
  | grep -E '^[[:space:]]+[a-z]+\.[a-z]+( \\)?$' \
  | sed -E 's/^[[:space:]]+//; s/[[:space:]]+\\$//' \
  | sort -u > "$TMP/registry"

check cmp -s "$TMP/expected" "$TMP/protocol"
check cmp -s "$TMP/expected" "$TMP/router"
check cmp -s "$TMP/expected" "$TMP/ae"
check cmp -s "$TMP/expected" "$TMP/registry"

printf 'Contract audit tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
