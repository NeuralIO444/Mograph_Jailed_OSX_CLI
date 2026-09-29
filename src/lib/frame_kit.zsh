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
# - no generic bridge is exposed to callers.
#
# Bridge note (target-Mac Gate A, 2026-09-29): macOS Tahoe (26.x) broke
# JXA's ObjC bridge for AVFoundation ($.AVURLAsset is undefined even though
# ObjC.import('AVFoundation') succeeds), while Foundation still bridges.
# AppleScriptObjC (use framework "AVFoundation") sees AVFoundation classes
# and copyCGImageAtTime: returns a valid CGImageRef, but the Tahoe
# AppleScript bridge cannot coerce that CGImageRef (a raw C pointer) into
# any usable form -- not to NSBitmapImageRep, not to a reference, not to
# ImageIO C functions, not even to an integer address. The adapter is
# therefore Python 3 + ctypes: the system python3 calls the same
# AVFoundation APIs through libobjc, and ctypes handles C pointers
# natively. NSInvocation is used for every method that takes a CMTime by
# value, so no struct-by-value ABI marshaling is required. The embedded
# script is fixed; request data enters only through environment variables.
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

# Executes a fixed embedded Python 3 + ctypes adapter. Request data is
# supplied only through environment variables; no request value is
# interpreted as Python source. The caller passes the exact frame
# presentation time (value/timescale) read from the avmediainfo sample
# table -- the adapter never computes frame times from nominal frame-rate
# metadata, because target-Mac Gate A (2026-09-29) proved nominal rates can
# disagree with the true non-uniform sample grid. The adapter extracts the
# full-resolution frame; the caller (media.frame) bounds dimensions
# afterwards with sips so the adapter stays narrow.
frame_kit_extract_png() {
  local _source="$1"
  local _output="$2"
  local _seconds="$3"
  local _floor_value="$4"
  local _floor_timescale="$5"
  local _json=""

  frame_kit_reset
  cap_available python3 && cap_available jq || return 1

  _json=$(MJ_FRAMEKIT_SOURCE="$_source" \
    MJ_FRAMEKIT_OUTPUT="$_output" \
    MJ_FRAMEKIT_SECONDS="$_seconds" \
    MJ_FRAMEKIT_FLOOR_VALUE="$_floor_value" \
    MJ_FRAMEKIT_FLOOR_TIMESCALE="$_floor_timescale" \
    /usr/bin/python3 - <<'PYCTYPES_FRAMEKIT' 2>/dev/null
import ctypes
import json
import os
import sys

def error_json(code, message):
    return json.dumps({"ok": False, "code": code, "message": message})

class CMTime(ctypes.Structure):
    _fields_ = [("value", ctypes.c_int64), ("timescale", ctypes.c_int32),
                ("flags", ctypes.c_int32), ("epoch", ctypes.c_int64)]

def main():
    src_path = os.environ.get("MJ_FRAMEKIT_SOURCE") or ""
    out_path = os.environ.get("MJ_FRAMEKIT_OUTPUT") or ""
    secs_text = os.environ.get("MJ_FRAMEKIT_SECONDS") or ""
    floor_text = os.environ.get("MJ_FRAMEKIT_FLOOR_VALUE") or ""
    floor_ts_text = os.environ.get("MJ_FRAMEKIT_FLOOR_TIMESCALE") or ""
    if not src_path:
        return error_json("INVALID_SOURCE", "Missing source path.")
    if not out_path:
        return error_json("INVALID_OUTPUT", "Missing output path.")
    if not secs_text:
        return error_json("INVALID_TIME", "Missing requested time.")
    if not floor_text or not floor_ts_text:
        return error_json("INVALID_FLOOR_TIME", "Missing frame presentation time.")
    try:
        t_secs = float(secs_text)
        floor_val = int(floor_text)
        floor_ts = int(floor_ts_text)
    except ValueError:
        return error_json("INVALID_TIME", "Requested time is not numeric.")
    if t_secs < 0:
        return error_json("INVALID_TIME", "Requested time is negative.")
    if floor_val < 0 or floor_ts < 1:
        return error_json("INVALID_FLOOR_TIME", "Frame presentation time is invalid.")
    if os.path.exists(out_path):
        return error_json("OUTPUT_EXISTS", "The output path already exists.")

    try:
        objc = ctypes.CDLL("/usr/lib/libobjc.A.dylib")
        ctypes.CDLL("/System/Library/Frameworks/AVFoundation.framework/AVFoundation")
        imgio = ctypes.CDLL("/System/Library/Frameworks/ImageIO.framework/ImageIO")
        cf = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
    except Exception as e:
        return error_json("BRIDGE_LOAD_FAILED", "Could not load system frameworks: %s" % e)

    objc.objc_getClass.restype = ctypes.c_void_p
    objc.objc_getClass.argtypes = [ctypes.c_char_p]
    objc.sel_registerName.restype = ctypes.c_void_p
    objc.sel_registerName.argtypes = [ctypes.c_char_p]

    def cls(n):
        c = objc.objc_getClass(n.encode())
        if not c:
            raise RuntimeError("class %s not found" % n)
        return c

    def sel(n):
        return objc.sel_registerName(n.encode())

    msg = objc.objc_msgSend
    msg.restype = ctypes.c_void_p

    try:
        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_char_p]
        nsstr = msg(cls("NSString"), sel("stringWithUTF8String:"), src_path.encode("utf-8"))
        if not nsstr:
            return error_json("ASSET_OPEN_FAILED", "Could not form a string for the source path.")
        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
        nsurl = msg(cls("NSURL"), sel("fileURLWithPath:"), nsstr)
        if not nsurl:
            return error_json("ASSET_OPEN_FAILED", "Could not form a file URL for the source.")
        asset_cls = cls("AVURLAsset")
        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        alloced = msg(asset_cls, sel("alloc"))
        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
        asset = msg(alloced, sel("initWithURL:options:"), nsurl, None)
        if not asset:
            return error_json("ASSET_OPEN_FAILED", "AVURLAsset could not open the source.")

        # Refuse video-less sources at the adapter level (defense in depth;
        # the caller also probes).
        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_char_p]
        media_type = msg(cls("NSString"), sel("stringWithUTF8String:"), b"vide")
        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
        tracks = msg(asset, sel("tracksWithMediaType:"), media_type)
        if not tracks:
            return error_json("NO_VIDEO_TRACK_ADAPTER", "The asset has no video track.")
        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        ntracks = msg(tracks, sel("count"))
        if ntracks < 1:
            return error_json("NO_VIDEO_TRACK_ADAPTER", "The asset has no video track.")

        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
        gen = msg(cls("AVAssetImageGenerator"), sel("assetImageGeneratorWithAsset:"), asset)
        if not gen:
            return error_json("GENERATOR_FAILED", "AVAssetImageGenerator could not be created.")
        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_bool]
        msg(gen, sel("setAppliesPreferredTrackTransform:"), True)

        # Zero tolerances via NSInvocation (CMTime is passed by value).
        for tsel_name in ("setRequestedTimeToleranceBefore:", "setRequestedTimeToleranceAfter:"):
            ts = sel(tsel_name)
            msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
            sig = msg(gen, sel("methodSignatureForSelector:"), ts)
            if not sig:
                return error_json("GENERATOR_FAILED", "Could not get method signature for %s" % tsel_name)
            inv = msg(cls("NSInvocation"), sel("invocationWithMethodSignature:"), sig)
            msg(inv, sel("setTarget:"), gen)
            msg(inv, sel("setSelector:"), ts)
            zt = CMTime(0, floor_ts, 1, 0)
            msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int]
            msg(inv, sel("setArgument:atIndex:"), ctypes.byref(zt), 2)
            msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
            msg(inv, sel("invoke"))

        # Extract the exact sample frame, capturing actualTime.
        cs = sel("copyCGImageAtTime:actualTime:error:")
        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
        sig = msg(gen, sel("methodSignatureForSelector:"), cs)
        if not sig:
            return error_json("GENERATOR_FAILED", "Could not get method signature for copyCGImageAtTime.")
        inv = msg(cls("NSInvocation"), sel("invocationWithMethodSignature:"), sig)
        msg(inv, sel("setTarget:"), gen)
        msg(inv, sel("setSelector:"), cs)
        req = CMTime(floor_val, floor_ts, 1, 0)
        actual = CMTime(0, 0, 0, 0)
        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int]
        msg(inv, sel("setArgument:atIndex:"), ctypes.byref(req), 2)
        msg(inv, sel("setArgument:atIndex:"), ctypes.byref(actual), 3)
        nullp = ctypes.c_void_p(None)
        msg(inv, sel("setArgument:atIndex:"), ctypes.byref(nullp), 4)
        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        msg(inv, sel("invoke"))
        image = ctypes.c_void_p()
        msg.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
        msg(inv, sel("getReturnValue:"), ctypes.byref(image))
        if not image.value:
            return error_json("FRAME_GENERATION_FAILED",
                               "AVFoundation did not return an image for frame presentation time %d/%d."
                               % (floor_val, floor_ts))

        # Dimensions via CoreGraphics C API.
        imgio.CGImageGetWidth.restype = ctypes.c_ulong
        imgio.CGImageGetWidth.argtypes = [ctypes.c_void_p]
        imgio.CGImageGetHeight.restype = ctypes.c_ulong
        imgio.CGImageGetHeight.argtypes = [ctypes.c_void_p]
        w = imgio.CGImageGetWidth(image)
        h = imgio.CGImageGetHeight(image)
        if w < 1 or h < 1:
            return error_json("FRAME_RESULT_INVALID", "AVFoundation returned invalid frame dimensions.")

        # Write PNG via ImageIO C API.
        cf.CFURLCreateFromFileSystemRepresentation.restype = ctypes.c_void_p
        cf.CFURLCreateFromFileSystemRepresentation.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_long, ctypes.c_bool]
        out_url = cf.CFURLCreateFromFileSystemRepresentation(None, out_path.encode("utf-8"), len(out_path.encode("utf-8")), False)
        if not out_url:
            return error_json("PNG_WRITE_FAILED", "Could not form an output file URL.")
        cf.CFStringCreateWithCString.restype = ctypes.c_void_p
        cf.CFStringCreateWithCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint32]
        type_str = cf.CFStringCreateWithCString(None, b"public.png", 0x08000100)
        imgio.CGImageDestinationCreateWithURL.restype = ctypes.c_void_p
        imgio.CGImageDestinationCreateWithURL.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_ulong, ctypes.c_void_p]
        dest = imgio.CGImageDestinationCreateWithURL(out_url, type_str, 1, None)
        if not dest:
            return error_json("PNG_ENCODE_FAILED", "ImageIO could not create a PNG destination.")
        imgio.CGImageDestinationAddImage.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
        imgio.CGImageDestinationAddImage(dest, image, None)
        imgio.CGImageDestinationFinalize.restype = ctypes.c_bool
        imgio.CGImageDestinationFinalize.argtypes = [ctypes.c_void_p]
        if not imgio.CGImageDestinationFinalize(dest):
            return error_json("PNG_WRITE_FAILED", "ImageIO could not finalize the PNG file.")
    except Exception as e:
        return error_json("PYCTYPES_EXCEPTION", "Python ctypes adapter failed: %s" % e)

    if not os.path.isfile(out_path) or os.path.getsize(out_path) < 1:
        return error_json("PNG_WRITE_FAILED", "The staged PNG output is missing or empty.")

    # actualTime captured from the generator; fall back to the requested
    # floor time if the generator left it invalid.
    if actual.flags & 1 and actual.timescale > 0:
        a_val, a_ts = actual.value, actual.timescale
    else:
        a_val, a_ts = floor_val, floor_ts
    a_secs = float(a_val) / float(a_ts)
    return json.dumps({
        "ok": True,
        "requestedSeconds": t_secs,
        "actualSeconds": a_secs,
        "actualValue": int(a_val),
        "actualTimescale": int(a_ts),
        "pixelWidth": int(w),
        "pixelHeight": int(h),
        "transformApplied": True,
        "toleranceBeforeSeconds": 0,
        "toleranceAfterSeconds": 0,
        "adapter": "PYCTYPES_AVAssetImageGenerator",
    })

try:
    sys.stdout.write(main())
except Exception as e:
    sys.stdout.write(error_json("PYCTYPES_EXCEPTION", "Python ctypes adapter failed: %s" % e))
PYCTYPES_FRAMEKIT
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
  cap_available python3 && cap_available jq && cap_available sips && cap_available awk && cap_available mktemp && cap_available mv && cap_available rm && cap_available stat && cap_available uname && standard_library_localfs_available && standard_library_mediaprobe_available
}
