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
index.add
index.search
index.verify
preset.add
preset.get
host.detect
ae.render
c4d.render
trace.asset
audit.plugins
project.diff
project.health
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
  | grep -E '^[[:space:]]+[a-z0-9]+\.[a-z0-9]+(\|[a-z0-9]+\.[a-z0-9]+)+\)' \
  | sed -E 's/^[[:space:]]+//; s/\).*//; s/\|/\n/g' \
  | sort -u > "$TMP/protocol"

sed -n '/case "\$REQUEST_COMMAND" in/,/esac/p' "$ROOT/src/cli/entry.zsh" \
  | sed -nE 's/^[[:space:]]+([a-z0-9]+\.[a-z0-9]+)\).*/\1/p' \
  | sort -u > "$TMP/router"

awk '/var allowed = \[/,/\];/' "$ROOT/integrations/after-effects/MographJailed_Client.jsxinc" \
  | grep -oE '"[a-z0-9]+\.[a-z0-9]+"' | tr -d '"' | sort -u > "$TMP/ae"

sed -n '/^operation_names()/,/^}/p' "$ROOT/src/core/operations.zsh" \
  | grep -E '^[[:space:]]+[a-z0-9]+\.[a-z0-9]+( \\)?$' \
  | sed -E 's/^[[:space:]]+//; s/[[:space:]]+\\$//' \
  | sort -u > "$TMP/registry"

check cmp -s "$TMP/expected" "$TMP/protocol"
check cmp -s "$TMP/expected" "$TMP/router"
check cmp -s "$TMP/expected" "$TMP/ae"
check cmp -s "$TMP/expected" "$TMP/registry"

# The installer's checksum list covers the tree as committed.
check sh "$ROOT/scripts/make-manifest.sh" --check

# Version strings must agree: runtime constant, VERSION file, newest CHANGELOG entry.
CONST_V=$(sed -n 's/^MOGRAPHJAILED_CLI_VERSION="\(.*\)"$/\1/p' "$ROOT/src/core/constants.zsh")
FILE_V=$(sed -n '1s/^MographJailed //p' "$ROOT/VERSION")
LOG_V=$(sed -n 's/^## \([0-9][0-9A-Za-z.-]*\).*/\1/p' "$ROOT/CHANGELOG.md" | head -1)
check test -n "$CONST_V" -a "$CONST_V" = "$FILE_V"
check test "$CONST_V" = "$LOG_V"

printf 'Contract audit tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
