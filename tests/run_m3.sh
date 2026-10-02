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
req() {
  local id=$1 cmd=$2 path=$3 out=$4
  {
    echo 'MOGRAPHJAILED_REQUEST 1'; echo "requestId=$id"; echo "command=$cmd"
    printf 'arg.path=%s\n' "$(printf '%s' "$path" | base64 -w0)"
  } > "$TMP/$id.req"
  set +e; "$CLI" --request "$TMP/$id.req" > "$out"; RC=$?; set -e
}

# ffmpeg is test-fixture tooling only; it is not a MographJailed runtime dependency.
ffmpeg -loglevel error -f lavfi -i color=size=160x90:rate=24:color=black -t 0.5 -c:v libx264 -pix_fmt yuv420p "$TMP/sample.mp4"
BEFORE=$(sha256sum "$TMP/sample.mp4" | awk '{print $1}')
req m3-001 media.inspect "$TMP/sample.mp4" "$TMP/inspect.json"
check test "$RC" -eq 0
check jq -e '.ok==true and .data.sizeBytes>0 and (.data.basicType|type=="string") and .data.nativeProbe=="unavailable" and .data.sources.filesystem==["stat","file"]' "$TMP/inspect.json"
check jq -e '.data.durationSeconds==null and .data.metadata.mdlsAdvisory==false' "$TMP/inspect.json"
AFTER=$(sha256sum "$TMP/sample.mp4" | awk '{print $1}')
check test "$BEFORE" = "$AFTER"

req m3-002 media.timing "$TMP/sample.mp4" "$TMP/timing.json"
check test "$RC" -ne 0
check jq -e '.ok==false and .error.code=="UNSUPPORTED"' "$TMP/timing.json"

printf 'not-media' > "$TMP/bad.bin"
req m3-003 media.inspect "$TMP/bad.bin" "$TMP/bad.json"
check test "$RC" -eq 0
check jq -e '.ok==true and .data.durationSeconds==null' "$TMP/bad.json"

printf 'M3 tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
