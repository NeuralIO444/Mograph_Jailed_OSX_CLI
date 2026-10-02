#!/usr/bin/env bash
# Cinema 4D intelligence over scene receipts (c4d.inspect, c4d.lint) and the AE/C4D bridge (bridge.check).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
EXPL="$ROOT/scripts/terminal/mj_explain.py"
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
export MJ_STORE_DIR="$TMP/store" MJ_AUDIT_DIR="$TMP/noaudit"
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

python3 - "$TMP" <<'PY'
import copy, json, os, sys
d = sys.argv[1]
good = {"schema": "MJ_C4D_SCRAPE_1", "scraperVersion": "1.0", "scenePath": "/work/hero.c4d", "sceneName": "hero.c4d", "scrapedAt": "2026-10-01T10:00:00Z", "c4dVersion": "2026.3",
        "fps": 24, "startFrame": 0, "endFrame": 47, "width": 1920, "height": 1080, "renderer": "redshift", "outputPath": "/work/renders/hero_", "outputFormat": "PNG", "multipass": True,
        "passes": [{"name": "Beauty"}, {"name": "Depth"}], "cameras": [{"name": "Camera", "active": True}], "takes": [{"name": "Main", "active": True}],
        "materials": [{"name": "Wood", "type": "redshift"}, {"name": "Metal", "type": "redshift"}],
        "textures": [{"path": "tex/wood.png", "resolved": "/work/tex/wood.png", "missing": False, "absolute": False}], "objects": 12}
json.dump(good, open(os.path.join(d, "good.c4dscrape.json"), "w"))
bad = copy.deepcopy(good)
bad.update({"width": 1921, "height": 1081, "startFrame": 100, "endFrame": 10, "outputPath": "", "cameras": [], "passes": [],
            "materials": [{"name": "A", "type": "standard"}, {"name": "B", "type": "standard"}, {"name": "C", "type": "redshift"}],
            "textures": [{"path": "tex/gone.png", "resolved": "", "missing": True, "absolute": False},
                         {"path": "/Users/me/Desktop/wood.png", "resolved": "/Users/me/Desktop/wood.png", "missing": False, "absolute": True},
                         {"path": "tex/ok.png", "resolved": "/work/tex/ok.png", "missing": False, "absolute": False}]})
json.dump(bad, open(os.path.join(d, "bad.c4dscrape.json"), "w"))
std = copy.deepcopy(good); std["renderer"] = "standard"; json.dump(std, open(os.path.join(d, "std.c4dscrape.json"), "w"))
def lay(i, n, src, sp, **kw):
    l = {"index": i, "name": n, "type": "AVLayer", "sourceName": src, "sourcePath": sp, "sourceId": 0, "effects": [], "expressions": []}; l.update(kw); return l
def ae(comp, footage=None):
    return {"schema": "MJ_PROJECT_SCRAPE_1", "scraperVersion": "1.0", "projectPath": "/p/promo.aep", "projectName": "promo.aep", "scrapedAt": "2026-10-01T11:00:00Z", "aeVersion": "26.5", "numItems": 3,
            "fonts": [], "footage": footage or [], "comps": comp}
okc = {"id": 1, "name": "Main", "width": 1920, "height": 1080, "frameRate": 24, "duration": 2.0, "layers": [lay(1, "3D", "hero.c4d", "/work/hero.c4d"), lay(2, "BG", "bg.mov", "/work/bg.mov")]}
json.dump(ae([okc]), open(os.path.join(d, "ae_ok.json"), "w"))
badc = {"id": 1, "name": "Main", "width": 1280, "height": 720, "frameRate": 30, "duration": 3.0, "layers": [lay(1, "3D", "hero.c4d", "/old/copy/hero.c4d")]}
json.dump(ae([badc, {"id": 2, "name": "Other", "width": 1920, "height": 1080, "frameRate": 24, "duration": 2.0, "layers": [lay(1, "3D2", "HERO.C4D", "/work/hero.c4d")]}],
             [{"id": 9, "name": "hero.c4d", "path": "/old/copy/hero.c4d", "missing": True}]), open(os.path.join(d, "ae_bad.json"), "w"))
json.dump(ae([{"id": 1, "name": "Main", "width": 1920, "height": 1080, "frameRate": 24, "duration": 2.0, "layers": [lay(1, "BG", "bg.mov", "/work/bg.mov")]}]), open(os.path.join(d, "ae_none.json"), "w"))
PY

# ---------- c4d.inspect ----------
run "$TMP/i1.json" c4d.inspect "path=$TMP/good.c4dscrape.json"
check jq -e '.ok==true and .data.schema=="MJ_C4D_SUMMARY_1" and .data.renderer=="redshift" and .data.frames==48 and .data.seconds==2 and .data.width==1920' "$TMP/i1.json"
check jq -e '.data.passes==["Beauty","Depth"] and .data.cameras==1 and .data.activeCamera=="Camera" and .data.materials=={"total":2,"byType":{"redshift":2}} and .data.textures.total==1' "$TMP/i1.json"
check jq -e '.warnings==[] and .data.sourceUnchanged==true and (.data|has("_warnings")|not)' "$TMP/i1.json"
run "$TMP/i2.json" c4d.inspect "path=$TMP/bad.c4dscrape.json"
check jq -e '[.warnings[].code]==["TEXTURES_MISSING"] and .data.textures.missing==["tex/gone.png"] and .data.textures.absolute==["/Users/me/Desktop/wood.png"]' "$TMP/i2.json"

# ---------- c4d.lint ----------
run "$TMP/l1.json" c4d.lint "path=$TMP/good.c4dscrape.json"
check jq -e '.ok==true and .data.schema=="MJ_C4D_LINT_1" and .data.numFindings==0 and .data.findings==[]' "$TMP/l1.json"
run "$TMP/l2.json" c4d.lint "path=$TMP/bad.c4dscrape.json"
check jq -e '[.data.findings[].code] | sort == ["C001","C002","C003","C004","C005","C006","C007","C009"]' "$TMP/l2.json"
check jq -e '.data.errors==2 and .data.warnings==5 and .data.info==1 and .data.findings[0].severity=="error"' "$TMP/l2.json"
check jq -e '[.data.findings[] | (.teach.why|length)>30 and (.teach.fix|length)>10 and (.message|length)>5] | all' "$TMP/l2.json"
check jq -e '.data.teaching | keys == ["C001","C002","C003","C004","C005","C006","C007","C009"]' "$TMP/l2.json"
check jq -e '(.data.findings[] | select(.code=="C001") | .subject)=="tex/gone.png" and (.data.findings[] | select(.code=="C002") | .subject)=="/Users/me/Desktop/wood.png"' "$TMP/l2.json"
run "$TMP/l3.json" c4d.lint "path=$TMP/std.c4dscrape.json"
check jq -e '[.data.findings[].code]==["C008"] and .data.info==1 and .data.errors==0' "$TMP/l3.json"

# ---------- bridge.check ----------
run "$TMP/b1.json" bridge.check "path=$TMP/good.c4dscrape.json" "input=$TMP/ae_ok.json"
check jq -e '.ok==true and .data.schema=="MJ_BRIDGE_CHECK_1" and .data.matched==1 and .data.consistent==true and .data.findings==[] and .data.matches[0]=={"comp":"Main","layer":"3D","layerIndex":1,"samePath":true}' "$TMP/b1.json"
check jq -e '.warnings==[] and .data.sourceUnchanged==true and .data.scene.seconds==2' "$TMP/b1.json"
run "$TMP/b2.json" bridge.check "path=$TMP/good.c4dscrape.json" "input=$TMP/ae_bad.json"
check jq -e '.data.matched==2 and .data.consistent==false' "$TMP/b2.json"
check jq -e '[.data.findings[] | select(.comp=="Main") | .code] | sort == ["B001","B002","B003","B004","B005"]' "$TMP/b2.json"
check jq -e '[.data.findings[] | select(.comp=="Other")] == []' "$TMP/b2.json"                               # case-insensitive name match, correct path, nothing wrong
check jq -e '(.data.findings[] | select(.code=="B001") | .message) == "Comp \"Main\" runs at 30 fps; the scene is 24 fps."' "$TMP/b2.json"
check jq -e '.data.errors==3 and .data.warnings==2' "$TMP/b2.json"
run "$TMP/b3.json" bridge.check "path=$TMP/good.c4dscrape.json" "input=$TMP/ae_bad.json" "target=Other"
check jq -e '.data.matched==1 and .data.consistent==true' "$TMP/b3.json"
run "$TMP/b4.json" bridge.check "path=$TMP/good.c4dscrape.json" "input=$TMP/ae_none.json"
check jq -e '.ok==true and .data.matched==0 and .data.consistent==false and ([.warnings[].code]==["NO_MATCHING_LAYER"])' "$TMP/b4.json"
run "$TMP/b5.json" bridge.check "path=$TMP/good.c4dscrape.json" "input=$TMP/ae_bad.json" "target=NoSuchComp"
check jq -e '.data.matched==0 and ([.warnings[].code]==["NO_MATCHING_LAYER"])' "$TMP/b5.json"

# ---------- bad input ----------
printf 'not json' > "$TMP/junk.json"; printf '{"schema":"MJ_C4D_SCRAPE_1","fps":24}' > "$TMP/partial.json"; printf '{"schema":"MJ_PROJECT_SCRAPE_1"}' > "$TMP/wrongschema.json"
python3 -c "
import json; d=json.load(open('$TMP/good.c4dscrape.json')); d['fps']=0; json.dump(d, open('$TMP/fps0.json','w'))"
for op in c4d.inspect c4d.lint; do
  run "$TMP/e1.json" $op "path=$TMP/junk.json";        check jq -e '.error.code=="INVALID_JSON"' "$TMP/e1.json"
  run "$TMP/e2.json" $op "path=$TMP/partial.json";     check jq -e '.error.code=="SCHEMA_MISMATCH"' "$TMP/e2.json"
  run "$TMP/e3.json" $op "path=$TMP/wrongschema.json"; check jq -e '.error.code=="SCHEMA_MISMATCH"' "$TMP/e3.json"
  run "$TMP/e4.json" $op "path=$TMP/fps0.json";        check jq -e '.error.code=="SCHEMA_MISMATCH"' "$TMP/e4.json"
  run "$TMP/e5.json" $op "path=relative";              check jq -e '.error.code=="INVALID_PATH"' "$TMP/e5.json"
  run "$TMP/e6.json" $op "path=$TMP/nope.json";        check jq -e '.error.code=="INVALID_TARGET"' "$TMP/e6.json"
done
run "$TMP/e7.json" bridge.check "path=$TMP/good.c4dscrape.json"
check jq -e '.error.code=="MISSING_ARGUMENT"' "$TMP/e7.json"
run "$TMP/e8.json" bridge.check "path=$TMP/ae_ok.json" "input=$TMP/ae_ok.json"
check jq -e '.error.code=="SCHEMA_MISMATCH"' "$TMP/e8.json"                                                  # a project scrape is not a scene scrape

# ---------- plain language ----------
python3 "$EXPL" "$TMP/i1.json" > "$TMP/x1.txt";  check grep -q 'hero.c4d (Cinema 4D 2026.3, redshift renderer)' "$TMP/x1.txt"; check grep -q '1920 x 1080 at 24 fps, frames 0 to 47 (48 frames, 2.00 seconds)' "$TMP/x1.txt"
python3 "$EXPL" "$TMP/i2.json" > "$TMP/x2.txt";  check grep -q '1 missing (tex/gone.png)' "$TMP/x2.txt"; check grep -q 'Heads up' "$TMP/x2.txt"
python3 "$EXPL" "$TMP/l2.json" > "$TMP/x3.txt";  check grep -q 'Found 8 problems: 2 errors, 5 warnings, 1 note' "$TMP/x3.txt"; check grep -q 'Why it matters:' "$TMP/x3.txt"; check grep -q 'Before:' "$TMP/x3.txt"
python3 "$EXPL" "$TMP/l1.json" > "$TMP/x4.txt";  check grep -q 'No problems found' "$TMP/x4.txt"
python3 "$EXPL" "$TMP/b1.json" > "$TMP/x5.txt";  check grep -q 'Everything matches' "$TMP/x5.txt"
python3 "$EXPL" "$TMP/b2.json" > "$TMP/x6.txt";  check grep -q 'Comp "Main" runs at 30 fps; the scene is 24 fps' "$TMP/x6.txt"
python3 "$EXPL" "$TMP/b4.json" > "$TMP/x7.txt";  check grep -q 'Nothing was compared' "$TMP/x7.txt"

# ---------- the human commands ----------
export MJ_CONFIG="$TMP/cfg/config"; mkdir -p "$TMP/rc"
mjz(){ MJ_CLI="$CLI" zsh -f -c "source '$ROOT/scripts/shell/mj-cli.zsh'; $1"; }
mjz "mj config set receipts_dir '$TMP/rc'" >/dev/null
cp "$TMP/bad.c4dscrape.json" "$TMP/rc/old.c4dscrape.json"; cp "$TMP/good.c4dscrape.json" "$TMP/rc/new.c4dscrape.json"
touch -t 202610010900 "$TMP/rc/old.c4dscrape.json"; touch -t 202610011000 "$TMP/rc/new.c4dscrape.json"
cp "$TMP/ae_ok.json" "$TMP/rc/promo.20261001T110000Z.scrape.json"
mjz "mj scene last" | grep -q 'No problems found' && pass=$((pass+1)) || { echo "FAIL: mj scene last" >&2; fail=$((fail+1)); }
mjz "mj scene '$TMP/rc/old.c4dscrape.json'" > "$TMP/hs.txt"; check grep -q 'Found 8 problems' "$TMP/hs.txt"
mjz "mj scene last --summary" | grep -q 'hero.c4d (Cinema 4D' && pass=$((pass+1)) || { echo "FAIL: mj scene --summary" >&2; fail=$((fail+1)); }
mjz "mj bridge last last" | grep -q 'Everything matches' && pass=$((pass+1)) || { echo "FAIL: mj bridge" >&2; fail=$((fail+1)); }
mjz "mj bridge '$TMP/good.c4dscrape.json' '$TMP/ae_bad.json' Other" | grep -q 'Everything matches' && pass=$((pass+1)) || { echo "FAIL: mj bridge comp" >&2; fail=$((fail+1)); }
set +e; HOME="$TMP/nohome" MJ_CONFIG="$TMP/cfg/none" mjz "mj scene last" >/dev/null 2>&1; r=$?; set -e
check test "$r" = 66

echo "Cinema 4D tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
