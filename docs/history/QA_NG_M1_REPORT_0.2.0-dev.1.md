# MographJailed 0.2.0-dev.1 — NG-M1 QA Report

## Scope

NG-M1 adds Capability Registry 2.0 and runtime trust without changing the existing Protocol v1 transport or the semantics of qualified RC3 operations.

New public operations:

- `system.describe`
- `runtime.verify`

New AE client helpers:

- `describe(forceRefresh)`
- `verifyRuntime(options)`
- `can(command)`
- `isInteractiveSafe(command)`

## Results

Legacy/regression suites: **218/218 passed**.

NG-M1-specific suite: **39/39 passed**.

Combined deterministic total: **257/257 passed**.

Protocol fuzz: **1,000 generated requests, 0 failures** using the QA-only batch harness. The semantic operation suite separately covers real registry/runtime-verification behavior.

## Review findings closed

- Runtime SHA utilities are optional for `runtime.verify` unless the caller supplies an expected digest; the registry advertises them as optional rather than mandatory.
- Protocol, command router, AE command allowlist, and Capability Registry command list are parity-tested.
- Runtime verification discloses the runtime filename, not its full filesystem path.
- Version/protocol/filename mismatches produce a valid diagnostic result with `compatible:false`; malformed verification arguments still fail closed as protocol errors.
- `media.timing` remains explicitly `LAB_GATED` and unavailable rather than being inferred from undocumented `avmediainfo` text.

## Remaining gate

Target-Mac qualification for `system.describe` and `runtime.verify`, including the exact release SHA-256 and the updated After Effects client, remains required before any 0.2 production promotion.
