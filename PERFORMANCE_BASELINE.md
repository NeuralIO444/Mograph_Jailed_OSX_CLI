# MographJailed RC3 Performance Baseline

These measurements are **Linux QA-container indicators only**, not macOS SLAs. They are retained to detect large accidental regressions in the local build. Target-Mac timing must be recorded separately, especially for SMB media.

12-run indicative medians from the RC3 Linux compatibility build:

| Operation | Fixture | Median | Slowest observed |
|---|---|---:|---:|
| `system.probe` | local | 77.25 ms | 81.76 ms |
| `file.inspect` | 4 KB local file | 29.65 ms | 32.17 ms |
| `media.inspect` | 4 KB local file, no macOS metadata adapters | 29.71 ms | 31.81 ms |
| `volume.inspect` | local temp filesystem | 21.29 ms | 22.12 ms |
| `file.hash` | 10 MB local file | 69.83 ms | 75.26 ms |

Interpretation:

- `file.hash` cost scales with file size and storage speed and is explicitly classified as potentially slow.
- `package.create` is potentially slow and was not benchmarked in Linux because production requires macOS `ditto`.
- `media.inspect` and `volume.inspect` can still block on a slow/stale network volume because After Effects `system.callSystem()` is synchronous and macOS does not provide a zero-install generic timeout primitive suitable for this architecture.
- Default AE inspection therefore avoids full-file hashing and does not run `avmediainfo`.

Target-Mac qualification should record rough local and SMB response times rather than enforce these Linux numbers.


## dev.4 terminal targets

- `mj-man`: local file render only; no Native evidence operation is triggered.
- `mj-top`: snapshot-only; invokes only fast/read-only runtime/registry/storage operations.
- target interactive startup on a normal local project path: approximately sub-second to low-single-second, with target-Mac qualification required for the measured value.
- no hash, Spotlight search, media decode, derivative creation, or recursive scan is permitted during normal dashboard startup.

## Standard Library 1.0 performance policy

`media.timing` is intentionally classified `BOUNDED_MEDIA_PROBE` and `interactiveSafe=false`. The adapter reads only the `avmediainfo` pre-sample header, exits before `Sample Information`, and enforces a 256-line ceiling. Exact sample-table enumeration is not part of the default operation.

`system.describe` may execute a fixed in-memory SQLite capability probe when `/usr/bin/sqlite3` is present. The probe has no request-controlled SQL, forces memory temp storage, creates no persistent database, and is intended to remain a small bounded capability check. Product-owned SQLite stores will be introduced only through fixed schemas and their own performance/locking tests.

Standard Library 1.0 automatic media operations are local-only. SMB response-time benchmarking is intentionally out of scope because the project policy does not test or mutate production network shares automatically.


## FrameKit SL-M2 performance policy

`media.frame` is classified `FRAME_DECODE` and `interactiveSafe=false`. It performs an explicit AVFoundation decode and PNG encode and therefore must not run automatically during routine panel refresh/Analyze UI paths.

The public operation extracts exactly one requested frame per call, caps the maximum generated dimension at 4096 pixels (2048 default), refuses network/unknown storage, and does not enumerate a sample table. Zero time tolerance intentionally favors temporal precision over decode speed.

Portable QA cannot provide meaningful AVFoundation decode timings. The dev.2 target-Mac gate records functional behavior on the built-in H.264 fixture and may derive local temporary HEVC/ProRes fixtures; measured timings are diagnostic rather than release SLAs. VFR performance/behavior remains fixture-gated rather than inferred from CFR media.
