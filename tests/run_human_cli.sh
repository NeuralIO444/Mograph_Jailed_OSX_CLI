#!/usr/bin/env bash
# Human CLI features: config (#29), lint teaching (#33), explain (#28), health (#32),
# project.diff (#22), human verbs (#26), completions (#30), snapshot hooks (#31), installer (#15 #27).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
export MJ_STORE_DIR="$TMP/store" MJ_AUDIT_DIR="$TMP/noaudit" MJ_CONFIG="$TMP/cfg/config"
unset MJ_VERSIONS_DIR MJ_RECEIPTS_DIR MJ_WATCH_DIR MJ_POST_SNAPSHOT_HOOK
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
mjz(){ MJ_CLI="$CLI" zsh -f -c "source '$ROOT/scripts/shell/mj-cli.zsh'; $1"; }

# ================= #29 config =================
check bash -c "MJ_CONFIG='$TMP/cfg/config' zsh -f -c \"source '$ROOT/scripts/shell/mj-config.zsh'; mj_config_get versions_dir\" | grep -q 'AE_Versions'"
mjz "mj config set versions_dir '$TMP/v'" | grep -q 'saved' && pass=$((pass+1)) || { echo "FAIL: config set" >&2; fail=$((fail+1)); }
check test "$(cat "$TMP/cfg/config")" = "versions_dir=$TMP/v"
check test "$(mjz "mj config get versions_dir")" = "$TMP/v"
mjz "mj config set versions_dir '$TMP/v2'" >/dev/null                                   # replaces, no duplicate lines
check test "$(grep -c '^versions_dir=' "$TMP/cfg/config")" = 1
check test "$(mjz "mj config get versions_dir")" = "$TMP/v2"
check test "$(MJ_VERSIONS_DIR=/env/wins mjz "mj config get versions_dir")" = "/env/wins"        # env beats file
mjz "mj config show" > "$TMP/show.txt"
check grep -Eq 'versions_dir +\(file\) +.*/v2' "$TMP/show.txt"
check bash -c "MJ_VERSIONS_DIR=/e MJ_CONFIG='$TMP/cfg/config' MJ_CLI='$CLI' zsh -f -c \"source '$ROOT/scripts/shell/mj-cli.zsh'; mj config show\" | grep -Eq 'versions_dir +\(env\)'"
check grep -Eq 'receipts_dir +\(default\)' "$TMP/show.txt"
set +e; mjz "mj config set bogus x" >/dev/null 2>&1; r1=$?; mjz "mj config set versions_dir relative/path" >/dev/null 2>&1; r2=$?
mjz "mj config set cli" >/dev/null 2>&1; r3=$?; set -e
check test "$r1" = 64 -a "$r2" = 64 -a "$r3" = 64
check test "$(grep -c bogus "$TMP/cfg/config")" = 0
# values are data: shell syntax in a config file is never executed, and ~ is expanded
printf 'receipts_dir=$(touch %s/pwned)\n# comment\n\nwatch_dir=~/Movies\n' "$TMP" >> "$TMP/cfg/config"
check test "$(mjz "mj config get watch_dir")" = "~/Movies"           # read verbatim from a hand-written file
check test ! -e "$TMP/pwned"
mjz "mj config set watch_dir '~/Footage'" >/dev/null
check test "$(mjz "mj config get watch_dir")" = "$HOME/Footage"          # ~ expanded on set
mjz "mj config unset watch_dir" >/dev/null
check test -z "$(grep '^watch_dir' "$TMP/cfg/config" || true)"
# the config's cli is used by mj; the dashboard picks up folders and cli from config
mkdir -p "$TMP/v2" "$TMP/rc"
mjz "mj config set cli '$CLI'" >/dev/null
check bash -c "MJ_CLI= MJ_CONFIG='$TMP/cfg/config' zsh -f -c \"source '$ROOT/scripts/shell/mj-cli.zsh'; mj system.probe\" | jq -e '.ok==true' >/dev/null"
mjz "mj config set receipts_dir '$TMP/rc'" >/dev/null
"$ROOT/tools/mj-observe-dash.zsh" --json > "$TMP/dashcfg.json" 2>"$TMP/dashcfg.err" || true
check jq -e '.schema=="MJ_OBSERVE_DASH_1"' "$TMP/dashcfg.json"                           # no --versions/--cli flags needed
check bash -c "MJ_CONFIG='$TMP/nocfg' HOME='$TMP/emptyhome' '$ROOT/tools/mj-observe-dash.zsh' --json 2>&1 | grep -q 'mj config set versions_dir'"

# ================= fixtures: two versions of one project =================
mkdir -p "$TMP/sc/media"; : > "$TMP/sc/media/bg.mov"; : > "$TMP/sc/media/logo.psd"
python3 - "$TMP/sc" <<'PY'
import json, os, sys, copy
d = sys.argv[1]
M = os.path.join(d, "media")
def layer(i, name, typ="AVLayer", src="", sid=0, fx=(), ex=(), **kw):
    l = {"index": i, "name": name, "type": typ, "enabled": True, "solo": False, "locked": False, "sourceName": src, "sourcePath": "", "sourceId": sid,
         "effects": [{"name": n, "matchName": m} for n, m in fx], "expressions": [{"propertyPath": p, "expression": e} for p, e in ex]}
    l.update(kw); return l
v1 = {"schema": "MJ_PROJECT_SCRAPE_1", "scraperVersion": "1.0", "projectPath": "/p/hero.aep", "projectName": "hero.aep", "scrapedAt": "2026-10-01T09:00:00Z", "aeVersion": "24.6.0", "numItems": 5,
      "fonts": ["Inter"],
      "footage": [{"id": 10, "name": "bg.mov", "path": os.path.join(M, "bg.mov"), "missing": False}, {"id": 11, "name": "logo.psd", "path": os.path.join(M, "logo.psd"), "missing": False}],
      "comps": [{"id": 1, "name": "Main", "width": 1920, "height": 1080, "frameRate": 24, "duration": 5, "layers": [
                  layer(1, "Title", "TextLayer", fx=[("Glow", "ADBE Glo2")], ex=[("Transform/Position", 'thisComp.layer("Logo").transform.position')]),
                  layer(2, "Logo", src="logo.psd", sid=11),
                  layer(3, "Old BG", src="bg.mov", sid=10)]}]}
v2 = copy.deepcopy(v1)
v2["scrapedAt"] = "2026-10-01T10:30:00Z"; v2["fonts"] = ["Inter", "Brandon Grotesque"]
v2["footage"][1]["missing"] = True
c = v2["comps"][0]; c["frameRate"] = 30
c["layers"][0]["expressions"][0]["expression"] = 'thisComp.layer("Logo Missing").transform.position'
c["layers"][0]["effects"].append({"name": "Sapphire Glow", "matchName": "S_Glow"})
del c["layers"][2]
c["layers"].append(layer(3, "New BG", src="bg.mov", sid=10))
v2["comps"].append({"id": 2, "name": "Outro", "width": 1920, "height": 1080, "frameRate": 30, "duration": 2, "layers": []})
json.dump(v1, open(os.path.join(d, "v1.scrape.json"), "w")); json.dump(v2, open(os.path.join(d, "v2.scrape.json"), "w"))
# ids stripped: older scrapes match by name
for name, v in (("n1", v1), ("n2", v2)):
    w = copy.deepcopy(v)
    for cc in w["comps"]:
        cc.pop("id", None)
    for f in w["footage"]:
        f.pop("id", None)
    json.dump(w, open(os.path.join(d, name + ".scrape.json"), "w"))
PY

# ================= #22 project.diff =================
run "$TMP/df.json" project.diff "path=$TMP/sc/v1.scrape.json" "input=$TMP/sc/v2.scrape.json"
check jq -e '.ok==true and .data.schema=="MJ_DIFF_1" and .data.identical==false and .data.matchedBy=={"comps":"id","footage":"id"}' "$TMP/df.json"
check jq -e '.data.summary | .compsAdded==1 and .compsRemoved==0 and .compsChanged==1 and .layersAdded==1 and .layersRemoved==1 and .expressionsChanged==1 and .footageMissingChanged==1 and .fontsAdded==1 and .effectsAdded==1' "$TMP/df.json"
check jq -e '[.data.changes[].text] | (index("comp \"Outro\" added (0 layers)")!=null) and (index("comp \"Main\": frame rate 24 -> 30")!=null) and (index("footage \"logo.psd\" went missing")!=null) and (index("font \"Brandon Grotesque\" added")!=null)' "$TMP/df.json"
check jq -e '[.data.changes[].text] | any(test("expression on Transform/Position changed")) and any(test("layer \"Title\".*effects \\+Sapphire Glow")) and any(test("layer \"Old BG\" removed")) and any(test("layer \"New BG\" added"))' "$TMP/df.json"
check jq -e '.data.sourceUnchanged==true and .warnings==[]' "$TMP/df.json"
run "$TMP/dfs.json" project.diff "path=$TMP/sc/v1.scrape.json" "input=$TMP/sc/v1.scrape.json"      # same file: identical
check jq -e '.data.identical==true and .data.changes==[] and ([.data.summary[]]|add)==0' "$TMP/dfs.json"
run "$TMP/dfr.json" project.diff "path=$TMP/sc/v2.scrape.json" "input=$TMP/sc/v1.scrape.json"      # reversed: out-of-order warning, added<->removed
check jq -e '[.warnings[].code]|index("SCRAPES_OUT_OF_ORDER")!=null' "$TMP/dfr.json"
check jq -e '.data.summary.compsRemoved==1 and .data.summary.compsAdded==0' "$TMP/dfr.json"
run "$TMP/dfn.json" project.diff "path=$TMP/sc/n1.scrape.json" "input=$TMP/sc/n2.scrape.json"      # no ids: matched by name, same answer
check jq -e '.data.matchedBy=={"comps":"name","footage":"path"} and .data.summary.compsAdded==1 and .data.summary.layersAdded==1 and .data.summary.expressionsChanged==1' "$TMP/dfn.json"
python3 -c "import json; d=json.load(open('$TMP/sc/v2.scrape.json')); d['projectPath']='/other/x.aep'; json.dump(d, open('$TMP/sc/other.scrape.json','w'))"
run "$TMP/dfo.json" project.diff "path=$TMP/sc/v1.scrape.json" "input=$TMP/sc/other.scrape.json"
check jq -e '[.warnings[].code]|index("DIFFERENT_PROJECTS")!=null' "$TMP/dfo.json"
run "$TMP/dfe.json" project.diff "path=$TMP/sc/v1.scrape.json" "input=$TMP/nope.json"
check jq -e '.ok==false' "$TMP/dfe.json"
run "$TMP/dfm.json" project.diff "path=$TMP/sc/v1.scrape.json"
check jq -e '.error.code=="MISSING_ARGUMENT"' "$TMP/dfm.json"

# ================= #32 project.health =================
run "$TMP/h1.json" project.health "path=$TMP/sc/v1.scrape.json"
check jq -e '.ok==true and .data.schema=="MJ_PROJECT_HEALTH_1" and .data.formulaVersion==1 and (.data.formula|length)>40' "$TMP/h1.json"
# v1: no missing footage; 1 error (E001? no) -> lint of v1 has clean expressions
check jq -e '.data.score==100 and .data.band=="healthy" and ([.data.components[]|select(.measured)]|length)==2' "$TMP/h1.json"
check jq -e '(.data.components[]|select(.name=="snapshots")) | .measured==false and .max==25' "$TMP/h1.json"
run "$TMP/h2.json" project.health "path=$TMP/sc/v2.scrape.json"
# v2: 1 missing item (-12 => 23/35) and 1 expression error E001 (-8 => 32/40): 55/75 -> 73
check jq -e '.data.score==73 and .data.band=="needs a look"' "$TMP/h2.json"
check jq -e '(.data.components[]|select(.name=="footage")) | .points==23 and (.findings|length)==1 and .findings[0]=={"kind":"missing","name":"logo.psd"}' "$TMP/h2.json"
check jq -e '(.data.components[]|select(.name=="expressions")) | .points==32 and (.findings[0] | .code=="E001" and .comp=="Main" and .layer=="Title")' "$TMP/h2.json"
# snapshots measured: create a snapshot, then a stale one, and a missing one
mkdir -p "$TMP/hv"
run "$TMP/h3.json" project.health "path=$TMP/sc/v1.scrape.json" "input=$TMP/hv"
check jq -e '(.data.components[]|select(.name=="snapshots")) | .measured==true and .points==0 and .why=="No snapshots of this project exist."' "$TMP/h3.json"
check jq -e '.data.score==75' "$TMP/h3.json"                       # (35+40+0)/100
: > "$TMP/hv/hero.20261001T090000Z.aaaaaaaaaaaa.aep"
run "$TMP/h4.json" project.health "path=$TMP/sc/v1.scrape.json" "input=$TMP/hv"
check jq -e '(.data.components[]|select(.name=="snapshots")) | .points==25' "$TMP/h4.json"
check jq -e '.data.score==100' "$TMP/h4.json"
: > "$TMP/hv/Hero.20260928T090000Z.bbbbbbbbbbbb.AEP"               # case-insensitive, but the newer one above wins
run "$TMP/h5.json" project.health "path=$TMP/sc/v2.scrape.json" "input=$TMP/hv"   # newest snapshot is 1.5 h older than the v2 scrape
check jq -e '(.data.components[]|select(.name=="snapshots")) | .points==15' "$TMP/h5.json"
# record + trend
run "$TMP/r1.json" project.health "path=$TMP/sc/v1.scrape.json" "format=record"
run "$TMP/r2.json" project.health "path=$TMP/sc/v2.scrape.json" "format=record"
check jq -e '.data.recorded==true and .data.trend==[100,73]' "$TMP/r2.json"
run "$TMP/r2b.json" project.health "path=$TMP/sc/v2.scrape.json" "format=record"       # idempotent: same receipt, same row
check jq -e '.data.trend==[100,73]' "$TMP/r2b.json"
run "$TMP/ra.json" project.health "format=all"
check jq -e '.data.schema=="MJ_HEALTH_TRENDS_1" and (.data.projects|length)==1 and .data.projects[0].series==[100,73] and .data.projects[0].direction=="worsening" and .data.projects[0].latestScore==73' "$TMP/ra.json"
run "$TMP/rs.json" project.health "path=$TMP/sc/v1.scrape.json"                         # plain score never writes
check jq -e '.data.recorded==false and .data.trend==null' "$TMP/rs.json"
run "$TMP/rb.json" project.health "path=$TMP/sc/v1.scrape.json" "format=bogus"
check jq -e '.error.code=="INVALID_ARGUMENT"' "$TMP/rb.json"
rm -rf "$TMP/store"; run "$TMP/re.json" project.health "format=all"
check jq -e '.error.code=="STORE_EMPTY"' "$TMP/re.json"

# ================= #33 lint teaches =================
run "$TMP/lt.json" expression.lint "path=$TMP/sc/v2.scrape.json"
check jq -e '.data.findings[0] | .code=="E001" and (.teach.why|length)>40 and (.teach.fix|length)>10 and (.message|test("does not exist"))' "$TMP/lt.json"
check jq -e '.data.teaching.E001 | (.before|length)>5 and (.after|length)>5' "$TMP/lt.json"
cat > "$TMP/sc/lintall.json" <<J
{"schema":"MJ_PROJECT_SCRAPE_1","scraperVersion":"1.0","projectPath":"/p/l.aep","projectName":"l.aep","scrapedAt":"2026-10-01T00:00:00Z","aeVersion":"24.0","numItems":1,"fonts":[],"footage":[],
 "comps":[{"name":"M","id":1,"width":10,"height":10,"pixelAspect":1,"frameRate":24,"duration":1,"numLayers":1,"layers":[
  {"name":"L","index":1,"type":"AVLayer","sourceName":"","sourcePath":"","effects":[],"expressions":[
   {"propertyPath":"a","expression":"thisComp.layer(\"Nope\").position"},
   {"propertyPath":"b","expression":"effect(\"Nope\")(1)"},
   {"propertyPath":"c","expression":"for (i=0;i<9;i++){ sampleImage([i,0],[1,1],true,time); }"},
   {"propertyPath":"d","expression":"footage(\"/Users/me/x.json\").sourceData"},
   {"propertyPath":"e","expression":"$(python3 -c "import sys; print(chr(101)+chr(118)+chr(97)+chr(108))")(\"x\")"},
   {"propertyPath":"f","expression":"$(python3 -c "print('x'*2100)")"}]}]}]}
J
python3 - "$TMP/sc/lintall.json" <<'PY'
import json, sys
p = sys.argv[1]; raw = open(p).read()
# the shell $(...) substitutions above were written by the shell heredoc; rebuild the two special expressions explicitly
d = json.loads(raw.replace('$(', '(')) if False else None
PY
python3 - "$TMP/sc/lintall.json" <<'PY'
import json, sys
p = sys.argv[1]
d = {"schema": "MJ_PROJECT_SCRAPE_1", "scraperVersion": "1.0", "projectPath": "/p/l.aep", "projectName": "l.aep", "scrapedAt": "2026-10-01T00:00:00Z", "aeVersion": "24.0", "numItems": 1, "fonts": [], "footage": [],
     "comps": [{"name": "M", "id": 1, "width": 10, "height": 10, "pixelAspect": 1, "frameRate": 24, "duration": 1, "numLayers": 1, "layers": [
        {"name": "L", "index": 1, "type": "AVLayer", "sourceName": "", "sourcePath": "", "effects": [], "expressions": [
          {"propertyPath": "a", "expression": 'thisComp.layer("Nope").position'}, {"propertyPath": "b", "expression": 'effect("Nope")(1)'},
          {"propertyPath": "c", "expression": 'for (i=0;i<9;i++){ sampleImage([i,0],[1,1],true,time); }'},
          {"propertyPath": "d", "expression": 'footage("/Users/me/x.json").sourceData'},
          {"propertyPath": "e", "expression": "ev" + "al(\"x\")"}, {"propertyPath": "f", "expression": "x" * 2100}]}]}]}
json.dump(d, open(p, "w"))
PY
run "$TMP/la.json" expression.lint "path=$TMP/sc/lintall.json"
check jq -e '[.data.findings[].code]|sort==["E001","E002","I001","W001","W002","W003"]' "$TMP/la.json"
check jq -e '[.data.findings[] | (.teach.why|length)>30 and (.teach.fix|length)>10] | all' "$TMP/la.json"
check jq -e '.data.teaching|keys==["E001","E002","I001","W001","W002","W003"]' "$TMP/la.json"
check jq -e '[.data.findings[] | {code,severity,comp,layer,propertyPath,message}|keys|length]|all(.==6)' "$TMP/la.json"      # the stable fields are unchanged

# ================= #28 explain =================
EXPL="$ROOT/scripts/terminal/mj_explain.py"
explain(){ python3 "$EXPL" "$1"; }
run "$TMP/x_ing.json" project.ingest "path=$TMP/sc/v2.scrape.json"
explain "$TMP/x_ing.json" > "$TMP/x1.txt"
check grep -q 'hero.aep (After Effects 24.6.0)' "$TMP/x1.txt"
check grep -Eq '2 comps, 3 layers' "$TMP/x1.txt"
check grep -q 'Missing: logo.psd' "$TMP/x1.txt"
explain "$TMP/la.json" > "$TMP/x2.txt"
check grep -q 'Found 6 problems: 2 errors, 3 warnings, 1 note' "$TMP/x2.txt"
check grep -q 'Why it matters:' "$TMP/x2.txt"
check grep -q 'Before:' "$TMP/x2.txt"
check bash -c "! grep -Eq '^[[:space:]]*[{\"]' '$TMP/x2.txt'"             # plain language: no JSON lines
explain "$TMP/df.json" > "$TMP/x3.txt"
check grep -q 'frame rate 24 -> 30' "$TMP/x3.txt"
check grep -Eq '1 comps? added' "$TMP/x3.txt"
explain "$TMP/h2.json" > "$TMP/x4.txt"
check grep -q 'health: 73 out of 100 (needs a look)' "$TMP/x4.txt"
check grep -q 'footage: lost 12 of 35 points' "$TMP/x4.txt"
check grep -q 'Score formula version 1' "$TMP/x4.txt"
explain "$TMP/r2.json" > "$TMP/x4b.txt"
check grep -q 'Trend over 2 snapshots: getting worse' "$TMP/x4b.txt"
explain "$TMP/dfs.json" > "$TMP/x5.txt"
check grep -q 'No differences' "$TMP/x5.txt"
run "$TMP/x_err.json" file.inspect "path=relative"
explain "$TMP/x_err.json" > "$TMP/x6.txt"
check grep -q 'That did not work (INVALID_PATH)' "$TMP/x6.txt"
check grep -q 'What to do: Pass a full path' "$TMP/x6.txt"
check grep -q 'Nothing was changed' "$TMP/x6.txt"
run "$TMP/x_w.json" deps.graph "path=$TMP/sc/v2.scrape.json"
explain "$TMP/x_w.json" > "$TMP/x7.txt"
check grep -q 'uses' "$TMP/x7.txt"
printf '{"schema":"WHO_KNOWS"}' > "$TMP/x_unk.json"
set +e; python3 "$EXPL" "$TMP/x_unk.json" > "$TMP/x8.txt" 2>&1; r=$?; python3 "$EXPL" "$TMP/nope" >/dev/null 2>&1; r2=$?; echo 'not json' | python3 "$EXPL" - >/dev/null 2>&1; r3=$?; set -e
check test "$r" = 65 -a "$r2" = 66 -a "$r3" = 65
check grep -q 'do not recognise' "$TMP/x8.txt"
cat "$TMP/x_ing.json" | python3 "$EXPL" - | head -1 | grep -q 'hero.aep' && pass=$((pass+1)) || { echo "FAIL: explain stdin" >&2; fail=$((fail+1)); }
# warnings from the response are shown to a person
run "$TMP/x_wr.json" project.ingest "path=$TMP/scrape_trunc.json"
python3 -c "
import json; d=json.load(open('$TMP/sc/v2.scrape.json')); d['compsTruncated']=True; json.dump(d, open('$TMP/scrape_trunc.json','w'))"
run "$TMP/x_wr.json" project.ingest "path=$TMP/scrape_trunc.json"
explain "$TMP/x_wr.json" > "$TMP/x9.txt"
check grep -q 'Heads up:' "$TMP/x9.txt"

echo "Human CLI tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
