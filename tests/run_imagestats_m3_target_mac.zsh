#!/bin/zsh -f
# MographJailed SL-M3 ImageStats — Target-Mac Qualification (Gate A)
# Run on the target Mac: /bin/zsh tests/run_imagestats_m3_target_mac.zsh
emulate -R zsh
set -u
ROOT=${0:A:h:h}
CLI="$ROOT/dist/mograph-jailed.zsh"
TMP=$(/usr/bin/mktemp -d /tmp/MographJailed_ImageStats_M3.XXXXXXXX) || exit 1
trap '/bin/rm -rf "$TMP"' EXIT HUP INT TERM
pass=0
fail=0
skip=0
b64(){ printf '%s' "$1" | /usr/bin/base64 | /usr/bin/awk 'BEGIN{ORS=""}{printf "%s",$0}'; }
pass_test(){ print -r -- "PASS|$1|$2"; (( pass++ )); }
fail_test(){ print -r -- "FAIL|$1|$2"; (( fail++ )); }
skip_test(){ print -r -- "SKIP|$1|$2"; (( skip++ )); }
run_req(){ /bin/zsh -f "$CLI" --request "$TMP/$1.req" > "$TMP/$1.json"; }

print -r -- 'HEADER|schema|MOGRAPHJAILED_IMAGESTATS_M3_TARGET_1'
print -r -- 'HEADER|scope|LOCAL_ONLY'
print -r -- 'HEADER|networkMutation|0'
print -r -- 'HEADER|sudo|0'

if [[ ! -x "$CLI" ]]; then fail_test runtime cli_missing; print -r -- "SUMMARY|pass=$pass|fail=$fail|skip=$skip"; exit 1; fi

# 1. Registry: both operations available, local-only, correct requirements
cat > "$TMP/describe.req" <<'REQ'
MOGRAPHJAILED_REQUEST 1
requestId=imagestats-m3-describe
command=system.describe
REQ
if run_req describe && /usr/bin/jq -e '.ok==true and .data.operations["image.stats"].available==true and .data.operations["image.compare"].available==true and .data.standardLibrary.modules.ImageStats.available==true and .data.standardLibrary.modules.ImageStats.authority=="DERIVED_IMAGE_SIGNATURE"' "$TMP/describe.json" >/dev/null; then
  pass_test registry imagestats_available
else
  fail_test registry imagestats_unavailable_or_contract_mismatch
fi

# 2. Extract two frames via FrameKit for real test images
MOVIE='/System/Library/PrivateFrameworks/Slideshows.framework/Versions/A/Resources/Content/Styles/SlidingPanels.mrbStyle/Contents/Resources/Preview.mov'
if [[ ! -r "$MOVIE" ]]; then
  MOVIE=$(/usr/bin/mdfind -onlyin /System/Library 'kMDItemContentTypeTree == "public.movie"' 2>/dev/null | /usr/bin/awk 'NR==1{print;exit}')
fi

if [[ -z "$MOVIE" || ! -r "$MOVIE" ]]; then
  skip_test fixture no_local_movie_found
  print -r -- "SUMMARY|pass=$pass|fail=$fail|skip=$skip"
  exit 0
fi

FRAME_A="$TMP/frame_a.png"
FRAME_B="$TMP/frame_b.png"
cat > "$TMP/extract_a.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=imagestats-m3-extract-a
command=media.frame
arg.path=$(b64 "$MOVIE")
arg.output=$(b64 "$FRAME_A")
arg.timeSeconds=$(b64 0.5)
arg.maxPixels=$(b64 320)
REQ
cat > "$TMP/extract_b.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=imagestats-m3-extract-b
command=media.frame
arg.path=$(b64 "$MOVIE")
arg.output=$(b64 "$FRAME_B")
arg.timeSeconds=$(b64 1.5)
arg.maxPixels=$(b64 320)
REQ

if ! run_req extract_a || ! /usr/bin/jq -e '.ok==true' "$TMP/extract_a.json" >/dev/null; then
  fail_test fixture frame_extraction_failed
  print -r -- "SUMMARY|pass=$pass|fail=$fail|skip=$skip"
  exit 1
fi
run_req extract_b >/dev/null 2>&1

# 3. image.stats on real frame
cat > "$TMP/stats.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=imagestats-m3-stats
command=image.stats
arg.path=$(b64 "$FRAME_A")
REQ
if run_req stats && /usr/bin/jq -e '.ok==true and .data.schema=="MJ_IMAGE_STATS_1" and (.data.histogram|length)==64 and (.data.gridAverages|length)==64 and .data.pixelWidth>0 and .data.pixelHeight>0 and .data.sourceUnchanged==true' "$TMP/stats.json" >/dev/null; then
  pass_test stats valid_mj_image_stats_1
else
  fail_test stats invalid_schema_or_shape
  /bin/cat "$TMP/stats.json" 2>/dev/null || true
fi

# 4. Determinism: run stats twice, output must be identical
cat > "$TMP/stats2.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=imagestats-m3-stats2
command=image.stats
arg.path=$(b64 "$FRAME_A")
REQ
if run_req stats2 && /usr/bin/jq -e '.ok==true' "$TMP/stats2.json" >/dev/null; then
  H1=$(/usr/bin/jq -c '.data.histogram' "$TMP/stats.json")
  H2=$(/usr/bin/jq -c '.data.histogram' "$TMP/stats2.json")
  G1=$(/usr/bin/jq -c '.data.gridAverages' "$TMP/stats.json")
  G2=$(/usr/bin/jq -c '.data.gridAverages' "$TMP/stats2.json")
  if [[ "$H1" == "$H2" && "$G1" == "$G2" ]]; then
    pass_test determinism identical_output_twice
  else
    fail_test determinism output_differs
  fi
else
  fail_test determinism second_run_failed
fi

# 5. image.compare on identical images → score 1.0
cat > "$TMP/compare_same.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=imagestats-m3-compare-same
command=image.compare
arg.pathA=$(b64 "$FRAME_A")
arg.pathB=$(b64 "$FRAME_A")
REQ
if run_req compare_same && /usr/bin/jq -e '.ok==true and .data.schema=="MJ_IMAGE_COMPARE_1" and .data.score==1.0 and .data.histogramSimilarity==1.0 and .data.gridSimilarity==1.0 and .data.sourceUnchanged==true' "$TMP/compare_same.json" >/dev/null; then
  pass_test compare identical_images_score_1
else
  fail_test compare identical_images_wrong_score
  /bin/cat "$TMP/compare_same.json" 2>/dev/null || true
fi

# 6. image.compare on different frames → score < 1.0, > 0.0
if [[ -f "$FRAME_B" ]]; then
  cat > "$TMP/compare_diff.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=imagestats-m3-compare-diff
command=image.compare
arg.pathA=$(b64 "$FRAME_A")
arg.pathB=$(b64 "$FRAME_B")
REQ
  if run_req compare_diff && /usr/bin/jq -e '.ok==true and .data.score<1.0 and .data.score>=0.0' "$TMP/compare_diff.json" >/dev/null; then
    pass_test compare different_frames_score_in_range
  else
    fail_test compare different_frames_bad_score
    /bin/cat "$TMP/compare_diff.json" 2>/dev/null || true
  fi
else
  skip_test compare second_frame_unavailable
fi

# 7. Rejects non-PNG file
echo "not a png" > "$TMP/fake.txt"
cat > "$TMP/stats_bad.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=imagestats-m3-stats-bad
command=image.stats
arg.path=$(b64 "$TMP/fake.txt")
REQ
if run_req stats_bad && /usr/bin/jq -e '.ok==false' "$TMP/stats_bad.json" >/dev/null; then
  pass_test rejection non_png_rejected
else
  fail_test rejection non_png_accepted
fi

# 8. Rejects missing file
cat > "$TMP/stats_missing.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=imagestats-m3-stats-missing
command=image.stats
arg.path=$(b64 "/nonexistent/image.png")
REQ
if run_req stats_missing && /usr/bin/jq -e '.ok==false' "$TMP/stats_missing.json" >/dev/null; then
  pass_test rejection missing_file_rejected
else
  fail_test rejection missing_file_accepted
fi

# 9. Source unchanged: sha256 before/after
BEFORE=$(/usr/bin/shasum -a 256 "$FRAME_A" | /usr/bin/awk '{print $1}')
run_req stats >/dev/null 2>&1
AFTER=$(/usr/bin/shasum -a 256 "$FRAME_A" | /usr/bin/awk '{print $1}')
if [[ "$BEFORE" == "$AFTER" ]]; then
  pass_test immutability source_unchanged
else
  fail_test immutability source_modified
fi

print -r -- "SUMMARY|pass=$pass|fail=$fail|skip=$skip"
print -r -- 'POLICY|networkReads=0|networkWrites=0|sudo=0|python=system_stdlib|xcodeTools=0'
