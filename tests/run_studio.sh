#!/usr/bin/env bash
# Studio tools: project.preflight (fonts, footage, third-party effects), mj check and mj timeline.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
export MJ_STORE_DIR="$TMP/store" MJ_AUDIT_DIR="$TMP/noaudit" MJ_FONT_DIRS="$TMP/fonts" MJ_FONT_DIRS_ONLY=1
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
has(){ case "$(cat "$1")" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
b64(){ printf '%s' "$1" | base64 | tr -d '\n'; }
run(){
  local _out="$1" _cmd="$2"; shift 2
  local _f="$TMP/req_$RANDOM$RANDOM.txt"
  { printf 'MOGRAPHJAILED_REQUEST 1\nrequestId=t%s\ncommand=%s\n' "$RANDOM" "$_cmd"
    for _a in "$@"; do printf 'arg.%s=%s\n' "${_a%%=*}" "$(b64 "${_a#*=}")"; done; } > "$_f"
  "$CLI" --request "$_f" > "$_out" 2>/dev/null || true
}

python3 "$ROOT/tests/support/make_tutorial_fixtures.py" "$TMP/AE" >/dev/null
# Fonts: a real sfnt name table for Inter-Regular (PostScript) / Inter (family), a collection holding
# BrandonGrotesque-Bold, and a junk file that must be skipped.
python3 - "$TMP/fonts" <<'PY'
import os, struct, sys
d = sys.argv[1]; os.makedirs(d)
def name_table(names):
    recs, blob = b"", b""
    for nid, s in names:
        raw = s.encode("utf-16-be")
        recs += struct.pack(">HHHHHH", 3, 1, 0x409, nid, len(raw), len(blob)); blob += raw
    return struct.pack(">HHH", 0, len(names), 6 + len(recs)) + recs + blob
def sfnt(names, base=0):
    t = name_table(names)
    return struct.pack(">IHHHH", 0x00010000, 1, 16, 0, 0) + struct.pack(">4sIII", b"name", 0, base + 28, len(t)) + t
open(os.path.join(d, "Inter.ttf"), "wb").write(sfnt([(1, "Inter"), (6, "Inter-Regular")]))
one = sfnt([(1, "Brandon Grotesque"), (6, "BrandonGrotesque-Bold")], base=16)
open(os.path.join(d, "Brandon.ttc"), "wb").write(b"ttcf" + struct.pack(">HHI", 1, 0, 1) + struct.pack(">I", 16) + one)
open(os.path.join(d, "junk.otf"), "wb").write(b"not a font")
PY
SPRING="$TMP/AE/receipts/spring.20261001T163000Z.scrape.json"

# ---- preflight: every font found (family name and collection) ----
run "$TMP/p1.json" project.preflight path="$SPRING"
check jq -e '.ok and .command=="project.preflight" and .data.schema=="MJ_PREFLIGHT_1"' "$TMP/p1.json"
check jq -e '.data.fontsMissing==0 and ([.data.fonts[].state]|all(.=="installed"))' "$TMP/p1.json"
check jq -e '.data.fontScan.files==3' "$TMP/p1.json"                       # junk read but yields nothing
check jq -e '.data.footageMissing==1 and .data.footage[0].name=="logo.psd" and .data.footage[0].state=="missing"' "$TMP/p1.json"
check jq -e '.data.thirdPartyEffects|map(.matchName)==["S_Glow"]' "$TMP/p1.json"   # ADBE effects are first party
check jq -e '.data.ready==false and .data.problems==1 and .data.sourceUnchanged' "$TMP/p1.json"
check jq -e '[.warnings[].code]|index("FONT_REPORT_UNAVAILABLE")!=null' "$TMP/p1.json"

# ---- After Effects' own missing-font report wins; PostScript names match; gone-since-scrape footage ----
python3 - "$SPRING" "$TMP/s2.json" "$TMP/AE" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["scraperVersion"] = "1.1"
d["missingFonts"] = ["Inter-Regular"]
for c in d["comps"]:
    for l in c["layers"]:
        if l.get("font") == "Inter": l["font"] = "Inter-Regular"
        if l.get("font") == "Brandon Grotesque": l["font"] = "BrandonGrotesque-Bold"
d["fonts"] = ["BrandonGrotesque-Bold", "Inter-Regular"]
d["footage"].append({"id": 99, "name": "gone.mov", "path": sys.argv[3] + "/media/gone.mov", "missing": False, "hasVideo": True, "hasAudio": False})
d["footage"].append({"id": 98, "name": "Black Solid 1", "kind": "solid", "path": "", "missing": False, "hasVideo": True, "hasAudio": False})
json.dump(d, open(sys.argv[2], "w"))
PY
run "$TMP/p2.json" project.preflight path="$TMP/s2.json"
check jq -e '.data.fonts|map({(.name): .state})|add=={"BrandonGrotesque-Bold":"installed","Inter-Regular":"missing"}' "$TMP/p2.json"
check jq -e '(.data.fonts[]|select(.name=="Inter-Regular")|.foundOnThisMac)==true' "$TMP/p2.json"
check jq -e '[.data.footage[]|{name,state}]==[{"name":"logo.psd","state":"missing"},{"name":"gone.mov","state":"goneSinceScrape"}]' "$TMP/p2.json"
check jq -e '[.warnings[]?.code]|index("FONT_REPORT_UNAVAILABLE")==null' "$TMP/p2.json"

# ---- font not found anywhere ----
rm "$TMP/fonts/Brandon.ttc"
run "$TMP/p3.json" project.preflight path="$SPRING"
check jq -e '(.data.fonts[]|select(.name=="Brandon Grotesque")) as $f | $f.state=="notFound" and $f.uses==[{"comp":"Main","layer":"Title"}]' "$TMP/p3.json"

# ---- argument errors ----
run "$TMP/e1.json" project.preflight path=relative.json
check jq -e '.error.code=="INVALID_PATH"' "$TMP/e1.json"
echo '{"schema":"nope"}' > "$TMP/bad.json"
run "$TMP/e2.json" project.preflight path="$TMP/bad.json"
check jq -e '.error.code=="SCHEMA_MISMATCH"' "$TMP/e2.json"

# ---- plain language ----
python3 "$ROOT/scripts/terminal/mj_explain.py" "$TMP/p3.json" > "$TMP/p3.txt"
check has "$TMP/p3.txt" "Spring Promo.aep: 2 things to fix before it opens cleanly."
check has "$TMP/p3.txt" 'Font Brandon Grotesque is not found on this Mac (used by "Title" in Main).'
check has "$TMP/p3.txt" "Third-party effects to confirm are installed: Sapphire Glow (S_Glow)."

# ---- mj check and mj timeline ----
export HOME="$TMP/home"; mkdir -p "$HOME" "$TMP/versions"
mjz(){ MJ_CLI="$CLI" MJ_CONFIG="$TMP/cfg" zsh -f -c "source '$ROOT/scripts/shell/mj-cli.zsh'; $1" > "$TMP/out.txt" 2>&1 && echo 0 > "$TMP/rc" || echo $? > "$TMP/rc"; }
mjz "mj config set receipts_dir '$TMP/AE/receipts'; mj config set versions_dir '$TMP/versions'; mj config set watch_dir '$TMP/AE/projects'"
mjz "mj check 'Spring Promo'"
check has "$TMP/out.txt" "Spring Promo.aep: 3 things to fix."
check has "$TMP/out.txt" "!! Fonts: 1 missing (Brandon Grotesque)."
check has "$TMP/out.txt" "?? Third-party effects to confirm: S_Glow."
check test "$(cat "$TMP/rc")" = 1
mjz "mj check '$TMP/AE/receipts/summer.20261002T090000Z.scrape.json'"
check has "$TMP/out.txt" "Summer Sale.aep: ready."
check test "$(cat "$TMP/rc")" = 0
mjz "mj check 'No Such Project'"
check has "$TMP/out.txt" 'no scrape receipt for "No Such Project"'
mjz "mj check 'Spring Promo' --details"
check has "$TMP/out.txt" "Checked 1 expression."
mjz "mj snapshot 'Spring Promo' >/dev/null; mj timeline 'spring promo'"
check has "$TMP/out.txt" "Spring Promo.aep: 2 scrapes and 1 snapshot, oldest first"
check has "$TMP/out.txt" "first scrape"
check has "$TMP/out.txt" 'comp "Main": frame rate 24 -> 30'
check grep -qE "snapshot +[0-9a-f]{12}" "$TMP/out.txt"
mjz "mj timeline"
check test "$(cat "$TMP/rc")" = 64

echo "Studio tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
