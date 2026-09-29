#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }

# Pure Standard Library helpers are portable enough to unit-test in the QA shell.
# shellcheck disable=SC1090
source "$ROOT/src/core/constants.zsh"
# shellcheck disable=SC1090
source "$ROOT/src/core/errors.zsh"
# shellcheck disable=SC1090
source "$ROOT/src/core/capabilities.zsh"
# shellcheck disable=SC1090
source "$ROOT/src/lib/local_fs.zsh"
# shellcheck disable=SC1090
source "$ROOT/src/lib/native_db.zsh"
# shellcheck disable=SC1090
source "$ROOT/src/lib/media_probe.zsh"
# shellcheck disable=SC1090
source "$ROOT/src/lib/image_kit.zsh"
# shellcheck disable=SC1090
source "$ROOT/src/lib/frame_kit.zsh"

check test "$MOGRAPHJAILED_STANDARD_LIBRARY_VERSION" = "1.0"
check test "$(mj_fs_class apfs)" = "local"
check test "$(mj_fs_class overlay)" = "local"
check test "$(mj_fs_class smbfs)" = "network"
check test "$(mj_fs_class nfs)" = "network"
check test "$(mj_fs_class mysteryfs)" = "unknown"
check mj_local_scope_probe "$TMP"
check test "$MJ_LOCAL_SCOPE_CLASS" = "local"
check native_db_validate_store_path "$TMP/mj-test.db"

cat > "$TMP/avmediainfo-header.txt" <<'FIXTURE'
Asset: /System/Library/test.mov
Duration: 5.005 seconds (3003/600)
Track count: 1
Track 1: Video 'vide'
	Enabled: Yes
	Format Description 1:
		Format: H.264 'avc1'
		Dimensions: 240 x 160
		Encoded Pixels: 240 x 160
		Presentation Dimensions: 240 x 160
	System support for decoding this track: Yes
	Data size: 358259 bytes
	Media time scale: 600
	Duration: 5.005 seconds
	Estimated data rate: 572.642 kbit/s
	Nominal frame rate: 29.970 fps
	Language code: eng
	Minimum sample duration: 20/600 seconds
	Frame reordering required
	1 segment present
FIXTURE
HEADER=$(cat "$TMP/avmediainfo-header.txt")
check media_probe_parse_text "$HEADER"
check test "$MJ_MEDIA_DURATION_SECONDS" = "5.005"
check test "$MJ_MEDIA_DURATION_VALUE" = "3003"
check test "$MJ_MEDIA_DURATION_TIMESCALE" = "600"
check test "$MJ_MEDIA_TRACK_COUNT" = "1"
check test "$MJ_MEDIA_VIDEO_TRACK_COUNT" = "1"
check test "$MJ_MEDIA_VIDEO_TRACK_INDEX" = "1"
check test "$MJ_MEDIA_VIDEO_ENABLED" = "true"
check test "$MJ_MEDIA_VIDEO_CODEC" = "H.264"
check test "$MJ_MEDIA_VIDEO_FOURCC" = "avc1"
check test "$MJ_MEDIA_VIDEO_WIDTH" = "240"
check test "$MJ_MEDIA_VIDEO_HEIGHT" = "160"
check test "$MJ_MEDIA_VIDEO_TIMESCALE" = "600"
check test "$MJ_MEDIA_VIDEO_NOMINAL_FPS" = "29.970"
check test "$MJ_MEDIA_VIDEO_MIN_SAMPLE_VALUE" = "20"
check test "$MJ_MEDIA_VIDEO_MIN_SAMPLE_TIMESCALE" = "600"
check test "$MJ_MEDIA_VIDEO_REORDERING" = "true"
check test "$MJ_MEDIA_VIDEO_DECODE_SUPPORTED" = "true"

cat > "$TMP/avmediainfo-audio-only.txt" <<'FIXTURE'
Asset: /System/Library/Sounds/Glass.aiff
Duration: 1.650083 seconds (79204/48000)
Track count: 1
Track 1: Audio 'soun'
FIXTURE
AUDIO_ONLY=$(cat "$TMP/avmediainfo-audio-only.txt")
check media_probe_parse_text "$AUDIO_ONLY"
check test "$MJ_MEDIA_VIDEO_TRACK_COUNT" = "0"
check test -z "$MJ_MEDIA_VIDEO_TRACK_INDEX"

# Shape drift must fail closed rather than emit guessed timing.
BROKEN=$(printf '%s\n' "$HEADER" | sed '/Nominal frame rate:/d')
if media_probe_parse_text "$BROKEN"; then
  echo "FAIL: malformed MediaProbe fixture unexpectedly parsed" >&2
  fail=$((fail+1))
else
  pass=$((pass+1))
fi

# Target-Mac Gate A regression (2026-09-29): avmediainfo --brief on audio-only
# input prints "Error analysis is not supported for format ..." instead of the
# 0-error sentinel. That is a successful container read, not a probe failure,
# so analyzed_ok must accept it; garbage must still fail closed.
AIFF_BRIEF=$(printf '%s\n' \
  'Asset: /System/Library/Sounds/Glass.aiff' \
  'Duration: 1.650 seconds (79204/48000)' \
  'Track count: 1' \
  "Track 1: Sound, Enabled, Format: Linear PCM, 0 bytes, 1.650 seconds" \
  'Error analysis is not supported for format public.aiff-audio.')
check media_probe_analyzed_ok "$AIFF_BRIEF"
if media_probe_analyzed_ok "not a movie"; then
  echo "FAIL: garbage MediaProbe brief unexpectedly analyzed-ok" >&2
  fail=$((fail+1))
else
  pass=$((pass+1))
fi

cat > "$TMP/describe.req" <<'REQ'
MOGRAPHJAILED_REQUEST 1
requestId=stdlib-describe
command=system.describe
REQ
"$CLI" --request "$TMP/describe.req" > "$TMP/describe.json"
check jq -e '.ok==true and .cliVersion=="0.3.0-dev.2"' "$TMP/describe.json"
check jq -e '.data.standardLibrary.version=="1.0" and .data.standardLibrary.policy.localOnlyByDefault==true and .data.standardLibrary.policy.networkMutation==false and .data.standardLibrary.policy.arbitrarySqlAPI==false' "$TMP/describe.json"
check jq -e '.data.standardLibrary.modules.LocalFS.available==true and (.data.standardLibrary.modules.NativeDB.available|type)=="boolean" and .data.standardLibrary.modules.NativeDB.publicSql==false and (.data.standardLibrary.modules.NativeDB.features.json|type)=="boolean" and (.data.standardLibrary.modules.NativeDB.features.fts5|type)=="boolean"' "$TMP/describe.json"
check jq -e '.data.standardLibrary.modules.FrameKit.available==false and .data.standardLibrary.modules.FrameKit.state=="UNAVAILABLE" and .data.standardLibrary.modules.FrameKit.targetMacQualificationRequired==true' "$TMP/describe.json"
check jq -e '.data.operations|length==21' "$TMP/describe.json"
check jq -e '.data.operations["media.timing"].cost=="BOUNDED_MEDIA_PROBE" and .data.operations["media.timing"].authority=="NORMALIZED_NATIVE_MEDIA" and .data.operations["media.timing"].executionScope=="LOCAL_ONLY" and .data.operations["media.timing"].interactiveSafe==false' "$TMP/describe.json"
check jq -e '.data.operations["media.timing"].requires.all==["avmediainfo","awk","df","uname"]' "$TMP/describe.json"

cat > "$TMP/report.req" <<'REQ'
MOGRAPHJAILED_REQUEST 1
requestId=stdlib-report
command=report.tech
REQ
"$CLI" --request "$TMP/report.req" > "$TMP/report.json"
check jq -e '.data.standardLibrary.version=="1.0" and .data.policy.localOnly==true' "$TMP/report.json"
check jq -e '.data.capabilities.sqlite3.path=="/usr/bin/sqlite3" and .data.capabilities.jq.path=="/usr/bin/jq"' "$TMP/report.json"

# The Standard Library does not add a generic SQL/shell execution command.
check /bin/bash -c '! grep -RInE "(^|[| ])(db|sql)\\.(exec|query|run)|shell\\.execute" "$1/src/core/protocol.zsh" "$1/src/core/operations.zsh" "$1/src/cli/entry.zsh"' bash "$ROOT"
check grep -q 'publicSql":false' "$ROOT/src/lib/standard_library.zsh"
check grep -q 'arbitrarySqlAPI":false' "$ROOT/src/lib/standard_library.zsh"
check grep -q -- '-init /dev/null' "$ROOT/src/lib/native_db.zsh"
check grep -q 'PRAGMA temp_store=MEMORY' "$ROOT/src/lib/native_db.zsh"
check grep -q 'SQLITE_HISTORY SQLITE_TMPDIR' "$ROOT/src/core/constants.zsh"

# Shared primitives must actually live behind library boundaries.
check grep -q '^mj_fs_type()' "$ROOT/src/lib/local_fs.zsh"
check grep -q '^image_positive_identification()' "$ROOT/src/lib/image_kit.zsh"
check grep -q '^media_probe_parse_text()' "$ROOT/src/lib/media_probe.zsh"
check grep -q '^native_db_validate_store_path()' "$ROOT/src/lib/native_db.zsh"
check /bin/bash -c '! grep -q "^volume_fs_type()" "$1/src/modules/volume.zsh"' bash "$ROOT"
check /bin/bash -c '! grep -q "^sips_property()" "$1/src/modules/image.zsh"' bash "$ROOT"

# AE consumers get typed convenience access without any new shell boundary.
check grep -q 'Client.prototype.standardLibrary' "$ROOT/integrations/after-effects/MographJailed_Client.jsxinc"
check grep -q 'Client.prototype.mediaTiming' "$ROOT/integrations/after-effects/MographJailed_Client.jsxinc"

printf 'Standard Library 1.0 tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
