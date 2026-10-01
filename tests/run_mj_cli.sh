#!/usr/bin/env bash
# Phase 10: mj front end (single ops, ops listing, recipes, completion data).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
# Run zsh code with mj loaded against the portable bundle.
mjz(){ MJ_CLI="$ROOT/dist/mograph-jailed-linux-test.sh" zsh -f -c "source '$ROOT/scripts/shell/mj-cli.zsh'; $1"; }

mkdir -p "$TMP/my frames"
printf 'x' > "$TMP/my frames/a file.txt"

# single operation, value with spaces
mjz "mj file.inspect 'path=$TMP/my frames/a file.txt'" > "$TMP/o1.json" || true
check jq -e --arg p "$TMP/my frames/a file.txt" '.ok==true and .data.path==$p' "$TMP/o1.json"
# runtime exit code propagates
set +e; mjz "mj file.inspect path=relative" > "$TMP/o2.json"; rc=$?; set -e
check test "$rc" -ne 0
check jq -e '.error.code=="INVALID_PATH"' "$TMP/o2.json"
# `mj cd` keeps the legacy go-to-folder meaning; an old alias does not shadow the function
mkdir -p "$TMP/root"
check test "$(MOGRAPHJAILED_ROOT="$TMP/root" mjz "alias mj='echo OLD'; source '$ROOT/scripts/shell/mj-cli.zsh'; mj cd; pwd -P")" = "$(cd "$TMP/root" && pwd -P)"
# bare `mj` is the launch screen (static when not on a terminal)
check bash -c "MJ_STORE_DIR='$TMP/nostore' MJ_AUDIT_DIR='$TMP/noaudit' MJ_CLI='$ROOT/dist/mograph-jailed-linux-test.sh' zsh -f -c \"source '$ROOT/scripts/shell/mj-cli.zsh'; mj\" | grep -q 'M O G R A P H'"
# argument syntax checked locally
set +e; mjz "mj file.inspect noequals" 2>"$TMP/e1"; rc=$?; set -e
check test "$rc" = 64
# ops listing marks required args
mjz "mj ops" > "$TMP/ops.txt"
check grep -q $'^golden.record\tAVAILABLE\tpath\\* output\\* label\\*$' "$TMP/ops.txt"
check test "$(wc -l < "$TMP/ops.txt" | tr -d ' ')" = 46

# recipe: comments, quoting, placeholders with spaces
cat > "$TMP/check.mjrecipe" <<'R'
# inspect then hash the same file
file.inspect path={{target}}

file.hash "path={{target}}"
R
mjz "mj recipe '$TMP/check.mjrecipe' 'target=$TMP/my frames/a file.txt'" > "$TMP/r1.out" 2>"$TMP/r1.err"
check grep -q '\[2/2\] file.hash' "$TMP/r1.err"
check test "$(grep -c '"ok": *true' "$TMP/r1.out")" = 2
# validation happens before any step runs
printf 'file.inspect path={{target}}\nsystem.shell cmd=rm\n' > "$TMP/bad1.mjrecipe"
set +e; mjz "mj recipe '$TMP/bad1.mjrecipe' target=/tmp" > "$TMP/b1.out" 2>"$TMP/b1.err"; rc=$?; set -e
check test "$rc" = 65
check grep -q 'unknown operation: system.shell' "$TMP/b1.err"
check test ! -s "$TMP/b1.out"
printf 'file.inspect path=/tmp evil=1\n' > "$TMP/bad2.mjrecipe"
set +e; mjz "mj recipe '$TMP/bad2.mjrecipe'" 2>"$TMP/b2.err"; rc=$?; set -e
check grep -q 'does not accept argument: evil' "$TMP/b2.err"
printf 'file.inspect path={{target}}\n' > "$TMP/bad3.mjrecipe"
set +e; mjz "mj recipe '$TMP/bad3.mjrecipe'" 2>"$TMP/b3.err"; rc=$?; set -e
check grep -q 'needs target=<value>' "$TMP/b3.err"
# shell syntax in a recipe is inert data, never executed
printf 'file.inspect "path=$(touch %s/pwned)"\n' "$TMP" > "$TMP/inert.mjrecipe"
mjz "mj recipe '$TMP/inert.mjrecipe'" >/dev/null 2>&1 || true
check test ! -e "$TMP/pwned"
# stops at first failing step
printf 'file.inspect path=relative\nsystem.probe\n' > "$TMP/stop.mjrecipe"
set +e; mjz "mj recipe '$TMP/stop.mjrecipe'" > /dev/null 2>"$TMP/s.err"; rc=$?; set -e
check test "$rc" -ne 0
check grep -q 'step 1 (file.inspect) failed' "$TMP/s.err"
check bash -c "! grep -q '2/2' '$TMP/s.err'"


# --- notifications (stub osascript records its arguments) ---
export MJ_STORE_DIR="$TMP/nstore"
cat > "$TMP/osa" <<'STUB'
#!/bin/sh
{ for a in "$@"; do printf '%s\n' "$a"; done; echo "=== end"; } >> "$OSA_LOG"
STUB
chmod +x "$TMP/osa"
export MJ_OSASCRIPT="$TMP/osa" OSA_LOG="$TMP/osa.log"
: > "$OSA_LOG"
osa_wait(){ for _ in $(seq 1 30); do grep -q "=== end" "$OSA_LOG" 2>/dev/null && return 0; sleep 0.1; done; return 1; }
mjn(){ MJ_CLI="$ROOT/dist/mograph-jailed-linux-test.sh" zsh -f -c "source '$ROOT/scripts/shell/mj-cli.zsh'; $1"; }

check test -n "$(mjn "mj notify status" | grep 'off')"
mjn "mj golden.check path=/nonexistent input=/x" >/dev/null 2>&1 || true
sleep 0.4; check test ! -s "$OSA_LOG"                                  # off by default: silent
mjn "mj notify on" >/dev/null
check test -e "$TMP/nstore/notify.on"
check test "$(stat -c '%a' "$TMP/nstore" 2>/dev/null || stat -f '%Lp' "$TMP/nstore")" = 700
mjn "mj system.probe" >/dev/null 2>&1 || true
sleep 0.4; check test ! -s "$OSA_LOG"                                  # fast, non-render op: silent
mjn "mj golden.check path=/nonexistent input=/x" >/dev/null 2>&1 || true
osa_wait
check bash -c "sed -n '1,2p;3p;4p' '$OSA_LOG' | head -3 | grep -q 'on run argv'"
check grep -qx 'mj golden.check' "$OSA_LOG"
check grep -qE '^failed: ' "$OSA_LOG"
check grep -qx 'Basso' "$OSA_LOG"
: > "$OSA_LOG"
# a passing golden check notifies with Glass
mkdir -p "$TMP/g/frames" "$TMP/g/rec"
python3 - "$TMP/g/frames" <<'PY'
import struct, sys, zlib, os
def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
for i in range(3):
    open(os.path.join(sys.argv[1], "f%d.png" % i), "wb").write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 4, 4, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress((b'\x00' + bytes([i * 40, 0, 0]) * 4) * 4)) + chunk(b'IEND', b''))
PY
mjn "mj golden.record path='$TMP/g/frames' output='$TMP/g/rec' label=t1" >/dev/null 2>&1
mjn "mj golden.check path='$TMP/g/frames' input='$TMP/g/rec/t1.golden.json'" >/dev/null 2>&1
osa_wait
check grep -q 'golden check passed (3 frames)' "$OSA_LOG"
check grep -qx 'Glass' "$OSA_LOG"
: > "$OSA_LOG"
# recipes notify at the end, and on the failing step
printf 'system.probe\nsystem.probe\n' > "$TMP/ok.mjrecipe"
mjn "mj recipe '$TMP/ok.mjrecipe'" >/dev/null 2>&1
osa_wait; check grep -q 'finished all 2 steps' "$OSA_LOG"
: > "$OSA_LOG"
printf 'system.probe\nfile.inspect path=relative\nsystem.probe\n' > "$TMP/stop2.mjrecipe"
mjn "mj recipe '$TMP/stop2.mjrecipe'" >/dev/null 2>&1 || true
osa_wait; check grep -q 'stopped at step 2 of 3 (file.inspect)' "$OSA_LOG"
: > "$OSA_LOG"
# text is data: quotes, $(), backticks and newlines reach osascript verbatim as arguments
mjn "_mj_notify_fire 'ti\"tle \$(touch $TMP/X1)' 'me\`touch $TMP/X2\`ssage\"; do shell script \"touch $TMP/X3\"' good"
osa_wait
check grep -qF "ti\"tle \$(touch $TMP/X1)" "$OSA_LOG"
check grep -qF "do shell script" "$OSA_LOG"
check test ! -e "$TMP/X1" -a ! -e "$TMP/X2" -a ! -e "$TMP/X3"
: > "$OSA_LOG"
# test + off
mjn "mj notify off" >/dev/null; mjn "mj notify test" >/dev/null; osa_wait
check grep -q 'Notifications are working' "$OSA_LOG"
check test ! -e "$TMP/nstore/notify.on"
set +e; mjn "mj notify bogus" >/dev/null 2>&1; rc=$?; set -e
check test "$rc" = 64
unset MJ_STORE_DIR MJ_OSASCRIPT OSA_LOG

echo "mj front end tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
