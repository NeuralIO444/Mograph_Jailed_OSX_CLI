# MographJailed 0.1.0-rc3 Independent Engineering Review

Date: 2026-09-17

## Executive disposition

**PROMOTE AFTER TARGET-MAC QUALIFICATION.**

RC2 should not be promoted further. The independent review produced enough hardening and one P1-capable shell-state finding during RC3 development to justify an immutable new release candidate. RC3 has no unresolved P0/P1 findings in portable QA. macOS/After Effects/`ditto` semantics remain explicit environment gates.

## QA summary

Included deterministic portable suites:

- M1 Protocol + Capability Probe: **21/21**
- M2 Filesystem Core: **26/26**
- M3 Media Core: **8/8**
- M4 After Effects static/pure client: **14/14**
- M5 Packaging + Tech Report portable/static: **12/12**
- M6 isolated research checks: **7/7**
- Cross-milestone QA swarm: **32/32**
- RC3 environment/symlink hardening: **32/32**
- Concurrency: **62/62**
- Command-contract parity: **3/3**

**Included deterministic total: 217/217 passing.**

Separate QA-only deterministic protocol fuzz run: **1,000/1,000 cases, 0 failures**.

Separate mutation stress: a deliberate append during a 256 MB SHA-256 operation produced `SOURCE_CHANGED` / exit 74 as intended.

## Findings

| ID | Severity | Area | Finding | Disposition | Regression |
|---|---|---|---|---|---|
| RC3-001 | P1-capable | Shell state | Temporary function variables used global/dynamic shell state. During RC3 SHA adapter work this produced a real wrong-target hash in the development branch when a helper overwrote a caller temporary. | **Fixed.** Runtime helper temporaries are function-local; intentionally shared protocol/error/result state remains explicit. | Scope-contamination tests + all file-hash tests. |
| RC3-002 | P2 | Environment | Runtime inherited more process environment than necessary. Absolute paths already limited PATH attacks, but locale, compatibility flags and tool hook variables could still influence native behavior. | **Fixed.** Normalize PATH/locale/IFS/`COMMAND_MODE`; unset compatibility, `ditto`/copyfile, Perl and startup hook variables after startup. | Hostile PATH + Perl-hook hash test; static environment contract. |
| RC3-003 | P2 | Shell startup | Supported AE invocation did not explicitly suppress user zsh startup files. | **Fixed.** AE invokes `/bin/zsh -f`; production shebang is `#!/bin/zsh -f`; bundle runs `emulate -R zsh`. `/etc/zshenv` remains a target-Mac/IT gate. | M4/static + RC3 hardening. |
| RC3-004 | P2 | Temp lifecycle | Temp root could be lexically safe yet reached through a symlink; ownership marker proved MJ protocol identity but was not bound to exact created path/user. | **Fixed.** Canonical temp root; RC3 marker binds canonical path + effective user; retarget/tamper/control-TMPDIR tests fail closed. | RC3 hardening suite. |
| RC3-005 | P2 | Packaging | Package output/source canonicalization and publish-failure classification could be stronger. | **Fixed.** Canonical source/output parent, source recheck, canonical publish path, no-overwrite `mv -n`, separate package-failure vs output-race response. | M5 + static hardening; success path remains macOS gate. |
| RC3-006 | P2 | AE responsiveness | Default `media.inspect` executed `avmediainfo` even though its result was not consumed as stable structured data. This could add synchronous network/media delay without trustworthy product value. | **Fixed.** Default inspection only reports `avmediainfo` availability and returns `nativeProbe:"notRun"` when present. | M3 + hardening static contract. |
| RC3-007 | P2 | File identity | Full SHA-256 could succeed even if a file was visibly replaced/modified during the read, reducing value as durable asset identity. | **Fixed.** Pre/post followed-target device+inode+size+mtime check; obvious changes fail with `SOURCE_CHANGED`. | M2 normal/symlink tests + 256 MB mutation stress. |
| RC3-008 | P2 | Build reproducibility | Production bundle regeneration depended on zsh in the build environment even though bundling is text assembly. | **Fixed.** Builder is POSIX `/bin/sh`; output remains zsh. Source-to-dist byte parity remains release-blocking. | QA swarm parity + RC3 build check. |
| RC3-009 | P3 | API semantics | `writable` implied stronger guarantees than shell permission tests provide, particularly on mounted/read-only/network filesystems. | **Fixed.** Public field is `writableHint` and explicitly advisory. | M2/hardening + docs. |
| RC3-010 | P3 | Contract drift | Command names are duplicated across protocol, CLI router and AE client. | **Mitigated.** Added exact command-set parity test. | Contract audit 3/3. |

No unresolved P0/P1 findings remain in the portable review.

## Architecture review

The project boundary remains appropriate. MographJailed is still a native capability layer rather than an After Effects business-logic or workflow engine. There is no public arbitrary command executor, no background service, no MCP responsibility, and no Looper strategy logic in the core.

The three-tier direction remains valid:

1. MJ protocol + pure shell/native adapters.
2. Optional macOS CLI capabilities.
3. Experimental AVFoundation/Core Image research isolated outside production.

## Security review

Confirmed in production source/distribution:

- no public `shell.execute` / raw command API;
- no `eval`;
- no production `sh -c` or `zsh -c` request path;
- arguments cross the protocol as canonical Base64 data;
- request/control/size bounds remain enforced;
- native adapters use absolute executable paths;
- temp cleanup requires canonical-root + marker proof;
- package creation refuses overwrite and top-level source symlink;
- source media operations remain read-only;
- JXA/`osascript` is capability-reported only, not executed by production operations.

Remaining shell/filesystem limitation: no shell-only design can make same-user path replacement races mathematically impossible. Destructive scope is intentionally constrained to MJ-owned temp cleanup, and packaging only creates a previously absent requested archive.

## Darwin vs Linux semantics

Portable QA intentionally uses Linux compatibility branches where needed. macOS behavior is not inferred from Linux results.

Mac-specific gates remain for:

- BSD `stat` formats and `-L` followed-target hash identity;
- `df -Y` filesystem type on APFS/SMB;
- native `sha256` vs `shasum` selection;
- `mdls` metadata output;
- `/usr/bin/ditto` archive creation and `mv -n` publication;
- zsh startup behavior under enterprise `/etc/zshenv`;
- After Effects `system.callSystem()` execution.

## Environment poisoning answers

1. **Can PATH poisoning execute an unintended native binary?** Production adapters use absolute paths; RC3 also resets PATH. Portable hostile-PATH test passed.
2. **Can locale alter parsed output?** RC3 sets `LC_ALL=C` and `LANG=C` before adapters execute.
3. **Can TMPDIR manipulation bypass containment?** Relative/control-character roots are refused; symlink roots canonicalize; retargeting causes cleanup refusal.
4. **Can compatibility/tool environment variables alter behavior?** Known macOS `SYSTEM_VERSION_COMPAT`, `ditto`/copyfile and Perl hooks are removed after startup. User zsh startup is skipped with `-f`; `/etc/zshenv` remains target-Mac controlled.

## Concurrency

Portable concurrency tests passed for 12 simultaneous temp creates, 12 simultaneous cleanup operations, and 12 simultaneous hashes. No shared temp filenames or cross-run deletion was observed. `mktemp` provides unique workspaces.

Package same-destination concurrency still requires the target Mac because the real implementation requires `ditto`; publication uses a staged archive plus `mv -n` and refuses an output that appears during creation.

## Protocol / compatibility

Protocol remains v1. RC3 does not add a raw execution escape hatch. Unknown request fields and command-invalid arguments are rejected. Clients may ignore additive response fields, and protocol-breaking future changes must trigger an explicit version decision.

The protocol, CLI router and AE allowlist now have an exact parity test.

## Media correctness

`media.inspect` returns file facts plus advisory `mdls` metadata when available. It does not claim media validation. It does not execute `avmediainfo` in the default path. `media.timing` remains deliberately fail-closed because no documented stable structured sample-timing adapter has been promoted.

## After Effects blocking

`system.callSystem()` is treated as synchronous. Operation classes:

- **FAST/BOUNDED-INTENT:** `system.probe`, `system.doctor`, local `file.inspect`, local `volume.inspect`.
- **MAY BLOCK ON NETWORK:** `file.inspect`, `media.inspect`, `volume.inspect` against stale/slow SMB paths.
- **POTENTIALLY SLOW / EXPLICIT:** `file.hash`, `package.create`.
- **NOT IN DEFAULT PATH:** `avmediainfo`, forensic double-SHA verification.

There is no zero-install generic timeout primitive in the current architecture; UI consumers should keep expensive operations explicit and provide appropriate user feedback.

## Release reproducibility

- Modular source builds production `dist/mograph-jailed.zsh` with `scripts/build.zsh` using `/bin/sh`.
- Production output still targets `/bin/zsh -f`.
- Source-to-dist byte parity is tested.
- A clean extraction/rebuild/retest is required immediately before publishing RC3.

## Dependency audit

See `DEPENDENCY_AUDIT.md`. Production does not depend on Python, Node, jq, package managers, FFmpeg, OpenCV, Xcode/CLT, daemons, or cloud APIs. QA-only tooling is explicitly separated.

## Remaining target-Mac gates

1. APFS + SMB filesystem type/classification and free-space behavior.
2. Native SHA adapter and followed-target hash stability behavior.
3. `mdls` metadata on representative ProRes/H.264/HEVC and SMB media.
4. Managed After Effects → `/bin/zsh -f` → request → JSON response round trip.
5. Clean stdout under enterprise `/etc/zshenv` policy.
6. `ditto` ZIP success path, symlink behavior and same-destination no-overwrite behavior.

## Final RC3 decision

Portable disposition: **PASS**.

Promotion disposition: **RC3 → target-Mac qualification → 0.1.0**.

If a target-Mac P0/P1 issue appears, RC3 remains immutable and the fix must ship as RC4 rather than mutating RC3 in place.
