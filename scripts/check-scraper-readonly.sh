#!/bin/sh
# CI guard: the Tier 0 project scraper must be strictly read-only.
#
# Fails if integrations/after-effects/MographJailed_ProjectScraper.jsx
# contains any AE DOM mutation call. The scraper's only allowed file
# writing is its own output JSON (File.open("w") / writeln / close),
# which is intentionally NOT banned here.
#
# POSIX sh + grep only.

set -u

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
target="$root/integrations/after-effects/MographJailed_ProjectScraper.jsx"

if [ ! -f "$target" ]; then
    echo "SCRAPER_READONLY_FAIL: missing $target" >&2
    exit 1
fi

fail=0
report=""

for pat in \
    '\.save[[:space:]]*\(' \
    '\.remove[[:space:]]*\(' \
    '\.add[[:space:]]*\(' \
    '\.replace[[:space:]]*\(' \
    '\.setValue[[:space:]]*\(' \
    '\.setValueAtTime[[:space:]]*\(' \
    '\.addKey[[:space:]]*\(' \
    '\.removeKey[[:space:]]*\(' \
    '\.duplicate[[:space:]]*\(' \
    'proj\.close[[:space:]]*\(' \
    'project\.close[[:space:]]*\(' \
    'beginUndoGroup' \
    'endUndoGroup' \
    'app\.executeCommand' \
; do
    hits=$(grep -nE "$pat" "$target" || true)
    if [ -n "$hits" ]; then
        fail=1
        report="${report}pattern [$pat]:${hits}
"
    fi
done

if [ "$fail" -ne 0 ]; then
    echo "SCRAPER_READONLY_FAIL: banned mutation pattern found" >&2
    printf '%s' "$report" >&2
    exit 1
fi

echo "SCRAPER_READONLY_OK"
exit 0
