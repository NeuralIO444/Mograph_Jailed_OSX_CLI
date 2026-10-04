# MJ Native Protocol v1

Request files use a deliberately small text format so the runtime does not depend on `jq`, Python, Node, or another downloaded parser.

```text
MOGRAPHJAILED_REQUEST 1
requestId=<restricted ASCII token>
command=<allowlisted command>
arg.path=<canonical Base64 of UTF-8 value>
```

Rules:

- Commands and argument names are compile-time allowlists.
- Each command has its own accepted/required argument schema; extra arguments fail with `UNEXPECTED_ARGUMENT`.
- Argument values use canonical Base64 so production paths never become shell syntax.
- Decoded Base64 is round-tripped before use; unsupported byte sequences fail closed.
- ASCII control characters are rejected in protocol arguments. This deliberately excludes unusual but legal filenames containing tabs/newlines/control bytes in exchange for a smaller, auditable boundary.
- NUL cannot be represented and is rejected by canonical encoding behavior.
- Request IDs are capped at 128 characters.
- A request is capped at 32 lines, each line at 32,768 characters, and each decoded argument at 16,384 characters.
- Unknown request fields are rejected.
- No request can contain a raw command line.

Responses are JSON envelopes containing `protocol`, `protocolVersion`, `cliVersion`, `requestId`, `command`, `ok`, `data`, `warnings`, and `error`.

Every failure response must contain a non-empty error `code` and `message`. stdout is protocol-only; diagnostics belong on stderr.

## Compatibility policy

- `protocolVersion` governs breaking request/response contract changes.
- `cliVersion` may change while protocol v1 remains compatible.
- A client may accept any CLI version that returns a supported protocol version.
- Consumers should ignore unknown additive response fields.
- A breaking command schema or semantic change after V1 qualification requires a protocol-version decision rather than silent reinterpretation.
- Unsupported request protocol versions fail with `BAD_REQUEST_VERSION`.


## NG-M1 additive operations

Protocol v1 now also allowlists `system.describe` and `runtime.verify`.

`runtime.verify` requires canonical Base64 arguments `expectedCliVersion` and `expectedProtocolVersion`; `expectedFilename` and `expectedSha256` are optional. Runtime mismatches are returned as a successful diagnostic operation with `data.compatible:false`, while malformed verification arguments fail closed with a normal protocol error envelope.

The capability registry is a data contract layered on Protocol v1; its own schema is `MOGRAPHJAILED_CAPABILITY_REGISTRY_2`.

## NG-M2 additive operations

Protocol v1 additionally allowlists the following operations:

- `asset.manifest`: required `path`; optional `format` (`fast` or `sha256`)
- `asset.verify`: required `path`; one or more of `expectedFilename`, `expectedSizeBytes`, `expectedModifiedEpoch`, `expectedSha256`
- `search.candidate`: required `path` (search root) and `target` (leaf filename); optional `maxResults`
- `file.provenance`: required `path`
- `image.inspect`: required `path`
- `image.derivative`: required `input`, `output`, and `target` (bounded maximum pixel dimension)
- `storage.preflight`: required `path`; optional `requiredBytes`

All argument values remain canonical Base64. New argument names are compile-time allowlisted. Search candidates are advisory; asset mismatches are returned as successful diagnostic results with `match:false`; image derivatives refuse overwrite and do not mutate the input.


## 0.2.0-dev.4.1 contract correction

Protocol v1 command schemas are unchanged. Capability Registry 2.0 now guarantees `requires.all` and `optionalCapabilities` are emitted as true arrays with one capability per string element under production zsh as well as QA shells. This corrects representation only; it does not add or reinterpret a public operation.

## 0.3.0-dev.1 / Standard Library 1.0 additive contract

Protocol v1 transport remains unchanged. dev.1 retained 20 public commands; dev.2 grows additively to 21 with `media.frame`.

Registry 2.0 adds a top-level `standardLibrary` descriptor and per-operation `executionScope`. These are additive fields.

The existing `media.timing` command is now implemented when the required Standard Library MediaProbe capabilities are present. Its request schema remains:

```text
command=media.timing
arg.path=<Base64 absolute path>
```

The operation is `LOCAL_ONLY`. A positively identified network filesystem returns `NETWORK_SCOPE_BLOCKED`; an unclassified filesystem returns `STORAGE_SCOPE_UNKNOWN`. The default adapter does not enumerate a full sample table.

No `db.*`, `sql.*`, or generic shell command is added. NativeDB remains an internal fixed-capability layer in this milestone.


## 0.3.0-dev.2 / FrameKit SL-M2 additive contract

Protocol v1 additionally allowlists `media.frame`. No existing command schema is reinterpreted.

Request schema:

```text
command=media.frame
arg.path=<Base64 absolute local media path>
arg.output=<Base64 absolute new .png path>
arg.timeSeconds=<Base64 non-negative decimal seconds>
arg.maxPixels=<Base64 integer 64..4096>   # optional; default 2048
```

`path`, `output`, and `timeSeconds` are required. The operation is `LOCAL_ONLY`, refuses overwrite, and returns schema `MJ_MEDIA_FRAME_1` with requested time, actual generated time, delta, dimensions, output facts, transform/tolerance evidence, source-stability evidence, and adapter identity.

The operation does not accept JavaScript, Objective-C selectors, shell commands, SQL, codec settings, or arbitrary AVFoundation options.

## 0.3.0-dev.3 / SL-M3 ImageStats additive contract

Protocol v1 additionally allowlists `image.stats` and `image.compare`, growing the public surface from 21 to 23 operations. No existing command schema is reinterpreted.

Request schemas:

```text
command=image.stats
arg.path=<Base64 absolute image path>

command=image.compare
arg.pathA=<Base64 absolute image path>
arg.pathB=<Base64 absolute image path>
```

Both are `SIZE_DEPENDENT`, `NONE` mutation, `DERIVED_IMAGE_SIGNATURE` authority, and `EXPLICIT_PATH_OR_NONE` execution scope. `image.stats` returns schema `MJ_IMAGE_STATS_1` (bounded deterministic signatures); `image.compare` returns schema `MJ_IMAGE_COMPARE_1` (interpretable 0.0–1.0 similarity score). Both require `python3`, `sips`, and `awk`; both are read-only and never mutate the source image.

## Tier 0 Observer additive contract

Protocol v1 additionally allowlists four project-observation operations, growing the public surface from 23 to 27 operations. No existing command schema is reinterpreted.

Request schemas:

```text
command=project.ingest
arg.path=<Base64 absolute MJ_PROJECT_SCRAPE_1 JSON path>

command=expression.lint
arg.path=<Base64 absolute MJ_PROJECT_SCRAPE_1 JSON path>

command=plugin.audit
arg.path=<Base64 absolute plug-ins directory path>

command=project.snapshot
arg.path=<Base64 absolute .aep path>
arg.output=<Base64 absolute versions directory path>
```

All four are `LOCAL_ONLY`: network and unknown filesystem classes fail closed before any work runs. `project.ingest` returns schema `MJ_PROJECT_SUMMARY_1`; `expression.lint` returns `MJ_EXPRESSION_LINT_1`; `plugin.audit` returns `MJ_PLUGIN_AUDIT_1`; `project.snapshot` returns `MJ_PROJECT_SNAPSHOT_1`. Only `project.snapshot` mutates (`DERIVATIVE_CREATE`: a new hash-suffixed copy that never overwrites; unchanged sources are skipped, not re-copied). The other three are read-only, and only `project.snapshot` is excluded from interactive-safe paths.

## Frame-sequence additive contract (loop seams, golden frames)

Protocol v1 additionally allowlists three frame-sequence operations, growing the public surface from 27 to 30 operations. Two argument names are added: `minFrames` and `threshold`. No existing command schema is reinterpreted.

Request schemas:

```text
command=loop.seams
arg.path=<Base64 absolute directory of PNG frames>
arg.minFrames=<optional Base64 integer; 0 or omitted = half the frame count>
arg.maxResults=<optional Base64 integer 1-50; default 5>

command=golden.record
arg.path=<Base64 absolute directory of PNG frames>
arg.output=<Base64 absolute existing directory for the receipt>
arg.label=<Base64 label: letters, digits, dot, dash, underscore; max 64>

command=golden.check
arg.path=<Base64 absolute directory of PNG frames>
arg.input=<Base64 absolute MJ_GOLDEN_1 receipt path>
arg.threshold=<optional Base64 decimal 0-1, up to 4 places; default 0.98>
```

Frames are the regular, non-hidden `*.png` files in the directory, sorted by name (8- or 16-bit RGB/RGBA, non-interlaced; at most 2,000). When `sips` is available, frames are downscaled to a 256 px long edge in a private temp directory before signing; sources are never touched.

All three are `LOCAL_ONLY`, `FRAME_COUNT_DEPENDENT`, `DERIVED_IMAGE_SIGNATURE`, require only `python3`, and list `sips` as optional.

- `loop.seams` returns `MJ_LOOP_SEAMS_1`: ranked `{startFrame, endFrame, lengthFrames, score}` candidates. The loop plays `startFrame..endFrame-1`; `endFrame` is the frame that should match `startFrame`. Near-duplicate seams (both ends within 2 frames) are suppressed. Mutation `INTERNAL_TEMP`.
- `golden.record` writes `<output>/<label>.golden.json` (`MJ_GOLDEN_1`: per-frame SHA-256 + signature) and refuses to overwrite (`OUTPUT_EXISTS`). Mutation `DERIVATIVE_CREATE`.
- `golden.check` returns `MJ_GOLDEN_CHECK_1`: per-frame `identical` (same bytes), `pass` (score ≥ threshold), `changed`, or `missing`, plus `extraFrames`, `worstScore`, and overall `passed`. Mutation `INTERNAL_TEMP`.

## Audit contract

Protocol v1 additionally allowlists `audit.verify`, growing the public surface from 30 to 31 operations. No existing command schema is reinterpreted.

```text
command=audit.verify
arg.path=<Base64 absolute audit.jsonl path>
```

`LOCAL_ONLY`, `SIZE_DEPENDENT`, mutation `NONE`, authority `DERIVED_AUDIT_CHAIN`, requires `python3`. Returns `MJ_AUDIT_VERIFY_1`: `valid`, `entriesVerified`, `firstBrokenLine`, `reason`, first/last timestamps, and `headHash` (SHA-256 of the newest line, only when valid).

The runtime appends to `<dir>/audit.jsonl` after every request, including rejected ones, when `<dir>` already exists. `<dir>` is `~/Library/Logs/MographJailed`, or `MJ_AUDIT_DIR` when set. Each line is `{"v":1,"ts","cliVersion","requestId","command","exitCode","args":{name:value},"prev"}`; `prev` is the SHA-256 of the previous line's bytes (64 zeros for the first). Writers serialize on an atomic `mkdir` lock. Logging never alters a response or exit code, and is skipped (not retried) if the lock cannot be taken within 5 s.

## Argument schemas in system.describe

Each operation descriptor in `system.describe` now includes `"args":{"allowed":[...],"required":[...]}`, generated from the same table the request validator uses. Clients and shell completion should read this instead of hard-coding argument lists.

## Protect-work additive contract

Protocol v1 additionally allowlists three operations, growing the public surface from 31 to 34. No existing command schema is reinterpreted.

```text
command=project.restore
arg.path=<Base64 absolute snapshot .aep path>
arg.output=<Base64 absolute existing directory>

command=deps.graph
arg.path=<Base64 absolute MJ_PROJECT_SCRAPE_1 JSON path>

command=handoff.package
arg.path=<Base64 absolute .aep path>
arg.input=<Base64 absolute MJ_PROJECT_SCRAPE_1 JSON path for that project>
arg.output=<Base64 absolute existing parent directory>
arg.label=<Base64 label: letters, digits, dot, dash, underscore; max 64>
```

All three are `LOCAL_ONLY` and require `python3` (`project.restore` and `handoff.package` also `cp`).

- `project.restore` (`DERIVATIVE_CREATE`) returns `MJ_PROJECT_RESTORE_1`. If `<snapshot>.snapshot.json` exists, the snapshot's SHA-256 must match it or the restore is refused (`SNAPSHOT_CORRUPT`); `receiptVerified` reports which case applied. Writes `<stem>.restored.<UTC>.aep` (or `-2`, `-3` … on a same-second collision) via a verified temp copy and hard link, so an existing file is never replaced.
- `deps.graph` (`NONE`) returns `MJ_DEPS_GRAPH_1`: per-comp footage, precomps, effects and text use; every footage/effect dependency with its direct users and the comps impacted through precomp nesting; `missingFootage`, `unverifiedFootage`, and `singlePointsOfFailure` (dependencies impacting two or more comps, most impact first).
- `handoff.package` (`DERIVATIVE_CREATE`) creates `<output>/<label>.handoff/` with `project/`, `footage/` (local referenced files; numbered image sequences collected as a folder), `MANIFEST.json` (`MJ_HANDOFF_1`: SHA-256 of every packaged file, fonts, effects, missing and skipped footage) and `README.txt`. The folder is reserved atomically (`OUTPUT_EXISTS` if present), free space is checked first (`INSUFFICIENT_SPACE`), and a failed build removes the partial folder. The packaged project is not relinked.

Footage paths read from a scrape are classified from the kernel mount table, without touching the path. Footage on network or unknown storage is never stat'ed or copied: `deps.graph` reports it as unverified and `handoff.package` lists it as skipped.

## Search and recall additive contract (MJ-owned store)

Protocol v1 additionally allowlists five operations, growing the public surface from 34 to 39, and adds the argument name `version`. No existing command schema is reinterpreted.

```text
command=index.add
arg.path=<Base64 absolute receipt file, or directory searched recursively for *.json>

command=index.search
arg.target=<Base64 search words>
arg.maxResults=<optional Base64 integer 1-200; default 20>

command=index.verify

command=preset.add
arg.path=<Base64 absolute file, max 512 MB>
arg.label=<Base64 label: letters, digits, dot, dash, underscore; max 64>

command=preset.get
arg.label=<Base64 label>
arg.output=<Base64 absolute existing directory>
arg.version=<optional Base64 integer; default latest>
```

The store is `~/Library/Application Support/MographJailed` (`MJ_STORE_DIR` overrides), created with mode 700 by the first writing operation, and must be on a local filesystem. It holds `index.sqlite` (fixed schema, `PRAGMA user_version` 1; a newer version is refused with `STORE_TOO_NEW`) and `presets/<sha256>` blobs. There is still no SQL request surface: every statement is fixed text with bound parameters.

- `index.add` (`STORE_WRITE`, `MJ_OWNED_STORE`) indexes `MJ_PROJECT_SCRAPE_1`, `MJ_PROJECT_SNAPSHOT_1`, `MJ_GOLDEN_1` and `MJ_HANDOFF_1` files (≤ 8 MB each, ≤ 5,000 per call), skipping other JSON, hidden directories, symlinks and non-local subtrees. Unchanged files (same SHA-256) are not re-indexed. Returns `MJ_INDEX_ADD_1`.
- `index.search` (`NONE`, `ADVISORY_INDEX`) splits the query into words (max 12), matches each as a prefix, requires all of them, and ranks by BM25. FTS operators in the query are never interpreted. Returns `MJ_INDEX_SEARCH_1` with `kind` (`project`, `comp`, `layer`, `effect`, `expression`, `font`, `footage`, `snapshot`, `golden`, `handoff`, `file`, `preset`), `name`, `detail` and the source receipt.
- `index.verify` (`NONE`) returns `MJ_INDEX_VERIFY_1`: SQLite `integrity_check`, FTS integrity, schema version, counts, `staleDocs` (indexed local receipts that no longer exist) and `corruptPresetBlobs`; `healthy` is false on any integrity failure or corrupt blob.
- `preset.add` (`STORE_WRITE`) stores the file content-addressed and records a new label version only when the bytes differ from the label's latest (`created:false, reason:"unchanged"` otherwise). Kind is inferred from the extension (`.ffx`, `.aet`, `.aep`, `.mogrt`, `.jsx`, `.js`, `.txt`, `.c4d`, `.lib4d`, `.rsmat`). Returns `MJ_PRESET_1`.
- `preset.get` (`DERIVATIVE_CREATE`) re-hashes the blob (`PRESET_CORRUPT` on mismatch) and writes the original filename, or `<stem>-v<N><ext>` if that exists; `OUTPUT_EXISTS` if both exist. Returns `MJ_PRESET_GET_1`.

`index.search` and `index.verify` fail with `STORE_EMPTY` and create nothing when the store does not exist yet.

## Host-application additive contract (After Effects, Cinema 4D)

Protocol v1 additionally allowlists three operations, growing the public surface from 39 to 42, and adds the argument names `range` and `timeoutSeconds`. No existing command schema is reinterpreted.

```text
command=host.detect

command=ae.render
arg.path=<Base64 absolute .aep>
arg.target=<Base64 comp name>
arg.output=<Base64 absolute existing parent directory>
arg.label=<Base64 label: letters, digits, dot, dash, underscore; max 64>
arg.range=<optional Base64 "START-END" frames, inclusive>
arg.timeoutSeconds=<optional Base64 integer 10-86400; default 3600>
arg.version=<optional Base64 host year >= 2024; default newest installed>

command=c4d.render
arg.path=<Base64 absolute .c4d>
arg.target=<optional Base64 take name>
(output, label, range, timeoutSeconds, version as for ae.render)
```

Hosts are discovered only as `/Applications/Adobe After Effects <year>/` (needs the `.app` and `aerender`) and `/Applications/Maxon Cinema 4D <year>/` (needs `Cinema 4D.app` and `Commandline.app`); years before 2024 are reported but unsupported. No host path is ever taken from a request. `PYTHONPATH`, `PYTHONHOME` and related variables are cleared for every embedded Python script.

- `host.detect` (`NONE`, `AUTHORITATIVE_ENVIRONMENT`) returns `MJ_HOST_DETECT_1`: macOS version/arch, GPU and Metal support, console-session ownership, every AE/C4D install with version, CLI paths, Redshift presence and `supported`, and a `ready` summary. Licensing is reported `unverified`; it is only observed when a host runs.
- `ae.render` / `c4d.render` (`DERIVATIVE_CREATE`, `RENDER_BOUND`) render to a new PNG sequence in `<output>/<label>.<UTC>/` (a suffix is added on collision) and write `render.json` (`MJ_RENDER_1`) and `render.log` there. `ae.render` forces `-outputSettings "Format: PNG Sequence"`, never uses `-reuse`, and never saves the project. `c4d.render` uses the scene's own render settings (Redshift or Physical) and overrides only image path and format. The receipt records host year/version, exact `argv`, frame count against expected, SHA-256 of the first and last frame, and the source file's hash before and after (`source.unchanged`).
- Status is `complete`, or the operation fails with `RENDER_FAILED`, `RENDER_INCOMPLETE` (frames missing), `RENDER_TIMEOUT`, or `LICENCE_NOT_CONFIGURED`. Every host process runs with stdin closed, in its own process group (killed whole on timeout), and a licence-choice prompt in its output stops it immediately. Receipts are written for failures too.
- One render at a time per machine (`RENDER_BUSY`), enforced with a lock under the store whose owner pid is checked so a crashed run's lock is reclaimed. The newest receipt is recorded in `<store>/last-render.json` for `mj last` and `mj open-last`.

## Project audit queries (store schema v2)

Protocol v1 additionally allowlists two read-only operations, growing the public surface from 42 to 44. No existing command schema is reinterpreted.

```text
command=trace.asset
arg.target=<Base64 exact asset name, asset path, or font name>   (not needed for format=missing)
arg.format=<optional Base64: asset (default) | font | missing>
arg.path=<optional Base64 absolute project path to restrict to one project>
arg.maxResults=<optional Base64 integer 1-500; default 50>

command=audit.plugins
arg.target=<optional Base64 effect matchName, exact and case-sensitive>
arg.maxResults=<optional Base64 integer 1-1000; default 100>
```

Both are `LOCAL_ONLY`, `NONE` mutation, `DERIVED_PROJECT_SUMMARY`, require `python3`, and fail with `STORE_EMPTY` (creating nothing) until `index.add` has indexed at least one `MJ_PROJECT_SCRAPE_1` receipt. Statements are fixed text with bound parameters.

Store schema v2 adds normalized `projects`, `compositions`, `layers`, `assets`, `fonts` and `plugins` tables, filled by `index.add` from scrapes. One row set per `projectPath`; the newest `scrapedAt` wins, so an older receipt indexed later never replaces newer data. Opening a v1 store migrates it in place and marks existing scrape receipts for a one-time re-read on the next `index.add`.

- `trace.asset` returns `MJ_TRACE_1`: for each matching project, each matching asset or font, and every layer that uses it with the full root-to-comp nesting chains (`"Main > Mid > Inner"`, up to 20 per layer). Precomp links use the layer's `sourceId`, so duplicate comp names resolve correctly; scrapes that lack ids fall back to a name only when the comp name is unique. `format=missing` lists every asset flagged missing. Font lookups are case-insensitive and report layers by the font recorded on each text layer; fonts present in the project but not attributed to any layer are reported with no uses.
- `audit.plugins` with a `target` returns `MJ_PLUGIN_USAGE_1`: the unique project paths that use that exact effect `matchName`, with layer-use and composition counts. Without a `target` it returns `MJ_PLUGIN_INVENTORY_1`: every `matchName` in the index with project and layer-use counts, most widely used first. Only each project's newest indexed scrape is counted.

`MJ_PROJECT_SCRAPE_1` gains three optional fields (layer `sourceId`, text-layer `font`, footage `id`); consumers that do not know them are unaffected.

## Verification semantics (0.4.0-dev.1)

- **`project.snapshot`** stages the copy under a hidden name in the output directory, re-hashes the staged copy and the source, and publishes with a hard link. If either hash differs from the hash taken before copying, nothing is kept and the operation fails with `SNAPSHOT_UNSTABLE` (the project was being written; the watcher retries on the next save). An existing snapshot is never replaced (`OUTPUT_EXISTS`). The `.aep` extension is matched case-insensitively, so `Foo.AEP` and `Foo.aep` use the same `Foo.latest.json` pointer. Responses report `copyVerified`; the receipt records `copyVerified` and `sourceStableDuringCopy`.
- **`sourceUnchanged`** reports a comparison of the source's identity before and after the operation: size and modification time (Python-based operations compare nanosecond timestamps; shell-based ones compare to the second; for a directory of frames, the names, sizes and times of its regular files). A `false` value means the source changed while the operation ran. Operations that refuse to continue when the source changes (`image.derivative`, `media.frame`, `project.snapshot`, which also compare content hashes) can only report `true`. A rewrite of identical size within the timestamp precision is not detected by the size-and-time check. `preset.get` does not report it (its source is the hash-verified store).
- **Version**: `runtime.verify`, `system.describe` and `VERSION` report `0.4.0-dev.1`; `tests/run_contract_audit.sh` fails if the runtime constant, `VERSION` and the newest `CHANGELOG.md` heading disagree.

## Warnings

Every success response carries `"warnings": []`. When an operation completes but its result is incomplete or needs attention, the list holds `{ "code", "message" }` objects instead (for example `RESULTS_TRUNCATED`, `MISSING_FOOTAGE`, `FILE_TOO_LARGE_TO_HASH`). A warning never changes `ok` or the exit code. The codes are listed in `docs/man/errors.md`. Operations backed by a Python engine report warnings through a reserved `_warnings` list in their result, which the runtime lifts into this field; it never appears inside `data`.

`plugin.audit` hashes files up to 2 GB each; larger files are listed with `sha256: null` and a `FILE_TOO_LARGE_TO_HASH` warning. `file.hash` has no size bound; on Apple Silicon SHA-256 runs at roughly 350 MB/s (about 3 seconds per GiB), so size your timeouts accordingly.

## Standard input, doctor guidance, dashboard JSON

- **`--request -`** reads the request from standard input (up to 256 KB; larger is `REQUEST_TOO_LARGE`). The runtime copies it to a private temporary file first, so parsing and the audit log behave exactly as for a file. The temporary file is removed on every exit path.
- **`system.doctor`** now includes `guidance` (one entry per missing tool: `capability`, the `unlocks` list of operations it blocks, and a plain-language `hint`) and `operations: {total, unavailable}`. `ready` still means "core capabilities present"; it does not mean every operation is available. The doctor itself uses only core tools, so it answers even when `python3` is missing.
- **`tools/mj-observe-dash.zsh --json`** prints the dashboard's data as one JSON document (`MJ_OBSERVE_DASH_1`) and exits. The receipt ingest is cached by the newest receipt's path, size and modification time.

## Project insight: diff, health, teaching lint (0.4.0-dev.1)

Two read-only operations are added (44 to 46). Store schema is now v3 (adds a `health` table; v1/v2 stores migrate in place).

```text
command=project.diff
arg.path=<Base64 absolute MJ_PROJECT_SCRAPE_1 path: the earlier version>
arg.input=<Base64 absolute MJ_PROJECT_SCRAPE_1 path: the later version>

command=project.health
arg.path=<Base64 absolute scrape path>                    (not needed for format=all)
arg.input=<optional Base64 absolute snapshot versions folder: adds snapshot freshness>
arg.format=<optional: score (default) | record | all>
```

- `project.diff` returns `MJ_DIFF_1`: a `summary` of counts and a `changes` list of plain sentences (comps, layers, expression text per property, footage including "went missing", fonts, effect types). Comps and footage are matched by the scraper's item `id` when every item has one, otherwise by name or path; `matchedBy` says which. Warnings: `DIFFERENT_PROJECTS`, `SCRAPES_OUT_OF_ORDER`, `CHANGES_TRUNCATED`.
- `project.health` returns `MJ_PROJECT_HEALTH_1`: `score` 0-100, a `band`, and `components` that each carry their points, what was lost and why, and the findings behind it. **Formula version 1:** score = 100 x earned / measurable points, where *footage* is worth 35 (minus 12 per missing item, 3 per unlinked item), *expressions* 40 (minus 8 per lint error, 3 per warning) and *snapshots* 25 (25 if the newest snapshot is within an hour of the scrape, 15 within a day, else 0; none = 0), counted only when `input` is given. Bands: 90+ healthy, 70-89 needs a look, 40-69 at risk, below 40 unhealthy. The formula text is returned with every score and `formulaVersion` changes whenever the arithmetic does; trends only compare scores of the same version. Plug-in availability is not part of v1 (a scrape records effect names but not whether they are installed).
- `format=record` also stores the score (keyed by project path and receipt hash, so it is idempotent) and returns the `trend`; `format=all` returns `MJ_HEALTH_TRENDS_1`, every recorded project's latest score and series. Mutation is `STORE_WRITE` for the operation as a whole; `score` and `all` never write.
- `expression.lint` findings gain `teach: {why, fix}`, and the result gains `teaching: {code: {before, after}}` for the codes present. Codes, severities and messages are unchanged, so scripted consumers are unaffected.

## Cinema 4D intelligence and the AE/C4D bridge (0.4.0-dev.2)

Three read-only operations are added (46 to 49). They work on **receipts**, so they need no Cinema 4D licence and never open a scene. The receipt (`MJ_C4D_SCRAPE_1`, see `docs/MJ_C4D_SCRAPE_1.md`) is written by `integrations/cinema4d/MographJailed_C4DScraper.py` under `c4dpy`; that scraper is guarded read-only in CI but has **not yet been run against a real Cinema 4D**.

```text
command=c4d.inspect
arg.path=<Base64 absolute MJ_C4D_SCRAPE_1 path>

command=c4d.lint
arg.path=<Base64 absolute MJ_C4D_SCRAPE_1 path>

command=bridge.check
arg.path=<Base64 absolute MJ_C4D_SCRAPE_1 path>
arg.input=<Base64 absolute MJ_PROJECT_SCRAPE_1 path>
arg.target=<optional Base64 comp name to restrict the check to>
```

- `c4d.inspect` returns `MJ_C4D_SUMMARY_1`: renderer, resolution, fps, frame range and seconds, output path, passes, cameras, takes, materials by type, and textures with the missing and absolute ones listed. Warnings: `TEXTURES_MISSING`, `SCENE_TRUNCATED`.
- `c4d.lint` returns `MJ_C4D_LINT_1` with rules `C001` missing texture (error), `C002` absolute texture path, `C003` no camera, `C004` odd resolution, `C005` end frame before start (error), `C006` empty output path, `C007` standard materials in a Redshift scene, `C008` renderer is not Redshift or Physical (note), `C009` multi-pass on with no passes (note). Each finding carries `teach: {why, fix}`; the result carries `teaching` before/after snippets, as `expression.lint` does.
- `bridge.check` returns `MJ_BRIDGE_CHECK_1`. It finds the After Effects layers whose source is the same `.c4d` (matched by file name, case-insensitively) and compares the comp with the scene: `B001` frame rate (error), `B002` resolution, `B003` duration (more than one frame apart), `B004` the layer points at a different path from the scene that was checked (error), `B005` After Effects reports the scene file missing (error). `consistent` is true only when something matched and nothing was found. With no matching layer it warns `NO_MATCHING_LAYER` and compares nothing.
- Content errors in a receipt are `INVALID_JSON`, `SCHEMA_MISMATCH` and `SCRAPE_TOO_LARGE` with exit 65, as for After Effects scrapes.

## Studio tools, delivery QC and After Effects jobs (0.4.0-dev.3)

Seven additive operations; no existing contract changed.

| Operation | Args (required*) | Writes | Schema |
|---|---|---|---|
| `project.preflight` | `path`* (scrape) | nothing | `MJ_PREFLIGHT_1` |
| `cache.inspect` | none | nothing | `MJ_CACHE_INSPECT_1` |
| `cache.clean` | `target`* (cache id), `format` (`report` default, `delete`) | empties one known cache folder | `MJ_CACHE_CLEAN_1` |
| `media.qc` | `path`*, `format` (built-in spec) or `input` (spec file) | nothing | `MJ_MEDIA_QC_1` |
| `project.extract` | `path`* (.aep), `input`* (scrape), `target`* (comp ids, comma separated), `output`*, `label`* | a new `<label>.mjjob` folder | `MJ_AE_JOB_PLAN_1` |
| `project.conform` | `input`* (scrape), `spec`, `format` (`plan` default, `job`), and for a job `path`, `output`, `label` | a job only with `format=job` | `MJ_CONFORM_PLAN_1` |
| `project.jobcheck` | `path`* (job folder) | nothing | `MJ_AE_JOB_CHECK_1` |

`spec` is a new argument name. A job folder holds `before.aep`, `plan.json` (`MJ_AE_JOB_1`) and `run.jsx`; After Effects writes `result.aep` and `result.json` (`MJ_AE_JOB_RESULT_1`). `cache.clean` has the new mutation class `CACHE_DELETE`. New error codes: `INVALID_SPEC` (65), `HOST_BUSY` (74), `POLICY_DENIED` (77); new warnings are listed in `docs/man/errors.md`.

## Dimension prong (additive)

Protocol v1 additionally allowlists `dimension.probe`, `dimension.safezone`, and `dimension.conform`. No existing command schema is reinterpreted. `project.conform` remains the studio naming plan; it does not call Dimension.

- `dimension.probe`: no arguments. Runs `dimension --json catalog profiles`.
- `dimension.safezone`: required `spec` (preset id: letters, digits, `_`, `:`, `-`). Runs `dimension --json safe-zone plan --preset <spec>`.
- `dimension.conform`: required `path` (existing manifest file) and `spec` (preset id). Runs `dimension --json conform --source <path> --preset <spec>`.

The binary is `dimension` on `PATH`, or `MJ_DIMENSION_BIN` if that path is executable. Argument values stay canonical Base64. The engine is not given a shell; argv is fixed. A non-JSON stdout is `DIMENSION_RESULT_INVALID`. A missing binary is `UNSUPPORTED` (exit 69).
