#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh"
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
# These suites assert the "native macOS tools are absent" behavior (UNSUPPORTED / UNAVAILABLE). Simulate the
# absence so the same assertions hold on a Mac, which has them, as on a Linux runner, which does not.
export MJ_TEST_MISSING_CAPS="ditto xattr sips mdfind avmediainfo mdls jq"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check() { if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
runreq() {
  local id=$1 cmd=$2 path=${3-} output=${4-} out=$5
  { echo 'MOGRAPHJAILED_REQUEST 1'; echo "requestId=$id"; echo "command=$cmd";
    [[ -n "$path" ]] && printf 'arg.path=%s\n' "$(printf '%s' "$path" | base64 -w0)"
    [[ -n "$output" ]] && printf 'arg.output=%s\n' "$(printf '%s' "$output" | base64 -w0)"
  } > "$TMP/$id.req"
  set +e; "$CLI" --request "$TMP/$id.req" > "$out"; RC=$?; set -e
}
runreq m5-001 report.tech "" "" "$TMP/report.json"
check test "$RC" -eq 0
check jq -e '.ok==true and .data.schema=="MJ_TECH_NATIVE_1" and .data.policy.zeroInstall==true and .data.policy.rawShellAPI==false and (.data.capabilities|type=="object")' "$TMP/report.json"
check jq -e '.data|has("userName")|not' "$TMP/report.json"

mkdir "$TMP/report-folder"; printf 'report' > "$TMP/report-folder/report.json"
runreq m5-002 package.create "$TMP/report-folder" "$TMP/out.zip" "$TMP/package.json"
check test "$RC" -ne 0
check jq -e '.error.code=="UNSUPPORTED"' "$TMP/package.json"
check test ! -e "$TMP/out.zip"

runreq m5-002b package.create "$TMP/report-folder" "$TMP/report-folder/inside.zip" "$TMP/inside.json"
check test "$RC" -ne 0
check jq -e '.error.code=="INVALID_OUTPUT"' "$TMP/inside.json"
check test ! -e "$TMP/report-folder/inside.zip"

# Existing output is refused before any native packager is invoked.
printf 'existing' > "$TMP/existing.zip"
runreq m5-003 package.create "$TMP/report-folder" "$TMP/existing.zip" "$TMP/existing.json"
check test "$RC" -ne 0
check jq -e '.error.code=="OUTPUT_EXISTS"' "$TMP/existing.json"
check grep -q '/usr/bin/ditto -c -k --sequesterRsrc --keepParent' "$ROOT/src/modules/package.zsh"

printf 'M5 tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
