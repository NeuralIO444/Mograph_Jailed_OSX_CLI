#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
b64(){ printf '%s' "$1" | base64 | tr -d '\n'; }

# Pure validation helpers.
# shellcheck disable=SC1090
source "$ROOT/src/core/constants.zsh"
# shellcheck disable=SC1090
source "$ROOT/src/core/errors.zsh"
# shellcheck disable=SC1090
source "$ROOT/src/core/capabilities.zsh"
# shellcheck disable=SC1090
source "$ROOT/src/lib/local_fs.zsh"
# shellcheck disable=SC1090
source "$ROOT/src/lib/media_probe.zsh"
# shellcheck disable=SC1090
source "$ROOT/src/lib/image_kit.zsh"
# shellcheck disable=SC1090
source "$ROOT/src/lib/frame_kit.zsh"

check frame_kit_is_time_seconds 0
check frame_kit_is_time_seconds 1
check frame_kit_is_time_seconds 1.234567
if frame_kit_is_time_seconds -1; then fail=$((fail+1)); echo 'FAIL: negative time accepted' >&2; else pass=$((pass+1)); fi
if frame_kit_is_time_seconds 1e3; then fail=$((fail+1)); echo 'FAIL: exponent time accepted' >&2; else pass=$((pass+1)); fi
if frame_kit_is_time_seconds nan; then fail=$((fail+1)); echo 'FAIL: nan time accepted' >&2; else pass=$((pass+1)); fi
check frame_kit_is_max_pixels 64
check frame_kit_is_max_pixels 2048
check frame_kit_is_max_pixels 4096
if frame_kit_is_max_pixels 63; then fail=$((fail+1)); echo 'FAIL: maxPixels 63 accepted' >&2; else pass=$((pass+1)); fi
if frame_kit_is_max_pixels 4097; then fail=$((fail+1)); echo 'FAIL: maxPixels 4097 accepted' >&2; else pass=$((pass+1)); fi
if frame_kit_is_max_pixels 1024.5; then fail=$((fail+1)); echo 'FAIL: decimal maxPixels accepted' >&2; else pass=$((pass+1)); fi
check frame_kit_time_before_duration 0 5.005
check frame_kit_time_before_duration 5.004 5.005
if frame_kit_time_before_duration 5.005 5.005; then fail=$((fail+1)); echo 'FAIL: end time accepted' >&2; else pass=$((pass+1)); fi
if frame_kit_time_before_duration 9 5.005; then fail=$((fail+1)); echo 'FAIL: out-of-range time accepted' >&2; else pass=$((pass+1)); fi

# Contract/registry.
cat > "$TMP/describe.req" <<'REQ'
MOGRAPHJAILED_REQUEST 1
requestId=framekit-describe
command=system.describe
REQ
"$CLI" --request "$TMP/describe.req" > "$TMP/describe.json"
check jq -e '.ok==true and .cliVersion=="0.4.0-dev.2" and (.data.operations|length)==56' "$TMP/describe.json"
check jq -e '.data.operations["media.frame"].cost=="FRAME_DECODE" and .data.operations["media.frame"].mutation=="DERIVATIVE_CREATE" and .data.operations["media.frame"].authority=="NATIVE_FRAME_DERIVATIVE" and .data.operations["media.frame"].executionScope=="LOCAL_ONLY" and .data.operations["media.frame"].interactiveSafe==false' "$TMP/describe.json"
check jq -e '.data.operations["media.frame"].requires.all==["avmediainfo","python3","jq","sips","awk","df","mktemp","mv","rm","stat","uname"]' "$TMP/describe.json"
check jq -e '.data.standardLibrary.modules.FrameKit.authority=="NATIVE_FRAME_DERIVATIVE" and .data.standardLibrary.modules.FrameKit.executionScope=="LOCAL_ONLY" and .data.standardLibrary.modules.FrameKit.exactRequest==true and .data.standardLibrary.modules.FrameKit.trackTransform==true and .data.standardLibrary.modules.FrameKit.publicGenericJXA==false and .data.standardLibrary.modules.FrameKit.targetMacQualificationRequired==true' "$TMP/describe.json"

# Protocol schema recognizes media.frame before capability execution.
cat > "$TMP/missing.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=framekit-missing
command=media.frame
arg.path=$(b64 /tmp/source.mov)
REQ
"$CLI" --request "$TMP/missing.req" > "$TMP/missing.json" || true
check jq -e '.ok==false and .error.code=="MISSING_ARGUMENT"' "$TMP/missing.json"

cat > "$TMP/extra.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=framekit-extra
command=media.frame
arg.path=$(b64 /tmp/source.mov)
arg.output=$(b64 /tmp/frame.png)
arg.timeSeconds=$(b64 1.0)
arg.target=$(b64 unexpected)
REQ
"$CLI" --request "$TMP/extra.req" > "$TMP/extra.json" || true
check jq -e '.ok==false and .error.code=="UNEXPECTED_ARGUMENT"' "$TMP/extra.json"

# Static safety boundaries around the embedded adapter.
check grep -q 'AVFoundation.framework' "$ROOT/src/lib/frame_kit.zsh"
check grep -q 'ImageIO.framework' "$ROOT/src/lib/frame_kit.zsh"
check grep -q "setRequestedTimeToleranceBefore:" "$ROOT/src/lib/frame_kit.zsh"
check grep -q "setRequestedTimeToleranceAfter:" "$ROOT/src/lib/frame_kit.zsh"
check grep -q "setAppliesPreferredTrackTransform:" "$ROOT/src/lib/frame_kit.zsh"
check grep -q "copyCGImageAtTime:" "$ROOT/src/lib/frame_kit.zsh"
check grep -q 'actualSeconds' "$ROOT/src/lib/frame_kit.zsh"
check grep -q 'MJ_FRAMEKIT_FLOOR_VALUE' "$ROOT/src/lib/frame_kit.zsh"
check grep -q 'INVALID_FLOOR_TIME' "$ROOT/src/lib/frame_kit.zsh"
check grep -q 'media_probe_sample_floor_ticks' "$ROOT/src/modules/media.zsh"
check /bin/bash -c '! grep -q "nominalFrameRate" "$1/src/lib/frame_kit.zsh"' bash "$ROOT"
check /bin/bash -c '! grep -E "eval\\(|Function\\(|curl|nc |https?://|/Volumes/" "$1/src/lib/frame_kit.zsh"' bash "$ROOT"
check /bin/bash -c '! grep -RInE "jxa\\.(exec|run)|objc\\.(exec|run)|shell\\.execute" "$1/src/core" "$1/src/modules" "$1/src/lib" >/dev/null' bash "$ROOT"
check grep -q 'mj_require_local_existing_path "\$_path"' "$ROOT/src/modules/media.zsh"
check grep -q 'mj_require_local_existing_path "\$_parent_real"' "$ROOT/src/modules/media.zsh"
check grep -q 'Refusing to overwrite an existing frame derivative' "$ROOT/src/modules/media.zsh"
check grep -q 'Client.prototype.mediaFrame' "$ROOT/integrations/after-effects/MographJailed_Client.jsxinc"
check grep -q '"media.frame"' "$ROOT/integrations/after-effects/MographJailed_Client.jsxinc"

printf 'FrameKit M2 portable tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
