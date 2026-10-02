#!/bin/sh
# CI guard: the After Effects job runner may change only the job's own copy and write only new files.
#
# integrations/after-effects/MographJailed_JobRunner.jsx (or $1, used by tests) must:
#   - open exactly one project, the job's copy:            app.open(workFile)
#   - save exactly once, to the new result file:           app.project.save(resultFile)
#   - close only without saving or with the user's prompt: CloseOptions.DO_NOT_SAVE_CHANGES / PROMPT_TO_SAVE_CHANGES
#   - make File objects only from the plan's paths:        new File(P.work|P.result|P.receipt|P.quietFlag)
#   - open only its receipt for writing:                   receiptFile.open("w")
#   - never run programs, dynamic code or menu commands, import, delete, rename or copy files.
# A static text search, like scripts/check-scraper-readonly.sh: reviewers must also reject computed
# member access (x["save"](...)) in this file, which the last rule catches only for indexed calls.
set -u
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
target="${1:-$root/integrations/after-effects/MographJailed_JobRunner.jsx}"
[ -f "$target" ] || { echo "JOB_RUNNER_FAIL: missing $target" >&2; exit 1; }
fail=0
note() { fail=1; echo "JOB_RUNNER_FAIL: $1" >&2; }
count() { grep -oE "$1" "$target" | wc -l | tr -d ' '; }
flat=$(tr '\n\r' '  ' < "$target")

[ "$(count 'app\.open[[:space:]]*\(')" = 1 ] || note "app.open must appear exactly once"
[ "$(count 'app\.open\(workFile\)')" = 1 ] || note "app.open may open only workFile"
[ "$(count '\.save[A-Za-z]*[[:space:]]*\(')" = 1 ] || note ".save must appear exactly once"
[ "$(count 'app\.project\.save\(resultFile\)')" = 1 ] || note "the one save must be app.project.save(resultFile)"
hits=$(grep -noE 'CloseOptions\.[A-Z_]+' "$target" | grep -vE 'CloseOptions\.(DO_NOT_SAVE_CHANGES|PROMPT_TO_SAVE_CHANGES)$' || true)
[ -z "$hits" ] || note "close may not save: $hits"
hits=$(printf '%s' "$flat" | grep -oE 'new[[:space:]]+File[[:space:]]*\([^)]*\)' | grep -vE '^new File\(P\.(work|result|receipt|quietFlag)\)$' || true)
[ -z "$hits" ] || note "File objects may come only from P.work, P.result, P.receipt: $hits"
hits=$(grep -noE '[A-Za-z_]+\.open[[:space:]]*\([[:space:]]*"[wae]' "$target" | grep -vE ':receiptFile\.open' || true)
[ -z "$hits" ] || note "only receiptFile may be opened for writing: $hits"
for pat in 'callSystem' '(^|[^.A-Za-z_])eval[[:space:]]*\(' 'new[[:space:]]+Function' 'evalFile' '\$\.eval' 'executeCommand' \
           'import[A-Z][A-Za-z]*[[:space:]]*\(' '\.remove[A-Za-z]*[[:space:]]*\(' '\.rename[[:space:]]*\(' '\.copy[[:space:]]*\(' '\.execute[[:space:]]*\(' \
           'consolidateFootage' 'removeUnusedFootage' 'saveWithDialog' 'app\.(quit|newProject|purge)' 'system\.' 'new[[:space:]]+Folder' 'Folder\.[a-z]' '\.changePath' '\.replace[A-Z][A-Za-z]*[[:space:]]*\('; do
  hits=$(grep -nE "$pat" "$target" || true)
  [ -z "$hits" ] || note "banned [$pat]: $hits"
done
hits=$(printf '%s' "$flat" | grep -oE '[A-Za-z0-9_]*\][[:space:]]*\(' || true)
[ -z "$hits" ] || note "call of an indexed value (computed dispatch): $hits"
[ "$fail" -eq 0 ] && echo "JOB_RUNNER_OK"
exit "$fail"
