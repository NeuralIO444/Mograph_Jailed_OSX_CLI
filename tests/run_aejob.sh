#!/usr/bin/env bash
# After Effects jobs: project.extract, project.conform (plan and job), project.jobcheck, and mj extract /
# conform / ae. After Effects itself is not here: the runner's part is simulated by writing what it writes.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
RUNNER="$ROOT/integrations/after-effects/MographJailed_JobRunner.jsx"
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
export MJ_STORE_DIR="$TMP/store" MJ_AUDIT_DIR="$TMP/noaudit" MJ_TEST_APPS_DIR="$TMP/apps"
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
has(){ case "$(cat "$1")" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
b64(){ printf '%s' "$1" | base64 | tr -d '\n'; }
run(){
  local _out="$1" _cmd="$2"; shift 2
  local _f="$TMP/req_$RANDOM$RANDOM.txt"
  { printf 'MOGRAPHJAILED_REQUEST 1\nrequestId=t%s\ncommand=%s\n' "$RANDOM" "$_cmd"
    for _a in "$@"; do printf 'arg.%s=%s\n' "${_a%%=*}" "$(b64 "${_a#*=}")"; done; } > "$_f"
  set +e; "$CLI" --request "$_f" > "$_out" 2>/dev/null; echo $? > "$_out.rc"; set -e
}

mkdir -p "$TMP/AE/projects/Promo" "$TMP/AE/receipts" "$TMP/jobs"
AEP="$TMP/AE/projects/Promo/Promo.aep"; printf 'real project bytes' > "$AEP"
SCRAPE="$TMP/AE/receipts/promo.20261002T100000Z.scrape.json"
python3 - "$AEP" "$SCRAPE" <<'PY'
import json, sys
aep, out = sys.argv[1:3]
def L(i, name, typ="AVLayer", **kw):
    d = {"index": i, "name": name, "type": typ, "enabled": True, "hasVideo": True, "hasAudio": False, "sourceName": "", "sourcePath": "", "sourceId": 0,
         "sourceKind": "", "label": 1, "adjustment": False, "effects": [], "expressions": []}
    d.update(kw); return d
def E(path, text): return {"propertyPath": path, "expression": text}
doc = {"schema": "MJ_PROJECT_SCRAPE_1", "scraperVersion": "1.1", "projectPath": aep, "projectName": "Promo.aep", "scrapedAt": "2026-10-02T10:00:00Z",
       "aeVersion": "26.5.0", "numItems": 9, "fonts": [], "missingFonts": [],
       "comps": [
         {"id": 1, "name": "Main Comp", "label": 15, "folder": "", "width": 1920, "height": 1080, "pixelAspect": 1, "frameRate": 24, "duration": 10, "numLayers": 5, "layers": [
            L(1, "BG Solid", sourceId=20, sourceKind="solid"), L(2, "Grade", sourceId=21, sourceKind="solid", adjustment=True),
            L(3, "Lower Third", sourceId=2, sourceKind="comp", label=15), L(4, "Logo Null", "NullLayer"),
            L(5, "Title", "TextLayer", expressions=[E("Transform/Position", 'thisComp.layer("Logo Null").transform.position')])]},
         {"id": 2, "name": "Lower Third", "label": 15, "folder": "", "width": 1920, "height": 1080, "pixelAspect": 1, "frameRate": 24, "duration": 10, "numLayers": 2, "layers": [
            L(1, "Name", "TextLayer", expressions=[E("Transform/Opacity", 'comp("Main Comp").layer("Title").transform.opacity')]),
            L(2, "Bar", "ShapeLayer", expressions=[E("Transform/Position", "thisComp.layer('Nme').transform.position + [0, 10]")])]},
         {"id": 3, "name": "Unused Comp", "folder": "", "width": 640, "height": 360, "pixelAspect": 1, "frameRate": 24, "duration": 2, "numLayers": 0, "layers": []}],
       "footage": [{"id": 20, "name": "BG Solid", "kind": "solid", "folder": "Solids", "path": "", "missing": False, "hasVideo": True, "hasAudio": False},
                   {"id": 21, "name": "Grade", "kind": "solid", "folder": "", "path": "", "missing": False, "hasVideo": True, "hasAudio": False},
                   {"id": 22, "name": "music.wav", "kind": "footage", "folder": "", "path": "/x/music.wav", "missing": False, "hasVideo": False, "hasAudio": True},
                   {"id": 23, "name": "plate.mov", "kind": "footage", "folder": "", "path": "/x/plate.mov", "missing": False, "hasVideo": True, "hasAudio": True}]}
json.dump(doc, open(out, "w"))
old = dict(doc, scraperVersion="1.0"); json.dump(old, open(out.replace(".scrape.json", ".old.json"), "w"))
PY

# ---- conform: the plan (read-only) ----
run "$TMP/c.json" project.conform input="$SCRAPE"
check jq -e '.ok and .data.schema=="MJ_CONFORM_PLAN_1" and .data.job==null and .data.specName=="MographJailed studio default"' "$TMP/c.json"
check jq -e '.data.plan.itemRenames|map([.from,.to])==[["Main Comp","Main_Comp"],["Lower Third","PRE_Lower_Third"],["Unused Comp","Unused_Comp"]]' "$TMP/c.json"
check jq -e '[.data.plan.layerRenames[]|.to]==["SOL_BG_Solid","ADJ_Grade","PRE_Lower_Third","NULL_Logo_Null","TXT_Title","TXT_Name","SHP_Bar"]' "$TMP/c.json"
check jq -e '[.data.plan.layerRenames[]|.kind]==["solid","adjustment","precomp","null","text","text","shape"]' "$TMP/c.json"
check jq -e '.data.plan.expressions|map(.to)==["thisComp.layer(\"NULL_Logo_Null\").transform.position","comp(\"Main_Comp\").layer(\"TXT_Title\").transform.opacity"]' "$TMP/c.json"
check jq -e '.data.plan.suggestions==[{"comp":"Lower Third","layer":"Bar","path":"Transform/Position","reference":"Nme","suggestion":"Name","applied":false}]' "$TMP/c.json"
check jq -e '[.data.plan.layerLabels[]|[.layer,.from,.to]]==[["BG Solid",1,2],["Grade",1,5],["Logo Null",1,11],["Name",1,1]]|not' "$TMP/c.json"
check jq -e '[.data.plan.layerLabels[]|[.layer,.to]]==[["BG Solid",2],["Grade",5],["Logo Null",11],["Bar",8]]' "$TMP/c.json"
check jq -e '.data.plan.itemLabels==[{"id":1,"kind":"comp","name":"Main Comp","from":15,"to":9}]' "$TMP/c.json"
check jq -e '[.data.plan.moves[]|[.name,.to]]==[["Main Comp","01_Comps"],["Lower Third","02_Precomps"],["Unused Comp","01_Comps"],["BG Solid","04_Solids"],["Grade","04_Solids"],["music.wav","05_Audio"],["plate.mov","03_Footage"]]' "$TMP/c.json"
check jq -e '.data.changes==(.data.counts|add) and .data.sourceUnchanged' "$TMP/c.json"

# A custom spec: no prefixes for text, apply close-match fixes, keep spaces, no folders.
printf '# house\nname = House\nlayerPrefix.text =\nspaces = keep\nfixBrokenRefs = apply\nfolder.mainComps =\nfolder.precomps =\nfolder.footage =\nfolder.solids =\nfolder.audio =\n' > "$TMP/house.spec"
run "$TMP/c2.json" project.conform input="$SCRAPE" spec="$TMP/house.spec"
check jq -e '.data.specName=="House" and .data.counts.moves==0 and ([.data.plan.layerRenames[]|.to]|index("Title"))==null' "$TMP/c2.json"
check jq -e '(.data.plan.expressions[]|select(.layer=="Bar")|.to)=="thisComp.layer('"'"'Name'"'"').transform.position + [0, 10]"' "$TMP/c2.json"
check jq -e '.data.plan.suggestions[0].applied==true' "$TMP/c2.json"
check jq -e '[.data.plan.itemRenames[]|.to]==["PRE_Lower Third"]' "$TMP/c2.json"
# Idempotent: a project that already follows the spec plans no renames.
python3 - "$SCRAPE" "$TMP/done.json" "$TMP/c.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); plan = json.load(open(sys.argv[3]))["data"]["plan"]
ren = {(r["compId"], r["index"]): r["to"] for r in plan["layerRenames"]}; cren = {r["id"]: r["to"] for r in plan["itemRenames"]}
for c in d["comps"]:
    c["name"] = cren.get(c["id"], c["name"])
    for l in c["layers"]:
        l["name"] = ren.get((c["id"], l["index"]), l["name"]); l["expressions"] = []
json.dump(d, open(sys.argv[2], "w"))
PY
run "$TMP/c3.json" project.conform input="$TMP/done.json"
check jq -e '.data.counts.itemRenames==0 and .data.counts.layerRenames==0' "$TMP/c3.json"
# Old scrape: names and expressions only, said so.
run "$TMP/c4.json" project.conform input="${SCRAPE%.scrape.json}.old.json"
check jq -e '[.warnings[].code]|index("SCRAPE_TOO_OLD")!=null' "$TMP/c4.json"
# Bad specs
printf 'label.text = 99\n' > "$TMP/bad1.spec"; printf 'colour = red\n' > "$TMP/bad2.spec"; printf 'precompPrefix = "x\n' > "$TMP/bad3.spec"
for b in bad1 bad2 bad3; do run "$TMP/$b.json" project.conform input="$SCRAPE" spec="$TMP/$b.spec"; check jq -e '.error.code=="INVALID_SPEC"' "$TMP/$b.json"; check test "$(cat "$TMP/$b.json.rc")" = 65; done
run "$TMP/e.json" project.conform input="$SCRAPE" format=apply; check jq -e '.error.code=="INVALID_ARGUMENT"' "$TMP/e.json"
run "$TMP/e.json" project.conform input="$SCRAPE" format=job; check jq -e '.error.code=="MISSING_ARGUMENT"' "$TMP/e.json"

# ---- conform: a job ----
run "$TMP/j.json" project.conform input="$SCRAPE" format=job path="$AEP" output="$TMP/jobs" label=promo-conform
J="$TMP/jobs/promo-conform.mjjob"
check jq -e '.ok and .data.job.folder=="'"$J"'" and .data.job.result=="'"$J"'/result.aep"' "$TMP/j.json"
check cmp -s "$AEP" "$J/before.aep"
check test ! -e "$J/result.aep"
check jq -e '.schema=="MJ_AE_JOB_1" and .kind=="conform" and .work=="'"$J"'/before.aep" and .quietFlag=="'"$J"'/quiet" and (.conform.layerRenames|length)==7' "$J/plan.json"
check jq -e '.source.sha256=="'"$(shasum -a 256 "$AEP" | cut -d' ' -f1)"'"' "$J/plan.json"
check test "$(head -1 "$J/run.jsx")" = "#target aftereffects"
check grep -q '^var MJ_PLAN = {' "$J/run.jsx"
check cmp -s <(tail -n "$(wc -l < "$RUNNER")" "$J/run.jsx") "$RUNNER"            # the fixed runner, unmodified
check python3 -c "import sys; t=open(sys.argv[1]).read(); assert all(ord(c) < 128 for c in t.split('var MJ_PLAN = ')[1].split(';\n', 1)[0])" "$J/run.jsx"
run "$TMP/j2.json" project.conform input="$SCRAPE" format=job path="$AEP" output="$TMP/jobs" label=promo-conform
check jq -e '.error.code=="OUTPUT_EXISTS"' "$TMP/j2.json"; check test "$(cat "$TMP/j2.json.rc")" = 73
run "$TMP/j3.json" project.conform input="$SCRAPE" format=job path="$AEP" output="$TMP/jobs" label="../x"
check jq -e '.error.code=="INVALID_ARGUMENT"' "$TMP/j3.json"
python3 -c "
keys = ['precompPrefix', 'mainCompPrefix'] + ['layerPrefix.' + k for k in 'text shape solid null adjustment camera light precomp footage audio'.split()] + \
       ['label.' + k for k in 'text shape solid null adjustment camera light precomp footage audio mainComp precompItem'.split()] + \
       ['folder.' + k for k in 'mainComps precomps footage solids audio'.split()]
print('spaces = keep'); print('fixBrokenRefs = off'); [print(k + ' =') for k in keys]" > "$TMP/noop.spec"
run "$TMP/j4.json" project.conform input="$SCRAPE" spec="$TMP/noop.spec" format=job path="$AEP" output="$TMP/jobs" label=nothing
check jq -e '.ok and .data.job==null and ([.warnings[].code]|index("NOTHING_TO_DO"))!=null' "$TMP/j4.json"
check test ! -e "$TMP/jobs/nothing.mjjob"

# ---- extract ----
run "$TMP/x.json" project.extract path="$AEP" input="$SCRAPE" target=1 output="$TMP/jobs" label=main-only
check jq -e '.ok and .data.schema=="MJ_AE_JOB_PLAN_1" and .data.keeps.comps==["Lower Third","Main Comp"] and .data.keeps.footage==["BG Solid","Grade"]' "$TMP/x.json"
check jq -e '.data.removes=={"comps":1,"footage":2}' "$TMP/x.json"
check jq -e '.extract=={"compIds":[1],"compNames":["Main Comp"]} and .kind=="extract"' "$TMP/jobs/main-only.mjjob/plan.json"
run "$TMP/x2.json" project.extract path="$AEP" input="$SCRAPE" target=2,3 output="$TMP/jobs" label=two
check jq -e '.data.keeps.comps==["Lower Third","Unused Comp"] and .data.keeps.footage==[]' "$TMP/x2.json"
# Lower Third's Name layer reads comp("Main Comp"), which is not kept (found in a real After Effects run).
check jq -e '[.warnings[].code]==["EXTERNAL_REFERENCES"] and .data.externalReferences==[{"comp":"Lower Third","layer":"Name","path":"Transform/Opacity","references":"Main Comp"}]' "$TMP/x2.json"
check jq -e '.data.externalReferences==[] and ([.warnings[]?.code]|index("EXTERNAL_REFERENCES"))==null' "$TMP/x.json"
run "$TMP/xe1.json" project.extract path="$AEP" input="$SCRAPE" target=9 output="$TMP/jobs" label=e1; check jq -e '.error.code=="NOT_FOUND"' "$TMP/xe1.json"; check test ! -e "$TMP/jobs/e1.mjjob"
run "$TMP/xe2.json" project.extract path="$AEP" input="$SCRAPE" target='1;2' output="$TMP/jobs" label=e2; check jq -e '.error.code=="INVALID_ARGUMENT"' "$TMP/xe2.json"
run "$TMP/xe3.json" project.extract path="$AEP" input="$SCRAPE" target=1,1 output="$TMP/jobs" label=e3; check jq -e '.error.code=="INVALID_ARGUMENT"' "$TMP/xe3.json"
run "$TMP/xe4.json" project.extract path="$SCRAPE" input="$SCRAPE" target=1 output="$TMP/jobs" label=e4; check jq -e '.error.code=="INVALID_TARGET"' "$TMP/xe4.json"
cp "$AEP" "$TMP/Other.aep"
run "$TMP/xe5.json" project.extract path="$TMP/Other.aep" input="$SCRAPE" target=1 output="$TMP/jobs" label=e5
check jq -e '.error.code=="PROJECT_SCRAPE_MISMATCH"' "$TMP/xe5.json"; check test "$(cat "$TMP/xe5.json.rc")" = 65; check test ! -e "$TMP/jobs/e5.mjjob"
# Same file name in another folder (two clients each have a Main.aep) is a different project.
mkdir -p "$TMP/AE/projects/Other"; cp "$AEP" "$TMP/AE/projects/Other/Promo.aep"
run "$TMP/xe6.json" project.extract path="$TMP/AE/projects/Other/Promo.aep" input="$SCRAPE" target=1 output="$TMP/jobs" label=e6
check jq -e '.error.code=="PROJECT_SCRAPE_MISMATCH"' "$TMP/xe6.json"
run "$TMP/xe7.json" project.conform input="$SCRAPE" format=job path="$TMP/AE/projects/Other/Promo.aep" output="$TMP/jobs" label=e7
check jq -e '.error.code=="PROJECT_SCRAPE_MISMATCH"' "$TMP/xe7.json"
rm -rf "$TMP/AE/projects/Other"

# Cross-comp layer references follow only a certain comp (thisComp, or comp("..") directly before .layer)
python3 - "$SCRAPE" "$TMP/cross.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
main, lt = d["comps"][0], d["comps"][1]
lt["layers"].append({"index": 3, "name": "Color", "type": "NullLayer", "enabled": True, "hasVideo": True, "hasAudio": False, "sourceName": "", "sourcePath": "", "sourceId": 0, "sourceKind": "solid", "label": 1, "adjustment": False, "effects": [], "expressions": []})
main["layers"].append({"index": 6, "name": "Color", "type": "TextLayer", "enabled": True, "hasVideo": True, "hasAudio": False, "sourceName": "", "sourcePath": "", "sourceId": 0, "sourceKind": "", "label": 1, "adjustment": False, "effects": [], "expressions": [
    {"propertyPath": "Transform/Position", "expression": 'comp("Lower Third").layer("Color").transform.position'},
    {"propertyPath": "Transform/Scale", "expression": 'comp("Lower Third")\n  .layer("Color").transform.scale'},
    {"propertyPath": "Transform/Rotation", "expression": 'var c = comp("Lower Third"); c.layer("Color").transform.rotation'},
    {"propertyPath": "Transform/Opacity", "expression": 'thisComp.layer("Color").transform.opacity'}]})
json.dump(d, open(sys.argv[2], "w"))
PY
run "$TMP/cr.json" project.conform input="$TMP/cross.json"
check jq -e '[.data.plan.expressions[]|select(.layer=="Color")|.to]==["comp(\"PRE_Lower_Third\").layer(\"NULL_Color\").transform.position","comp(\"PRE_Lower_Third\")\n  .layer(\"NULL_Color\").transform.scale","var c = comp(\"PRE_Lower_Third\"); c.layer(\"Color\").transform.rotation","thisComp.layer(\"TXT_Color\").transform.opacity"]' "$TMP/cr.json"
check jq -e '[.warnings[].code]|index("DYNAMIC_REFERENCES")!=null' "$TMP/cr.json"
# Names that already match the spec are never the target of a collision rename
python3 - "$SCRAPE" "$TMP/res.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); m = d["comps"][0]
base = {"type": "TextLayer", "enabled": True, "hasVideo": True, "hasAudio": False, "sourceName": "", "sourcePath": "", "sourceId": 0, "sourceKind": "", "label": 1, "adjustment": False, "effects": [], "expressions": []}
m["layers"] = [dict(base, index=1, name="A"), dict(base, index=2, name="TXT_A")]
json.dump(d, open(sys.argv[2], "w"))
PY
run "$TMP/rs.json" project.conform input="$TMP/res.json"
check jq -e '[.data.plan.layerRenames[]|select(.comp=="Main Comp" or .comp=="Main")|[.from,.to]]==[["A","TXT_A_2"]]' "$TMP/rs.json"

# ---- jobcheck: before running, after a good run, and when something is off ----
X="$TMP/jobs/main-only.mjjob"
run "$TMP/k1.json" project.jobcheck path="$X"
check jq -e '.ok and .data.status=="notRun" and .data.complete==false and ([.data.checks[]|select(.ok)|.check]|sort)==["copyUnchanged","originalUnchanged"]' "$TMP/k1.json"
printf 'new project' > "$X/result.aep"
printf '{"schema":"MJ_AE_JOB_RESULT_1","status":"done","applied":1,"steps":1,"skipped":[],"errors":[],"itemsBefore":9,"itemsAfter":5}\n' > "$X/result.json"
run "$TMP/k2.json" project.jobcheck path="$X"
check jq -e '.data.status=="done" and .data.complete and .data.result=="'"$X"'/result.aep" and .data.itemsAfter==5' "$TMP/k2.json"
printf ' and more work' >> "$AEP"                                          # you kept working on the original: reported, not a failure
run "$TMP/k3.json" project.jobcheck path="$X"
check jq -e '.data.complete and ((.data.checks[]|select(.check=="originalUnchanged")|.ok)==false)' "$TMP/k3.json"
printf x >> "$X/before.aep"
run "$TMP/k4.json" project.jobcheck path="$X"
check jq -e '.data.complete==false and ((.data.checks[]|select(.check=="copyUnchanged")|.ok)==false)' "$TMP/k4.json"
python3 -c "import json,sys; p=json.load(open(sys.argv[1])); p['result']='/etc/passwd'; json.dump(p, open(sys.argv[1],'w'))" "$TMP/jobs/two.mjjob/plan.json"
run "$TMP/k5.json" project.jobcheck path="$TMP/jobs/two.mjjob"; check jq -e '.error.code=="INVALID_RECEIPT"' "$TMP/k5.json"
run "$TMP/k6.json" project.jobcheck path="$TMP"; check jq -e '.error.code=="INVALID_TARGET"' "$TMP/k6.json"

# ---- plain language ----
python3 "$ROOT/scripts/terminal/mj_explain.py" "$TMP/c.json" > "$TMP/c.txt"
check has "$TMP/c.txt" "Promo.aep against MographJailed studio default: 24 changes."
check has "$TMP/c.txt" "Main Comp / Logo Null -> NULL_Logo_Null"
check has "$TMP/c.txt" 'Suggestion: Lower Third / Transform/Position: "Nme" does not exist; did you mean "Name"?'
check has "$TMP/c.txt" "This is a plan; nothing was changed."
python3 "$ROOT/scripts/terminal/mj_explain.py" "$TMP/k2.json" > "$TMP/k.txt"
check has "$TMP/k.txt" 'The extract job "main-only" was applied.'
check has "$TMP/k.txt" "Project items: 9 before, 5 after."

# ---- mj extract / conform / ae (osascript and After Effects stood in for) ----
A="$TMP/apps/Adobe After Effects 2026"; mkdir -p "$A/Adobe After Effects 2026.app/Contents"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>26.5.0</string></dict></plist>\n' > "$A/Adobe After Effects 2026.app/Contents/Info.plist"
printf '#!/bin/sh\nexit 0\n' > "$A/aerender"; chmod +x "$A/aerender"
cat > "$TMP/osascript" <<EOF
#!/bin/sh
printf '%s\n' "\$@" > "$TMP/osa.args"
job=\$(dirname "\$(eval echo \\\${\$#})")
[ -e "\$job/quiet" ] || exit 9
printf 'new' > "\$job/result.aep"
printf '{"schema":"MJ_AE_JOB_RESULT_1","status":"done","applied":3,"steps":3,"skipped":[],"errors":[]}\n' > "\$job/result.json"
EOF
chmod +x "$TMP/osascript"
printf 'real project bytes' > "$AEP"
mkdir -p "$TMP/versions"
mjz(){ MJ_CLI="$CLI" MJ_CONFIG="$TMP/cfg" MJ_OSASCRIPT="$TMP/osascript" zsh -f -c "source '$ROOT/scripts/shell/mj-cli.zsh'; $1" > "$TMP/out.txt" 2>&1 && echo 0 > "$TMP/rc" || echo $? > "$TMP/rc"; }
mjz "mj config set receipts_dir '$TMP/AE/receipts'; mj config set versions_dir '$TMP/versions'; mj config set watch_dir '$TMP/AE/projects'"
mjz "mj conform Promo"
check has "$TMP/out.txt" "Promo.aep against MographJailed studio default"
check test -z "$(ls "$TMP/versions")"
mjz "mj extract Promo 'Lower Third' --label lt"
check has "$TMP/out.txt" 'Made an extract job: "Lower Third" from Promo.aep.'
check jq -e '.extract.compIds==[2]' "$TMP/versions/lt.mjjob/plan.json"
mjz "mj extract Promo 'No Such Comp'"
check has "$TMP/out.txt" 'no comp named "No Such Comp" in Promo.aep'
check test "$(cat "$TMP/rc")" = 66
mjz "mj extract Promo '#3' --label byid"
check jq -e '.extract.compIds==[3]' "$TMP/versions/byid.mjjob/plan.json"
mjz "mj ae run '$TMP/versions/lt.mjjob'"
check test -e "$TMP/versions/lt.mjjob/quiet"
check has "$TMP/osa.args" 'tell application "Adobe After Effects 2026" to DoScriptFile (item 1 of argv)'
check test "$(tail -1 "$TMP/osa.args")" = "$TMP/versions/lt.mjjob/run.jsx"
check has "$TMP/out.txt" 'The extract job "lt" was applied.'
mjz "mj conform Promo --run --label pc"
check has "$TMP/out.txt" "Made a conform job:"
check has "$TMP/out.txt" 'The conform job "pc" was applied.'
mjz "mj ae verify '$TMP/versions/pc.mjjob'"
check has "$TMP/out.txt" "ok The original project is byte-for-byte what it was when the job was made."
mjz "mj conform Promo --spec"
check test "$(cat "$TMP/rc")" = 64
mjz "mj extract Promo 'Lower Third' --label"
check test "$(cat "$TMP/rc")" = 64
mjz "mj check promo"
check has "$TMP/out.txt" "Promo.aep:"
mjz "mj timeline PRO"
check has "$TMP/out.txt" "Promo.aep:"
mjz "mj ae run '$TMP/nope'"
check test "$(cat "$TMP/rc")" = 64

echo "After Effects job tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
