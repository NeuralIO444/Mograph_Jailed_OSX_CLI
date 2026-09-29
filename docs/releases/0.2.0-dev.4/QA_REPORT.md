# MographJailed 0.2.0-dev.4 — Engineering QA Report

## Four-role loop

### Planner

Scoped dev.4 to one contract correction and one optional terminal-UX increment. Protocol v1 and the 20-operation public command surface remain unchanged. Live monitoring, media intelligence, daemons, system man pages, and new destructive operations were explicitly excluded.

### Implementation

Implemented:

- shell-independent Capability Registry array serialization
- `mj-man` v2 Markdown-to-terminal renderer
- snapshot-only `mj-top`
- modern / ASCII / plain presentation modes
- local terminal-UX installer
- MJ_Organize integration handoff

### Independent review

The review found and corrected two pre-QA issues:

1. the first dashboard layout assumed approximately 60 columns and could wrap in narrow panes; dev.4 now adapts panel and label width down to compact terminals
2. interrupted dashboard execution could leave small `/tmp/mj-top-*` files; `mj-top` now executes inside a subshell with a local cleanup trap so parent-shell state is not modified

The review also confirmed that `mj-top` does not call `mdfind`, `xattr`, `sips`, `mdls`, `ditto`, or `avmediainfo` directly. Evidence collection remains behind the MJ Native Protocol.

### QA

Deterministic suites:

- M1: 21/21
- M2: 26/26
- M3: 8/8
- M4: 14/14
- M5: 12/12
- M6: 7/7
- QA swarm: 32/32
- RC3 hardening: 32/32
- concurrency: 62/62
- contract audit: 4/4
- NG-M1: 39/39
- NG-M2: 64/64
- stage hardening: 25/25
- dev.4 Registry/Terminal UX: 61/61

**Deterministic total: 407/407.**

Protocol fuzz:

- offsets 0–499: 500/500, 0 failures
- offsets 500–999: 500/500, 0 failures
- **total: 1,000/1,000, 0 failures**

## Registry contract correction

The release specifically asserts:

```json
"requires":{"all":["stat","file","uname"]}
"optionalCapabilities":["sha256","shasum"]
```

and rejects the prior production-zsh representation where multiple capability names could appear as a single whitespace-joined string element.

## Terminal UX safety

- no sudo
- no Homebrew/package manager
- no background daemon
- no live polling in dev.4
- no system man-page or MANPATH modification
- no arbitrary shell API
- no direct evidence-tool calls from `mj-top`
- `NO_COLOR`, ASCII, and non-TTY/plain fallbacks are present
- terminal presentation code is not included in `dist/mograph-jailed.zsh`

## Build parity

Two independent modular-source builds produced the same production CLI SHA-256:

`cf9cf57269b684ffa31d23903c254632881fff8497b79f349009f1c35ac1cdf5`

## Remaining Mac gates

Portable QA cannot certify Terminal.app rendering or JXA execution. See `tests/DEV4_MAC_QUALIFICATION.md` for:

- production-zsh Registry array verification
- `mj-man` rendering/search
- `mj-top` modern/ascii/plain rendering
- Ctrl-C cleanup
- TCC/Automation-prompt check
- NG-M2 `mdfind`/`xattr`/`sips` qualification
