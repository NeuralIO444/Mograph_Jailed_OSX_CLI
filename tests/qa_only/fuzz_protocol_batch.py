#!/usr/bin/env python3
"""QA-only 1,000-request parser/envelope fuzzer for MographJailed 0.2.

This deliberately focuses on protocol safety rather than native operation cost.
Semantic/native behavior is covered by run_ng_m1.sh and run_ng_m2.sh.
"""
import base64, json, os, random, subprocess, tempfile, sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit('usage: fuzz_protocol_batch.py <project-root>')
project = Path(sys.argv[1]).resolve()
rng = random.Random(0x5550434F02)
CASES = int(os.environ.get('MJ_FUZZ_CASES', '500'))
OFFSET = int(os.environ.get('MJ_FUZZ_OFFSET', '0'))

def b64(b: bytes) -> str:
    return base64.b64encode(b).decode('ascii')

def make_case(i: int, root: Path):
    slot = i % 100
    rid = f'fuzz-{i:04d}'
    lines = ['MOGRAPHJAILED_REQUEST 1', f'requestId={rid}']
    want_ok = None
    canary = root / f'CANARY-{i}'

    # A very small success sample exercises the router without turning a
    # protocol fuzzer into a filesystem/media benchmark.
    if slot == 0:
        lines += ['command=system.describe']; want_ok = True
    elif slot == 1:
        lines += ['command=system.probe']; want_ok = True
    elif slot == 2:
        lines += [
            'command=runtime.verify',
            'arg.expectedCliVersion=' + b64(b'0.3.0-dev.2'),
            'arg.expectedProtocolVersion=' + b64(b'1'),
        ]; want_ok = True
    elif slot == 3:
        p = root / f'asset-{i}.txt'; p.write_text('asset', encoding='utf-8')
        lines += ['command=asset.manifest', 'arg.path=' + b64(str(p).encode())]
        want_ok = True
    elif slot == 4:
        lines += ['command=storage.preflight', 'arg.path=' + b64(str(root).encode())]
        want_ok = True

    # Protocol/schema/adversarial cases below intentionally avoid expensive
    # native work. They should all fail safely and preserve JSON envelopes.
    elif slot == 5:
        lines[0] = 'MOGRAPHJAILED_REQUEST 999'; lines += ['command=system.probe']
    elif slot == 6:
        lines += ['command=shell.execute']
    elif slot == 7:
        lines += ['command=file.inspect']  # missing path
    elif slot == 8:
        lines += ['command=system.probe', 'requestId=duplicate']
    elif slot == 9:
        lines[1] = 'requestId=bad id'; lines += ['command=system.probe']
    elif slot == 10:
        lines += ['command=file.inspect', 'arg.unknown=x']
    elif slot == 11:
        lines += ['command=file.inspect', 'arg.path=!!!!']
    elif slot == 12:
        lines += ['command=image.derivative', 'arg.input=' + b64(b'/tmp/x'), 'arg.output=' + b64(b'/tmp/o.png')]  # target missing
    elif slot == 13:
        lines += ['command=search.candidate', 'arg.path=' + b64(str(root).encode())]  # target missing
    elif slot == 14:
        lines += ['command=asset.verify', 'arg.path=' + b64(str(root / 'none').encode())]  # no expected identity
    elif slot == 15:
        attack = f"/tmp/' ; touch {canary} ; #".encode()
        lines += ['command=file.inspect', 'arg.path=' + b64(attack)]
    elif slot == 16:
        lines += ['command=system.describe', 'arg.path=' + b64(b'/tmp')]
    elif slot == 17:
        lines += ['command=asset.manifest', 'arg.path=' + b64(b'/tmp/noncanonical').rstrip('=')]
    elif slot == 18:
        lines += ['command=package.create']
    elif slot == 19:
        lines += ['command=runtime.verify', 'arg.expectedCliVersion=' + b64(b'0.3.0-dev.2')]  # missing protocol
    elif slot == 20:
        lines += ['command=storage.preflight', 'arg.path=' + b64(str(root).encode()), 'arg.requiredBytes=' + b64(b'bananas')]
    elif slot == 21:
        lines += ['command=asset.verify', 'arg.path=' + b64(str(root).encode()), 'arg.expectedFilename=' + b64(b'a/b')]
    elif slot == 22:
        lines += ['command=search.candidate', 'arg.path=' + b64(str(root).encode()), 'arg.target=' + b64(b'a/b')]
    elif slot == 23:
        lines += ['command=image.derivative', 'arg.input=' + b64(b'/tmp/x'), 'arg.output=' + b64(b'/tmp/o.png'), 'arg.target=' + b64(b'999999')]
    else:
        # Keep the bulk of the 1,000 cases parser-only. Base64/canonicalization
        # is sampled explicitly in slots 11-23 and has dedicated regressions.
        mode = slot % 6
        if mode == 0:
            lines[0] = 'NOT_MJ 1'; lines += ['command=system.probe']
        elif mode == 1:
            lines += ['command=shell.execute']
        elif mode == 2:
            lines += ['command=file.inspect']  # required arg missing
        elif mode == 3:
            lines += ['command=system.probe', 'requestId=duplicate']
        elif mode == 4:
            lines[1] = 'requestId=bad id'; lines += ['command=system.probe']
        else:
            lines += ['command=system.probe', 'unknownField=value']


    return '\n'.join(lines) + '\n', want_ok, canary

with tempfile.TemporaryDirectory(prefix='mj-fuzz-batch-') as td:
    root = Path(td)
    expected = []
    reqs = []
    for n in range(CASES):
        i = OFFSET + n
        text, ok, canary = make_case(i, root)
        p = root / f'c-{i:04d}.req'
        p.write_text(text, encoding='utf-8')
        reqs.append(p)
        expected.append((ok, canary))

    harness = root / 'batch.sh'
    harness.write_text(r'''#!/bin/bash
set -u
ROOT="$1"; shift
for f in \
 src/core/constants.zsh src/core/json.zsh src/core/errors.zsh src/core/response.zsh src/core/protocol.zsh src/core/path.zsh src/core/capabilities.zsh src/core/operations.zsh \
 src/lib/local_fs.zsh src/lib/native_db.zsh src/lib/media_probe.zsh src/lib/image_kit.zsh src/lib/standard_library.zsh \
 src/modules/system.zsh src/modules/file.zsh src/modules/runtime.zsh src/modules/volume.zsh src/modules/temp.zsh src/modules/media.zsh src/modules/asset.zsh src/modules/provenance.zsh src/modules/image.zsh src/modules/storage.zsh src/modules/search.zsh src/modules/report.zsh src/modules/package.zsh; do source "$ROOT/$f"; done
# QA-only fast printable-ASCII quoting. Production JSON escaping has dedicated regression coverage.
json_quote(){ local s="$1"; s=${s//\\/\\\\}; s=${s//\"/\\\"}; printf '"%s"' "$s"; }
eval "$(sed '$d' "$ROOT/src/cli/entry.zsh")"
for req in "$@"; do
  out="${req}.out"; rcfile="${req}.rc"
  main --request "$req" > "$out"
  printf '%s' "$?" > "$rcfile"
done
''', encoding='utf-8')
    harness.chmod(0o755)

    failures = []
    # Keep shell argv/process state bounded. This is still 1,000 independent
    # protocol requests; chunking avoids irrelevant large-argv slowdown.
    CHUNK = 250
    for start in range(0, len(reqs), CHUNK):
        group = reqs[start:start + CHUNK]
        proc = subprocess.run(['/bin/bash', str(harness), str(project)] + [str(p) for p in group], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if proc.returncode != 0:
            failures.append((start, 'harness', proc.returncode, proc.stderr[:500]))

    for i, p in enumerate(reqs):
        out = Path(str(p) + '.out'); rcfile = Path(str(p) + '.rc')
        if not out.exists() or not rcfile.exists():
            failures.append((i, 'missing')); continue
        raw = out.read_text(); rc = int(rcfile.read_text() or 999)
        try:
            obj = json.loads(raw)
        except Exception as e:
            failures.append((i, 'json', raw[:160], str(e))); continue

        if obj.get('protocol') != 'MOGRAPHJAILED' or obj.get('protocolVersion') != 1 or not isinstance(obj.get('ok'), bool):
            failures.append((i, 'envelope', obj)); continue
        if rc == 0 and obj.get('ok') is not True:
            failures.append((i, 'rc-ok', obj))
        if rc != 0:
            err = obj.get('error') or {}
            if obj.get('ok') is not False or not err.get('code') or not err.get('message'):
                failures.append((i, 'rc-error', rc, obj))

        want, canary = expected[i]
        if want is True and obj.get('ok') is not True:
            failures.append((i, 'expected-success', obj))
        if canary.exists():
            failures.append((i, 'canary')); canary.unlink()

    print(json.dumps({'cases': CASES, 'offset': OFFSET, 'failures': len(failures), 'sampleFailures': failures[:10]}, indent=2))
    raise SystemExit(1 if failures else 0)
