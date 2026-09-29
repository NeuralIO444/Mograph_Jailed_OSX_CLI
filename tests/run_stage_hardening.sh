#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }

# Directly exercise ownership-bound stage helpers without invoking macOS-only adapters.
# shellcheck disable=SC1090
source "$ROOT/src/core/constants.zsh"
# shellcheck disable=SC1090
source "$ROOT/src/core/path.zsh"
REQUEST_ID="qa-stage-owner"
mkdir -p "$TMP/out"
create_mj_stage_dir "$TMP/out" "MographJailed_QA"
STAGE="$MJ_STAGE_DIR"
check test -d "$STAGE"
check test -f "$STAGE/.mj_native_stage"
check is_safe_mj_stage_dir "$STAGE" "$TMP/out" "MographJailed_QA"
check grep -qx 'qa-stage-owner' "$STAGE/.mj_native_stage"
check grep -qx "$STAGE" "$STAGE/.mj_native_stage"

# Marker tampering must refuse recursive cleanup and leave the directory intact.
cp "$STAGE/.mj_native_stage" "$TMP/marker.good"
sed -i '2s/.*/other-request/' "$STAGE/.mj_native_stage"
set +e
cleanup_mj_stage_dir "$STAGE" "$TMP/out" "MographJailed_QA"
RC=$?
set -e
check test "$RC" -ne 0
check test -d "$STAGE"
cp "$TMP/marker.good" "$STAGE/.mj_native_stage"
check cleanup_mj_stage_dir "$STAGE" "$TMP/out" "MographJailed_QA"
check test ! -e "$STAGE"

# Missing ownership proof must also refuse cleanup.
create_mj_stage_dir "$TMP/out" "MographJailed_QA"
STAGE2="$MJ_STAGE_DIR"
rm -f "$STAGE2/.mj_native_stage"
set +e
cleanup_mj_stage_dir "$STAGE2" "$TMP/out" "MographJailed_QA"
RC=$?
set -e
check test "$RC" -ne 0
check test -d "$STAGE2"
rm -rf "$STAGE2" # QA harness cleanup only.

# Production image/package modules must route stage creation and deletion through the guard.
check grep -q 'create_mj_stage_dir' "$ROOT/src/modules/image.zsh"
check grep -q 'cleanup_mj_stage_dir' "$ROOT/src/modules/image.zsh"
check grep -q 'create_mj_stage_dir' "$ROOT/src/modules/package.zsh"
check grep -q 'cleanup_mj_stage_dir' "$ROOT/src/modules/package.zsh"
check /bin/bash -c '! grep -F '\''/bin/rm -rf "$_stage"'\'' "$1/src/modules/image.zsh" "$1/src/modules/package.zsh"' bash "$ROOT"

# image.inspect must positively identify a raster image rather than succeeding with nulls.
check grep -q 'image_positive_identification "$_path"' "$ROOT/src/modules/image.zsh"
check grep -q 'sips did not positively identify the target as a raster image' "$ROOT/src/modules/image.zsh"

# Capability Registry must match helper dependencies used by corrected operations.
cat > "$TMP/describe.req" <<'REQ'
MOGRAPHJAILED_REQUEST 1
requestId=qa-stage-describe
command=system.describe
REQ
"$CLI" --request "$TMP/describe.req" > "$TMP/describe.json"
check jq -e '.cliVersion=="0.3.0-dev.2"' "$TMP/describe.json"
check jq -e '.data.operations["image.derivative"].requires.all | index("uname") != null' "$TMP/describe.json"
check jq -e '.data.operations["asset.manifest"].requires.all | index("uname") != null' "$TMP/describe.json"
check jq -e '.data.operations["storage.preflight"].requires.all == ["df","awk","uname"]' "$TMP/describe.json"
check jq -e '.data.operations["package.create"].requires.all | index("uname") != null' "$TMP/describe.json"

# Generated bundle must contain the ownership marker logic and no stale dev.2 version.
"$ROOT/scripts/build.zsh" >/dev/null
check grep -q '.mj_native_stage' "$ROOT/dist/mograph-jailed.zsh"
check /bin/bash -c '! grep -q "0.2.0-dev.2" "$1/dist/mograph-jailed.zsh"' bash "$ROOT"

printf 'Stage hardening tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
