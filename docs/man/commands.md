# MographJailed Public Operations

## System

- `system.probe` — detect the current macOS environment and native capabilities.
- `system.doctor` — report whether the runtime has its required core capabilities.
- `system.describe` — return Capability Registry 2.0 plus Standard Library 1.0 module metadata.
- `runtime.verify` — verify the running runtime/version/protocol and optionally SHA-256.

## Files and assets

- `file.inspect` — read basic file facts.
- `file.hash` — SHA-256 with source-stability checks; size-dependent and not interactive-safe.
- `file.provenance` — read extended-attribute names only; values are never requested.
- `asset.manifest` — create a single-asset identity record.
- `asset.verify` — compare an asset against expected identity evidence.
- `search.candidate` — advisory Spotlight-backed candidate search; never auto-relinks.

## Images

- `image.inspect` — positive native image identification and image facts through ImageKit.
- `image.derivative` — create a staged, non-overwriting analysis derivative; never overwrites the source.

## Storage

- `storage.preflight` — filesystem/free-space/readability/writability-hint evidence.
- `volume.inspect` — filesystem and volume facts.

## Temporary workspaces

- `temp.create` — create an MJ-owned temporary workspace.
- `temp.clean` — delete only ownership-proven MJ temporary workspaces.

## Media

- `media.inspect` — conservative fast/advisory media metadata; does not execute `avmediainfo`.
- `media.timing` — Standard Library MediaProbe timing summary. Explicit, bounded, non-interactive, and `LOCAL_ONLY`.
- `media.frame` — create one bounded, non-overwriting local PNG frame derivative at a requested media time; dev.2 qualification candidate.

`media.timing` reports native duration/timescale, track count, selected video codec/dimensions/timescale, nominal FPS, minimum sample duration, frame-reordering requirement, and decode-support evidence. It does not enumerate the full sample table.

## Tier 0 Observer

Read-only project observation. It can look at everything and change nothing — `project.snapshot` only ever creates new versioned copies: it never overwrites and never mutates the source.

- `project.ingest` — validate an `MJ_PROJECT_SCRAPE_1` JSON receipt (written by the After Effects scraper) and summarize it: comps, layers, expressions, effects, fonts, footage, missing/unlinked footage.
- `expression.lint` — static analysis over scraped expressions: broken layer/effect references (`E001`/`E002`), `sampleImage()` inside loops (`W001`), hard-coded absolute paths (`W002`), and more.
- `plugin.audit` — enumerate and SHA-256 hash an After Effects Plug-ins directory. Reads only; never modifies it.
- `project.snapshot` — hash an `.aep` and save a timestamped, hash-suffixed versioned copy (APFS copy-on-write clone when available); skips unchanged projects; refuses to overwrite an existing snapshot.

Use `mj-man terminal` for the btop-style observer dashboard.

## Reports and packages

- `report.tech` — native diagnostic receipt including Standard Library status.
- `package.create` — create a ZIP derivative using native `ditto`, refusing overwrite.

Use `mj-man protocol` for request-file format.
