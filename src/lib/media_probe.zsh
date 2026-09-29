# MJ Standard Library 1.0 — MediaProbe
# Normalizes a bounded subset of Apple's avmediainfo text output. The adapter
# is deliberately conservative: it parses only stable-looking labeled facts,
# validates numeric fields, and fails closed when the expected shape changes.
# It never enumerates the full sample table in the default timing operation.

media_probe_is_uint() {
  case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

media_probe_is_number() {
  printf '%s\n' "$1" | /usr/bin/awk 'BEGIN{ok=0} /^[0-9]+([.][0-9]+)?$/ {ok=1} END{exit ok?0:1}'
}

media_probe_reset() {
  MJ_MEDIA_DURATION_SECONDS=""
  MJ_MEDIA_DURATION_VALUE=""
  MJ_MEDIA_DURATION_TIMESCALE=""
  MJ_MEDIA_TRACK_COUNT=""
  MJ_MEDIA_VIDEO_TRACK_COUNT="0"
  MJ_MEDIA_VIDEO_TRACK_INDEX=""
  MJ_MEDIA_VIDEO_ENABLED="unknown"
  MJ_MEDIA_VIDEO_CODEC=""
  MJ_MEDIA_VIDEO_FOURCC=""
  MJ_MEDIA_VIDEO_WIDTH=""
  MJ_MEDIA_VIDEO_HEIGHT=""
  MJ_MEDIA_VIDEO_DECODE_SUPPORTED="unknown"
  MJ_MEDIA_VIDEO_DATA_BYTES=""
  MJ_MEDIA_VIDEO_TIMESCALE=""
  MJ_MEDIA_VIDEO_DURATION_SECONDS=""
  MJ_MEDIA_VIDEO_NOMINAL_FPS=""
  MJ_MEDIA_VIDEO_MIN_SAMPLE_VALUE=""
  MJ_MEDIA_VIDEO_MIN_SAMPLE_TIMESCALE=""
  MJ_MEDIA_VIDEO_REORDERING="unknown"
}

# Parse labeled avmediainfo output supplied as one string. The parser is kept
# separate from process execution so it can be regression-tested from fixtures.
media_probe_parse_text() {
  local _text="$1"
  local _parsed=""
  local _key=""
  local _value=""

  media_probe_reset
  _parsed=$(MJ_MEDIA_PROBE_INPUT="$_text" /usr/bin/awk 'BEGIN {
      text=ENVIRON["MJ_MEDIA_PROBE_INPUT"];
      n=split(text, lines, "\n");
      assetDuration=""; durationValue=""; durationScale=""; trackCount="";
      videoCount=0; videoIndex=""; videoEnabled="unknown"; codec=""; fourcc="";
      width=""; height=""; decode="unknown"; dataBytes=""; mediaScale="";
      videoDuration=""; fps=""; minValue=""; minScale=""; reorder="unknown";
      inVideo=0;
      for (i=1; i<=n; i++) {
        line=lines[i];
        if (line ~ /^Duration:[[:space:]]*[0-9]/ && assetDuration=="") {
          v=line; sub(/^Duration:[[:space:]]*/, "", v);
          split(v, a, /[[:space:]]+/); assetDuration=a[1];
          r=line; sub(/^.*\(/, "", r); sub(/\).*$/, "", r);
          if (r ~ /^[0-9]+\/[0-9]+$/) { split(r, q, "/"); durationValue=q[1]; durationScale=q[2]; }
        }
        if (line ~ /^Track count:[[:space:]]*[0-9]+/) {
          v=line; sub(/^Track count:[[:space:]]*/, "", v); trackCount=v;
        }
        if (line ~ /^Track [0-9]+: Video/) {
          videoCount++;
          if (videoCount==1) {
            inVideo=1;
            v=line; sub(/^Track[[:space:]]+/, "", v); sub(/:.*/, "", v); videoIndex=v;
            if (line ~ /, Enabled,/) videoEnabled="true";
            else if (line ~ /, Disabled,/) videoEnabled="false";
          } else {
            inVideo=0;
          }
          continue;
        }
        if (line ~ /^Track [0-9]+:/ && line !~ /: Video/) { inVideo=0; continue; }
        if (!inVideo) continue;

        if (line ~ /^[[:space:]]*Enabled:[[:space:]]*/) {
          v=line; sub(/^[[:space:]]*Enabled:[[:space:]]*/, "", v);
          if (v=="Yes") videoEnabled="true"; else if (v=="No") videoEnabled="false";
        } else if (line ~ /^[[:space:]]*Format:[[:space:]]*/) {
          v=line; sub(/^[[:space:]]*Format:[[:space:]]*/, "", v);
          parts=split(v, p, "\047");
          if (parts>=3) { fourcc=p[2]; codec=p[1]; sub(/[[:space:]]+$/, "", codec); }
          else { codec=v; }
        } else if (line ~ /^[[:space:]]*Dimensions:[[:space:]]*[0-9]+[[:space:]]*x[[:space:]]*[0-9]+/) {
          v=line; sub(/^[[:space:]]*Dimensions:[[:space:]]*/, "", v); gsub(/[[:space:]]/, "", v);
          split(v, d, "x"); width=d[1]; height=d[2];
        } else if (line ~ /^[[:space:]]*System support for decoding this track:[[:space:]]*/) {
          v=line; sub(/^.*:[[:space:]]*/, "", v);
          if (v=="Yes") decode="true"; else if (v=="No") decode="false";
        } else if (line ~ /^[[:space:]]*Data size:[[:space:]]*[0-9]+ bytes/) {
          v=line; sub(/^[[:space:]]*Data size:[[:space:]]*/, "", v); sub(/[[:space:]]+bytes.*/, "", v); dataBytes=v;
        } else if (line ~ /^[[:space:]]*Media time scale:[[:space:]]*[0-9]+/) {
          v=line; sub(/^[[:space:]]*Media time scale:[[:space:]]*/, "", v); mediaScale=v;
        } else if (line ~ /^[[:space:]]+Duration:[[:space:]]*[0-9]/) {
          v=line; sub(/^[[:space:]]+Duration:[[:space:]]*/, "", v); split(v, a, /[[:space:]]+/); videoDuration=a[1];
        } else if (line ~ /^[[:space:]]*Nominal frame rate:[[:space:]]*[0-9]/) {
          v=line; sub(/^[[:space:]]*Nominal frame rate:[[:space:]]*/, "", v); sub(/[[:space:]]+fps.*/, "", v); fps=v;
        } else if (line ~ /^[[:space:]]*Minimum sample duration:[[:space:]]*[0-9]+\/[0-9]+ seconds/) {
          v=line; sub(/^[[:space:]]*Minimum sample duration:[[:space:]]*/, "", v); sub(/[[:space:]]+seconds.*/, "", v);
          split(v, q, "/"); minValue=q[1]; minScale=q[2];
        } else if (line ~ /^[[:space:]]*Frame reordering required/) {
          reorder="true";
        } else if (line ~ /^[[:space:]]*Frame reordering not required/) {
          reorder="false";
        }
      }
      print "durationSeconds=" assetDuration;
      print "durationValue=" durationValue;
      print "durationTimescale=" durationScale;
      print "trackCount=" trackCount;
      print "videoTrackCount=" videoCount;
      print "videoTrackIndex=" videoIndex;
      print "videoEnabled=" videoEnabled;
      print "videoCodec=" codec;
      print "videoFourCC=" fourcc;
      print "videoWidth=" width;
      print "videoHeight=" height;
      print "videoDecodeSupported=" decode;
      print "videoDataBytes=" dataBytes;
      print "videoTimescale=" mediaScale;
      print "videoDurationSeconds=" videoDuration;
      print "videoNominalFPS=" fps;
      print "videoMinSampleValue=" minValue;
      print "videoMinSampleTimescale=" minScale;
      print "videoReordering=" reorder;
    }') || return 1

  while IFS='=' read -r _key _value; do
    case "$_key" in
      durationSeconds) MJ_MEDIA_DURATION_SECONDS="$_value" ;;
      durationValue) MJ_MEDIA_DURATION_VALUE="$_value" ;;
      durationTimescale) MJ_MEDIA_DURATION_TIMESCALE="$_value" ;;
      trackCount) MJ_MEDIA_TRACK_COUNT="$_value" ;;
      videoTrackCount) MJ_MEDIA_VIDEO_TRACK_COUNT="$_value" ;;
      videoTrackIndex) MJ_MEDIA_VIDEO_TRACK_INDEX="$_value" ;;
      videoEnabled) MJ_MEDIA_VIDEO_ENABLED="$_value" ;;
      videoCodec) MJ_MEDIA_VIDEO_CODEC="$_value" ;;
      videoFourCC) MJ_MEDIA_VIDEO_FOURCC="$_value" ;;
      videoWidth) MJ_MEDIA_VIDEO_WIDTH="$_value" ;;
      videoHeight) MJ_MEDIA_VIDEO_HEIGHT="$_value" ;;
      videoDecodeSupported) MJ_MEDIA_VIDEO_DECODE_SUPPORTED="$_value" ;;
      videoDataBytes) MJ_MEDIA_VIDEO_DATA_BYTES="$_value" ;;
      videoTimescale) MJ_MEDIA_VIDEO_TIMESCALE="$_value" ;;
      videoDurationSeconds) MJ_MEDIA_VIDEO_DURATION_SECONDS="$_value" ;;
      videoNominalFPS) MJ_MEDIA_VIDEO_NOMINAL_FPS="$_value" ;;
      videoMinSampleValue) MJ_MEDIA_VIDEO_MIN_SAMPLE_VALUE="$_value" ;;
      videoMinSampleTimescale) MJ_MEDIA_VIDEO_MIN_SAMPLE_TIMESCALE="$_value" ;;
      videoReordering) MJ_MEDIA_VIDEO_REORDERING="$_value" ;;
    esac
  done <<EOF_MEDIA_PARSED
$_parsed
EOF_MEDIA_PARSED

  media_probe_is_number "$MJ_MEDIA_DURATION_SECONDS" || return 1
  media_probe_is_uint "$MJ_MEDIA_TRACK_COUNT" || return 1
  if [ -n "$MJ_MEDIA_DURATION_VALUE" ] || [ -n "$MJ_MEDIA_DURATION_TIMESCALE" ]; then
    media_probe_is_uint "$MJ_MEDIA_DURATION_VALUE" || return 1
    media_probe_is_uint "$MJ_MEDIA_DURATION_TIMESCALE" || return 1
    [ "$MJ_MEDIA_DURATION_TIMESCALE" -gt 0 ] || return 1
  fi
  media_probe_is_uint "$MJ_MEDIA_VIDEO_TRACK_COUNT" || return 1

  if [ "$MJ_MEDIA_VIDEO_TRACK_COUNT" -gt 0 ]; then
    media_probe_is_uint "$MJ_MEDIA_VIDEO_TRACK_INDEX" || return 1
    [ "$MJ_MEDIA_VIDEO_TRACK_INDEX" -gt 0 ] || return 1
    [ -n "$MJ_MEDIA_VIDEO_CODEC" ] || return 1
    media_probe_is_uint "$MJ_MEDIA_VIDEO_WIDTH" || return 1
    media_probe_is_uint "$MJ_MEDIA_VIDEO_HEIGHT" || return 1
    [ "$MJ_MEDIA_VIDEO_WIDTH" -gt 0 ] && [ "$MJ_MEDIA_VIDEO_HEIGHT" -gt 0 ] || return 1
    if [ -n "$MJ_MEDIA_VIDEO_DATA_BYTES" ]; then media_probe_is_uint "$MJ_MEDIA_VIDEO_DATA_BYTES" || return 1; fi
    media_probe_is_uint "$MJ_MEDIA_VIDEO_TIMESCALE" || return 1
    [ "$MJ_MEDIA_VIDEO_TIMESCALE" -gt 0 ] || return 1
    media_probe_is_number "$MJ_MEDIA_VIDEO_DURATION_SECONDS" || return 1
    media_probe_is_number "$MJ_MEDIA_VIDEO_NOMINAL_FPS" || return 1
    if [ -n "$MJ_MEDIA_VIDEO_MIN_SAMPLE_VALUE$MJ_MEDIA_VIDEO_MIN_SAMPLE_TIMESCALE" ]; then
      media_probe_is_uint "$MJ_MEDIA_VIDEO_MIN_SAMPLE_VALUE" || return 1
      media_probe_is_uint "$MJ_MEDIA_VIDEO_MIN_SAMPLE_TIMESCALE" || return 1
      [ "$MJ_MEDIA_VIDEO_MIN_SAMPLE_TIMESCALE" -gt 0 ] || return 1
    fi
  fi
  return 0
}

media_probe_analyzed_ok() {
  local _text="$1"
  MJ_MEDIA_PROBE_INPUT="$_text" /usr/bin/awk 'BEGIN {
    text=ENVIRON["MJ_MEDIA_PROBE_INPUT"];
    if (text ~ /Movie analyzed with 0 error\./) exit 0;
    # Target-Mac Gate A (2026-09-29): avmediainfo --brief on audio-only input
    # prints "Error analysis is not supported for format ..." instead of the
    # 0-error sentinel. The container read succeeded; track parsing below
    # still decides NO_VIDEO_TRACK vs timing, so this is not a probe failure.
    if (text ~ /Error analysis is not supported for format /) exit 0;
    exit 1;
  }'
}

# Capture only the pre-sample header. awk exits at "Sample Information" and
# enforces a hard 256-line ceiling so long media cannot create unbounded shell
# output. This is the key Standard Library boundary for synchronous AE use.
media_probe_capture_header() {
  local _path="$1"
  local _out=""
  cap_available avmediainfo && cap_available awk || return 1
  _out=$(/usr/bin/avmediainfo "$_path" --samples --mediatype video 2>/dev/null | /usr/bin/awk '
    NR > 256 { exit 3 }
    /^[[:space:]]*Sample Information[[:space:]]*$/ { exit 0 }
    { print }
  ') || return 1
  MJ_MEDIA_PROBE_HEADER="$_out"
  return 0
}

media_probe_read_timing() {
  local _path="$1"
  local _brief=""
  MJ_MEDIA_PROBE_HEADER=""
  cap_available avmediainfo && cap_available awk || return 1
  _brief=$(/usr/bin/avmediainfo "$_path" --brief 2>/dev/null) || return 1
  media_probe_analyzed_ok "$_brief" || return 1
  media_probe_capture_header "$_path" || return 1
  media_probe_parse_text "$MJ_MEDIA_PROBE_HEADER"
}

standard_library_mediaprobe_available() {
  cap_available avmediainfo && cap_available awk && standard_library_localfs_available
}

# Exact frame-floor lookup from the avmediainfo sample table (text on stdin).
# Prints the presentation timestamp (track-timescale ticks) of the video
# frame displayed at time t: the largest sample presentation timestamp <= t.
#
# Never trusts nominal frame-rate metadata. Target-Mac Gate A (2026-09-29)
# proved a 29.97fps-nominal track uses non-uniform integer presentation
# times in a 600-timescale (..., 561, 581, 601, ...), so frameIndex * fps
# arithmetic cannot name real frames; only the sample table can.
# Fails closed on any shape drift, timescale mismatch, or empty table.
media_probe_sample_floor_ticks_from_text() {
  local _time="$1" _timescale="$2"
  case "$_timescale" in ''|*[!0-9]*) return 1 ;; esac
  MJ_PROBE_FLOOR_TIME="$_time" MJ_PROBE_FLOOR_TS="$_timescale" /usr/bin/awk '
    BEGIN {
      t = ENVIRON["MJ_PROBE_FLOOR_TIME"] + 0;
      ts = ENVIRON["MJ_PROBE_FLOOR_TS"] + 0;
      if (!(t >= 0) || !(ts >= 1)) exit 3;
      req = int(t * ts + 0.000001);
      in_table = 0; best = -1; best_hms = ""; seen = 0;
    }
    !in_table && /Sample Index/ && /Presentation Time/ { in_table = 1; next; }
    in_table && (/^Track / || (/Sample Index/ && /Presentation Time/)) { in_table = 0; next; }
    in_table {
      line = $0; sub(/^[ \t]+/, "", line);
      nf = split(line, f, /[ \t]+/);
      # f[1]=index f[2]=decodeTicks f[3]=decodeHMS f[4]=presentTicks f[5]=presentHMS ...
      if (nf >= 5 && f[1] ~ /^[0-9]+$/ && f[4] ~ /^[0-9]+$/) {
        seen = 1;
        pts = f[4] + 0;
        if (pts <= req && pts > best) { best = pts; best_hms = f[5]; }
      }
      next;
    }
    END {
      if (!seen || best < 0) exit 4;
      # Timescale consistency: the floor tick count expressed in the probe
      # timescale must agree with the table human-readable timestamp.
      nh = split(best_hms, hp, ":");
      if (nh != 3) exit 5;
      hms = hp[1]*3600 + hp[2]*60 + hp[3];
      diff = best/ts - hms;
      if (diff > 0.002 || diff < -0.002) exit 5;
      printf "%d", best;
    }'
}

# Production wrapper: reads the sample table from the media file itself.
media_probe_sample_floor_ticks() {
  local _path="$1" _time="$2" _timescale="$3"
  cap_available avmediainfo && cap_available awk || return 1
  /usr/bin/avmediainfo "$_path" --samples --mediatype video 2>/dev/null | media_probe_sample_floor_ticks_from_text "$_time" "$_timescale"
}
