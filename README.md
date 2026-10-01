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

You get one JSON envelope on stdout. `system.describe` lists all 30 allowlisted operations plus the capability registry. See `PROTOCOL.md` for the request format and `docs/man/` for the terminal UX (`mj-man`, `mj-top`, `mj-observe-dash`).

## Production rules

- No sudo. No package manager. No Xcode. No background daemon.
- No public arbitrary-shell or arbitrary-SQL operation; product code submits allowlisted structured requests.
- Standard Library work is local-only by default; network and unknown storage fail closed.
- Source media is never mutated; derivatives never overwrite.

## Runtime requirements

- stock macOS with `/bin/zsh`
- no Python, Node/npm, Homebrew, FFmpeg, OpenCV, Xcode/CLT, daemon, local server, cloud API, or admin installation required
- optional Apple-native capabilities are probed and fail closed
- After Effects invocation uses `/bin/zsh -f` to avoid user shell-startup state
- Standard Library 1.0 is local-first; network volumes are outside automatic execution/mutation paths

Ruby/Perl, Xcode tools, Python, Node, and GNU utilities may be used by isolated development/QA work when available, but they are not production runtime dependencies.

## Current development line

`0.3.0` is the qualified production baseline. The current line is the **Tier 0 Observer**: read-only After Effects project intelligence. It can look at everything and change nothing — unless you tell it to, and then it still won't overwrite.

- **`project.ingest`** — validate an `MJ_PROJECT_SCRAPE_1` receipt from the After Effects scraper and summarize it: comps, layers, expressions, effects, fonts, footage, missing/unlinked footage.
- **`expression.lint`** — static analysis over scraped expressions: broken layer/effect references, `sampleImage()` in loops, hard-coded paths, and more.
- **`plugin.audit`** — enumerate and SHA-256 hash an After Effects Plug-ins directory. Reads only.
- **`project.snapshot`** — hash an `.aep` and save a timestamped, hash-suffixed versioned copy (APFS clone when available); skips unchanged projects; refuses to overwrite.
- **AE scraper** — `integrations/after-effects/MographJailed_ProjectScraper.jsx`: ES3 project traversal that writes one user-selected JSON receipt and never modifies the open project. A static guard (`scripts/check-scraper-readonly.sh`) proves it.
- **Watcher** — an optional user-level LaunchAgent that fires `project.snapshot` on `.aep` changes. No sudo, no network.
- **Dashboard** — `tools/mj-observe-dash.zsh`: a btop-style live terminal view of snapshots, project vitals, lint findings, and watcher state. Strictly read-only.

Protocol v1 is preserved and the public surface grows additively from 23 to 27 allowlisted operations. See `docs/TIER0_OBSERVER.md` and `docs/MJ_PROJECT_SCRAPE_1.md`.

Frame-sequence tools (Power CLI Phases 5–6, see `docs/PLAN_AE_C4D_POWER_CLI.md`) add three more operations (30 total) over a folder of rendered PNG frames:

- **`loop.seams`** — rank the best start/end frames for a seamless loop.
- **`golden.record`** / **`golden.check`** — record key-frame hashes and signatures once, then flag frames whose look changed after a plugin, Redshift or macOS update.

The Standard Library 1.0 line (`media.frame`, `media.timing`, ImageKit, FrameKit) remains intact underneath; `0.3.0-dev.3` qualified the `image.stats` / `image.compare` slice.

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
- `docs/releases/0.3.0-dev.2/QA_REPORT.md`
- `docs/releases/0.3.0-dev.2/RELEASE_MANIFEST.md`
- `tests/FRAMEKIT_M2_MAC_QUALIFICATION.md`
- `docs/integrations/MJ_Organize_Native_Handoff.md`
- `tests/STDLIB_1_MAC_QUALIFICATION.md`
