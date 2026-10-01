# Changelog

## 0.4.0-dev.1 — 2026-10-01

Power CLI for After Effects and Cinema 4D. Protocol v1 preserved; the public surface grew additively from 27 to 44 operations. The sections below describe the pieces.

### Fixes from the 2026-09-30 review

- `project.snapshot` (#7, #8, #9): the copy is staged, its SHA-256 and the source's are re-checked, and a mismatch keeps nothing (`SNAPSHOT_UNSTABLE`); publish is by hard link so an existing snapshot is never overwritten; the project stem is case-insensitive so `.AEP` projects dedupe and name their latest pointer consistently. Receipts now record `copyVerified` and `sourceStableDuringCopy`.
- `sourceUnchanged` (#20) is now measured (size and modification time before and after) in `image.stats`, `image.compare`, `project.ingest`, `expression.lint`, `plugin.audit`, `project.snapshot` and the newer frame, protect and library operations, instead of a literal `true`. `preset.get` no longer reports it (its source is the hash-verified store).
- Dashboard (#10): the observer dashboard reads the unwrapped `*.latest.json` pointer, so project paths show.
- Version (#12): the runtime and `VERSION` now report `0.4.0-dev.1`; `tests/run_contract_audit.sh` fails if the constant, `VERSION` and the newest changelog entry disagree.

### Phase 7 (live progress, notifications, status)

- Renders write `<store>/render-progress.json` (frames counted from finished PNGs, total from `range`, fps, ETA) about twice a second; removed when the render ends. The dashboard shows an animated bar and sets the Terminal title to `MJ · rendering N%`.
- `mj notify on|off|test|status`: opt-in native notifications for renders, golden checks, recipes and operations running 10 s or more; text passed to osascript as arguments only.
- `mj status` (and `--swiftbar`): one-line status from local files; optional `integrations/swiftbar/mj.10s.sh`. No menu-bar process by design.
- Fixed: a successful `mj recipe` returned non-zero when notifications were off (caught by the new tests).
- Tests: `run_host.sh` 39, `run_mj_cli.sh` 38, `run_ui.sh` 52.

### Terminal experience

- `mj` (bare) is now a launch screen: animated gradient wordmark and a live boot checklist (runtime, After Effects, Cinema 4D/Redshift, GPU, library, audit log, last render). `mj ui` is a full-screen dashboard with Overview / Renders / Library / Audit tabs. `mj cd` replaces the old bare-`mj` go-to-folder behavior.
- `scripts/terminal/mj_ui.py`: read-only, stdlib-only; truecolor → 256-color → plain/ASCII fallbacks (`NO_COLOR`, `MJ_PLAIN`, `MJ_ASCII`, `MJ_NO_ANIM`), terminal always restored on exit, `--once`/`--plain`/`--width` for scripting.
- Runtime: `<store>/renders.jsonl` render history; `index.verify` now reports `projects`.
- Added `tests/run_ui.sh` (41 checks, including real pseudo-terminal sessions).

### Project audit queries (Modules 1–3 fold-in)

- Added `trace.asset` and `audit.plugins` (operations 43–44) over new normalized store tables (schema v2: projects, compositions, layers, assets, fonts, plugins) with in-place v1 migration.
- Scraper (`MJ_PROJECT_SCRAPE_1`, additive optional fields): layer `sourceId`, text-layer `font`, footage `id`; read-only guard still passes.
- Newest scrape per project path wins; older receipts never replace newer data.
- AE client: `traceAsset()`, `auditPlugins()`. Added `tests/run_audit_queries.sh` (29 checks).

### Power CLI Phases 0–1 (hosts and rendering)

- Added `host.detect`, `ae.render`, `c4d.render` (operations 40–42) and argument names `range`, `timeoutSeconds`.
- Guarded host runner: closed stdin, own process group, streamed log, hard timeout, licence-prompt detection, single-render lock with stale-lock reclaim.
- Python environment hardening: `PYTHONPATH`/`PYTHONHOME`/`PYTHONSTARTUP` cleared, user site and bytecode disabled for every embedded script.
- `mj last`, `mj open-last`; test bundle only: `MJ_TEST_APPS_DIR` points host discovery at a stub `/Applications`.
- Added `tests/run_host.sh` (31 checks, stub hosts). Contract audit now accepts digits in operation names (`c4d.render`).
- Observed on the target Mac: `c4dpy` blocks on an interactive licence prompt until C4D licensing is configured once by hand.

### Power CLI Phase 9 (search and recall)

- Added `index.add`, `index.search`, `index.verify`, `preset.add`, `preset.get` (operations 35–39) and argument name `version`.
- MJ-owned store (SL-M4): fixed-schema SQLite + FTS5 via Python's stdlib `sqlite3` with bound parameters only; migrations by `user_version`; content-addressed preset blobs.
- AE client: `indexAdd()`, `indexSearch()`, `indexVerify()`, `presetAdd()`, `presetGet()`.
- Added `tests/run_library.sh` (31 checks).

### Power CLI Phase 8 (protect work)

- Added `project.restore`, `deps.graph`, `handoff.package` (operations 32–34).
- Footage from scrapes is classified local/network/unknown from the mount table; only local footage is ever stat'ed or copied.
- AE client: `projectRestore()`, `depsGraph()`, `handoffPackage()`.
- Added `tests/run_protect.sh` (31 checks).

### Power CLI Phases 8 (audit) and 10 (shell)

- Added opt-in hash-chained audit log (`~/Library/Logs/MographJailed/audit.jsonl` when the directory exists; `MJ_AUDIT_DIR` overrides) and `audit.verify` (operation 31).
- `system.describe` operation descriptors now publish `args.allowed` / `args.required` from the validator's own schema table (`request_schema_for`).
- Added `mj` front end (`scripts/shell/mj-cli.zsh`): single operations, `mj ops`, zsh completion, and validated data-only recipes (`recipes/render-qa.mjrecipe`).
- Added `tests/run_audit.sh` (17 checks) and `tests/run_mj_cli.sh` (17 checks).

### Power CLI Phases 5–6

- Added `loop.seams`, `golden.record`, `golden.check` (operations 28–30) and argument names `minFrames`, `threshold`. Protocol v1 preserved; no existing schema changed.
- ImageStats signature engine moved into one shared Python block; PNG decoder now accepts 16-bit RGB/RGBA (common for C4D renders).
- Frame operations downscale through `sips` when present (48 × 1080p frames in ~3 s) and fall back to direct decode otherwise; `python3` is the only hard requirement.
- AE client: `loopSeams()`, `goldenRecord()`, `goldenCheck()`.
- Added `tests/run_frames.sh` (29 checks).

## 0.3.0 — qualified production baseline

Tagged `0.3.0`. Note: the tagged build self-reports `0.3.0-dev.2` (the version constant was not bumped before tagging; fixed going forward by a version-sync test).

## 0.3.0-dev.3

SL-M3 ImageKit analysis: `image.stats` and `image.compare` (see `docs/releases/0.3.0-dev.3/QA_REPORT_SL_M3.md`).

## 0.3.0-dev.2 — 2026-09-22

SL-M2 FrameKit qualification candidate for MJ_AE_Looper.

- Added `src/lib/frame_kit.zsh` with one fixed local-only AVFoundation/JXA frame derivative path.
- Added `media.frame` as the 21st Protocol v1 operation; existing operation schemas remain unchanged.
- Added bounded PNG output, zero time tolerance, preferred-track transform, requested/actual time reporting, no-overwrite staging, and source-identity recheck.
- Refuses network/unknown storage for both source and output parent.
- Added AE client `mediaFrame()` helper and FrameKit metadata to Registry/Tech Report.
- Added portable FrameKit contract/security tests and target-Mac + After Effects child-process qualification harnesses.
- No generic JXA, shell, SQL, Python, Node, FFmpeg, package-manager, sudo, or server capability was added.
- Portable deterministic QA: 515/515; protocol fuzz: 1,000/1,000 with 0 failures.
- Target-Mac/AE qualification remains required before replacing the qualified dev.1 install.

## 0.3.0-dev.1 — 2026-09-22

MJ Standard Library 1.0 foundation release, aimed first at MJ_Organize and MJ_AE_Looper.

- Added reusable `src/lib/` boundaries for LocalFS, NativeDB, MediaProbe, ImageKit, and the Standard Library descriptor.
- Promoted the existing `media.timing` command from fail-closed placeholder to a bounded, normalized `avmediainfo` adapter when native capabilities are present.
- Made `media.timing` explicitly `LOCAL_ONLY`; it blocks network and unknown filesystem classes before probing media.
- Bounded MediaProbe output at the pre-sample header and a 256-line ceiling; the default operation never enumerates the full sample table.
- Added stock SQLite runtime/JSON/FTS5 `:memory:` probes with no public arbitrary-SQL command and no persistent DB creation in this milestone.
- Moved reusable `sips` image-inspection primitives into ImageKit without changing source-mutation policy.
- Added Standard Library metadata to `system.describe` and `report.tech`, plus AE client helpers for library discovery and media timing.
- Added `sqlite3` and `jq` to machine capability reporting; neither introduces a third-party install requirement.
- Preserved Protocol v1 and the existing 20-operation public command surface.
- FrameKit/JXA remains lab-gated pending an After Effects child-process frame-extraction qualification.

## 0.2.0-dev.4.1 — 2026-09-22

Target-Mac qualification hotfix for dev.4.

- Fixed `runtime.verify` under real zsh: `runtime_self_path` now uses `ZSH_ARGZERO` when available because zsh `FUNCTION_ARGZERO` changes `$0` inside shell functions.
- Moved `mj-top` execution into a clean `/bin/zsh -f` worker so Apple Terminal session-exit hooks from the interactive parent shell are not inherited.
- Preserved snapshot-only dashboard behavior, Protocol v1, Capability Registry v2, and the 20-operation public command surface.
- Added dedicated Mac-hotfix regression coverage and retained the full dev.4 terminal/registry suite.
- Portable QA after the fixes: 421/421 deterministic tests and 1,000/1,000 protocol fuzz cases with 0 failures.


## 0.2.0-dev.4 — 2026-09-22

- Corrected Capability Registry 2.0 `requires.all` and `optionalCapabilities` serialization so zsh emits one JSON array element per capability rather than a whitespace-joined scalar.
- Preserved Protocol v1 and the existing 20-operation public command surface.
- Added project-local `mj-man` v2 with Markdown-to-terminal rendering, ANSI styling, plain-output fallback, search through `less`, and new `organize`/`terminal` topics.
- Added snapshot-only `mj-top` runtime/capability/storage/safety dashboard with modern, ASCII, and plain presentation modes.
- Added isolated terminal UX installer; no system man page, MANPATH change, sudo, daemon, or external package is required.
- Added MJ_Organize Native integration handoff.
- Added dev.4 Registry/Terminal QA without placing presentation code in the production CLI bundle.


## 0.2.0-dev.3 — 2026-09-22

Independent NG-M2 QA hardening release. Supersedes dev.2.

- Bound image/package staging directories to protocol + request ID + exact path + effective user + stage prefix before recursive cleanup is permitted.
- Removed direct recursive stage cleanup from image/package modules; missing/tampered ownership proof now fails closed.
- Replaced recursive marker-initialization cleanup with known-file + non-recursive empty-directory cleanup.
- Fixed `image.inspect` false-success behavior: `sips` must positively identify format, width, and height or the target is rejected.
- Applied the same positive image gate before `image.derivative`.
- Reconciled Capability Registry required dependencies with actual helpers/handlers.
- Expanded NG-M2 tests to 64/64 and added 25/25 independent dev.3 hardening tests.
- Full deterministic QA: 346/346; protocol fuzz: 1,000/1,000 with 0 failures.
- Protocol v1 and the 20-operation public command surface remain unchanged.

## 0.2.0-dev.1 — 2026-09-21

NG-M1 Capability Registry 2.0 + Runtime Trust development release.

- Added `system.describe` with per-operation availability, cost, mutation, authority, interactive-safety, network-sensitivity, required, and optional capability metadata.
- Added `runtime.verify` for pinned CLI version, protocol, runtime filename, and optional exact SHA-256 verification.
- Added AE client helpers `describe`, `verifyRuntime`, `can`, and `isInteractiveSafe` with a cached description response.
- Kept Protocol v1 and existing RC3 operation semantics intact.
- Added registry/protocol/router/AE command parity enforcement.
- Added 39 NG-M1 semantic tests and a 1,000-request QA-only protocol fuzz pass.
- Kept `media.timing` explicitly lab-gated rather than parsing undocumented `avmediainfo` text.

## 0.1.0-rc3 — 2026-09-17

Independent architecture/security hardening release.

- Fixed a P1 shell-state defect: helper-function temporary variables were globally scoped and could overwrite caller state. All runtime helper temporaries are now function-local; the defect class has dedicated regression coverage.
- Normalized production environment state (`PATH`, locale, IFS, `COMMAND_MODE`) and removed inherited macOS compatibility, `ditto`/copyfile, Perl, and shell-startup hook variables after startup.
- Hardened zsh startup with `/bin/zsh -f`, `#!/bin/zsh -f`, and `emulate -R zsh`.
- Made the production build deterministically reproducible from modular source with a POSIX `/bin/sh` build script; source-to-dist parity remains release-blocking.
- Canonicalized temp roots, bound RC3 ownership markers to exact path + effective user, and added retarget/tamper/control-character regression tests.
- Canonicalized package source/output parents, rechecked source state before `ditto`, and distinguished publish failure from output-race refusal.
- Removed default `avmediainfo` execution from `media.inspect`; availability is reported but the synchronous default path no longer performs a diagnostic probe whose output is not consumed structurally.
- Renamed write-state output to advisory `writableHint` rather than implying filesystem write success.
- Added preferred native `sha256` capability with `shasum` as an optional legacy fallback where available.
- Added pre/post device+inode+size+mtime stability checking around full-file SHA-256; obvious mid-read replacement/modification now fails with `SOURCE_CHANGED`.
- Added RC3 environment/symlink hardening tests, concurrency tests, command-contract parity tests, and a 1,000-case deterministic protocol fuzz pass.
- Expanded target-Mac qualification requirements for startup output, APFS/SMB semantics, hashing adapter selection, media metadata, AE invocation, and `ditto` packaging.

## 0.1.0-rc2 — 2026-09-17
- Added production-bundle parity QA so `dist/mograph-jailed.zsh` must exactly match the modular source build graph; rebuilt the stale RC artifact discovered by the swarm.

QA hardening release.

- Fixed missing-required-argument failures that previously lost their structured error code/message through shell command-substitution scope.
- Added command-specific argument schemas and request-size bounds.
- Fixed macOS volume filesystem detection: Darwin now uses `df -Y` when supported instead of incorrectly treating BSD `stat %T` as a filesystem type.
- Made the M4 test self-contained instead of reading a hardcoded `/mnt/data/MographJailed` workspace.
- Added AE-side command allowlisting, control-character rejection, bounded request values, Unix request line endings, and request-write cleanup.
- Changed the default AE media inspection from double full-file SHA-256 to bounded size+mtime verification; SHA-256 before/after remains an explicit forensic path.
- Added target-Mac M2/M3 qualification gates.
- Added a dedicated QA swarm regression suite.
- Clarified that structured `media.timing` remains intentionally fail-closed in V0.1.

## 0.1.0-rc1 — 2026-09-17

- Established MJ Native Protocol v1.
- Added capability probing and doctor report.
- Added file inspection, SHA-256, volume inspection, and guarded temp storage.
- Added source-labeled media inspection with optional `avmediainfo` validation.
- Deliberately rejected undocumented `avmediainfo` sample-text parsing for structured timing.
- Added After Effects JSX integration spike with embedded Base64 and JSON parsing.
- Added privacy-minimal Tech Report receipt.
- Added safe, non-overwriting `ditto` package creation.
- Completed JXA/AVFoundation/Core Image lab research; not promoted to production.
- Hardened Base64 canonicalization, JSON control-character escaping, cleanup traversal checks, and shell quoting.
