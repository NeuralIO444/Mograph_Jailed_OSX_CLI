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
# - no generic JXA/Objective-C bridge is exposed to callers.

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

# Executes a fixed embedded JXA adapter. Request data is supplied only through
# environment variables; no request value is interpreted as JavaScript source.
# The adapter uses the synchronous Objective-C compatibility API because JXA
# cannot consume Swift async/await. It is isolated here so a future native
# helper can replace it without changing the public media.frame contract.
frame_kit_extract_png() {
  local _source="$1"
  local _output="$2"
  local _seconds="$3"
  local _timescale="$4"
  local _max_pixels="$5"
  local _json=""

  frame_kit_reset
  cap_available osascript && cap_available jq || return 1

  _json=$(MJ_FRAMEKIT_SOURCE="$_source" \
    MJ_FRAMEKIT_OUTPUT="$_output" \
    MJ_FRAMEKIT_SECONDS="$_seconds" \
    MJ_FRAMEKIT_TIMESCALE="$_timescale" \
    MJ_FRAMEKIT_MAX_PIXELS="$_max_pixels" \
    /usr/bin/osascript -l JavaScript - <<'JXA_FRAMEKIT' 2>/dev/null
ObjC.import('Foundation');
ObjC.import('AppKit');
ObjC.import('AVFoundation');
ObjC.import('CoreMedia');
ObjC.import('CoreGraphics');

function envString(name) {
    var value = $.NSProcessInfo.processInfo.environment.objectForKey(name);
    if (!value) { throw new Error('missing environment value: ' + name); }
    return ObjC.unwrap(value);
}

function errorJSON(code, message) {
    return JSON.stringify({ok:false, code:String(code), message:String(message)});
}

function run() {
    try {
        var source = envString('MJ_FRAMEKIT_SOURCE');
        var output = envString('MJ_FRAMEKIT_OUTPUT');
        var seconds = Number(envString('MJ_FRAMEKIT_SECONDS'));
        var timescale = Number(envString('MJ_FRAMEKIT_TIMESCALE'));
        var maxPixels = Number(envString('MJ_FRAMEKIT_MAX_PIXELS'));
        if (!isFinite(seconds) || seconds < 0) { return errorJSON('INVALID_TIME', 'Requested time is invalid.'); }
        if (!isFinite(timescale) || timescale < 1 || timescale > 2147483647) { return errorJSON('INVALID_TIMESCALE', 'Media timescale is invalid.'); }
        if (!isFinite(maxPixels) || maxPixels < 64 || maxPixels > 4096) { return errorJSON('INVALID_BOUND', 'Pixel bound is invalid.'); }

        var url = $.NSURL.fileURLWithPath(source);
        var asset = $.AVURLAsset.alloc.initWithURLOptions(url, $());
        if (!asset) { return errorJSON('ASSET_OPEN_FAILED', 'AVURLAsset could not open the source.'); }

        var generator = $.AVAssetImageGenerator.alloc.initWithAsset(asset);
        if (!generator) { return errorJSON('GENERATOR_FAILED', 'AVAssetImageGenerator could not be created.'); }
        generator.appliesPreferredTrackTransform = true;
        generator.maximumSize = $.CGSizeMake(maxPixels, maxPixels);
        var zero = $.CMTimeMake(0, 1);
        generator.requestedTimeToleranceBefore = zero;
        generator.requestedTimeToleranceAfter = zero;

        var requested = $.CMTimeMakeWithSeconds(seconds, timescale);
        var actualRef = Ref();
        var errorRef = $();
        var image = generator.copyCGImageAtTimeActualTimeError(requested, actualRef, errorRef);
        if (!image) {
            var message = 'AVFoundation did not return an image.';
            try {
                if (!errorRef.isNil()) { message = ObjC.unwrap(errorRef.localizedDescription); }
            } catch (ignoreError) {}
            return errorJSON('FRAME_GENERATION_FAILED', message);
        }

        var actual = actualRef[0];
        var actualSeconds = Number($.CMTimeGetSeconds(actual));
        var width = Number($.CGImageGetWidth(image));
        var height = Number($.CGImageGetHeight(image));
        if (!isFinite(actualSeconds) || width < 1 || height < 1) {
            return errorJSON('FRAME_RESULT_INVALID', 'AVFoundation returned invalid frame metadata.');
        }

        var bitmap = $.NSBitmapImageRep.alloc.initWithCGImage(image);
        if (!bitmap) { return errorJSON('PNG_ENCODE_FAILED', 'NSBitmapImageRep could not wrap the generated image.'); }
        var png = bitmap.representationUsingTypeProperties($.NSPNGFileType, $());
        if (!png) { return errorJSON('PNG_ENCODE_FAILED', 'AppKit could not encode the generated image as PNG.'); }
        if (!png.writeToFileAtomically(output, true)) {
            return errorJSON('PNG_WRITE_FAILED', 'PNG data could not be written to the staged output.');
        }

        return JSON.stringify({
            ok:true,
            requestedSeconds:seconds,
            actualSeconds:actualSeconds,
            actualValue:Number(actual.value),
            actualTimescale:Number(actual.timescale),
            pixelWidth:width,
            pixelHeight:height,
            transformApplied:true,
            toleranceBeforeSeconds:0,
            toleranceAfterSeconds:0,
            adapter:'JXA_AVAssetImageGenerator'
        });
    } catch (e) {
        return errorJSON('JXA_EXCEPTION', e && e.message ? e.message : String(e));
    }
}
JXA_FRAMEKIT
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
