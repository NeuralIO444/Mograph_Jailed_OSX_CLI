# Roadmap

## 0.1.x stable reference

- Preserve the qualified hardened core.
- No next-generation feature work is backported unless it closes a critical safety defect.

## 0.2.x — Native Asset Intelligence

Completed development capabilities:

- Capability Registry 2.0 / `system.describe`
- `runtime.verify`
- `asset.manifest` / `asset.verify`
- `search.candidate`
- read-only `file.provenance`
- `image.inspect` / bounded non-overwriting `image.derivative`
- `storage.preflight`
- project-local terminal UX (`mj-man`, snapshot `mj-top`)

The 0.2 line remains the asset-intelligence foundation and preserves the 20-operation Protocol v1 surface.

## 0.3.x — MJ Standard Library 1.0 + Native Media Intelligence

### SL-M1 — Standard Library foundation — `0.3.0-dev.1`

Implemented:

- `src/lib/local_fs.zsh` — LocalFS shared filesystem classification
- `src/lib/native_db.zsh` — NativeDB runtime/JSON/FTS5 capability probes; no public SQL API
- `src/lib/media_probe.zsh` — bounded `avmediainfo` normalization
- `src/lib/image_kit.zsh` — reusable `sips` image primitives
- Standard Library descriptor in `system.describe` and `report.tech`
- `media.timing` promoted from placeholder to a bounded **local-only** normalized timing summary when available
- AE client `standardLibrary()` and `mediaTiming()` helpers
- explicit network policy: no automatic server enumeration, testing, caching, indexing, SQLite stores, or mutation

Target products:

- **MJ_Organize:** shared LocalFS/storage/image/asset evidence and future local receipt/index stores
- **MJ_AE_Looper:** normalized media timing first; frame extraction/comparison next

### SL-M2 — FrameKit candidate — `0.3.0-dev.2`

Implemented in the candidate:

- fixed embedded JXA/AVFoundation adapter; no generic JXA surface;
- new additive `media.frame` operation;
- local-only source and output-parent enforcement;
- exact-time request with zero tolerance;
- requested vs actual `CMTime` in the response;
- preferred track transform;
- bounded PNG output (64–4096 px, default 2048);
- non-overwriting staged publish and source-identity recheck;
- portable contract/security regression suite;
- target-Mac gate with built-in H.264 fixture and optional local HEVC/ProRes derived fixtures;
- dedicated After Effects child-process qualification JSX.

Promotion gate still outstanding:

1. pass `tests/run_framekit_m2_target_mac.zsh` on the managed Mac;
2. pass `tests/MographJailed_FrameKit_AE_Qualification.jsx` from After Effects;
3. record real JXA/CMTime behavior and transform correctness;
4. qualify a real local VFR fixture rather than synthesizing a claim from CFR media;
5. add corrupt-media evidence if the target gate exposes adapter-specific behavior requiring hardening.

The target-Mac-qualified `0.3.0-dev.1` install remains the baseline until these gates pass.

### SL-M3 — ImageKit analysis

Implemented (portable engineering complete; target-Mac qualification pending — see `docs/releases/0.3.0-dev.3/QA_REPORT_SL_M3.md`):

- `image.stats` — deterministic bounded signatures (`MJ_IMAGE_STATS_1`: 4×4×4 RGB histogram + 8×8 grid averages) via a pure-python3-stlib PNG decoder; read-only
- `image.compare` — interpretable 0.0–1.0 frame-distance score (`MJ_IMAGE_COMPARE_1`) for coarse loop-seam ranking
- Registry authority `DERIVED_IMAGE_SIGNATURE`; requires `python3`, `sips`, `awk`

Core Image remains behind the adapter boundary; Looper consumes MJ contracts, not Core Image directly.

### Tier 0 — Observer (27-operation surface)

Implemented on the current development line (see `docs/TIER0_OBSERVER.md`, `docs/MJ_PROJECT_SCRAPE_1.md`, `tests/run_observe_t0.sh`):

- `project.ingest` — validate an `MJ_PROJECT_SCRAPE_1` receipt, return `MJ_PROJECT_SUMMARY_1`
- `expression.lint` — static analysis over scraped expressions, return `MJ_EXPRESSION_LINT_1`; reports only, never fixes
- `plugin.audit` — enumerate and hash a Plug-ins directory, return `MJ_PLUGIN_AUDIT_1`; reads only
- `project.snapshot` — hash-suffixed, never-overwrite `.aep` copy with hash-skip idempotency, return `MJ_PROJECT_SNAPSHOT_1`; the only watcher-triggered operation
- AE scraper (`integrations/after-effects/MographJailed_ProjectScraper.jsx`, ES3 read-only; proven by `scripts/check-scraper-readonly.sh`), user-level LaunchAgent watcher (`watcher/`, `tools/watch-install.zsh`), and read-only `tools/mj-observe-dash.zsh` dashboard

All four operations are `LOCAL_ONLY`. Tier 0 changes nothing except creating new snapshot copies; Tier 1 (user-invoked generation) and Tier 2 (nonexistent: in-place mutation, network, sudo, arbitrary shell/SQL) are documented in `docs/TIER0_OBSERVER.md`.

### SL-M4 — NativeDB product stores

Only after product schemas are designed:

- fixed-schema local receipts
- optional local asset indexes
- FTS5 search over MJ-owned metadata
- migrations/versioning
- corruption/integrity receipts

No arbitrary SQL request API. No database on SMB/network volumes.

## 0.4.x — Perceptual Intelligence Lab

- Vision feature prints
- image similarity
- coarse candidate filtering
- optional OCR/visual evidence where a MJ product has a concrete need

## Promotion rule

Experimental adapters remain isolated until they pass managed-Mac security, performance, TCC/XProtect, deterministic-output, and After Effects child-process qualification. Development releases do not replace the qualified production reference until their target-Mac gates explicitly pass.
