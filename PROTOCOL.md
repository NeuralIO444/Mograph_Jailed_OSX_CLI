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
