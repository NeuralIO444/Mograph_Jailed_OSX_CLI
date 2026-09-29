#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
pass=0; fail=0
check() { if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
P="$ROOT/research/jxa/framework_probe.js"
check grep -q "ObjC.import('Foundation')" "$P"
check grep -q "ObjC.import('AVFoundation')" "$P"
check grep -q "ObjC.import('CoreImage')" "$P"
check bash -c "! grep -Eq 'Application\\(|System Events|tell application|doShellScript|do shell script' '$P'"
check grep -q 'DO NOT PROMOTE' "$ROOT/research/M6_NATIVE_MEDIA_LAB.md"
check bash -c "! grep -q 'lab.avfoundation.probe' '$ROOT/src/core/protocol.zsh'"
check grep -q '/usr/bin/osascript -l JavaScript' "$ROOT/research/jxa/run_framework_probe.zsh"
printf 'M6 static/research tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
