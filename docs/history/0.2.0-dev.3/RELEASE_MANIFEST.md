# MographJailed 0.2.0-dev.3 Release Manifest

## Identity

- CLI version: `0.2.0-dev.3`
- Protocol version: `1`
- Capability Registry: `2`
- Release class: development / target-Mac qualification candidate
- Stable reference: qualified 0.1.x remains unchanged
- Prior development checkpoints: `0.2.0-dev.1` (NG-M1), `0.2.0-dev.2` (superseded NG-M2 candidate)

## NG-M2 production modules

- `src/modules/asset.zsh`
- `src/modules/provenance.zsh`
- `src/modules/image.zsh`
- `src/modules/storage.zsh`
- `src/modules/search.zsh`

## New public operations

- `asset.manifest`
- `asset.verify`
- `search.candidate`
- `file.provenance`
- `image.inspect`
- `image.derivative`
- `storage.preflight`

The public command surface is now 20 allowlisted operations. Protocol/router/AE client/Capability Registry parity is release-tested.

## Independent dev.3 hardening

The dev.2 release artifact was independently re-extracted and reviewed before target-Mac qualification. dev.3 fixes two release-blocking findings and two defense-in-depth issues:

- ownership-bound staging cleanup for image derivatives and packages
- positive `sips` image identification; non-images no longer succeed with null structure
- Capability Registry/handler dependency reconciliation
- non-recursive cleanup during ownership-marker initialization failure

See `QA_INDEPENDENT_REVIEW_DEV3.md`.

## Integration additions

`integrations/after-effects/MographJailed_Client.jsxinc` adds semantic wrappers for:

- `assetManifest`
- `assetVerify`
- `searchCandidate`
- `fileProvenance`
- `inspectImage`
- `createImageDerivative`
- `storagePreflight`

## Safety semantics

- asset operations are read-only
- Spotlight search is advisory only and never relinks
- provenance lists xattr names only and has no write/delete/clear path
- image derivative creation is staged and refuses overwrite
- derivative input identity is checked before/after processing
- storage `writableHint` remains advisory
- macOS-specific adapters fail closed when unavailable

## QA evidence

Portable deterministic suites, all passing individually:

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

**Deterministic total: 346/346.**

Protocol fuzzing:

- offsets 0–499: 500 cases / 0 failures
- offsets 500–999: 500 cases / 0 failures
- **total: 1,000 cases / 0 failures**

Evidence is retained under `tests/results/`.

## Production bundle integrity

`dist/mograph-jailed.zsh`

SHA-256:

`d97ce0ffdd5945daaafb2898b8b561f960300bfc7d0cb26afd9e408695935829`

The bundle is generated deterministically from modular source by `scripts/build.zsh`. Source-to-dist parity remains release-blocking. dev.3 adds ownership-bound derivative/package staging cleanup and positive `sips` image identification.

## Runtime dependencies

No downloaded runtime dependency was introduced. Production remains stock-macOS zsh/native utilities only. New optional/native adapters use `mdfind`, `xattr`, and `sips` when capability-probed.

## Remaining qualification

See `tests/NG_M2_MAC_QUALIFICATION.md`. The macOS-specific search/provenance/image adapters must pass on the managed production Mac before this development line is promoted for production use or bundled into team Looper distributions.
