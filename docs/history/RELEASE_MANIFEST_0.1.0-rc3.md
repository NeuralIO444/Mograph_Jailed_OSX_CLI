# MographJailed 0.1.0-rc3 Release Manifest

Release date: 2026-09-17

## Release status

- M1 Protocol + Capability Probe: **21/21**.
- M2 Filesystem Core: **26/26** portable tests; target macOS APFS/SMB/hash gate remains.
- M3 Media Core: **8/8** portable tests; target macOS metadata gate remains.
- M4 After Effects Integration: **14/14** static/pure-client tests; managed-Mac AE execution gate remains.
- M5 Packaging + Tech Report: **12/12** portable/static tests; native `ditto` success-path gate remains.
- M6 Native Media Lab: **7/7** research/static checks; JXA/AVFoundation/Core Image remain outside production.
- Cross-milestone QA swarm: **32/32**.
- RC3 environment/symlink/scope hardening: **32/32**.
- Concurrency: **62/62**.
- Command-contract parity: **3/3**.

Included deterministic automated total: **217/217 passing**.

Separate QA-only deterministic protocol fuzz pass: **1,000/1,000 cases, 0 failures**.

Separate file-mutation stress: **PASS** — a deliberate append during a 256 MB hash returned `SOURCE_CHANGED` / exit 74.

## RC3 engineering disposition

RC3 supersedes RC2 for further qualification. Major hardening in this candidate includes:

- function-local runtime temporary state, eliminating a P1-capable shell variable collision class exposed during RC3 adapter work;
- normalized PATH/locale/IFS/macOS compatibility environment and removal of known `ditto`/Perl hook variables;
- `/bin/zsh -f` + `emulate -R zsh` startup hardening;
- canonical, path+user-bound temp ownership markers;
- canonical package source/output handling and clearer race/publish failure behavior;
- no default `avmediainfo` execution in `media.inspect`;
- advisory `writableHint` semantics;
- native `sha256` preference plus optional `shasum` fallback;
- pre/post device+inode+size+mtime stability checking around SHA-256;
- deterministic POSIX-shell source-to-dist build and parity enforcement;
- expanded environment, symlink, concurrency, contract and fuzz QA.

See `QA_RC3_REPORT.md` for findings and dispositions.

## Production artifact hashes

- `dist/mograph-jailed.zsh`
  - SHA-256: `73cdddf727b060b3aae772ff2fc9aa241a20ff4f54f30ee98cfbb96f31663cb9`
- `integrations/after-effects/MographJailed_Client.jsxinc`
  - SHA-256: `12967a3e4fc3637ea76543248a2af2317eabb1ed3165753773fc874ab75e86dd`
- `integrations/after-effects/MographJailed_AE_Spike.jsx`
  - SHA-256: `ba69c7fca3a22b4d135f19f762b5e5dfd8b4d04038d7c3a4cee29e61db496e6d`
- `PROJECT_PLAN.md`
  - SHA-256: `e6fae3f92abd22785583f2a19213e80947b2cd65f1b027afecf9b92e7a655d9f`
- `QA_RC3_REPORT.md`
  - SHA-256: `80a6ddcf2bd8d9c4a4d93ed1057e2f8a65957b85a4e5bd514cf95e05e1c59b5c`
- `DEPENDENCY_AUDIT.md`
  - SHA-256: `b8da48ae09bb673b6a6d76b508b39c13c21d5c69f5b3255ccdff697a2a3d37a8`
- `PERFORMANCE_BASELINE.md`
  - SHA-256: `e60ba28cf2f137a9c1bce9ab758baf1885de79690199a7ce31fb18e237f2e0c3`
- `tests/TARGET_MAC_QUALIFICATION.md`
  - SHA-256: `33b6a1d44684676a0fd3a94c685cb180a49c3b948b3a57d3c99fae27c1c94851`

## Runtime policy

MographJailed `0.1.0-rc3` is local-only and zero-install by design. It exposes named allowlisted operations rather than arbitrary shell execution. Source media is read-only. Production commands do not execute JXA. Runtime Python, Node, jq, Homebrew, FFmpeg, OpenCV, Xcode/CLT, daemons, local servers, and cloud processing are not required.

After Effects `system.callSystem()` is synchronous. Routine AE integration avoids full-file hashing and does not execute `avmediainfo`. Full hashing and ZIP creation are explicit operations.

## Required target-Mac gates

Before declaring `0.1.0` production-ready, run `tests/TARGET_MAC_QUALIFICATION.md`, covering:

1. APFS + SMB filesystem classification, free-space facts and advisory write hints.
2. Native SHA-256 adapter selection and file-hash stability behavior.
3. `mdls` metadata against representative media and proof that default `media.inspect` does not run `avmediainfo`.
4. Managed After Effects -> `/bin/zsh -f` -> request file -> structured JSON response, including spaces/apostrophes/Unicode paths and clean stdout.
5. Native `/usr/bin/ditto` ZIP creation, canonical output and no-overwrite behavior.

M6 promotion is not required for V0.1 and remains experimental.

## Archive verification rule

The published RC3 ZIP is valid only if a fresh extraction can rebuild `dist/mograph-jailed.zsh`, reproduce source-to-dist parity, and pass the full deterministic portable suite without referring to the development workspace.
