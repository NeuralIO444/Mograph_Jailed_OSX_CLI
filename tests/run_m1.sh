#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh"
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0
check() { if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }

cat > "$TMP/probe.req" <<'REQ'
MOGRAPHJAILED_REQUEST 1
requestId=test-001
command=system.probe
REQ
"$CLI" --request "$TMP/probe.req" > "$TMP/probe.json"
check jq -e '.protocol=="MOGRAPHJAILED" and .protocolVersion==1 and .cliVersion=="0.3.0-dev.2" and .requestId=="test-001" and .command=="system.probe" and .ok==true and (.data.capabilities|type=="object")' "$TMP/probe.json"

cat > "$TMP/doctor.req" <<'REQ'
MOGRAPHJAILED_REQUEST 1
requestId=test-002
command=system.doctor
REQ
"$CLI" --request "$TMP/doctor.req" > "$TMP/doctor.json"
check jq -e '.ok==true and .data.ready==false and .data.isMacOS==false' "$TMP/doctor.json"

cat > "$TMP/bad-command.req" <<'REQ'
MOGRAPHJAILED_REQUEST 1
requestId=test-003
command=shell.execute
arg.path=L3RtcA==
REQ
set +e
"$CLI" --request "$TMP/bad-command.req" > "$TMP/bad-command.json"
rc=$?
set -e
check test "$rc" -ne 0
check jq -e '.ok==false and .error.code=="UNSUPPORTED_COMMAND"' "$TMP/bad-command.json"

CANARY="$TMP/SHOULD_NOT_EXIST"
attack=$(printf '$(touch %s)' "$CANARY" | base64 -w0)
cat > "$TMP/injection.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=test-004
command=file.inspect
arg.path=$attack
REQ
set +e
"$CLI" --request "$TMP/injection.req" > "$TMP/injection.json"
rc=$?
set -e
check test "$rc" -ne 0
check test ! -e "$CANARY"
check jq -e '.error.code=="INVALID_PATH"' "$TMP/injection.json"

ctrl=$(printf '/tmp/a\tb' | base64 -w0)
cat > "$TMP/control.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=test-control
command=file.inspect
arg.path=$ctrl
REQ
set +e
"$CLI" --request "$TMP/control.req" > "$TMP/control.json"
rc=$?
set -e
check test "$rc" -ne 0
check jq -e '.error.code=="INVALID_ARGUMENT"' "$TMP/control.json"

cat > "$TMP/noncanonical.req" <<'REQ'
MOGRAPHJAILED_REQUEST 1
requestId=test-b64
command=file.inspect
arg.path=L3RtcA
REQ
set +e
"$CLI" --request "$TMP/noncanonical.req" > "$TMP/noncanonical.json"
rc=$?
set -e
check test "$rc" -ne 0
check jq -e '.error.code=="INVALID_ARGUMENT_ENCODING"' "$TMP/noncanonical.json"



# Required argument errors must keep their structured error state.
cat > "$TMP/missing-arg.req" <<'REQ'
MOGRAPHJAILED_REQUEST 1
requestId=test-missing
command=file.inspect
REQ
set +e
"$CLI" --request "$TMP/missing-arg.req" > "$TMP/missing-arg.json"
rc=$?
set -e
check test "$rc" -ne 0
check jq -e '.ok==false and .error.code=="MISSING_ARGUMENT" and (.error.message|length)>0' "$TMP/missing-arg.json"

# Present-but-empty required arguments exercise the runtime require_arg path.
cat > "$TMP/empty-arg.req" <<'REQ'
MOGRAPHJAILED_REQUEST 1
requestId=test-empty
command=file.inspect
arg.path=
REQ
set +e
"$CLI" --request "$TMP/empty-arg.req" > "$TMP/empty-arg.json"
rc=$?
set -e
check test "$rc" -ne 0
check jq -e '.ok==false and .error.code=="MISSING_ARGUMENT" and (.error.message|length)>0' "$TMP/empty-arg.json"

# Commands reject globally-known but command-invalid arguments instead of ignoring them.
cat > "$TMP/unexpected.req" <<'REQ'
MOGRAPHJAILED_REQUEST 1
requestId=test-unexpected
command=system.probe
arg.path=L3RtcA==
REQ
set +e
"$CLI" --request "$TMP/unexpected.req" > "$TMP/unexpected.json"
rc=$?
set -e
check test "$rc" -ne 0
check jq -e '.ok==false and .error.code=="UNEXPECTED_ARGUMENT"' "$TMP/unexpected.json"

# Oversized decoded values fail closed before reaching a native adapter.
large=$(head -c 17000 /dev/zero | tr '\0' 'a' | base64 -w0)
cat > "$TMP/oversized.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=test-oversized
command=file.inspect
arg.path=$large
REQ
set +e
"$CLI" --request "$TMP/oversized.req" > "$TMP/oversized.json"
rc=$?
set -e
check test "$rc" -ne 0
check jq -e '.ok==false and .error.code=="REQUEST_TOO_LARGE"' "$TMP/oversized.json"

cat > "$TMP/bad-field.req" <<'REQ'
MOGRAPHJAILED_REQUEST 1
requestId=test-005
command=system.probe
rawCommand=touch /tmp/oops
REQ
set +e
"$CLI" --request "$TMP/bad-field.req" > "$TMP/bad-field.json"
rc=$?
set -e
check test "$rc" -ne 0
check jq -e '.error.code=="MALFORMED_REQUEST"' "$TMP/bad-field.json"

printf 'M1 tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
