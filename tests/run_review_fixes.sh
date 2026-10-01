#!/usr/bin/env bash
# Regression tests for the 2026-09-30 review findings (GitHub issues). One section per issue.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/tmpd"; export TMPDIR="$TMP/tmpd"          # private temp folder: counts below cannot be disturbed by anything else
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

# ---- #14: watcher logs real outcomes, avoids request collisions, sees .AEP ----
render_watcher(){ # render_watcher <watch dir> <versions dir> <cli> -> path of rendered script
  mkdir -p "$2"
  sed -e "s|__WATCH_DIR__|$1|g" -e "s|__VERSIONS_DIR__|$2|g" -e "s|__CLI_PATH__|$3|g" "$ROOT/watcher/watch-fire.zsh" > "$2/fire.zsh"; echo "$2/fire.zsh"
}
mkdir -p "$TMP/w/watch/sub"
printf 'lower-bytes' > "$TMP/w/watch/a.aep"
printf 'upper-bytes' > "$TMP/w/watch/sub/B.AEP"
FIRE=$(render_watcher "$TMP/w/watch" "$TMP/w/versions" "$CLI")
zsh -f "$FIRE"
LOG="$TMP/w/versions/watcher.log"
check grep -q 'snapshot ok: .*/a.aep' "$LOG"
check grep -q 'snapshot ok: .*/B.AEP' "$LOG"                 # uppercase extension is seen
check test "$(ls "$TMP"/w/versions/B.*.aep 2>/dev/null | wc -l | tr -d ' ')" = 1
zsh -f "$FIRE"
check grep -q 'unchanged, skipped: .*/a.aep' "$LOG"
# failures carry the receipt's error code
cat > "$TMP/w/failcli.sh" <<'STUB'
#!/bin/sh
echo '{"ok":false,"error":{"code":"OUTPUT_UNAVAILABLE","message":"x"}}'; exit 73
STUB
chmod +x "$TMP/w/failcli.sh"
FIRE2=$(render_watcher "$TMP/w/watch" "$TMP/w/v2" "$TMP/w/failcli.sh")
zsh -f "$FIRE2"
check grep -q 'snapshot FAILED (OUTPUT_UNAVAILABLE) (continuing): .*/a.aep' "$TMP/w/v2/watcher.log"
cat > "$TMP/w/unstable.sh" <<'STUB'
#!/bin/sh
echo '{"ok":false,"error":{"code":"SNAPSHOT_UNSTABLE","message":"x"}}'; exit 74
STUB
chmod +x "$TMP/w/unstable.sh"
FIRE3=$(render_watcher "$TMP/w/watch" "$TMP/w/v3" "$TMP/w/unstable.sh")
zsh -f "$FIRE3"
check grep -q 'busy, project was changing' "$TMP/w/v3/watcher.log"
# overlapping runs in the same second each get their own request file and leave none behind
cat > "$TMP/w/slowcli.sh" <<STUB
#!/bin/sh
sleep 1
exec "$CLI" "\$@"
STUB
chmod +x "$TMP/w/slowcli.sh"
FIRE4=$(render_watcher "$TMP/w/watch" "$TMP/w/v4" "$TMP/w/slowcli.sh")
for i in 1 2 3 4; do zsh -f "$FIRE4" & done; wait
check test "$(grep -c 'snapshot FAILED' "$TMP/w/v4/watcher.log" || true)" = 0
check test "$(ls -A "$TMP/w/v4/.watcher" | wc -l | tr -d ' ')" = 0
check test "$(ls "$TMP"/w/v4/a.*.aep | wc -l | tr -d ' ')" -ge 1
check bash -c "! grep -q 'req-\$(date' '$ROOT/watcher/watch-fire.zsh'"

# ---- #16 / #25: dashboard caches the receipt ingest and has a JSON mode ----
mkdir -p "$TMP/d/versions" "$TMP/d/receipts" "$TMP/d/proj"
printf 'dash-bytes' > "$TMP/d/proj/Dash.aep"
run "$TMP/ds.json" project.snapshot "path=$TMP/d/proj/Dash.aep" "output=$TMP/d/versions"
sed "s|\$TMP|$TMP|g" "$TMP/scrape.json" > "$TMP/d/receipts/Dash.20261001T000000Z.scrape.json"
"$ROOT/tools/mj-observe-dash.zsh" --versions "$TMP/d/versions" --receipts "$TMP/d/receipts" --cli "$CLI" --json > "$TMP/dash.json" 2>/dev/null
check jq -e '.schema=="MJ_OBSERVE_DASH_1" and (.generatedAt|test("^20")) and (.projects|length)==1 and (.projects[0].project_path|endswith("Dash.aep"))' "$TMP/dash.json"
check jq -e '.summary.schema=="MJ_PROJECT_SUMMARY_1" and .lint.schema=="MJ_EXPRESSION_LINT_1" and .receipt=="Dash.20261001T000000Z.scrape.json"' "$TMP/dash.json"
check jq -e '.watcher|has("loaded") and has("tail")' "$TMP/dash.json"
check jq -e '.ingestCalls==1' "$TMP/dash.json"
"$ROOT/tools/mj-observe-dash.zsh" --versions "$TMP/d/versions" --receipts "$TMP/d/receipts" --cli "$CLI" --json --ticks 5 > "$TMP/dash5.json" 2>/dev/null
check jq -e '.ingestCalls==1 and .summary.schema=="MJ_PROJECT_SUMMARY_1"' "$TMP/dash5.json"      # 5 refreshes, 1 ingest
# a broken receipt is also cached (not re-parsed every tick) and surfaces its error code
printf 'not json' > "$TMP/d/receipts/Dash.20261002T000000Z.scrape.json"
"$ROOT/tools/mj-observe-dash.zsh" --versions "$TMP/d/versions" --receipts "$TMP/d/receipts" --cli "$CLI" --json --ticks 5 > "$TMP/dashbad.json" 2>/dev/null
check jq -e '.ingestCalls==1 and (.receipt_error|type)=="string" and (.summary|not)' "$TMP/dashbad.json"
# no receipts: nothing is ingested
"$ROOT/tools/mj-observe-dash.zsh" --versions "$TMP/d/versions" --cli "$CLI" --json --ticks 3 > "$TMP/dashnone.json" 2>/dev/null
check jq -e '.ingestCalls==0 and (.summary|not)' "$TMP/dashnone.json"
# --json implies a single frame: no escape codes, valid JSON only
check bash -c "! grep -q $'\\x1b' '$TMP/dash.json'"

# ---- #21: --request - reads standard input ----
printf stable > "$TMP/stable.txt"
printf 'MOGRAPHJAILED_REQUEST 1\nrequestId=stdin1\ncommand=file.inspect\narg.path=%s\n' "$(b64 "$TMP/stable.txt")" > "$TMP/in.req"
"$CLI" --request "$TMP/in.req" > "$TMP/si_file.json" 2>/dev/null || true
"$CLI" --request - < "$TMP/in.req" > "$TMP/si_stdin.json" 2>/dev/null || true
check cmp -s "$TMP/si_file.json" "$TMP/si_stdin.json"
check jq -e '.ok==true and .requestId=="stdin1"' "$TMP/si_stdin.json"
cat "$TMP/in.req" | "$CLI" --request - > "$TMP/si_pipe.json" 2>/dev/null || true
check cmp -s "$TMP/si_file.json" "$TMP/si_pipe.json"
printf '' | "$CLI" --request - > "$TMP/si_empty.json" 2>/dev/null || rc=$?
check jq -e '.ok==false' "$TMP/si_empty.json"
head -c 400000 /dev/zero | tr '\0' 'a' 2>/dev/null | "$CLI" --request - > "$TMP/si_big.json" 2>/dev/null || true
check jq -e '.error.code=="REQUEST_TOO_LARGE"' "$TMP/si_big.json"
check test "$(ls "$TMPDIR" | grep -c 'mj-stdin-request' || true)" = 0                    # no temp file left behind
# F11 (QA): killed while waiting for input, the temp file is still removed
mkfifo "$TMP/sig.fifo"
"$CLI" --request - < "$TMP/sig.fifo" > "$TMP/sig.out" 2>&1 &
SIGPID=$!
exec 9> "$TMP/sig.fifo"                                                                   # hold the writer open: the reader blocks
for _ in $(seq 1 50); do ls "$TMPDIR" | grep -q 'mj-stdin-request' && break; sleep 0.1; done
check bash -c "ls '$TMPDIR' | grep -q 'mj-stdin-request'"                                  # the temp file exists while blocked
kill -TERM $SIGPID; wait $SIGPID 2>/dev/null || true
exec 9>&-
sleep 0.3
check test "$(ls "$TMPDIR" | grep -c 'mj-stdin-request' || true)" = 0

"$CLI" --request - extra < "$TMP/in.req" > "$TMP/si_bad.json" 2>/dev/null || rc=$?
check jq -e '.error.code=="USAGE"' "$TMP/si_bad.json"

# ---- #23: system.doctor explains what is missing and what it blocks ----
printf 'MOGRAPHJAILED_REQUEST 1\nrequestId=doc\ncommand=system.doctor\n' > "$TMP/doc.req"
"$CLI" --request "$TMP/doc.req" > "$TMP/dr0.json" 2>/dev/null
# The baseline depends on the machine (a Linux runner genuinely lacks sips, xattr, ...), so test relations, not absolutes.
check jq -e '.ok==true and .data.operations.total>=44 and (.data.guidance|type)=="array"' "$TMP/dr0.json"
check jq -e '(.data.operations.unavailable==0) == (.data.guidance==[])' "$TMP/dr0.json"      # unavailable operations <=> guidance entries
check jq -e '[.data.guidance[] | (.unlocks|length)>0 and (.hint|length)>40] | all' "$TMP/dr0.json"
MJ_TEST_MISSING_CAPS="python3 sips" "$CLI" --request "$TMP/doc.req" > "$TMP/dr1.json" 2>/dev/null
check jq -e '[.data.guidance[].capability] | (index("python3")!=null) and (index("sips")!=null)' "$TMP/dr1.json"
check jq -e '(.data.guidance[]|select(.capability=="python3")|.unlocks) | index("project.ingest")!=null and index("loop.seams")!=null and index("ae.render")!=null' "$TMP/dr1.json"
check jq -e '(.data.guidance[]|select(.capability=="sips")|.unlocks) | index("image.inspect")!=null' "$TMP/dr1.json"
check jq -e '[.data.guidance[] | (.hint|length)>40] | all' "$TMP/dr1.json"
check jq -e '.data.operations.unavailable>=20 and .data.operations.unavailable<.data.operations.total and .data.operations.unavailable>'"$(jq '.data.operations.unavailable' "$TMP/dr0.json")"'' "$TMP/dr1.json"
MJ_TEST_MISSING_CAPS="shasum sha256" "$CLI" --request "$TMP/doc.req" > "$TMP/dr2.json" 2>/dev/null
check jq -e '[.data.guidance[].capability]|index("sha256 or shasum")!=null' "$TMP/dr2.json"
MJ_TEST_MISSING_CAPS="sha256" "$CLI" --request "$TMP/doc.req" > "$TMP/dr3.json" 2>/dev/null     # one hasher is enough
check jq -e '[.data.guidance[].capability] | index("sha256 or shasum")==null' "$TMP/dr3.json"
# the doctor itself needs nothing optional: it still answers when python3 is "missing"
check jq -e '.ok==true and .data.ready!=null' "$TMP/dr1.json"
# #11, now dynamic: a missing df is refused, not reported as available
printf 'MOGRAPHJAILED_REQUEST 1\nrequestId=v\ncommand=volume.inspect\narg.path=%s\n' "$(b64 "$TMP")" > "$TMP/vol.req"
MJ_TEST_MISSING_CAPS="df" "$CLI" --request "$TMP/vol.req" > "$TMP/vi2.json" 2>/dev/null || true
check jq -e '.ok==false and .error.code=="UNSUPPORTED"' "$TMP/vi2.json"

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
