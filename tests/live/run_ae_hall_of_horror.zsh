#!/bin/zsh -f
# Hall of horror, live: After Effects must be running on this Mac. Not part of run_all.sh or CI.
#
#   zsh tests/live/run_ae_hall_of_horror.zsh [--keep]
#
# 1. Reachability: host.detect finds After Effects, it answers AppleScript, scripts may write files.
# 2. Builds a hostile project in After Effects (quotes, backslashes, slashes, Unicode and emoji in names,
#    a 250-character name, two comps with the same name, a 12-deep precomp chain, names that already
#    carry studio prefixes, expressions by name, by index and through escaped quotes).
# 3. Scrapes it unattended, then runs ingest, lint, health, preflight, mj check, conform (plan and job)
#    and extract (by id, and the deep chain) through the real runner in After Effects.
# 4. Opens every result in After Effects and evaluates every expression: none may error.
# 5. Runner refusals: a job that already ran, and a job whose copy is gone, change nothing.
# 6. The original project's bytes never change.
# Everything is written under a scratch folder. It will not start if a project is open in After Effects.
emulate -R zsh
setopt pipefail
ROOT=${0:A:h:h:h}
CLI="$ROOT/dist/mograph-jailed.zsh"
KEEP=0; [ "${1:-}" = --keep ] && KEEP=1
W=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/mj-ae-horror.XXXXXX") || exit 73
W=${W:A}
(( KEEP )) || trap '/bin/rm -rf "$W"' EXIT
pass=0; fail=0
ok(){ pass=$((pass+1)); print -r -- "  ok   $1"; }
bad(){ fail=$((fail+1)); print -r -- "  FAIL $1"; }
section(){ print; print -r -- "== $1"; }
export MJ_CONFIG="$W/config" MJ_STORE_DIR="$W/store" MJ_CLI="$CLI"
source "$ROOT/scripts/shell/mj-cli.zsh"
mkdir -p "$W/receipts" "$W/jobs" "$W/proj/Horror" "$W/checks"
mj config set receipts_dir "$W/receipts" >/dev/null; mj config set versions_dir "$W/jobs" >/dev/null; mj config set watch_dir "$W/proj" >/dev/null

# ---- 1. reachability
section "reachability"
APP=$(_mj_ae_app) || { print "No supported After Effects found."; exit 69; }
NAME="${${APP:t}%.app}"
ok "host.detect: $NAME"
ae_do(){ # ae_do <jsx file> [timeout seconds]: run a script in After Effects and wait for it
  /usr/bin/osascript -e 'on run argv' -e "with timeout of ${2:-600} seconds" -e "tell application \"$NAME\" to DoScriptFile (item 1 of argv)" -e 'end timeout' -e 'end run' -- "$1" >/dev/null 2>"$W/osa.err"
}
cat > "$W/ping.jsx" <<EOF
var f = new File("$W/ping.txt"); f.lineFeed = "Unix"; f.open("w");
f.writeln(app.version); f.writeln(app.preferences.getPrefAsLong("Main Pref Section", "Pref_SCRIPTING_FILE_NETWORK_SECURITY"));
f.writeln(app.project ? app.project.numItems : 0); f.writeln(app.project && app.project.file ? app.project.file.fsName : ""); f.close();
EOF
t0=$EPOCHREALTIME; zmodload zsh/datetime
if ae_do "$W/ping.jsx" 60 && [ -f "$W/ping.txt" ]; then
  ok "AppleScript round trip in $(printf '%.2f' $(( EPOCHREALTIME - t0 ))) s (After Effects $(sed -n 1p "$W/ping.txt"))"
else
  bad "After Effects did not answer AppleScript: $(cat "$W/osa.err" 2>/dev/null)"; print "Allow Terminal to control After Effects (System Settings > Privacy & Security > Automation) and clear any open dialog."; exit 69
fi
[ "$(sed -n 2p "$W/ping.txt")" = 1 ] && ok "scripts may write files" || { bad "turn on Settings > Scripting & Expressions > Allow Scripts to Write Files and Access Network"; exit 69; }
if [ "$(sed -n 3p "$W/ping.txt")" != 0 ] || [ -n "$(sed -n 4p "$W/ping.txt")" ]; then
  print "A project is open in After Effects ($(sed -n 4p "$W/ping.txt")). Save and close it (File > Close Project), then run this again."; exit 75
fi
ok "no project open"

# ---- 2. the horror project (names written as \u escapes so the script file is plain ASCII)
section "build"
SRC="$W/proj/Horror/Horror.aep"
cat > "$W/build.jsx" <<EOF
(function () {
  var log = new File("$W/build.log");
  try {
    app.newProject();
    var P = app.project.items;
    var leaf = P.addComp("Leaf", 640, 360, 1, 4, 24); leaf.layers.addText("leaf");
    var cur = leaf, i, c;
    for (i = 1; i <= 12; i++) { c = P.addComp("Level " + i, 640, 360, 1, 4, 24); c.layers.add(cur); cur = c; }
    var q = P.addComp('Quote "Comp"', 1920, 1080, 1, 4, 24);
    var bs = P.addComp("Back\\\\slash", 1920, 1080, 1, 4, 24);
    var uni = P.addComp("Ünïcödé 🎬", 1920, 1080, 1, 4, 24);
    var sl = P.addComp("a/b slash", 1920, 1080, 1, 4, 24);
    var longName = ""; for (i = 0; i < 25; i++) { longName += "LongName_"; } longName = longName.substring(0, 250);
    var lg = P.addComp(longName, 640, 360, 1, 4, 24);
    var d1 = P.addComp("Dup", 640, 360, 1, 4, 24); d1.layers.addText("first dup");
    var d2 = P.addComp("Dup", 640, 360, 1, 4, 24); d2.layers.addText("second dup");
    var main = P.addComp("Main", 1920, 1080, 1, 4, 24);
    main.layers.add(cur); main.layers.add(q); main.layers.add(uni); main.layers.add(sl);
    var bob = main.layers.addText("Bob's Title"); bob.name = "Bob's Title";
    var pre = main.layers.addText("already"); pre.name = "TXT_Already";
    var nul = main.layers.addNull(4); nul.name = "Ctrl";
    var t = main.layers.addText("Driver"); t.name = "Driver";
    t.property("Transform").property("Position").expression = 'thisComp.layer("Ctrl").transform.position';
    t.property("Transform").property("Opacity").expression = 'thisComp.layer("Bob\\'s Title").transform.opacity';
    t.property("Transform").property("Rotation").expression = 'thisComp.layer(1).transform.rotation';
    t.property("Transform").property("Scale").expression = 'comp("Level 12").layer(1).transform.scale';
    var tq = q.layers.addText("in quote comp"); tq.name = "Inner";
    tq.property("Transform").property("Opacity").expression = 'comp("Main").layer("Ctrl").transform.opacity';
    app.project.save(new File("$SRC"));
    log.lineFeed = "Unix"; log.open("w"); log.writeln("built " + app.project.numItems); log.close();
  } catch (e) { log.open("w"); log.writeln("ERROR " + e.toString() + " line " + e.line); log.close(); }
})();
EOF
ae_do "$W/build.jsx" 600
grep -q '^built' "$W/build.log" 2>/dev/null && ok "built $(cat "$W/build.log")" || { bad "build failed: $(cat "$W/build.log" 2>/dev/null)"; exit 1; }
SHA0=$(/usr/bin/shasum -a 256 "$SRC" | cut -d' ' -f1)

scrape(){ # scrape <aep> <out dir>: open, scrape unattended, close unsaved
  { printf 'var MJ_SCRAPE_OUT_DIR = "%s"; var MJ_SCRAPE_QUIET = true;\napp.project.close(CloseOptions.DO_NOT_SAVE_CHANGES);\napp.open(new File("%s"));\n' "$2" "$1"
    cat "$ROOT/integrations/after-effects/MographJailed_ProjectScraper.jsx"
    printf '\napp.project.close(CloseOptions.DO_NOT_SAVE_CHANGES);\n'; } > "$W/scrape.jsx"
  ae_do "$W/scrape.jsx" 600
}
# evaluate <aep> <report>: open, evaluate every expression at time 0, list errors, close unsaved
evaluate(){
  cat > "$W/eval.jsx" <<EOF
app.project.close(CloseOptions.DO_NOT_SAVE_CHANGES);
app.open(new File("$1"));
(function () {
  var out = [], i, l, k, c, L, tr, p;
  for (i = 1; i <= app.project.numItems; i++) {
    c = app.project.item(i); if (!(c instanceof CompItem)) continue;
    for (l = 1; l <= c.numLayers; l++) { L = c.layer(l); tr = L.property("Transform");
      for (k = 1; k <= tr.numProperties; k++) { p = tr.property(k);
        if (p.expression) { try { p.valueAtTime(0, false); } catch (e) {}
          out.push((p.expressionError ? "ERROR " : "OK ") + c.name + " / " + L.name + " / " + p.name + " :: " + p.expression + (p.expressionError ? " :: " + p.expressionError : "")); } } } }
  var f = new File("$2"); f.encoding = "UTF-8"; f.lineFeed = "Unix"; f.open("w"); f.write(out.join("\\n")); f.close();
})();
app.project.close(CloseOptions.DO_NOT_SAVE_CHANGES);
EOF
  ae_do "$W/eval.jsx" 600
}

# ---- 3. scrape and the read-only checks
section "scrape and checks"
scrape "$SRC" "$W/receipts"
S=$(ls "$W/receipts"/*.scrape.json 2>/dev/null | head -1)
[ -n "$S" ] && ok "scraped unattended: ${S:t}" || { bad "no scrape written"; exit 1; }
/usr/bin/jq -e '.scraperVersion=="1.1" and (.comps|length)==21' "$S" >/dev/null && ok "21 comps recorded, scraper 1.1" || bad "scrape content: $(/usr/bin/jq -c '{v:.scraperVersion,n:(.comps|length)}' "$S")"
/usr/bin/jq -e '[.comps[].name]|index("Ünïcödé 🎬")!=null and index("Quote \"Comp\"")!=null and index("Back\\slash")!=null' "$S" >/dev/null && ok "hostile names survive the scrape exactly" || bad "names mangled: $(/usr/bin/jq -c '[.comps[].name]' "$S")"
for op in project.ingest expression.lint project.health project.preflight deps.graph; do
  out=$(_mj_run $op "path=$S"); [ "$(print -r -- "$out" | /usr/bin/jq -r .ok)" = true ] && ok "$op" || bad "$op: $(print -r -- "$out" | /usr/bin/jq -c .error)"
done
mj check Horror > "$W/check.txt" 2>&1; [ $? -le 1 ] && grep -q "Horror.aep:" "$W/check.txt" && ok "mj check: $(head -1 "$W/check.txt")" || bad "mj check: $(cat "$W/check.txt")"
mj conform Horror > "$W/plan.txt" 2>&1 && ok "mj conform plan: $(head -1 "$W/plan.txt")" || bad "conform plan: $(cat "$W/plan.txt")"

# ---- 4. jobs, for real
section "jobs in After Effects"
mj conform Horror --run --label horror-conform > "$W/conform.txt" 2>&1
grep -q 'was applied' "$W/conform.txt" && ok "conform job: $(grep -m1 'steps applied\|applied;' "$W/conform.txt" | sed 's/^ *//')" || bad "conform job: $(tail -8 "$W/conform.txt")"
LEVEL12=$(/usr/bin/jq -r '.comps[]|select(.name=="Level 12")|.id' "$S")
DUPS=($(/usr/bin/jq -r '.comps[]|select(.name=="Dup")|.id' "$S"))
mj extract Horror "#$LEVEL12" --label horror-chain --run > "$W/chain.txt" 2>&1
grep -q 'was applied' "$W/chain.txt" && ok "extract the 12-deep chain: $(grep 'Project items' "$W/chain.txt" | sed 's/^ *//')" || bad "extract chain: $(tail -8 "$W/chain.txt")"
mj extract Horror Dup > "$W/dup.txt" 2>&1; [ $? = 65 ] && grep -q 'more than one comp is named "Dup"' "$W/dup.txt" && ok "a duplicated comp name is refused by name" || bad "dup by name: $(cat "$W/dup.txt")"
mj extract Horror "#${DUPS[2]}" --label horror-dup --run > "$W/dup2.txt" 2>&1
grep -q 'was applied' "$W/dup2.txt" && ok "the second \"Dup\" extracted by id" || bad "dup by id: $(tail -8 "$W/dup2.txt")"

# ---- 5. results inside After Effects
section "results"
evaluate "$W/jobs/horror-conform.mjjob/result.aep" "$W/checks/conform.txt"
n_err=$(grep -c '^ERROR' "$W/checks/conform.txt"); n_all=$(grep -c . "$W/checks/conform.txt")
[ "$n_err" = 0 ] && [ "$n_all" -ge 5 ] && ok "conform result: all $n_all expressions evaluate without error" || { bad "conform result: $n_err of $n_all expressions error"; grep '^ERROR' "$W/checks/conform.txt" | head -5 | sed 's/^/       /'; }
grep -q 'thisComp.layer("NULL_Ctrl")' "$W/checks/conform.txt" && ok "renamed layer followed by its expression" || bad "Ctrl reference not updated: $(grep Driver "$W/checks/conform.txt" | head -2)"
mkdir -p "$W/receipts2"; scrape "$W/jobs/horror-conform.mjjob/result.aep" "$W/receipts2"
R2=$(ls "$W/receipts2"/*.scrape.json 2>/dev/null | head -1)
if [ -n "$R2" ]; then
  /usr/bin/jq -e '[.comps[].layers[]|select(.name=="TXT_Already")]|length==1' "$R2" >/dev/null && ok "an already-prefixed layer is not prefixed twice" || bad "TXT_Already changed: $(/usr/bin/jq -c '[.comps[].layers[].name]' "$R2")"
  /usr/bin/jq -e '[.comps[]|select(.name|startswith("PRE_Level_"))]|length==12' "$R2" >/dev/null && ok "12 nested precomps renamed PRE_Level_*" || bad "precomp names: $(/usr/bin/jq -c '[.comps[].name]' "$R2")"
  /usr/bin/jq -e '[.comps[]|.folder]|all(.=="01_Comps" or .=="02_Precomps")' "$R2" >/dev/null && ok "every comp filed into 01_Comps or 02_Precomps" || bad "folders: $(/usr/bin/jq -c '[.comps[]|{name,folder}]' "$R2")"
else bad "result could not be scraped"; fi
evaluate "$W/jobs/horror-chain.mjjob/result.aep" "$W/checks/chain.txt"
mkdir -p "$W/receipts3"; scrape "$W/jobs/horror-chain.mjjob/result.aep" "$W/receipts3"
R3=$(ls "$W/receipts3"/*.scrape.json 2>/dev/null | head -1)
[ -n "$R3" ] && /usr/bin/jq -e '(.comps|length)==13' "$R3" >/dev/null && ok "chain extract keeps exactly Level 1-12 and Leaf" || bad "chain extract comps: $( [ -n "$R3" ] && /usr/bin/jq -c '[.comps[].name]' "$R3")"

# ---- 6. runner refusals
section "refusals"
J="$W/jobs/horror-conform.mjjob"; before=$(/usr/bin/shasum -a 256 "$J/result.aep" "$J/result.json")
ae_do "$J/run.jsx" 120
[ "$(/usr/bin/shasum -a 256 "$J/result.aep" "$J/result.json")" = "$before" ] && ok "a job that already ran refuses to run again" || bad "re-running a job changed its result"
mj extract Horror Leaf --label horror-gone > /dev/null 2>&1; G="$W/jobs/horror-gone.mjjob"; /bin/rm -f "$G/before.aep"; : > "$G/quiet"
ae_do "$G/run.jsx" 120
[ ! -e "$G/result.aep" ] && ok "a job whose copy is gone does nothing" || bad "a job without its copy produced a result"

# ---- 7. the original
section "original"
[ "$(/usr/bin/shasum -a 256 "$SRC" | cut -d' ' -f1)" = "$SHA0" ] && ok "Horror.aep is byte-for-byte unchanged after everything" || bad "THE ORIGINAL PROJECT CHANGED"

print; print "After Effects hall of horror: $pass passed, $fail failed$( (( KEEP )) && print "   (kept: $W)")"
[ $fail -eq 0 ]
