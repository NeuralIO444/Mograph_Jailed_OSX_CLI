# MJ_PROJECT_SCRAPE_1 — Project scraper JSON schema

Produced by `integrations/after-effects/MographJailed_ProjectScraper.jsx`
(walk the open project in After Effects, read-only). Consumed by
`project.ingest` (validate + summarize) and `expression.lint` (static analysis).

## Top-level

| Field | Type | Required | Notes |
|---|---|---|---|
| `schema` | string | yes | Must be `"MJ_PROJECT_SCRAPE_1"` |
| `scraperVersion` | string | yes | e.g. `"1.0"` |
| `projectPath` | string | yes | Absolute path of the .aep |
| `projectName` | string | yes | Leaf filename |
| `scrapedAt` | string | yes | ISO-8601 timestamp in UTC with a trailing `Z` (scraper 1.0 and later). Receipts from older scraper builds have no `Z` and mean the scraping machine's local time; consumers treat a bare timestamp as local time |
| `aeVersion` | string | yes | e.g. `"25.1.0"` |
| `numItems` | integer | yes | `app.project.numItems` |
| `comps` | array | yes | Comp descriptors (see below) |
| `fonts` | array of string | yes | Unique fonts across text layers (the text document's `font`, a PostScript name such as `Inter-Bold`) |
| `missingFonts` | array of string | no | Scraper 1.1+: PostScript names After Effects itself reports as missing or substituted (`app.fonts.missingOrSubstitutedFonts`, AE 24.0+). Absent when the host has no Font API |
| `footage` | array | yes | Footage descriptors (see below) |

## Comp descriptor

| Field | Type | Notes |
|---|---|---|
| `name` | string | |
| `id` | integer | Project item id |
| `label` | integer | Scraper 1.1+, optional: label colour index 0-16 |
| `folder` | string | Scraper 1.1+, optional: project-panel folder path such as `Comps/Precomps`; `""` at the root |
| `width`, `height` | integer | |
| `pixelAspect` | number | |
| `frameRate` | number | |
| `duration` | number | Seconds |
| `numLayers` | integer | |
| `layers` | array | Layer descriptors |

## Layer descriptor

| Field | Type | Notes |
|---|---|---|
| `name` | string | |
| `index` | integer | 1-based |
| `type` | string | `AVLayer`, `TextLayer`, `ShapeLayer`, `CameraLayer`, `LightLayer`, `NullLayer`, `Unknown` |
| `enabled`, `solo`, `locked` | boolean | |
| `hasVideo`, `hasAudio` | boolean | |
| `sourceName` | string | Empty when no source |
| `sourcePath` | string | Absolute file path, empty when none |
| `sourceId` | integer | Optional. Project item id of the layer's source (a footage item or a precomp's comp `id`); `0`/absent when none. Lets consumers resolve nested comps exactly even when names repeat |
| `sourceKind` | string | Scraper 1.1+, optional: `comp`, `solid`, `footage`, `placeholder`, or `""` with no source |
| `label` | integer | Scraper 1.1+, optional: label colour index 0-16 |
| `adjustment` | boolean | Scraper 1.1+, optional: adjustment layer |
| `font` | string | Optional. Text layers only: the font of the text document (first character); empty otherwise |
| `effects` | array | `{"name","matchName"}` |
| `markers` | integer | Marker count |
| `numProperties` | integer | Total properties walked |
| `numKeyframedProperties` | integer | |
| `expressions` | array | `{"propertyPath","expression"}` |

## Footage descriptor

| Field | Type | Notes |
|---|---|---|
| `id` | integer | Optional. Project item id |
| `name` | string | |
| `kind` | string | Scraper 1.1+, optional: `footage`, `solid` or `placeholder` |
| `label` | integer | Scraper 1.1+, optional |
| `folder` | string | Scraper 1.1+, optional: project-panel folder path |
| `path` | string | Absolute path, empty when none |
| `missing` | boolean | As reported by AE (`footageItem.missing`) |
| `hasVideo`, `hasAudio` | boolean | |

## Bounds (scraper must enforce)

- Max 200 comps; extra comps set top-level `"compsTruncated": true`
- Max 500 layers per comp; extra layers set `"layersTruncated": true` on the comp
- Max 2000 footage items; extras set top-level `"footageTruncated": true`
- Expression text truncated to 2000 chars; truncated ones set `"expressionTruncated": true`
- Property walk is shallow: only properties with keyframes or expressions are
  enumerated in detail; others count toward `numProperties`
- Total JSON must stay under ~5 MB

## Determinism

Comps in project order, layers by index, fonts sorted alphabetically,
footage in project order. The scraper must not include timestamps inside
nested objects (only top-level `scrapedAt`).
