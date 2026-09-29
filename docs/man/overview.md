# MographJailed

MographJailed is the zero-install native macOS capability layer for MJ tools.

Current development line: 0.3.0-dev.2 FrameKit qualification candidate
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
mj            go to ~/Documents/MographJailed
mj-open       open MographJailed in Finder
```

## Production rules

No sudo. No package manager. No Xcode requirement. No background daemon. No arbitrary shell or SQL command API. Source media is not mutated by Native. Standard Library automatic work is local-only by default.

Use `mj-man commands` for the public operation list.
