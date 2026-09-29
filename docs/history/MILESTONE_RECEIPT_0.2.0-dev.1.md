# MographJailed NG-M1 Milestone Receipt

**Version:** 0.2.0-dev.1  
**Protocol:** 1  
**Capability Registry:** 2  
**Milestone:** NG-M1 — Capability Registry 2.0 + Runtime Trust

## Delivered

- `system.describe`
- `runtime.verify`
- per-operation availability/cost/mutation/authority/interactive/network metadata
- required and optional capability declarations
- After Effects client helpers for description, runtime verification, availability, and interactive-safety checks
- protocol/router/AE/registry command parity enforcement
- NG-M1 target-Mac qualification checklist

## Safety boundary

- Protocol v1 retained.
- No raw shell API added.
- No source-media mutation command added.
- No JXA/AVFoundation production dependency added.
- Runtime SHA verification is opt-in and targets the small MographJailed runtime, not production media.
- Qualified 0.1.x release remains separate and immutable.

## QA

- Legacy/regression: 218/218 passed
- NG-M1 semantic: 39/39 passed
- Deterministic total: 257/257 passed
- NG-M1 protocol fuzz: 1,000 requests / 0 failures

## Production bundle

`dist/mograph-jailed.zsh` SHA-256:

`06df4181bcc089e376b19b1424408769d57ab7d41a67c18d7fae3e88ce4ef907`

## Remaining gate

Run `tests/NG_M1_MAC_QUALIFICATION.md` on the managed production Mac before promoting this development line.
