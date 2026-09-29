# MographJailed 0.2.0-dev.3 — Independent QA / Code Review

Date: 2026-09-22  
Review target: exact `0.2.0-dev.2` release ZIP, patched forward to `0.2.0-dev.3` after release-blocking findings.

## Decision

**0.2.0-dev.2 is superseded.**  
**0.2.0-dev.3 is the preferred NG-M2 target-Mac qualification candidate.**

Do not promote NG-M2 to a team production bundle until the macOS-specific `mdfind`, `xattr`, and `sips` qualification checklist passes on the managed production Mac.

## Review method

The review started from a fresh extraction of the published dev.2 ZIP rather than a development workspace. It included:

- complete deterministic regression suite
- manual source review of every NG-M2 module
- protocol/router/AE-client/Capability Registry parity
- destructive-operation review
- source-to-dist rebuild checks
- shell-safety/static scans
- current Apple/macOS command-semantics verification for `sips`, `mdfind`, `xattr`, `mktemp`, `mv`, `ditto`, `rm`, and symlink behavior
- 1,000-case protocol fuzzing
- new ownership-bound staging tests

## Findings fixed in dev.3

### QA-D3-001 — P1 — Unproven recursive staging cleanup

**Area:** `image.derivative`, `package.create`

The release used `mktemp -d` for safe stage creation, but subsequent failure/success cleanup performed `rm -rf` against the staging pathname without first re-proving that the directory was still the MJ-created stage. On a writable shared/network destination, concurrent path replacement could make that cleanup act on a replacement directory.

**Fix:**

- added ownership-bound stage markers
- markers bind protocol, request ID, exact stage path, effective user, and stage prefix
- recursive stage cleanup is permitted only after marker/path/prefix/owner validation
- package and image modules route every stage cleanup through the guarded helper
- marker initialization failures use non-recursive known-path cleanup rather than unproven `rm -rf`

**Regression:** dedicated marker-tamper/missing-marker tests plus static proof that image/package modules have no direct stage `rm -rf`.

**Residual limitation:** shell code cannot make hostile same-user TOCTOU races mathematically impossible between final validation and deletion. The new design materially reduces accidental/concurrent substitution risk and fails closed when ownership proof is missing. Team/shared-volume qualification remains required.

### QA-D3-002 — P1 — `image.inspect` false-success on non-image files

**Area:** `image.inspect`

A readable regular non-image file could reach the success response even if all `sips` image properties failed, producing `ok:true` with null structure fields.

**Fix:**

`image.inspect` now requires positive `sips` identification: a non-empty documented image format plus positive integer width and height. Otherwise it returns `INVALID_TARGET`.

`image.derivative` applies the same positive source-image gate before creating a derivative.

**Mac gate:** qualification now explicitly requires a plain-text/non-image file to fail rather than return a null-filled successful inspection.

### QA-D3-003 — P2 — Capability Registry / handler dependency drift

**Area:** Registry 2.0 metadata and direct handlers

Several descriptors omitted helper dependencies such as `uname`, while `storage.preflight`/`volume.inspect` overstated an unused `stat` dependency. Some handlers did not explicitly enforce the same dependency set advertised by `system.describe`.

**Fix:**

- corrected `requires.all` for file, asset, image, storage, volume, media, and packaging operations
- added direct fail-closed capability checks where NG-M2 handlers rely on those tools
- preserved `sha256`/`shasum` as the appropriate `anyOf`/optional identity dependency

### QA-D3-004 — P2 — Recursive cleanup during marker initialization

**Area:** `temp.create`, generic stage creation

Fresh `mktemp` directories were recursively removed if ownership-marker initialization failed.

**Fix:**

Initialization failure now removes only the known marker and attempts non-recursive removal of the newly created empty directory. Recursive removal remains limited to paths whose ownership has been proven.

## Apple command-semantics review

The implementation was checked against current macOS manual behavior:

- `sips -g`, `-Z`, format conversion, and `--out` are documented image operations.
- `mdfind -0`, `-onlyin`, and `-name` are documented Spotlight search options; results remain advisory.
- `xattr` without a mutation mode lists attribute names; production code has no `-w`, `-d`, or `-c` path.
- `mktemp -d` provides unique stage directory creation.
- `mv -n` is documented as no-overwrite; callers additionally verify whether the staged file remained.
- `ditto -c -k --keepParent` is a documented ZIP creation workflow; traversal does not follow nested symlinks.
- macOS `rm -r` does not follow directory symlinks, but MJ still requires ownership proof before recursive managed cleanup.

## QA results

Deterministic portable suites:

- M1: 21/21
- M2: 26/26
- M3: 8/8
- M4: 14/14
- M5: 12/12
- M6: 7/7
- QA swarm: 32/32
- RC3 hardening: 32/32
- concurrency: 62/62
- command-contract parity: 4/4
- NG-M1: 39/39
- NG-M2: 64/64
- dev.3 independent double-check: 25/25

**Deterministic total: 346/346 passed.**

Protocol fuzzing:

- requests 0–499: 500/500, 0 failures
- requests 500–999: 500/500, 0 failures
- **total: 1,000/1,000, 0 failures**

## Security/static review

Production source currently has:

- no `eval`
- no `sh -c`, `bash -c`, or `zsh -c`
- no public arbitrary shell operation
- no production JXA execution path
- no xattr mutation operation
- no automatic Spotlight relink operation
- no source-image mutation path
- no overwrite path for image derivatives or packages
- recursive deletion only behind MJ ownership validation (`temp.clean` and the generic guarded stage cleanup helper)

## Bundle identity

Current production CLI SHA-256:

`d97ce0ffdd5945daaafb2898b8b561f960300bfc7d0cb26afd9e408695935829`

A release ZIP hash is recorded in `RELEASE_MANIFEST.md` after final archive assembly.

## Remaining environment gates

Portable QA cannot certify Apple-specific runtime behavior. Before promotion, run `tests/NG_M2_MAC_QUALIFICATION.md` and verify at minimum:

- `sips` positive image inspection and non-image rejection
- PNG derivative creation/non-overwrite/no source mutation/no stage residue
- xattr names-only behavior
- scoped Spotlight candidate behavior
- APFS and approved SMB storage preflight semantics
- After Effects client round trip with the dev.3 runtime

