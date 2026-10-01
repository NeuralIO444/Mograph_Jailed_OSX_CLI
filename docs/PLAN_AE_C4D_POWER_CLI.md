# Plan: MJ Power-User CLI for After Effects 2024 and Cinema 4D 2024

Status: draft, nothing implemented. Targets: AE 2024 (24.x), C4D 2024 (Redshift + Physical), macOS Sequoia (15)+, one workstation, stock zsh, no sudo, user-space only.

## Principles (inherited)
- Allowlisted, structured operations with fixed scripts. No "run this JSX/Python" escape hatch.
- Capability probes fail closed (app, version, licence, GUI session, GPU/Metal).
- Source files never mutated. Output is new, hash-suffixed files only.
- Tiers: T0 observe, T1 user-invoked generation. Nothing above.
- Hosts pinned to 2024; detected version recorded in every receipt.
- One per-host lock; one serial render queue (single GPU shared by Redshift and AE).

## Phases

### Phase 0 - Host discovery — DONE
- `host.detect` (`MJ_HOST_DETECT_1`): AE/C4D installs 2024+, CLIs, Redshift, Metal GPU, console session. Observed here: AE 2026 (26.5.0), C4D 2026.3 with Redshift, M2 Max, macOS 26.6.2.
- Licensing reported `unverified`; the real signal is `LICENCE_NOT_CONFIGURED` when a host asks for a licence choice (observed with `c4dpy` on this Mac).
- Deferred: TCC Automation permission probe (needed once AE scripting is used).

### Phase 1 - Render control — DONE (stubs qualified; real renders pending)
- `ae.render`, `c4d.render` with receipts (`MJ_RENDER_1`), one-at-a-time lock, timeout, licence-prompt detection, source-unchanged proof, `mj last` / `mj open-last`.
- Qualified against stub hosts (31 checks). Still to run on the workstation: a real AE render (needs a project and AE's own licence) and a real C4D render once C4D licensing is configured.
- Deferred: `render.queue` of multiple jobs; progress streaming to a dashboard (Phase 7); render cost estimator.

### Phase 2 - C4D scene intelligence
- `c4d.inspect` via `c4dpy`: scene graph, materials, textures, cameras, takes, render settings, Redshift nodes, fps.
- `c4d.lint` (report only): missing/absolute assets, fps/resolution mismatch vs AE comp; Redshift: missing RS textures/proxies, out-of-core settings, AOV mismatch; Physical: sampler and multipass/cryptomatte setup.
- `c4d.package`: copy assets to a new folder.
- Gate: lint catches a known-broken fixture scene.

### Phase 3 - AE/C4D bridge
- `bridge.check`: C4D scene vs AE comps using it (fps, duration, colour space, Cineware path).
- `bridge.export` / `ae.import`: fixed pass naming (beauty, depth, cryptomatte, object buffers) for both renderers; template-built comp.
- Receipts link C4D scene hash, render settings, outputs and AE snapshot.
- Gate: full C4D -> passes -> AE -> final round trip with no hand steps.

### Phase 4 - Workflow layer
- `recipe.run`: fixed parameterised chains (snapshot -> lint -> render -> verify).
- `project.diff` / `c4d.diff`.
- Batch mode over a folder with a summary report.
- Watcher upgrade: `.c4d` saves trigger inspect + lint.

### Phase 5 - Loop-Seam Finder — DONE (frame directories)
- Shipped: `loop.seams` over a directory of PNG frames → `MJ_LOOP_SEAMS_1` ranked start/end pairs, near-duplicate suppression, `minFrames`/`maxResults`.
- Kept python3 (already required by `project.ingest`); `sips` downscale makes HD sequences fast. JXA/CoreImage port deferred until python3 is actually unavailable on a target.
- Deferred: video input via `media.frame`, contact sheet of top candidates, coarse-to-fine refinement (only needed past ~2,000 frames).

### Phase 6 - Golden-Frame Regression — DONE (frame directories)
- Shipped: `golden.record` (`MJ_GOLDEN_1`, never overwrites) and `golden.check` (`MJ_GOLDEN_CHECK_1`: identical / pass / changed / missing, extra frames, `threshold`).
- Deferred: thumbnails in the receipt, re-rendering frames itself (needs Phase 1), linking to `plugin.audit` diffs.

### Phase 7 - Make it feel alive
- Live render dashboard: extend `mj-observe-dash` with progress, ETA, GPU load, current-frame thumbnail, AE/C4D job state.
- Native notifications and sounds on finish/fail via `osascript`.
- Menu-bar status indicator (JXA) showing watcher and render state; no new daemon beyond the existing LaunchAgent.

### Phase 8 - Protect work — DONE
- DONE: `project.restore` (hash-verified against the snapshot receipt; new file only). `project.diff` preview waits for Phase 4.
- DONE: `deps.graph` (`MJ_DEPS_GRAPH_1`: per-comp deps, transitive impact through precomps, missing footage, single points of failure). Deferred: offline HTML / text-tree rendering.
- DONE: `handoff.package` (project + local footage incl. image sequences + MANIFEST.json + README). JSON manifest stands in for the sqlite receipt until Phase 9. Deferred: relinking the packaged project (needs AE scripting).
- DONE: hash-chained append-only audit log of every request (opt-in by directory) + `audit.verify`.

### Phase 9 - Search and recall — DONE
- DONE: MJ-owned store (SQLite + FTS5, fixed schema, `user_version` migrations, local only) with `index.add`, `index.search`, `index.verify` (integrity receipts).
- DONE: preset library — `preset.add` / `preset.get`, SHA-256 content-addressed, versioned per label, searchable.
- Deferred: `expression.lint` suggesting library entries (needs tagged "known-good" expression presets first).

### Phase 10 - Shell power features — DONE (except render shortcuts)
- DONE: `mj` front end, `mj ops`, zsh completion driven by `system.describe` args.
- DONE: declarative recipes (`mj recipe`), validated against the registry before any step runs; shell syntax is inert.
- Deferred: `mj render --last`, `mj open-output` (need Phase 1 render receipts).

### Phase 11 - Hardening and release (ongoing)
- Target-Mac qualification checklist per phase; fuzz new request surfaces.
- macOS CI job; host wrappers tested with fake `aerender`/`c4dpy` stubs, real-host tests manual on the workstation.
- Man pages and docs for every operation.

## Dependencies and order
Phase 0 -> 1 -> 2 -> 3 are the spine. Phases 5 and 6 work today on any rendered PNG folder; they gain auto-render once Phase 1 lands. Phase 9 needs Phase 1 receipts. Phase 7 can follow Phase 1. Phase 8 and 10 can land incrementally once the spine exists.

## Risks
1. Licensing/GUI sessions: real-host tests stay manual on the workstation.
2. TCC prompts: detect and explain, never bypass.
3. AE is single-instance and stateful: per-host lock.
4. 2024 point-release drift: record host version in every receipt.
5. No in-place mutation or auto-fix: lint reports, recipes create new outputs.

## Not yet scheduled
Render cost estimator (sample frames -> projected time and disk).
