# MographJailed QA Swarm Report

Release candidate: **0.1.0-rc2**  
Review date: **2026-09-17**

## Executive result

The QA swarm reproduced the original RC1 baseline from a fresh extraction, then reviewed the project through protocol/security, filesystem/destructive operations, media correctness, After Effects integration, and release/packaging lenses.

RC1 should **not** be promoted. The swarm found multiple defects that were not covered by the original 70-test suite. All portable defects identified in this pass have been corrected in RC2 and have regression coverage.

Current portable verification:

- Included automated suites: **118/118 passing**.
- Separate deterministic randomized protocol fuzz pass: **400/400 cases passing, 0 failures**.
- Production arbitrary-shell execution API: **none**.
- Production JXA execution path: **none**.
- Source media mutation path: **none**.

RC2 remains a release candidate because macOS/After Effects-only qualification gates cannot be truthfully executed in the Linux QA environment.

## QA lenses

### 1. Protocol and security

Reviewed request parsing, schema enforcement, Base64 handling, JSON envelopes, shell injection boundaries, request limits, error behavior, command allowlisting, and hostile path syntax.

### 2. Filesystem and destructive operations

Reviewed immutable file inspection, hashing, temporary-directory ownership, cleanup boundaries, traversal-shaped paths, symlinks, volumes, package staging, overwrite behavior, and source-tree protection.

### 3. Media correctness

Reviewed metadata attribution, `mdls` behavior assumptions, `avmediainfo` scope, unsupported structured timing behavior, source immutability, and the boundary between advisory metadata and authoritative timing data.

### 4. After Effects integration

Reviewed ExtendScript request generation, shell quoting, response parsing, host-runtime assumptions, synchronous subprocess behavior, and the default media-inspection path.

### 5. Release and packaging

Reviewed self-contained tests, build inputs, runtime capability registration, documentation/implementation drift, `ditto` assumptions, release identity, and clean-extraction reproducibility.

## Findings and disposition

### QA-001 — Required-argument errors lost their error state

**Severity:** Release blocker  
**Status:** Fixed

Handlers previously called `require_arg` inside command substitution. Shell command substitution executes in a subshell, so `set_error` changes were discarded. Missing required arguments could therefore return a failure envelope with blank `error.code` and `error.message`.

Resolution:

- `require_arg` now writes to a controlled global result variable rather than returning values through command substitution.
- Command schemas validate required arguments before dispatch.
- Every path-requiring command has regression coverage for populated failure envelopes.

### QA-002 — macOS volume filesystem classification used the wrong BSD `stat` semantics

**Severity:** Release blocker  
**Status:** Fixed; target-Mac semantic gate remains

The Darwin adapter used `stat -f '%T'` as though `%T` returned the mounted filesystem type. On macOS/BSD `stat`, `-f` specifies a format and `%T` describes the file-object type. That would not reliably identify APFS/SMB/NFS volumes.

Resolution:

- Darwin now uses `df -kY`, whose type column is appropriate for mounted filesystem classification.
- If filesystem type cannot be established, the adapter returns `null` / `unknown` rather than guessing.
- `tests/M2_MAC_TEST_CHECKLIST.md` explicitly verifies APFS and SMB behavior on the target Mac.

### QA-003 — M4 test was not self-contained

**Severity:** Release blocker  
**Status:** Fixed

The original M4 Node test referenced a hardcoded `/mnt/data/MographJailed` path. A clean release extraction could therefore test a different workspace and report a false pass.

Resolution:

- M4 resolves the client relative to its own test directory.
- Clean-extraction verification is a release gate.

### QA-004 — Default AE media inspection performed two full-file hashes

**Severity:** High  
**Status:** Fixed

The initial AE sample hashed the complete media source before and after inspection. `system.callSystem()` is synchronous, so large ProRes assets or SMB-hosted sources could block the After Effects UI for a long period.

Resolution:

- Routine `inspectMediaReadOnly()` now checks size + modification time around metadata inspection.
- Full before/after SHA-256 remains available only as explicit `inspectMediaImmutable()` forensic validation.
- The Mac checklist warns against double-hashing large/network sources in the normal UI path.

### QA-005 — Known but irrelevant arguments were silently accepted

**Severity:** Medium  
**Status:** Fixed

The parser allowlisted argument names globally but did not initially enforce command-specific schemas, allowing irrelevant known arguments to be ignored.

Resolution:

- Every command now has an explicit allowed/required argument schema.
- Unexpected arguments fail closed with `UNEXPECTED_ARGUMENT`.

### QA-006 — Request resource bounds were incomplete

**Severity:** Medium  
**Status:** Fixed

The request format needed explicit upper bounds to avoid unbounded line/argument input at the shell boundary.

Resolution:

- Maximum request lines: 32.
- Maximum encoded line length: 32768 characters.
- Maximum decoded argument length: 16384 characters.
- Request IDs remain restricted to a small safe character set and bounded length.

### QA-007 — Base64/shell representability needed canonical validation

**Severity:** Medium  
**Status:** Fixed

Decoded protocol values need to remain representable by the shell without silent transformation.

Resolution:

- Base64 is decoded and re-encoded canonically before acceptance.
- ASCII control characters are rejected.
- JSON output escaping covers ASCII control characters.

### QA-008 — Relative temporary roots could undermine cleanup assumptions

**Severity:** Medium  
**Status:** Fixed

A non-absolute `TMPDIR` could create ambiguity between the path returned at creation and the cleanup root.

Resolution:

- MJ temp creation requires an absolute temp parent.
- Cleanup requires the exact immediate parent to be the actual MJ temp root.
- Traversal-shaped and trailing-slash variants are rejected.
- Only marker-owned MJ temp directories can be deleted.

### QA-009 — Runtime version did not identify the release candidate

**Severity:** Low  
**Status:** Fixed

RC1 reported the generic `0.1.0` CLI version rather than its release-candidate identity.

Resolution:

- Runtime reports `0.1.0-rc2`.
- M1 regression verifies the exact CLI version.

### QA-010 — Media timing specification drifted beyond the safe implementation

**Severity:** Medium documentation/API risk  
**Status:** Fixed by narrowing the contract

`avmediainfo --samples` provides useful diagnostic evidence, but the project does not rely on its human-readable text as a documented stable machine schema.

Resolution:

- `media.timing` remains reserved/fail-closed in V0.1 with `UNSUPPORTED_STRUCTURED_OUTPUT` after input validation.
- Structured sample timing is deferred to a stable, validated data source such as a future AVFoundation adapter.
- Project documentation now matches the implementation.

### QA-011 — Capability registry omitted core commands actually used by the runtime

**Severity:** Low  
**Status:** Fixed

The implementation used a few core utilities without explicitly surfacing them in the environment capability report.

Resolution:

- Registry/Tech Report now also reports `sed`, `rm`, `mv`, and `pwd` alongside the other native dependencies.

### QA-012 — Production bundle could drift behind modular source

**Severity:** Release blocker  
**Status:** Fixed

The modular source and Linux QA bundle contained the protocol fixes, but the previously generated production `dist/mograph-jailed.zsh` had not been rebuilt and still contained pre-fix `require_arg` command-substitution handlers. The source-level suites therefore passed while the artifact intended for macOS distribution was stale.

Resolution:

- Rebuilt `dist/mograph-jailed.zsh` from the final modular source graph.
- Added a cross-platform regression that independently reconstructs the expected production bundle and requires byte-for-byte equality with `dist/mograph-jailed.zsh`.
- Release packaging now occurs only after this source/distribution parity check passes.

## Adversarial protocol pass

A separate deterministic 400-case fuzz pass was run outside the shipped runtime test suite. Python was used only by the QA harness in the Linux build container; Python is **not** a MographJailed runtime dependency.

Coverage included:

- valid no-argument operations;
- missing required fields/arguments;
- unsupported commands;
- invalid and noncanonical Base64;
- duplicate fields;
- irrelevant allowlisted arguments;
- ASCII control characters;
- shell-looking filenames/paths;
- JSON-envelope validation;
- error-code/message non-emptiness;
- exit-code / `ok` consistency;
- canary checks for accidental command execution.

Result: **400 cases, 0 failures, no canary execution**.

## Verified design properties

- No `eval` in production source.
- No `sh -c` / `zsh -c` public execution path.
- No `shell.execute` / raw-command protocol operation.
- `osascript` is capability-reported only; production commands do not invoke JXA.
- Package creation rejects a top-level symlink source, stages output, refuses overwrite, and refuses placing output inside the source tree.
- Media source files are never transcoded or rewritten by the V0.1 production command surface.
- `avmediainfo` human-readable output is not promoted into guessed structured timestamps.

## Known limitations / open target-environment gates

These are not portable-code failures; they require the actual managed macOS/After Effects environment.

1. **M2 volume gate:** verify APFS and SMB/NFS classification through native `df -Y`.
2. **M3 media gate:** verify `mdls` / optional `avmediainfo` behavior on representative production media and network volumes.
3. **M4 After Effects gate:** execute the JSX bridge through `system.callSystem()` in the managed AE environment, including paths with spaces, apostrophes, and Unicode.
4. **M5 packaging gate:** execute the native `/usr/bin/ditto` ZIP success path and no-overwrite behavior on macOS.

Additionally, `system.callSystem()` is synchronous. V0.1 therefore keeps potentially expensive operations such as full-file hashing and packaging explicit. There is no background cancellation/timeout engine in this release candidate.

M6 JXA/AVFoundation/Core Image remains a research lab and is not required for V0.1 promotion.

## Release recommendation

- **0.1.0-rc1:** superseded; do not promote.
- **0.1.0-rc2:** portable QA accepted, pending the four target-Mac gates above.
- **0.1.0 production:** promote only after all required target-Mac qualification items pass and their results are recorded.
