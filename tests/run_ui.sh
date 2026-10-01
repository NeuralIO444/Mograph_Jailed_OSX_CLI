#!/usr/bin/env bash
# Terminal UI: launch screen and dashboard (scripts/terminal/mj_ui.py).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
UI="$ROOT/scripts/terminal/mj_ui.py"
TMP=$(mktemp -d)
TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
export MJ_CLI="$CLI" MJ_STORE_DIR="$TMP/store" MJ_AUDIT_DIR="$TMP/audit" MJ_TEST_APPS_DIR="$TMP/apps"
unset NO_COLOR MJ_PLAIN MJ_ASCII MJ_NO_ANIM
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
maxw(){ python3 -c "import re,sys; print(max(len(re.sub(r'\x1b\[[0-9;?]*[A-Za-z]','',l.rstrip('\n'))) for l in sys.stdin))"; }

# --- fake hosts ---
A="$TMP/apps"; mkdir -p "$A/Adobe After Effects 2026/Adobe After Effects 2026.app/Contents" "$A/Maxon Cinema 4D 2026/Cinema 4D.app/Contents" "$A/Maxon Cinema 4D 2026/Commandline.app/Contents/MacOS" "$A/Maxon Cinema 4D 2026/corelibs"
printf '<plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>26.5.0</string></dict></plist>' > "$A/Adobe After Effects 2026/Adobe After Effects 2026.app/Contents/Info.plist"
printf '<plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>2026.3</string></dict></plist>' > "$A/Maxon Cinema 4D 2026/Cinema 4D.app/Contents/Info.plist"
printf '#!/bin/sh\n' > "$A/Adobe After Effects 2026/aerender"; printf '#!/bin/sh\n' > "$A/Maxon Cinema 4D 2026/Commandline.app/Contents/MacOS/Commandline"
chmod +x "$A/Adobe After Effects 2026/aerender" "$A/Maxon Cinema 4D 2026/Commandline.app/Contents/MacOS/Commandline"
touch "$A/Maxon Cinema 4D 2026/corelibs/redshift.xlib"

# --- empty machine ---
python3 "$UI" home --plain --width 90 > "$TMP/h0.txt"
check grep -q 'M O G R A P H' "$TMP/h0.txt"
check grep -Eq 'runtime +0\.[0-9a-z.-]+ . 44 operations' "$TMP/h0.txt"
check grep -Eq 'after effects +2026 \(26\.5\.0\)' "$TMP/h0.txt"
check grep -Eq 'cinema 4d +2026 \(2026\.3\) +redshift' "$TMP/h0.txt"
check grep -q 'library .*empty.*mj index.add' "$TMP/h0.txt"
check grep -q 'audit log .*off.*mkdir' "$TMP/h0.txt"
check grep -q 'last render .*none yet' "$TMP/h0.txt"
check grep -q 'mj ui' "$TMP/h0.txt"
check test ! -e "$TMP/store" -a ! -e "$TMP/audit"       # looking creates nothing

# --- populated machine ---
mkdir -p "$TMP/r" "$TMP/audit"
cat > "$TMP/r/a.scrape.json" <<'J'
{"schema":"MJ_PROJECT_SCRAPE_1","projectName":"hero.aep","projectPath":"/p/hero.aep","scrapedAt":"2026-10-01T10:00:00Z","aeVersion":"26.5.0","fonts":["Inter"],
 "footage":[{"id":1,"name":"bg.mov","path":"/p/bg.mov","missing":false}],
 "comps":[{"id":1,"name":"Main","layers":[{"index":1,"name":"FX","type":"AVLayer","sourceName":"","sourcePath":"","sourceId":0,"effects":[{"name":"Glow","matchName":"ADBE Glo2"}]}]}]}
J
run "$TMP/i.json" index.add "path=$TMP/r"
printf 'x' > "$TMP/p.ffx"; run "$TMP/p.json" preset.add "path=$TMP/p.ffx" "label=glow"
for c in system.probe system.probe system.describe; do run "$TMP/x.json" $c; done
python3 - "$TMP/store/renders.jsonl" <<'PY'
import json, sys, time
rows = [{"endedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 3600 * (6 - i))), "host": "cinema4d" if i % 2 else "afterEffects",
         "status": "complete" if i != 3 else "incomplete", "label": "shot%d.20261001T1%d0000Z" % (i, i), "frames": 100 + i, "expected": 100 + i if i != 3 else 120,
         "seconds": 30 + i * 7.5, "receiptPath": "/x"} for i in range(6)]
open(sys.argv[1], "w").write("".join(json.dumps(r) + "\n" for r in rows))
PY
python3 "$UI" ui --once --plain --width 100 --tab overview > "$TMP/o.txt"
check grep -Eq '1 projects . [0-9]+ entries . 1 presets . healthy' "$TMP/o.txt"
check grep -Eq 'chain intact . [0-9]+ entries . head [0-9a-f]{8}' "$TMP/o.txt"
check grep -Eq '(ae|c4d) . (complete|incomplete) . [0-9]+/?[0-9]* frames' "$TMP/o.txt"
check grep -q 'LAST RENDER' "$TMP/o.txt"
check bash -c "! grep -q $'\\x1b' '$TMP/o.txt'"        # plain mode: no escape bytes at all
python3 "$UI" ui --once --plain --width 100 --tab renders > "$TMP/rn.txt"
check grep -q 'RENDER HISTORY (6)' "$TMP/rn.txt"
check grep -Eq 'incomplete +[0-9]+/120' "$TMP/rn.txt"
python3 "$UI" ui --once --plain --width 100 --tab library > "$TMP/lb.txt"
check grep -Eq 'ADBE Glo2 +1 +1' "$TMP/lb.txt"
python3 "$UI" ui --once --plain --width 100 --tab audit > "$TMP/au.txt"
check grep -q 'RECENT REQUESTS' "$TMP/au.txt"
check grep -Eq 'system\.describe +0' "$TMP/au.txt"
# every tab, every width fits the terminal
for w in 60 80 100 120; do for tab in overview renders library audit; do
  check test "$(python3 "$UI" ui --once --plain --width $w --tab $tab | maxw)" -le $w
done; done
check test "$(python3 "$UI" home --plain --width 60 | maxw)" -le 60

# --- real terminal sessions (pty) ---
cat > "$TMP/ptydrive.py" <<'PY'
import os, pty, re, select, struct, sys, termios, fcntl, time
def session(args, env_extra, keys=b"", cols=100, rows=30, wait=4.0):
    env = dict(os.environ, **env_extra)
    pid, fd = pty.fork()
    if pid == 0:
        os.execvpe("/usr/bin/python3", ["python3"] + args, env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    out, start, sent = b"", time.time(), 0
    while time.time() - start < 40:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            try: d = os.read(fd, 65536)
            except OSError: break
            if not d: break
            out += d
        if keys and sent < len(keys) and time.time() - start > wait + sent * 0.4:
            os.write(fd, keys[sent:sent + 1]); sent += 1
    try: _, status = os.waitpid(pid, 0)
    except ChildProcessError: status = 0
    return out.decode("utf-8", "replace"), os.waitstatus_to_exitcode(status)
ui, mode = sys.argv[1], sys.argv[2]
base = {"TERM": "xterm-256color", "COLORTERM": "truecolor"}
ok = True
def need(cond, msg):
    global ok
    if not cond: print("PTY FAIL:", msg); ok = False
if mode == "home":
    txt, code = session([ui, "home"], base)
    need(code == 0, "home exits 0")
    need(txt.count("38;2;") > 100, "truecolor gradient present")
    need(txt.count("\x1b[?25l") == 1 and txt.count("\x1b[?25h") == 1, "cursor hidden then restored")
    need("runtime" in txt and "after effects" in txt, "status rows present")
    txt, code = session([ui, "home"], dict(base, NO_COLOR="1"))
    need("\x1b[38" not in txt and "\x1b[1m" not in txt, "NO_COLOR removes colour")
    txt, code = session([ui, "home"], dict(base, TERM="dumb"))
    need("\x1b[?25l" not in txt and "\x1b[38" not in txt, "dumb terminal gets no escapes")
    txt, code = session([ui, "home"], dict(base, COLORTERM="", TERM="xterm-256color"))
    need("38;5;" in txt and "38;2;" not in txt, "256-colour fallback")
elif mode == "progress":
    txt, code = session([ui, "ui"], base, keys=b"q", wait=3.0)
    need("MJ · rendering 35%" in txt, "terminal title shows render progress")
    need("42/120 frames" in txt, "progress text on the overview")
    need("\x1b]2;\x07" in txt, "title reset on exit")
else:
    txt, code = session([ui, "ui"], base, keys=b"3q")
    need(code == 0, "ui exits 0 after q")
    need(txt.count("\x1b[?1049h") == 1 and txt.count("\x1b[?1049l") == 1, "alt screen entered and left once")
    need(txt.rstrip().endswith("\x1b[?1049l") or txt.rstrip().endswith("\x1b[?25h"), "terminal restored last")
    need("TOP EFFECTS" in txt, "key 3 switched to the library tab")
    txt, code = session([ui, "ui"], base, keys=b"\t\t\x03")
    need(code in (0, 130), "ctrl-c leaves cleanly")
    need("\x1b[?1049l" in txt, "alt screen left after ctrl-c")
print("PTY OK" if ok else "PTY BAD")
sys.exit(0 if ok else 1)
PY
# --- live render progress ---
sleep 120 & LIVE=$!
mkdir -p "$TMP/store/locks/render.lock"; echo $LIVE > "$TMP/store/locks/render.lock/pid"
write_progress(){ python3 - "$TMP/store/render-progress.json" "$LIVE" "$1" "$2" <<'PY'
import json, sys
total = None if sys.argv[4] == "null" else int(sys.argv[4]); frames = int(sys.argv[3])
json.dump({"host": "afterEffects", "label": "shot_07", "outputDir": "/x", "pid": int(sys.argv[2]), "startedAt": "2026-10-01T00:00:00Z",
           "elapsed": 10.0, "frames": frames, "total": total, "percent": round(100.0 * frames / total, 1) if total else None,
           "fps": 4.2, "etaSeconds": 18 if total else None}, open(sys.argv[1], "w"))
PY
}
write_progress 42 120
python3 "$UI" ui --once --plain --width 100 --tab overview > "$TMP/pg.txt"
check grep -q 'shot_07 . 42/120 frames . 35% . 4.2 fps . eta 0:18' "$TMP/pg.txt"
check grep -Eq '#{5,}\.{5,} +35%' "$TMP/pg.txt"
python3 "$UI" ui --once --plain --width 100 --tab renders > "$TMP/pg2.txt"
check grep -q 'RENDERING' "$TMP/pg2.txt"
check test "$(python3 "$UI" status --plain)" = "MJ * rendering shot_07 35% eta 0:18"
check bash -c "python3 '$UI' status --plain --swiftbar | sed -n '2p' | grep -qx -- '---'"
check test "$(python3 "$UI" ui --once --plain --width 60 --tab overview | maxw)" -le 60
write_progress 9 null
python3 "$UI" ui --once --plain --width 100 --tab overview > "$TMP/pg3.txt"
check grep -q 'shot_07 . 9 frames . 4.2 fps . 0:10 elapsed' "$TMP/pg3.txt"           # no total: indeterminate
check test "$(python3 "$UI" status --plain)" = "MJ * rendering shot_07 9 frames eta --:--"
write_progress 42 120
# pty sessions see the progress, the title, and the pulsing marker
check bash -c "python3 '$TMP/ptydrive.py' '$UI' progress | tail -1 | grep -q 'PTY OK'"
kill $LIVE; wait $LIVE 2>/dev/null || true
# a stale progress file (render process gone) is ignored
python3 "$UI" ui --once --plain --width 100 --tab overview > "$TMP/pg4.txt"
check bash -c "! grep -q 'shot_07' '$TMP/pg4.txt'"
check bash -c "python3 '$UI' status --plain | grep -q 'MJ . last render'"
rm -rf "$TMP/store/locks" "$TMP/store/render-progress.json"

# --- a tampered audit log is shouted about ---
cp "$TMP/audit/audit.jsonl" "$TMP/audit.good"
python3 - "$TMP/audit/audit.jsonl" <<'PY'
import sys; p = sys.argv[1]; L = open(p).read().splitlines(True); L[1] = L[1].replace('"exitCode":0', '"exitCode":9'); open(p, "w").writelines(L)
PY
python3 "$UI" ui --once --plain --width 100 --tab audit > "$TMP/au2.txt"
check grep -q 'CHAIN BROKEN at line 3' "$TMP/au2.txt"
cp "$TMP/audit.good" "$TMP/audit/audit.jsonl"

# --- viewing is read-only ---
BEFORE=$(find "$TMP/store" "$TMP/audit" -type f -exec cksum {} + | sort)
python3 "$UI" home --plain >/dev/null; python3 "$UI" ui --once --plain >/dev/null
# (the runtime itself appends audit lines for the requests the UI makes)
check test "$(find "$TMP/store" -type f -exec cksum {} + | sort)" = "$(echo "$BEFORE" | grep "$TMP/store")"
check bash -c "python3 '$UI' ui --tab nope --once >/dev/null 2>&1; test \$? -eq 64"

check bash -c "python3 '$TMP/ptydrive.py' '$UI' home | tail -1 | grep -q 'PTY OK'"
check bash -c "python3 '$TMP/ptydrive.py' '$UI' ui | tail -1 | grep -q 'PTY OK'"

echo "Terminal UI tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
