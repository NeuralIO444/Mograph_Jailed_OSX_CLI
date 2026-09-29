#!/bin/zsh -f
emulate -R zsh
set -u
ROOT=${0:A:h:h}
CLI="$ROOT/dist/mograph-jailed.zsh"
TMP=$(/usr/bin/mktemp -d /tmp/MographJailed_FrameKit_M2.XXXXXXXX) || exit 1
trap '/bin/rm -rf "$TMP"' EXIT HUP INT TERM
pass=0
fail=0
skip=0
b64(){ printf '%s' "$1" | /usr/bin/base64 | /usr/bin/awk 'BEGIN{ORS=""}{printf "%s",$0}'; }
pass_test(){ print -r -- "PASS|$1|$2"; (( pass++ )); }
fail_test(){ print -r -- "FAIL|$1|$2"; (( fail++ )); }
skip_test(){ print -r -- "SKIP|$1|$2"; (( skip++ )); }
run_req(){ /bin/zsh -f "$CLI" --request "$TMP/$1.req" > "$TMP/$1.json"; }

print -r -- 'HEADER|schema|MOGRAPHJAILED_FRAMEKIT_M2_TARGET_1'
print -r -- 'HEADER|scope|LOCAL_ONLY'
print -r -- 'HEADER|networkMutation|0'
print -r -- 'HEADER|sudo|0'

if [[ ! -x "$CLI" ]]; then fail_test runtime cli_missing; print -r -- "SUMMARY|pass=$pass|fail=$fail|skip=$skip"; exit 1; fi

cat > "$TMP/describe.req" <<'REQ'
MOGRAPHJAILED_REQUEST 1
requestId=framekit-m2-describe
command=system.describe
REQ
if run_req describe && /usr/bin/jq -e '.ok==true and .cliVersion=="0.3.0-dev.2" and .data.standardLibrary.modules.FrameKit.available==true and .data.operations["media.frame"].available==true and .data.operations["media.frame"].executionScope=="LOCAL_ONLY"' "$TMP/describe.json" >/dev/null; then
  pass_test registry framekit_available_local_only
else
  fail_test registry framekit_unavailable_or_contract_mismatch
fi

MOVIE='/System/Library/PrivateFrameworks/Slideshows.framework/Versions/A/Resources/Content/Styles/SlidingPanels.mrbStyle/Contents/Resources/Preview.mov'
if [[ ! -r "$MOVIE" ]]; then
  MOVIE=$(/usr/bin/mdfind -onlyin /System/Library 'kMDItemContentTypeTree == "public.movie"' 2>/dev/null | /usr/bin/awk 'NR==1{print;exit}')
fi

if [[ -n "$MOVIE" && -r "$MOVIE" ]]; then
  OUT="$TMP/frame.png"
  cat > "$TMP/frame.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=framekit-m2-frame
command=media.frame
arg.path=$(b64 "$MOVIE")
arg.output=$(b64 "$OUT")
arg.timeSeconds=$(b64 1.0)
arg.maxPixels=$(b64 640)
REQ
  if run_req frame && /usr/bin/jq -e '.ok==true and .data.schema=="MJ_MEDIA_FRAME_1" and .data.scope.classification=="local" and .data.scope.policy=="LOCAL_ONLY" and .data.frameAccurateRequest==true and .data.toleranceBeforeSeconds==0 and .data.toleranceAfterSeconds==0 and .data.preferredTrackTransformApplied==true and .data.sourceUnchanged==true and .data.requestedTime.seconds==1 and .data.actualTime.seconds>=0 and .data.pixelWidth>0 and .data.pixelHeight>0 and .data.pixelWidth<=640 and .data.pixelHeight<=640' "$TMP/frame.json" >/dev/null && [[ -s "$OUT" ]]; then
    pass_test frame exact_local_png
  else
    fail_test frame extraction_or_shape_failed
    /bin/cat "$TMP/frame.json" 2>/dev/null || true
  fi

  if /usr/bin/sips -g format -g pixelWidth -g pixelHeight "$OUT" 2>/dev/null | /usr/bin/grep -q 'format: png'; then
    pass_test frame_png sips_validated
  else fail_test frame_png invalid_png; fi

  # No-overwrite guarantee.
  if run_req frame; then
    fail_test no_overwrite second_call_unexpectedly_succeeded
  elif /usr/bin/jq -e '.ok==false and .error.code=="OUTPUT_EXISTS"' "$TMP/frame.json" >/dev/null; then
    pass_test no_overwrite refused_existing_output
  else fail_test no_overwrite wrong_error; fi

  # Out-of-range request must fail before FrameKit writes anything.
  DUR=$(/usr/bin/avmediainfo "$MOVIE" --brief 2>/dev/null | /usr/bin/awk '/^Duration:/ {print $2; exit}')
  BADOUT="$TMP/out_of_range.png"
  cat > "$TMP/range.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=framekit-m2-range
command=media.frame
arg.path=$(b64 "$MOVIE")
arg.output=$(b64 "$BADOUT")
arg.timeSeconds=$(b64 "$DUR")
arg.maxPixels=$(b64 640)
REQ
  if run_req range; then
    fail_test range end_time_unexpectedly_succeeded
  elif /usr/bin/jq -e '.ok==false and .error.code=="TIME_OUT_OF_RANGE"' "$TMP/range.json" >/dev/null && [[ ! -e "$BADOUT" ]]; then
    pass_test range end_time_refused_without_output
  else fail_test range wrong_error_or_output; fi

  # Optional codec expansion: local temp only. Core H.264 fixture above is required.
  if [[ -x /usr/bin/avconvert ]]; then
    HEVC="$TMP/hevc.mov"
    if /usr/bin/avconvert --source "$MOVIE" --preset PresetHEVCHighestQuality --output "$HEVC" >/dev/null 2>&1 && [[ -s "$HEVC" ]]; then
      HEVC_OUT="$TMP/hevc.png"
      cat > "$TMP/hevc.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=framekit-m2-hevc
command=media.frame
arg.path=$(b64 "$HEVC")
arg.output=$(b64 "$HEVC_OUT")
arg.timeSeconds=$(b64 1.0)
arg.maxPixels=$(b64 640)
REQ
      if run_req hevc && /usr/bin/jq -e '.ok==true and .data.schema=="MJ_MEDIA_FRAME_1"' "$TMP/hevc.json" >/dev/null && [[ -s "$HEVC_OUT" ]]; then pass_test codec_hevc local_decode; else fail_test codec_hevc frame_extract_failed; fi
    else skip_test codec_hevc avconvert_preset_unavailable; fi

    PRORES="$TMP/prores.mov"
    if /usr/bin/avconvert --source "$MOVIE" --preset PresetAppleProRes422LPCM --output "$PRORES" >/dev/null 2>&1 && [[ -s "$PRORES" ]]; then
      PRORES_OUT="$TMP/prores.png"
      cat > "$TMP/prores.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=framekit-m2-prores
command=media.frame
arg.path=$(b64 "$PRORES")
arg.output=$(b64 "$PRORES_OUT")
arg.timeSeconds=$(b64 1.0)
arg.maxPixels=$(b64 640)
REQ
      if run_req prores && /usr/bin/jq -e '.ok==true and .data.schema=="MJ_MEDIA_FRAME_1"' "$TMP/prores.json" >/dev/null && [[ -s "$PRORES_OUT" ]]; then pass_test codec_prores local_decode; else fail_test codec_prores frame_extract_failed; fi
    else skip_test codec_prores avconvert_preset_unavailable; fi
  else
    skip_test codec_hevc avconvert_absent
    skip_test codec_prores avconvert_absent
  fi
else
  fail_test fixture no_readable_local_system_movie
fi

# Corrupt/local non-media must fail before a derivative is published.
CORRUPT="$TMP/corrupt.mov"
CORRUPT_OUT="$TMP/corrupt.png"
print -r -- 'not a movie' > "$CORRUPT"
cat > "$TMP/corrupt.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=framekit-m2-corrupt
command=media.frame
arg.path=$(b64 "$CORRUPT")
arg.output=$(b64 "$CORRUPT_OUT")
arg.timeSeconds=$(b64 0)
arg.maxPixels=$(b64 640)
REQ
if run_req corrupt; then
  fail_test corrupt_media unexpected_success
elif /usr/bin/jq -e '.ok==false and (.error.code=="NATIVE_OUTPUT_INVALID" or .error.code=="NO_VIDEO_TRACK")' "$TMP/corrupt.json" >/dev/null && [[ ! -e "$CORRUPT_OUT" ]]; then
  pass_test corrupt_media refused_without_output
else
  fail_test corrupt_media wrong_error_or_output
fi

AUDIO='/System/Library/Sounds/Glass.aiff'
if [[ -r "$AUDIO" ]]; then
  AOUT="$TMP/audio.png"
  cat > "$TMP/audio.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=framekit-m2-audio
command=media.frame
arg.path=$(b64 "$AUDIO")
arg.output=$(b64 "$AOUT")
arg.timeSeconds=$(b64 0)
arg.maxPixels=$(b64 640)
REQ
  if run_req audio; then
    fail_test audio_guard audio_unexpectedly_succeeded
  elif /usr/bin/jq -e '.ok==false and .error.code=="NO_VIDEO_TRACK"' "$TMP/audio.json" >/dev/null && [[ ! -e "$AOUT" ]]; then
    pass_test audio_guard no_video_track_refused
  else fail_test audio_guard wrong_error; fi
else skip_test audio_guard system_audio_fixture_missing; fi

# A true VFR fixture is not synthesized here; generating one would require a
# broader media authoring surface. VFR remains an explicit follow-up fixture gate.
skip_test vfr no_qualified_local_vfr_fixture

print -r -- 'POLICY|networkReads=0|networkWrites=0|sudo=0|python=0|xcodeTools=0'
print -r -- "SUMMARY|pass=$pass|fail=$fail|skip=$skip"
(( fail == 0 ))
