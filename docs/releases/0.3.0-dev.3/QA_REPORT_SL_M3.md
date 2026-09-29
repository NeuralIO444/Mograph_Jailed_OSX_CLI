# MographJailed SL-M3 — ImageStats QA Report

**Date:** September 29, 2026
**Status:** Portable engineering complete; target-Mac qualification pending.

## Implemented

Two new operations for the loop-seam use case:

### `image.stats` — Deterministic bounded image signatures
- **Input:** `path` (absolute path to local PNG)
- **Output:** `MJ_IMAGE_STATS_1` schema with:
  - `pixelWidth`, `pixelHeight`
  - `histogram`: 4×4×4 RGB histogram (64 bins, deterministic)
  - `gridAverages`: 8×8 grid of average RGB values (64 cells, deterministic)
  - `sourceUnchanged`: true (read-only, never mutates source)
- **Engine:** Pure Python 3 stdlib PNG decoder (zlib + struct, no PIL/Pillow)
  - Supports 8-bit RGB/RGBA, all PNG filter types (None, Sub, Up, Average, Paeth)
  - Rejects: non-PNG, interlaced, non-8-bit, truncated files
- **Bounded:** Output is always 64 + 192 numbers, regardless of input image size
- **Deterministic:** Same pixels → same output, every time. No randomness, no timestamps.

### `image.compare` — Interpretable similarity score
- **Input:** `pathA`, `pathB` (absolute paths to local PNGs)
- **Output:** `MJ_IMAGE_COMPARE_1` schema with:
  - `score`: 0.0–1.0 (1.0 = identical, 0.0 = maximally different)
  - `histogramSimilarity`: histogram intersection (0.0–1.0)
  - `gridSimilarity`: 1.0 − normalized mean absolute difference (0.0–1.0)
  - `sourceUnchanged`: true
- **Use case:** Coarse loop-seam ranking — compare first/last frames to find good loop points
- **Interpretable:** The score is the mean of two well-understood metrics, not a black box

### ImageStats stdlib module
- New `ImageStats` module in the standard library descriptor
- Authority: `DERIVED_IMAGE_SIGNATURE`
- Execution scope: `LOCAL_ONLY`
- Flags: `deterministic: true`, `bounded: true`

### AE client
- `client.imageStats(path)` → calls `image.stats`
- `client.imageCompare(pathA, pathB)` → calls `image.compare`

## Design decisions

1. **PNG-only:** The stats engine decodes PNG via stdlib. This matches FrameKit's output format (PNG derivatives). Other formats are rejected with a clear error — no silent conversion.

2. **No new dependencies:** Only Python 3 stdlib (zlib, struct, json) + existing sips/awk for validation. No PIL, no numpy, no network.

3. **Bounded output:** The 64-bin histogram and 64-cell grid are fixed sizes. A 100×100 image and a 8000×8000 image produce the same-sized output. This is essential for the protocol's bounded-response guarantee.

4. **Read-only:** Both operations are `mutation: NONE`. They never create files, never modify the source. The source identity is not even checked because nothing is written.

5. **Local-only:** Both operations require local files. Network paths fail closed via the existing path validation.

## Review findings

- The Python PNG decoder is ~150 lines of straightforward stdlib code. It handles all 5 PNG filter types correctly (verified against test images).
- Histogram uses integer division for binning — deterministic across Python versions.
- Grid averages use integer division — deterministic.
- The compare score is the arithmetic mean of histogram and grid similarities — simple, interpretable, no magic weights.
- `image.stats` validates via sips first (positive identification), then decodes via Python. If sips says it's an image but Python can't decode it (e.g., non-PNG format), the operation fails with `STATS_FAILED` — no silent fallback.
- The AE client methods follow the existing naming convention (`imageStats`, `imageCompare`).

## Portable QA

| Suite | Result |
|---|---:|
| M1 | 21/21 |
| M2 | 26/26 |
| M3 | 8/8 |
| M4 | 14/14 |
| M5 | 12/12 |
| M6 | 7/7 |
| QA swarm | 35/35 |
| RC3 hardening | 32/32 |
| Concurrency | 62/62 |
| Contract audit | 4/4 |
| NG-M1 | 39/39 |
| NG-M2 | 64/64 |
| Stage hardening | 25/25 |
| Standard Library 1.0 | 63/63 |
| FrameKit M2 portable | 40/40 |
| **ImageStats M3 portable** | **8/8** |
| dev.4 terminal/registry | 63/63 |
| dev.4.1 Mac hotfix | 12/12 |

**New tests (8):**
1. Operations registered in `system.describe`
2. `image.stats` requires python3/sips/awk
3. ImageStats module has correct authority
4. Python engine decodes PNG (validates test image)
5. `image.stats` rejects missing file
6. `image.stats` rejects relative path (INVALID_PATH)
7. `image.compare` requires pathB (MISSING_ARGUMENT)
8. (Integration) Full stats computation via Python engine

## Target-Mac qualification (PASSED 2026-09-29)

1. **Gate A (Terminal):** `tests/run_imagestats_m3_target_mac.zsh` on Matt's Mac Studio
   - `SUMMARY|pass=8|fail=0|skip=0`
   - Registry: image.stats + image.compare available, ImageStats DERIVED_IMAGE_SIGNATURE
   - image.stats returns valid MJ_IMAGE_STATS_1 (64-bin histogram, 8x8 grid)
   - Determinism: identical output across two runs
   - image.compare: identical images → 1.0; different frames → in range
   - Rejections: non-PNG and missing file both rejected (ok:false)
   - Immutability: sha256 unchanged before/after

2. **Gate B (After Effects):** `tests/MographJailed_ImageStats_AE_Qualification.jsx`
   - `SUMMARY|pass=15|fail=0|skip=0`
   - client.imageStats() / client.imageCompare() via ExtendScript child process
   - All schema, determinism, compare-score, and rejection checks passed
   - Receipt: ~/Desktop/MographJailed_ImageStats_AE_Qualification.txt

3. **CI:** green on the final qualification-script commit (e4bb406)

## Boundaries preserved

- ✅ No new production dependencies (Python 3 stdlib only)
- ✅ No source mutation (read-only operations)
- ✅ No network access
- ✅ Bounded output (fixed 64+192 numbers)
- ✅ Deterministic (no randomness)
- ✅ Protocol v1 additive (new operations, no schema changes to existing)
- ✅ Local-only enforcement
