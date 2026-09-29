# Terminal UX

MographJailed provides two local terminal surfaces that consume the same audited protocol as other MJ tools.

## mj-man

Polished offline help generated from local Markdown topics.

```text
mj-man
mj-man list
mj-man commands
mj-man protocol
mj-man safety
mj-man looper
mj-man organize
mj-man terminal
mj-man troubleshooting
mj-man recovery
```

Search inside help with `/` and exit with `q`.

## mj-top

Snapshot-only read-only dashboard.

```text
mj-top
mj-top --plain
mj-top --ascii
```

The dashboard consumes `system.doctor`, `system.describe`, `runtime.verify`, and `storage.preflight` through MographJailed. It does not call media/filesystem evidence utilities directly.

## Presentation fallback

- modern: ANSI color + Unicode box drawing
- ascii: ANSI color + ASCII borders
- plain: no color + ASCII output

Set `NO_COLOR=1` to disable ANSI colors. Set `MJ_ASCII=1` to force ASCII borders.

The terminal UI is optional developer/qualification tooling. It is not required by bundled MJ applications.
