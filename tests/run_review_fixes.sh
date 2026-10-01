#!/usr/bin/env bash
# Regression tests for the 2026-09-30 review findings (GitHub issues). One section per issue.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
export MJ_STORE_DIR="$TMP/store" MJ_AUDIT_DIR="$TMP/noaudit"
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

# ---- #6: the shared base64 helper never wraps ----
LONG=$(printf 'x%.0s' $(seq 1 200))
check test "$(zsh -f -c "source '$ROOT/scripts/shell/mj-terminal.zsh'; _mj_b64 '$LONG'" | wc -l | tr -d ' ')" = 0
check test "$(zsh -f -c "source '$ROOT/scripts/shell/mj-terminal.zsh'; _mj_b64 '$LONG'" | base64 -d 2>/dev/null || zsh -f -c "source '$ROOT/scripts/shell/mj-terminal.zsh'; _mj_b64 '$LONG'" | base64 -D)" = "$LONG"

# ---- #11: volume.inspect checks its tools ----
check grep -q 'cap_available df && cap_available awk && cap_available uname' "$ROOT/src/modules/volume.zsh"
run "$TMP/vi.json" volume.inspect "path=$TMP"
check jq -e '.ok==true and .data.available==true and (.data.filesystem|type)=="string"' "$TMP/vi.json"

# ---- #17: warnings are real ----
run "$TMP/w0.json" system.probe
check jq -e '.warnings==[]' "$TMP/w0.json"
# plugin.audit over the entry bound
mkdir -p "$TMP/plug"; for i in $(seq 1 505); do : > "$TMP/plug/p$(printf '%04d' $i).plugin"; done
run "$TMP/w1.json" plugin.audit "path=$TMP/plug"
check jq -e '.ok==true and .data.truncated==true and ([.warnings[].code]|index("ENTRY_LIMIT_REACHED")!=null)' "$TMP/w1.json"
# a truncated / incomplete scrape
cat > "$TMP/scrape.json" <<J
{"schema":"MJ_PROJECT_SCRAPE_1","scraperVersion":"1.0","projectPath":"$TMP/p.aep","projectName":"p.aep","scrapedAt":"2026-10-01T00:00:00Z","aeVersion":"24.0","numItems":3,
 "compsTruncated":true,"footageTruncated":true,"fonts":[],
 "footage":[{"name":"gone.mov","path":"$TMP/gone.mov","missing":true,"hasVideo":true,"hasAudio":false}],
 "comps":[{"name":"M","id":1,"width":10,"height":10,"pixelAspect":1,"frameRate":24,"duration":1,"numLayers":1,"layersTruncated":true,"layers":[
   {"name":"L","index":1,"type":"AVLayer","sourceName":"gone.mov","sourcePath":"$TMP/gone.mov","effects":[],"expressions":[]}]}]}
J
run "$TMP/w2.json" project.ingest "path=$TMP/scrape.json"
check jq -e '[.warnings[].code]|sort==["COMPS_TRUNCATED","FOOTAGE_MISSING","FOOTAGE_TRUNCATED","LAYERS_TRUNCATED"]' "$TMP/w2.json"
check jq -e '.data|has("_warnings")|not' "$TMP/w2.json"                      # the reserved key never leaks into data
run "$TMP/w3.json" deps.graph "path=$TMP/scrape.json"
check jq -e '[.warnings[].code]|index("MISSING_FOOTAGE")!=null' "$TMP/w3.json"
printf 'aep' > "$TMP/p.aep"; mkdir -p "$TMP/out"
run "$TMP/w4.json" handoff.package "path=$TMP/p.aep" "input=$TMP/scrape.json" "output=$TMP/out" "label=hh"
check jq -e '[.warnings[].code]|index("MISSING_FOOTAGE")!=null' "$TMP/w4.json"
# index warnings
mkdir -p "$TMP/rc"; cp "$TMP/scrape.json" "$TMP/rc/a.json"
run "$TMP/w5.json" index.add "path=$TMP/rc"
check jq -e '.ok==true and .warnings==[]' "$TMP/w5.json"
rm "$TMP/rc/a.json"
run "$TMP/w6.json" index.verify
check jq -e '[.warnings[].code]|index("STALE_RECEIPTS")!=null' "$TMP/w6.json"
run "$TMP/w7.json" audit.plugins "maxResults=1"
check jq -e '.ok==true' "$TMP/w7.json"
# frames: extra frame in a golden check
mkdir -p "$TMP/fr" "$TMP/g"
python3 - "$TMP/fr" <<'PY'
import struct, sys, zlib, os
def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
for i in range(3):
    open(os.path.join(sys.argv[1], "f%d.png" % i), "wb").write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 4, 4, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress((b'\x00' + bytes([i * 50, 0, 0]) * 4) * 4)) + chunk(b'IEND', b''))
PY
run "$TMP/w8.json" golden.record "path=$TMP/fr" "output=$TMP/g" "label=gg"
cp "$TMP/fr/f0.png" "$TMP/fr/f9.png"
run "$TMP/w9.json" golden.check "path=$TMP/fr" "input=$TMP/g/gg.golden.json"
check jq -e '[.warnings[].code]|index("EXTRA_FRAMES")!=null' "$TMP/w9.json"
# warnings have the documented shape everywhere they appear
check jq -e '[.warnings[] | (.code|type)=="string" and (.message|type)=="string" and (.message|length)>0] | all' "$TMP/w2.json" "$TMP/w4.json" "$TMP/w9.json"

# ---- #19: plugin.audit does not hash enormous files ----
mkdir -p "$TMP/plug2"; head -c 4096 /dev/zero > "$TMP/plug2/small.bin"; head -c 300000 /dev/zero > "$TMP/plug2/big.bin"
MJ_TEST_PLUGIN_FILE_LIMIT=100000 run "$TMP/b1.json" plugin.audit "path=$TMP/plug2"
check jq -e '[.data.entries[] | select(.name=="big.bin") | .sha256] == [null]' "$TMP/b1.json"
check jq -e '[.data.entries[] | select(.name=="small.bin") | .sha256|type] == ["string"]' "$TMP/b1.json"
check jq -e '.data.entries[] | select(.name=="big.bin") | .sizeBytes==300000' "$TMP/b1.json"
check jq -e '[.warnings[].code]|index("FILE_TOO_LARGE_TO_HASH")!=null' "$TMP/b1.json"
run "$TMP/b2.json" plugin.audit "path=$TMP/plug2"                                   # default bound: both hashed, no warning
check jq -e '[.data.entries[].sha256|type]==["string","string"] and .warnings==[]' "$TMP/b2.json"
check bash -c "! grep -q 'MJ_TEST_PLUGIN_FILE_LIMIT' '$ROOT/dist/mograph-jailed.zsh'"   # the knob exists in the test bundle only

# ---- #18: image stats/compare emit valid JSON (needs sips, so macOS only) ----
if [ -x /usr/bin/sips ]; then
  cp "$TMP/fr/f0.png" "$TMP/s.png"
  run "$TMP/i1.json" image.stats "path=$TMP/s.png"
  check jq -e '.ok==true and (.data.pixelWidth|type)=="number" and (.data.histogram|length)==64 and (.data.gridAverages|length)==64' "$TMP/i1.json"
  run "$TMP/i2.json" image.compare "pathA=$TMP/fr/f0.png" "pathB=$TMP/fr/f2.png"
  check jq -e '.ok==true and (.data.score|type)=="number" and .data.score>=0 and .data.score<=1' "$TMP/i2.json"
fi
check bash -c "! grep -q 'pixelWidth\":%s.*_width' '$ROOT/src/modules/image.zsh' || grep -q 'Validate the engine' '$ROOT/src/modules/image.zsh'"

echo "Review-fix regression tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
