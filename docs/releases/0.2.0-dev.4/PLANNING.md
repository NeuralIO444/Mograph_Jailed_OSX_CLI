# MographJailed 0.2.0-dev.4 — Planning Gate

## Scope

This development increment is intentionally limited to:

1. Correct Capability Registry 2.0 dependency-array serialization under production zsh.
2. Add polished project-local `mj-man` v2 help rendering.
3. Add snapshot-only `mj-top` runtime/capability dashboard.
4. Add terminal presentation fallback for ANSI/Unicode, ASCII, and plain output.
5. Add an MJ_Organize integration handoff.
6. Preserve the 20-operation Protocol v1 command surface and all NG-M2 behavior.

## Non-goals

- no live/polling dashboard mode
- no daemon or LaunchAgent
- no process-control UI
- no new media-analysis operation
- no new destructive operation
- no system man-page installation or MANPATH modification
- no external package/runtime dependency

## Architecture

The terminal UX is a protocol consumer, not part of the CLI runtime bundle:

```text
mj-man / mj-top
        ↓
project-local shell/UI layer
        ↓
MJ Native Protocol v1
        ↓
dist/mograph-jailed.zsh
```

The dashboard may use stock macOS `osascript` only to parse/render protocol JSON. It must not bypass MographJailed to call evidence utilities directly.

## Promotion metrics

- all legacy deterministic tests pass
- dev.4-specific tests pass
- 1,000-case protocol fuzz passes
- source-to-dist parity passes
- no new downloaded runtime dependency
- clean extraction/rebuild reproduces the production CLI hash
- target-Mac checklist covers real zsh Registry output and terminal UX
