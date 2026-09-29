#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
MJ_FUZZ_CASES=500 MJ_FUZZ_OFFSET=0 python3 "$ROOT/tests/qa_only/fuzz_protocol_batch.py" "$ROOT"
MJ_FUZZ_CASES=500 MJ_FUZZ_OFFSET=500 python3 "$ROOT/tests/qa_only/fuzz_protocol_batch.py" "$ROOT"
printf 'Protocol fuzz total: 1000 cases, 0 failures\n'
