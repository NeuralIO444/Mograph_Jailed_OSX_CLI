#!/usr/bin/env python3
"""QA-only parallel protocol fuzzer for MographJailed NG-M1."""
import base64
import concurrent.futures
import json
import random
import subprocess
import tempfile
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: fuzz_ng_m1_parallel.py <linux-test-cli>")
cli = Path(sys.argv[1]).resolve()
rng = random.Random(0x4E474D31)  # NGM1
CASES = 1000
WORKERS = 12

def b64(raw: bytes) -> str:
    return base64.b64encode(raw).decode("ascii")

def make_case(i: int, root: Path):
    kind = i % 25
    rid = f"ng-fuzz-{i:04d}"
    lines = ["MOGRAPHJAILED_REQUEST 1", f"requestId={rid}"]
    expect_ok = None
    canary = root / f"CANARY-{i:04d}"
    if kind == 0:
        lines.append("command=system.probe"); expect_ok = True
    elif kind == 1:
        lines.append("command=system.describe"); expect_ok = True
    elif kind == 2:
        lines.append("command=runtime.verify")
        lines.append("arg.expectedCliVersion=" + b64(b"0.3.0-dev.2"))
        lines.append("arg.expectedProtocolVersion=" + b64(b"1"))
        lines.append("arg.expectedFilename=" + b64(cli.name.encode()))
        expect_ok = True
    elif kind == 3:
        lines.append("command=runtime.verify")
        lines.append("arg.expectedCliVersion=" + b64(b"wrong"))
        lines.append("arg.expectedProtocolVersion=" + b64(b"1"))
        expect_ok = True
    elif kind == 4:
        lines.append("command=runtime.verify")
        lines.append("arg.expectedCliVersion=" + b64(b"0.3.0-dev.2"))
    elif kind == 5:
        lines.append("command=runtime.verify")
        lines.append("arg.expectedCliVersion=" + b64(b"0.3.0-dev.2"))
        lines.append("arg.expectedProtocolVersion=" + b64(b"1"))
        lines.append("arg.expectedSha256=" + b64(b"not-a-sha"))
    elif kind == 6:
        lines.append("command=shell.execute")
    elif kind == 7:
        lines[0] = "MOGRAPHJAILED_REQUEST 999"; lines.append("command=system.probe")
    elif kind == 8:
        lines.append("command=file.inspect")
    elif kind == 9:
        lines.append("command=file.inspect"); lines.append("arg.path=!!!!")
    elif kind == 10:
        lines.append("command=file.inspect"); lines.append("arg.path=" + b64(b"/tmp/a\nnewline"))
    elif kind == 11:
        attack = f"/tmp/' ; touch {canary} ; #".encode()
        lines.append("command=file.inspect"); lines.append("arg.path=" + b64(attack))
    elif kind == 12:
        p = root / f"normal-{i}.txt"; p.write_text("ok", encoding="utf-8")
        lines.append("command=file.inspect"); lines.append("arg.path=" + b64(str(p).encode())); expect_ok = True
    elif kind == 13:
        p = root / f"hash-{i}.txt"; p.write_text("hash", encoding="utf-8")
        lines.append("command=file.hash"); lines.append("arg.path=" + b64(str(p).encode())); expect_ok = True
    elif kind == 14:
        lines.append("command=system.describe"); lines.append("arg.path=" + b64(b"/tmp"))
    elif kind == 15:
        lines.append("command=system.probe"); lines.append("requestId=duplicate")
    elif kind == 16:
        lines.append("command=system.probe"); lines.append("rawCommand=touch /tmp/nope")
    elif kind == 17:
        lines.append("command=file.inspect"); lines.append("arg.unknown=" + b64(b"x"))
    elif kind == 18:
        lines.append("command=file.inspect"); val=b64(b"/tmp/nope"); lines.extend(["arg.path="+val, "arg.path="+val])
    elif kind == 19:
        lines[1] = "requestId=bad id"; lines.append("command=system.probe")
    elif kind == 20:
        lines.append("command=package.create"); lines.append("arg.path=" + b64(str(root).encode()))
    elif kind == 21:
        lines.append("command=report.tech"); lines.append("arg.format=" + b64(b"json"))
    elif kind == 22:
        tail = "".join(rng.choice("abcXYZ0123 _-'$;[]()") for _ in range(rng.randint(1, 80)))
        lines.append("command=file.inspect"); lines.append("arg.path=" + b64(("/tmp/" + tail).encode()))
    elif kind == 23:
        lines.append("command=system.doctor"); expect_ok = True
    else:
        lines.append("command=file.inspect"); lines.append("arg.path=" + b64(b"/tmp/noncanonical").rstrip("="))
    return rid, "\n".join(lines) + "\n", expect_ok, canary

def execute(case):
    i, req, expect_ok, canary, req_path = case
    req_path.write_text(req, encoding="utf-8")
    proc = subprocess.run(["/bin/bash", str(cli), "--request", str(req_path)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    issues = []
    try:
        obj = json.loads(proc.stdout)
    except Exception as exc:
        return i, [("invalid-json", proc.stdout[:200], str(exc))]
    if obj.get("protocol") != "MOGRAPHJAILED" or obj.get("protocolVersion") != 1 or not isinstance(obj.get("ok"), bool):
        issues.append(("bad-envelope", obj))
    if proc.returncode == 0 and obj.get("ok") is not True:
        issues.append(("rc-ok-mismatch", proc.returncode, obj))
    if proc.returncode != 0:
        if obj.get("ok") is not False:
            issues.append(("rc-error-mismatch", proc.returncode, obj))
        err = obj.get("error") or {}
        if not isinstance(err.get("code"), str) or not err.get("code") or not isinstance(err.get("message"), str) or not err.get("message"):
            issues.append(("blank-error", obj))
    if expect_ok is True and obj.get("ok") is not True:
        issues.append(("expected-success", obj))
    if canary.exists():
        issues.append(("shell-canary-created",))
        canary.unlink()
    return i, issues

with tempfile.TemporaryDirectory(prefix="mj-ngm1-fuzz-") as td:
    root = Path(td)
    cases=[]
    for i in range(CASES):
        rid, text, expect_ok, canary = make_case(i, root)
        cases.append((i, text, expect_ok, canary, root / f"case-{i:04d}.req"))
    failures=[]
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        for i, issues in pool.map(execute, cases):
            for issue in issues:
                failures.append((i,)+issue)

print(json.dumps({"cases": CASES, "workers": WORKERS, "failures": len(failures), "sampleFailures": failures[:10]}, indent=2))
raise SystemExit(1 if failures else 0)
