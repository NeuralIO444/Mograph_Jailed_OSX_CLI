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
# has: like `grep`, but reads all of stdin first, so `producer | has -q x` cannot die of SIGPIPE under pipefail
has(){ local _in; _in=$(cat); grep "$@" <<<"$_in"; }
mjz(){ MJ_CLI="$CLI" zsh -f -c "source '$ROOT/scripts/shell/mj-cli.zsh'; $1"; }

# ================= #29 config =================
check bash -c "MJ_CONFIG='$TMP/cfg/config' zsh -f -c \"source '$ROOT/scripts/shell/mj-config.zsh'; mj_config_get versions_dir\" | grep -q 'AE_Versions'"
mjz "mj config set versions_dir '$TMP/v'" | has -q 'saved' && pass=$((pass+1)) || { echo "FAIL: config set" >&2; fail=$((fail+1)); }
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
cat "$TMP/x_ing.json" | python3 "$EXPL" - | head -1 | has -q 'hero.aep' && pass=$((pass+1)) || { echo "FAIL: explain stdin" >&2; fail=$((fail+1)); }
# warnings from the response are shown to a person
run "$TMP/x_wr.json" project.ingest "path=$TMP/scrape_trunc.json"
python3 -c "
import json; d=json.load(open('$TMP/sc/v2.scrape.json')); d['compsTruncated']=True; json.dump(d, open('$TMP/scrape_trunc.json','w'))"
run "$TMP/x_wr.json" project.ingest "path=$TMP/scrape_trunc.json"
explain "$TMP/x_wr.json" > "$TMP/x9.txt"
check grep -q 'Heads up:' "$TMP/x9.txt"

# ================= #31 snapshot hooks =================
render_watcher(){ mkdir -p "$2"; sed -e "s|__WATCH_DIR__|$1|g" -e "s|__VERSIONS_DIR__|$2|g" -e "s|__CLI_PATH__|$3|g" "$ROOT/watcher/watch-fire.zsh" > "$2/fire.zsh"; echo "$2/fire.zsh"; }
mkdir -p "$TMP/hk/watch" "$TMP/hk/my hooks"
printf 'hook-project' > "$TMP/hk/watch/Hooked.aep"
cat > "$TMP/hk/my hooks/good hook.sh" <<STUB
#!/bin/sh
echo "\$1" >> "$TMP/hk/calls.txt"
echo "\$MJ_SNAPSHOT_RECEIPT|\$MJ_SNAPSHOT_PATH|\$MJ_SOURCE_PATH|\$MJ_SNAPSHOT_SHA256" >> "$TMP/hk/env.txt"
echo "hook stdout line"
STUB
chmod 700 "$TMP/hk/my hooks/good hook.sh"
FIRE=$(render_watcher "$TMP/hk/watch" "$TMP/hk/v1" "$CLI")
MJ_POST_SNAPSHOT_HOOK="$TMP/hk/my hooks/good hook.sh" zsh -f "$FIRE"; rc=$?
check test "$rc" = 0
check test "$(wc -l < "$TMP/hk/calls.txt" | tr -d ' ')" = 1
RCPT=$(cat "$TMP/hk/calls.txt")
check test -f "$RCPT"
check bash -c "echo '$RCPT' | grep -q 'snapshot.json\$'"
check bash -c "cut -d'|' -f1 '$TMP/hk/env.txt' | grep -qx '$RCPT'"
check bash -c "cut -d'|' -f3 '$TMP/hk/env.txt' | grep -q 'Hooked.aep\$' && cut -d'|' -f4 '$TMP/hk/env.txt' | grep -Eq '^[0-9a-f]{64}\$'"
check grep -q 'hook ok: good hook.sh' "$TMP/hk/v1/watcher.log"
check grep -q 'hook stdout line' "$TMP/hk/v1/hook.log"
MJ_POST_SNAPSHOT_HOOK="$TMP/hk/my hooks/good hook.sh" zsh -f "$FIRE"                   # unchanged project: no new snapshot, no hook
check test "$(wc -l < "$TMP/hk/calls.txt" | tr -d ' ')" = 1
check grep -q 'unchanged, skipped' "$TMP/hk/v1/watcher.log"
# a failing hook is logged and cannot hurt the snapshot or the watcher
printf '#!/bin/sh\nexit 3\n' > "$TMP/hk/fail.sh"; chmod 700 "$TMP/hk/fail.sh"
FIRE2=$(render_watcher "$TMP/hk/watch" "$TMP/hk/v2" "$CLI")
MJ_POST_SNAPSHOT_HOOK="$TMP/hk/fail.sh" zsh -f "$FIRE2"; rc=$?
check test "$rc" = 0
check grep -q 'snapshot ok:' "$TMP/hk/v2/watcher.log"
check grep -q 'hook FAILED (exit 3) (snapshot is safe)' "$TMP/hk/v2/watcher.log"
check test "$(ls "$TMP"/hk/v2/Hooked.*.aep | wc -l | tr -d ' ')" = 1
# a hook that hangs is stopped at the timeout, children included
printf '#!/bin/sh\nsleep 300 &\nsleep 300\n' > "$TMP/hk/hang.sh"; chmod 700 "$TMP/hk/hang.sh"
FIRE3=$(render_watcher "$TMP/hk/watch" "$TMP/hk/v3" "$CLI")
START=$(date +%s)
MJ_POST_SNAPSHOT_HOOK="$TMP/hk/hang.sh" MJ_HOOK_TIMEOUT=2 zsh -f "$FIRE3"; rc=$?
check test "$rc" = 0 -a "$(( $(date +%s) - START ))" -lt 20
check grep -q 'hook timed out after 2s' "$TMP/hk/v3/watcher.log"
check grep -q 'snapshot ok:' "$TMP/hk/v3/watcher.log"
sleep 1; check bash -c "! pgrep -f 'sleep 300' >/dev/null"
# unsafe hooks are refused (and logged), never run
refuse(){ # refuse <hook path> <expected reason> <dir>
  local F; F=$(render_watcher "$TMP/hk/watch" "$3" "$CLI"); MJ_POST_SNAPSHOT_HOOK="$1" zsh -f "$F"
  grep -q "hook refused ($2)" "$3/watcher.log" && grep -q 'snapshot ok:' "$3/watcher.log"
}
printf '#!/bin/sh\ntouch "%s/hk/RAN"\n' "$TMP" > "$TMP/hk/evil.sh"
chmod 775 "$TMP/hk/evil.sh";                          check refuse "$TMP/hk/evil.sh" "writable by others" "$TMP/hk/r1"
chmod 600 "$TMP/hk/evil.sh";                          check refuse "$TMP/hk/evil.sh" "not executable" "$TMP/hk/r2"
check refuse "relative/hook.sh" "path is not absolute" "$TMP/hk/r3"
check refuse "$TMP/hk/does-not-exist.sh" "not a file" "$TMP/hk/r4"
check refuse "$TMP/hk" "not a file" "$TMP/hk/r5"
check test ! -e "$TMP/hk/RAN"
# the hook comes from the config file too; the environment wins; the path is never run through a shell
mjz "mj config set post_snapshot_hook '$TMP/hk/my hooks/good hook.sh'" >/dev/null
: > "$TMP/hk/calls.txt"
FIRE4=$(render_watcher "$TMP/hk/watch" "$TMP/hk/v4" "$CLI")
zsh -f "$FIRE4"
check test "$(wc -l < "$TMP/hk/calls.txt" | tr -d ' ')" = 1
mkdir -p "$TMP/hk/inj"; printf '#!/bin/sh\nexit 0\n' > "$TMP/hk/inj/a;touch INJECTED;b.sh"; chmod 700 "$TMP/hk/inj/a;touch INJECTED;b.sh"
FIRE5=$(render_watcher "$TMP/hk/watch" "$TMP/hk/v5" "$CLI")
( cd "$TMP/hk/inj" && MJ_POST_SNAPSHOT_HOOK="$TMP/hk/inj/a;touch INJECTED;b.sh" zsh -f "$FIRE5" )
check grep -q 'hook ok: a;touch INJECTED;b.sh' "$TMP/hk/v5/watcher.log"
check test ! -e "$TMP/hk/inj/INJECTED" -a ! -e "$TMP/hk/INJECTED"
mjz "mj config unset post_snapshot_hook" >/dev/null

# ================= #26 human commands =================
export MJ_CONFIG="$TMP/hcfg/config"
mkdir -p "$TMP/hv/versions" "$TMP/hv/receipts" "$TMP/hv/projects/Spring Promo" "$TMP/hv/projects/Other"
printf 'spring-promo-v1' > "$TMP/hv/projects/Spring Promo/Spring Promo.aep"
printf 'other-project' > "$TMP/hv/projects/Other/Other_Project.aep"
printf 'second' > "$TMP/hv/projects/Other/Other_Second.aep"
mjz "mj config set versions_dir '$TMP/hv/versions'" >/dev/null
mjz "mj config set receipts_dir '$TMP/hv/receipts'" >/dev/null
mjz "mj config set watch_dir '$TMP/hv/projects'" >/dev/null
mjz "mj config set cli '$CLI'" >/dev/null
# snapshot by name, plain language out
mjz "mj snapshot 'Spring Promo'" > "$TMP/hs1.txt"
check grep -q 'Saved a verified copy of Spring Promo.aep' "$TMP/hs1.txt"
check test "$(ls "$TMP"/hv/versions/Spring\ Promo.*.aep | wc -l | tr -d ' ')" = 1
mjz "mj snapshot 'Spring Promo'" > "$TMP/hs2.txt"
check grep -q 'Nothing to save: Spring Promo.aep has not changed' "$TMP/hs2.txt"
mjz "mj snapshot '$TMP/hv/projects/Other/Other_Project.aep'" >/dev/null                 # by path
check test "$(ls "$TMP"/hv/versions/Other_Project.*.aep | wc -l | tr -d ' ')" = 1
set +e; mjz "mj snapshot Other_" > "$TMP/hs3.txt" 2>&1; r1=$?; mjz "mj snapshot nonexistent" > "$TMP/hs4.txt" 2>&1; r2=$?; mjz "mj snapshot" >/dev/null 2>&1; r3=$?; set -e
check test "$r1" = 65 -a "$r2" = 66 -a "$r3" = 64
check grep -q 'matches more than one project' "$TMP/hs3.txt"
check grep -q 'Other_Second.aep' "$TMP/hs3.txt"
check grep -q 'no project found for "nonexistent"' "$TMP/hs4.txt"
# versions
mjz "mj versions" > "$TMP/hv1.txt"
check grep -Eq 'Spring Promo +20[0-9-]+ [0-9:]+ +[0-9.]+ MB +[0-9a-f]{12}' "$TMP/hv1.txt"
mjz "mj versions spring" > "$TMP/hv2.txt"; check bash -c "grep -q 'Spring Promo' '$TMP/hv2.txt' && ! grep -q Other_Project '$TMP/hv2.txt'"
mjz "mj versions nothing-like-this" | has -q 'No versions matching' && pass=$((pass+1)) || { echo "FAIL: versions none" >&2; fail=$((fail+1)); }
# lint / health / diff / explain from remembered receipts
cp "$TMP/sc/v1.scrape.json" "$TMP/hv/receipts/hero.20261001T090000Z.scrape.json"
cp "$TMP/sc/v2.scrape.json" "$TMP/hv/receipts/hero.20261001T103000Z.scrape.json"
touch -t 202610010900 "$TMP/hv/receipts/hero.20261001T090000Z.scrape.json"; touch -t 202610011030 "$TMP/hv/receipts/hero.20261001T103000Z.scrape.json"
mjz "mj lint last" > "$TMP/hl.txt"
check grep -q 'Found 1 problem: 1 error' "$TMP/hl.txt"
check grep -q 'Why it matters:' "$TMP/hl.txt"
check bash -c "! grep -Eq '^[[:space:]]*[{\"]' '$TMP/hl.txt'"
mjz "mj health last" > "$TMP/hh.txt"
check grep -q 'health: 55 out of 100 (at risk)' "$TMP/hh.txt"
check grep -q 'snapshots: lost 25 of 25 points. No snapshots of this project exist' "$TMP/hh.txt"
check test ! -e "$TMP/store/index.sqlite"                                          # reading a score never writes
mjz "mj health last --record" > "$TMP/hh2.txt"
check test -e "$TMP/store/index.sqlite"
mjz "mj health '$TMP/hv/receipts/hero.20261001T090000Z.scrape.json' --record" > "$TMP/hh3.txt"
check grep -q 'Trend over 2 snapshots' "$TMP/hh3.txt"
mjz "mj diff last" > "$TMP/hd.txt"
check grep -q 'frame rate 24 -> 30' "$TMP/hd.txt"
check grep -q 'hero.20261001T090000Z' "$TMP/hd.txt"                                 # older first
mjz "mj diff '$TMP/hv/receipts/hero.20261001T090000Z.scrape.json' '$TMP/hv/receipts/hero.20261001T103000Z.scrape.json'" | has -q 'frame rate 24 -> 30' && pass=$((pass+1)) || { echo "FAIL: diff paths" >&2; fail=$((fail+1)); }
mjz "mj explain '$TMP/hv/receipts/hero.20261001T103000Z.scrape.json'" | has -q 'Scrape of hero.aep' && pass=$((pass+1)) || { echo "FAIL: explain file" >&2; fail=$((fail+1)); }
# doctor in plain language, healthy and not
mjz "mj doctor" | has -q 'This Mac is ready' && pass=$((pass+1)) || { echo "FAIL: doctor ok" >&2; fail=$((fail+1)); }
MJ_TEST_MISSING_CAPS="python3" mjz "mj doctor" > "$TMP/hdoc.txt" 2>&1 || true
# python3 itself is hidden from the runtime, but the explainer still needs a real one
check grep -q 'python3 is missing and blocks' "$TMP/hdoc.txt"
check grep -q 'What to do: Used by the project' "$TMP/hdoc.txt"
# errors are explained, with the next step, and set a non-zero exit
set +e; mjz "mj snapshot /nonexistent/x.aep" > "$TMP/herr.txt" 2>&1; r=$?; set -e
check test "$r" -ne 0
# not configured: clear hints, never a stack trace
export MJ_CONFIG="$TMP/hcfg/empty"
set +e
HOME="$TMP/emptyhome" mjz "mj versions" > "$TMP/n1.txt" 2>&1; n1=$?
HOME="$TMP/emptyhome" mjz "mj lint last" > "$TMP/n2.txt" 2>&1; n2=$?
HOME="$TMP/emptyhome" mjz "mj watch on" > "$TMP/n3.txt" 2>&1; n3=$?
set -e
check test "$n1" = 66 -a "$n2" = 66 -a "$n3" = 66
check grep -q 'mj config set versions_dir' "$TMP/n1.txt"
check grep -q 'mj config set receipts_dir' "$TMP/n2.txt"
check grep -q 'mj config set watch_dir' "$TMP/n3.txt"
# watch on/off call the real installers with the remembered folders (stubs here: nothing is installed)
export MJ_CONFIG="$TMP/hcfg/config"
mkdir -p "$TMP/fake/scripts/shell" "$TMP/fake/scripts/terminal" "$TMP/fake/tools"
cp "$ROOT/scripts/shell/mj-cli.zsh" "$ROOT/scripts/shell/mj-config.zsh" "$TMP/fake/scripts/shell/"; cp "$ROOT/scripts/terminal/mj_explain.py" "$TMP/fake/scripts/terminal/"
printf '#!/bin/zsh -f\nprint -r -- "INSTALL $*" >> "%s/fake/calls.txt"\n' "$TMP" > "$TMP/fake/tools/watch-install.zsh"
printf '#!/bin/zsh -f\nprint -r -- "UNINSTALL $*" >> "%s/fake/calls.txt"\n' "$TMP" > "$TMP/fake/tools/watch-uninstall.zsh"
MJ_CLI="$CLI" zsh -f -c "source '$TMP/fake/scripts/shell/mj-cli.zsh'; mj watch on; mj watch off; mj watch bogus" >/dev/null 2>&1 || true
check grep -qx "INSTALL --yes $TMP/hv/projects $TMP/hv/versions" "$TMP/fake/calls.txt"
check grep -qx "UNINSTALL --yes" "$TMP/fake/calls.txt"
MJ_CLI="$CLI" zsh -f -c "source '$TMP/fake/scripts/shell/mj-cli.zsh'; mj watch status" > "$TMP/ws.txt" 2>&1 || true
check grep -Eq 'Watcher: (on|off)' "$TMP/ws.txt"
unset MJ_CONFIG; export MJ_CONFIG="$TMP/cfg/config"

# ================= #30 completions =================
# Drive the completer with stubbed completion primitives and read what it offers.
complete(){ # complete <word index> <words...>  -> offered words, one per line, and FILES markers
  local cur="$1"; shift
  MJ_CLI="$CLI" zsh -f -c "
    source '$ROOT/scripts/shell/mj-cli.zsh'
    compadd() { local arr=0; while [ \$# -gt 0 ]; do case \$1 in -a) arr=1 ;; -S|-P|-J) shift ;; -*) ;; *) if (( arr )); then print -rl -- \"\${(P@)1}\"; else print -r -- \"\$1\"; fi ;; esac; shift; done }
    _files() { print -r -- FILES\${*:+ \$*}; }
    compset() { return 0; }
    typeset -a words; words=(mj $*)
    CURRENT=$cur; PREFIX=\"\${words[CURRENT]:-}\"
    _mj_complete
  "
}
complete 2 "" > "$TMP/c1.txt"
for w in snapshot versions lint health diff explain watch doctor config notify status ui file.inspect loop.seams trace.asset project.health; do check grep -qx "$w" "$TMP/c1.txt"; done
check grep -qx "ae.render" "$TMP/c1.txt"
complete 3 watch "" | has -qx on && complete 3 watch "" | has -qx status && pass=$((pass+2)) || { echo "FAIL: watch completion" >&2; fail=$((fail+1)); }
check test "$(complete 3 notify "" | sort | tr '\n' ' ')" = "off on status test "
complete 3 config "" > "$TMP/c2.txt"; for w in show path get set unset; do check grep -qx "$w" "$TMP/c2.txt"; done
complete 4 config set "" > "$TMP/c3.txt"; for w in versions_dir receipts_dir watch_dir cli post_snapshot_hook; do check grep -qx "$w" "$TMP/c3.txt"; done
check grep -q "FILES" <(complete 5 config set versions_dir "")
check grep -q "FILES -g" <(complete 3 snapshot "")
complete 3 lint "" > "$TMP/c4.txt"; check grep -qx last "$TMP/c4.txt"; check grep -q FILES "$TMP/c4.txt"
complete 3 health "" | has -qx -- --record && pass=$((pass+1)) || { echo "FAIL: health completion" >&2; fail=$((fail+1)); }
complete 3 loop.seams "" > "$TMP/c5.txt"; for w in path minFrames maxResults; do check grep -qx "$w" "$TMP/c5.txt"; done      # operation args come from the runtime
complete 3 golden.check "" > "$TMP/c6.txt"; check grep -qx threshold "$TMP/c6.txt"
check test -z "$(complete 3 doctor "")"                                                                                  # commands without arguments offer nothing
check test -z "$(complete 3 status "")"

# ================= #15 / #27 installer =================
( cd "$ROOT" && sh scripts/make-manifest.sh >/dev/null )
mkzip(){ # mkzip <out.zip> [tamper|nomanifest]
  python3 - "$ROOT" "$1" "${2:-}" <<'PY'
import os, subprocess, sys, zipfile
root, out, mode = sys.argv[1:4]
files = subprocess.check_output(["git", "ls-files"], cwd=root, text=True).split("\n")
if "SHA256SUMS" not in files: files.append("SHA256SUMS")      # not tracked until first committed
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        p = os.path.join(root, f)
        if not f or not os.path.isfile(p): continue
        if f == "SHA256SUMS" and mode == "nomanifest": continue
        data = open(p, "rb").read()
        if mode == "tamper" and f == "src/core/constants.zsh": data += b"\n# injected\n"
        z.writestr("Mograph_Jailed_OSX_CLI-test/" + f, data)
PY
}
mkdir -p "$TMP/inst" "$TMP/inst/home"
mkzip "$TMP/inst/good.zip"; mkzip "$TMP/inst/bad.zip" tamper; mkzip "$TMP/inst/old.zip" nomanifest; printf 'not a zip' > "$TMP/inst/junk.zip"
GOODSHA=$(shasum -a 256 "$TMP/inst/good.zip" | awk '{print $1}')
install_with(){ # install_with <zip> <root> [extra env assignments...]
  local z="$1" r="$2"; shift 2
  env HOME="$TMP/inst/home" MJ_INSTALL_ALLOW_NONMAC=1 MJ_INSTALL_YES=1 MJ_INSTALL_ROOT="$r" MJ_INSTALL_ZIP_URL="file://$z" "$@" zsh -f "$ROOT/tools/install-designer.zsh" </dev/null
}
set +e
install_with "$TMP/inst/good.zip" "$TMP/inst/r1" > "$TMP/inst/o1.txt" 2>&1; i1=$?
set -e
check test "$i1" = 0
check test -f "$TMP/inst/r1/dist/mograph-jailed.zsh"
check grep -q 'every file matches its checksum' "$TMP/inst/o1.txt"
check grep -q "download SHA-256: $GOODSHA" "$TMP/inst/o1.txt"
check grep -q 'it runs' "$TMP/inst/o1.txt"
check grep -q 'mj ui' "$TMP/inst/o1.txt"                                       # farewell teaches the everyday commands
check test ! -e "$TMP/inst/home/Library/LaunchAgents" -a ! -e "$TMP/inst/home/.config"   # scripted install adds no extras, no watcher, no config
check bash -c "! grep -q 'Open the live dashboard' '$TMP/inst/o1.txt'"       # and never launches the dashboard
# pinned hash: right -> proceeds, wrong -> refuses with nothing installed
set +e
install_with "$TMP/inst/good.zip" "$TMP/inst/r2" MJ_INSTALL_SHA256="$GOODSHA" > "$TMP/inst/o2.txt" 2>&1; i2=$?
install_with "$TMP/inst/good.zip" "$TMP/inst/r3" MJ_INSTALL_SHA256="$(printf '0%.0s' $(seq 1 64))" > "$TMP/inst/o3.txt" 2>&1; i3=$?
set -e
check test "$i2" = 0 -a -f "$TMP/inst/r2/dist/mograph-jailed.zsh"
check grep -q 'matches the SHA-256 you pinned' "$TMP/inst/o2.txt"
check test "$i3" -ne 0 -a ! -e "$TMP/inst/r3"
check grep -q 'does not match the SHA-256 you pinned' "$TMP/inst/o3.txt"
# a file changed after the manifest was made: refused, nothing copied
set +e; install_with "$TMP/inst/bad.zip" "$TMP/inst/r4" > "$TMP/inst/o4.txt" 2>&1; i4=$?; set -e
check test "$i4" -ne 0 -a ! -e "$TMP/inst/r4"
check grep -q 'do not match their checksums' "$TMP/inst/o4.txt"
# an older release with no checksum list still installs, with a clear notice
set +e; install_with "$TMP/inst/old.zip" "$TMP/inst/r5" > "$TMP/inst/o5.txt" 2>&1; i5=$?; set -e
check test "$i5" = 0 -a -f "$TMP/inst/r5/dist/mograph-jailed.zsh"
check grep -q 'no checksum list' "$TMP/inst/o5.txt"
# garbage download: refused
set +e; install_with "$TMP/inst/junk.zip" "$TMP/inst/r6" > "$TMP/inst/o6.txt" 2>&1; i6=$?; set -e
check test "$i6" -ne 0 -a ! -e "$TMP/inst/r6"
# existing folder: untouched unless replacement is explicitly allowed
mkdir -p "$TMP/inst/r7"; printf 'mine' > "$TMP/inst/r7/keep.txt"
set +e; install_with "$TMP/inst/good.zip" "$TMP/inst/r7" > "$TMP/inst/o7.txt" 2>&1; i7=$?; set -e
check test "$i7" -ne 0 -a "$(cat "$TMP/inst/r7/keep.txt")" = mine -a ! -e "$TMP/inst/r7/dist"
set +e; install_with "$TMP/inst/good.zip" "$TMP/inst/r7" MJ_INSTALL_REPLACE=1 > "$TMP/inst/o8.txt" 2>&1; i8=$?; set -e
check test "$i8" = 0 -a -f "$TMP/inst/r7/dist/mograph-jailed.zsh"
# the installed copy works
check bash -c "printf 'MOGRAPHJAILED_REQUEST 1\nrequestId=i\ncommand=system.probe\n' | zsh -f '$TMP/inst/r1/dist/mograph-jailed.zsh' --request - | grep -q '\"ok\":true'"
# the manifest in the repo is current and covers the runtime
check sh "$ROOT/scripts/make-manifest.sh" --check
check grep -q ' dist/mograph-jailed.zsh$' "$ROOT/SHA256SUMS"
check bash -c "! grep -q ' SHA256SUMS\$' '$ROOT/SHA256SUMS'"

echo "Human CLI tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
