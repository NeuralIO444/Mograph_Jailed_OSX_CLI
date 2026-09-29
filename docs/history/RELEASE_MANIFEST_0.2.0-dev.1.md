# MographJailed 0.2.0-dev.1 Release Manifest

## Identity

- CLI version: `0.2.0-dev.1`
- Protocol version: `1`
- Capability Registry: `2`
- Release class: development / target-Mac qualification candidate
- Stable reference: 0.1.x remains unchanged

## New production source

- `src/core/operations.zsh`
- `src/modules/runtime.zsh`

## New public operations

- `system.describe`
- `runtime.verify`

## Updated integration

`integrations/after-effects/MographJailed_Client.jsxinc` adds:

- `describe(forceRefresh)`
- `verifyRuntime(options)`
- `can(command)`
- `isInteractiveSafe(command)`

## QA evidence

- 218/218 legacy/regression tests
- 39/39 NG-M1 semantic tests
- 257/257 deterministic combined total
- 1,000/1,000 protocol fuzz requests
- 4/4 command contract parity checks included in the deterministic total

## Bundle integrity

`dist/mograph-jailed.zsh`

SHA-256: `06df4181bcc089e376b19b1424408769d57ab7d41a67c18d7fae3e88ce4ef907`

The production bundle is generated deterministically from modular source by `scripts/build.zsh`. Source-to-dist parity remains release-blocking.

## Runtime dependencies

No new runtime dependency was introduced. Production remains stock-macOS zsh/native utilities only.

## Remaining qualification

See `tests/NG_M1_MAC_QUALIFICATION.md`.
