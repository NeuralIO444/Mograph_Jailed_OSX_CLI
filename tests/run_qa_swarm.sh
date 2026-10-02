#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh"
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check() { if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
b64(){ printf '%s' "$1" | base64 -w0; }
run_req(){
  local name=$1
  set +e
  "$CLI" --request "$TMP/$name.req" > "$TMP/$name.json"
  RC=$?
  set -e
}

# Blank structured errors are never allowed.
cat > "$TMP/missing.req" <<'REQ'
MOGRAPHJAILED_REQUEST 1
requestId=swarm-missing
command=package.create
arg.path=L3RtcA==
REQ
run_req missing
check test "$RC" -ne 0
check jq -e '.error.code=="MISSING_ARGUMENT" and (.error.message|length)>0' "$TMP/missing.json"

# Every path-requiring command returns a populated missing-argument error.
for cmd in file.inspect file.hash volume.inspect temp.clean media.inspect media.timing media.frame; do
  name="missing-${cmd//./-}"
  cat > "$TMP/$name.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=swarm-$name
command=$cmd
REQ
  run_req "$name"
  check test "$RC" -ne 0
  check jq -e '.error.code=="MISSING_ARGUMENT" and (.error.message|length)>0' "$TMP/$name.json"
done

# Known-but-irrelevant args are rejected.
cat > "$TMP/ignored.req" <<'REQ'
MOGRAPHJAILED_REQUEST 1
requestId=swarm-extra
command=report.tech
arg.format=anNvbg==
REQ
run_req ignored
check test "$RC" -ne 0
check jq -e '.error.code=="UNEXPECTED_ARGUMENT"' "$TMP/ignored.json"

# Hostile path bytes remain data and cannot create the canary.
CANARY="$TMP/CANARY"
attack="/tmp/' ; touch $CANARY ; #"
cat > "$TMP/hostile.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=swarm-hostile
command=file.inspect
arg.path=$(b64 "$attack")
REQ
run_req hostile
check test "$RC" -ne 0
check test ! -e "$CANARY"
check jq -e '.error.code=="NOT_FOUND"' "$TMP/hostile.json"

# Every response must be valid JSON with the expected protocol envelope.
for f in "$TMP"/*.json; do
  check jq -e '.protocol=="MOGRAPHJAILED" and .protocolVersion==1 and (.ok|type)=="boolean" and (.error==null or ((.error.code|type)=="string" and (.error.message|type)=="string"))' "$f"
done

# Darwin volume classification must use df -Y, not BSD stat %T.
check grep -q '/bin/df -kY' "$ROOT/src/lib/local_fs.zsh"
check sh -c '! grep -q "/usr/bin/stat -f '''%T'''" "$1/src/lib/local_fs.zsh"' sh "$ROOT"

# Production source must contain no generic shell executor or eval.
check sh -c '! grep -RInE "(^|[^A-Za-z])(eval|shell\\.execute|sh -c|zsh -c)([^A-Za-z]|$)" "$1/src" "$1/integrations"' sh "$ROOT"


# Production bundle must exactly match the modular source build graph.
EXPECTED_DIST="$TMP/mograph-jailed-expected.zsh"
: > "$EXPECTED_DIST"
printf '%s\n' '#!/bin/zsh -f' 'emulate -R zsh' 'set -u' >> "$EXPECTED_DIST"
for f in \
  src/core/constants.zsh \
  src/core/json.zsh \
  src/core/errors.zsh \
  src/core/response.zsh \
  src/core/protocol.zsh \
  src/core/path.zsh \
  src/core/capabilities.zsh \
  src/core/operations.zsh \
  src/lib/local_fs.zsh \
  src/lib/native_db.zsh \
  src/lib/media_probe.zsh \
  src/lib/image_kit.zsh \
  src/lib/image_stats.zsh \
  src/lib/frame_kit.zsh \
  src/lib/standard_library.zsh \
  src/modules/system.zsh \
  src/modules/file.zsh \
  src/modules/runtime.zsh \
  src/modules/volume.zsh \
  src/modules/temp.zsh \
  src/modules/media.zsh \
  src/modules/asset.zsh \
  src/modules/provenance.zsh \
  src/modules/image.zsh \
  src/modules/storage.zsh \
  src/modules/search.zsh \
  src/modules/report.zsh \
  src/modules/package.zsh \
  src/modules/project.zsh \
  src/modules/frames.zsh \
  src/modules/audit.zsh \
  src/modules/protect.zsh \
  src/modules/library.zsh \
  src/modules/insight.zsh \
  src/modules/c4d.zsh \
  src/modules/studio.zsh \
  src/modules/space.zsh \
  src/modules/host.zsh \
  src/cli/entry.zsh; do
  printf '\n# --- %s ---\n' "$f" >> "$EXPECTED_DIST"
  cat "$ROOT/$f" >> "$EXPECTED_DIST"
done
check cmp -s "$EXPECTED_DIST" "$ROOT/dist/mograph-jailed.zsh"

printf 'QA swarm regression tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
