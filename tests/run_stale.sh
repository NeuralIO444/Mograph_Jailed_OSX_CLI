#!/usr/bin/env bash
# #36: a report older than the project it describes is never presented as the project's current state.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P); trap 'rm -rf "$TMP"' EXIT
export MJ_STORE_DIR="$TMP/store" MJ_AUDIT_DIR="$TMP/noaudit" TZ=UTC
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
has(){ case "$(cat "$1")" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
b64(){ printf '%s' "$1" | base64 | tr -d '\n'; }
run(){ local _out="$1" _cmd="$2"; shift 2; local _f="$TMP/req_$RANDOM$RANDOM.txt"
  { printf 'MOGRAPHJAILED_REQUEST 1\nrequestId=t%s\ncommand=%s\n' "$RANDOM" "$_cmd"; for _a in "$@"; do printf 'arg.%s=%s\n' "${_a%%=*}" "$(b64 "${_a#*=}")"; done; } > "$_f"
  "$CLI" --request "$_f" > "$_out" 2>/dev/null; }
mkdir -p "$TMP/AE/projects/Fresh" "$TMP/AE/receipts"
AEP="$TMP/AE/projects/Fresh/Fresh.aep"; printf v1 > "$AEP"
mk_report(){ # mk_report <file> <scrapedAt>
  python3 - "$AEP" "$1" "$2" <<'PY'
import json, sys
aep, out, at = sys.argv[1:4]
l = {"index": 1, "name": "Title", "type": "TextLayer", "enabled": True, "hasVideo": True, "hasAudio": False, "sourceName": "", "sourcePath": "", "sourceId": 0, "effects": [], "expressions": []}
json.dump({"schema": "MJ_PROJECT_SCRAPE_1", "scraperVersion": "1.1", "projectPath": aep, "projectName": "Fresh.aep", "scrapedAt": at, "aeVersion": "26.5.0", "numItems": 1, "fonts": [], "missingFonts": [],
           "comps": [{"id": 1, "name": "Main", "width": 1920, "height": 1080, "frameRate": 24, "duration": 5, "numLayers": 1, "layers": [l]}], "footage": []}, open(out, "w"))
PY
}
epoch(){ python3 -c "import calendar,time,sys; print(calendar.timegm(time.strptime(sys.argv[1],'%Y-%m-%dT%H:%M:%SZ')))" "$1"; }
set_mtime(){ python3 -c "import os,sys; e=int(sys.argv[2]); os.utime(sys.argv[1], (e, e))" "$AEP" "$(epoch "$1")"; }
codes(){ jq -r '[.warnings[]?.code]|join(",")' "$1"; }

R="$TMP/AE/receipts/fresh.20261001T100000Z.scrape.json"
# ---- project saved BEFORE the report: current, no warning anywhere
mk_report "$R" "2026-10-01T10:00:00Z"; set_mtime "2026-10-01T09:00:00Z"
for op in project.preflight project.ingest expression.lint project.health; do run "$TMP/o.json" $op path="$R"; check jq -e '.ok' "$TMP/o.json"; check test "$(codes "$TMP/o.json")" = ""; done
run "$TMP/p.json" project.preflight path="$R"; check jq -e '.data.reportStale==null' "$TMP/p.json"
# ---- exactly at the report time, and within the 2 s slack: still current
set_mtime "2026-10-01T10:00:02Z"; run "$TMP/o.json" project.preflight path="$R"; check jq -e '.data.reportStale==null' "$TMP/o.json"
# ---- saved after the report: every reading operation says so, in the same words
set_mtime "2026-10-01T10:00:03Z"
for op in project.preflight project.ingest expression.lint project.health; do run "$TMP/o.json" $op path="$R"; check jq -e '.ok' "$TMP/o.json"; check test "$(codes "$TMP/o.json")" = "REPORT_OLDER_THAN_PROJECT"; done
set_mtime "2026-10-02T08:30:00Z"
run "$TMP/p.json" project.preflight path="$R"
check jq -e '.data.reportStale.reportMadeAt=="2026-10-01T10:00:00Z" and .data.reportStale.projectSavedAt=="2026-10-02T08:30:00Z" and .data.ready==false' "$TMP/p.json"
check jq -e '.warnings[0].message|test("older version of the project")' "$TMP/p.json"
# ---- cannot compare: project gone, no path, unreadable date => no warning (never invent one)
mv "$AEP" "$AEP.gone"; run "$TMP/o.json" project.preflight path="$R"; check jq -e '.data.reportStale==null' "$TMP/o.json"; mv "$AEP.gone" "$AEP"
mk_report "$TMP/AE/receipts/bad.scrape.json" "yesterday"; run "$TMP/o.json" project.preflight path="$TMP/AE/receipts/bad.scrape.json"; check jq -e '.ok and .data.reportStale==null' "$TMP/o.json"
# ---- a bare timestamp (older scraper) is local time: 10:00 local in UTC+10 is 00:00Z
mk_report "$TMP/AE/receipts/local.scrape.json" "2026-10-01T10:00:00"
set_mtime "2026-10-01T05:00:00Z"
TZ=Etc/GMT-10 run "$TMP/o.json" project.preflight path="$TMP/AE/receipts/local.scrape.json"; check jq -e '.data.reportStale!=null' "$TMP/o.json"   # report was made 2026-10-01T00:00Z, project saved at 05:00Z
TZ=UTC run "$TMP/o.json" project.preflight path="$TMP/AE/receipts/local.scrape.json"; check jq -e '.data.reportStale==null' "$TMP/o.json"            # report 10:00Z, project 05:00Z
# ---- through mj: the headline, the exit code, and a fresh report clears it
export HOME="$TMP/home" MJ_CONFIG="$TMP/cfg"; mkdir -p "$HOME"
mjz(){ MJ_CLI="$CLI" zsh -f -c "source '$ROOT/scripts/shell/mj-cli.zsh'; $1" > "$TMP/out.txt" 2>&1; echo $? > "$TMP/rc"; }
mjz "mj config set receipts_dir '$TMP/AE/receipts' >/dev/null; mj config set versions_dir '$TMP/v' >/dev/null; mj config set watch_dir '$TMP/AE/projects' >/dev/null"
rm -f "$TMP/AE/receipts/bad.scrape.json" "$TMP/AE/receipts/local.scrape.json"
set_mtime "2026-10-02T08:30:00Z"
mjz "mj check Fresh"
check has "$TMP/out.txt" "Fresh.aep: cannot say yet: this report is older than the project."
check has "$TMP/out.txt" "run the After Effects script on it again"
check bash -c "! grep -q 'Fresh.aep: ready' '$TMP/out.txt'"
check test "$(cat "$TMP/rc")" = 1
mk_report "$TMP/AE/receipts/fresh.20261002T090000Z.scrape.json" "2026-10-02T09:00:00Z"        # the designer ran the script again
mjz "mj check Fresh"
check has "$TMP/out.txt" "Fresh.aep: ready."; check test "$(cat "$TMP/rc")" = 0
echo "Stale-report tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
