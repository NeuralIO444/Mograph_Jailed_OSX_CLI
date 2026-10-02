#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh"
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
# These suites assert the "native macOS tools are absent" behavior (UNSUPPORTED / UNAVAILABLE). Simulate the
# absence so the same assertions hold on a Mac, which has them, as on a Linux runner, which does not.
export MJ_TEST_MISSING_CAPS="ditto xattr sips mdfind avmediainfo mdls jq"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
b64(){ printf '%s' "$1" | base64 -w0; }
run_req(){ local name=$1; set +e; "$CLI" --request "$TMP/$name.req" > "$TMP/$name.json"; RC=$?; set -e; }

ASSET="$TMP/asset.txt"
printf 'MJ NG-M2 asset\n' > "$ASSET"
if [ "$(uname)" = "Darwin" ]; then
  SIZE=$(stat -f %z "$ASSET")
  MTIME=$(stat -f %m "$ASSET")
else
  SIZE=$(stat -c %s "$ASSET")
  MTIME=$(stat -c %Y "$ASSET")
fi
SHA=$(sha256sum "$ASSET" | awk '{print $1}')

# Single-asset fast manifest.
cat > "$TMP/manifest-fast.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm2-manifest-fast
command=asset.manifest
arg.path=$(b64 "$ASSET")
REQ
run_req manifest-fast
check test "$RC" -eq 0
check jq -e --argjson s "$SIZE" --argjson m "$MTIME" '.ok==true and .cliVersion=="0.4.0-dev.2" and .data.schema=="MJ_ASSET_MANIFEST_1" and .data.filename=="asset.txt" and .data.sizeBytes==$s and .data.modifiedEpoch==$m and .data.identity.mode=="STAT_FINGERPRINT" and .data.identity.sha256==null' "$TMP/manifest-fast.json"

# SHA manifest is explicit and stable.
cat > "$TMP/manifest-sha.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm2-manifest-sha
command=asset.manifest
arg.path=$(b64 "$ASSET")
arg.format=$(b64 sha256)
REQ
run_req manifest-sha
check test "$RC" -eq 0
check jq -e --arg h "$SHA" '.data.identity.mode=="SHA256" and .data.identity.sha256==$h and (.data.identity.hashSource=="sha256" or .data.identity.hashSource=="shasum") and .data.identity.stabilityCheck=="device+inode+size+mtime"' "$TMP/manifest-sha.json"

cat > "$TMP/manifest-bad-mode.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm2-manifest-bad
command=asset.manifest
arg.path=$(b64 "$ASSET")
arg.format=$(b64 deepMagic)
REQ
run_req manifest-bad-mode
check test "$RC" -ne 0
check jq -e '.error.code=="INVALID_ARGUMENT"' "$TMP/manifest-bad-mode.json"

# Multi-field asset verification.
cat > "$TMP/verify-stat.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm2-verify-stat
command=asset.verify
arg.path=$(b64 "$ASSET")
arg.expectedFilename=$(b64 asset.txt)
arg.expectedSizeBytes=$(b64 "$SIZE")
arg.expectedModifiedEpoch=$(b64 "$MTIME")
REQ
run_req verify-stat
check test "$RC" -eq 0
check jq -e '.data.match==true and .data.checks.filename==true and .data.checks.sizeBytes==true and .data.checks.modifiedEpoch==true and .data.checks.sha256==null' "$TMP/verify-stat.json"

cat > "$TMP/verify-mismatch.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm2-verify-mismatch
command=asset.verify
arg.path=$(b64 "$ASSET")
arg.expectedSizeBytes=$(b64 99999)
REQ
run_req verify-mismatch
check test "$RC" -eq 0
check jq -e '.data.match==false and .data.checks.sizeBytes==false' "$TMP/verify-mismatch.json"

cat > "$TMP/verify-sha.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm2-verify-sha
command=asset.verify
arg.path=$(b64 "$ASSET")
arg.expectedSha256=$(b64 "$SHA")
REQ
run_req verify-sha
check test "$RC" -eq 0
check jq -e --arg h "$SHA" '.data.match==true and .data.actual.sha256==$h and .data.checks.sha256==true' "$TMP/verify-sha.json"

cat > "$TMP/verify-no-expected.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm2-verify-empty
command=asset.verify
arg.path=$(b64 "$ASSET")
REQ
run_req verify-no-expected
check test "$RC" -ne 0
check jq -e '.error.code=="MISSING_ARGUMENT"' "$TMP/verify-no-expected.json"

cat > "$TMP/verify-bad-name.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm2-verify-name
command=asset.verify
arg.path=$(b64 "$ASSET")
arg.expectedFilename=$(b64 '/tmp/asset.txt')
REQ
run_req verify-bad-name
check test "$RC" -ne 0
check jq -e '.error.code=="INVALID_ARGUMENT"' "$TMP/verify-bad-name.json"

cat > "$TMP/verify-bad-size.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm2-verify-size
command=asset.verify
arg.path=$(b64 "$ASSET")
arg.expectedSizeBytes=$(b64 nope)
REQ
run_req verify-bad-size
check test "$RC" -ne 0
check jq -e '.error.code=="INVALID_ARGUMENT"' "$TMP/verify-bad-size.json"

# Storage preflight stays advisory for writability/classification but authoritative about measured free bytes.
cat > "$TMP/storage.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm2-storage
command=storage.preflight
arg.path=$(b64 "$TMP")
arg.requiredBytes=$(b64 1024)
REQ
run_req storage
check test "$RC" -eq 0
check jq -e '.data.freeBytes>0 and .data.requiredBytes==1024 and .data.enoughSpace==true and (.data.writableHint|type)=="boolean" and (.data.network|type)=="boolean"' "$TMP/storage.json"

cat > "$TMP/storage-huge.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm2-storage-huge
command=storage.preflight
arg.path=$(b64 "$TMP")
arg.requiredBytes=$(b64 9999999999999999999)
REQ
run_req storage-huge
check test "$RC" -ne 0
check jq -e '.error.code=="INVALID_ARGUMENT"' "$TMP/storage-huge.json"

cat > "$TMP/storage-bad.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm2-storage-bad
command=storage.preflight
arg.path=$(b64 "$TMP")
arg.requiredBytes=$(b64 bananas)
REQ
run_req storage-bad
check test "$RC" -ne 0
check jq -e '.error.code=="INVALID_ARGUMENT"' "$TMP/storage-bad.json"

# macOS-specific adapters fail closed when unavailable on the Linux QA host.
for cmd in file.provenance image.inspect search.candidate; do
  name="unsupported-${cmd//./-}"
  if [ "$cmd" = "search.candidate" ]; then
    cat > "$TMP/$name.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm2-$name
command=$cmd
arg.path=$(b64 "$TMP")
arg.target=$(b64 asset.txt)
REQ
  else
    cat > "$TMP/$name.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm2-$name
command=$cmd
arg.path=$(b64 "$ASSET")
REQ
  fi
  run_req "$name"
  check test "$RC" -ne 0
  check jq -e '.error.code=="UNSUPPORTED"' "$TMP/$name.json"
done

cat > "$TMP/unsupported-image-derivative.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm2-image-derivative
command=image.derivative
arg.input=$(b64 "$ASSET")
arg.output=$(b64 "$TMP/out.png")
arg.target=$(b64 512)
REQ
run_req unsupported-image-derivative
check test "$RC" -ne 0
check jq -e '.error.code=="UNSUPPORTED"' "$TMP/unsupported-image-derivative.json"
check test ! -e "$TMP/out.png"

# Protocol schemas reject missing/extra NG-M2 arguments.
cat > "$TMP/search-missing.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm2-search-missing
command=search.candidate
arg.path=$(b64 "$TMP")
REQ
run_req search-missing
check test "$RC" -ne 0
check jq -e '.error.code=="MISSING_ARGUMENT"' "$TMP/search-missing.json"

cat > "$TMP/image-missing.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=ngm2-image-missing
command=image.derivative
arg.input=$(b64 "$ASSET")
arg.output=$(b64 "$TMP/out.png")
REQ
run_req image-missing
check test "$RC" -ne 0
check jq -e '.error.code=="MISSING_ARGUMENT"' "$TMP/image-missing.json"

# Registry advertises conservative safety/cost semantics.
cat > "$TMP/describe.req" <<'REQ'
MOGRAPHJAILED_REQUEST 1
requestId=ngm2-describe
command=system.describe
REQ
run_req describe
check test "$RC" -eq 0
check jq -e '.data.operations|length==50' "$TMP/describe.json"
check jq -e '.data.operations["asset.manifest"].cost=="MODE_DEPENDENT" and .data.operations["asset.manifest"].interactiveSafe==false and .data.operations["asset.manifest"].authority=="ASSET_IDENTITY"' "$TMP/describe.json"
check jq -e '.data.operations["search.candidate"].authority=="ADVISORY_INDEX" and .data.operations["search.candidate"].mutation=="INTERNAL_TEMP" and .data.operations["search.candidate"].interactiveSafe==false' "$TMP/describe.json"
check jq -e '.data.operations["image.derivative"].mutation=="DERIVATIVE_CREATE" and .data.operations["image.derivative"].interactiveSafe==false' "$TMP/describe.json"
check jq -e '.data.operations["file.provenance"].authority=="AUTHORITATIVE_FILESYSTEM_METADATA" and .data.operations["storage.preflight"].authority=="MIXED"' "$TMP/describe.json"

# Read-only provenance implementation never invokes xattr write/delete/clear modes.
check grep -q '/usr/bin/xattr "$_path"' "$ROOT/src/modules/provenance.zsh"
check /bin/bash -c '! grep -E "/usr/bin/xattr[[:space:]]+-(w|d|c)" "$1/src/modules/provenance.zsh"' bash "$ROOT"

# Image derivative is staged/non-overwriting and never passes the source as sips --out.
check grep -q 'create_mj_stage_dir' "$ROOT/src/modules/image.zsh"
check grep -q 'cleanup_mj_stage_dir' "$ROOT/src/modules/image.zsh"
check grep -q '.mj_native_stage' "$ROOT/src/core/path.zsh"
check grep -q '/bin/mv -n' "$ROOT/src/modules/image.zsh"
check grep -q 'sourceUnchanged' "$ROOT/src/modules/image.zsh"

# Spotlight candidate search is advisory and cannot relink.
check grep -q 'automaticRelink' "$ROOT/src/modules/search.zsh"
check /bin/bash -c '! grep -RInE "relink|replaceFootage" "$1/src/modules/search.zsh" | grep -v automaticRelink' bash "$ROOT"

# AE semantic helpers are present.
for method in assetManifest assetVerify searchCandidate fileProvenance inspectImage createImageDerivative storagePreflight; do
  check grep -q "Client.prototype.$method" "$ROOT/integrations/after-effects/MographJailed_Client.jsxinc"
done

# New modules are in the bundled production graph.
for f in asset provenance image storage search; do
  check grep -q "# --- src/modules/$f.zsh ---" "$ROOT/dist/mograph-jailed.zsh"
done

printf 'NG-M2 tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
