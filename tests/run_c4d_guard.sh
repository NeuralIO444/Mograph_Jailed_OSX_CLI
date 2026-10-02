#!/usr/bin/env bash
# The Cinema 4D scraper read-only guard: rejects anything that could change a scene or reach outside; accepts reads.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
GUARD="$ROOT/scripts/check-c4d-scraper-readonly.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
verdict(){ printf 'import c4d\n%s\n' "$1" > "$TMP/s.py"; if sh "$GUARD" "$TMP/s.py" >/dev/null 2>&1; then echo accepted; else echo rejected; fi; }
must_reject(){ [ "$(verdict "$1")" = rejected ] && pass=$((pass+1)) || { echo "FAIL: accepted: $1" >&2; fail=$((fail+1)); }; }
must_accept(){ [ "$(verdict "$1")" = accepted ] && pass=$((pass+1)) || { echo "FAIL: rejected: $1" >&2; fail=$((fail+1)); }; }

check sh "$GUARD"                                                    # the real scraper passes
check bash -c "! sh '$GUARD' '$TMP/missing.py' >/dev/null 2>&1"

for s in 'c4d.documents.SaveDocument(doc, p, 0, 0)' 'doc.InsertObject(o)' 'doc.InsertMaterial(m)' 'obj.InsertTag(t)' 'obj.Remove()' 'obj.SetName("x")' \
         'obj.SetMg(m)' 'obj.SetAbsPos(v)' 'doc.SetFps(30)' 'doc.SetMaxTime(t)' 'rd[c4d.RDATA_XRES] = 10' 'doc[c4d.DOCUMENT_X] = 1' 'obj[c4d.ID] += 1' \
         'c4d.CallCommand(12098)' 'c4d.documents.RenderDocument(doc, rd, bmp, 0)' 'c4d.EventAdd()' 'doc.StartUndo()' 'c4d.documents.KillDocument(doc)' \
         'c4d.documents.MergeDocument(doc, p, 0)' 'c4d.utils.SendModelingCommand(1, [o])' 'take.SetName("x")' 'obj.Message(c4d.MSG_UPDATE)' \
         'import subprocess' 'import shutil' 'import ctypes' 'os.system("x")' 'os.remove(p)' 'os.rename(a, b)' 'os.makedirs(d)' 'os.popen("x")' \
         'eval("1")' 'exec("x = 1")' 'getattr(obj, "Remove")()' 'setattr(obj, "a", 1)' '__import__("os")' 'globals()' \
         'f = open(p, "w")' 'f = open(p, "a")' "f = open(p, 'w')" 'f = open(p, "r+")'; do must_reject "$s"; done
# only one exclusive write is allowed: the receipt
must_reject $'open(a, "x")\nopen(b, "x")'
must_accept 'fps = doc.GetFps()'
must_accept $'cam = {}\ncam["active"] = True'
must_accept 'with open(path, "x", encoding="utf-8") as f:
    f.write("x")'
must_accept 'with open(path) as f:
    data = f.read()'
must_accept 'for obj in iter_objects(doc.GetFirstObject()):
    name = obj.GetName()'
must_accept 'rd = doc.GetActiveRenderData(); w = rd[c4d.RDATA_XRES]'

echo "C4D scraper guard tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
