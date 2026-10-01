#!/usr/bin/env bash
# #13 --help/--version and #24 error-code table: documented, complete, and matching behavior.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
PROD="$ROOT/dist/mograph-jailed.zsh"
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
export MJ_STORE_DIR="$TMP/store" MJ_AUDIT_DIR="$TMP/audit"
pass=0; fail=0
check(){ if "$@"; then pass=$((pass+1)); else echo "FAIL: $*" >&2; fail=$((fail+1)); fi; }
b64(){ printf '%s' "$1" | base64 | tr -d '\n'; }
runx(){ # runx <outfile> <cmd> [name=value...]; prints exit code
  local _out="$1" _cmd="$2"; shift 2
  local _f="$TMP/req_$RANDOM.txt"
  { printf 'MOGRAPHJAILED_REQUEST 1\nrequestId=t%s\ncommand=%s\n' "$RANDOM" "$_cmd"
    for _a in "$@"; do printf 'arg.%s=%s\n' "${_a%%=*}" "$(b64 "${_a#*=}")"; done; } > "$_f"
  set +e; "$CLI" --request "$_f" > "$_out" 2>/dev/null; local rc=$?; set -e; echo $rc
}

# --- #13: --help / --version ---
set +e; "$PROD" --version > "$TMP/v.txt" 2>&1; rcv=$?; "$PROD" --help > "$TMP/h.txt" 2>&1; rch=$?; "$PROD" -V > "$TMP/v2.txt"; "$PROD" -h > "$TMP/h2.txt"; set -e
check test "$rcv" = 0 -a "$rch" = 0
VER=$(sed -n 's/^MOGRAPHJAILED_CLI_VERSION="\(.*\)"$/\1/p' "$ROOT/src/core/constants.zsh")
check test "$(cat "$TMP/v.txt")" = "mograph-jailed $VER (protocol 1)"
check cmp -s "$TMP/v.txt" "$TMP/v2.txt"
check cmp -s "$TMP/h.txt" "$TMP/h2.txt"
check grep -q 'Usage:' "$TMP/h.txt"
check grep -q 'Exit codes:' "$TMP/h.txt"
# every operation appears with a summary, and the count matches the registry
run_desc=$(runx "$TMP/d.json" system.describe)
N_OPS=$(jq '.data.operations|length' "$TMP/d.json")
check test "$(sed -n '/^Operations:/,$p' "$TMP/h.txt" | tail -n +2 | wc -l | tr -d ' ')" = "$N_OPS"
check bash -c "jq -r '.data.operations|keys[]' '$TMP/d.json' | while read -r op; do grep -qE \"^  \${op//./\\\\.} +[A-Z]\" '$TMP/h.txt' || exit 1; done"
# summaries are published through system.describe and none is empty or too long
check jq -e '[.data.operations[] | .summary | (type=="string" and length>=10 and length<=80)] | all' "$TMP/d.json"
# help/version are not requests: no audit entry, no output files
mkdir -p "$TMP/audit"; "$PROD" --help >/dev/null; "$PROD" --version >/dev/null
check test ! -e "$TMP/audit/audit.jsonl"
# wrong usage still fails with the documented code and now points at --help
set +e; "$PROD" --help extra > "$TMP/x.json" 2>&1; rcx=$?; "$PROD" > "$TMP/y.json" 2>&1; rcy=$?; set -e
check test "$rcx" = 64 -a "$rcy" = 64
check jq -e '.error.code=="USAGE" and (.error.message|test("--help"))' "$TMP/y.json"

# --- #24: the table is complete ---
python3 - "$ROOT" <<'PY' || exit 1
import glob, re, sys
root = sys.argv[1]
doc = open(root + "/docs/man/errors.md").read()
documented = set(re.findall(r"^\| `([A-Z][A-Z0-9_]+)` \|", doc, re.M))
used = set()
for f in glob.glob(root + "/src/**/*.zsh", recursive=True):
    s = open(f).read()
    used |= set(re.findall(r'set_error "([A-Z][A-Z0-9_]+)"', s))
    used |= set(re.findall(r'(?:\berr|error_json)\("([A-Z][A-Z0-9_]+)"', s))
    used |= set(re.findall(r'"code"\s*:\s*"([A-Z][A-Z0-9_]+)"', s))
    used |= set(re.findall(r'\("([A-Z][A-Z0-9_]{5,})",\s*"', s))
used = {c for c in used if not c.startswith("MJ_")}
missing = sorted(used - documented)
stale = sorted(documented - used)
if missing: print("UNDOCUMENTED:", missing)
if stale: print("DOCUMENTED BUT UNUSED:", stale)
sys.exit(1 if missing or stale else 0)
PY
check true     # reaching here means the python guard passed (set -e would have stopped us)
# the rows are well formed: 4 columns, a valid exit code, no empty cells
check python3 - "$ROOT" <<'PY'
import re, sys
rows = re.findall(r"^\| `[A-Z0-9_]+` \| (\d+) \| (.+?) \| (.+?) \|$", open(sys.argv[1] + "/docs/man/errors.md").read(), re.M)
assert len(rows) >= 80 and all(int(e) in (64, 65, 66, 69, 73, 74, 77) and m.strip() and w.strip() for e, m, w in rows)
PY

# --- #24: documented exit codes match behavior for the common codes ---
ex(){ local want="$1" code="$2" got="$3"; check test "$got" = "$want"; check jq -e --arg c "$code" '.error.code==$c' "$TMP/e.json"; }
mkdir -p "$TMP/o"; printf x > "$TMP/o/f.txt"
printf 'MOGRAPHJAILED_REQUEST 1\nrequestId=a\ncommand=nope.nope\n' > "$TMP/bad.req"
set +e; "$CLI" --request "$TMP/bad.req" > "$TMP/e.json" 2>/dev/null; rc=$?; set -e; ex 65 UNSUPPORTED_COMMAND $rc
rc=$(runx "$TMP/e.json" file.inspect); ex 65 MISSING_ARGUMENT $rc
rc=$(runx "$TMP/e.json" file.inspect path=relative); ex 65 INVALID_PATH $rc
rc=$(runx "$TMP/e.json" file.inspect path=/nonexistent/zzz); ex 66 NOT_FOUND $rc
rc=$(runx "$TMP/e.json" index.search target=glow); ex 66 STORE_EMPTY $rc
rc=$(runx "$TMP/e.json" image.derivative input=/nonexistent/a.png output="$TMP/o/out.png" target=64); check test "$rc" -ne 0
printf z > "$TMP/exists.zip"
rc=$(runx "$TMP/e.json" package.create path="$TMP/o" output="$TMP/exists.zip"); ex 73 OUTPUT_EXISTS $rc
rc=$(runx "$TMP/e.json" ae.render path="$TMP/o/f.txt" target=x output="$TMP/o" label=x); ex 65 INVALID_TARGET $rc
printf 'MOGRAPHJAILED_REQUEST 1\nrequestId=a\ncommand=system.probe\nbogus=1\n' > "$TMP/bad2.req"
set +e; "$CLI" --request "$TMP/bad2.req" > "$TMP/e.json" 2>/dev/null; rc=$?; set -e; ex 65 MALFORMED_REQUEST $rc

echo "Error code & help tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
