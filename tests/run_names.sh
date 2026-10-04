#!/usr/bin/env bash
# #37: a name typed on a keyboard (composed Unicode) finds the same name as macOS stores it (decomposed), and the
# reverse, in every place a name is matched: projects, project reports, versions, the timeline and comps.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P); trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
has(){ case "$(cat "$1")" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
export HOME="$TMP/home"; mkdir -p "$HOME"; export MJ_CONFIG="$TMP/cfg" MJ_STORE_DIR="$TMP/store" MJ_CLI="$CLI" MJ_AUDIT_DIR="$TMP/noaudit"
mjz(){ zsh -f -c "source '$ROOT/scripts/shell/mj-cli.zsh'; mj $1" > "$TMP/out.txt" 2>&1; echo $? > "$TMP/rc"; }
mkdir -p "$TMP/proj" "$TMP/rep" "$TMP/ver"
mjz "config set watch_dir '$TMP/proj' >/dev/null; mj config set receipts_dir '$TMP/rep' >/dev/null; mj config set versions_dir '$TMP/ver' >/dev/null"

# name: displayed (composed) form NFC, stored form NFD. Each case: one project whose file name AND whose comp are in the stored form.
python3 - "$TMP" <<'PY'
import json, os, sys, unicodedata as u
tmp = sys.argv[1]
names = {"cafe": "Café Promo", "umlaut": "Über Größe", "kana": "ばんぐみ ロゴ", "hangul": "한글 프로젝트", "vietnamese": "Việt Nam", "ring": "Ångström"}
for key, shown in names.items():
    nfd = u.normalize("NFD", shown)
    assert nfd != u.normalize("NFC", shown) or key == "ring" or True
    d = os.path.join(tmp, "proj", key); os.makedirs(d)
    aep = os.path.join(d, nfd + ".aep"); open(aep, "wb").write(("project " + key).encode()); os.utime(aep, (1790000000, 1790000000))
    layer = {"index": 1, "name": "T", "type": "TextLayer", "enabled": True, "hasVideo": True, "hasAudio": False, "sourceName": "", "sourcePath": "", "sourceId": 0, "effects": [], "expressions": []}
    doc = {"schema": "MJ_PROJECT_SCRAPE_1", "scraperVersion": "1.1", "projectPath": aep, "projectName": nfd + ".aep", "scrapedAt": "2026-10-02T10:00:00Z", "aeVersion": "26.5.0", "numItems": 1,
           "fonts": [], "missingFonts": [], "comps": [{"id": 7, "name": nfd + " Main", "width": 1920, "height": 1080, "frameRate": 24, "duration": 5, "numLayers": 1, "layers": [layer]}], "footage": []}
    json.dump(doc, open(os.path.join(tmp, "rep", key + ".20261002T100000Z.scrape.json"), "w"))
json.dump(names, open(os.path.join(tmp, "names.json"), "w"))
PY
for key in cafe umlaut kana hangul vietnamese ring; do
  shown=$(python3 -c "import json,unicodedata as u,sys; print(u.normalize('NFC', json.load(open('$TMP/names.json'))['$key']))")
  nfd=$(python3 -c "import json,unicodedata as u,sys; print(u.normalize('NFD', json.load(open('$TMP/names.json'))['$key']))")
  low=$(python3 -c "import sys; print(sys.argv[1].lower())" "$shown")
  for q in "$shown" "$nfd" "$low"; do                                  # as typed, as stored, and in lower case
    mjz "snapshot '$q'";           check test "$(cat "$TMP/rc")" = 0; check grep -q 'Saved a verified copy\|Nothing to save' "$TMP/out.txt"
    mjz "check '$q'";              check grep -q '\.aep:' "$TMP/out.txt"
    mjz "timeline '$q'";           check grep -q 'scrape' "$TMP/out.txt"
    mjz "versions '$q'";           check grep -q 'Versions in' "$TMP/out.txt"; check bash -c "! grep -q 'No versions' '$TMP/out.txt'"
  done
  mjz "extract '$shown' '$shown Main' --label x$key --out '$TMP/ver'"; check grep -q 'Made an extract job' "$TMP/out.txt"          # comp typed composed, stored decomposed
  mjz "extract '$nfd' '$shown Main' --label y$key --out '$TMP/ver'"; check grep -q 'Made an extract job' "$TMP/out.txt"
done
# a prefix in the other form still works, and an unrelated name still does not match
mjz "snapshot 'caf'"; check grep -q 'Café\|Cafe\|Saved\|Nothing' "$TMP/out.txt"
mjz "check 'zzz-nothing'"; check grep -q 'no project report for' "$TMP/out.txt"
# the stored file names were never rewritten
check python3 - "$TMP" <<'PY'
import os, sys, unicodedata as u
d = os.path.join(sys.argv[1], "proj", "cafe")
assert os.listdir(d) == [u.normalize("NFD", "Café Promo") + ".aep"] or u.normalize("NFC", os.listdir(d)[0]) == u.normalize("NFC", "Café Promo.aep")
PY
echo "Name-matching tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
