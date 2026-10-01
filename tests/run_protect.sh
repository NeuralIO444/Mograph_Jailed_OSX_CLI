#!/usr/bin/env bash
# Phase 8 "protect work": project.restore, deps.graph, handoff.package.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
b64(){ printf '%s' "$1" | base64 | tr -d '\n'; }
run(){
  local _out="$1" _cmd="$2"; shift 2
  local _f="$TMP/req_$RANDOM$RANDOM.txt"
  { printf 'MOGRAPHJAILED_REQUEST 1\nrequestId=t%s\ncommand=%s\n' "$RANDOM" "$_cmd"
    for _a in "$@"; do printf 'arg.%s=%s\n' "${_a%%=*}" "$(b64 "${_a#*=}")"; done; } > "$_f"
  "$CLI" --request "$_f" > "$_out" 2>/dev/null || true
}
sum(){ cat "$@" | cksum; }

# --- fixtures ---
mkdir -p "$TMP/proj" "$TMP/media/seq" "$TMP/versions" "$TMP/restored" "$TMP/out"
printf 'aep-v1-bytes' > "$TMP/proj/hero.aep"
printf 'mp4-bytes' > "$TMP/media/bg.mp4"
for i in 0001 0002 0003; do printf "frame$i" > "$TMP/media/seq/img_$i.png"; done
printf 'unrelated' > "$TMP/media/seq/other_0001.png"
cat > "$TMP/scrape.json" <<J
{"schema":"MJ_PROJECT_SCRAPE_1","scraperVersion":"1.0","projectPath":"$TMP/proj/hero.aep",
 "projectName":"hero.aep","scrapedAt":"2026-10-01T00:00:00Z","aeVersion":"24.6.0","numItems":6,
 "fonts":["Inter","Helvetica Neue"],
 "footage":[{"name":"bg.mp4","path":"$TMP/media/bg.mp4","missing":false},
            {"name":"img_[0001-0003].png","path":"$TMP/media/seq/img_0001.png","missing":false},
            {"name":"gone.mov","path":"$TMP/media/gone.mov","missing":true}],
 "comps":[
  {"name":"Main","layers":[
    {"name":"BG","type":"AVLayer","sourceName":"bg.mp4","sourcePath":"$TMP/media/bg.mp4","effects":[{"name":"Glow","matchName":"ADBE Glo2"}]},
    {"name":"Pre","type":"AVLayer","sourceName":"Pre","sourcePath":"","effects":[]},
    {"name":"Title","type":"TextLayer","sourceName":"","sourcePath":"","effects":[]}]},
  {"name":"Pre","layers":[
    {"name":"Seq","type":"AVLayer","sourceName":"img","sourcePath":"$TMP/media/seq/img_0001.png","effects":[{"name":"Glow","matchName":"ADBE Glo2"}]},
    {"name":"Gone","type":"AVLayer","sourceName":"gone.mov","sourcePath":"$TMP/media/gone.mov","effects":[]}]},
  {"name":"Other","layers":[
    {"name":"Pre","type":"AVLayer","sourceName":"Pre","sourcePath":"","effects":[]}]}
 ]}
J
SRC_SUM=$(sum "$TMP/proj/hero.aep" "$TMP/media/bg.mp4" "$TMP"/media/seq/*)

# --- project.restore ---
run "$TMP/snap.json" project.snapshot "path=$TMP/proj/hero.aep" "output=$TMP/versions"
SNAP=$(jq -r '.data.snapshotPath' "$TMP/snap.json")
run "$TMP/r1.json" project.restore "path=$SNAP" "output=$TMP/restored"
check jq -e '.ok==true and .data.schema=="MJ_PROJECT_RESTORE_1" and .data.receiptVerified==true' "$TMP/r1.json"
R1=$(jq -r '.data.restoredPath' "$TMP/r1.json")
check cmp -s "$R1" "$TMP/proj/hero.aep"
run "$TMP/r2.json" project.restore "path=$SNAP" "output=$TMP/restored"
R2=$(jq -r '.data.restoredPath' "$TMP/r2.json")
check test -f "$R2" -a "$R1" != "$R2"
check test "$(ls -A "$TMP/restored" | wc -l | tr -d ' ')" = 2      # no partial files left
# a snapshot whose bytes no longer match its receipt is refused
cp "$SNAP" "$TMP/versions/tampered.aep"; cp "$SNAP.snapshot.json" "$TMP/versions/tampered.aep.snapshot.json"
printf 'x' >> "$TMP/versions/tampered.aep"
run "$TMP/r3.json" project.restore "path=$TMP/versions/tampered.aep" "output=$TMP/restored"
check jq -e '.error.code=="SNAPSHOT_CORRUPT"' "$TMP/r3.json"
check test "$(ls -A "$TMP/restored" | wc -l | tr -d ' ')" = 2
# no receipt: restores, but says it could not verify
cp "$TMP/proj/hero.aep" "$TMP/versions/loose.aep"
run "$TMP/r4.json" project.restore "path=$TMP/versions/loose.aep" "output=$TMP/restored"
check jq -e '.ok==true and .data.receiptVerified==false' "$TMP/r4.json"
run "$TMP/r5.json" project.restore "path=$TMP/scrape.json" "output=$TMP/restored"
check jq -e '.error.code=="INVALID_TARGET"' "$TMP/r5.json"
run "$TMP/r6.json" project.restore "path=$SNAP" "output=relative"
check jq -e '.error.code=="INVALID_PATH"' "$TMP/r6.json"

# --- deps.graph ---
run "$TMP/g.json" deps.graph "path=$TMP/scrape.json"
check jq -e '.ok==true and .data.schema=="MJ_DEPS_GRAPH_1"' "$TMP/g.json"
check jq -e --arg p "$TMP/media/gone.mov" '.data.missingFootage==[$p]' "$TMP/g.json"
# sequence footage used only by Pre still impacts Main and Other through nesting
check jq -e --arg p "$TMP/media/seq/img_0001.png" '(.data.dependencies[]|select(.id==$p)) | .directUsers==["Pre"] and .impactedComps==["Main","Other","Pre"] and .missing==false and .storage=="local"' "$TMP/g.json"
check jq -e '.data.singlePointsOfFailure[0].id=="ADBE Glo2" and (.data.singlePointsOfFailure[0].impactedComps|length)==3' "$TMP/g.json"
check jq -e '(.data.comps[]|select(.name=="Main")) | .precomps==["Pre"] and .usesText==true' "$TMP/g.json"
check jq -e '.data.fonts==["Helvetica Neue","Inter"]' "$TMP/g.json"
run "$TMP/g2.json" deps.graph "path=$TMP/proj/hero.aep"
check jq -e '.error.code=="INVALID_JSON"' "$TMP/g2.json"

# --- handoff.package ---
run "$TMP/h.json" handoff.package "path=$TMP/proj/hero.aep" "input=$TMP/scrape.json" "output=$TMP/out" "label=hero_delivery"
H="$TMP/out/hero_delivery.handoff"
check jq -e '.ok==true and .data.filesCollected==4 and .data.projectMatchesScrape==true' "$TMP/h.json"
check cmp -s "$H/project/hero.aep" "$TMP/proj/hero.aep"
check cmp -s "$H/footage/bg.mp4" "$TMP/media/bg.mp4"
check test "$(ls "$H/footage/img")" = "$(printf 'img_0001.png\nimg_0002.png\nimg_0003.png')"
check test ! -e "$H/.incomplete"
check jq -e --arg p "$TMP/media/gone.mov" '.schema=="MJ_HANDOFF_1" and .missingFootage==[$p] and (.files|length)==4 and .fonts==["Helvetica Neue","Inter"]' "$H/MANIFEST.json"
# manifest hashes describe the packaged bytes
check python3 - "$H" <<'PY'
import hashlib, json, os, sys
h = sys.argv[1]; m = json.load(open(os.path.join(h, "MANIFEST.json")))
assert all(hashlib.sha256(open(os.path.join(h, f["packaged"]), "rb").read()).hexdigest() == f["sha256"] for f in m["files"])
PY
check grep -q 'Inter' "$H/README.txt"
check grep -q 'MISSING footage' "$H/README.txt"
H_SUM=$(find "$H" -type f -exec cksum {} + | sort)
run "$TMP/h2.json" handoff.package "path=$TMP/proj/hero.aep" "input=$TMP/scrape.json" "output=$TMP/out" "label=hero_delivery"
check jq -e '.error.code=="OUTPUT_EXISTS"' "$TMP/h2.json"
check test "$(find "$H" -type f -exec cksum {} + | sort)" = "$H_SUM"
run "$TMP/h3.json" handoff.package "path=$TMP/proj/hero.aep" "input=$TMP/scrape.json" "output=$TMP/out" "label=../escape"
check jq -e '.error.code=="INVALID_ARGUMENT"' "$TMP/h3.json"
check test "$(ls -A "$TMP/out")" = "hero_delivery.handoff"

# --- storage classification rules (mount table parsing; no network needed) ---
cat > "$TMP/mounts_test.py" <<'PY'
_MOUNTS = parse_mounts('''/dev/disk3s1s1 on / (apfs, sealed, local, read-only, journaled)
//user@nas/Footage on /Volumes/Footage (smbfs, nodev, nosuid, mounted by user)
/dev/disk5s1 on /Volumes/Footage Local (apfs, local, nodev)
/dev/sda1 on /data type ext4 (rw,relatime)
server:/x on /mnt/nfs type nfs4 (rw)''')
assert storage_class('/Users/me/a.mov') == 'local'
assert storage_class('/Volumes/Footage/shot.mov') == 'network'
assert storage_class('/Volumes/Footage Local/shot.mov') == 'local'
assert storage_class('/Volumes/FootageX/shot.mov') == 'local'
assert storage_class('/mnt/nfs/a') == 'network' and storage_class('/data/a') == 'local'
assert storage_class("relative/x") == "unknown"
PY
zsh -f -c "source '$ROOT/src/modules/protect.zsh'; print -r -- \"\$MJ_PY_PROTECT_LIB\"" > "$TMP/mounts_lib.py"
check bash -c "cat '$TMP/mounts_lib.py' '$TMP/mounts_test.py' | python3 -"

check test "$(sum "$TMP/proj/hero.aep" "$TMP/media/bg.mp4" "$TMP"/media/seq/*)" = "$SRC_SUM"

echo "Protect-work tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
