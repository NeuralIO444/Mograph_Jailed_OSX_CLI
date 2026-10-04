# Error codes

Every failed request returns a JSON envelope with `"ok": false` and an `error` object:

```text
{ "ok": false, "error": { "code": "OUTPUT_EXISTS", "message": "…" }, … }
```

`code` is stable and safe to branch on; `message` is for people and may change. The process exit code groups failures the same way:

| Exit | Meaning |
|---|---|
| 0 | success |
| 64 | wrong command-line usage |
| 65 | the request or its arguments were not acceptable |
| 66 | something you named was not found (or the store is empty) |
| 69 | this Mac cannot do it (missing tool or capability) |
| 73 | a problem with where the output goes |
| 74 | the operation ran and failed |
| 77 | permission denied |

The exit column is what the shell layer returns. A code detected inside an operation's Python engine (for example a bad `range`, or `STORE_EMPTY` from `trace.asset`) exits 74 even when the same code exits 65 or 66 elsewhere, so branch on the `code` field, not the exit number, when precision matters. The exception is a scrape or receipt that is invalid JSON, too large, or the wrong schema: those are always 65, from every operation that reads one.

No failure ever leaves a half-written result behind: outputs are staged and published only when complete, and sources are never changed.

89 codes. Run `mj ops` for what each operation accepts.

## Your request

The request file or its arguments were not acceptable. Nothing ran.

| Code | Exit | What it means | What to do |
|---|---|---|---|
| `USAGE` | 64 | The runtime was started with the wrong arguments. | Use `--request <file>`, or `--help`. |
| `REQUEST_NOT_FOUND` | 65 | The request file does not exist. | Check the path passed to `--request`. |
| `REQUEST_TOO_LARGE` | 65 | The request has too many lines or a line/argument that is too long. | Requests are small by design; send fewer or shorter arguments. |
| `BAD_REQUEST_VERSION` | 65 | The first line is not `MOGRAPHJAILED_REQUEST 1`. | Use the request format in `mj-man protocol`. |
| `MALFORMED_REQUEST` | 65 | A line is not `name=value`, or has an unknown field. | Fix the request file; see `mj-man protocol`. |
| `DUPLICATE_FIELD` | 65 | `requestId`, `command` or an argument appears twice. | Send each field once. |
| `MISSING_FIELD` | 65 | `requestId` or `command` is missing. | Add the missing line. |
| `INVALID_REQUEST_ID` | 65 | `requestId` has unsupported characters or is over 128 characters. | Use letters, digits and `. _ : -` only. |
| `UNSUPPORTED_COMMAND` | 65 | The command is not on the allowlist. | Run `mj ops` for the real list. |
| `UNEXPECTED_ARGUMENT` | 65 | The command does not accept that argument. | Run `mj ops` to see allowed arguments. |
| `MISSING_ARGUMENT` | 65 | A required argument is missing or empty. | Run `mj ops`; required arguments are marked `*`. |
| `INVALID_ARGUMENT` | 65 | An argument has a bad value: wrong type, out of range, not allowed, or a name that is not allowlisted. | Read the message; it names the argument and the allowed range. |
| `INVALID_ARGUMENT_ENCODING` | 65 | An argument is not valid Base64. | `mj` encodes for you; if you build requests yourself, Base64 every value. |
| `INVALID_PATH` | 65 | A path is not absolute (or is empty). | Pass a full path starting with `/`. |
| `INVALID_TARGET` | 65 | The path exists but is the wrong kind of thing (a folder instead of a file, the wrong extension, not a recognized image). | Check the file type the operation expects; the message says which. |
| `INVALID_OUTPUT` | 65 | The output path is not usable (not absolute, empty, or not a supported name). | Give an absolute path in an existing, writable folder. |
| `PERMISSION_DENIED` | 77 | macOS will not let this user read the file or folder. | Check permissions, or grant Terminal access under Privacy & Security. |
| `NOT_FOUND` | 66 | The path (or label/version) does not exist. | Check spelling and that drives are mounted. |

## This Mac

The runtime refused because of what is or is not available. Nothing was changed.

| Code | Exit | What it means | What to do |
|---|---|---|---|
| `UNSUPPORTED` | 69 | A needed stock macOS tool or capability is missing (message names it). | Run `system.doctor`. For `python3`, see the README runtime requirements. |
| `NOT_IMPLEMENTED` | 69 | The command is recognized but not built into this runtime. | Update to a newer runtime. |
| `DECODE_UNSUPPORTED` | 69 | macOS cannot decode the selected video track. | Use a codec macOS supports, or transcode the media. |
| `NETWORK_SCOPE_BLOCKED` | 73 | The path is on a network volume; this operation is local-only. | Copy the file to a local drive. |
| `STORAGE_SCOPE_UNKNOWN` | 73 | The drive type could not be identified as local, so the operation fails closed. | Use a path on the internal drive or a standard local volume. |
| `HOST_NOT_FOUND` | 65 | No supported After Effects or Cinema 4D (2024 or newer, with its command-line tools) is installed. | Run `mj host.detect`; check the `version` argument. |
| `LICENCE_NOT_CONFIGURED` | 74 | The host asked which licence to use. MographJailed never answers that prompt. | Run the host's command line once by hand to set up licensing, then retry. |

## Output problems

Where the result was supposed to go. The source was not touched.

| Code | Exit | What it means | What to do |
|---|---|---|---|
| `FILE_EMPTY` | 65 | A project or scene is 0 bytes. This is what a Dropbox or iCloud file looks like before it has downloaded. | Open it once or make it available offline, wait for the download, then try again. Nothing was saved. |
| `FILE_NOT_DOWNLOADED` | 74 | The file is stored online only (macOS marks it "dataless"), so its bytes are not on this Mac. Reading it would start a download. | Make it available offline in Dropbox, iCloud or your sync app, wait for it to finish, then try again. |
| `OUTPUT_EXISTS` | 73 | The destination already exists; MographJailed never overwrites. | Choose a different name or folder. |
| `OUTPUT_UNAVAILABLE` | 73 | The output folder is missing, not writable, or on unsuitable storage. | Create it, fix its permissions, or use a local folder. |
| `INSUFFICIENT_SPACE` | 74 | Not enough free disk space for the handoff. | Free space or pick another drive; the message gives the size needed. |
| `TEMP_UNAVAILABLE` | 73 | The temporary folder is missing, unusable, or has odd characters in its path. | Check `TMPDIR`; use a plain local path. |
| `TEMP_CREATE_FAILED` | 73 | A private working folder could not be created. | Check free space and permissions on the temporary folder. |
| `TEMP_REFUSED` | 77 | `temp.clean` refused to delete a folder it cannot prove it created. | Nothing to do; only folders made by `temp.create` can be cleaned. |
| `TEMP_CLEAN_FAILED` | 74 | A MographJailed temporary folder could not be removed. | Delete it yourself if it is stale. |
| `STAGE_CLEANUP_REFUSED` | 74 | An operation failed and its staging folder could not be proven safe to delete, so it was left in place. | Inspect the folder named in the message and remove it by hand. |

## A file changed or could not be read reliably

The runtime protects the evidence it reports.

| Code | Exit | What it means | What to do |
|---|---|---|---|
| `SOURCE_CHANGED` | 74 | The file changed while it was being hashed or processed. | Wait until the file is no longer being written, then retry. |
| `SOURCE_STATE_UNAVAILABLE` | 74 | The file's size/time identity could not be established. | Check the file still exists and is readable. |
| `HASH_FAILED` | 74 | SHA-256 could not be calculated. | Check the file is readable and `shasum` works. |
| `NATIVE_OUTPUT_INVALID` | 74 | A macOS tool returned output the runtime did not expect. | Report it with the macOS version; nothing was changed. |
| `PROVENANCE_READ_FAILED` | 74 | Extended-attribute names could not be read. | Check permissions on the file. |
| `RUNTIME_PATH_UNAVAILABLE` | 74 | The runtime could not work out where it is installed. | Run it by its full path. |
| `SEARCH_FAILED` | 74 | Spotlight search failed or is off for that location. | Check Spotlight indexing for the folder. |

## Images, media and packages

| Code | Exit | What it means | What to do |
|---|---|---|---|
| `IMAGE_DERIVATIVE_FAILED` | 74 | macOS could not create the smaller image copy. | Check the image opens in Preview; retry. |
| `STATS_FAILED` | 74 | Image signatures could not be computed (bad or unsupported PNG). | Use 8- or 16-bit RGB/RGBA, non-interlaced PNGs. |
| `DECODE_FAILED` | 74 | A PNG frame could not be decoded; the message names the frame. | Re-render or remove the damaged frame. |
| `COMPARE_FAILED` | 74 | Two image signatures could not be compared. | Retry; check both images with `image.inspect`. |
| `INVALID_SPEC` | 65 | A delivery or studio spec is not readable `key = value` text, or uses an unknown key or an invalid value. | Fix the line named in the message; see `docs/man/qc.md` or `docs/man/studio.md` for the keys. |
| `NO_VIDEO_TRACK` | 65 | The media has no video track. | Choose a file with video. |
| `TIME_OUT_OF_RANGE` | 65 | The requested time is outside the media duration. | Use a time inside the clip. |
| `FRAME_EXTRACTION_FAILED` | 74 | A frame could not be extracted; the message may name an adapter detail (see the last section). | Try another time, or check the media plays in QuickTime. |
| `FRAME_VALIDATION_FAILED` | 74 | The extracted PNG did not match the frame macOS reported. | Retry; report if it repeats. |
| `FRAME_SCALE_FAILED` | 74 | The frame could not be scaled to the size limit. | Retry with a larger `maxPixels`. |
| `FRAME_PUBLISH_FAILED` | 74 | The frame could not be written without overwriting. | Choose a new output name. |
| `PACKAGE_FAILED` | 74 | The ZIP could not be created. | Check free space and that the output folder is writable. |

## Project files, snapshots and handoffs

| Code | Exit | What it means | What to do |
|---|---|---|---|
| `INVALID_JSON` | 65 | A scrape or receipt is not valid JSON. | Re-run the scraper; do not edit receipts by hand. |
| `SCHEMA_MISMATCH` | 65 | A scrape is not an `MJ_PROJECT_SCRAPE_1` document or is missing required parts. | Re-scrape with the current scraper. |
| `SCRAPE_TOO_LARGE` | 65 | The scrape exceeds the size limit (8 MB). | Scrape a smaller project, or split it. |
| `READ_FAILED` | 74 | A file could not be read. | Check it exists and is readable. |
| `INGEST_FAILED` | 74 | The scrape summarizer failed to run. | Run `system.doctor`; confirm `python3` works. |
| `LINT_FAILED` | 74 | The expression linter failed to run. | Run `system.doctor`; confirm `python3` works. |
| `SNAPSHOT_FAILED` | 74 | The project could not be copied or published. | Check free space and permissions in the versions folder. |
| `SNAPSHOT_UNSTABLE` | 74 | The project changed while it was being copied, so no snapshot was kept. | Normal while After Effects is saving; the watcher retries on the next save. |
| `SNAPSHOT_CORRUPT` | 74 | A snapshot no longer matches its receipt; restore refused. | Do not use that snapshot; restore an earlier one. |
| `RESTORE_FAILED` | 74 | The restored copy could not be written or did not verify. | Check free space; retry. |
| `HANDOFF_FAILED` | 74 | The handoff folder could not be built; the partial folder was removed. | Read the message; usually space or permissions. |
| `TOO_MANY_FILES` | 74 | Too many files for one call (handoff or `index.add`). | Index a narrower folder. |
| `INVALID_RECEIPT` | 74 | A receipt is not the expected kind (for example not an `MJ_GOLDEN_1` record). | Pass the right file. |

## Frames, loops and golden records

| Code | Exit | What it means | What to do |
|---|---|---|---|
| `INSUFFICIENT_FRAMES` | 74 | Not enough PNG frames in the folder for this operation. | `loop.seams` needs at least 3 frames; `golden.record` at least 1. |
| `TOO_MANY_FRAMES` | 74 | More than 2,000 frames in the folder. | Work on a shorter range or split the folder. |

## Renders

Details are in `render.json` and `render.log` in the render folder.

| Code | Exit | What it means | What to do |
|---|---|---|---|
| `HOST_BUSY` | 74 | The app that owns a cache is running, so `cache.clean` did not delete anything. | Quit the app named in the message and try again. |
| `POLICY_DENIED` | 77 | The tool will not do this by design (for example emptying a cache the app manages itself). | Use the app's own setting named in the message. |
| `RENDER_BUSY` | 74 | Another render is running; renders run one at a time. | Wait for it, or check `mj status`. |
| `RENDER_FAILED` | 74 | The host exited with an error. | Read `errorTail` in `render.json` and `render.log`. |
| `RENDER_INCOMPLETE` | 74 | The host finished but fewer frames exist than expected. If it produced none and said nothing, it was probably waiting on a dialog (sign-in, project conversion, script permissions). | Open the application once by hand and clear any prompt; check the comp/scene range and the log; re-render. |
| `RENDER_TIMEOUT` | 74 | The render hit its time limit and was stopped. | Raise `timeoutSeconds` or render a shorter range. |

## Library, index and presets

| Code | Exit | What it means | What to do |
|---|---|---|---|
| `STORE_EMPTY` | 66 | Nothing has been indexed yet. | Run `mj index.add path=<receipts>` first. |
| `STORE_TOO_NEW` | 74 | The store was made by a newer MographJailed. | Update this runtime; do not downgrade the store. |
| `STORE_UNAVAILABLE` | 73 | The store folder cannot be created or used. | Check `MJ_STORE_DIR`, permissions, and that it is on a local drive. |
| `PRESET_TOO_LARGE` | 74 | Presets are limited to 512 MB. | Store a smaller file. |
| `PRESET_FAILED` | 74 | The stored copy of a preset did not verify. | Retry; check free space. |
| `PRESET_CORRUPT` | 74 | A stored preset's bytes no longer match their hash. | Run `mj index.verify`; re-add the preset from its source. |
| `CONFLICT` | 74 | Another process wrote the same thing at the same moment. | Retry. |

## FrameKit adapter details

These appear inside the message of `FRAME_EXTRACTION_FAILED`, not as the error code itself.

| Code | Exit | What it means | What to do |
|---|---|---|---|
| `INVALID_SOURCE` | 74 | The adapter was given no source path. | Internal; report it. |
| `INVALID_TIME` | 74 | The adapter was given no time. | Internal; report it. |
| `INVALID_FLOOR_TIME` | 74 | The adapter was given no frame-floor time. | Internal; report it. |
| `ASSET_OPEN_FAILED` | 74 | macOS could not open the media file. | Check the file plays in QuickTime. |
| `NO_VIDEO_TRACK_ADAPTER` | 74 | The asset has no video track. | Choose a file with video. |
| `GENERATOR_FAILED` | 74 | AVFoundation could not create its frame generator. | Check the media and macOS version. |
| `FRAME_GENERATION_FAILED` | 74 | AVFoundation returned no image for that exact time. | Try a nearby time. |
| `FRAME_RESULT_INVALID` | 74 | AVFoundation returned invalid dimensions. | Retry; report if it repeats. |
| `PNG_ENCODE_FAILED` | 74 | ImageIO could not create the PNG. | Check free space. |
| `PNG_WRITE_FAILED` | 74 | The PNG file could not be written. | Check the output folder. |
| `BRIDGE_LOAD_FAILED` | 74 | System frameworks could not be loaded. | Report with the macOS version. |
| `PYCTYPES_EXCEPTION` | 74 | The Python/ctypes bridge failed. | Report with the macOS version. |

## Warnings

A successful response can still carry `warnings`: a list of `{ "code", "message" }`. A warning means the result is correct but incomplete or needs attention; it never fails the request. `"warnings": []` means nothing to report.

| Code | What it means | What to do |
|---|---|---|
| `COMPS_TRUNCATED` | The scrape holds only the first comps of a larger project. | Counts are lower bounds. |
| `LAYERS_TRUNCATED` | Some comps have more layers than the scraper records. | Layer counts for those comps are lower bounds. |
| `FOOTAGE_TRUNCATED` | The scrape holds only the first footage items of a larger project. | Footage lists are partial. |
| `FOOTAGE_MISSING` | Footage items are marked missing. | Relink in After Effects, or see `trace.asset format=missing`. |
| `FINDINGS_TRUNCATED` | `expression.lint` found more issues than it lists. | Fix the listed ones and run it again. |
| `ENTRY_LIMIT_REACHED` | `plugin.audit` stopped at its entry limit. | Audit sub-folders separately. |
| `FILE_TOO_LARGE_TO_HASH` | Plug-in files over 2 GB were listed without a SHA-256. | Hash them with `file.hash` if you need to. |
| `MISSING_FOOTAGE` | Footage files that a project uses are missing. | Find or relink them before delivery. |
| `FOOTAGE_UNVERIFIED` | Footage on network or unknown storage was not checked. | Check those files by hand. |
| `FOOTAGE_NOT_COLLECTED` | Footage on network or unknown storage was not copied into the handoff. | Copy it separately. |
| `PROJECT_SCRAPE_MISMATCH` | 65 | The scrape was made from a different project than the `.aep` given (compared by full path), or `handoff.package` was given a scrape of a differently named project. | Scrape this project again (`mj scrape` or the After Effects script) so comp ids and layer numbers match. |
| `FILES_UNREADABLE` | Some receipts could not be indexed. | See `problems` in the result. |
| `RESULTS_TRUNCATED` | More results exist than were returned. | Raise `maxResults` or narrow the query. |
| `STALE_RECEIPTS` | Indexed receipts no longer exist on disk. | Re-run `index.add` on the current folder. |
| `PRESET_BLOB_CORRUPT` | Stored presets failed their hash check. | Re-add them from their source files. |
| `EXTRA_FRAMES` | Frames not in the golden record were not checked. | Record a new golden set if they belong. |
| `DIFFERENT_PROJECTS` | The two scrapes compared by `project.diff` come from different project paths. | Check you passed two versions of the same project. |
| `SCRAPES_OUT_OF_ORDER` | The first scrape is newer than the second. | Swap the arguments to read the diff in time order. |
| `CHANGES_TRUNCATED` | `project.diff` found more changes than it lists. | The summary counts are complete; narrow the comparison. |
| `TEXTURES_MISSING` | Textures a Cinema 4D scene points at are not on disk. | See `mj scene`; relink or collect assets. |
| `SCENE_TRUNCATED` | The scene held more textures, materials or cameras than the scraper records. | Counts are lower bounds. |
| `NO_MATCHING_LAYER` | No layer in the After Effects project uses the Cinema 4D scene being checked. | Check the scene and project are the right pair; the layer's source must be that `.c4d` file. |
| `FONT_REPORT_UNAVAILABLE` | The scrape has no After Effects missing-font report (scraper before 1.1, or After Effects before 24.0). | Font status comes from scanning this Mac's font folders; a font manager may provide fonts it cannot see. Re-scrape with scraper 1.1 for After Effects' own answer. |
| `FONT_SCAN_CAPPED` | The font scan stopped at its file limit. | Some installed fonts may not have been seen. |
| `CACHE_PARTLY_CLEANED` | Some entries in a cache folder could not be removed. | They are listed in `problems`; check permissions or quit the app and run it again. |
| `PEAK_IS_SAMPLE_PEAK` | The peak check uses the sample peak, not a 4x-oversampled true peak. | Leave about 0.5 dB of extra headroom on bright material. |
| `DUPLICATE_SPEC_KEY` | A delivery or studio spec sets the same key more than once. | The last value is used; check the two line numbers in the warning and remove the duplicate. |
| `SCRAPE_TOO_OLD` | The scrape comes from scraper 1.0, which does not record labels, folders, solids or adjustment layers. | Only names and expressions are planned; re-scrape with scraper 1.1 for the rest. |
| `SCRAPE_TRUNCATED` | The scrape hit its comp or layer limits. | Comps or layers past the limits are not in the plan. |
| `DYNAMIC_REFERENCES` | Some expressions look layers or comps up by a computed name. | Those references cannot be followed when renaming; check them after the job runs. |
| `EXTERNAL_REFERENCES` | Expressions in the comps being extracted refer to comps that will not be in the new project. | Add those comps to the extract, or fix the expressions afterwards (`externalReferences` lists them). |
| `REPORT_OLDER_THAN_PROJECT` | The project was saved after the report was made, so the report describes an older version of it. | Run the After Effects script on the project again. `mj check` will not call it ready until you do. |
| `NAME_TOO_LONG` | A comp or layer name is longer than After Effects allows (255 characters), so it did not come from After Effects. | It is left out of the conform plan and never renamed; check how the report was made. |
| `NOTHING_TO_DO` | The project already matches the studio spec. | No job was made. |
| `SOURCE_CHANGED_DURING_RENDER` | The project or scene changed while rendering. | The frames may mix two versions; re-render. |
