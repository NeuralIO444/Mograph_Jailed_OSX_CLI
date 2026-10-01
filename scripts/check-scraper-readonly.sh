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
# Accepted residual risk: this is a text search. Calling an indexed value (x["set"](...)) is
# rejected, but other ways of computing a method name defeat any text search, so reviewers must
# reject computed member access in this file. A banned name inside a comment is rejected too.
#
# POSIX sh + grep only.

set -u

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
target="${1:-$root/integrations/after-effects/MographJailed_ProjectScraper.jsx}"

# Local objects the scraper builds itself. Adding a name here is a deliberate act.
LOCAL_RECEIVERS='rec'
# The one file the scraper may write: its own output receipt.
OUTPUT_FILE_RECEIVERS='outFile'

# Settable AE DOM properties (assignment to these on an AE object mutates the project).
PROPS='expression|expressionEnabled|enabled|name|locked|solo|shy|comment|label|parent|width|height|duration|frameRate|pixelAspect|displayStartTime|workAreaStart|workAreaDuration|time|startTime|inPoint|outPoint|stretch|blendingMode|motionBlur|threeDLayer|adjustmentLayer|selected|bgColor|useProxy|audioEnabled|guideLayer|collapseTransformation|autoOrient|preserveTransparency|effectsActive|quality|samplingQuality|source|file|value|text|sourceText|font|fontSize|fillColor|strokeColor|position|scale|rotation|opacity|anchorPoint|transform|trackMatteType|isTrackMatte|timeRemapEnabled|canSetTimeRemapEnabled|bitsPerChannel|linearBlending|audioActive|framesCountType|displayStartFrame|feetFramesFilmType|timeDisplayType|workingSpace|expressionEngine|transparencyGridThumbnails|footageTimecodeDisplayStartType|framesUseFeetFrames|gpuAccelType|colorManagementSystem|workingGamma|compensateForSceneReferredProfiles|nativeSource|useCollapsedTransform|ignoreRepeat'

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

# 1b. The same calls, written so a line-based search misses them: the name and "(" split across
# lines or separated by a /* comment */. Flatten the file and allow comments/space before "(".
NAMES='save|saveWithDialog|duplicate|replace|add[A-Za-z]*|remove[A-Za-z]*|set[A-Z][A-Za-z]*|move[A-Z][A-Za-z]*|import[A-Z][A-Za-z]*|copyToComp|autoFixExpressions|replaceSource|createNewFolder|reduceMemoryUsage|applyPreset|precompose|render|reduceProject|consolidateFootage|openInViewer|rename|copy|execute|createAlias|scheduleTask|saveSetting|cancelTask|callSystem'
flat=$(tr '\n\r' '  ' < "$target")
hits=$(printf '%s' "$flat" | grep -oE "[A-Za-z0-9_]*\.($NAMES)([[:space:]]|/\*[^*]*\*/)*\(" || true)
[ -z "$hits" ] || note "mutating call (possibly split over lines or a comment):
$hits"

# 1c. Writing files: the scraper may open only its own output file for writing; any other
# open(...) for write/append/edit, a rename, or a computed receiver is rejected.
hits=$(grep -noE "[A-Za-z_][A-Za-z0-9_]*[])]?\.open[[:space:]]*\([[:space:]]*[\"'][wae]" "$target" | grep -vE "^[0-9]+:($OUTPUT_FILE_RECEIVERS)\.open" || true)
[ -z "$hits" ] || note "file opened for writing other than the scraper's own output [$OUTPUT_FILE_RECEIVERS]:
$hits"
hits=$(printf '%s' "$flat" | grep -oE "\)[[:space:]]*\.open[[:space:]]*\(" || true)
[ -z "$hits" ] || note "open() called on a call result (new File(...).open(...)):
$hits"

# 1d. Calling the result of an index or call, x[i](...) / f()(...): computed dispatch a text
# search cannot see through.
hits=$(printf '%s' "$flat" | grep -oE "[A-Za-z0-9_]*\][[:space:]]*\(" || true)
[ -z "$hits" ] || note "call of an indexed value (computed dispatch):
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
