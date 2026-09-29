# MographJailed Milestone Receipt

Release candidate: **0.1.0-rc3**

## M1 — Protocol + Capability Probe

**Plan:** remove hidden runtime dependencies; define allowlisted request protocol and JSON envelope.  
**Implement:** modular protocol, errors, capability registry, `system.probe`, `system.doctor`, deterministic bundler.  
**Review:** removed `eval`; corrected subshell error-state loss; added command-specific schemas, request bounds, canonical Base64 checks, control-character rejection, and full JSON control escaping.  
**RC3 hardening:** fixed-path environment normalization and zsh `-f` startup policy.  
**QA:** **21/21** automated milestone tests pass.

Status: **COMPLETE**.

## M2 — Filesystem Core

**Plan:** immutable file reads, explicit hashing, conservative volume facts, marker-owned temp lifecycle.  
**Implement:** `file.inspect`, `file.hash`, `volume.inspect`, `temp.create`, `temp.clean`.  
**Review:** closed traversal-shaped cleanup paths; corrected macOS filesystem type to `df -Y`; canonicalized temp roots; bound RC3 markers to path+effective user; made write state advisory; added hash stability checking and native `sha256` preference.  
**QA:** **26/26** portable milestone tests pass plus separate source-mutation stress.

Status: **CODE COMPLETE / TARGET-MAC FILESYSTEM+HASH GATE REQUIRED**.

## M3 — Media Core

**Plan:** aggregate only source-attributed metadata; never guess missing media facts.  
**Implement:** `media.inspect`, optional `mdls`, `avmediainfo` capability reporting without default execution, `media.timing` fail-closed contract.  
**Review:** rejected parsing undocumented `avmediainfo` text and removed its synchronous default probe.  
**QA:** **8/8** portable milestone tests pass.

Status: **COMPLETE FOR V0.1 SCOPE / TARGET-MAC MEDIA GATE REQUIRED**. Structured sample timing remains intentionally unsupported.

## M4 — After Effects Integration Spike

**Plan:** minimal JSX client; request-file transport; one audited shell boundary.  
**Implement:** probe, doctor, bounded read-only media inspection, explicit forensic double-SHA option, Base64 request encoder, embedded JSON parser, diagnostic spike UI.  
**Review:** removed host `JSON.parse` dependency; hardened request cleanup/allowlisting; removed default full-file hashing; changed invocation to `/bin/zsh -f`.  
**QA:** **14/14** static/pure-function tests pass.

Status: **CODE COMPLETE / TARGET-MAC AFTER EFFECTS GATE REQUIRED**.

## M5 — Packaging + Tech Report Integration

**Plan:** privacy-minimal environment receipt and report-only ZIP packaging.  
**Implement:** `report.tech`, `package.create`.  
**Review:** canonical source/output parents, no-overwrite staging, source recheck, race-aware `mv -n`, source-tree output rejection and top-level symlink rejection.  
**QA:** **12/12** portable/static milestone tests pass.

Status: **CODE COMPLETE / TARGET-MAC DITTO GATE REQUIRED**.

## M6 — Native Media Lab

**Plan:** determine whether JXA + AVFoundation + Core Image should enter production.  
**Implement:** isolated framework probe and research specifications; no production route added.  
**Review:** kept framework access isolated because managed-Mac/XProtect/TCC behavior is not proven.  
**QA:** **7/7** research/static checks pass.

Status: **COMPLETE — DO NOT PROMOTE TO V0.1**.

## Cross-milestone review

- Original QA swarm regression/security suite: **32/32**.
- RC3 environment/symlink/scope hardening suite: **32/32**.
- Concurrency suite: **62/62**.
- Protocol/CLI/AE command-contract parity: **3/3**.

Included deterministic aggregate: **217/217 passing**.

Separate deterministic QA-only protocol fuzz pass: **1,000/1,000 cases, 0 failures**. Python is used only by this QA harness and is not a runtime dependency.

Separate mutation stress: **PASS** (`SOURCE_CHANGED` detected during a deliberately modified 256 MB hash).

## Overall

Portable implementation/review: **PASS**.  
Target-environment gates still required: **macOS APFS/SMB/hash semantics, macOS media metadata, managed After Effects runtime, native `ditto` packaging**.  
Production JXA dependency: **none**.  
Production arbitrary-shell command API: **none**.

See `QA_RC3_REPORT.md` and `tests/TARGET_MAC_QUALIFICATION.md` before promotion to `0.1.0`.
