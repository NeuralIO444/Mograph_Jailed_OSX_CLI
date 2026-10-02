# MographJailed

Zero-install native macOS capability and evidence layer for MJ applications.

Development source is modular zsh. Deployment bundles deterministically to one `dist/mograph-jailed.zsh` runtime. Product code submits allowlisted structured requests; there is no public arbitrary-shell or arbitrary-SQL command.

## Install — designers (easy)

Don't use the terminal much? Run **one command**, answer a few plain-English questions, done:

```sh
curl -fsSL https://raw.githubusercontent.com/NeuralIO444/Mograph_Jailed_OSX_CLI/main/tools/install-designer.zsh | zsh
```

It downloads MographJailed into `~/Documents/MographJailed`, checks that it runs, and offers to add the help pages (`mj-man`) and the automatic project-version watcher. No git, no sudo, no admin password. Full walkthrough: [Designer Install](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/wiki/Designer-Install).

## Install — developers (quickstart)

```sh
git clone https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI.git
cd Mograph_Jailed_OSX_CLI
```

Send a request file at the bundled runtime (stock `/bin/zsh` on macOS; the portable surface also runs on Linux):

```sh
printf 'MOGRAPHJAILED_REQUEST 1\nrequestId=hello\ncommand=system.probe\n' > /tmp/mj-request.txt
zsh -f dist/mograph-jailed.zsh --request /tmp/mj-request.txt
```

You get one JSON envelope on stdout. `system.describe` lists all 56 allowlisted operations plus the capability registry. See `PROTOCOL.md` for the request format and `docs/man/` for the terminal UX (`mj-man`, `mj-top`, `mj-observe-dash`).

## Production rules

- No sudo. No package manager. No Xcode. No always-on daemon (the optional watcher is a user-level LaunchAgent: `mj watch off` removes it).
- No public arbitrary-shell or arbitrary-SQL operation; product code submits allowlisted structured requests.
- Standard Library work is local-only by default; network and unknown storage fail closed.
- Source media is never mutated; derivatives never overwrite.

## Runtime requirements

- stock macOS (Sequoia or newer) with `/bin/zsh`, Apple Silicon or Intel
- no Node/npm, Homebrew, FFmpeg, OpenCV, daemon, local server, cloud API, or admin installation required
- **`/usr/bin/python3` is required for the Project observer, Frame tools, Protect work, Search/audits and Host rendering operations** (everything added since 0.3). On a Mac without the Xcode Command Line Tools, that path is a stub that offers to install them, so on a locked-down Mac confirm `/usr/bin/python3 --version` works before relying on those operations. Python is used with its standard library only (`sqlite3`, `json`, `hashlib`, `subprocess`); no packages are installed. `system.doctor` and `system.describe` report which operations are available.
- `jq` (shipped with macOS 15 and later at `/usr/bin/jq`) is used by `mj`, the watcher and frame extraction
- the original asset, image, media, storage and package operations need only stock macOS tools
- optional Apple-native capabilities are probed and fail closed
- After Effects invocation uses `/bin/zsh -f` to avoid user shell-startup state
- Standard Library 1.0 is local-first; network volumes are outside automatic execution/mutation paths
- Rendering needs your own licensed After Effects and/or Cinema 4D 2024 or newer; nothing here activates or configures licences

Ruby/Perl, Xcode tools, Node, and GNU utilities may be used by isolated development/QA work when available, but they are not production runtime dependencies.

## What it is

A local, zero-daemon toolkit for motion-design pipelines on managed Macs. It looks at After Effects and Cinema 4D work, renders it, checks it, searches it and packages it — and never edits your projects. Everything is an allowlisted operation with a structured request and a JSON response. **56 operations**, no network, no sudo, and no background process unless you turn on the optional watcher (a user-level LaunchAgent you can remove with one command).

| Area | Operations | What you get |
|---|---|---|
| **Hosts and rendering** | `host.detect` `ae.render` `c4d.render` | Finds After Effects / Cinema 4D 2024+ (Redshift, Metal GPU). Renders a comp or scene to a new PNG sequence with a receipt: frames vs expected, first/last-frame hashes, source-unchanged proof. One render at a time, hard timeout, fail-fast on an unconfigured C4D licence. |
| **Frame tools** | `loop.seams` `golden.record` `golden.check` | Rank the best loop points in a render. Record key frames once, then catch a look changing after a plugin, Redshift or macOS update. |
| **Project observer** | `project.ingest` `expression.lint` `plugin.audit` `project.snapshot` | Read-only project intelligence from an AE scrape: comps, layers, expressions, effects, fonts, footage; lint; plug-in hashing; versioned snapshots. |
| **Protect work** | `project.restore` `deps.graph` `handoff.package` `audit.verify` | Restore any snapshot as a new verified copy. See what breaks if a file goes missing. Build a client handoff folder with a SHA-256 manifest. Tamper-evident request log. |
| **Search and audits** | `index.add` `index.search` `index.verify` `trace.asset` `audit.plugins` | One local index of everything you scrape. Full-text search; exact nested comp path (`Main > Mid > Inner`) to any missing asset or font; every project using a given effect `matchName`; full plugin inventory. |
| **Presets** | `preset.add` `preset.get` | Versioned, hash-addressed library for `.ffx`, templates, expressions, `.c4d`, Redshift materials. |
| **Asset and media intelligence** | `file.*` `asset.*` `image.*` `media.*` `storage.*` `volume.*` `search.candidate` `package.create` … | The 0.2/0.3 foundation: identity, provenance, images, native media timing and frame extraction. |

## Quick tour

```sh
mj                                                 # launch screen: hosts, library, audit log, renders
mj ui                                              # live dashboard (q quits, 1-4 switch tabs)
mj ops                                             # every operation; required args marked *
mj host.detect                                     # what is installed, ready to render
mj ae.render path=/work/hero.aep target="Main" output=/work/renders label=hero range=0-119
mj last                                            # newest render receipt
mj notify on                                       # macOS notification when a render / check / recipe finishes
mj status                                          # one line: live progress or last render
mj loop.seams path=/work/renders/hero.<stamp> minFrames=48
mj golden.check path=/work/renders/hero.<stamp> input=/work/golden/hero_master.golden.json
mj index.add path=/work/receipts                   # index scrapes, snapshots, golden records
mj trace.asset format=missing                      # exact nested path to every missing asset
mj audit.plugins target=S_Glow                     # which projects use this effect?
mj recipe recipes/render-qa.mjrecipe frames=... golden=...
```

`mj` has tab completion and is installed by `scripts/shell/install-terminal-ux.sh`. Local help: `mj-man` (topics: `mj`, `render`, `frames`, `audit`, `library`, `commands`, `protocol`, `safety`). Terminal UI: `mj` (launch screen) and `mj ui` (dashboard); the Tier 0 observer view is `tools/mj-observe-dash.zsh`.

## Everyday commands

```sh
mj snapshot "Spring Promo"        # save a verified version of a project
mj lint last                      # what is wrong with my expressions, and how to fix it
mj health last --record           # 0-100 project health, trended over time
mj diff last                      # what changed between my two newest scrapes
mj explain last                   # any receipt, in plain language
mj watch on                       # version my .aep files automatically
mj doctor                         # is this Mac ready?
mj config set versions_dir ~/AE_Versions    # set a folder once; every tool remembers it
```

Every one of these is a thin wrapper over an operation and prints sentences, not JSON. The operations underneath (`project.diff`, `project.health`, `expression.lint` with teaching text, …) stay fully scriptable, and `--request -` reads a request from standard input.

## Guides

New here? Follow the [tutorials](docs/guides/README.md): first hour, automatic versions, find and fix problems, render and verify, Cinema 4D into After Effects, client handoff. Task lookups are in the [how-to page](docs/guides/howto.md).

**New in 0.4.0-dev.3:** `mj check` (one verdict: expressions, health, fonts, footage), `mj timeline`, `mj space` (find and safely empty After Effects, Adobe and Redshift caches), `mj qc` (a render against a delivery spec, loudness included), `mj extract` (comps into their own project) and `mj conform` (studio naming, labels, folders and expression fixes). The last two run in After Effects on a verified copy and never touch your original. Cinema 4D scenes get `mj scene` (inspect and lint), `mj bridge` (scene against an After Effects project) and `.c4d` snapshots; `mj batch` runs a recipe over a folder.

## Trust model

- **Allowlisted operations only.** No `shell.execute`, no `db.query`; every database statement is fixed text with bound parameters, and a recipe is data that is validated before it runs.
- **Sources are never changed.** Outputs are always new files and folders; nothing is overwritten, and receipts prove the source hash did not change.
- **Local only.** Network volumes are classified without being touched and are never opened, copied or indexed. Hosts are found only in `/Applications`; a request cannot name a binary.
- **Fail closed and honest.** Missing tools, unsupported hosts and unconfigured licences return a clear error code, not a guess. Host runs have closed stdin, a hard timeout and a whole-process-group kill.
- **Tamper-evident.** Turn on the audit log (`mkdir -p ~/Library/Logs/MographJailed`) and every request is chained by SHA-256; `audit.verify` finds edits and deletions.
- **Verified downloads.** The installer prints the download's SHA-256, checks every file against a shipped `SHA256SUMS`, and can pin a release tag and hash.
- **Unattended hooks are fenced.** An optional `post_snapshot_hook` runs only if it is an executable you own that nobody else can write to, directly (no shell), with a time limit, and can never harm a snapshot.
- **Stock macOS.** Runs on `/bin/zsh` plus the system `python3` (only for the Power CLI operations). See `DEPENDENCY_AUDIT.md`.

Protocol v1 is preserved and the public surface has grown additively: 20 → 23 → 27 → 46 → 49 → 56 operations. The full request and response contracts are in `PROTOCOL.md`; the roadmap is `docs/PLAN_AE_C4D_POWER_CLI.md` and the GitHub milestones. Scraper schema: `docs/MJ_PROJECT_SCRAPE_1.md`; observer tiers: `docs/TIER0_OBSERVER.md`.

## Existing asset intelligence

The 0.2 line remains intact:

- `asset.manifest`
- `asset.verify`
- `search.candidate`
- `file.provenance`
- `image.inspect`
- `image.derivative`
- `storage.preflight`

These are evidence providers, not workflow automation. Search never relinks automatically, provenance exposes xattr names only, derivatives never overwrite source media, and storage writability remains advisory.

## Performance boundary

After Effects `system.callSystem()` is synchronous. Consumers should respect Capability Registry metadata. `file.hash`, Spotlight search, derivative creation, package creation, `media.timing`, and `media.frame` are explicit/non-interactive operations. Routine UI paths should favor fast inspection operations.

## Standard Library policy

The Standard Library is intentionally narrow. It wraps approved macOS primitives behind stable MJ contracts so consumer tools do not parse native command output or depend on implementation details directly.

```text
MJ_Organize / MJ_AE_Looper
        ↓
MJ Native Protocol v1
        ↓
MJ Standard Library 1.0
        ↓
fixed stock-macOS adapters
```

No generic `shell.execute`, `db.query`, or similar escape hatch is introduced.

## Key documents

- `PROJECT_PLAN.md`
- `ARCHITECTURE.md`
- `PROTOCOL.md`
- `SECURITY.md`
- `CAPABILITY_REGISTRY.md`
- `DEPENDENCY_AUDIT.md`
- `docs/PLAN_AE_C4D_POWER_CLI.md`
- `docs/releases/0.3.0-dev.2/QA_REPORT.md`
- `docs/releases/0.3.0-dev.2/RELEASE_MANIFEST.md`
- `tests/FRAMEKIT_M2_MAC_QUALIFICATION.md`
- `docs/integrations/MJ_Organize_Native_Handoff.md`
- `tests/STDLIB_1_MAC_QUALIFICATION.md`
