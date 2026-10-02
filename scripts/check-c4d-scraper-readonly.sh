#!/bin/sh
# CI guard: the Cinema 4D scene scraper must be strictly read-only.
#
# Fails if integrations/cinema4d/MographJailed_C4DScraper.py (or the file given as $1, for tests) contains
# a call or assignment that could change a scene, render, run another program, or run dynamic code.
# Its only allowed write is its own new receipt: open(path, "x") in main(), "x" = never overwrite.
#
# A text search. Accepted residual risk: computed attribute access (getattr(obj, "Set" + "Name")(...))
# defeats it, so getattr/setattr/globals are banned outright, and reviewers must reject anything dynamic.
set -u
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
target="${1:-$root/integrations/cinema4d/MographJailed_C4DScraper.py}"
[ -f "$target" ] || { echo "C4D_SCRAPER_READONLY_FAIL: missing $target" >&2; exit 1; }

fail=0; report=""
note() { fail=1; report="${report}$1
"; }
flat=$(tr '\n\r' '  ' < "$target")

# Calls that change a scene, render, save, or reach outside.
NAMES='SaveDocument|Save[A-Za-z]*|InsertObject|InsertMaterial|InsertTag|InsertUnder|InsertAfter|InsertBefore|InsertTake|Insert[A-Z][A-Za-z]*|Remove|Set[A-Z][A-Za-z]*|SendModelingCommand|CallCommand|RenderDocument|Render[A-Za-z]*|AddUndo|StartUndo|EndUndo|Message|MultiMessage|Flush|KillDocument|SetActiveDocument|LoadFile|MergeDocument|InsertRenderData|CopyTo|GetClone|Rename|Delete|Move|Copy|Execute|CreateTake|AddTake|AddCamera|AddMaterial|EventAdd|DrawViews|SetDocument'
hits=$(printf '%s' "$flat" | grep -oE "[A-Za-z0-9_]*\.($NAMES)([[:space:]]|#[^ ]*)*\(" || true)
[ -z "$hits" ] || note "call that can change a scene or reach outside:
$hits"

# Assignment into a scene object, render settings, document or take (rd[...] = ..., doc[...] = ...).
hits=$(grep -nE "(^|[^A-Za-z0-9_])(rd|doc|obj|mat|take|td|cam|post|base|child|item)\[[^]]*\][[:space:]]*[-+*/]?=[^=]" "$target" | grep -vE '^[0-9]+:[[:space:]]*(cam|item)\["(active|path|resolved|missing|absolute)"\][[:space:]]*=' || true)
[ -z "$hits" ] || note "assignment into a Cinema 4D object or setting:
$hits"

# Other programs, files, dynamic code.
for pat in 'import[[:space:]]+(subprocess|shutil|socket|ctypes|importlib|pickle)' 'os\.(system|remove|unlink|rename|replace|rmdir|mkdir|makedirs|popen|exec[a-z]*|spawn[a-z]*|chmod|chown|symlink|link)' \
           '(^|[^A-Za-z0-9_.])(eval|exec|compile|__import__|getattr|setattr|delattr|globals|locals|vars)[[:space:]]*\(' 'subprocess' ; do
    hits=$(grep -nE "$pat" "$target" || true)
    [ -z "$hits" ] || note "forbidden [$pat]:
$hits"
done

# Opening files: reading is fine; the only write is the new receipt, opened exclusively ("x").
hits=$(grep -nE "open[[:space:]]*\([^)]*,[[:space:]]*[\"'][rwabt+]*[wa+][rwabt+]*[\"']" "$target" || true)
[ -z "$hits" ] || note "file opened for write/append/update (only an exclusive \"x\" receipt is allowed):
$hits"
n=$(grep -cE "open[[:space:]]*\([^)]*[\"']x[\"']" "$target" || true)
[ "${n:-0}" -le 1 ] || note "more than one exclusive write ($n); only the receipt may be written"

if [ "$fail" -ne 0 ]; then
    echo "C4D_SCRAPER_READONLY_FAIL: banned pattern found" >&2
    printf '%s' "$report" >&2
    exit 1
fi
echo "C4D_SCRAPER_READONLY_OK"
