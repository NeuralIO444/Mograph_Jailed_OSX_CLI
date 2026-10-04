#!/usr/bin/env bash
# #38: a project is found by name wherever it is under the projects folder, quickly, without wandering into places
# that are not projects, and with a plain message if the folder is too large to search.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P); trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
export HOME="$TMP/home"; mkdir -p "$HOME/Library/Application Support"; export MJ_CONFIG="$TMP/cfg" MJ_STORE_DIR="$HOME/Library/Application Support/MographJailed" MJ_CLI="$CLI" MJ_AUDIT_DIR="$TMP/noaudit"
mkdir -p "$MJ_STORE_DIR" "$TMP/proj" "$TMP/ver"
mjz(){ zsh -f -c "source '$ROOT/scripts/shell/mj-cli.zsh'; mj $1" > "$TMP/out.txt" 2> "$TMP/err.txt"; echo $? > "$TMP/rc"; }
mjz "config set watch_dir '$TMP/proj' >/dev/null; mj config set versions_dir '$TMP/ver' >/dev/null"
mkp(){ mkdir -p "$(dirname "$1")"; printf '%s' "$2" > "$1"; }

# ---- depth: shallow, studio-deep, and absurdly deep all work
mkp "$TMP/proj/Spot_shallow.aep" a
mkp "$TMP/proj/Acme Corp/2026_Q3_Spring_Campaign/03_Motion/AE/Projects/Spot_30s_v07.aep" b
deep="$TMP/proj"; for i in $(seq 1 25); do deep="$deep/level$i"; done; mkp "$deep/Spot_very_deep.aep" c
for n in Spot_shallow Spot_30s_v07 Spot_very_deep; do
  mjz "snapshot $n"; check test "$(cat "$TMP/rc")" = 0; check grep -q 'Saved a verified copy' "$TMP/out.txt"
done
mjz "snapshot Spot_30s_v07.aep"; check grep -q 'Nothing to save' "$TMP/out.txt"          # same project again, by file name

# ---- places that are not the designer's projects are not searched
mkp "$TMP/proj/Job/Adobe After Effects 2026 Auto-Save/Job-auto-save1.aep" x
mkp "$TMP/proj/Job/Job.aep" y
mkp "$TMP/proj/.Trash/Gone.aep" x
mkp "$TMP/proj/Some.app/Contents/Inner.aep" x
mkp "$TMP/proj/node_modules/pkg/Dep.aep" x
mkp "$TMP/proj/Job/._Job.aep" x
mjz "snapshot Job"; check test "$(cat "$TMP/rc")" = 0                                  # the auto-save copy does not make "Job" ambiguous
for n in Gone Inner Dep; do mjz "snapshot $n"; check test "$(cat "$TMP/rc")" = 66; done
# a symlink loop does not hang the search
ln -s "$TMP/proj" "$TMP/proj/Acme Corp/loop"; mjz "snapshot Spot_30s_v07"; check test "$(cat "$TMP/rc")" = 0

# ---- speed: a big tree is searched in well under a second once, and instantly the second time
python3 - "$TMP/proj/Big" <<'PY'
import os, sys
root = sys.argv[1]
for i in range(60):
    for j in range(30):
        d = os.path.join(root, "client%02d" % i, "job%02d" % j, "Projects")
        os.makedirs(d)
        for k in range(4):
            open(os.path.join(d, "f%d.mov" % k), "w").close()
open(os.path.join(root, "client59", "job29", "Projects", "Needle_Final.aep"), "w").write("needle")
PY
rm -f "$MJ_STORE_DIR/projects-index.json"
t0=$(python3 -c "import time;print(time.time())"); mjz "snapshot Needle_Final"; t1=$(python3 -c "import time;print(time.time())")
check test "$(cat "$TMP/rc")" = 0
check python3 -c "import sys; assert float(sys.argv[2]) - float(sys.argv[1]) < 3.0, float(sys.argv[2]) - float(sys.argv[1])" "$t0" "$t1"
scans1=$(python3 -c "import json;print(json.load(open('$MJ_STORE_DIR/projects-index.json'))['scans'])")
mjz "snapshot Needle_Final"; scans2=$(python3 -c "import json;print(json.load(open('$MJ_STORE_DIR/projects-index.json'))['scans'])")
check test "$scans1" = "$scans2"                                                      # the second lookup used the cached list
# a project saved a moment ago is found even though the cached list is older
mkp "$TMP/proj/Fresh/Brand_New.aep" n; mjz "snapshot Brand_New"; check test "$(cat "$TMP/rc")" = 0
check test "$(python3 -c "import json;print(json.load(open('$MJ_STORE_DIR/projects-index.json'))['scans'])")" -gt "$scans2"
# not found is said plainly, and says it looked everywhere
mjz "snapshot Does_Not_Exist"; check test "$(cat "$TMP/rc")" = 66; check grep -q 'looked in all its folders' "$TMP/err.txt"

# ---- too large to search: stops, says so, and says what to do
MJ_FIND_MAX_ENTRIES=100 mjz "snapshot Does_Not_Exist_Either"
check test "$(cat "$TMP/rc")" = 66; check grep -q 'stopped looking after' "$TMP/err.txt"; check grep -q 'full path' "$TMP/err.txt"

# ---- ~/Library is never searched when the projects folder is the home folder
mkp "$HOME/Library/Caches/Cached_Thing.aep" x; mkp "$HOME/Documents/Real_Doc.aep" r
mjz "config set watch_dir '$HOME' >/dev/null"; mjz "snapshot Cached_Thing"; check test "$(cat "$TMP/rc")" = 66; mjz "snapshot Real_Doc"; check test "$(cat "$TMP/rc")" = 0
echo "Depth tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
