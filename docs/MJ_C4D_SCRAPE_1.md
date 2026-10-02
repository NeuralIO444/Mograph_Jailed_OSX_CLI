# MJ_C4D_SCRAPE_1 — Cinema 4D scene scrape

Produced by `integrations/cinema4d/MographJailed_C4DScraper.py`, which runs under `c4dpy` and **only reads** the scene it loads. Consumed by `c4d.inspect`, `c4d.lint` and `bridge.check`.

> **Status: the scraper has not yet been run against a real Cinema 4D.** It is written against the documented Python API with every read guarded, and a static guard (`scripts/check-c4d-scraper-readonly.sh`) forbids anything that could change a scene. Headless `c4dpy` stops at an interactive licence prompt until licensing is configured once by hand; run the scraper once after that and report any field it cannot fill. The consumers below are fully tested against hand-written receipts.

## Fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `schema` | string | yes | `"MJ_C4D_SCRAPE_1"` |
| `scraperVersion` | string | yes | e.g. `"1.0"` |
| `scenePath` | string | yes | Absolute path of the `.c4d` |
| `sceneName` | string | yes | Leaf filename |
| `scrapedAt` | string | yes | ISO-8601 UTC with trailing `Z` |
| `c4dVersion` | string | yes | e.g. `"2026.3"` |
| `fps` | number | yes | Document frame rate (> 0) |
| `startFrame`, `endFrame` | integer | yes | Document range, inclusive |
| `width`, `height` | integer | yes | Render resolution in pixels |
| `pixelAspect` | number | no | |
| `renderer` | string | yes | `"redshift"`, `"physical"`, `"standard"` or `"other"` |
| `outputPath` | string | no | Render output path/pattern; empty if none |
| `outputFormat` | string | no | e.g. `"PNG"` |
| `multipass` | boolean | no | Multi-pass output enabled |
| `passes` | array of `{name}` | no | Multi-pass layers / Redshift AOVs |
| `cameras` | array of `{name, active}` | no | |
| `takes` | array of `{name, active}` | no | |
| `materials` | array of `{name, type}` | no | `type`: `"redshift"`, `"standard"`, `"other"` |
| `textures` | array | no | `{path, resolved, missing, absolute}` per asset |
| `objects` | integer | no | Object count |

## Bounds

Up to 2,000 textures, 500 materials, 200 cameras and 200 takes; extra entries set `"truncated": true` at the top level. The file must stay under 8 MB.

## Determinism

Arrays are in document order; there are no timestamps inside nested objects.
