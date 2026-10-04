#!/usr/bin/env bash
# #42: terminal control codes, hyperlinks, carriage returns and right-to-left overrides inside project names, file names
# and fonts are shown as visible escapes, never obeyed; ordinary Unicode is untouched.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P); trap "" EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
export HOME="$TMP/home"; mkdir -p "$HOME"; export MJ_CONFIG="$TMP/cfg" MJ_STORE_DIR="$TMP/store" MJ_CLI="$CLI" MJ_AUDIT_DIR="$TMP/noaudit"
mkdir -p "$TMP/proj/Evil" "$TMP/rep" "$TMP/ver"
python3 - "$TMP" <<'PY'
import json, os, sys
tmp = sys.argv[1]
evil = {"color": "\x1b[31mRED\x1b[0m", "link": "\x1b]8;;http://evil.example\x1b\\click me\x1b]8;;\x1b\\", "title": "\x1b]0;PWNED\x07", "bidi": "invoice\u202egpj.exe", "cr": "good\rEVIL", "clear": "\x1b[2J\x1b[H",
        "bell": "ding\x07", "zero": "a\u200bb", "c1": "x\x9b31my", "tag": "t\U000e0041g", "isolate": "a\u2066b\u2069"}
good = "日本語 Café 🎬"
aep = os.path.join(tmp, "proj", "Evil", "Evil.aep"); open(aep, "wb").write(b"evil"); os.utime(aep, (1790000000, 1790000000))
layers = [{"index": i + 1, "name": v, "type": "TextLayer", "enabled": True, "hasVideo": True, "hasAudio": False, "sourceName": "", "sourcePath": "", "sourceId": 0, "effects": [], "font": v,
           "expressions": [{"propertyPath": "Transform/Position", "expression": 'thisComp.layer("Ghost%d").x' % i}]} for i, v in enumerate(evil.values())]
layers.append({"index": 99, "name": good, "type": "TextLayer", "enabled": True, "hasVideo": True, "hasAudio": False, "sourceName": "", "sourcePath": "", "sourceId": 0, "effects": [], "expressions": []})
doc = {"schema": "MJ_PROJECT_SCRAPE_1", "scraperVersion": "1.1", "projectPath": aep, "projectName": "Evil.aep", "scrapedAt": "2026-10-02T10:00:00Z", "aeVersion": "26.5.0", "numItems": 3,
       "fonts": list(evil.values()), "missingFonts": [], "comps": [{"id": 1, "name": "Main " + evil["color"], "width": 1920, "height": 1080, "frameRate": 24, "duration": 5, "numLayers": len(layers), "layers": layers},
                                                                {"id": 2, "name": "Main " + evil["link"], "width": 1920, "height": 1080, "frameRate": 24, "duration": 5, "numLayers": 0, "layers": []}],
       "footage": [{"id": 5, "name": "clip" + evil["color"] + ".mov", "path": "/nonexistent/" + evil["clear"] + "clip.mov", "missing": True, "hasVideo": True, "hasAudio": False}]}
json.dump(doc, open(os.path.join(tmp, "rep", "evil.20261002T100000Z.scrape.json"), "w"))
bidi = os.path.join(tmp, "proj", "Evil", "Bidi.aep"); open(bidi, "wb").write(b"bidi"); os.utime(bidi, (1790000000, 1790000000))
b = dict(doc); b.update({"projectPath": bidi, "projectName": "Bidi.aep", "fonts": [evil["bidi"]], "comps": [{"id": 1, "name": "Main", "width": 1920, "height": 1080, "frameRate": 24, "duration": 5, "numLayers": 1, "layers": [dict(layers[3], index=1, expressions=[])]}], "footage": []})
json.dump(b, open(os.path.join(tmp, "rep", "bidi.20261002T100000Z.scrape.json"), "w"))
# two projects whose file names carry control codes, and a version of each
for n in ("Twin\x1b[31m.aep", "Twin\u202egpj.aep"):
    p = os.path.join(tmp, "proj", n); open(p, "wb").write(n.encode())
open(os.path.join(tmp, "proj", "Cafe " + good + ".aep"), "wb").write(b"ok")
PY
mjz(){ zsh -f -c "source '$ROOT/scripts/shell/mj-cli.zsh'; mj $1" > "$TMP/out.txt" 2> "$TMP/err.txt"; echo $? > "$TMP/rc"; cat "$TMP/out.txt" "$TMP/err.txt" > "$TMP/all.txt"; }
clean(){ python3 - "$TMP/all.txt" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search("[\x00-\x08\x0b-\x1f\x7f-\x9f\u00ad\u061c\u200b-\u200f\u2028-\u202e\u2060-\u206f\ufeff\U000e0000-\U000e007f]", t)
sys.exit(1 if m else 0)
PY
}
mjz "config set watch_dir '$TMP/proj' >/dev/null; mj config set receipts_dir '$TMP/rep' >/dev/null; mj config set versions_dir '$TMP/ver' >/dev/null"

for line in "check Evil" "lint Evil" "lint last" "health last" "conform Evil" "timeline Evil" "diff last" "explain '$TMP/rep/evil.20261002T100000Z.scrape.json'" "versions" "doctor" "extract Evil nothing-here" "snapshot Twin" "snapshot Evil"; do
  mjz "$line"; check clean
done
# the visible escape is what the person sees
mjz "check Evil"; check grep -q '\\x1b\[31mRED' "$TMP/all.txt"
mjz "check Bidi"; check clean; check grep -q 'invoice\\u202egpj.exe' "$TMP/all.txt"          # a font name with a right-to-left override
mjz "lint Evil";  check grep -q '\\x1b\[2J' "$TMP/all.txt"; check grep -q 'Error in "Main \\x1b\[31mRED' "$TMP/all.txt"
mjz "health Evil"; check grep -q 'Evil.aep health' "$TMP/all.txt"
# the ambiguity list for two look-alike file names is safe and shows both
mjz "snapshot Twin"; check test "$(cat "$TMP/rc")" = 65; check clean; check grep -q 'matches more than one project' "$TMP/err.txt"
# comp lists in errors
mjz "extract Evil nothing-here"; check clean; check grep -q 'no comp named' "$TMP/err.txt"
# ordinary Unicode is left alone
mjz "snapshot 'Cafe 日本語 Café 🎬'"; check test "$(cat "$TMP/rc")" = 0; check grep -q '日本語 Café 🎬' "$TMP/all.txt"; check clean
# the dashboard scrubs the data it draws
check python3 - "$ROOT" <<'PY'
import sys
sys.path.insert(0, sys.argv[1] + "/scripts/terminal")
import mj_ui
d = mj_ui.scrub({"a": ["x\x1b[2Jy", {"b": "p\u202eq"}], "n": 5, "ok": "日本語 🎬"})
assert d == {"a": ["x\\x1b[2Jy", {"b": "p\\u202eq"}], "n": 5, "ok": "日本語 🎬"}, d
PY
check python3 - "$ROOT" <<'PY'
import sys
sys.path.insert(0, sys.argv[1] + "/scripts/terminal")
import mj_explain as m
assert m.clean_text("tab\there\nnew") == "tab\there\nnew"            # tab and newline are text, not danger
assert m.clean_text("a\rb") == "a\\x0db" and m.clean_text("\x9b") == "\\x9b" and m.clean_text("\u2067") == "\\u2067"
PY
echo "Unsafe-name tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
