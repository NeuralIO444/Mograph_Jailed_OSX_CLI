# MographJailed 0.3.0-dev.1 — Release Manifest

## Identity

- CLI: `0.3.0-dev.1`
- Protocol: `1`
- Capability Registry: `2`
- Standard Library: `1.0`
- Terminal UX: `1`
- Release class: Standard Library 1.0 development milestone

## Public protocol surface

20 allowlisted operations. No command was added or removed.

`media.timing` keeps its existing command name but is now implemented and reports:

- `cost`: `BOUNDED_MEDIA_PROBE`
- `authority`: `NORMALIZED_NATIVE_MEDIA`
- `executionScope`: `LOCAL_ONLY`
- `interactiveSafe`: `false`
- required capabilities: `avmediainfo`, `awk`, `df`, `uname`

## Standard Library modules

- `LocalFS` — production available when native filesystem classification primitives are available.
- `NativeDB` — internal SQLite runtime/JSON/FTS5 capability layer; `publicSql=false`.
- `MediaProbe` — bounded normalized native media timing.
- `ImageKit` — qualified `sips` image primitives behind a reusable library boundary.
- `FrameKit` — `LAB_GATED` in this release.

## Runtime dependencies

Production remains stock-macOS-only. New qualified production candidates are:

- `/usr/bin/sqlite3`
- `/usr/bin/jq` (capability/reporting; not required by normal runtime operations)
- `/usr/bin/avmediainfo`

Existing stock macOS dependencies remain documented in `DEPENDENCY_AUDIT.md`.

Explicitly not required: Python, Ruby, Perl, Node/npm, FFmpeg, Homebrew, MacPorts, Docker, or administrator-installed packages.

## QA

- deterministic: 475/475
- protocol fuzz: 1,000/1,000, 0 failures
- deterministic production CLI SHA-256: `e563f74e094988e01c3c5bb47149f7f68a7fc2b496a273eee8a653adfc09752c`

## Target-Mac promotion gate

Run `tests/run_stdlib_1_target_mac.zsh` from the extracted release. It is local-only and performs no network mutation, sudo, installation, or developer-tool execution.
