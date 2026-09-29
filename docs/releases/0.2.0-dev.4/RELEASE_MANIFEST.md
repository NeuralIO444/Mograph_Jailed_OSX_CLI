# MographJailed 0.2.0-dev.4 — Release Manifest

## Identity

- CLI: `0.2.0-dev.4`
- Protocol: `1`
- Capability Registry: `2`
- Terminal UX: `1`
- Release class: development / target-Mac qualification candidate

## Public protocol surface

20 allowlisted operations. No command was added or removed in dev.4.

## Runtime correction

Capability Registry `requires.all` and `optionalCapabilities` now serialize one capability per JSON array element under production zsh and QA bash.

## Optional terminal UX

Project-local files:

- `scripts/shell/mj-terminal.zsh`
- `scripts/shell/mj-man.zsh`
- `scripts/shell/mj-top.zsh`
- `scripts/shell/install-terminal-ux.sh`
- `scripts/terminal/mj-md-render.awk`
- `scripts/terminal/mj-top-render.js`
- `docs/man/*`

These files are not included in the production CLI bundle.

## Integration documentation

- `docs/integrations/MJ_Organize_Native_Handoff.md`

## QA

- deterministic: 407/407
- protocol fuzz: 1,000/1,000, 0 failures
- deterministic source build SHA: `cf9cf57269b684ffa31d23903c254632881fff8497b79f349009f1c35ac1cdf5`

## Runtime dependencies

No downloaded runtime dependency added. The production CLI dependency set remains stock macOS only. Optional terminal presentation uses stock macOS `awk`, `less`, and `osascript` when invoked.

## Promotion gate

Requires `tests/DEV4_MAC_QUALIFICATION.md` on the managed production Mac before dev.4 supersedes dev.3 as the preferred local development build.
