#!/usr/bin/env python3
"""QA-only batch protocol fuzzer for MographJailed NG-M1."""
import base64
import json
import random
import subprocess
import tempfile
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: fuzz_ng_m1_batch.py <project-root>")
root_project = Path(sys.argv[1]).resolve()
rng = random.Random(0x4E474D31)
CASES = 1000

def b64(raw: bytes) -> str:
    return base64.b64encode(raw).decode("ascii")

def make_case(i: int, root: Path):
    slot = i % 100
    rid = f"ng-fuzz-{i:04d}"
    lines = ["MOGRAPHJAILED_REQUEST 1", f"requestId={rid}"]
    expect_ok = None
    canary = root / f"CANARY-{i:04d}"
    if slot == 0:
        lines.append("command=system.describe"); expect_ok = True
    elif slot == 1:
        lines.append("command=runtime.verify")
        lines.append("arg.expectedCliVersion=" + b64(b"0.3.0-dev.2"))
        lines.append("arg.expectedProtocolVersion=" + b64(b"1"))
        expect_ok = True
    elif slot == 2:
        p = root / f"normal-{i}.txt"; p.write_text("ok", encoding="utf-8")
        lines.append("command=file.inspect"); lines.append("arg.path=" + b64(str(p).encode())); expect_ok = True
    elif slot == 3:
        lines.append("command=runtime.verify")
        lines.append("arg.expectedCliVersion=" + b64(b"0.3.0-dev.2"))
        lines.append("arg.expectedProtocolVersion=" + b64(b"1"))
        lines.append("arg.expectedSha256=" + b64(b"not-a-sha"))
    elif slot == 4:
        lines.append("command=file.inspect"); lines.append("arg.path=!!!!")
    elif slot == 5:
        attack = f"/tmp/' ; touch {canary} ; #".encode()
        lines.append("command=file.inspect"); lines.append("arg.path=" + b64(attack))
    elif slot % 10 == 0:
        lines[0] = "MOGRAPHJAILED_REQUEST 999"; lines.append("command=system.probe")
    elif slot % 10 == 1:
        lines.append("command=shell.execute")
    elif slot % 10 == 2:
        lines.append("command=file.inspect")  # missing arg
    elif slot % 10 == 3:
        lines.append("command=runtime.verify")  # missing required args
    elif slot % 10 == 4:
        lines.append("command=system.probe"); lines.append("requestId=duplicate")
    elif slot % 10 == 5:
        lines.append("command=system.probe"); lines.append("rawCommand=touch /tmp/nope")
    elif slot % 10 == 6:
        lines[1] = "requestId=bad id"; lines.append("command=system.probe")
    elif slot % 10 == 7:
        lines.append("command=file.inspect"); lines.append("arg.unknown=x")
    elif slot % 10 == 8:
        lines.append("command=system.describe"); lines.append("arg.unknown=x")
    else:
        lines.append("command=package.create")  # missing path/output
    return "\n".join(lines) + "\n", expect_ok, canary

with tempfile.TemporaryDirectory(prefix="mj-ngm1-batch-fuzz-") as td:
    root = Path(td)
    expected = []
    req_paths = []
    for i in range(CASES):
        text, expect_ok, canary = make_case(i, root)
        req = root / f"case-{i:04d}.req"
        req.write_text(text, encoding="utf-8")
        req_paths.append(req)
        expected.append((expect_ok, canary))

    harness = root / "batch.sh"
    harness.write_text(r'''#!/bin/bash
set -u
ROOT="$1"; shift
source "$ROOT/src/core/constants.zsh"
source "$ROOT/src/core/json.zsh"
source "$ROOT/src/core/errors.zsh"
source "$ROOT/src/core/response.zsh"
source "$ROOT/src/core/protocol.zsh"
source "$ROOT/src/core/path.zsh"
source "$ROOT/src/core/capabilities.zsh"
source "$ROOT/src/core/operations.zsh"
source "$ROOT/src/modules/system.zsh"
source "$ROOT/src/modules/file.zsh"
source "$ROOT/src/modules/runtime.zsh"
source "$ROOT/src/modules/volume.zsh"
source "$ROOT/src/modules/temp.zsh"
source "$ROOT/src/modules/media.zsh"
source "$ROOT/src/modules/report.zsh"
source "$ROOT/src/modules/package.zsh"
# QA-only fast JSON quoting: protocol fuzz inputs here use printable ASCII for
# response fields. Production json_quote has separate regression coverage.
json_quote(){ local s="$1"; s=${s//\\/\\\\}; s=${s//\"/\\\"}; printf '"%s"' "$s"; }
eval "$(sed '$d' "$ROOT/src/cli/entry.zsh")"
i=0
for req in "$@"; do
  out="${req}.out"
  rcfile="${req}.rc"
  main --request "$req" > "$out"
  rc=$?
  printf '%s' "$rc" > "$rcfile"
  i=$((i+1))
done
''', encoding="utf-8")
    harness.chmod(0o755)
    proc = subprocess.run(["/bin/bash", str(harness), str(root_project)] + [str(p) for p in req_paths], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    failures=[]
    if proc.returncode != 0:
        failures.append((-1, "batch-harness-failed", proc.returncode, proc.stderr[:500]))
    for i, req in enumerate(req_paths):
        out = Path(str(req) + ".out")
        rcfile = Path(str(req) + ".rc")
        if not out.exists() or not rcfile.exists():
            failures.append((i, "missing-result")); continue
        raw=out.read_text(encoding="utf-8")
        rc=int(rcfile.read_text() or "999")
        try:
            obj=json.loads(raw)
        except Exception as exc:
            failures.append((i,"invalid-json",raw[:200],str(exc))); continue
        if obj.get("protocol") != "MOGRAPHJAILED" or obj.get("protocolVersion") != 1 or not isinstance(obj.get("ok"), bool):
            failures.append((i,"bad-envelope",obj)); continue
        if rc == 0 and obj.get("ok") is not True:
            failures.append((i,"rc-ok-mismatch",rc,obj))
        if rc != 0:
            if obj.get("ok") is not False:
                failures.append((i,"rc-error-mismatch",rc,obj))
            err=obj.get("error") or {}
            if not err.get("code") or not err.get("message"):
                failures.append((i,"blank-error",obj))
        expect_ok, canary = expected[i]
        if expect_ok is True and obj.get("ok") is not True:
            failures.append((i,"expected-success",obj))
        if canary.exists():
            failures.append((i,"shell-canary-created",)); canary.unlink()

print(json.dumps({"cases":CASES,"failures":len(failures),"sampleFailures":failures[:10]},indent=2))
raise SystemExit(1 if failures else 0)
