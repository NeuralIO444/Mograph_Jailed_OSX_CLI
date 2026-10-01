#!/usr/bin/env bash
# Modules 1-3 fold-in: normalized tables + trace.asset (vendor reverse-engineering)
# and audit.plugins (annual plugin audit), including v1 -> v2 store migration.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d)
TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
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

mkdir -p "$TMP/r"
# Project A: Main -> Mid -> Inner (text with Brandon Grotesque, missing logo.psd).
# Two comps are both named "Inner" (ids 3 and 5); only id 3 is nested under Mid.
cat > "$TMP/r/vendor.scrape.json" <<'J'
{"schema":"MJ_PROJECT_SCRAPE_1","projectName":"vendor.aep","projectPath":"/vendors/acme/vendor.aep","scrapedAt":"2026-10-01T10:00:00Z","aeVersion":"24.6.0",
 "fonts":["Brandon Grotesque","Inter"],
 "footage":[{"id":10,"name":"logo.psd","path":"/vendors/acme/logo.psd","missing":true},
            {"id":11,"name":"bg.mov","path":"/vendors/acme/bg.mov","missing":false}],
 "comps":[
  {"id":1,"name":"Main","width":1920,"height":1080,"frameRate":24,"duration":5,"layers":[
    {"index":1,"name":"Mid layer","type":"AVLayer","sourceName":"Mid","sourcePath":"","sourceId":2,"effects":[{"name":"Glow","matchName":"ADBE Glo2"}]},
    {"index":2,"name":"BG","type":"AVLayer","sourceName":"bg.mov","sourcePath":"/vendors/acme/bg.mov","sourceId":11,"effects":[]}]},
  {"id":2,"name":"Mid","layers":[
    {"index":1,"name":"Inner layer","type":"AVLayer","sourceName":"Inner","sourcePath":"","sourceId":3,"effects":[{"name":"Sapphire Glow","matchName":"S_Glow"}]}]},
  {"id":3,"name":"Inner","layers":[
    {"index":1,"name":"Title","type":"TextLayer","sourceName":"","sourcePath":"","sourceId":0,"font":"Brandon Grotesque","effects":[]},
    {"index":2,"name":"Logo","type":"AVLayer","sourceName":"logo.psd","sourcePath":"/vendors/acme/logo.psd","sourceId":10,"effects":[{"name":"Glow","matchName":"ADBE Glo2"}]}]},
  {"id":5,"name":"Inner","layers":[
    {"index":1,"name":"Other logo","type":"AVLayer","sourceName":"logo.psd","sourcePath":"/vendors/acme/logo.psd","sourceId":10,"effects":[]}]}
 ]}
J
# Project B: also uses S_Glow; also shipped as an OLDER scrape of project A that must not win.
cat > "$TMP/r/other.scrape.json" <<'J'
{"schema":"MJ_PROJECT_SCRAPE_1","projectName":"other.aep","projectPath":"/work/other.aep","scrapedAt":"2026-09-01T00:00:00Z","aeVersion":"25.0.0",
 "fonts":[],"footage":[],
 "comps":[{"id":1,"name":"Solo","layers":[{"index":1,"name":"FX","type":"AVLayer","sourceName":"","sourcePath":"","sourceId":0,"effects":[{"name":"Sapphire Glow","matchName":"S_Glow"},{"name":"Fast Blur","matchName":"ADBE Fast Blur"}]}]}]}
J
cat > "$TMP/r/vendor_old.scrape.json" <<'J'
{"schema":"MJ_PROJECT_SCRAPE_1","projectName":"vendor.aep","projectPath":"/vendors/acme/vendor.aep","scrapedAt":"2025-01-01T00:00:00Z","aeVersion":"23.0.0",
 "fonts":["Comic Sans"],"footage":[],"comps":[{"id":1,"name":"Ancient","layers":[]}]}
J
# Older-style scrape with no ids/fonts: names only.
cat > "$TMP/r/legacy.scrape.json" <<'J'
{"schema":"MJ_PROJECT_SCRAPE_1","projectName":"legacy.aep","projectPath":"/work/legacy.aep","scrapedAt":"2026-08-01T00:00:00Z","aeVersion":"24.0.0",
 "fonts":["Inter"],"footage":[{"name":"gone.mov","path":"/work/gone.mov","missing":true}],
 "comps":[{"name":"Root","layers":[{"index":1,"name":"Pre","type":"AVLayer","sourceName":"Child","sourcePath":"","effects":[]}]},
          {"name":"Child","layers":[{"index":1,"name":"Clip","type":"AVLayer","sourceName":"gone.mov","sourcePath":"/work/gone.mov","effects":[]}]}]}
J

run "$TMP/e.json" trace.asset "target=logo.psd"
check jq -e '.error.code=="STORE_EMPTY"' "$TMP/e.json"
run "$TMP/a.json" index.add "path=$TMP/r"
check jq -e '.ok==true and .data.added==4' "$TMP/a.json"

# --- trace.asset: missing asset -> exact nested comp paths ---
run "$TMP/t1.json" trace.asset "target=logo.psd"
check jq -e '.data.schema=="MJ_TRACE_1" and .data.matchCount==1 and .data.projects[0].projectPath=="/vendors/acme/vendor.aep"' "$TMP/t1.json"
check jq -e '.data.projects[0].matches[0] | .missing==true and ([.uses[] | {comp, layer, paths}] | sort_by(.comp)) == [
  {"comp":"Inner","layer":"Logo","paths":["Main > Mid > Inner"]},
  {"comp":"Inner","layer":"Other logo","paths":["Inner"]}]' "$TMP/t1.json"
# lookup by full path works too
run "$TMP/t2.json" trace.asset "target=/vendors/acme/logo.psd"
check jq -e '.data.matchCount==1' "$TMP/t2.json"
# every missing asset across all projects
run "$TMP/t3.json" trace.asset "format=missing"
check jq -e '[.data.projects[] | {p: .projectPath, a: [.matches[].name]}] == [{"p":"/vendors/acme/vendor.aep","a":["logo.psd"]},{"p":"/work/legacy.aep","a":["gone.mov"]}]' "$TMP/t3.json"
# legacy scrape: nesting resolved by unique comp name
check jq -e '(.data.projects[] | select(.projectPath=="/work/legacy.aep") | .matches[0].uses[0].paths) == ["Root > Child"]' "$TMP/t3.json"
# restrict to one project
run "$TMP/t4.json" trace.asset "format=missing" "path=/work/legacy.aep"
check jq -e '(.data.projects|length)==1' "$TMP/t4.json"
run "$TMP/t5.json" trace.asset "format=missing" "path=/nope.aep"
check jq -e '.error.code=="NOT_FOUND"' "$TMP/t5.json"

# --- trace.asset: font ---
run "$TMP/f1.json" trace.asset "format=font" "target=Brandon Grotesque"
check jq -e '.data.matchCount==1 and .data.projects[0].matches[0].uses[0] == {"comp":"Inner","layer":"Title","layerIndex":1,"paths":["Main > Mid > Inner"],"pathsTruncated":false}' "$TMP/f1.json"
run "$TMP/f2.json" trace.asset "format=font" "target=brandon grotesque"
check jq -e '.data.matchCount==1' "$TMP/f2.json"
# a font listed project-wide but with no layer attribution is still reported
run "$TMP/f3.json" trace.asset "format=font" "target=Inter"
check jq -e '.data.matchCount==2 and ([.data.projects[].matches[0].uses|length] | all(. == 0))' "$TMP/f3.json"
# the older scrape's font never replaced the newer project data
run "$TMP/f4.json" trace.asset "format=font" "target=Comic Sans"
check jq -e '.data.matchCount==0' "$TMP/f4.json"
run "$TMP/f5.json" trace.asset "format=font"
check jq -e '.error.code=="MISSING_ARGUMENT"' "$TMP/f5.json"
run "$TMP/f6.json" trace.asset "format=bogus" "target=x"
check jq -e '.error.code=="INVALID_ARGUMENT"' "$TMP/f6.json"

# --- audit.plugins ---
run "$TMP/p1.json" audit.plugins "target=S_Glow"
check jq -e '.data.schema=="MJ_PLUGIN_USAGE_1" and [.data.projects[] | {projectPath, layerUses}] == [{"projectPath":"/vendors/acme/vendor.aep","layerUses":1},{"projectPath":"/work/other.aep","layerUses":1}]' "$TMP/p1.json"
# exact match only: a prefix or different case finds nothing
run "$TMP/p2.json" audit.plugins "target=S_"
check jq -e '.data.projectCount==0' "$TMP/p2.json"
run "$TMP/p3.json" audit.plugins "target=s_glow"
check jq -e '.data.projectCount==0' "$TMP/p3.json"
# hostile input is just a string
run "$TMP/p4.json" audit.plugins "target=' OR 1=1 --"
check jq -e '.ok==true and .data.projectCount==0' "$TMP/p4.json"
# inventory (no target): every matchName with project counts
run "$TMP/p5.json" audit.plugins
check jq -e '.data.schema=="MJ_PLUGIN_INVENTORY_1" and .data.projectsIndexed==3 and (.data.effects[] | select(.matchName=="ADBE Glo2")) == {"matchName":"ADBE Glo2","effectName":"Glow","projects":1,"layerUses":2}' "$TMP/p5.json"
check jq -e '.data.effects[0].projects >= .data.effects[-1].projects' "$TMP/p5.json"

# --- re-index a newer scrape of A: old rows replaced, not duplicated ---
python3 - "$TMP/r/vendor.scrape.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["scrapedAt"] = "2026-10-02T00:00:00Z"
for c in d["comps"]:
    for l in c["layers"]:
        l["effects"] = [e for e in l["effects"] if e["matchName"] != "S_Glow"]
json.dump(d, open(p, "w"))
PY
run "$TMP/a2.json" index.add "path=$TMP/r"
check jq -e '.data.updated==1' "$TMP/a2.json"
run "$TMP/p6.json" audit.plugins "target=S_Glow"
check jq -e '[.data.projects[].projectPath] == ["/work/other.aep"]' "$TMP/p6.json"
run "$TMP/p7.json" audit.plugins "target=ADBE Glo2"
check jq -e '.data.projects[0].layerUses==2' "$TMP/p7.json"

# --- v1 store migrates to v2 and re-reads receipts on the next index.add ---
rm -rf "$TMP/store"; mkdir -m 700 "$TMP/store"
python3 - "$TMP/store/index.sqlite" "$TMP/r/vendor.scrape.json" <<'PY'
import hashlib, sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.executescript("""
CREATE TABLE docs(id INTEGER PRIMARY KEY, path TEXT UNIQUE NOT NULL, sha256 TEXT NOT NULL, schema TEXT NOT NULL, title TEXT, indexed_at TEXT NOT NULL);
CREATE VIRTUAL TABLE entries USING fts5(doc_id UNINDEXED, kind, name, detail, tokenize='unicode61 remove_diacritics 2');
CREATE TABLE presets(id INTEGER PRIMARY KEY, label TEXT NOT NULL, version INTEGER NOT NULL, sha256 TEXT NOT NULL, kind TEXT NOT NULL, original_name TEXT NOT NULL, bytes INTEGER NOT NULL, added_at TEXT NOT NULL, UNIQUE(label, version));
PRAGMA user_version = 1;""")
sha = hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest()
db.execute("INSERT INTO docs(path, sha256, schema, title, indexed_at) VALUES (?,?,?,?,?)", (sys.argv[2], sha, "MJ_PROJECT_SCRAPE_1", "vendor.aep", "2026-10-01T00:00:00Z"))
db.commit()
PY
run "$TMP/m1.json" index.verify
check jq -e '.data.schemaVersion==3 and .data.healthy==true and .data.docs==1' "$TMP/m1.json"
run "$TMP/m2.json" audit.plugins
check jq -e '.error.code=="STORE_EMPTY"' "$TMP/m2.json"
run "$TMP/m3.json" index.add "path=$TMP/r/vendor.scrape.json"
check jq -e '.data.updated==1 and .data.unchanged==0' "$TMP/m3.json"
run "$TMP/m4.json" trace.asset "target=logo.psd"
check jq -e '.data.matchCount==1' "$TMP/m4.json"

# --- describe publishes the schemas ---
run "$TMP/d.json" system.describe
check jq -e '.data.operations["trace.asset"].args=={"allowed":["target","path","format","maxResults"],"required":[]} and .data.operations["audit.plugins"].mutation=="NONE"' "$TMP/d.json"

echo "Audit query tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
