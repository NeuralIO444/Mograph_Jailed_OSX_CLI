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

## mj-observe-dash

btop-style live dashboard for the Tier 0 Observer.

```text
tools/mj-observe-dash.zsh --versions ~/AE_Versions --receipts ~/AE_Receipts
```

Shows project snapshot counts and sizes with sparklines, project vitals from the newest scrape receipt, expression lint findings, and watcher launchd state. Keys: `q` quit, `r` refresh. `--once` renders a single frame for scripting; `--interval N` sets the refresh period (default 5s).

Strictly read-only: the dashboard only invokes `project.ingest` and `expression.lint`, and never modifies After Effects projects or snapshot history.

## Presentation fallback

- modern: ANSI color + Unicode box drawing
- ascii: ANSI color + ASCII borders
- plain: no color + ASCII output

Set `NO_COLOR=1` to disable ANSI colors. Set `MJ_ASCII=1` to force ASCII borders.

The terminal UI is optional developer/qualification tooling. It is not required by bundled MJ applications.

## mj — power-user front end

`scripts/shell/mj-cli.zsh` (installed by `install-terminal-ux.sh`) adds one command:

```text
mj ops                                    list operations; required arguments marked *
mj loop.seams path=~/renders/hero minFrames=24
mj golden.check path=~/renders/hero input=~/golden/hero_v1.golden.json
mj recipe recipes/render-qa.mjrecipe frames=~/renders/hero golden=~/golden/hero_v1.golden.json
```

Tab completion offers operation names, then that operation's argument names, then file paths for values. Argument lists come from `system.describe`, so completion never drifts from the runtime.

Recipes are data, not scripts: one `operation name=value` per line, `#` comments, `{{name}}` placeholders filled from the command line. Every step's operation and argument names are checked against the registry before the first step runs, shell syntax is never evaluated, and the recipe stops at the first failing step.

## Audit log

Create the directory once to turn it on:

```text
mkdir -p ~/Library/Logs/MographJailed
```

From then on every request appends one line to `audit.jsonl` there: time, command, arguments, exit code, and the SHA-256 of the previous line. Check the chain with:

```text
mj audit.verify path=$HOME/Library/Logs/MographJailed/audit.jsonl
```

An edited, inserted or deleted line breaks the chain at that point. Keep a copy of the reported `headHash` elsewhere to also detect a truncated tail. Remove the directory to turn logging off.
