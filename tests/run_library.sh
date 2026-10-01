#!/usr/bin/env bash
# Phase 9 search and recall: index.add/search/verify, preset.add/get.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
export MJ_STORE_DIR="$TMP/store"
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

# --- empty store: read operations do not create anything ---
run "$TMP/s0.json" index.search "target=glow"
check jq -e '.error.code=="STORE_EMPTY"' "$TMP/s0.json"
run "$TMP/v0.json" index.verify
check jq -e '.error.code=="STORE_EMPTY"' "$TMP/v0.json"
check test ! -e "$TMP/store"

# --- receipts to index ---
mkdir -p "$TMP/receipts/sub" "$TMP/receipts/.hidden"
cat > "$TMP/receipts/hero.scrape.json" <<'J'
{"schema":"MJ_PROJECT_SCRAPE_1","projectName":"hero_sting.aep","projectPath":"/p/hero_sting.aep","aeVersion":"24.6.0",
 "fonts":["Helvetica Neue","Inter"],"footage":[{"name":"ocean_plate.mov","path":"/m/ocean_plate.mov"}],
 "comps":[{"name":"Main Title","width":1920,"height":1080,"frameRate":29.97,"duration":10,
   "layers":[{"name":"Logo Glow","type":"AVLayer","sourceName":"logo.png",
              "effects":[{"name":"Glow","matchName":"ADBE Glo2"}],
              "expressions":[{"propertyPath":"Effects/Glow/Radius","expression":"sampleImage([0,0])[0]*wiggle(2,5)"}]}]}]}
J
printf '{"schema":"MJ_PROJECT_SNAPSHOT_1","sourcePath":"/p/hero_sting.aep","snapshotPath":"/v/hero.x.aep","createdAt":"20261001T000000Z"}' > "$TMP/receipts/sub/hero.snapshot.json"
printf '{"schema":"MJ_GOLDEN_1","label":"hero_master","sourceDir":"/r/hero","frames":[{"name":"f1.png"}]}' > "$TMP/receipts/sub/hero_master.golden.json"
printf '{"schema":"MJ_HANDOFF_1","label":"client_delivery","createdAt":"2026-10-01T00:00:00Z","project":{"source":"/p/hero_sting.aep"},"fonts":["Inter"],"files":[{"packaged":"footage/ocean_plate.mov","source":"/m/ocean_plate.mov"}]}' > "$TMP/receipts/MANIFEST.json"
printf '{"schema":"SOMETHING_ELSE"}' > "$TMP/receipts/other.json"
printf 'not json' > "$TMP/receipts/broken.json"
printf '{"schema":"MJ_GOLDEN_1","label":"secret_hidden","frames":[]}' > "$TMP/receipts/.hidden/h.json"
printf 'ignored' > "$TMP/receipts/notes.txt"

run "$TMP/a1.json" index.add "path=$TMP/receipts"
check jq -e '.ok==true and .data.added==4 and .data.skipped==2 and .data.filesExamined==6' "$TMP/a1.json"
check test "$(stat -c '%a' "$TMP/store" 2>/dev/null || stat -f '%Lp' "$TMP/store")" = 700
run "$TMP/a2.json" index.add "path=$TMP/receipts"
check jq -e '.data.added==0 and .data.unchanged==4' "$TMP/a2.json"
sed -i.bak 's/Main Title/Main Title Revised/' "$TMP/receipts/hero.scrape.json" && rm "$TMP/receipts/hero.scrape.json.bak"
run "$TMP/a3.json" index.add "path=$TMP/receipts/hero.scrape.json"
check jq -e '.data.updated==1' "$TMP/a3.json"

# --- search ---
run "$TMP/s1.json" index.search "target=glow"
check jq -e '[.data.results[].kind] | (index("effect") != null) and (index("layer") != null)' "$TMP/s1.json"
run "$TMP/s2.json" index.search "target=revised"
check jq -e '.data.results[0].kind=="comp" and .data.results[0].name=="Main Title Revised"' "$TMP/s2.json"
run "$TMP/s3.json" index.search "target=helv"            # prefix match
check jq -e '[.data.results[] | select(.kind=="font" and .name=="Helvetica Neue")] | length == 1' "$TMP/s3.json"
run "$TMP/s4.json" index.search "target=sampleImage wiggle"
check jq -e '.data.results[0].kind=="expression"' "$TMP/s4.json"
run "$TMP/s5.json" index.search "target=ocean" "maxResults=1"
check jq -e '(.data.results|length)==1' "$TMP/s5.json"
run "$TMP/s6.json" index.search "target=secret_hidden"
check jq -e '.data.results==[]' "$TMP/s6.json"
# hostile queries are just words: no FTS syntax errors, no SQL
run "$TMP/s7.json" index.search "target=\"; DROP TABLE docs; -- NEAR( OR * ^"
check jq -e '.ok==true' "$TMP/s7.json"
run "$TMP/s8.json" index.search "target=*** ((("
check jq -e '.error.code=="INVALID_ARGUMENT"' "$TMP/s8.json"

# --- presets ---
mkdir "$TMP/presets" "$TMP/out"
printf 'glow v1' > "$TMP/presets/soft_glow.ffx"
run "$TMP/p1.json" preset.add "path=$TMP/presets/soft_glow.ffx" "label=soft_glow"
check jq -e '.data.version==1 and .data.created==true and .data.kind=="ae-animation-preset"' "$TMP/p1.json"
run "$TMP/p2.json" preset.add "path=$TMP/presets/soft_glow.ffx" "label=soft_glow"
check jq -e '.data.version==1 and .data.created==false' "$TMP/p2.json"
printf 'glow v2' > "$TMP/presets/soft_glow.ffx"
run "$TMP/p3.json" preset.add "path=$TMP/presets/soft_glow.ffx" "label=soft_glow"
check jq -e '.data.version==2 and .data.created==true' "$TMP/p3.json"
run "$TMP/g1.json" preset.get "label=soft_glow" "output=$TMP/out"
check jq -e '.data.version==2' "$TMP/g1.json"
check test "$(cat "$TMP/out/soft_glow.ffx")" = "glow v2"
run "$TMP/g2.json" preset.get "label=soft_glow" "output=$TMP/out" "version=1"
check test "$(cat "$TMP/out/soft_glow-v1.ffx")" = "glow v1"
run "$TMP/g3.json" preset.get "label=soft_glow" "output=$TMP/out" "version=1"
check jq -e '.error.code=="OUTPUT_EXISTS"' "$TMP/g3.json"
check test "$(cat "$TMP/out/soft_glow.ffx")" = "glow v2"
run "$TMP/g4.json" preset.get "label=nope" "output=$TMP/out"
check jq -e '.error.code=="NOT_FOUND"' "$TMP/g4.json"
run "$TMP/g5.json" preset.add "path=$TMP/presets/soft_glow.ffx" "label=../x"
check jq -e '.error.code=="INVALID_ARGUMENT"' "$TMP/g5.json"
run "$TMP/s9.json" index.search "target=soft glow"
check jq -e '[.data.results[] | select(.kind=="preset")] | length == 2' "$TMP/s9.json"

# --- verify: healthy, then stale doc and corrupted preset blob ---
run "$TMP/v1.json" index.verify
check jq -e '.data.healthy==true and .data.sqliteIntegrity=="ok" and .data.ftsIntegrity==true and .data.schemaVersion==3 and .data.presetVersions==2 and .data.staleDocs==[]' "$TMP/v1.json"
rm "$TMP/receipts/sub/hero_master.golden.json"
V1SHA=$(jq -r '.data.sha256' "$TMP/p1.json")
printf 'tampered' > "$TMP/store/presets/$V1SHA"
run "$TMP/v2.json" index.verify
check jq -e --arg p "$TMP/receipts/sub/hero_master.golden.json" --arg s "$V1SHA" '.data.healthy==false and .data.staleDocs==[$p] and .data.corruptPresetBlobs==[$s]' "$TMP/v2.json"
rm -f "$TMP/out/soft_glow-v1.ffx"
run "$TMP/g6.json" preset.get "label=soft_glow" "output=$TMP/out" "version=1"
check jq -e '.error.code=="PRESET_CORRUPT"' "$TMP/g6.json"
check test ! -e "$TMP/out/soft_glow-v1.ffx"

# --- a newer store schema is refused, not "migrated" downward ---
python3 -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute('PRAGMA user_version=99'); c.commit()" "$TMP/store/index.sqlite"
run "$TMP/v3.json" index.verify
check jq -e '.error.code=="STORE_TOO_NEW"' "$TMP/v3.json"

echo "Library (index/preset) tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
