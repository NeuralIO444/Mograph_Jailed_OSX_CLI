#!/usr/bin/env python3
"""QA-only deterministic protocol fuzzer. Not a MographJailed runtime dependency."""
import base64
import json
import os
import random
import subprocess
import sys
import tempfile
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("usage: fuzz_protocol.py <linux-test-cli>")
cli = Path(sys.argv[1]).resolve()
rng = random.Random(0x5550434F)  # "MJ"
CASES = 1000
failures = []

commands_with_path = ["file.inspect", "file.hash", "volume.inspect", "temp.clean", "media.inspect", "media.timing"]
noarg_commands = ["system.probe", "system.doctor", "system.describe", "temp.create", "report.tech"]
all_commands = commands_with_path + noarg_commands + ["runtime.verify", "package.create"]

def b64(raw: bytes) -> str:
    return base64.b64encode(raw).decode("ascii")

def make_case(i: int, root: Path, canary: Path):
    kind = i % 24
    rid = f"fuzz-{i:04d}"
    lines = ["MOGRAPHJAILED_REQUEST 1", f"requestId={rid}"]
    expect_ok = None

    if kind == 0:
        lines.append("command=system.probe"); expect_ok = True
    elif kind == 1:
        lines.append("command=shell.execute")
    elif kind == 2:
        lines[0] = "MOGRAPHJAILED_REQUEST 999"; lines.append("command=system.probe")
    elif kind == 3:
        lines.append("command=file.inspect")  # missing required arg
    elif kind == 4:
        lines.append("command=system.probe"); lines.append("requestId=duplicate")
    elif kind == 5:
        lines.append("command=system.probe"); lines.append("rawCommand=touch /tmp/nope")
    elif kind == 6:
        lines.append("command=file.inspect"); lines.append("arg.path=!!!!")
    elif kind == 7:
        lines.append("command=file.inspect"); lines.append("arg.path=" + b64(b"/tmp/a\x00b"))
    elif kind == 8:
        lines.append("command=file.inspect"); lines.append("arg.path=" + b64(b"/tmp/a\nb"))
    elif kind == 9:
        attack = f"/tmp/' ; touch {canary} ; #".encode()
        lines.append("command=file.inspect"); lines.append("arg.path=" + b64(attack))
    elif kind == 10:
        p = root / f"normal-{i}.txt"; p.write_text("ok", encoding="utf-8")
        lines.append("command=file.inspect"); lines.append("arg.path=" + b64(str(p).encode())); expect_ok = True
    elif kind == 11:
        p = root / f"hash-{i}.txt"; p.write_text("hash", encoding="utf-8")
        lines.append("command=file.hash"); lines.append("arg.path=" + b64(str(p).encode())); expect_ok = True
    elif kind == 12:
        lines.append("command=report.tech"); lines.append("arg.format=" + b64(b"json"))
    elif kind == 13:
        lines.append("command=package.create"); lines.append("arg.path=" + b64(str(root).encode()))  # output missing
    elif kind == 14:
        lines.append("command=file.inspect"); lines.append("arg.unknown=" + b64(b"x"))
    elif kind == 15:
        # Random canonical bytes that are valid UTF-8 and begin with an absolute path.
        tail = "".join(rng.choice("abcXYZ0123 _-'$;[]()") for _ in range(rng.randint(1, 80)))
        lines.append("command=file.inspect"); lines.append("arg.path=" + b64(("/tmp/" + tail).encode("utf-8")))
    elif kind == 16:
        lines.append("command=system.doctor"); expect_ok = True
    elif kind == 17:
        # invalid request id
        lines[1] = "requestId=bad id"; lines.append("command=system.probe")
    elif kind == 18:
        # duplicate argument
        lines.append("command=file.inspect"); val=b64(b"/tmp/nope"); lines += ["arg.path="+val, "arg.path="+val]
    elif kind == 19:
        lines.append("command=system.describe"); expect_ok = True
    elif kind == 20:
        lines.append("command=runtime.verify")
        lines.append("arg.expectedCliVersion=" + b64(b"0.4.0-dev.2"))
        lines.append("arg.expectedProtocolVersion=" + b64(b"1"))
        lines.append("arg.expectedFilename=" + b64(cli.name.encode("utf-8")))
        expect_ok = True
    elif kind == 21:
        lines.append("command=runtime.verify")  # missing expectedProtocolVersion
        lines.append("arg.expectedCliVersion=" + b64(b"0.4.0-dev.2"))
    elif kind == 22:
        lines.append("command=runtime.verify")
        lines.append("arg.expectedCliVersion=" + b64(b"0.4.0-dev.2"))
        lines.append("arg.expectedProtocolVersion=" + b64(b"1"))
        lines.append("arg.expectedSha256=" + b64(b"not-a-sha"))
    else:
        # Non-canonical base64 (padding removed) or empty argument.
        lines.append("command=" + rng.choice(commands_with_path))
        val = b64(b"/tmp/noncanonical").rstrip("=")
        lines.append("arg.path=" + val)
    return rid, "\n".join(lines) + "\n", expect_ok

with tempfile.TemporaryDirectory(prefix="mograph-jailed-fuzz-") as td:
    root = Path(td)
    canary = root / "SHELL_CANARY"
    for i in range(CASES):
        rid, text, expect_ok = make_case(i, root, canary)
        req = root / f"case-{i:04d}.req"
        req.write_text(text, encoding="utf-8", errors="strict")
        proc = subprocess.run(["/bin/bash", str(cli), "--request", str(req)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        raw = proc.stdout
        try:
            obj = json.loads(raw)
        except Exception as exc:
            failures.append((i, "invalid-json", repr(raw[:200]), str(exc)))
            continue
        if obj.get("protocol") != "MOGRAPHJAILED" or obj.get("protocolVersion") != 1 or not isinstance(obj.get("ok"), bool):
            failures.append((i, "bad-envelope", obj))
            continue
        if proc.returncode == 0 and obj.get("ok") is not True:
            failures.append((i, "rc-ok-mismatch", proc.returncode, obj))
        if proc.returncode != 0:
            if obj.get("ok") is not False:
                failures.append((i, "rc-error-mismatch", proc.returncode, obj))
            err = obj.get("error") or {}
            if not isinstance(err.get("code"), str) or not err.get("code") or not isinstance(err.get("message"), str) or not err.get("message"):
                failures.append((i, "blank-error", obj))
        if expect_ok is True and obj.get("ok") is not True:
            failures.append((i, "expected-success", obj))
        if canary.exists():
            failures.append((i, "shell-canary-created"))
            canary.unlink()

print(json.dumps({"cases": CASES, "failures": len(failures), "sampleFailures": failures[:10]}, indent=2))
raise SystemExit(1 if failures else 0)
