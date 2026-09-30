# MographJailed
## Research + Project Architecture Plan

**Project:** MographJailed  
**CLI identity:** `mograph-jailed`  
**Role:** Zero-install native macOS capability layer for MJ applications.  
**Status:** the current development line carries 27 Protocol v1 operations: the `0.3.0-dev.2` SL-M2 FrameKit candidate, plus SL-M3 ImageStats (`image.stats`, `image.compare`; portable-complete, see `docs/releases/0.3.0-dev.3/QA_REPORT_SL_M3.md`) and the Tier 0 Observer (`project.ingest`, `expression.lint`, `plugin.audit`, `project.snapshot`; see `docs/TIER0_OBSERVER.md`). The target-Mac-qualified `0.3.0-dev.1` install remains the baseline until the `media.frame` target-Mac and After Effects child-process gates pass.

---

## 1. Project Charter

MographJailed is a standalone shared project that gives MJ tools safe, deterministic access to approved capabilities already present in macOS.

It is not an After Effects tool itself. After Effects tools such as MJ_AE_LOOPER consume it through a versioned protocol.

Primary consumers may include:

- MJ_AE_LOOPER
- MJ_Organize
- MJ_Brief
- future media/QC utilities
- future project/asset-management utilities

The project exists to prevent each MJ product from separately implementing shell quoting, filesystem inspection, media probing, hashing, temporary-file management, packaging, volume detection, and OS capability detection.

### Core product promise

> Provide a minimal, secure, local-only, zero-install macOS capability layer that degrades gracefully and never modifies production source media by default.

---

## 2. Hard Constraints

MographJailed must assume a locked-down corporate Mac.

No dependency on:

- administrator rights
- Homebrew or MacPorts
- Python
- pip
- Node/npm runtime
- FFmpeg
- OpenCV
- Docker
- Xcode
- Xcode Command Line Tools
- a daemon or LaunchAgent
- a local web server
- cloud processing
- internet access at runtime

Original source media is immutable unless a future explicitly approved command says otherwise. V1 contains no source mutation commands.

---

## 3. Research Conclusions

### 3.1 After Effects bridge

After Effects ExtendScript exposes `system.callSystem()`, which executes an OS command and returns command output. This is sufficient to create a bridge to a bundled macOS helper.

Important design implication: After Effects should never call arbitrary native utilities directly. It should call MographJailed through one adapter.

### 3.2 Shell runtime

macOS uses zsh as the default interactive shell. MographJailed should explicitly invoke `/bin/zsh` rather than depending on the user's configured shell or PATH.

The distributed helper does not need to rely on its executable permission bit if AE invokes it as:

`/bin/zsh <bundled-script> ...`

This improves portability on copied/network-delivered packages.

### 3.3 Native media utilities

`avmediainfo` is useful for track/sample-level inspection but is not universal across old macOS releases. It first appeared in macOS 11, so it must be capability-probed.

`avconvert` is useful for temporary derivatives/proxies, but it is not a general FFmpeg replacement and preserves only one video and one audio track during conversion. It must never be used as a source-preserving round-trip mechanism.

### 3.4 Structured data

`plutil` can create, validate, modify, and convert JSON/property-list data. It is a strong candidate for protocol construction/validation, but individual feature flags must still be probed because some `plutil` operations appeared in later macOS releases.

### 3.5 JXA / native frameworks

JavaScript for Automation can bridge to Objective-C frameworks, and AVFoundation can generate frames from video assets. This remains promising for advanced frame analysis.

However, JXA is inspected by XProtect, and application-to-application automation can involve macOS Automation privacy controls. Therefore JXA/AVFoundation is not part of the V1 core. It is an isolated research adapter that must earn promotion through testing.

### 3.6 AVFoundation frame analysis

AVFoundation's image generator can request images at times in a video, constrain output size, report the actual generated time, and use zero time tolerance for frame-accurate requests at increased decoding cost.

This validates the future direction for native frame sampling, but not yet the deployment mechanism from a locked-down AE environment.

---

## 4. Capability Classification

### CORE

Use after startup capability verification.

| Capability | Primary use |
|---|---|
| `/bin/zsh` | MographJailed runtime |
| `sw_vers` | macOS version/build |
| `stat` | filesystem facts |
| `file` | file/type inspection |
| `df` | available storage / filesystem facts |
| `mktemp` | private temporary workspace |
| `plutil` | structured data validation/conversion |
| `sips` | image metadata / bounded image operations |
| `ditto` | report/package copy and ZIP creation |
| `shasum` | SHA-256 identity when available |

### CORE BUT ADVISORY DATA

| Capability | Reason |
|---|---|
| `mdls` | useful metadata, but results can be null/incomplete and must not be treated as authoritative media truth |

### OPTIONAL MEDIA ADAPTERS

| Capability | Reason |
|---|---|
| `avmediainfo` | powerful track/sample timing inspection; macOS 11+ and must be probed |
| `avconvert` | temporary derivative/proxy generation only |
| `afinfo` | audio-file inspection |
| `afconvert` | optional temporary audio conversion |

### OPTIONAL SUPPORT ADAPTERS

| Capability | Reason |
|---|---|
| `mdfind` | Spotlight-backed relocation assistance; dependent on metadata index coverage |
| `xattr` read-only | provenance/extended metadata diagnostics only |

### LAB / EXPERIMENTAL

| Capability | Reason |
|---|---|
| `osascript -l JavaScript` / JXA | enterprise/security behavior must be validated |
| AVFoundation via JXA | potentially high-value frame extraction, not yet proven as deployment path |
| Core Image via JXA | potentially high-value comparison primitives, not yet proven |

### REJECT FOR CORE

- arbitrary shell execution exposed to product modules
- Finder/System Events automation
- terminal-window automation
- Python/Ruby/Perl as application runtimes
- downloaded executables
- background daemons
- installers

---

## 5. Architecture

```text
MJ applications
        |
        | MJ Native Protocol v1
        v
+-----------------------------+
| MographJailed Client Adapter  |
| (small adapter per product) |
+-------------+---------------+
              |
              | request file + fixed invocation
              v
+-----------------------------+
|      mograph-jailed.zsh        |
|  protocol / validation      |
|  capability registry        |
|  command router             |
+-------------+---------------+
              |
       +------+------+----------------+
       |             |                |
       v             v                v
   filesystem      media           system
   adapters        adapters        adapters
       |             |                |
       +-------------+----------------+
                     |
                     v
                macOS tools
```

### Critical separation

Product code requests capabilities such as:

- `file.inspect`
- `file.hash`
- `media.inspect`
- `media.timing`
- `volume.inspect`
- `system.probe`

Product code never requests:

- `shell.execute`
- `run.command`
- raw command strings

---

## 6. Request/Response Protocol

### Preferred request transport

Do not interpolate production filenames or project strings directly into a shell command.

Preferred sequence:

1. Product creates a MJ-owned temporary request file.
2. Request file contains the requested operation and all arguments.
3. AE invokes only the bundled MographJailed runner plus the safe request-file path.
4. MographJailed validates protocol version and operation allowlist.
5. MographJailed performs the operation.
6. It returns/writes a structured response envelope.

This confines shell quoting to a very small audited boundary.

### Response envelope

Every operation should return the same conceptual structure:

```text
protocol: MOGRAPHJAILED
protocolVersion: 1
cliVersion: x.y.z
requestId: ...
command: media.inspect
ok: true|false
data: {...}
warnings: [...]
error: null|{code,message,details}
```

### Error philosophy

- parse failure = failure
- unsupported capability = explicit `UNSUPPORTED`
- permission failure = explicit `PERMISSION_DENIED`
- missing source = explicit `NOT_FOUND`
- malformed media = explicit media error
- unexpected native output = failure, never guessed parsing

---

## 7. V0.1 Command Surface

Keep the first usable release narrow.

### `system.probe`

Detect:

- macOS version/build
- architecture
- MographJailed version
- availability of approved native tools
- optional adapters
- protocol features

### `system.doctor`

Produce a human-readable and machine-readable health report.

### `file.inspect`

Return safe file facts:

- exists
- regular file/directory
- size
- modification time
- readable
- writable hint (advisory; not proof of filesystem write success)
- basic type
- advisory metadata when available

### `file.hash`

SHA-256 identity.

Hashing is explicit, not silently performed for every file because large media can make it expensive.

### `media.inspect`

Aggregate only available sources and identify where each fact came from.

Possible facts:

- container/type
- duration when available
- dimensions when available
- metadata presence
- native parser availability
- warnings

Do not invent missing metadata.

### `media.timing`

V0.1 reserves this command but deliberately does **not** parse `avmediainfo` sample text into authoritative structured timing because Apple does not document a stable machine-readable schema for that output.

Current behavior:

- if `avmediainfo` is unavailable: return `UNSUPPORTED`;
- the default `media.inspect` path does not execute `avmediainfo`;
- if `avmediainfo` is available, `media.timing` still returns `UNSUPPORTED_STRUCTURED_OUTPUT` rather than parsing undocumented human output.

Structured sample timestamps, durations, cadence irregularities, and timing-gap analysis are deferred to a future adapter with a stable structured source (for example, a validated AVFoundation path).

### `volume.inspect`

Return:

- mount availability
- free space
- filesystem type when available
- local/network classification when confidently detectable
- read capability and advisory write hint

### `temp.create`

Create a unique MJ-owned temporary run directory using `mktemp`.

### `temp.clean`

Remove only a validated MJ-owned temporary directory.

No recursive deletion is permitted outside the MJ temp root.

---

## 8. V0.2 Candidate Surface

After V0.1 is hardened:

- `package.create`
- `image.inspect`
- `image.resize` for temporary derivatives
- `media.proxy`
- `asset.manifest`
- `cache.key`
- `cache.validate`
- `search.candidate` using Spotlight as advisory search

---

## 9. V0.3+ Research Surface

Do not commit to these until the native-framework spike succeeds.

- `media.frame`
- `media.sampleFrames`
- `image.compare`
- `media.seamCandidates`
- `media.temporalSignature`
- `media.motionContinuity`

These become the foundation for MJ_AE_LOOPER seam analysis.

---

## 10. Source Layout

Develop modularly and bundle for deployment.

```text
MographJailed/
|
+-- README.md
+-- ARCHITECTURE.md
+-- SECURITY.md
+-- PROTOCOL.md
+-- ROADMAP.md
+-- CHANGELOG.md
|
+-- src/
|   +-- cli/
|   |   +-- entry.zsh
|   +-- core/
|   |   +-- protocol.zsh
|   |   +-- errors.zsh
|   |   +-- capabilities.zsh
|   |   +-- paths.zsh
|   |   +-- temp.zsh
|   |   +-- logging.zsh
|   +-- modules/
|   |   +-- system.zsh
|   |   +-- file.zsh
|   |   +-- media.zsh
|   |   +-- volume.zsh
|   |   +-- package.zsh
|   |   +-- image.zsh
|   +-- adapters/
|       +-- sw_vers.zsh
|       +-- stat.zsh
|       +-- file.zsh
|       +-- df.zsh
|       +-- mdls.zsh
|       +-- shasum.zsh
|       +-- sips.zsh
|       +-- avmediainfo.zsh
|       +-- avconvert.zsh
|       +-- ditto.zsh
|
+-- research/
|   +-- jxa/
|   +-- avfoundation/
|   +-- coreimage/
|
+-- tests/
|   +-- protocol/
|   +-- paths/
|   +-- security/
|   +-- filesystem/
|   +-- media/
|   +-- fixtures/
|
+-- scripts/
|   +-- build.zsh
|   +-- test.zsh
|
+-- dist/
    +-- mograph-jailed.zsh
```

The deployed CLI should be one portable bundled zsh file where practical, while development source remains modular.

---

## 11. Security Model

### Command allowlist

Only compiled-in MJ operations can execute.

### Absolute native paths

Prefer known system paths rather than a user-controlled PATH. Capability probing records actual approved paths.

### No `eval`

Never use shell `eval` with project data, filenames, metadata, or protocol values.

### Untrusted inputs

Treat as hostile:

- filenames
- project names
- layer names
- metadata
- volume names
- request JSON

Test filenames containing:

- spaces
- apostrophes
- quotes
- semicolons
- dollar signs
- backticks
- command substitutions
- Unicode
- leading hyphens
- very long names

### Path validation

- canonicalize where safe
- use `--` where supported
- distinguish symlink from target
- never clean/delete outside MJ-owned temp roots
- never infer that a path is safe from its filename

### Environment normalization

Use a controlled environment for parsing where needed:

- known PATH or absolute utilities
- stable locale for machine parsing
- bounded output

### Original-media rule

V1 native media operations are read-only.

---

## 12. Blocking / Long-Running Work

`system.callSystem()` is conceptually synchronous from the JSX caller's perspective and should not become the mechanism for unbounded media work.

V0.1 commands should therefore be intentionally bounded.

Expensive operations such as hashing very large files or future frame analysis should evolve toward a job protocol:

```text
job.start
job.status
job.cancel
job.result
```

A job writes only inside MJ temporary storage and can be polled by the consumer. This prevents the architecture from depending on a permanently running service.

This should be designed early even if not implemented in the first spike.

---

## 13. Test Matrix

### Path safety

- ordinary local path
- spaces
- apostrophe
- double quote
- Unicode
- emoji
- semicolon
- `$()` sequence
- backticks
- leading dash
- very long path

### Filesystem

- local APFS
- removable volume
- SMB/network volume
- read-only file
- read-only folder
- missing file
- disconnected volume
- symlink

### Media

- ProRes MOV
- H.264 MOV/MP4
- HEVC
- audio-only file
- still image
- corrupt/truncated media
- VFR sample when available
- multi-track media
- large 4K file

### Capability degradation

Simulate or test:

- no `avmediainfo`
- no usable Spotlight metadata
- read permission denied
- temp creation failure
- unsupported codec
- malformed native-tool output

### Security

No test input may cause an unintended command to execute.

Add canary filenames containing command-like text and verify the filesystem is unchanged after every test.

---

## 14. Milestones

### M0 — Research Baseline

Complete.

Deliverables:

- project boundary
- capability classification
- core architecture
- JXA isolation decision
- initial security model

### M1 — Protocol + Capability Probe

Build:

- protocol envelope
- request validation
- capability registry
- `system.probe`
- `system.doctor`
- bundled build output

Exit criteria:

- valid machine-readable response
- no arbitrary shell execution
- path/security unit fixtures pass

### M2 — Filesystem Core

Build:

- `file.inspect`
- `file.hash`
- `volume.inspect`
- `temp.create`
- `temp.clean`

Exit criteria:

- local/network/read-only failure cases handled
- no source mutation
- cleanup cannot escape MJ temp root

### M3 — Media Core

Build:

- `media.inspect`
- optional `avmediainfo` adapter
- `media.timing`

Exit criteria:

- clear source attribution for returned metadata
- graceful behavior without optional media utility
- malformed media fails closed

### M4 — After Effects Integration Spike

Build a minimal AE client that:

1. probes MographJailed
2. submits a structured request
3. receives/parses a response
4. inspects one selected media file
5. displays diagnostics
6. verifies the source remains unchanged

Exit criteria:

- works without admin/install step
- paths with spaces/apostrophes/Unicode pass
- no surprise application Automation prompt

### M5 — Packaging + Tech Report Integration

Add:

- report bundle creation
- environment receipt
- native-capability section for MJ Tech Reports

### M6 — Native Media Lab

Research only:

- JXA execution behavior
- AVFoundation frame extraction
- Core Image comparison
- XProtect behavior
- TCC behavior
- network media
- current macOS versions

Decision gate:

Promote to supported adapter only if repeatable, safe, and no-install on target machines.

---

## 15. Acceptance Criteria for V0.1

V0.1 is complete when:

1. MographJailed runs from a copied project folder without an installer.
2. It requires no external runtime or package manager.
3. Every command produces a versioned structured response.
4. Unsupported capabilities are reported rather than guessed.
5. No public API accepts a raw shell command.
6. Production source files are read-only.
7. Temp cleanup is constrained to MJ-owned paths.
8. Hostile filename tests cannot trigger command execution.
9. `avmediainfo` absence does not break the core.
10. One AE JSX client can call the system through the protocol.
11. Tech diagnostics can explain exactly which native capabilities were used.
12. The bundled distribution remains generated from modular source.

---

## 16. First Engineering Work Package

Do not begin with media analysis.

Build the foundation in this order:

1. repository skeleton
2. protocol constants and error taxonomy
3. safe request-file loader
4. capability registry
5. `system.probe`
6. `system.doctor`
7. security/path fixtures
8. single-file bundler
9. smoke-test harness
10. AE integration stub

Only then add file/media adapters.

This order tests the hardest cross-cutting risks before product scope grows.

---

## 17. Decision Log

### D001 — Standalone project

**Decision:** MographJailed is its own project.  
**Reason:** multiple MJ applications can consume the same secure native capability layer.

### D002 — Shell target

**Decision:** zsh is the V1 implementation target.  
**Reason:** zero-install availability and direct fit for orchestrating native macOS commands.

### D003 — Modular source, single deployment

**Decision:** modular `.zsh` development source bundles into one portable `mograph-jailed.zsh` distribution where practical.

### D004 — Protocol, not shell access

**Decision:** applications consume named MJ operations through a versioned request/response protocol.

### D005 — Request file

**Decision:** production paths/data live inside a structured request file rather than being interpolated into a raw command line wherever practical.

### D006 — Capability-first

**Decision:** no optional utility is assumed. Features derive from startup capability detection.

### D007 — JXA isolated

**Decision:** JXA/AVFoundation/Core Image remain experimental until tested on managed production Macs.

### D008 — Fail closed

**Decision:** malformed, ambiguous, unsupported, or unexpectedly formatted native results return an error instead of inferred data.

---

## 18. Longer-Term Role

If V0.1 succeeds, MographJailed becomes the macOS abstraction layer for the broader MJ tool family:

```text
MJ_Brief --------+
MJ_Organize -----+
MJ_AE_LOOPER ----+---- MographJailed ---- macOS native capabilities
Future QC tools ---+
Future asset tools +
```

This is intentionally narrower than an MCP server or general automation framework. Its value comes from being small, deterministic, local, auditable, and reusable.

---

## Research Basis

Research for this plan used current documentation from:

- Adobe After Effects Scripting Guide (`System.callSystem`)
- Apple Terminal User Guide (zsh and shell scripting)
- Apple Platform Security (Terminal/script protections and JXA inspection)
- Apple macOS Automation privacy documentation
- Apple AVFoundation documentation (`AVAssetImageGenerator`)
- macOS manual pages for `avmediainfo`, `avconvert`, `mdls`, `plutil`, `sips`, `shasum`, `ditto`, `mktemp`, `df`, `xattr`, `mdfind`, `sw_vers`, and related native utilities


### D009 — `avmediainfo` is diagnostic evidence in V0.1

**Decision:** Do not parse `avmediainfo` human-readable sample text into authoritative structured timestamps in V0.1. The tool is capability-probed, but default media inspection does not execute it, but structured timing remains `UNSUPPORTED` until a documented/stable adapter is proven.  
**Reason:** The public manual documents the fields displayed but not a machine-readable schema. Guessing a parser conflicts with fail-closed behavior.


---

## NG-M1 Addendum — Capability Registry 2.0 + Runtime Trust

The 0.2 development line introduces self-describing operation metadata (`system.describe`) and bundled-runtime compatibility verification (`runtime.verify`). These features are additive to Protocol v1 and are intended to let consumers such as MJ_AE_LOOPER choose operations based on actual availability, cost, mutation scope, authority, and interactive-safety metadata instead of hardcoded platform assumptions.

---

## NG-M2 Addendum — Asset Intelligence

The 0.2 development line now adds conservative, reusable asset evidence primitives: single-file manifests/verification, advisory Spotlight candidate search, read-only provenance names, image inspection/derivatives, and storage preflight. These capabilities do not perform recursive project crawling, automatic relinking, source mutation, or background indexing. They are intended to supply evidence to MJ products while product-specific workflow decisions remain in the consuming application.

Promotion requires target-Mac validation of `mdfind`, `xattr`, and `sips` behavior on the managed production Mac, including paths with spaces/apostrophes/Unicode, APFS and SMB semantics where available, derivative non-overwrite/source-immutability checks, and Spotlight-disabled/partial-index behavior.


## dev.4 Terminal UX boundary

`mj-man` and `mj-top` are optional project-local protocol consumers. They are not bundled into `dist/mograph-jailed.zsh`, do not add a daemon/background service, and do not bypass MographJailed for evidence collection.

---

## Standard Library 1.0 Addendum — 0.3.0-dev.2

The next architecture step is an internal MJ-owned standard library rather than a larger collection of product-specific shell adapters.

### Purpose

Give MJ_Organize, MJ_AE_Looper, and later MJ products stable primitives without exposing the underlying macOS command/API directly.

```text
Product logic
    ↓
Protocol operation
    ↓
MJ Standard Library
    ↓
qualified stock macOS primitive
```

### Initial modules

- **LocalFS:** filesystem classification and fail-closed local-only guard.
- **NativeDB:** stock SQLite runtime/JSON/FTS5 capability layer. No arbitrary SQL request surface.
- **MediaProbe:** normalized, bounded native timing facts.
- **ImageKit:** reusable native image inspection primitives.
- **FrameKit:** implemented as the bounded `media.frame` dev.2 candidate; promotion remains gated on managed-Mac + AE-child qualification.

### D010 — bounded `avmediainfo` promotion

**Decision:** D009 remains correct for the default `media.inspect` path and for full sample-table parsing. However, after target-machine discovery demonstrated the native `avmediainfo` surface, 0.3 may parse a narrowly labeled, hard-bounded pre-sample header for the explicit `media.timing` command.

**Guardrails:**

- explicit operation only;
- local filesystem only;
- `--brief` must report zero analysis errors;
- parser captures no more than 256 header lines;
- sample rows are not enumerated;
- numeric fields are validated;
- unexpected shape fails with `NATIVE_OUTPUT_INVALID`;
- nominal FPS is labeled advisory-nominal rather than sample-truth.

### D011 — SQLite is an internal primitive, not a database API

**Decision:** qualify the stock `sqlite3` runtime as NativeDB but do not expose `db.query`, `sql.exec`, or user-supplied SQL.

**Reason:** SQLite is valuable for local receipts, indexes, caches, and FTS, but a generic SQL endpoint would widen the authority/safety surface unnecessarily. Product-specific schemas will be added only when a concrete Organize/Looper feature needs them.

### D012 — local-only Standard Library default

**Decision:** network volumes may be classified when an explicit caller path requires it, but Standard Library automatic work does not enumerate, test, cache to, index, create SQLite stores on, or mutate network volumes.

`media.timing` and the new `media.frame` operation enforce `executionScope=LOCAL_ONLY` directly.

### D013 — Ruby/Perl remain auxiliary

Target-machine qualification showed stock Ruby and Perl runtimes are functional, including JSON/digest/file I/O (and Perl regex). They may be used by isolated developer/QA utilities, but are not production dependencies. The production library remains zsh + fixed native adapters + SQLite/JXA only when explicitly promoted.
