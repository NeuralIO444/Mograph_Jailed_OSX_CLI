#!/usr/bin/env bash
# media.qc and mj qc. avmediainfo and afconvert are stood in for by small scripts (test bundle hook);
# the loudness meter itself runs for real on generated audio with known loudness (ITU-R BS.1770:
# a 1 kHz sine at A dBFS on both stereo channels reads A LUFS), and against ffmpeg when it is installed.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
export MJ_STORE_DIR="$TMP/store" MJ_AUDIT_DIR="$TMP/noaudit" MJ_TEST_AVMEDIAINFO="$TMP/avmediainfo" MJ_TEST_AFCONVERT="$TMP/afconvert"
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
has(){ case "$(cat "$1")" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
b64(){ printf '%s' "$1" | base64 | tr -d '\n'; }
run(){
  local _out="$1" _cmd="$2"; shift 2
  local _f="$TMP/req_$RANDOM$RANDOM.txt"
  { printf 'MOGRAPHJAILED_REQUEST 1\nrequestId=t%s\ncommand=%s\n' "$RANDOM" "$_cmd"
    for _a in "$@"; do printf 'arg.%s=%s\n' "${_a%%=*}" "$(b64 "${_a#*=}")"; done; } > "$_f"
  set +e; "$CLI" --request "$_f" > "$_out" 2>/dev/null; echo $? > "$_out.rc"; set -e
}
# Stand-ins: avmediainfo prints <movie>.avmi; afconvert copies <movie>.wav to its output argument.
printf '#!/bin/sh\n[ -f "$1.avmi" ] || exit 1\ncat "$1.avmi"\n' > "$TMP/avmediainfo"
printf '#!/bin/sh\nfor a; do last=$a; done\nfor a; do case "$a" in *.mov|*.mp4) src=$a ;; esac; done\n[ -f "$src.wav" ] || exit 1\ncp "$src.wav" "$last"\n' > "$TMP/afconvert"
chmod +x "$TMP/avmediainfo" "$TMP/afconvert"

python3 - "$TMP" <<'PY'
import math, os, struct, sys
d = sys.argv[1]
def wav(path, rate, chans, frames):
    data = b"".join(struct.pack("<" + "f" * chans, *fr) for fr in frames)
    fmt = struct.pack("<HHIIHH", 3, chans, rate, rate * chans * 4, chans * 4, 32)
    body = b"WAVE" + b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"FLLR" + struct.pack("<I", 4) + b"\0\0\0\0" + b"data" + struct.pack("<I", len(data)) + data
    open(path, "wb").write(b"RIFF" + struct.pack("<I", len(body)) + body)
def sine(db, secs, rate=48000, chans=2, f=1000.0):
    a = 10 ** (db / 20.0)
    return [(a * math.sin(2 * math.pi * f * i / rate),) * chans for i in range(int(secs * rate))]
AV = """Asset: {name}
Duration: {dur} seconds (1/1)
Track count: 2
Track 1: Video 'vide'
\tEnabled: Yes
\tFormat Description 1:
\t\tFormat: {fmt}
\t\tDimensions: {w} x {h}
\t\tPresentation Dimensions: {w} x {h}
{color}\tSystem support for decoding this track: Yes
\tNominal frame rate: {fps} fps
Track 2: Sound 'soun'
\tEnabled: Yes
\tFormat Description 1:
\t\tFormat: Linear PCM 'lpcm'
\t\tSample rate: {sr}
\t\tChannels per frame: {ch}
\tSystem support for decoding this track: Yes

Movie analyzed with 0 error.
"""
NOCOLOR = "\t\tWarning: Color Primaries were not specified in the format description\n\t\tWarning: Transfer function was not specified in the format description\n\t\tWarning: YCbCr matrix was not specified in the format description\n"
def movie(name, frames_db, color=True, fmt="Apple ProRes 422 HQ 'apch'", w=1920, h=1080, fps="29.970", sr="48000.0", ch=2, dur="5.000", audio=True):
    p = os.path.join(d, name); open(p, "wb").write(b"movie")
    text = AV.format(name=name, dur=dur, fmt=fmt, w=w, h=h, fps=fps, sr=sr, ch=ch, color="" if color else NOCOLOR)
    if not audio:
        text = text.split("Track 2:")[0].replace("Track count: 2", "Track count: 1") + "\nMovie analyzed with 0 error.\n"
    open(p + ".avmi", "w").write(text)
    if frames_db is not None:
        wav(p + ".wav", 48000, 2, frames_db)
movie("good.mov", sine(-24.0, 5))                                     # on target for broadcast-us
movie("loud.mov", sine(-20.0, 5), color=False)                        # 4 LU too loud, no colour tags
movie("gated.mov", sine(-24.0, 3) + sine(-70.0, 3))                   # quiet tail is gated out
movie("silent.mov", [(0.0, 0.0)] * 48000 * 2)
movie("web.mp4", sine(-14.0, 3), fmt="H.264 'avc1'", fps="23.976")
movie("vertical.mp4", sine(-14.0, 3), fmt="H.264 'avc1'", w=1080, h=1920, fps="30.000", dur="95.000")
movie("noaudio.mov", None, audio=False)
movie("nodecode.mov", None)                                           # afconvert stand-in has no audio for it
open(os.path.join(d, "custom.mjspec"), "w").write("# house spec\nname = House master\ncodec = prores\nfps = 29.97\nloudness = -24\nloudnessTolerance = 0.5\naudioChannels = 2\n")
open(os.path.join(d, "bad.mjspec"), "w").write("codec = prores\nloudnes = -24\n")
PY

run "$TMP/g.json" media.qc path="$TMP/good.mov" format=broadcast-us
check jq -e '.ok and .data.schema=="MJ_MEDIA_QC_1" and .data.passed and .data.failed==0' "$TMP/g.json"
check jq -e '.data.media.loudness.integrated==-24.0 and .data.media.loudness.samplePeak==-24.0' "$TMP/g.json"
check jq -e '[.data.checks[].check]|sort==["audioChannels","audioSampleRate","codec","colorTags","container","fps","height","loudness","peakMax","width"]' "$TMP/g.json"
check jq -e '.data.sourceUnchanged and ([.warnings[].code]==["PEAK_IS_SAMPLE_PEAK"])' "$TMP/g.json"

run "$TMP/l.json" media.qc path="$TMP/loud.mov" format=broadcast-us
check jq -e '.data.passed==false and .data.failed==2 and (.data.checks[0:2]|map(.check)|sort)==["colorTags","loudness"]' "$TMP/l.json"
check jq -e '(.data.checks[]|select(.check=="loudness")|.actual)==-20.0' "$TMP/l.json"
check jq -e '(.data.checks[]|select(.check=="loudness")|.message|test("too loud by 4.0 LU"))' "$TMP/l.json"
check test "$(cat "$TMP/l.json.rc")" = 0                              # a failed check is a result, not an error

run "$TMP/ga.json" media.qc path="$TMP/gated.mov" format=broadcast-us
# Ungated, the quiet half would pull it to about -27; blocks straddling the change keep some energy (ffmpeg reads -24.2).
check jq -e '.data.media.loudness.integrated >= -24.4 and .data.media.loudness.integrated <= -24.1' "$TMP/ga.json"
run "$TMP/s.json" media.qc path="$TMP/silent.mov" format=broadcast-us
check jq -e '(.data.checks[]|select(.check=="loudness")|.status)=="warn" and .data.media.loudness.integrated==null' "$TMP/s.json"

run "$TMP/w.json" media.qc path="$TMP/web.mp4" format=web
check jq -e '.data.passed and .data.media.video.codec=="h264"' "$TMP/w.json"
run "$TMP/w2.json" media.qc path="$TMP/web.mp4" format=broadcast-eu
check jq -e '[.data.checks[]|select(.status=="fail")|.check]|sort==["codec","container","fps","loudness"]' "$TMP/w2.json"
run "$TMP/v.json" media.qc path="$TMP/vertical.mp4" format=social-vertical
check jq -e '[.data.checks[]|select(.status=="fail")|.check]==["maxDuration"]' "$TMP/v.json"
run "$TMP/n.json" media.qc path="$TMP/noaudio.mov" format=broadcast-us
check jq -e '[.data.checks[]|select(.status=="fail")|.check]==["audio"] and ([.data.checks[].check]|index("loudness"))==null' "$TMP/n.json"
run "$TMP/d.json" media.qc path="$TMP/nodecode.mov" format=broadcast-us
check jq -e '[.data.checks[]|select(.status=="skipped")|.check]|sort==["loudness","peakMax"]' "$TMP/d.json"
MJ_TEST_AFCONVERT=/nonexistent run "$TMP/na.json" media.qc path="$TMP/good.mov" format=broadcast-us
check jq -e '(.data.checks[]|select(.check=="loudness")|.message)=="Not measured: afconvert is not available."' "$TMP/na.json"

# Spec files
run "$TMP/c.json" media.qc path="$TMP/good.mov" input="$TMP/custom.mjspec"
check jq -e '.data.passed and .data.specName=="House master" and (.data.checks|length)==4' "$TMP/c.json"
run "$TMP/c2.json" media.qc path="$TMP/loud.mov" input="$TMP/custom.mjspec"
check jq -e '(.data.checks[]|select(.check=="loudness")|.status)=="fail"' "$TMP/c2.json"
run "$TMP/e1.json" media.qc path="$TMP/good.mov" input="$TMP/bad.mjspec"
check jq -e '.error.code=="INVALID_SPEC" and (.error.message|test("line 2: unknown key loudnes"))' "$TMP/e1.json"; check test "$(cat "$TMP/e1.json.rc")" = 65

# Spec validation: typos and bad values are errors, tolerance 0 means exact, an empty spec is refused
printf 'codec = prores\naudio = requried\n' > "$TMP/t1.mjspec"; printf 'fps = abc\n' > "$TMP/t2.mjspec"; printf 'audioSampleRate = 48k\n' > "$TMP/t3.mjspec"
printf 'colorTags = yes\n' > "$TMP/t4.mjspec"; printf 'name = Nothing\n' > "$TMP/t5.mjspec"; printf 'width = nan\n' > "$TMP/t6.mjspec"
for t in t1 t2 t3 t4 t5 t6; do run "$TMP/$t.json" media.qc path="$TMP/good.mov" input="$TMP/$t.mjspec"; check jq -e '.error.code=="INVALID_SPEC"' "$TMP/$t.json"; check test "$(cat "$TMP/$t.json.rc")" = 65; done
printf 'loudness = -24\nloudnessTolerance = 0\n' > "$TMP/exact.mjspec"
run "$TMP/ex1.json" media.qc path="$TMP/good.mov" input="$TMP/exact.mjspec"; check jq -e '.data.passed' "$TMP/ex1.json"
run "$TMP/ex2.json" media.qc path="$TMP/loud.mov" input="$TMP/exact.mjspec"; check jq -e '.data.passed==false and ((.data.checks[]|select(.check=="loudness")|.expected)=="-24 LUFS (+/- 0)")' "$TMP/ex2.json"
# A clip under 0.4 s cannot be measured: skipped, not "silent"
python3 - "$TMP" <<'PY'
import math, os, struct, sys
d = sys.argv[1]; rate = 48000
fr = [(0.1 * math.sin(2 * math.pi * 1000 * i / rate),) * 2 for i in range(int(0.2 * rate))]
data = b"".join(struct.pack("<ff", *f) for f in fr); fmt = struct.pack("<HHIIHH", 3, 2, rate, rate * 8, 8, 32)
body = b"WAVE" + b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", len(data)) + data
open(os.path.join(d, "short.mov.wav"), "wb").write(b"RIFF" + struct.pack("<I", len(body)) + body)
open(os.path.join(d, "short.mov"), "wb").write(b"m")
open(os.path.join(d, "short.mov.avmi"), "w").write(open(os.path.join(d, "good.mov.avmi")).read().replace("good.mov", "short.mov").replace("5.000", "0.200"))
PY
run "$TMP/sh.json" media.qc path="$TMP/short.mov" format=broadcast-us
check jq -e '(.data.checks[]|select(.check=="loudness")|.status)=="skipped" and ((.data.checks[]|select(.check=="loudness")|.message)|test("under 0.4 s"))' "$TMP/sh.json"

# Argument errors
run "$TMP/e2.json" media.qc path="$TMP/good.mov";                                     check jq -e '.error.code=="MISSING_ARGUMENT"' "$TMP/e2.json"
run "$TMP/e3.json" media.qc path="$TMP/good.mov" format=web input="$TMP/custom.mjspec"; check jq -e '.error.code=="INVALID_ARGUMENT"' "$TMP/e3.json"
run "$TMP/e4.json" media.qc path="$TMP/good.mov" format=cinema;                       check jq -e '.error.code=="INVALID_ARGUMENT" and (.error.message|test("broadcast-us"))' "$TMP/e4.json"; check test "$(cat "$TMP/e4.json.rc")" = 65
run "$TMP/e5.json" media.qc path="$TMP/missing.mov" format=web;                       check jq -e '.error.code=="NOT_FOUND"' "$TMP/e5.json"; check test "$(cat "$TMP/e5.json.rc")" = 66
printf x > "$TMP/junk.mov"
run "$TMP/e6.json" media.qc path="$TMP/junk.mov" format=web;                          check jq -e '.error.code=="DECODE_UNSUPPORTED"' "$TMP/e6.json"
MJ_TEST_AVMEDIAINFO=/nonexistent run "$TMP/e7.json" media.qc path="$TMP/good.mov" format=web; check jq -e '.error.code=="UNSUPPORTED"' "$TMP/e7.json"

# mj qc: plain language and a non-zero exit when a check fails
mjz(){ MJ_CLI="$CLI" MJ_CONFIG="$TMP/cfg" zsh -f -c "source '$ROOT/scripts/shell/mj-cli.zsh'; $1" > "$TMP/out.txt" 2>&1 && echo 0 > "$TMP/rc" || echo $? > "$TMP/rc"; }
mjz "mj qc '$TMP/loud.mov' broadcast-us"
check has "$TMP/out.txt" "loud.mov fails 2 checks for US broadcast (ATSC A/85)."
check has "$TMP/out.txt" "!! Integrated loudness is -20.0 LUFS; the spec wants -24 +/- 2 (too loud by 4.0 LU)."
check test "$(cat "$TMP/rc")" = 1
mjz "mj qc '$TMP/good.mov' broadcast-us"
check has "$TMP/out.txt" "good.mov passes for US broadcast (ATSC A/85)."
check test "$(cat "$TMP/rc")" = 0
mjz "mj config set qc_spec '$TMP/custom.mjspec' >/dev/null; mj qc '$TMP/good.mov'"
check has "$TMP/out.txt" "passes for House master"
mjz "mj config set qc_spec cinema"
check test "$(cat "$TMP/rc")" = 64

# The meter against ffmpeg's EBU R128 meter, when ffmpeg is installed (macOS CI installs it).
if command -v ffmpeg >/dev/null 2>&1; then
  ffmpeg -loglevel error -y -f lavfi -i "anoisesrc=color=pink:amplitude=0.3:duration=20:sample_rate=48000" -f lavfi -i "anoisesrc=color=brown:amplitude=0.02:duration=10:sample_rate=48000" \
    -filter_complex "[0][1]concat=n=2:v=0:a=1,aformat=channel_layouts=stereo" -c:a pcm_f32le "$TMP/noise.wav"
  REF=$(ffmpeg -nostats -hide_banner -i "$TMP/noise.wav" -af ebur128 -f null - 2>&1 | grep -A1 "Integrated loudness" | awk '/I:/ {print $2}')
  MINE=$( { echo 'import json, os, re, shutil, sys'; echo 'def err(c, m): sys.exit(m)'; sed -n "/^IFS= read -r -d '' MJ_PY_QC/,/^PY_QC_LIB/p" "$ROOT/src/modules/deliver.zsh" | sed '1d;$d'; echo "print(loudness('$TMP/noise.wav')['integrated'])"; } | python3 - )
  check python3 -c "import sys; assert abs(float('$REF') - float('$MINE')) <= 0.1, ('$REF', '$MINE')"
fi

echo "QC tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
