# Delivery QC: check a rendered movie against a delivery spec before it goes out. Read-only.
#
# media.qc path=<movie> format=<built-in spec> | input=<spec file>
#   Container, codec, size, frame rate, duration, colour tags, audio channels and sample rate from
#   stock avmediainfo; integrated loudness (ITU-R BS.1770-4 / EBU R128 gating) and sample peak
#   measured here in Python on audio decoded by stock afconvert. Each check passes, fails, warns or
#   is skipped with a reason. No ffmpeg: true peak is approximated by the sample peak (stated).

IFS= read -r -d '' MJ_PY_QC <<'PY_QC_LIB' || true
import array, math, struct, subprocess, tempfile

BUILTIN_SPECS = {
    "broadcast-us": {"name": "US broadcast (ATSC A/85)", "container": "mov", "codec": "prores", "width": "1920", "height": "1080",
                     "fps": "29.97, 23.976", "audio": "required", "audioChannels": "2", "audioSampleRate": "48000",
                     "loudness": "-24", "loudnessTolerance": "2", "peakMax": "-2", "colorTags": "required"},
    "broadcast-eu": {"name": "European broadcast (EBU R128)", "container": "mov", "codec": "prores", "width": "1920", "height": "1080",
                     "fps": "25", "audio": "required", "audioChannels": "2", "audioSampleRate": "48000",
                     "loudness": "-23", "loudnessTolerance": "1", "peakMax": "-1", "colorTags": "required"},
    "web": {"name": "Web and streaming", "container": "mp4, mov", "codec": "h264, hevc", "audio": "any",
            "audioSampleRate": "48000, 44100", "loudness": "-14", "loudnessTolerance": "2", "peakMax": "-1"},
    "social-vertical": {"name": "Social, vertical 9:16", "container": "mp4", "codec": "h264", "width": "1080", "height": "1920",
                        "fps": "23.976, 24, 25, 29.97, 30", "maxDuration": "90", "audio": "any", "loudness": "-14", "loudnessTolerance": "2", "peakMax": "-1"},
    "prores-master": {"name": "ProRes master", "container": "mov", "codec": "prores", "audio": "any", "audioSampleRate": "48000", "colorTags": "required"},
}
SPEC_KEYS = {"name", "container", "codec", "width", "height", "fps", "minDuration", "maxDuration", "audio", "audioChannels",
             "audioSampleRate", "loudness", "loudnessTolerance", "peakMax", "colorTags"}
CODEC_FAMILY = {"apch": "prores", "apcn": "prores", "apcs": "prores", "apco": "prores", "ap4h": "prores", "ap4x": "prores", "aprh": "prores", "aprn": "prores",
                "avc1": "h264", "avc3": "h264", "hvc1": "hevc", "hev1": "hevc", "dvh1": "hevc", "jpeg": "mjpeg", "png ": "png", "rle ": "animation", "mp4v": "mpeg4"}

def parse_spec_file(path):
    spec = {}
    try:
        lines = open(path, encoding="utf-8").read(65536).splitlines()
    except (OSError, UnicodeDecodeError):
        err("INVALID_SPEC", "The spec file could not be read as UTF-8 text.")
    for n, line in enumerate(lines, 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            err("INVALID_SPEC", "Spec line %d is not key = value." % n)
        k, v = (x.strip() for x in line.split("=", 1))
        if k not in SPEC_KEYS:
            err("INVALID_SPEC", "Spec line %d: unknown key %s (known: %s)." % (n, k, ", ".join(sorted(SPEC_KEYS))))
        spec[k] = v
    return spec

def spec_list(v):
    return [x.strip().lower() for x in str(v).split(",") if x.strip()]

def spec_num(spec, k):
    try:
        return float(spec[k])
    except (KeyError, ValueError):
        if k in spec:
            err("INVALID_SPEC", "%s must be a number." % k)
        return None

def probe(avmediainfo, path):
    try:
        out = subprocess.run([avmediainfo, path], capture_output=True, text=True, timeout=60, stdin=subprocess.DEVNULL)
    except Exception:
        err("NATIVE_OUTPUT_INVALID", "avmediainfo could not be run on this file.")
    text = out.stdout
    if out.returncode != 0 or "Track count:" not in text:
        err("DECODE_UNSUPPORTED", "macOS cannot read this movie (avmediainfo found no tracks).")
    info = {"duration": None, "video": None, "audio": None}
    m = re.search(r"^Duration: ([0-9.]+) seconds", text, re.M)
    if m:
        info["duration"] = float(m.group(1))
    for block in re.split(r"^Track \d+: ", text, flags=re.M)[1:]:
        kind = block.split(None, 1)[0]
        if kind == "Video" and info["video"] is None:
            v = {}
            m = re.search(r"Format: (.*?) '(.{4})'", block)
            if m:
                v["format"], v["fourcc"] = m.group(1), m.group(2)
                v["codec"] = CODEC_FAMILY.get(m.group(2), m.group(2).strip().lower())
            m = re.search(r"Presentation Dimensions: (\d+) x (\d+)", block) or re.search(r"Dimensions: (\d+) x (\d+)", block)
            if m:
                v["width"], v["height"] = int(m.group(1)), int(m.group(2))
            m = re.search(r"Nominal frame rate: ([0-9.]+) fps", block)
            if m:
                v["fps"] = float(m.group(1))
            v["colorTags"] = {"primaries": "Color Primaries were not specified" not in block,
                              "transfer": "Transfer function was not specified" not in block,
                              "matrix": "YCbCr matrix was not specified" not in block}
            info["video"] = v
        elif kind == "Sound" and info["audio"] is None:
            a = {}
            m = re.search(r"Format: (.*?) '(.{4})'", block)
            if m:
                a["format"] = m.group(1)
            m = re.search(r"Channels per frame: (\d+)", block)
            if m:
                a["channels"] = int(m.group(1))
            m = re.search(r"Sample rate: ([0-9.]+)", block)
            if m:
                a["sampleRate"] = float(m.group(1))
            info["audio"] = a
    return info

# ---- ITU-R BS.1770-4 loudness, streamed so long files need little memory ----
def _biquads(rate):
    """K-weighting: high shelf then high pass, coefficients for any sample rate (BS.1770 analogue prototypes)."""
    def shelf():
        G, Q, fc = 3.99984385397, 0.7071752369554193, 1681.9744509555319
        K = math.tan(math.pi * fc / rate); Vh = 10 ** (G / 20.0); Vb = Vh ** 0.499666774155
        a0 = 1 + K / Q + K * K
        return ((Vh + Vb * K / Q + K * K) / a0, 2 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0)
    def highpass():
        Q, fc = 0.5003270373253953, 38.13547087613982
        K = math.tan(math.pi * fc / rate)
        a0 = 1 + K / Q + K * K
        return (1 / a0, -2 / a0, 1 / a0, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0)
    return shelf(), highpass()

def read_wav_float(path):
    """Yields (rate, channels) then interleaved float32 arrays of about one second each."""
    f = open(path, "rb")
    if f.read(4) != b"RIFF":
        raise ValueError("not a WAV file")
    f.read(4)
    if f.read(4) != b"WAVE":
        raise ValueError("not a WAV file")
    rate = chans = fmt = bits = None
    while True:
        hdr = f.read(8)
        if len(hdr) < 8:
            raise ValueError("no data chunk")
        cid, size = hdr[:4], struct.unpack("<I", hdr[4:])[0]
        if cid == b"fmt ":
            body = f.read(size)
            fmt, chans, rate = struct.unpack("<HHI", body[:8]); bits = struct.unpack("<H", body[14:16])[0]
            if fmt == 0xFFFE and len(body) >= 26:
                fmt = struct.unpack("<H", body[24:26])[0]
        elif cid == b"data":
            break
        else:
            f.seek(size + (size & 1), 1)
    if fmt != 3 or bits != 32:
        raise ValueError("expected 32-bit float samples")
    yield rate, chans
    left = size
    step = rate * chans * 4
    while left > 0:
        buf = f.read(min(step, left))
        if not buf:
            break
        left -= len(buf)
        a = array.array("f"); a.frombytes(buf[: len(buf) - len(buf) % 4])
        if struct.pack("=I", 1) != struct.pack("<I", 1):
            a.byteswap()
        yield a

def loudness(wav_path):
    """{integrated LUFS or None (all gated out), samplePeak dBFS, seconds}."""
    gen = read_wav_float(wav_path)
    rate, chans = next(gen)
    (b0, b1, b2, a1, a2), (c0, c1, c2, d1, d2) = _biquads(rate)
    weights = [1.0, 1.0, 1.0, 0.0, 1.41, 1.41][:chans] if chans <= 6 else [1.0] * chans
    if chans <= 2:
        weights = [1.0] * chans
    active = [ch for ch in range(chans) if weights[ch] != 0.0]
    state = {ch: [0.0] * 8 for ch in active}
    seg = rate // 10                      # 100 ms
    seg_sums, cur, cur_n = [], [0.0] * chans, 0
    peak = 0.0
    total = 0
    for block in gen:
        n = len(block) // chans
        total += n
        if n:
            peak = max(peak, max(block), -min(block))
        sqs = {}
        for ch in active:
            x1, x2, y1, y2, z1, z2, w1, w2 = state[ch]
            out = []
            app = out.append
            for x in block[ch::chans]:
                y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                x2 = x1; x1 = x; y2 = y1; y1 = y
                z = c0 * y + c1 * z1 + c2 * z2 - d1 * w1 - d2 * w2
                z2 = z1; z1 = y; w2 = w1; w1 = z
                app(z * z)
            state[ch] = [x1, x2, y1, y2, z1, z2, w1, w2]
            sqs[ch] = out
        i = 0
        while i < n:                     # accumulate 100 ms segments
            take = min(seg - cur_n, n - i)
            for ch in active:
                cur[ch] += math.fsum(sqs[ch][i:i + take])
            cur_n += take; i += take
            if cur_n == seg:
                seg_sums.append(cur); cur, cur_n = [0.0] * chans, 0
    # 400 ms blocks, 75 % overlap
    blocks = []
    for j in range(len(seg_sums) - 3):
        z = sum(weights[ch] * sum(seg_sums[j + q][ch] for q in range(4)) / (4 * seg) for ch in range(chans))
        if z > 0:
            blocks.append(z)
    def lufs(z):
        return -0.691 + 10 * math.log10(z)
    gated = [z for z in blocks if lufs(z) > -70.0]
    integrated = None
    if gated:
        rel = lufs(sum(gated) / len(gated)) - 10.0
        g2 = [z for z in gated if lufs(z) > rel]
        if g2:
            integrated = round(lufs(sum(g2) / len(g2)), 1)
    return {"integrated": integrated, "samplePeak": round(20 * math.log10(peak), 1) if peak > 0 else None, "seconds": round(total / float(rate), 3) if rate else 0}
PY_QC_LIB

deliver_python() {
  local _main=""
  IFS= read -r -d '' _main || true
  printf '%s\n%s\n%s' "$MJ_PY_PROTECT_LIB" "$MJ_PY_QC" "$_main" | /usr/bin/python3 - 2>/dev/null
}

handle_media_qc() {
  local _rc=0 _path="" _fmt="" _spec="" _out=""
  require_arg path || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  _path="$MJ_REQUIRED_ARG_VALUE"
  is_absolute_path "$_path" || { set_error "INVALID_PATH" "Movie path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
  [ -f "$_path" ] || { set_error "NOT_FOUND" "Movie not found."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 66; }
  mj_require_local_existing_path "$_path" || { emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 73; }
  request_arg_present format && _fmt=$(request_arg_get format)
  request_arg_present input && _spec=$(request_arg_get input)
  if [ -n "$_fmt" ] && [ -n "$_spec" ]; then set_error "INVALID_ARGUMENT" "Give either format (a built-in spec) or input (a spec file), not both."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; fi
  if [ -z "$_fmt" ] && [ -z "$_spec" ]; then set_error "MISSING_ARGUMENT" "Give format=<built-in spec> or input=<spec file>."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; fi
  if [ -n "$_spec" ]; then
    is_absolute_path "$_spec" || { set_error "INVALID_PATH" "Spec path must be absolute."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 65; }
    [ -f "$_spec" ] || { set_error "NOT_FOUND" "Spec file not found."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 66; }
  fi
  cap_available python3 && cap_available avmediainfo || { set_error "UNSUPPORTED" "Delivery QC needs stock python3 and avmediainfo (macOS 12 or later)."; emit_error_response "$REQUEST_COMMAND" "$REQUEST_ID"; return 69; }
  _out=$(MJ_MOVIE="$_path" MJ_FMT="$_fmt" MJ_SPEC="$_spec" MJ_AVMEDIAINFO="$(cap_path avmediainfo)" \
         MJ_AFCONVERT="$(cap_available afconvert && cap_path afconvert)" deliver_python <<'PY_MEDIA_QC'
movie = os.environ["MJ_MOVIE"]
id0 = tree_id(movie)
if os.environ["MJ_FMT"]:
    spec = BUILTIN_SPECS.get(os.environ["MJ_FMT"])
    if spec is None:
        err("INVALID_ARGUMENT", "Unknown spec %s; built-in specs: %s." % (os.environ["MJ_FMT"], ", ".join(sorted(BUILTIN_SPECS))))
    spec = dict(spec); spec_name = spec.pop("name"); spec_src = os.environ["MJ_FMT"]
else:
    spec = parse_spec_file(os.environ["MJ_SPEC"]); spec_name = spec.pop("name", os.path.basename(os.environ["MJ_SPEC"])); spec_src = os.environ["MJ_SPEC"]
info = probe(os.environ["MJ_AVMEDIAINFO"], movie)
v, a = info["video"] or {}, info["audio"]
checks = []
def add(check, status, expected, actual, message):
    checks.append({"check": check, "status": status, "expected": expected, "actual": actual, "message": message})
def one_of(check, key, actual, label):
    if key not in spec:
        return
    want = spec_list(spec[key])
    if actual is None:
        add(check, "fail", ", ".join(want), None, "%s could not be read." % label)
    elif str(actual).lower() in want:
        add(check, "pass", ", ".join(want), actual, "%s is %s." % (label, actual))
    else:
        add(check, "fail", ", ".join(want), actual, "%s is %s; the spec wants %s." % (label, actual, " or ".join(want)))

ext = os.path.splitext(movie)[1].lower().lstrip(".")
one_of("container", "container", ext, "Container")
if not info["video"]:
    if any(k in spec for k in ("codec", "width", "height", "fps", "colorTags")):
        add("video", "fail", "a video track", None, "There is no video track.")
else:
    one_of("codec", "codec", v.get("codec"), "Codec")
    for key in ("width", "height"):
        if key in spec:
            want = int(spec_num(spec, key)); got = v.get(key)
            add(key, "pass" if got == want else "fail", want, got, "%s is %s%s." % (key.capitalize(), got, "" if got == want else "; the spec wants %d" % want))
    if "fps" in spec:
        want = [float(x) for x in spec_list(spec["fps"])]
        got = v.get("fps")
        ok = got is not None and any(abs(got - w) < 0.011 for w in want)
        add("fps", "pass" if ok else "fail", ", ".join("%g" % w for w in want), got, "Frame rate is %s fps%s." % ("%g" % got if got else "unknown", "" if ok else "; the spec wants %s" % " or ".join("%g" % w for w in want)))
    if spec.get("colorTags", "").lower() == "required":
        tags = v.get("colorTags", {})
        missing = [k for k in ("primaries", "transfer", "matrix") if not tags.get(k)]
        add("colorTags", "fail" if missing else "pass", "primaries, transfer, matrix", [k for k in tags if tags[k]],
            "Colour tags missing: %s; players may show the wrong colours." % ", ".join(missing) if missing else "Colour tags are set.")
dur = info["duration"]
for key, cmp, word in (("minDuration", lambda d, w: d >= w - 0.001, "at least"), ("maxDuration", lambda d, w: d <= w + 0.001, "at most")):
    if key in spec:
        w = spec_num(spec, key)
        ok = dur is not None and cmp(dur, w)
        add(key, "pass" if ok else "fail", w, dur, "Duration is %.3f s; the spec wants %s %g s." % (dur or 0, word, w))
need_audio = spec.get("audio", "any").lower()
if need_audio == "required" and not a:
    add("audio", "fail", "an audio track", None, "There is no audio track.")
elif need_audio == "none" and a:
    add("audio", "fail", "no audio", a.get("format"), "There is an audio track; the spec wants none.")
if a:
    if "audioChannels" in spec:
        w = int(spec_num(spec, "audioChannels")); g = a.get("channels")
        add("audioChannels", "pass" if g == w else "fail", w, g, "Audio has %s channel%s%s." % (g, "" if g == 1 else "s", "" if g == w else "; the spec wants %d" % w))
    if "audioSampleRate" in spec:
        want = [int(float(x)) for x in spec_list(spec["audioSampleRate"])]; g = int(a.get("sampleRate") or 0)
        add("audioSampleRate", "pass" if g in want else "fail", ", ".join(map(str, want)), g, "Audio sample rate is %d Hz%s." % (g, "" if g in want else "; the spec wants %s" % " or ".join(map(str, want))))
measured = None
if a and ("loudness" in spec or "peakMax" in spec):
    afc = os.environ.get("MJ_AFCONVERT", "")
    if not afc:
        for key in ("loudness", "peakMax"):
            if key in spec:
                add(key, "skipped", spec[key], None, "Not measured: afconvert is not available.")
    else:
        tmp = tempfile.mkdtemp(prefix="mj-qc.")
        wav = os.path.join(tmp, "audio.wav")
        try:
            r = subprocess.run([afc, "-f", "WAVE", "-d", "LEF32", movie, wav], capture_output=True, timeout=600, stdin=subprocess.DEVNULL)
            if r.returncode != 0 or not os.path.isfile(wav):
                raise ValueError("decode failed")
            measured = loudness(wav)
        except Exception:
            measured = None
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        if measured is None:
            for key in ("loudness", "peakMax"):
                if key in spec:
                    add(key, "skipped", spec[key], None, "Not measured: macOS could not decode the audio.")
        else:
            if "loudness" in spec:
                w = spec_num(spec, "loudness"); tol = spec_num(spec, "loudnessTolerance") or 1.0; g = measured["integrated"]
                if g is None:
                    add("loudness", "warn", "%g LUFS" % w, None, "The audio is silent (below the -70 LUFS gate).")
                else:
                    ok = abs(g - w) <= tol + 1e-9
                    add("loudness", "pass" if ok else "fail", "%g LUFS (+/- %g)" % (w, tol), g,
                        "Integrated loudness is %.1f LUFS%s." % (g, "" if ok else "; the spec wants %g +/- %g (%s by %.1f LU)" % (w, tol, "too loud" if g > w else "too quiet", abs(g - w))))
            if "peakMax" in spec:
                w = spec_num(spec, "peakMax"); g = measured["samplePeak"]
                ok = g is None or g <= w + 1e-9
                add("peakMax", "pass" if ok else "fail", "%g dBFS" % w, g, "Sample peak is %s dBFS%s." % ("%.1f" % g if g is not None else "-inf", "" if ok else "; the spec allows %g" % w))
order = {"fail": 0, "warn": 1, "skipped": 2, "pass": 3}
fails = sum(1 for c in checks if c["status"] == "fail")
warns = []
if any(c["check"] == "peakMax" and c["status"] != "skipped" for c in checks):
    warns.append({"code": "PEAK_IS_SAMPLE_PEAK", "message": "Peak is the sample peak; a true-peak meter can read up to about 0.5 dB higher on bright material."})
print(json.dumps({"ok": True, "data": {
    "schema": "MJ_MEDIA_QC_1", "path": movie, "spec": spec_src, "specName": spec_name, "passed": fails == 0,
    "failed": fails, "warnings": sum(1 for c in checks if c["status"] == "warn"), "skipped": sum(1 for c in checks if c["status"] == "skipped"),
    "checks": sorted(checks, key=lambda c: order[c["status"]]),
    "media": {"duration": dur, "video": info["video"], "audio": a, "loudness": measured},
    "sourceUnchanged": tree_id(movie) == id0,
    "_warnings": warns,
}}))
PY_MEDIA_QC
) || true
  frames_emit_python_result "$_out"
}
