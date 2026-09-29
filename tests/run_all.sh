#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/tests/run_m1.sh"
"$ROOT/tests/run_m2.sh"
"$ROOT/tests/run_m3.sh"
node "$ROOT/tests/run_m4.js"
"$ROOT/tests/run_m5.sh"
"$ROOT/tests/run_m6.sh"
"$ROOT/tests/run_qa_swarm.sh"

"$ROOT/tests/run_rc3_hardening.sh"
"$ROOT/tests/run_concurrency.sh"
"$ROOT/tests/run_contract_audit.sh"
"$ROOT/tests/run_ng_m1.sh"
"$ROOT/tests/run_ng_m2.sh"
"$ROOT/tests/run_stage_hardening.sh"
"$ROOT/tests/run_stdlib_1.sh"
"$ROOT/tests/run_framekit_m2.sh"
"$ROOT/tests/run_imagestats_m3.sh"

"$ROOT/tests/run_dev4_terminal_ux.sh"

"$ROOT/tests/run_dev4_1_mac_hotfix.sh"
