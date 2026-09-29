# Tier 0 — Observer

Tier 0 is the "look at everything, change nothing" layer of MographJailed.
It exists so a noob can install the tool on a production machine and the
worst possible outcome is some JSON files appearing in a receipts folder.

## The three tiers

- **Tier 0 — Observe.** Read-only inspection: scrape projects, lint
  expressions, audit plugins, snapshot `.aep` files. These are the ONLY
  operations the watcher may ever trigger.
- **Tier 1 — Generate.** User-invoked creation: JSON inversion builds new
  projects, the aerender queue renders, contact sheets assemble. Creates new
  files only, never overwrites, never modifies a project in place, and is
  NEVER triggered by the watcher — only by the user explicitly hitting go.
- **Tier 2 — Doesn't exist.** In-place project mutation, network access,
  sudo, arbitrary shell/SQL. There is no code path for these, so there is
  nothing for a bug to accidentally invoke.

## Tier 0 pieces

### Project scraper (After Effects side)

`integrations/after-effects/MographJailed_ProjectScraper.jsx`

Run via **File > Scripts > Run Script File** in After Effects. Walks the
open project and emits a `MJ_PROJECT_SCRAPE_1` JSON document (schema:
`docs/MJ_PROJECT_SCRAPE_1.md`): comps, layers, keyframed/expression
properties, effects, fonts, footage — with enforced bounds (200 comps max,
500 layers/comp max, expressions truncated to 2000 chars, ~5 MB total cap).

Strictly read-only. A CI guard (`scripts/check-scraper-readonly.sh`)
rejects any AE DOM mutation call in the file; the scraper's only file
write is the JSON document itself, to a folder the user picks.

### `project.ingest` (CLI)

Validates a scraper JSON document against the `MJ_PROJECT_SCRAPE_1`
schema and produces a summary (comp/layer/expression/font/footage
counts). The trust boundary between the AE side and the CLI side:
malformed or hostile JSON fails closed here.

### `expression.lint` (CLI)

Static analysis over the expressions captured in a scrape — the
spell-checker for AE expressions. Flags broken layer/property
references, suspicious constructs, and known performance traps.
Reports; never fixes.

### `plugin.audit` (CLI)

Enumerates installed plugins (AE Plug-ins folders) and the registered
effect list, hashes them, and diffs against a studio-standard list.
Answers "what's on this machine, and what's missing for this project"
without installing or touching anything.

### `project.snapshot` (CLI)

No-overwrite snapshot of a `.aep` file into the versions dir, with
hash-skip idempotency (unchanged files are skipped, not re-copied).
This is the operation the watcher fires — the only watcher-triggered
command in the system.

### Watcher (macOS side)

`watcher/com.neuralio.mograph-jailed.watcher.plist` (template),
`watcher/watch-fire.zsh` (template), installed by
`tools/watch-install.zsh`, removed by `tools/watch-uninstall.zsh`.

A user-profile `launchd` agent: on `.aep` changes under the watch dir,
it runs a one-shot scan and fires one `project.snapshot` request per
`.aep` found (max 2 levels deep). It then exits — there is no
always-on process.

## Installing the watcher

```zsh
./tools/watch-install.zsh <watch-dir> <versions-dir>
```

Example:

```zsh
./tools/watch-install.zsh "$HOME/Movies/AE Projects" "$HOME/Documents/MographJailed/versions"
```

The installer:

1. Validates the CLI, the watch dir (must exist and be readable), and
   creates the versions dir if missing.
2. Prints exactly what it will do and asks `Proceed? [y/N]`
   (pass `--yes` to skip the prompt for scripted installs).
3. Renders the plist + fire script templates into
   `<versions-dir>/.watcher/` with real paths substituted.
4. Copies the plist into **your own** `~/Library/LaunchAgents`
   (never `/Library`, never sudo).
5. Loads it for your user via
   `launchctl bootstrap gui/$(id -u) <plist>`
   (falls back to `launchctl load`). If `launchctl` fails — e.g. MDM
   blocks background items — it prints the error plainly and exits
   nonzero; nothing is left half-installed.

## Uninstalling the watcher

```zsh
./tools/watch-uninstall.zsh
```

Unloads the agent (`launchctl bootout`, `unload -w` fallback) and
removes the plist. **Never touches the versions dir** — your snapshots
and logs stay put.

## What the LaunchAgent can and cannot do

Can:

- Run as you, with only your permissions, when files under the watch
  dir change (throttled to one fire per 30 s).
- Execute the rendered fire script, which builds `MOGRAPHJAILED_REQUEST`
  files and calls the CLI with `command=project.snapshot`.
- Append to `<versions-dir>/watcher.log`.

Cannot:

- Run as root, touch the system, or use the network (it never does —
  there is no network code anywhere in Tier 0).
- Modify, save, or delete any `.aep` or project content.
- Trigger renders, builds, or any Tier 1 operation — the fire script
  only ever emits `project.snapshot`.
- Hide from you (see below).

## Verifying it's running

```zsh
launchctl print gui/$(id -u)/com.neuralio.mograph-jailed.watcher
tail -f ~/Documents/MographJailed/versions/watcher.log
```

## How macOS surfaces it

Modern macOS notifies you when a background item is added and lists it
under **System Settings > General > Login Items** ("Allow in the
Background"). The watcher appears there as `com.neuralio.mograph-jailed.watcher`
and can be disabled with one toggle — no terminal needed. Uninstalling
via `tools/watch-uninstall.zsh` removes it completely.

## Safety guarantees

- **Read-only CI guard.** `scripts/check-scraper-readonly.sh` greps the
  scraper JSX for every AE DOM mutation pattern (`save`, `remove`,
  `add`, `replace`, `setValue`, `setValueAtTime`, `addKey`,
  `removeKey`, `duplicate`, project `close`, undo groups,
  `app.executeCommand`) and fails the build if any appear.
  Read-only is proven, not claimed.
- **No-overwrite snapshots.** `project.snapshot` never overwrites an
  existing snapshot; outputs are uniquely named.
- **Hash-skip idempotency.** Unchanged `.aep` files are detected by hash
  and skipped — the watcher firing repeatedly costs nothing and
  changes nothing.
- **Receipts for everything.** Every watcher fire appends one line per
  file to `watcher.log`; every CLI request gets a structured response.
  If anything ever looks wrong, the paper trail shows exactly what ran.
- **One-delete uninstall.** Removing the watcher is deleting one plist;
  no residue, no orphaned processes.

## Observer dashboard

`tools/mj-observe-dash.zsh` is a btop-style live terminal view over Tier 0
data. It is itself Tier 0: strictly read-only, it never modifies projects
and never writes outside temp request files it deletes immediately.

```sh
tools/mj-observe-dash.zsh --versions ~/AE_Versions --receipts ~/AE_Receipts
```

Panels: project snapshots (per-project counts, size bars, sparklines),
project vitals (from the newest scrape receipt via `project.ingest`),
expression lint findings (via `expression.lint`), and watcher status
(launchd state + log tail). Keys: `q` quit, `r` refresh; `--once`
renders a single frame for scripting; `--interval N` sets the refresh
period (default 5s).
