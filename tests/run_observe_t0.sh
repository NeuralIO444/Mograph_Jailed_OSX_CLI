#!/usr/bin/env bash
# Tier 0 (Observer) portable tests: project.ingest, expression.lint,
# plugin.audit, project.snapshot.
# Pure-python paths (ingest/lint validation) run anywhere python3 exists.
# plugin.audit / project.snapshot exercise the real filesystem + shasum.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
b64(){ printf '%s' "$1" | base64 | tr -d '\n'; }

req(){
  local _cmd="$1"; shift
  local _id="test-$RANDOM-$RANDOM"
  local _f="$TMP/req_$RANDOM.txt"
  {
    printf 'MOGRAPHJAILED_REQUEST 1\n'
    printf 'requestId=%s\n' "$_id"
    printf 'command=%s\n' "$_cmd"
    for _a in "$@"; do
      printf 'arg.%s=%s\n' "${_a%%=*}" "$(b64 "${_a#*=}")"
    done
  } > "$_f"
  printf '%s|%s\n' "$_id" "$_f"
}
run_req(){
  local _spec="$1"; local _out="$2"
  local _id="${_spec%%|*}" _f="${_spec#*|}"
  "$CLI" --request "$_f" > "$_out" 2>/dev/null || true
  printf '%s' "$_id"
}

# --- Fixtures ---
printf 'fake-bg-bytes' > "$TMP/bg.mp4"
cat > "$TMP/scrape.json" <<JSONEOF
{
  "schema": "MJ_PROJECT_SCRAPE_1",
  "scraperVersion": "1.0",
  "projectPath": "$TMP/test.aep",
  "projectName": "test.aep",
  "scrapedAt": "2026-09-29T00:00:00Z",
  "aeVersion": "25.1.0",
  "numItems": 6,
  "comps": [
    {
      "name": "Main", "id": 1, "width": 1920, "height": 1080, "pixelAspect": 1.0,
      "frameRate": 29.97, "duration": 10.0, "numLayers": 2,
      "layers": [
        {
          "name": "BG", "index": 1, "type": "AVLayer",
          "enabled": true, "solo": false, "locked": false,
          "hasVideo": true, "hasAudio": false,
          "sourceName": "bg.mp4", "sourcePath": "$TMP/bg.mp4",
          "effects": [{"name": "Gaussian Blur", "matchName": "ADBE Gaussian Blur 2"}],
          "markers": 0, "numProperties": 4, "numKeyframedProperties": 1,
          "expressions": [
            {"propertyPath": "Transform/Position", "expression": "thisComp.layer(\"Missing\").transform.position"},
            {"propertyPath": "Transform/Opacity", "expression": "effect(\"Nope\").param(1)"},
            {"propertyPath": "Effects/Gaussian Blur/Blurriness", "expression": "for (i=0;i<10;i++){ s=sampleImage([i,i],[5,5],true,time); } s[0]"}
          ]
        },
        {
          "name": "Title", "index": 2, "type": "TextLayer",
          "enabled": true, "solo": false, "locked": false,
          "hasVideo": true, "hasAudio": false,
          "sourceName": "", "sourcePath": "",
          "effects": [], "markers": 0,
          "numProperties": 3, "numKeyframedProperties": 0,
          "expressions": [
            {"propertyPath": "Text/Source Text", "expression": "eval(\"/Users/matt/file.txt\")"}
          ]
        }
      ]
    },
    {
      "name": "Precomp", "id": 2, "width": 1280, "height": 720, "pixelAspect": 1.0,
      "frameRate": 29.97, "duration": 5.0, "numLayers": 1,
      "layers": [
        {
          "name": "Shape", "index": 1, "type": "ShapeLayer",
          "enabled": true, "solo": false, "locked": false,
          "hasVideo": true, "hasAudio": false,
          "sourceName": "", "sourcePath": "",
          "effects": [], "markers": 0,
          "numProperties": 2, "numKeyframedProperties": 0, "expressions": []
        }
      ]
    }
  ],
  "fonts": ["Helvetica", "ArialMT"],
  "footage": [
    {"name": "bg.mp4", "path": "$TMP/bg.mp4", "missing": false, "hasVideo": true, "hasAudio": false},
    {"name": "gone.mov", "path": "$TMP/gone.mov", "missing": true, "hasVideo": true, "hasAudio": false},
    {"name": "unlinked.psd", "path": "", "missing": false, "hasVideo": true, "hasAudio": false}
  ]
}
JSONEOF
printf 'not json at all{{{' > "$TMP/bad.json"
printf '{"schema":"WRONG","comps":[]}' > "$TMP/wrong-schema.json"

# --- project.ingest: valid ---
rid=$(run_req "$(req project.ingest "path=$TMP/scrape.json")" "$TMP/ingest.json")
check jq -e --arg r "$rid" '.ok==true and .requestId==$r and .command=="project.ingest" and .data.schema=="MJ_PROJECT_SUMMARY_1"' "$TMP/ingest.json"
check jq -e '.data.numComps==2 and .data.numLayers==3 and .data.numExpressions==4 and .data.numEffects==1' "$TMP/ingest.json"
check jq -e '.data.fonts==["ArialMT","Helvetica"] and .data.numFonts==2' "$TMP/ingest.json"
check jq -e '.data.footageMissing==["gone.mov"] and .data.footageUnlinked==["unlinked.psd"] and .data.numFootage==3' "$TMP/ingest.json"
check jq -e '.data.layerTypes.AVLayer==1 and .data.layerTypes.TextLayer==1 and .data.layerTypes.ShapeLayer==1' "$TMP/ingest.json"

# --- project.ingest: invalid inputs ---
run_req "$(req project.ingest "path=$TMP/bad.json")" "$TMP/ingest-bad.json" >/dev/null
check jq -e '.ok==false and .error.code=="INVALID_JSON"' "$TMP/ingest-bad.json"
run_req "$(req project.ingest "path=$TMP/wrong-schema.json")" "$TMP/ingest-wrong.json" >/dev/null
check jq -e '.ok==false and .error.code=="SCHEMA_MISMATCH"' "$TMP/ingest-wrong.json"
run_req "$(req project.ingest "path=/nope/missing.json")" "$TMP/ingest-missing.json" >/dev/null
check jq -e '.ok==false' "$TMP/ingest-missing.json"
run_req "$(req project.ingest)" "$TMP/ingest-noarg.json" >/dev/null
check jq -e '.ok==false' "$TMP/ingest-noarg.json"

# --- expression.lint ---
run_req "$(req expression.lint "path=$TMP/scrape.json")" "$TMP/lint.json" >/dev/null
check jq -e '.ok==true and .data.schema=="MJ_EXPRESSION_LINT_1" and .data.numExpressions==4' "$TMP/lint.json"
check jq -e '.data.errors==2 and .data.warnings==2 and .data.info==1 and .data.numFindings==5' "$TMP/lint.json"
check jq -e '[.data.findings[].code]|sort==["E001","E002","I001","W001","W002"]' "$TMP/lint.json"
check jq -e '[.data.findings[]|select(.code=="E001")][0]|(.comp=="Main" and .layer=="BG" and .severity=="error")' "$TMP/lint.json"
check jq -e '[.data.findings[]|select(.code=="W001")][0].propertyPath=="Effects/Gaussian Blur/Blurriness"' "$TMP/lint.json"
run_req "$(req expression.lint "path=$TMP/bad.json")" "$TMP/lint-bad.json" >/dev/null
check jq -e '.ok==false and .error.code=="INVALID_JSON"' "$TMP/lint-bad.json"

# --- plugin.audit ---
mkdir -p "$TMP/plugins/Fake.plugin/Contents" "$TMP/plugins/Effects"
printf 'plugin-bytes' > "$TMP/plugins/Fake.plugin/Contents/binary"
printf 'effect-bytes' > "$TMP/plugins/Effects/blur.aex"
printf 'readme' > "$TMP/plugins/README.txt"
run_req "$(req plugin.audit "path=$TMP/plugins")" "$TMP/audit.json" >/dev/null
check jq -e '.ok==true and .data.schema=="MJ_PLUGIN_AUDIT_1" and .data.numEntries==3 and .data.truncated==false' "$TMP/audit.json"
check jq -e '[.data.entries[].kind]|sort==["bundle","directory","file"]' "$TMP/audit.json"
check jq -e '[.data.entries[]|select(.kind=="file")][0]|(.name=="README.txt" and .sha256!=null and .sizeBytes==6)' "$TMP/audit.json"
check jq -e '[.data.entries[]|select(.kind=="bundle")][0].sha256==null' "$TMP/audit.json"
run_req "$(req plugin.audit "path=/nope/missing")" "$TMP/audit-bad.json" >/dev/null
check jq -e '.ok==false' "$TMP/audit-bad.json"

# --- project.snapshot ---
printf 'aep-bytes-v1' > "$TMP/test.aep"
mkdir -p "$TMP/versions"
H1=$(sha256sum "$TMP/test.aep" | awk '{print $1}')
run_req "$(req project.snapshot "path=$TMP/test.aep" "output=$TMP/versions")" "$TMP/snap1.json" >/dev/null
check jq -e --arg h "$H1" '.ok==true and .data.schema=="MJ_PROJECT_SNAPSHOT_1" and .data.snapshotCreated==true and .data.sha256==$h' "$TMP/snap1.json"
SNAP1=$(jq -r '.data.snapshotPath' "$TMP/snap1.json")
check test -f "$SNAP1"
check test -f "$SNAP1.snapshot.json"
check test -f "$TMP/versions/test.latest.json"
# source must be byte-identical after snapshotting
check test "$(sha256sum "$TMP/test.aep" | awk '{print $1}')" = "$H1"
# second run: unchanged -> no new snapshot
N1=$(ls "$TMP"/versions/*.aep | wc -l)
run_req "$(req project.snapshot "path=$TMP/test.aep" "output=$TMP/versions")" "$TMP/snap2.json" >/dev/null
check jq -e '.ok==true and .data.snapshotCreated==false and .data.reason=="unchanged"' "$TMP/snap2.json"
check test "$(ls "$TMP"/versions/*.aep | wc -l)" = "$N1"
# modify -> new snapshot with a different name
printf 'aep-bytes-v2-longer' > "$TMP/test.aep"
run_req "$(req project.snapshot "path=$TMP/test.aep" "output=$TMP/versions")" "$TMP/snap3.json" >/dev/null
check jq -e '.ok==true and .data.snapshotCreated==true' "$TMP/snap3.json"
SNAP3=$(jq -r '.data.snapshotPath' "$TMP/snap3.json")
check test "$SNAP3" != "$SNAP1"
check test -f "$SNAP3"
# missing source -> error, nothing written
run_req "$(req project.snapshot "path=/nope/missing.aep" "output=$TMP/versions")" "$TMP/snap-bad.json" >/dev/null
check jq -e '.ok==false' "$TMP/snap-bad.json"
# non-.aep source -> rejected before any copy
printf 'not-a-project' > "$TMP/notes.txt"
N2=$(ls "$TMP"/versions/*.aep | wc -l)
run_req "$(req project.snapshot "path=$TMP/notes.txt" "output=$TMP/versions")" "$TMP/snap-txt.json" >/dev/null
check jq -e '.ok==false and .error.code=="INVALID_TARGET"' "$TMP/snap-txt.json"
check test "$(ls "$TMP"/versions/*.aep | wc -l)" = "$N2"

# --- dashboard (btop-style, read-only) ---
DASH_TMP=$(mktemp -d)
mkdir -p "$DASH_TMP/versions" "$DASH_TMP/receipts"
printf 'aep-bytes' > "$DASH_TMP/versions/demo.20260929T150000Z.a1b2c3d4e5f6.aep"
cp "$TMP/scrape.json" "$DASH_TMP/receipts/demo.20260929T150000Z.scrape.json"
printf '2026-09-29 15:10:00 snapshot ok: /tmp/x.aep\n' > "$DASH_TMP/versions/watcher.log"
DASH_OUT=$(COLUMNS=100 LINES=32 "$ROOT/tools/mj-observe-dash.zsh" \
  --versions "$DASH_TMP/versions" --receipts "$DASH_TMP/receipts" \
  --cli "$CLI" --once 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
check printf '%s' "$DASH_OUT" | grep -q "TIER 0 OBSERVER"
check printf '%s' "$DASH_OUT" | grep -q "PROJECT SNAPSHOTS (1)"
check printf '%s' "$DASH_OUT" | grep -q "PROJECT VITALS"
check printf '%s' "$DASH_OUT" | grep -q "EXPRESSION LINT"
check printf '%s' "$DASH_OUT" | grep -q "WATCHER"
check printf '%s' "$DASH_OUT" | grep -q "READ-ONLY"
# every rendered line must fit the terminal width (no misaligned borders)
check python3 - "$DASH_OUT" <<'PY_ALIGN'
import re, sys, unicodedata
def w(s):
    return sum(2 if unicodedata.east_asian_width(c) in ("W", "F") else 1 for c in s)
bad = [l for l in sys.argv[1].splitlines() if w(l) > 100]
sys.exit(1 if bad else 0)
PY_ALIGN
# dashboard must not modify the versions dir (read-only Tier 0)
check test "$(ls "$DASH_TMP/versions" | wc -l | tr -d ' ')" = "2"
rm -rf "$DASH_TMP"

printf 'Tier 0 observer tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
