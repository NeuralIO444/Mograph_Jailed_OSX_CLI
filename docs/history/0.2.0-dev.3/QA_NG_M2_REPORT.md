# MographJailed 0.2.0-dev.3 — NG-M2 QA Report

## Scope

NG-M2 adds conservative Asset Intelligence operations on top of the qualified core and NG-M1 Capability Registry 2.0. Protocol v1 remains unchanged.

New public operations:

- `asset.manifest`
- `asset.verify`
- `search.candidate`
- `file.provenance`
- `image.inspect`
- `image.derivative`
- `storage.preflight`

## Portable deterministic QA

NG-M2-specific suite: **64/64 passed**.

The suite covers fast/SHA manifests, identity verification success/mismatch/failure cases, storage preflight, protocol schemas, capability-registry metadata, read-only provenance implementation, derivative staging/non-overwrite/source-safety structure, advisory/no-relink search semantics, AE client helpers, and production-bundle inclusion.

All legacy, NG-M1, NG-M2, and dev.3 independent hardening suites now pass in one aggregate invocation. The deterministic suite total is **346/346**. See `QA_INDEPENDENT_REVIEW_DEV3.md` for the release-blocking issues found in dev.2 and fixed in dev.3.

## Protocol fuzzing

Two independent batches covered 1,000 unique request IDs/cases total:

- offsets 0–499: **500/500, 0 failures**
- offsets 500–999: **500/500, 0 failures**

The fuzzer focuses on parser/envelope/allowlist/Base64/schema/shell-canary behavior. Native operation semantics are covered by dedicated deterministic suites rather than using fuzzing as a performance benchmark.

## Environment-gated behavior

The Linux QA host cannot truthfully validate Apple implementations of:

- `/usr/bin/mdfind`
- `/usr/bin/xattr`
- `/usr/bin/sips`

Those adapters fail closed as `UNSUPPORTED` when unavailable and have static safety checks. Their real behavior must be validated using `tests/NG_M2_MAC_QUALIFICATION.md` before this development line is promoted for production use.

## Current decision

`0.2.0-dev.3` is suitable as a development/target-Mac qualification candidate. It does **not** replace the qualified 0.1.x production runtime yet.
