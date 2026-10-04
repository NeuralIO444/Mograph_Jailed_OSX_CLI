#!/usr/bin/env bash
# #43: names far longer than After Effects allows (255 characters) cannot flood the terminal or slow a check down.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P); trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
export HOME="$TMP/home"; mkdir -p "$HOME"; export MJ_CONFIG="$TMP/cfg" MJ_STORE_DIR="$TMP/store" MJ_CLI="$CLI" MJ_AUDIT_DIR="$TMP/noaudit"
mkdir -p "$TMP/proj/Bomb" "$TMP/rep" "$TMP/ver"; printf bomb > "$TMP/proj/Bomb/Bomb.aep"; touch -t 202609210000 "$TMP/proj/Bomb/Bomb.aep"
python3 - "$TMP" <<'PY'
import json, os, sys
tmp = sys.argv[1]
def L(i, name, ex=()):
    return {"index": i, "name": name, "type": "TextLayer", "enabled": True, "hasVideo": True, "hasAudio": False, "sourceName": "", "sourcePath": "", "sourceId": 0, "effects": [],
            "expressions": [{"propertyPath": "Transform/Position", "expression": e} for e in ex]}
big = "N" * 100000
layers = [L(i, "L%d" % i, ['thisComp.layer("Ghost%d").x' % i]) for i in range(1, 60)]
short_layers = [L(1, "ok"), L(2, "X" * 1_000_000), L(3, "Y" * 255), L(4, "Z" * 256)]
doc = {"schema": "MJ_PROJECT_SCRAPE_1", "scraperVersion": "1.1", "projectPath": os.path.join(tmp, "proj", "Bomb", "Bomb.aep"), "projectName": "Bomb.aep", "scrapedAt": "2026-10-02T10:00:00Z", "aeVersion": "26.5.0",
       "numItems": 3, "fonts": ["F" * 100000], "missingFonts": [], "comps": [{"id": 1, "name": big, "width": 1920, "height": 1080, "frameRate": 24, "duration": 5, "numLayers": len(layers), "layers": layers},
                                                                              {"id": 2, "name": "Short", "width": 1920, "height": 1080, "frameRate": 24, "duration": 5, "numLayers": len(short_layers), "layers": short_layers}],
       "footage": [{"id": 5, "name": "clip" + "c" * 500000, "path": "/nonexistent/clip.mov", "missing": True, "hasVideo": True, "hasAudio": False, "folder": ""}]}
json.dump(doc, open(os.path.join(tmp, "rep", "bomb.20261002T100000Z.scrape.json"), "w"))
PY
R="$TMP/rep/bomb.20261002T100000Z.scrape.json"
b64(){ printf '%s' "$1" | base64 | tr -d '\n'; }
op(){ local out="$1" cmd="$2"; shift 2; { printf 'MOGRAPHJAILED_REQUEST 1\nrequestId=t\ncommand=%s\n' "$cmd"; for a in "$@"; do printf 'arg.%s=%s\n' "${a%%=*}" "$(b64 "${a#*=}")"; done; } > "$TMP/req"; "$CLI" --request "$TMP/req" > "$out" 2>/dev/null; }
now(){ python3 -c "import time;print(time.time())"; }
under(){ python3 -c "import sys; assert float(sys.argv[2])-float(sys.argv[1]) < float(sys.argv[3]), float(sys.argv[2])-float(sys.argv[1])" "$1" "$2" "$3"; }

# ---- the engines: bounded responses, quickly
t0=$(now); op "$TMP/lint.json" expression.lint path="$R"; t1=$(now)
check jq -e '.ok and (.data.findings|length)>0' "$TMP/lint.json"; check under "$t0" "$t1" 3; check test "$(wc -c < "$TMP/lint.json")" -lt 400000
check jq -e '[.data.findings[]|.comp|length]|max<=255' "$TMP/lint.json"; check jq -e '.data.findings[0].comp|test("characters\\)$")' "$TMP/lint.json"
op "$TMP/plan.json" project.conform input="$R"
check jq -e '.ok and ([.warnings[].code]|index("NAME_TOO_LONG"))!=null' "$TMP/plan.json"; check test "$(wc -c < "$TMP/plan.json")" -lt 200000
check jq -e '.data.plan.nameTooLong==3' "$TMP/plan.json"                                       # the 100,000-char comp, the 1,000,000-char layer and the 256-char layer
check jq -e '[.data.plan.layerRenames[]|.from|length]|max<=255' "$TMP/plan.json"
check jq -e '[.data.plan.layerRenames[]|select(.from|length==255)]|length==1' "$TMP/plan.json"  # exactly 255 is a legal After Effects name: still planned
check jq -e '[.data.plan.layerRenames[]|select(.comp=="Short")]|length==2' "$TMP/plan.json"      # "ok" and the 255-character layer
# a job built from it never carries the oversize names
op "$TMP/job.json" project.conform input="$R" format=job path="$TMP/proj/Bomb/Bomb.aep" output="$TMP/ver" label=big
check jq -e '.ok' "$TMP/job.json"; check test "$(wc -c < "$TMP/ver/big.mjjob/plan.json")" -lt 100000

# ---- the commands a person types: fast, and the screen is not flooded
for line in "check Bomb" "lint Bomb" "health Bomb" "conform Bomb" "timeline Bomb" "explain '$R'"; do
  t0=$(now); zsh -f -c "source '$ROOT/scripts/shell/mj-cli.zsh'; mj config set watch_dir '$TMP/proj' >/dev/null; mj config set receipts_dir '$TMP/rep' >/dev/null; mj config set versions_dir '$TMP/ver' >/dev/null; mj $line" > "$TMP/o.txt" 2> "$TMP/e.txt"; t1=$(now)
  check under "$t0" "$t1" 5; check test "$(cat "$TMP/o.txt" "$TMP/e.txt" | wc -c)" -lt 200000
  check python3 - "$TMP/o.txt" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8", errors="replace").read()
assert not re.search(r"\S{200,}", t), "a single word of 200+ characters reached the screen"
PY
done
zsh -f -c "source '$ROOT/scripts/shell/mj-cli.zsh'; mj lint Bomb" 2>&1 | grep -q 'characters)' && pass=$((pass+1)) || { echo "FAIL: the cut is marked with the real length" >&2; fail=$((fail+1)); }
echo "Long-name tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
