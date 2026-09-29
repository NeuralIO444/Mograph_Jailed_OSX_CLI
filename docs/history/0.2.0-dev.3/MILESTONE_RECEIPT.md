# MographJailed NG-M2 Milestone Receipt

**Version:** 0.2.0-dev.3  
**Protocol:** 1  
**Capability Registry:** 2  
**Milestone:** NG-M2 — Asset Intelligence

## Delivered

- `asset.manifest`
- `asset.verify`
- `search.candidate`
- `file.provenance`
- `image.inspect`
- `image.derivative`
- `storage.preflight`
- expanded 20-operation Capability Registry metadata
- semantic After Effects client wrappers
- NG-M2 target-Mac qualification checklist
- dedicated NG-M2 QA and fuzz evidence

## Intentional exclusions

NG-M2 does not provide:

- recursive project crawling
- automatic asset relinking
- xattr mutation
- source-image mutation
- overwrite of derivative output
- background indexing/service
- AVFoundation/Vision production execution

## Safety boundary

- Protocol v1 retained.
- No raw shell API added.
- Source assets remain immutable.
- Spotlight results remain advisory.
- Provenance is names-only/read-only.
- Derivatives stage into a new output and refuse overwrite.
- Qualified 0.1.x release remains separate and unchanged.

## QA

- Deterministic portable suites: **346/346 passed**
- NG-M2 semantic suite: **64/64 passed**
- dev.3 independent double-check: **25/25 passed**
- command-contract parity: **4/4 passed**
- NG-M2 protocol fuzz: **1,000 requests / 0 failures** across two 500-case batches

## Production bundle

`dist/mograph-jailed.zsh` SHA-256:

`d97ce0ffdd5945daaafb2898b8b561f960300bfc7d0cb26afd9e408695935829`

## Remaining gate

Run `tests/NG_M2_MAC_QUALIFICATION.md` on the managed production Mac before promoting NG-M2 or using its macOS-specific adapters in a team production bundle. dev.3 supersedes dev.2 for that qualification.
