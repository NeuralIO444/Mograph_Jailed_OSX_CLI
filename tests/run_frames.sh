#!/usr/bin/env bash
# Phase 5/6 portable tests: loop.seams, golden.record, golden.check.
# Synthetic PNG sequences; sips downscale is optional so this runs on Linux too.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
b64(){ printf '%s' "$1" | base64 | tr -d '\n'; }
run(){
  local _out="$1" _cmd="$2"; shift 2
  local _f="$TMP/req_$RANDOM$RANDOM.txt"
  { printf 'MOGRAPHJAILED_REQUEST 1\nrequestId=t%s\ncommand=%s\n' "$RANDOM" "$_cmd"
    for _a in "$@"; do printf 'arg.%s=%s\n' "${_a%%=*}" "$(b64 "${_a#*=}")"; done; } > "$_f"
  "$CLI" --request "$_f" > "$_out" 2>/dev/null || true
}

# 24-frame loop: brightness ramps up then down, so frame 0 ~ frame 24 would close the loop;
# frames 0 and 23 are near-identical (period 24). An 8-bit and a 16-bit sequence.
mkdir -p "$TMP/seq" "$TMP/seq16" "$TMP/golden"
python3 - "$TMP" <<'PY'
import struct, zlib, os, sys
tmp = sys.argv[1]
def png(path, w, h, rgb, depth=8):
    raw = b''
    for y in range(h):
        raw += b'\x00'
        for x in range(w):
            r, g, b = rgb(x, y)
            raw += bytes([r, g, b]) if depth == 8 else struct.pack('>HHH', r * 257, g * 257, b * 257)
    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, depth, 2, 0, 0, 0))
                + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))
for i in range(24):
    v = int(255 * (i if i <= 12 else 24 - i) / 12)
    png(os.path.join(tmp, "seq", "f%04d.png" % i), 16, 16, lambda x, y: (v, (x * 16) % 256, 255 - v))
for i in range(4):
    png(os.path.join(tmp, "seq16", "f%04d.png" % i), 8, 8, lambda x, y: (i * 60, 0, 0), depth=16)
PY

# registry
run "$TMP/describe.json" system.describe
for op in loop.seams golden.record golden.check; do
  check jq -e --arg op "$op" '.data.operations[$op].executionScope=="LOCAL_ONLY" and .data.operations[$op].requires.all==["python3"]' "$TMP/describe.json"
done
check jq -e '.data.operations["golden.record"].mutation=="DERIVATIVE_CREATE"' "$TMP/describe.json"

# loop.seams: best seam with minFrames 12 is start 0 / end 23-ish region (v symmetric) — score near 1
run "$TMP/ls.json" loop.seams "path=$TMP/seq" "minFrames=12" "maxResults=3"
check jq -e '.ok==true and .data.schema=="MJ_LOOP_SEAMS_1" and .data.frameCount==24 and (.data.candidates|length)==3' "$TMP/ls.json"
check jq -e '.data.candidates[0].score >= .data.candidates[1].score and .data.candidates[0].lengthFrames >= 12' "$TMP/ls.json"
check jq -e '.data.candidates[0].score > 0.95' "$TMP/ls.json"
# near-duplicate suppression: no two candidates within 2 frames on both ends
check jq -e '[.data.candidates as $c | range(0;$c|length) as $i | range($i+1;$c|length) as $j
  | (($c[$i].startFrame-$c[$j].startFrame)|fabs) <= 2 and (($c[$i].endFrame-$c[$j].endFrame)|fabs) <= 2] | any | not' "$TMP/ls.json"
run "$TMP/ls16.json" loop.seams "path=$TMP/seq16" "minFrames=2"
check jq -e '.ok==true and .data.frameCount==4' "$TMP/ls16.json"
# validation
run "$TMP/e1.json" loop.seams "path=relative/dir"
check jq -e '.error.code=="INVALID_PATH"' "$TMP/e1.json"
run "$TMP/e2.json" loop.seams "path=$TMP/seq" "minFrames=24"
check jq -e '.error.code=="INVALID_ARGUMENT"' "$TMP/e2.json"
run "$TMP/e3.json" loop.seams "path=$TMP/seq" "maxResults=abc"
check jq -e '.error.code=="INVALID_ARGUMENT"' "$TMP/e3.json"
mkdir "$TMP/empty"
run "$TMP/e4.json" loop.seams "path=$TMP/empty"
check jq -e '.error.code=="INSUFFICIENT_FRAMES"' "$TMP/e4.json"
printf 'junk' > "$TMP/empty/bad.png"; cp "$TMP/seq/f0000.png" "$TMP/seq/f0001.png" "$TMP/empty/"
run "$TMP/e5.json" loop.seams "path=$TMP/empty"
check jq -e '.ok==false and .error.code=="DECODE_FAILED"' "$TMP/e5.json"

# golden.record: creates receipt, refuses overwrite, rejects bad labels
SEQ_SUM=$(cat "$TMP"/seq/*.png | cksum)
run "$TMP/gr.json" golden.record "path=$TMP/seq" "output=$TMP/golden" "label=hero_v1"
check jq -e '.ok==true and .data.frameCount==24' "$TMP/gr.json"
check jq -e '.schema=="MJ_GOLDEN_1" and (.frames|length)==24 and (.frames[0].sha256|length)==64' "$TMP/golden/hero_v1.golden.json"
G_SUM=$(cksum < "$TMP/golden/hero_v1.golden.json")
run "$TMP/gr2.json" golden.record "path=$TMP/seq" "output=$TMP/golden" "label=hero_v1"
check jq -e '.error.code=="OUTPUT_EXISTS"' "$TMP/gr2.json"
check test "$(cksum < "$TMP/golden/hero_v1.golden.json")" = "$G_SUM"
run "$TMP/gr3.json" golden.record "path=$TMP/seq" "output=$TMP/golden" "label=../evil"
check jq -e '.error.code=="INVALID_ARGUMENT"' "$TMP/gr3.json"
check test ! -e "$TMP/evil.golden.json"

# golden.check: identical -> pass; altered frame -> changed; removed -> missing; new -> extra
run "$TMP/gc.json" golden.check "path=$TMP/seq" "input=$TMP/golden/hero_v1.golden.json"
check jq -e '.ok==true and .data.passed==true and .data.framesFailed==0 and ([.data.frames[].status]|unique)==["identical"]' "$TMP/gc.json"
cp -R "$TMP/seq" "$TMP/seq2"
cp "$TMP/seq/f0012.png" "$TMP/seq2/f0000.png"     # very different frame
rm "$TMP/seq2/f0005.png"
cp "$TMP/seq/f0001.png" "$TMP/seq2/zz_extra.png"
run "$TMP/gc2.json" golden.check "path=$TMP/seq2" "input=$TMP/golden/hero_v1.golden.json"
check jq -e '.data.passed==false and .data.framesFailed==2' "$TMP/gc2.json"
check jq -e '(.data.frames[]|select(.name=="f0000.png").status)=="changed"' "$TMP/gc2.json"
check jq -e '(.data.frames[]|select(.name=="f0005.png").status)=="missing"' "$TMP/gc2.json"
check jq -e '.data.extraFrames==["zz_extra.png"]' "$TMP/gc2.json"
# a loose threshold forgives the changed frame
run "$TMP/gc3.json" golden.check "path=$TMP/seq2" "input=$TMP/golden/hero_v1.golden.json" "threshold=0"
check jq -e '(.data.frames[]|select(.name=="f0000.png").status)=="pass" and .data.framesFailed==1' "$TMP/gc3.json"
run "$TMP/gc4.json" golden.check "path=$TMP/seq" "input=$TMP/golden/hero_v1.golden.json" "threshold=2"
check jq -e '.error.code=="INVALID_ARGUMENT"' "$TMP/gc4.json"
run "$TMP/gc5.json" golden.check "path=$TMP/seq" "input=$TMP/seq/f0000.png"
check jq -e '.error.code=="INVALID_RECEIPT"' "$TMP/gc5.json"

# sources never mutated
check test "$(cat "$TMP"/seq/*.png | cksum)" = "$SEQ_SUM"

echo "Frames (loop.seams/golden) tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
