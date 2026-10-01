#!/bin/sh
# CI guard: the Tier 0 project scraper must be strictly read-only.
#
# Fails if integrations/after-effects/MographJailed_ProjectScraper.jsx (or the file
# given as $1, used by tests) contains an After Effects DOM mutation or a way to run
# arbitrary code. The scraper's only allowed writes are to its own output JSON
# (File.open("w") / write / writeln / close) and to its own local record objects.
#
# Checks, all by static text search:
#   1. mutating method calls: whole families (add*, remove*, set*, move*) plus named
#      calls (save, duplicate, importFile, autoFixExpressions, callSystem, ...)
#   2. assignments to settable AE properties (prop.expression = ..., layer.enabled = ...);
#      assignments whose receiver is one of LOCAL_RECEIVERS are the scraper's own records
#   3. dynamic code (eval, new Function, evalFile)
#
# Accepted residual risk: bracket notation or other dynamic dispatch
# (x["set" + "Value"](...)) defeats any text search. Reviewers must reject computed
# member access in this file.
#
# POSIX sh + grep only.

set -u

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
target="${1:-$root/integrations/after-effects/MographJailed_ProjectScraper.jsx}"

# Local objects the scraper builds itself. Adding a name here is a deliberate act.
LOCAL_RECEIVERS='rec'

# Settable AE DOM properties (assignment to these on an AE object mutates the project).
PROPS='expression|expressionEnabled|enabled|name|locked|solo|shy|comment|label|parent|width|height|duration|frameRate|pixelAspect|displayStartTime|workAreaStart|workAreaDuration|time|startTime|inPoint|outPoint|stretch|blendingMode|motionBlur|threeDLayer|adjustmentLayer|selected|bgColor|useProxy|audioEnabled|guideLayer|collapseTransformation|autoOrient|preserveTransparency|effectsActive|quality|samplingQuality|source|file|value|text|sourceText|font|fontSize|fillColor|strokeColor|position|scale|rotation|opacity|anchorPoint|transform|trackMatteType|isTrackMatte|timeRemapEnabled|canSetTimeRemapEnabled'

if [ ! -f "$target" ]; then
    echo "SCRAPER_READONLY_FAIL: missing $target" >&2
    exit 1
fi

fail=0
report=""

note() { fail=1; report="${report}$1
"; }

# 1. Mutating method calls.
for pat in \
    '\.save[[:space:]]*\(' \
    '\.saveWithDialog[[:space:]]*\(' \
    '\.duplicate[[:space:]]*\(' \
    '\.replace[[:space:]]*\(' \
    '\.add[A-Za-z]*[[:space:]]*\(' \
    '\.remove[A-Za-z]*[[:space:]]*\(' \
    '\.set[A-Z][A-Za-z]*[[:space:]]*\(' \
    '\.move[A-Z][A-Za-z]*[[:space:]]*\(' \
    '\.import[A-Z][A-Za-z]*[[:space:]]*\(' \
    '\.copyToComp[[:space:]]*\(' \
    '\.autoFixExpressions[[:space:]]*\(' \
    '\.replaceSource[[:space:]]*\(' \
    '\.createNewFolder[[:space:]]*\(' \
    '\.reduceMemoryUsage[[:space:]]*\(' \
    'proj\.close[[:space:]]*\(' \
    'project\.close[[:space:]]*\(' \
    'beginUndoGroup' \
    'endUndoGroup' \
    'app\.executeCommand' \
    'app\.(open|newProject|quit|purge)[[:space:]]*\(' \
    'callSystem' \
; do
    hits=$(grep -nE "$pat" "$target" || true)
    [ -z "$hits" ] || note "mutating call [$pat]:
$hits"
done

# 2. Assignments to settable AE properties (=, +=, -=, *=, /=; not ==).
# Receiver is the first identifier of the chain; allowed only if it is a local record.
hits=$(grep -noE "[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*\.($PROPS)[[:space:]]*[-+*/]?=[^=]" "$target" \
    | grep -vE "^[0-9]+:($LOCAL_RECEIVERS)\." || true)
[ -z "$hits" ] || note "assignment to an AE property [receiver not in LOCAL_RECEIVERS]:
$hits"
# Assignment onto the result of a call or index: item(1).name = ..., layers[2].enabled = ...
hits=$(grep -nE "[])]\.($PROPS)[[:space:]]*[-+*/]?=[^=]" "$target" || true)
[ -z "$hits" ] || note "assignment onto a call or index result:
$hits"

# 3. Dynamic code.
for pat in \
    '(^|[^.A-Za-z_])eval[[:space:]]*\(' \
    'new[[:space:]]+Function' \
    'evalFile' \
    '\$\.eval' \
; do
    hits=$(grep -nE "$pat" "$target" || true)
    [ -z "$hits" ] || note "dynamic code [$pat]:
$hits"
done

if [ "$fail" -ne 0 ]; then
    echo "SCRAPER_READONLY_FAIL: banned mutation pattern found" >&2
    printf '%s' "$report" >&2
    exit 1
fi

echo "SCRAPER_READONLY_OK"
exit 0
