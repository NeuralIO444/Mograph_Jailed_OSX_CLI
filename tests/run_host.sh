#!/usr/bin/env bash
# Phases 0-1: host.detect, ae.render, c4d.render against stub host binaries in a
# fake /Applications (test bundle only; production has no discovery override).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d)
TMP=$(cd "$TMP" && pwd -P)
trap 'pkill -f "$TMP/apps" 2>/dev/null || true; rm -rf "$TMP"' EXIT
export MJ_STORE_DIR="$TMP/store" MJ_TEST_APPS_DIR="$TMP/apps"
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
plist(){ mkdir -p "$1/Contents"; printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>%s</string></dict></plist>\n' "$2" > "$1/Contents/Info.plist"; }

# --- fake installs ---
A="$TMP/apps"
AE26="$A/Adobe After Effects 2026"
C4D="$A/Maxon Cinema 4D 2026"
mkdir -p "$AE26" "$A/Adobe After Effects 2023" "$A/Adobe After Effects 2025/Scripts" \
         "$C4D/corelibs" "$C4D/Commandline.app/Contents/MacOS" "$C4D/c4dpy.app/Contents/MacOS" "$A/Unrelated App"
plist "$AE26/Adobe After Effects 2026.app" 26.5.0
plist "$A/Adobe After Effects 2023/Adobe After Effects 2023.app" 23.6.0
plist "$C4D/Cinema 4D.app" 2026.3
touch "$C4D/corelibs/redshift.xlib"
cat > "$TMP/png.py" <<'PY'
import struct, sys, zlib
def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
v = int(sys.argv[2]) % 256
open(sys.argv[1], 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 4, 4, 8, 2, 0, 0, 0))
    + chunk(b'IDAT', zlib.compress((b'\x00' + bytes([v, 0, 0]) * 4) * 4)) + chunk(b'IEND', b''))
PY
# stub aerender: behaviour chosen by comp name
cat > "$AE26/aerender" <<STUB
#!/usr/bin/env bash
s=0; e=2
while [ \$# -gt 0 ]; do case "\$1" in
  -project) proj=\$2; shift;; -comp) comp=\$2; shift;; -output) out=\$2; shift;;
  -s) s=\$2; shift;; -e) e=\$2; shift;; esac; shift; done
case "\$comp" in
  Fail) echo "aerender ERROR: No comp was found with the given name."; exit 1;;
  Slow) echo "PROGRESS: starting"; sleep 60; exit 0;;
  Licence) echo "Enter the license method:"; echo "Please select:"; sleep 60;;
  Short) e=\$((e-1));;
  Prog) SLEEP=0.6;;
  Mutate) printf 'x' >> "\$proj";;
esac
for f in \$(seq \$s \$e); do
  python3 "$TMP/png.py" "\${out/\[#####\]/\$(printf '%05d' \$f)}" \$f
  echo "PROGRESS: frame \$f"
  [ -n "\${SLEEP:-}" ] && sleep \$SLEEP
done
echo "aerender version 26.5x89 Total Time Elapsed: 1 Seconds"
STUB
# stub C4D Commandline: frames named <prefix>NNNN.png
cat > "$C4D/Commandline.app/Contents/MacOS/Commandline" <<STUB
#!/usr/bin/env bash
s=0; e=1
while [ \$# -gt 0 ]; do case "\$1" in
  -render) scene=\$2; shift;; -oimage) img=\$2; shift;; -frame) s=\$2; e=\$3; shift 2;; esac; shift; done
case "\$scene" in *lic.c4d) echo "----"; echo "Enter the license method:"; sleep 60;; esac
for f in \$(seq \$s \$e); do python3 "$TMP/png.py" "\$img\$(printf '%04d' \$f).png" \$f; done
echo "Rendering successful"
STUB
cp "$C4D/Commandline.app/Contents/MacOS/Commandline" "$C4D/c4dpy.app/Contents/MacOS/c4dpy"
cp "$AE26/aerender" "$A/Adobe After Effects 2023/aerender"
chmod +x "$AE26/aerender" "$A/Adobe After Effects 2023/aerender" "$C4D/Commandline.app/Contents/MacOS/Commandline" "$C4D/c4dpy.app/Contents/MacOS/c4dpy"
mkdir -p "$TMP/proj" "$TMP/renders"
printf 'aep-bytes' > "$TMP/proj/hero.aep"; printf 'c4d-bytes' > "$TMP/proj/logo.c4d"; printf 'c4d' > "$TMP/proj/lic.c4d"

# --- host.detect ---
run "$TMP/d.json" host.detect
check jq -e '.ok==true and .data.schema=="MJ_HOST_DETECT_1" and .data.minimumYear==2024' "$TMP/d.json"
check jq -e '[.data.afterEffects[] | {year, complete, supported, version}] == [
  {"year":2023,"complete":true,"supported":false,"version":"23.6.0"},
  {"year":2025,"complete":false,"supported":false,"version":""},
  {"year":2026,"complete":true,"supported":true,"version":"26.5.0"}]' "$TMP/d.json"
check jq -e '.data.cinema4d[0] | .year==2026 and .version=="2026.3" and .redshift==true and .supported==true and (.c4dpy|type)=="string"' "$TMP/d.json"
check jq -e '.data.ready == {"aeRender":true,"c4dRender":true,"c4dHeadlessPython":true}' "$TMP/d.json"

# --- ae.render ---
run "$TMP/r1.json" ae.render "path=$TMP/proj/hero.aep" "target=Main" "output=$TMP/renders" "label=hero" "range=0-4"
check jq -e '.ok==true and .data.schema=="MJ_RENDER_1" and .data.status=="complete" and .data.hostYear==2026 and .data.frames.count==5 and .data.frames.expected==5' "$TMP/r1.json"
check jq -e '.data.source.unchanged==true and (.data.frames.firstSha256|length)==64' "$TMP/r1.json"
check jq -e '.data.argv | (index("-outputSettings") != null) and (index("DO_NOT_SAVE_CHANGES") != null) and (index("-reuse") == null)' "$TMP/r1.json"
J1=$(jq -r '.data.outputDir' "$TMP/r1.json")
check test -f "$J1/render.json" -a -f "$J1/render.log" -a -f "$J1/hero_00004.png"
check grep -q 'PROGRESS: frame 4' "$J1/render.log"
# rendered frames feed straight into the frame tools
run "$TMP/ls.json" loop.seams "path=$J1" "minFrames=2"
check jq -e '.ok==true and .data.frameCount==5' "$TMP/ls.json"
# a second render never reuses the folder
run "$TMP/r2.json" ae.render "path=$TMP/proj/hero.aep" "target=Main" "output=$TMP/renders" "label=hero"
check test "$(jq -r '.data.outputDir' "$TMP/r2.json")" != "$J1"
run "$TMP/r3.json" ae.render "path=$TMP/proj/hero.aep" "target=Fail" "output=$TMP/renders" "label=bad"
check jq -e '.error.code=="RENDER_FAILED" and (.error.message|test("render.json"))' "$TMP/r3.json"
check bash -c "grep -q 'No comp was found' '$TMP'/renders/bad.*/render.json"
run "$TMP/r4.json" ae.render "path=$TMP/proj/hero.aep" "target=Short" "output=$TMP/renders" "label=short" "range=0-4"
check jq -e '.error.code=="RENDER_INCOMPLETE"' "$TMP/r4.json"
run "$TMP/r5.json" ae.render "path=$TMP/proj/hero.aep" "target=Licence" "output=$TMP/renders" "label=lic"
check jq -e '.error.code=="LICENCE_NOT_CONFIGURED"' "$TMP/r5.json"
cp "$TMP/proj/hero.aep" "$TMP/proj/mut.aep"
run "$TMP/r6.json" ae.render "path=$TMP/proj/mut.aep" "target=Mutate" "output=$TMP/renders" "label=mut"
check jq -e '.data.status=="complete" and .data.source.unchanged==false' "$TMP/r6.json"
# validation
run "$TMP/v1.json" ae.render "path=$TMP/proj/logo.c4d" "target=Main" "output=$TMP/renders" "label=x"
check jq -e '.error.code=="INVALID_TARGET"' "$TMP/v1.json"
run "$TMP/v2.json" ae.render "path=$TMP/proj/hero.aep" "target=Main" "output=$TMP/renders" "label=x" "range=9-2"
check jq -e '.error.code=="INVALID_ARGUMENT"' "$TMP/v2.json"
run "$TMP/v3.json" ae.render "path=$TMP/proj/hero.aep" "target=Main" "output=$TMP/renders" "label=x" "version=2023"
check jq -e '.error.code=="INVALID_ARGUMENT"' "$TMP/v3.json"
run "$TMP/v4.json" ae.render "path=$TMP/proj/hero.aep" "target=Main" "output=$TMP/renders" "label=x" "version=2025"
check jq -e '.error.code=="HOST_NOT_FOUND"' "$TMP/v4.json"
run "$TMP/v5.json" ae.render "path=$TMP/proj/hero.aep" "output=$TMP/renders" "label=x"
check jq -e '.error.code=="MISSING_ARGUMENT"' "$TMP/v5.json"

# --- live progress: counted from finished frames, cleared when done ---
run "$TMP/prog.json" ae.render "path=$TMP/proj/hero.aep" "target=Prog" "output=$TMP/renders" "label=prog" "range=0-7" &
PROG=$!
SEEN=""
for i in $(seq 1 40); do
  if [ -f "$TMP/store/render-progress.json" ]; then
    SEEN="$SEEN $(jq -r '.frames' "$TMP/store/render-progress.json" 2>/dev/null)"
  fi
  kill -0 $PROG 2>/dev/null || break
  sleep 0.3
done
wait $PROG
check jq -e '.data.status=="complete" and .data.frames.count==8' "$TMP/prog.json"
check test "$(echo $SEEN | wc -w | tr -d ' ')" -ge 3
check python3 -c "import sys; v=[int(x) for x in sys.argv[1:] if x.isdigit()]; assert v==sorted(v) and v[0] < v[-1] <= 8, v" $SEEN
check test ! -e "$TMP/store/render-progress.json"
check bash -c "echo '$SEEN' | grep -q ' '"
# progress document shape (taken mid-run)
run "$TMP/prog2.json" ae.render "path=$TMP/proj/hero.aep" "target=Prog" "output=$TMP/renders" "label=prog2" "range=0-7" &
P2=$!
for i in $(seq 1 30); do [ -f "$TMP/store/render-progress.json" ] && jq -e '.frames>=2' "$TMP/store/render-progress.json" >/dev/null 2>&1 && break; sleep 0.2; done
cp "$TMP/store/render-progress.json" "$TMP/prog.mid.json" 2>/dev/null || true
wait $P2
check jq -e '.host=="afterEffects" and .total==8 and .percent>0 and .fps>0 and (.etaSeconds==null or (.etaSeconds|type)=="number") and (.pid|type)=="number" and (.label=="prog2")' "$TMP/prog.mid.json"

# --- one render at a time; timeout kills the whole process group ---
run "$TMP/slow.json" ae.render "path=$TMP/proj/hero.aep" "target=Slow" "output=$TMP/renders" "label=slow" "timeoutSeconds=10" &
SLOW=$!
sleep 2
run "$TMP/busy.json" c4d.render "path=$TMP/proj/logo.c4d" "output=$TMP/renders" "label=busy"
check jq -e '.error.code=="RENDER_BUSY"' "$TMP/busy.json"
wait $SLOW
check jq -e '.error.code=="RENDER_TIMEOUT"' "$TMP/slow.json"
# [a]pps: the pattern must not match this check's own command line
check bash -c "! pgrep -f '$TMP/[a]pps' >/dev/null"
check test ! -e "$TMP/store/locks/render.lock"
# a lock left by a dead process is reclaimed
mkdir -p "$TMP/store/locks/render.lock"; echo 999999 > "$TMP/store/locks/render.lock/pid"
run "$TMP/c1.json" c4d.render "path=$TMP/proj/logo.c4d" "output=$TMP/renders" "label=logo" "range=10-12" "target=Hero Take"
check jq -e '.ok==true and .data.host=="cinema4d" and .data.status=="complete" and .data.frames.count==3 and .data.redshiftInstalled==true' "$TMP/c1.json"
check jq -e '.data.argv[-2:]==["-take","Hero Take"] and .data.frames.first=="logo_0010.png"' "$TMP/c1.json"
run "$TMP/c2.json" c4d.render "path=$TMP/proj/lic.c4d" "output=$TMP/renders" "label=lic4d"
check jq -e '.error.code=="LICENCE_NOT_CONFIGURED"' "$TMP/c2.json"

# --- render history for the dashboard ---
check test "$(wc -l < "$TMP/store/renders.jsonl" | tr -d ' ')" -ge 8
check jq -se '[.[] | select(.host=="cinema4d" and .status=="complete")] | .[0] | .frames==3 and .expected==3 and (.label|startswith("logo."))' "$TMP/store/renders.jsonl"

# --- mj last: newest render receipt ---
check bash -c "MJ_CLI='$CLI' zsh -f -c \"source '$ROOT/scripts/shell/mj-cli.zsh'; mj last\" | jq -e '.host==\"cinema4d\" and .schema==\"MJ_RENDER_1\"' >/dev/null"

# --- sources untouched ---
check test "$(cat "$TMP/proj/hero.aep")" = "aep-bytes"
check test "$(cat "$TMP/proj/logo.c4d")" = "c4d-bytes"

echo "Host render tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
