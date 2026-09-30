#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh"
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check() { if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
b64(){ printf '%s' "$1" | base64 -w0; }
run_file_hash(){
  local id=$1 path=$2 out=$3
  cat > "$TMP/$id.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=$id
command=file.hash
arg.path=$(b64 "$path")
REQ
  set +e
  /bin/zsh -f "$CLI" --request "$TMP/$id.req" > "$out"
  RC=$?
  set -e
}
run_temp_create(){
  local id=$1 tmpdir=$2 out=$3
  cat > "$TMP/$id.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=$id
command=temp.create
REQ
  set +e
  TMPDIR="$tmpdir" /bin/zsh -f "$CLI" --request "$TMP/$id.req" > "$out"
  RC=$?
  set -e
}
run_temp_clean(){
  local id=$1 tmpdir=$2 path=$3 out=$4
  cat > "$TMP/$id.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=$id
command=temp.clean
arg.path=$(b64 "$path")
REQ
  set +e
  TMPDIR="$tmpdir" /bin/zsh -f "$CLI" --request "$TMP/$id.req" > "$out"
  RC=$?
  set -e
}

# Environment poisoning: fake PATH commands and hostile Perl settings must not
# alter the audited absolute-command path used by file.hash.
FAKEBIN="$TMP/fakebin"; mkdir "$FAKEBIN"
CANARY="$TMP/ENV_POISON_CANARY"
for cmd in shasum stat file uname awk; do
  cat > "$FAKEBIN/$cmd" <<FAKE
#!/bin/sh
touch '$CANARY'
exit 99
FAKE
  chmod +x "$FAKEBIN/$cmd"
done
TARGET="$TMP/hash-target.txt"; printf 'scope-and-env-regression\n' > "$TARGET"
EXPECTED=$(sha256sum "$TARGET" | awk '{print $1}')
cat > "$TMP/env-hash.req" <<REQ
MOGRAPHJAILED_REQUEST 1
requestId=rc3-env-hash
command=file.hash
arg.path=$(b64 "$TARGET")
REQ
set +e
PATH="$FAKEBIN" PERL5OPT='-MMographJailed_Must_Not_Load' SYSTEM_VERSION_COMPAT=1 COMMAND_MODE=legacy DITTO_TEST_OPTIONS='unexpected' /bin/zsh -f "$CLI" --request "$TMP/env-hash.req" > "$TMP/env-hash.json"
ENV_RC=$?
set -e
check test "$ENV_RC" -eq 0
check jq -e --arg h "$EXPECTED" '.ok==true and .data.hash==$h' "$TMP/env-hash.json"
check test ! -e "$CANARY"

# Helper-local regression: capability/file helpers may not overwrite caller
# variables with the same temporary names (the RC2->RC3 P1 defect class).
check /bin/bash -c '
  set -u
  source "$1/src/core/constants.zsh"
  source "$1/src/core/capabilities.zsh"
  probe(){ local _cap_path="caller-sentinel"; cap_available stat >/dev/null; [ "$_cap_path" = "caller-sentinel" ]; }
  probe
' bash "$ROOT"
check /bin/bash -c '
  set -u
  source "$1/src/core/constants.zsh"
  source "$1/src/modules/file.zsh"
  target="$2"
  probe(){ local _path="caller-sentinel"; file_stat_size "$target" >/dev/null; [ "$_path" = "caller-sentinel" ]; }
  probe
' bash "$ROOT" "$TARGET"

# TMPDIR symlink is canonicalized. Retargeting it later must make cleanup fail
# closed rather than deleting from the old or new target unexpectedly.
REAL_A="$TMP/real-a"; REAL_B="$TMP/real-b"; mkdir "$REAL_A" "$REAL_B"
LINK="$TMP/tmp-link"; ln -s "$REAL_A" "$LINK"
run_temp_create rc3-temp-link "$LINK" "$TMP/temp-link.json"
check test "$RC" -eq 0
TDIR=$(jq -r '.data.path' "$TMP/temp-link.json")
check /bin/bash -c 'case "$1" in "$2"/MographJailed.*) exit 0;; *) exit 1;; esac' bash "$TDIR" "$REAL_A"
rm "$LINK"; ln -s "$REAL_B" "$LINK"
run_temp_clean rc3-temp-retarget "$LINK" "$TDIR" "$TMP/temp-retarget.json"
check test "$RC" -ne 0
check jq -e '.error.code=="TEMP_REFUSED"' "$TMP/temp-retarget.json"
check test -d "$TDIR"
run_temp_clean rc3-temp-correct "$REAL_A" "$TDIR" "$TMP/temp-correct.json"
check test "$RC" -eq 0
check test ! -e "$TDIR"

# Ownership binding tamper: path/euid changes invalidate cleanup authorization.
run_temp_create rc3-marker-path "$REAL_A" "$TMP/marker-path-create.json"
MPATH=$(jq -r '.data.path' "$TMP/marker-path-create.json")
sed -i '3s|.*|/tmp/not-the-bound-path|' "$MPATH/.mj_native_owned"
run_temp_clean rc3-marker-path-clean "$REAL_A" "$MPATH" "$TMP/marker-path-clean.json"
check test "$RC" -ne 0
check jq -e '.error.code=="TEMP_REFUSED"' "$TMP/marker-path-clean.json"
rm -rf "$MPATH"

run_temp_create rc3-marker-euid "$REAL_A" "$TMP/marker-euid-create.json"
EPATH=$(jq -r '.data.path' "$TMP/marker-euid-create.json")
sed -i '4s/.*/99999999/' "$EPATH/.mj_native_owned"
run_temp_clean rc3-marker-euid-clean "$REAL_A" "$EPATH" "$TMP/marker-euid-clean.json"
check test "$RC" -ne 0
check jq -e '.error.code=="TEMP_REFUSED"' "$TMP/marker-euid-clean.json"
rm -rf "$EPATH"

# A control character in TMPDIR would create a path the request protocol cannot
# later represent; refuse it before creating an orphan workspace.
CONTROL_TMP="$TMP/control"$'\n'"dir"; mkdir "$CONTROL_TMP"
run_temp_create rc3-control-tmp "$CONTROL_TMP" "$TMP/control-tmp.json"
check test "$RC" -ne 0
check jq -e '.error.code=="TEMP_UNAVAILABLE"' "$TMP/control-tmp.json"
check /bin/bash -c '! compgen -G "$1/MographJailed.*" >/dev/null' bash "$CONTROL_TMP"

# Default media.inspect may report avmediainfo capability, but must not execute
# the tool in the synchronous default path.
INSPECT_BLOCK=$(awk '/^handle_media_inspect\(\)/,/^handle_media_timing\(\)/' "$ROOT/src/modules/media.zsh")
check /bin/bash -c '! grep -q "/usr/bin/avmediainfo" <<< "$1"' bash "$INSPECT_BLOCK"
check grep -q '_native_probe="notRun"' "$ROOT/src/modules/media.zsh"

# Environment/startup hardening and build reproducibility are release contracts.
check grep -q '^IFS=' "$ROOT/src/core/constants.zsh"
check grep -q 'unset SYSTEM_VERSION_COMPAT' "$ROOT/src/core/constants.zsh"
check grep -q 'unset DITTOABORT' "$ROOT/src/core/constants.zsh"
check grep -q 'unset PERL5OPT' "$ROOT/src/core/constants.zsh"
check grep -q '^#!/bin/sh$' "$ROOT/scripts/build.zsh"
check /bin/sh "$ROOT/scripts/build.zsh"
check /bin/bash -c 'head -n 1 "$1" | grep -qx "#!/bin/zsh -f" && sed -n "2p" "$1" | grep -qx "emulate -R zsh"' bash "$ROOT/dist/mograph-jailed.zsh"
check grep -q '/bin/zsh -f ' "$ROOT/integrations/after-effects/MographJailed_Client.jsxinc"

# Public write-permission fields are explicitly advisory, not guarantees.
check grep -q '"writableHint"' "$ROOT/src/modules/file.zsh"
check grep -q '"writableHint"' "$ROOT/src/modules/volume.zsh"
check /bin/bash -c '! grep -q '\''"writable":'\'' "$1/src/modules/volume.zsh"' bash "$ROOT"

printf 'RC3 hardening tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
