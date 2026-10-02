#!/usr/bin/env bash
# The After Effects job-runner guard: the real runner passes; one added line of anything that could touch
# the original project, save elsewhere, or run code makes it fail.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
GUARD="$ROOT/scripts/check-job-runner.sh"
RUNNER="$ROOT/integrations/after-effects/MographJailed_JobRunner.jsx"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
must_reject(){ { cat "$RUNNER"; printf '%s\n' "$1"; } > "$TMP/r.jsx"; if sh "$GUARD" "$TMP/r.jsx" >/dev/null 2>&1; then echo "FAIL: accepted: $1" >&2; fail=$((fail+1)); else pass=$((pass+1)); fi; }

check sh "$GUARD"
check bash -c "! sh '$GUARD' '$TMP/missing.jsx' >/dev/null 2>&1"
for s in 'app.open(new File(P.source.path));' 'app.open(other);' 'app.project.save();' 'app.project.save(workFile);' 'app.project.saveWithDialog();' \
         'app.project.close(CloseOptions.SAVE_CHANGES);' 'system.callSystem("rm -rf ~");' 'eval("1");' 'var f = new Function("x");' '$.evalFile(x);' \
         'app.executeCommand(2);' 'app.project.importFile(io);' 'receiptFile.remove();' 'workFile.rename("x");' 'workFile.copy("/tmp/x");' 'workFile.execute();' \
         'app.project.consolidateFootage();' 'app.project.removeUnusedFootage();' 'app.quit();' 'app.newProject();' 'var d = new Folder("/x");' \
         'var d = Folder.selectDialog("x");' 'it.replaceWithSolid([0,0,0], "x", 1, 1, 1);' 'it.changePath();' 'x["save"](resultFile);' \
         'var f = new File(P.receipt + "/../../x");' 'var f = new File("/etc/x");' 'logFile.open("w");' 'other.open("a");'; do
  must_reject "$s"
done
echo "Job runner guard tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
