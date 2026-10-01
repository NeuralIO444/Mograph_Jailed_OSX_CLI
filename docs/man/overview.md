# MographJailed

MographJailed is the zero-install native macOS capability layer for MJ tools.

Current development line: Power CLI (After Effects + Cinema 4D), 44 operations
Protocol: MOGRAPHJAILED v1
Capability Registry: v2
Standard Library: 1.0

## What it does

MographJailed exposes approved named operations for environment inspection, files, assets, images, media, storage, temporary workspaces, reports, and packaging.

Standard Library 1.0 provides LocalFS, NativeDB, MediaProbe, ImageKit, and the dev.2 FrameKit candidate. `media.frame` is local-only and remains target-Mac/AE qualification-gated before product promotion.

It is designed for managed production Macs and uses stock macOS capabilities only.

## Quick commands

```text
mj-status     concise environment status
mj-doctor     full machine-readable diagnostic response
mj-help       local Terminal quick-start
mj-man        polished local help system
mj-top        snapshot runtime/capability dashboard
mj            go to ~/Documents/MographJailed (with arguments: run an operation)
mj-open       open MographJailed in Finder
```

## Production rules

No sudo. No package manager. No Xcode requirement. No background daemon. No arbitrary shell or SQL command API. Source media is not mutated by Native. Standard Library automatic work is local-only by default.

## Power CLI

`mj <operation> name=value ...` runs any operation, with tab completion. `mj ops` lists them all. `mj recipe <file>` runs a checked multi-step recipe. `mj last` and `mj open-last` show and open the newest render.

Topics: `mj-man mj`, `mj-man render`, `mj-man frames`, `mj-man audit`, `mj-man library`.

Use `mj-man commands` for the public operation list.
