# MographJailed 0.2.0-dev.4.1 — Release Manifest

## Identity

- CLI: `0.2.0-dev.4.1`
- Protocol: `1`
- Capability Registry: `2`
- Terminal UX: `1`
- Release class: target-Mac qualification hotfix

## Public protocol surface

20 allowlisted operations. No command was added or removed.

## Hotfixes

- zsh runtime path resolution uses `ZSH_ARGZERO` so `runtime.verify` remains correct inside zsh functions.
- `mj-top` launches a clean `/bin/zsh -f` worker instead of an inherited interactive subshell.
- dashboard temp files remain worker-owned and trap-cleaned.

## QA

- deterministic: 421/421
- protocol fuzz: 1,000/1,000, 0 failures
- deterministic production CLI SHA-256: `28d2944817be1beaf55304eb06b6ab29c41dd0b43ff6571a6bbf22e91fc07577`

## Runtime dependencies

No downloaded runtime dependency added. Production CLI remains stock macOS only. Optional terminal UX continues to use stock macOS `awk`, `less`, `osascript`, and `zsh`.

## Target-Mac promotion gate

Run `tests/DEV4_1_MAC_QUALIFICATION.md`. In particular, confirm `Runtime verify` is PASS and `mj-top` returns without Apple Terminal `Saving session...` output.
