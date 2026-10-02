#!/usr/bin/env bash
# Hall of horror: hostile paths, malformed receipts, protocol abuse, injection attempts, odd environments
# and concurrency, thrown at the runtime and the mj front end. Every case must:
#   - finish within its time limit (nothing may hang on a FIFO, /dev/zero, a symlink loop or a JSON bomb),
#   - answer with exactly one JSON envelope and a documented exit code (0 64 65 66 69 73 74 77),
#   - fail with a named code, never a crash marker (ENGINE_FAILED, INGEST_FAILED, LINT_FAILED) or a traceback,
#   - never create the canary file that every injection attempt tries to make.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-linux-test.sh" >/dev/null
CLI="$ROOT/dist/mograph-jailed-linux-test.sh"
TMP=$(mktemp -d); TMP=$(cd "$TMP" && pwd -P)
trap 'chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
export MJ_STORE_DIR="$TMP/store" MJ_AUDIT_DIR="$TMP/noaudit" MJ_FONT_DIRS="$TMP/fonts" MJ_FONT_DIRS_ONLY=1
CANARY="$TMP/CANARY"
pass=0; fail=0
ok(){ pass=$((pass+1)); }
bad(){ echo "HORROR: $*" >&2; fail=$((fail+1)); }
b64(){ printf '%s' "$1" | base64 | tr -d '\n'; }
tmo(){ local s="$1"; shift; /usr/bin/perl -e 'alarm shift; exec @ARGV' "$s" "$@"; }   # macOS has no timeout(1)
CRASH='ENGINE_FAILED|INGEST_FAILED|LINT_FAILED|^$'

# horror <name> <allowed error codes regex, or OK> <command> [name=value ...]
horror(){
  local name="$1" want="$2" cmd="$3"; shift 3
  local req="$TMP/h.req" out="$TMP/h.out" errf="$TMP/h.err" rc code
  { printf 'MOGRAPHJAILED_REQUEST 1\nrequestId=horror\ncommand=%s\n' "$cmd"
    for a in "$@"; do printf 'arg.%s=%s\n' "${a%%=*}" "$(b64 "${a#*=}")"; done; } > "$req"
  tmo 30 "$CLI" --request "$req" > "$out" 2> "$errf"; rc=$?
  envelope "$name" "$want" "$rc" "$out" "$errf"
}
# envelope <name> <want> <rc> <stdout file> <stderr file>
envelope(){
  local name="$1" want="$2" rc="$3" out="$4" errf="$5" code
  if [ "$rc" = 142 ]; then bad "$name: hung (killed after its time limit)"; return; fi
  case " 0 64 65 66 69 73 74 77 " in *" $rc "*) ;; *) bad "$name: undocumented exit code $rc"; return ;; esac
  if [ "$(wc -l < "$out" | tr -d ' ')" != 1 ] || ! jq -e '.protocol=="MOGRAPHJAILED"' "$out" >/dev/null 2>&1; then bad "$name: not exactly one JSON envelope: $(head -c 200 "$out")"; return; fi
  if grep -q 'Traceback' "$errf" "$out"; then bad "$name: Python traceback"; return; fi
  [ -e "$CANARY" ] && { bad "$name: CANARY CREATED - something was executed"; rm -f "$CANARY"; return; }
  code=$(jq -r '.error.code // ""' "$out")
  if [ "$want" = OK ]; then
    [ "$rc" = 0 ] && jq -e '.ok' "$out" >/dev/null || { bad "$name: expected success, got $rc $code"; return; }
  elif [ "$rc" = 0 ]; then
    case "$want" in *OK*) ;; *) bad "$name: expected one of [$want], got success"; return ;; esac
  else
    [[ "$code" =~ $CRASH ]] && { bad "$name: crash marker '$code': $(jq -r .error.message "$out")"; return; }
    [[ "$code" =~ ^($want)$ ]] || { bad "$name: expected [$want], got $code ($(jq -r .error.message "$out"))"; return; }
  fi
  ok
}

# ---------------------------------------------------------------- fixtures
python3 "$ROOT/tests/support/make_tutorial_fixtures.py" "$TMP/AE" >/dev/null
GOOD="$TMP/AE/receipts/spring.20261001T163000Z.scrape.json"
mkdir -p "$TMP/paths" "$TMP/out" "$TMP/fonts"
weird=( "a b/c d.json" "café.json" "$(printf 'cafe\xcc\x81-nfd.json')" "🎬 promo ✨.json" "it's \"quoted\".json" 'back\slash.json' "-rf.json" '$(touch CANARY).json'
        "$(printf '%0.sx' $(seq 1 250)).json" )
for w in "${weird[@]}"; do mkdir -p "$TMP/paths/$(dirname -- "$w")"; cp "$GOOD" "$TMP/paths/$w"; done
deep="$TMP/deep"; for i in $(seq 1 28); do deep="$deep/dddddddddddddddd"; done; mkdir -p "$deep" && cp "$GOOD" "$deep/s.json"
ln -s "$TMP/nowhere.json" "$TMP/dangling.json"; ln -s "$TMP/loop2.json" "$TMP/loop1.json"; ln -s "$TMP/loop1.json" "$TMP/loop2.json"
ln -s "$GOOD" "$TMP/link.json"; mkfifo "$TMP/fifo.json" "$TMP/fifo.mov"; mkdir "$TMP/dir.json"
cp "$GOOD" "$TMP/locked.json"; chmod 000 "$TMP/locked.json"
python3 - "$TMP" "$GOOD" <<'PY'
import copy, json, os, sys
d, good = sys.argv[1], json.load(open(sys.argv[2]))
def w(name, data, mode="w"):
    with open(os.path.join(d, name), mode) as f: f.write(data)
f = open(os.path.join(d, "sparse.json"), "wb"); f.truncate(9 * 1024 ** 3); f.close()          # 9 GB of nothing, read not at all
w("garbage.json", os.urandom(4096), "wb")
w("bomb.json", "[" * 200000 + "]" * 200000)
w("deepobj.json", '{"a":' * 50000 + "1" + "}" * 50000)
w("bom.json", "﻿" + json.dumps(good), "w")
w("utf16.json", json.dumps(good).encode("utf-16"), "wb")
w("empty.json", "")
w("nan.json", json.dumps(good).replace('"frameRate": 30', '"frameRate": NaN').replace('"duration": 10', '"duration": Infinity'))
def mut(name, fn):
    g = copy.deepcopy(good); fn(g); w(name, json.dumps(g))
mut("comps-string.json", lambda g: g.update(comps="x"))
mut("layers-null.json", lambda g: [c.update(layers=None) for c in g["comps"]])
mut("layers-dict.json", lambda g: [c.update(layers={"a": 1}) for c in g["comps"]])
mut("layer-junk.json", lambda g: g["comps"][0]["layers"].extend([None, 5, "x", [], {"index": "1", "name": 7, "type": None, "expressions": "x", "effects": "y", "sourceId": "z"}]))
mut("comp-junk.json", lambda g: g["comps"].extend([None, 3, "x", {"id": "9", "name": None}, {"id": 10 ** 30, "name": "huge"}, {"id": -1, "name": "neg"}]))
mut("fonts-junk.json", lambda g: g.update(fonts=[None, 5, {"a": 1}, "ok"]))
mut("footage-junk.json", lambda g: g["footage"].extend([None, {"id": "x", "path": 5, "name": []}, {"path": "relative/path.mov", "missing": "yes"}]))
mut("expr-junk.json", lambda g: g["comps"][0]["layers"][1].update(expressions=[None, 5, {"propertyPath": None, "expression": None}, {"expression": "comp(\"" + "A" * 100000 + "\")"}]))
mut("dup-ids.json", lambda g: [c.update(id=1) for c in g["comps"]])
def self_loop(g):
    g["comps"][0]["layers"].append({"index": 99, "name": "Me", "type": "AVLayer", "sourceId": g["comps"][0]["id"]})
mut("self-loop.json", self_loop)
def ring(g):
    a, b = g["comps"][0], g["comps"][1]
    a["layers"].append({"index": 98, "name": "B", "type": "AVLayer", "sourceId": b["id"]})
    b["layers"].append({"index": 97, "name": "A", "type": "AVLayer", "sourceId": a["id"]})
mut("ring.json", ring)
def wide(g):
    g["comps"] = [{"id": i, "name": "C%d" % i, "layers": [{"index": 1, "name": "L", "type": "AVLayer", "sourceId": i + 1}]} for i in range(1, 3000)]
mut("chain3000.json", wide)
def names(g):
    for c, n in zip(g["comps"], ['Q"uote', "Back\\slash", "Ünïcödé 🎬"]):
        c["name"] = n
    g["comps"][0]["layers"][1]["expressions"] = [{"propertyPath": "Transform/Position", "expression": 'comp("Back\\\\slash").layer("x\\"y").position; thisComp.layer(\'Ünïcödé\')'}]
mut("evil-names.json", names)
PY

# ---------------------------------------------------------------- hostile paths
for w in "${weird[@]}"; do horror "path: $w" OK project.ingest path="$TMP/paths/$w"; done
horror "path: 28 levels deep" "OK" project.ingest path="$deep/s.json"
horror "path: .. segments" "OK|INVALID_PATH" project.ingest path="$TMP/paths/../paths/café.json"
horror "path: relative" INVALID_PATH project.ingest path=paths/café.json
horror "path: empty" "INVALID_PATH|MISSING_ARGUMENT|INVALID_ARGUMENT" project.ingest path=
horror "path: newline" "INVALID_ARGUMENT|INVALID_ARGUMENT_ENCODING|INVALID_PATH|INVALID_TARGET|NOT_FOUND" project.ingest path="$(printf '%s/a\nb.json' "$TMP")"
horror "path: dangling symlink" "INVALID_TARGET|NOT_FOUND" project.ingest path="$TMP/dangling.json"
horror "path: symlink loop" "INVALID_TARGET|NOT_FOUND" project.ingest path="$TMP/loop1.json"
horror "path: symlink to a good scrape" "OK|INVALID_TARGET" project.ingest path="$TMP/link.json"
horror "path: FIFO as scrape" INVALID_TARGET project.ingest path="$TMP/fifo.json"
horror "path: FIFO to lint" INVALID_TARGET expression.lint path="$TMP/fifo.json"
horror "path: FIFO to preflight" INVALID_TARGET project.preflight path="$TMP/fifo.json"
horror "path: FIFO movie to qc" "INVALID_TARGET|NOT_FOUND|UNSUPPORTED" media.qc path="$TMP/fifo.mov" format=web
horror "path: FIFO to file.hash" "INVALID_TARGET|NOT_FOUND" file.hash path="$TMP/fifo.json"
horror "path: /dev/zero" "INVALID_TARGET|NOT_FOUND|NETWORK_SCOPE_BLOCKED|STORAGE_SCOPE_UNKNOWN" project.ingest path=/dev/zero
horror "path: /dev/zero hashed" "INVALID_TARGET|NOT_FOUND|NETWORK_SCOPE_BLOCKED|STORAGE_SCOPE_UNKNOWN" file.hash path=/dev/zero
horror "path: directory" INVALID_TARGET project.ingest path="$TMP/dir.json"
[ "$(id -u)" = 0 ] || horror "path: unreadable" PERMISSION_DENIED project.ingest path="$TMP/locked.json"
horror "path: 9 GB sparse scrape" SCRAPE_TOO_LARGE project.ingest path="$TMP/sparse.json"
horror "path: 9 GB sparse to health" SCRAPE_TOO_LARGE project.health path="$TMP/sparse.json"

# ---------------------------------------------------------------- malformed receipts, through every consumer
for f in garbage bomb deepobj bom utf16 empty nan comps-string layers-null layers-dict layer-junk comp-junk fonts-junk footage-junk expr-junk dup-ids self-loop ring chain3000 evil-names; do
  for op in project.ingest expression.lint project.health project.preflight deps.graph project.conform; do
    horror "$f -> $op" "OK|INVALID_JSON|SCHEMA_MISMATCH|SCRAPE_TOO_LARGE" $op path="$TMP/$f.json" $( [ $op = project.conform ] && echo "input=$TMP/$f.json" )
  done
  horror "$f -> project.diff" "OK|INVALID_JSON|SCHEMA_MISMATCH|SCRAPE_TOO_LARGE" project.diff path="$GOOD" input="$TMP/$f.json"
done
horror "ring -> extract" "OK|NOT_FOUND" project.extract path="$TMP/AE/projects/Spring Promo/Spring Promo.aep" input="$TMP/ring.json" target=1 output="$TMP/out" label=ring
horror "chain3000 -> extract" "OK|NOT_FOUND" project.extract path="$TMP/AE/projects/Spring Promo/Spring Promo.aep" input="$TMP/chain3000.json" target=1 output="$TMP/out" label=chain
horror "evil names -> conform job" "OK" project.conform input="$TMP/evil-names.json" format=job path="$TMP/AE/projects/Spring Promo/Spring Promo.aep" output="$TMP/out" label=evil
python3 - "$TMP/out/evil.mjjob/run.jsx" <<'PY' && ok || bad "evil names: run.jsx plan is not pure ASCII JSON (script injection risk)"
import json, sys
t = open(sys.argv[1], encoding="utf-8").read()
plan = t.split("var MJ_PLAN = ", 1)[1].split(";\n", 1)[0]
assert all(ord(c) < 128 for c in plan) and " " not in plan
json.loads(plan)
PY

# ---------------------------------------------------------------- protocol abuse
raw(){ # raw <name> <want> <request bytes via printf %b>
  local name="$1" want="$2"; printf '%b' "$3" > "$TMP/raw.req"
  tmo 30 "$CLI" --request "$TMP/raw.req" > "$TMP/h.out" 2> "$TMP/h.err"; envelope "$name" "$want" $? "$TMP/h.out" "$TMP/h.err"
}
raw "proto: CRLF lines" "OK|MALFORMED_REQUEST|BAD_REQUEST_VERSION|INVALID_REQUEST_ID|UNSUPPORTED_COMMAND" 'MOGRAPHJAILED_REQUEST 1\r\nrequestId=a\r\ncommand=system.probe\r\n'
raw "proto: NUL byte" "MALFORMED_REQUEST|INVALID_REQUEST_ID|UNSUPPORTED_COMMAND|BAD_REQUEST_VERSION" 'MOGRAPHJAILED_REQUEST 1\nrequestId=a\0b\ncommand=system.probe\n'
raw "proto: empty file" "BAD_REQUEST_VERSION|MALFORMED_REQUEST|MISSING_FIELD" ''
raw "proto: no trailing newline" OK 'MOGRAPHJAILED_REQUEST 1\nrequestId=a\ncommand=system.probe'
raw "proto: version 2" BAD_REQUEST_VERSION 'MOGRAPHJAILED_REQUEST 2\nrequestId=a\ncommand=system.probe\n'
raw "proto: traversal command" UNSUPPORTED_COMMAND 'MOGRAPHJAILED_REQUEST 1\nrequestId=a\ncommand=../../bin/sh\n'
raw "proto: shell in command" UNSUPPORTED_COMMAND 'MOGRAPHJAILED_REQUEST 1\nrequestId=a\ncommand=system.probe;touch CANARY\n'
raw "proto: bad request id" INVALID_REQUEST_ID 'MOGRAPHJAILED_REQUEST 1\nrequestId=$(touch CANARY)\ncommand=system.probe\n'
raw "proto: duplicate command" DUPLICATE_FIELD 'MOGRAPHJAILED_REQUEST 1\nrequestId=a\ncommand=system.probe\ncommand=system.doctor\n'
raw "proto: duplicate arg" DUPLICATE_FIELD "MOGRAPHJAILED_REQUEST 1\nrequestId=a\ncommand=file.inspect\narg.path=$(b64 /tmp)\narg.path=$(b64 /etc)\n"
raw "proto: unknown arg name" "INVALID_ARGUMENT|MALFORMED_REQUEST|UNEXPECTED_ARGUMENT" "MOGRAPHJAILED_REQUEST 1\nrequestId=a\ncommand=file.inspect\narg.evil=$(b64 x)\n"
raw "proto: invalid base64" INVALID_ARGUMENT_ENCODING 'MOGRAPHJAILED_REQUEST 1\nrequestId=a\ncommand=file.inspect\narg.path=!!!notbase64!!!\n'
raw "proto: control chars in value" "INVALID_ARGUMENT|INVALID_ARGUMENT_ENCODING" "MOGRAPHJAILED_REQUEST 1\nrequestId=a\ncommand=file.inspect\narg.path=$(printf '/tmp/\033[31mred\a' | base64 | tr -d '\n')\n"
big=$(head -c 40000 /dev/zero | tr '\0' 'A')
raw "proto: 40 KB line" REQUEST_TOO_LARGE "MOGRAPHJAILED_REQUEST 1\nrequestId=a\ncommand=file.inspect\narg.path=$big\n"
raw "proto: 1000 lines" "REQUEST_TOO_LARGE|DUPLICATE_FIELD|MALFORMED_REQUEST" "MOGRAPHJAILED_REQUEST 1\nrequestId=a\ncommand=system.probe\n$(for i in $(seq 1 1000); do printf 'arg.path=eA==\\n'; done)"
printf 'garbage\n' | tmo 30 "$CLI" --request - > "$TMP/h.out" 2> "$TMP/h.err"; envelope "proto: garbage on stdin" "BAD_REQUEST_VERSION|MALFORMED_REQUEST" $? "$TMP/h.out" "$TMP/h.err"
tmo 30 "$CLI" --request "$TMP/dir.json" > "$TMP/h.out" 2> "$TMP/h.err"; envelope "proto: request is a directory" "REQUEST_NOT_FOUND|MALFORMED_REQUEST|BAD_REQUEST_VERSION" $? "$TMP/h.out" "$TMP/h.err"
tmo 30 "$CLI" --request "$TMP/fifo.json" > "$TMP/h.out" 2> "$TMP/h.err" < /dev/null; envelope "proto: request is a FIFO" "REQUEST_NOT_FOUND|MALFORMED_REQUEST|BAD_REQUEST_VERSION" $? "$TMP/h.out" "$TMP/h.err"

# ---------------------------------------------------------------- injection in values (all must stay literal)
for v in '$(touch '"$CANARY"')' '`touch '"$CANARY"'`' "; touch $CANARY" "| touch $CANARY" "&& touch $CANARY" "\$(touch $CANARY)"; do
  horror "inject label: $v" "INVALID_ARGUMENT|INVALID_OUTPUT|OUTPUT_UNAVAILABLE" golden.record path="$TMP/out" output="$TMP/out" label="$v"
  horror "inject path: $v" "INVALID_PATH|NOT_FOUND|INVALID_TARGET" file.inspect path="/tmp/$v"
  horror "inject target: $v" "INVALID_ARGUMENT|NOT_FOUND" cache.clean target="$v"
  horror "inject spec: $v" "INVALID_ARGUMENT" media.qc path="$GOOD" format="$v"
  horror "inject comp ids: $v" "INVALID_ARGUMENT" project.extract path="$TMP/AE/projects/Spring Promo/Spring Promo.aep" input="$GOOD" target="$v" output="$TMP/out" label=x
done

# ---------------------------------------------------------------- odd environments
mkdir -p "$TMP/tmp dir 'q'"
TMPDIR="$TMP/tmp dir 'q'" horror "env: TMPDIR with spaces and quotes" OK temp.create
LC_ALL=C LANG=C horror "env: C locale + unicode path" OK project.ingest path="$TMP/paths/🎬 promo ✨.json"
TZ=Pacific/Kiritimati horror "env: TZ +14" OK project.health path="$GOOD"
TZ=Etc/GMT+12 horror "env: TZ -12" OK project.health path="$GOOD"
printf 'MOGRAPHJAILED_REQUEST 1\nrequestId=p\ncommand=system.doctor\n' > "$TMP/p.req"
PATH=/nonexistent tmo 30 "$(command -v zsh)" -f "$CLI" --request "$TMP/p.req" > "$TMP/h.out" 2> "$TMP/h.err"; envelope "env: PATH points nowhere" OK $? "$TMP/h.out" "$TMP/h.err"
(unset HOME; tmo 30 "$CLI" --request "$TMP/h.req" > "$TMP/h.out" 2> "$TMP/h.err"; envelope "env: no HOME" "OK|STORE_UNAVAILABLE|UNSUPPORTED|INVALID_ARGUMENT|INVALID_PATH" $? "$TMP/h.out" "$TMP/h.err"; [ $fail -eq 0 ] ) || true

# ---------------------------------------------------------------- concurrency
mkdir -p "$TMP/race/proj" "$TMP/race/versions"; printf 'project bytes' > "$TMP/race/proj/Race.aep"
printf 'MOGRAPHJAILED_REQUEST 1\nrequestId=r\ncommand=project.snapshot\narg.path=%s\narg.output=%s\n' "$(b64 "$TMP/race/proj/Race.aep")" "$(b64 "$TMP/race/versions")" > "$TMP/race.req"
for i in $(seq 1 16); do (tmo 60 "$CLI" --request "$TMP/race.req" > "$TMP/race.$i.out" 2>&1; echo $? > "$TMP/race.$i.rc") & done; wait
# Every racer succeeds: one saves, the rest find the same bytes already saved (unchanged / alreadySaved).
n_ok=0; for i in $(seq 1 16); do rc=$(cat "$TMP/race.$i.rc"); [ "$rc" = 0 ] && n_ok=$((n_ok+1)) || bad "race snapshot $i: rc $rc $(jq -c .error "$TMP/race.$i.out")"; done
[ "$(jq -s '[.[] | select(.data.snapshotCreated == true)] | length' "$TMP"/race.*.out)" = 1 ] && ok || bad "race snapshot: not exactly one creator"
[ "$(ls "$TMP/race/versions" | grep -c '\.aep$')" = 1 ] && ok || bad "race snapshot: expected exactly one version, got $(ls "$TMP/race/versions")"
[ -z "$(ls -a "$TMP/race/versions" | grep -i 'partial\|\.tmp')" ] && ok || bad "race snapshot: partial files left behind"
[ "$n_ok" = 16 ] && ok || bad "race snapshot: $n_ok of 16 succeeded"
printf 'MOGRAPHJAILED_REQUEST 1\nrequestId=r\ncommand=index.add\narg.path=%s\n' "$(b64 "$TMP/AE/receipts")" > "$TMP/idx.req"
for i in $(seq 1 8); do (tmo 60 "$CLI" --request "$TMP/idx.req" > "$TMP/idx.$i.out" 2>&1; echo $? > "$TMP/idx.$i.rc") & done; wait
for i in $(seq 1 8); do rc=$(cat "$TMP/idx.$i.rc"); [ "$rc" = 0 ] && ok || bad "race index on a new store $i: rc $rc $(jq -c .error "$TMP/idx.$i.out")"; done
horror "race: index intact afterwards" OK index.verify

# ---------------------------------------------------------------- the mj front end
export HOME="$TMP/home with space"; mkdir -p "$HOME"
mjz(){ MJ_CLI="$CLI" MJ_CONFIG="$TMP/cfg" tmo 60 zsh -f -c "source '$ROOT/scripts/shell/mj-cli.zsh'; $1" > "$TMP/mj.out" 2>&1; echo $? > "$TMP/mj.rc"; }
mjcheck(){ local name="$1" want="$2"; local rc; rc=$(cat "$TMP/mj.rc")
  [ "$rc" = 142 ] && { bad "mj $name: hung"; return; }
  grep -q Traceback "$TMP/mj.out" && { bad "mj $name: traceback"; return; }
  [ -e "$CANARY" ] && { bad "mj $name: CANARY CREATED"; rm -f "$CANARY"; return; }
  [[ "$rc" =~ ^($want)$ ]] && ok || bad "mj $name: exit $rc, wanted $want: $(head -c 200 "$TMP/mj.out")"; }
mjz "mj config set receipts_dir '$TMP/AE/receipts'; mj config set watch_dir '$TMP/AE/projects'; mj config set versions_dir '$TMP/out'"; mjcheck "config in a HOME with spaces" 0
mjz "mj snapshot '*'"; mjcheck "snapshot of a glob star" 66
mjz "mj snapshot '[S]pring Promo'"; mjcheck "snapshot of a bracket pattern" 66
mjz "mj snapshot 'Spring\$(touch $CANARY)'"; mjcheck "snapshot of an injection name" 66
mjz "mj check '\`touch $CANARY\`'"; mjcheck "check of an injection name" 66
mjz "mj config set post_snapshot_hook '/tmp/\$(touch $CANARY)'; mj config show"; mjcheck "config value with \$(...)" 0
printf 'project.ingest path={{p}}\n' > "$TMP/r.mjrecipe"
mjz "mj recipe '$TMP/r.mjrecipe' 'p=\$(touch $CANARY)'"; mjcheck "recipe value with \$(...)" "65|66"
mjz "mj file.inspect 'path=\$(touch $CANARY)'"; mjcheck "operation arg with \$(...)" 65
mjz "mj 'file.inspect;touch $CANARY'"; mjcheck "operation name with ;" 65
mjz "mj extract 'Spring Promo' 'Main\"; touch $CANARY; \"'"; mjcheck "extract comp with quotes" "65|66"
mjz "mj qc '$TMP/fifo.mov'"; mjcheck "qc of a FIFO" "1|65|66|69"
mjz "mj space clean '../../etc'"; mjcheck "space clean traversal" "1|65"
mjz "mj timeline \"\$(printf 'x\\ny')\""; mjcheck "timeline with newline" "0|66"

echo "Hall of horror: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
