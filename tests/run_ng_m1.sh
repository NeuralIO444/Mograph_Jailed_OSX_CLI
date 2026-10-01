#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh"
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
b64(){ printf '%s' "$1" | base64 -w0; }
run_req(){
  local name=$1
  set +e
  "$CLI" --request "$TMP/$name.req" > "$TMP/$name.json"
  RC=$?
  set -e
}

# Capability Registry 2.0 is a stable, self-describing contract.
cat > "$TMP/describe.req" <<'REQ'
MOGRAPHJAILED_REQUEST 1
requestId=ngm1-describe
command=system.describe
REQ
run_req describe
check test "$RC" -eq 0
check jq -e '.ok==true and .cliVersion=="0.3.0-dev.2" and .data.schema=="MOGRAPHJAILED_CAPABILITY_REGISTRY_2" and .data.registryVersion==2 and .data.protocolVersion==1' "$TMP/describe.json"
check jq -e '.data.operations|length==30' "$TMP/describe.json"
check jq -e '.data.operations["file.hash"].cost=="SIZE_DEPENDENT" and .data.operations["file.hash"].interactiveSafe==false and .data.operations["file.hash"].authority=="AUTHORITATIVE_BYTES"' "$TMP/describe.json"
check jq -e '.data.operations["file.hash"].requires.anyOf==[["sha256","shasum"]]' "$TMP/describe.json"
check jq -e '.data.operations["runtime.verify"].requires.anyOf==[] and .data.operations["runtime.verify"].optionalCapabilities==["sha256","shasum"]' "$TMP/describe.json"
check jq -e '.data.operations["media.inspect"].authority=="ADVISORY_METADATA" and .data.operations["media.inspect"].optionalCapabilities==["mdls","avmediainfo"]' "$TMP/describe.json"
check jq -e '.data.operations["media.timing"].available==false and .data.operations["media.timing"].state=="UNAVAILABLE" and .data.operations["media.timing"].cost=="BOUNDED_MEDIA_PROBE" and .data.operations["media.timing"].interactiveSafe==false' "$TMP/describe.json"
check jq -e '.data.operations["temp.clean"].mutation=="TEMP_DELETE" and .data.operations["package.create"].mutation=="DERIVATIVE_CREATE"' "$TMP/describe.json"
check jq -e '[.data.operations[] | has("available") and has("state") and has("cost") and has("mutation") and has("authority") and has("interactiveSafe") and has("networkSensitive") and has("requires") and has("optionalCapabilities")] | all' "$TMP/describe.json"

# system.describe takes no arguments.
cat > "$TMP/describe-extra.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm1-describe-extra
command=system.describe
arg.path=$(b64 /tmp)
REQ
run_req describe-extra
check test "$RC" -ne 0
check jq -e '.error.code=="UNEXPECTED_ARGUMENT"' "$TMP/describe-extra.json"

# runtime.verify requires pinned CLI and protocol expectations.
cat > "$TMP/verify-missing.req" <<'REQ'
MOGRAPHJAILED_REQUEST 1
requestId=ngm1-verify-missing
command=runtime.verify
REQ
run_req verify-missing
check test "$RC" -ne 0
check jq -e '.error.code=="MISSING_ARGUMENT"' "$TMP/verify-missing.json"

cat > "$TMP/verify.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm1-verify
command=runtime.verify
arg.expectedCliVersion=$(b64 '0.3.0-dev.2')
arg.expectedProtocolVersion=$(b64 '1')
arg.expectedFilename=$(b64 'mograph-jailed-linux-test.sh')
REQ
run_req verify
check test "$RC" -eq 0
check jq -e '.ok==true and .data.compatible==true and .data.checks.cliVersion==true and .data.checks.protocolVersion==true and .data.checks.filename==true and .data.checks.sha256==null' "$TMP/verify.json"
check jq -e '.data.actual.filename=="mograph-jailed-linux-test.sh" and .data.actual.sha256==null and .data.runtimePathDisclosure=="filename-only"' "$TMP/verify.json"

# Mismatches are diagnostic results, not malformed-command errors.
cat > "$TMP/verify-version-mismatch.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm1-verify-version-mismatch
command=runtime.verify
arg.expectedCliVersion=$(b64 '9.9.9')
arg.expectedProtocolVersion=$(b64 '1')
arg.expectedFilename=$(b64 'mograph-jailed-linux-test.sh')
REQ
run_req verify-version-mismatch
check test "$RC" -eq 0
check jq -e '.ok==true and .data.compatible==false and .data.checks.cliVersion==false and .data.checks.protocolVersion==true' "$TMP/verify-version-mismatch.json"

cat > "$TMP/verify-protocol-mismatch.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm1-verify-protocol-mismatch
command=runtime.verify
arg.expectedCliVersion=$(b64 '0.3.0-dev.2')
arg.expectedProtocolVersion=$(b64 '999')
REQ
run_req verify-protocol-mismatch
check test "$RC" -eq 0
check jq -e '.data.compatible==false and .data.checks.protocolVersion==false' "$TMP/verify-protocol-mismatch.json"

cat > "$TMP/verify-filename-mismatch.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm1-verify-filename-mismatch
command=runtime.verify
arg.expectedCliVersion=$(b64 '0.3.0-dev.2')
arg.expectedProtocolVersion=$(b64 '1')
arg.expectedFilename=$(b64 'wrong-runtime.zsh')
REQ
run_req verify-filename-mismatch
check test "$RC" -eq 0
check jq -e '.data.compatible==false and .data.checks.filename==false' "$TMP/verify-filename-mismatch.json"

# Optional SHA-256 pins the exact runtime bytes when requested.
EXPECTED_SHA=$(sha256sum "$CLI" | awk '{print $1}')
cat > "$TMP/verify-sha.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm1-verify-sha
command=runtime.verify
arg.expectedCliVersion=$(b64 '0.3.0-dev.2')
arg.expectedProtocolVersion=$(b64 '1')
arg.expectedFilename=$(b64 'mograph-jailed-linux-test.sh')
arg.expectedSha256=$(b64 "$EXPECTED_SHA")
REQ
run_req verify-sha
check test "$RC" -eq 0
check jq -e --arg h "$EXPECTED_SHA" '.data.compatible==true and .data.actual.sha256==$h and .data.expected.sha256==$h and .data.checks.sha256==true and (.data.hashSource=="sha256" or .data.hashSource=="shasum")' "$TMP/verify-sha.json"

BAD_SHA=$(printf '0%.0s' {1..64})
cat > "$TMP/verify-bad-sha.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm1-verify-bad-sha
command=runtime.verify
arg.expectedCliVersion=$(b64 '0.3.0-dev.2')
arg.expectedProtocolVersion=$(b64 '1')
arg.expectedSha256=$(b64 "$BAD_SHA")
REQ
run_req verify-bad-sha
check test "$RC" -eq 0
check jq -e '.data.compatible==false and .data.checks.sha256==false' "$TMP/verify-bad-sha.json"

cat > "$TMP/verify-invalid-sha.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm1-verify-invalid-sha
command=runtime.verify
arg.expectedCliVersion=$(b64 '0.3.0-dev.2')
arg.expectedProtocolVersion=$(b64 '1')
arg.expectedSha256=$(b64 'not-a-sha')
REQ
run_req verify-invalid-sha
check test "$RC" -ne 0
check jq -e '.error.code=="INVALID_ARGUMENT" and (.error.message|contains("64-character"))' "$TMP/verify-invalid-sha.json"

# Filename is a leaf name, not an arbitrary filesystem path.
cat > "$TMP/verify-invalid-filename.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm1-verify-invalid-filename
command=runtime.verify
arg.expectedCliVersion=$(b64 '0.3.0-dev.2')
arg.expectedProtocolVersion=$(b64 '1')
arg.expectedFilename=$(b64 '/tmp/runtime.zsh')
REQ
run_req verify-invalid-filename
check test "$RC" -ne 0
check jq -e '.error.code=="INVALID_ARGUMENT"' "$TMP/verify-invalid-filename.json"

# The After Effects client exposes semantic helpers rather than shell syntax.
check grep -q 'Client.prototype.describe' "$ROOT/integrations/after-effects/MographJailed_Client.jsxinc"
check grep -q 'Client.prototype.verifyRuntime' "$ROOT/integrations/after-effects/MographJailed_Client.jsxinc"
check grep -q 'Client.prototype.can' "$ROOT/integrations/after-effects/MographJailed_Client.jsxinc"
check grep -q 'Client.prototype.isInteractiveSafe' "$ROOT/integrations/after-effects/MographJailed_Client.jsxinc"
check grep -q '"system.describe", "runtime.verify"' "$ROOT/integrations/after-effects/MographJailed_Client.jsxinc"

# Registry and runtime implementation are bundled into the production artifact.
check grep -q '# --- src/core/operations.zsh ---' "$ROOT/dist/mograph-jailed.zsh"
check grep -q '# --- src/modules/runtime.zsh ---' "$ROOT/dist/mograph-jailed.zsh"
check grep -q 'MOGRAPHJAILED_CLI_VERSION="0.3.0-dev.2"' "$ROOT/dist/mograph-jailed.zsh"

printf 'NG-M1 tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
