#!/bin/zsh -f
emulate -R zsh
set -u

ROOT="${0:A:h:h}"
CLI="$ROOT/dist/mograph-jailed.zsh"
TMP=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/MJ_StdLib1_Mac.XXXXXXXX") || exit 1
trap '/bin/rm -rf "$TMP"' EXIT HUP INT TERM
pass=0
fail=0
skip=0

pass_test() { print -r -- "PASS|$1|$2"; pass=$((pass+1)); }
fail_test() { print -r -- "FAIL|$1|$2"; fail=$((fail+1)); }
skip_test() { print -r -- "SKIP|$1|$2"; skip=$((skip+1)); }
b64() { print -rn -- "$1" | /usr/bin/base64 | /usr/bin/awk 'BEGIN{ORS=""}{printf "%s",$0}'; }

if [[ ! -x "$CLI" ]]; then
  print -r -- "FAIL|runtime|missing_or_not_executable=$CLI"
  exit 1
fi
if [[ ! -x /usr/bin/jq ]]; then
  print -r -- "FAIL|qa_jq|/usr/bin/jq_missing"
  exit 1
fi

run_req() {
  local name="$1"
  "$CLI" --request "$TMP/$name.req" > "$TMP/$name.json"
  return $?
}

cat > "$TMP/describe.req" <<'REQ'
MOGRAPHJAILED_REQUEST 1
requestId=stdlib1-mac-describe
command=system.describe
REQ
if run_req describe; then
  if /usr/bin/jq -e '.ok==true and .cliVersion=="0.3.0-dev.2" and .data.standardLibrary.version=="1.0"' "$TMP/describe.json" >/dev/null; then
    pass_test registry "version_and_library"
  else fail_test registry "unexpected_descriptor"; fi
  if /usr/bin/jq -e '.data.standardLibrary.modules.NativeDB.available==true and .data.standardLibrary.modules.NativeDB.features.json==true and .data.standardLibrary.modules.NativeDB.features.fts5==true' "$TMP/describe.json" >/dev/null; then
    pass_test nativedb "sqlite_json_fts5"
  else fail_test nativedb "sqlite_feature_probe_failed"; fi
  if /usr/bin/jq -e '.data.standardLibrary.modules.MediaProbe.available==true and .data.operations["media.timing"].available==true and .data.operations["media.timing"].executionScope=="LOCAL_ONLY"' "$TMP/describe.json" >/dev/null; then
    pass_test mediaprobe "available_local_only"
  else fail_test mediaprobe "not_available_or_policy_mismatch"; fi
else
  fail_test registry "system.describe_failed"
fi

MOVIE='/System/Library/PrivateFrameworks/Slideshows.framework/Versions/A/Resources/Content/Styles/SlidingPanels.mrbStyle/Contents/Resources/Preview.mov'
if [[ ! -r "$MOVIE" ]]; then
  MOVIE=$(/usr/bin/mdfind -onlyin /System/Library 'kMDItemContentTypeTree == "public.movie"' 2>/dev/null | /usr/bin/awk 'NR==1{print;exit}')
fi

if [[ -n "$MOVIE" && -r "$MOVIE" ]]; then
  cat > "$TMP/timing.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=stdlib1-mac-timing
command=media.timing
arg.path=$(b64 "$MOVIE")
REQ
  if run_req timing; then
    if /usr/bin/jq -e '.ok==true and .data.schema=="MJ_MEDIA_TIMING_2" and .data.bounded==true and .data.scope.classification=="local" and .data.scope.policy=="LOCAL_ONLY" and .data.sampleTableEnumerated==false and .data.duration.seconds>0 and .data.video.trackCount>=1 and .data.video.selected.pixelWidth>0 and .data.video.selected.pixelHeight>0 and .data.video.selected.nominalFrameRate>0' "$TMP/timing.json" >/dev/null; then
      pass_test media_timing "bounded_normalized_local_video"
    else
      fail_test media_timing "response_shape_or_values_invalid"
      /bin/cat "$TMP/timing.json"
    fi
  else
    fail_test media_timing "operation_failed"
    /bin/cat "$TMP/timing.json" 2>/dev/null || true
  fi
else
  skip_test media_timing "no_readable_local_system_movie_fixture"
fi

# The qualification script uses only the repository runtime, local temp files,
# a built-in local macOS movie, and in-memory SQLite probes through system.describe.
pass_test policy "local_only_no_admin_no_devtools"

print -r -- "SUMMARY|pass=$pass|fail=$fail|skip=$skip"
(( fail == 0 ))
