# MJ Standard Library 1.0 — FrameKit
# Narrow local-only AVFoundation frame derivative adapter.
#
# Design boundaries:
# - one readable local media source;
# - one non-existing local PNG output;
# - one non-negative requested time;
# - bounded output dimensions;
# - zero AVAssetImageGenerator time tolerance (frame-accurate request);
# - preferred track transform applied;
# - no generic AppleScript/JXA Objective-C bridge is exposed to callers.
#
# Bridge note (target-Mac Gate A, 2026-09-29): macOS Tahoe (26.x) broke JXA's
# ObjC bridge for AVFoundation ($.AVURLAsset is undefined even though
# ObjC.import('AVFoundation') succeeds), while Foundation still bridges.
# AppleScriptObjC (use framework "AVFoundation") still sees AVFoundation
# classes on Tahoe, so the adapter is AppleScriptObjC. The embedded script is
# fixed; request data enters only through environment variables.
#
# Frame-grid note: with zero tolerance, AVAssetImageGenerator returns nil
# unless the requested time is exactly a sample presentation time. Nominal
# frame-rate metadata cannot be trusted to compute one: target-Mac Gate A
# (2026-09-29) proved a 29.97fps-nominal track uses non-uniform integer
# presentation times in a 600-timescale (..., 561, 581, 601, ...), so
# frameIndex * fps arithmetic names phantom times. The caller
# (media.frame) therefore reads the exact presentation timestamp of the
# frame displayed at the requested time from the avmediainfo sample table
# (media_probe_sample_floor_ticks) and passes it in; the adapter requests
# that CMTime with zero tolerance. requestedSeconds echoes the caller's
# time; actualSeconds/value/timescale name the extracted frame. Consumers
# must use actualTime for verification (the media.frame contract already
# provides it alongside deltaSeconds).

MJ_FRAMEKIT_RESULT_JSON=""
MJ_FRAMEKIT_REQUESTED_SECONDS=""
MJ_FRAMEKIT_ACTUAL_SECONDS=""
MJ_FRAMEKIT_ACTUAL_VALUE=""
MJ_FRAMEKIT_ACTUAL_TIMESCALE=""
MJ_FRAMEKIT_PIXEL_WIDTH=""
MJ_FRAMEKIT_PIXEL_HEIGHT=""
MJ_FRAMEKIT_ERROR_CODE=""
MJ_FRAMEKIT_ERROR_MESSAGE=""

frame_kit_reset() {
  MJ_FRAMEKIT_RESULT_JSON=""
  MJ_FRAMEKIT_REQUESTED_SECONDS=""
  MJ_FRAMEKIT_ACTUAL_SECONDS=""
  MJ_FRAMEKIT_ACTUAL_VALUE=""
  MJ_FRAMEKIT_ACTUAL_TIMESCALE=""
  MJ_FRAMEKIT_PIXEL_WIDTH=""
  MJ_FRAMEKIT_PIXEL_HEIGHT=""
  MJ_FRAMEKIT_ERROR_CODE=""
  MJ_FRAMEKIT_ERROR_MESSAGE=""
}

frame_kit_is_time_seconds() {
  printf '%s\n' "$1" | /usr/bin/awk 'BEGIN{ok=0} /^[0-9]+([.][0-9]+)?$/ { if (length($0)<=24) ok=1 } END{exit ok?0:1}'
}

frame_kit_is_max_pixels() {
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  [ ${#1} -le 4 ] || return 1
  [ "$1" -ge 64 ] && [ "$1" -le 4096 ]
}

frame_kit_time_before_duration() {
  local _time="$1"
  local _duration="$2"
  MJ_FRAMEKIT_TIME="$_time" MJ_FRAMEKIT_DURATION="$_duration" /usr/bin/awk 'BEGIN {
    t=ENVIRON["MJ_FRAMEKIT_TIME"]+0;
    d=ENVIRON["MJ_FRAMEKIT_DURATION"]+0;
    exit (t>=0 && d>0 && t<d) ? 0 : 1;
  }'
}

# Executes a fixed embedded AppleScriptObjC adapter. Request data is supplied
# only through environment variables; no request value is interpreted as
# AppleScript source. The caller passes the exact frame presentation time
# (value/timescale) read from the avmediainfo sample table -- the adapter
# never computes frame times from nominal frame-rate metadata, because
# target-Mac Gate A (2026-09-29) proved nominal rates can disagree with the
# true non-uniform sample grid. The adapter extracts the full-resolution
# frame; the caller (media.frame) bounds dimensions afterwards with sips so
# the adapter stays narrow and every bridge call is an object call or a
# proven C function.
frame_kit_extract_png() {
  local _source="$1"
  local _output="$2"
  local _seconds="$3"
  local _floor_value="$4"
  local _floor_timescale="$5"
  local _json=""

  frame_kit_reset
  cap_available osascript && cap_available jq || return 1

  _json=$(MJ_FRAMEKIT_SOURCE="$_source" \
    MJ_FRAMEKIT_OUTPUT="$_output" \
    MJ_FRAMEKIT_SECONDS="$_seconds" \
    MJ_FRAMEKIT_FLOOR_VALUE="$_floor_value" \
    MJ_FRAMEKIT_FLOOR_TIMESCALE="$_floor_timescale" \
    /usr/bin/osascript - <<'ASOBJC_FRAMEKIT' 2>/dev/null
use framework "AVFoundation"
use framework "Foundation"
use framework "AppKit"
use scripting additions

on errorJSON(code, message)
  return "{\"ok\":false,\"code\":\"" & code & "\",\"message\":\"" & message & "\"}"
end errorJSON

try
  set srcPath to system attribute "MJ_FRAMEKIT_SOURCE"
  set outPath to system attribute "MJ_FRAMEKIT_OUTPUT"
  set secsText to system attribute "MJ_FRAMEKIT_SECONDS"
  set floorText to system attribute "MJ_FRAMEKIT_FLOOR_VALUE"
  set floorTsText to system attribute "MJ_FRAMEKIT_FLOOR_TIMESCALE"
  if srcPath is missing value or srcPath is "" then return my errorJSON("INVALID_SOURCE", "Missing source path.")
  if outPath is missing value or outPath is "" then return my errorJSON("INVALID_OUTPUT", "Missing output path.")
  if secsText is missing value or secsText is "" then return my errorJSON("INVALID_TIME", "Missing requested time.")
  if floorText is missing value or floorText is "" then return my errorJSON("INVALID_FLOOR_TIME", "Missing frame presentation time.")
  if floorTsText is missing value or floorTsText is "" then return my errorJSON("INVALID_FLOOR_TIME", "Missing frame presentation timescale.")
  set tSecs to secsText as real
  if tSecs < 0 then return my errorJSON("INVALID_TIME", "Requested time is negative.")
  set floorVal to floorText as integer
  set floorTs to floorTsText as integer
  if floorVal < 0 or floorTs < 1 then return my errorJSON("INVALID_FLOOR_TIME", "Frame presentation time is invalid.")

  set theURL to current application's NSURL's fileURLWithPath:srcPath
  if theURL is missing value then return my errorJSON("ASSET_OPEN_FAILED", "Could not form a file URL for the source.")
  set theAsset to current application's AVURLAsset's alloc()'s initWithURL:theURL options:(missing value)
  if theAsset is missing value then return my errorJSON("ASSET_OPEN_FAILED", "AVURLAsset could not open the source.")

  set vTracks to theAsset's tracksWithMediaType:(current application's AVMediaTypeVideo)
  if (count of vTracks) < 1 then return my errorJSON("NO_VIDEO_TRACK_ADAPTER", "The asset has no video track.")

  -- The requested CMTime is an exact sample presentation timestamp from the
  -- media sample table, so zero tolerance names a real frame by construction.
  set requestedTime to current application's CMTimeMake(floorVal, floorTs)
  set actualSeconds to floorVal / floorTs

  set gen to current application's AVAssetImageGenerator's assetImageGeneratorWithAsset:theAsset
  if gen is missing value then return my errorJSON("GENERATOR_FAILED", "AVAssetImageGenerator could not be created.")
  gen's setAppliesPreferredTrackTransform:true
  gen's setRequestedTimeToleranceBefore:(current application's CMTimeMake(0, floorTs))
  gen's setRequestedTimeToleranceAfter:(current application's CMTimeMake(0, floorTs))

  set cgImage to gen's copyCGImageAtTime:requestedTime actualTime:(missing value) |error|:(missing value)
  if cgImage is missing value then return my errorJSON("FRAME_GENERATION_FAILED", "AVFoundation did not return an image for frame presentation time " & (floorText as text) & "/" & (floorTsText as text) & ".")

  set rep to current application's NSBitmapImageRep's alloc()'s initWithCGImage:cgImage
  if rep is missing value then return my errorJSON("PNG_ENCODE_FAILED", "NSBitmapImageRep could not wrap the generated image.")
  set pngData to rep's representationUsingType:(current application's NSPNGFileType) |properties|:(missing value)
  if pngData is missing value then return my errorJSON("PNG_ENCODE_FAILED", "AppKit could not encode the generated image as PNG.")
  set wroteOK to pngData's writeToFile:outPath atomically:true
  if wroteOK is not true then return my errorJSON("PNG_WRITE_FAILED", "PNG data could not be written to the staged output.")

  set w to rep's pixelsWide()
  set h to rep's pixelsHigh()
  if w < 1 or h < 1 then return my errorJSON("FRAME_RESULT_INVALID", "AVFoundation returned invalid frame dimensions.")

  return "{\"ok\":true,\"requestedSeconds\":" & (tSecs as text) & ",\"actualSeconds\":" & (actualSeconds as text) & ",\"actualValue\":" & (floorVal as text) & ",\"actualTimescale\":" & (floorTs as text) & ",\"pixelWidth\":" & (w as text) & ",\"pixelHeight\":" & (h as text) & ",\"transformApplied\":true,\"toleranceBeforeSeconds\":0,\"toleranceAfterSeconds\":0,\"adapter\":\"ASOBJC_AVAssetImageGenerator\"}"
on error e
  return my errorJSON("ASOBJC_EXCEPTION", "AppleScriptObjC adapter failed: " & (e as text))
end try
ASOBJC_FRAMEKIT
  ) || return 1

  MJ_FRAMEKIT_RESULT_JSON="$_json"
  if ! printf '%s' "$_json" | /usr/bin/jq -e '.ok == true and (.requestedSeconds|type)=="number" and (.actualSeconds|type)=="number" and (.actualValue|type)=="number" and (.actualTimescale|type)=="number" and (.pixelWidth|type)=="number" and (.pixelHeight|type)=="number" and .transformApplied==true' >/dev/null 2>&1; then
    MJ_FRAMEKIT_ERROR_CODE=$(printf '%s' "$_json" | /usr/bin/jq -r 'if (.code|type)=="string" then .code else "NATIVE_OUTPUT_INVALID" end' 2>/dev/null || printf 'NATIVE_OUTPUT_INVALID')
    MJ_FRAMEKIT_ERROR_MESSAGE=$(printf '%s' "$_json" | /usr/bin/jq -r 'if (.message|type)=="string" then .message else "FrameKit adapter returned invalid output." end' 2>/dev/null || printf 'FrameKit adapter returned invalid output.')
    return 1
  fi

  MJ_FRAMEKIT_REQUESTED_SECONDS=$(printf '%s' "$_json" | /usr/bin/jq -r '.requestedSeconds')
  MJ_FRAMEKIT_ACTUAL_SECONDS=$(printf '%s' "$_json" | /usr/bin/jq -r '.actualSeconds')
  MJ_FRAMEKIT_ACTUAL_VALUE=$(printf '%s' "$_json" | /usr/bin/jq -r '.actualValue')
  MJ_FRAMEKIT_ACTUAL_TIMESCALE=$(printf '%s' "$_json" | /usr/bin/jq -r '.actualTimescale')
  MJ_FRAMEKIT_PIXEL_WIDTH=$(printf '%s' "$_json" | /usr/bin/jq -r '.pixelWidth')
  MJ_FRAMEKIT_PIXEL_HEIGHT=$(printf '%s' "$_json" | /usr/bin/jq -r '.pixelHeight')

  [ -f "$_output" ] && [ -s "$_output" ] || return 1
  image_positive_identification "$_output" || return 1
  return 0
}

standard_library_framekit_available() {
  cap_available osascript && cap_available jq && cap_available sips && cap_available awk && cap_available mktemp && cap_available mv && cap_available rm && cap_available stat && cap_available uname && standard_library_localfs_available && standard_library_mediaprobe_available
}
