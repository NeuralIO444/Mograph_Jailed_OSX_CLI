# MographJailed — Next-Generation Research & Product Roadmap

**Project:** MographJailed  
**Baseline:** 0.1.0-rc3  
**Planning date:** 2026-09-21  
**Purpose:** Expand MographJailed from a hardened zero-install macOS capability layer into a reusable local media/asset intelligence library without weakening its production-machine safety model.

> **2026-09-22 implementation status:** Standard Library 1.0 / `0.3.0-dev.2` now includes the FrameKit qualification candidate. `media.frame` is implemented as a fixed local-only JXA/AVFoundation derivative operation, but the qualified dev.1 install remains the baseline until target-Mac and After Effects child-process gates pass. The original roadmap below is retained as the research record.

---

## 1. Executive Direction

MographJailed should not become a general shell toolkit. Its next generation should become a **small, auditable local capability and evidence engine** for MJ applications.

The product boundary remains:

```text
MographJailed
= safe machine / filesystem / media evidence and deterministic primitives

MJ_AE_LOOPER / Organize / Brief
= product-specific decisions and workflow logic
```

The next generation should focus on four reusable capability families:

1. **Runtime Trust & Capability Discovery**
2. **Asset Intelligence**
3. **Image / Media Intelligence**
4. **Production Resilience & Diagnostics**

Advanced macOS frameworks remain behind an explicit lab gate until they are proven on the managed production Mac.

---

## 2. Research Roles / Findings

### Research Agent A — Stock macOS capability surface

High-value native components already present or strongly supported by macOS include:

- `mdfind` / `mdls` — Spotlight-backed search and metadata
- `sips` — image inspection, resizing, color/profile operations, and Apple-provided JavaScript execution
- `xattr` — read-only extended-attribute / quarantine diagnostics
- `afinfo` / `afconvert` — audio inspection and temporary derivatives
- `system_profiler -json` — targeted hardware/software diagnostics with a timeout and a `mini` detail level
- `scutil -r` — advisory network reachability
- `ditto` — packaging
- `textutil` — optional text/report conversion
- `caffeinate` — explicit opt-in sleep prevention for long operations

Tools deliberately not selected as core dependencies:

- `networkQuality` — performs an Internet test and therefore violates the default local/offline posture
- `qlmanage` — useful for experiments, but documented as a Quick Look debug/management utility rather than a preferred production API
- `diskutil` — powerful but unnecessary for normal MJ operations; retain as diagnostic-only research if `df -Y` proves insufficient

### Research Agent B — Native image/media intelligence

Apple provides several promising zero-install primitives:

- `sips --js` can execute JavaScript in the Scriptable Image Processing System and exposes image/Canvas-style operations.
- Core Image provides reduction filters such as area average, histogram, min/max, row/column averages, and k-means color extraction.
- AVFoundation `AVAssetImageGenerator` can extract images at requested media times and reports the actual generated time; pending requests can be cancelled.
- Vision `VNGenerateImageFeaturePrintRequest` produces feature prints and `VNFeaturePrintObservation` can compute distance between images.

These are high-value for Looper, asset deduplication, preview generation, visual QC, and image similarity, but framework access through JXA remains a lab capability until target-Mac behavior is qualified.

### Planning Agent — Product architecture

The existing protocol is strong enough to expand additively. New command names and additive response fields do not require a protocol-version bump as long as existing command semantics remain unchanged.

The next architecture should introduce **operation-level capability metadata** before adding heavyweight features.

### Safety / Reliability Agent

Advanced features create three new risks:

- synchronous AE blocking;
- network-volume stalls;
- accidental promotion of advisory evidence into authoritative facts.

Therefore all new operations should declare and enforce:

```text
availability
costClass
mutationClass
networkClass
privacyClass
dataAuthority
bounded / unbounded behavior
```

No advanced feature should silently execute during a fast `media.inspect` or normal AE Analyze action.

---

# 3. Capability Registry 2.0 — Build First

## Goal

Make MographJailed self-describing so consumers can safely select operations.

### Proposed command

```text
system.describe
```

Example response concept:

```json
{
  "protocolVersion": 1,
  "cliVersion": "0.2.0",
  "operations": {
    "media.inspect": {
      "available": true,
      "costClass": "FAST",
      "mutationClass": "READ_ONLY",
      "networkClass": "PATH_DEPENDENT",
      "dataAuthority": "ADVISORY",
      "interactiveSafe": true
    },
    "file.hash": {
      "available": true,
      "costClass": "HEAVY_BY_SIZE",
      "mutationClass": "READ_ONLY",
      "dataAuthority": "AUTHORITATIVE_BYTES",
      "interactiveSafe": false
    }
  }
}
```

## Recommended classifications

### Cost

```text
FAST
BOUNDED
HEAVY
EXPLICIT_ONLY
```

### Mutation

```text
READ_ONLY
TEMP_ONLY
OUTPUT_CREATE
SOURCE_MUTATION
```

`SOURCE_MUTATION` should remain empty for the foreseeable roadmap.

### Data authority

```text
AUTHORITATIVE
ADVISORY
DERIVED
EXPERIMENTAL
```

### Network behavior

```text
NONE
PATH_DEPENDENT
NETWORK_ACCESS
INTERNET_ACCESS
```

Default MJ production operations should never have `INTERNET_ACCESS`.

## Why this matters

Looper can ask whether an operation is safe before calling it instead of maintaining hardcoded knowledge of Native internals.

---

# 4. Next-Generation Tool Family A — Runtime Trust

## A1. `runtime.verify`

Purpose: verify that the bundled MographJailed runtime matches the product manifest that shipped with Looper/Organize.

Potential checks:

- CLI version
- protocol version
- expected SHA-256
- expected runtime filename
- required operation availability

Primary value:

- catches damaged/copied/partial runtime bundles;
- gives Tech Reports a deterministic runtime-trust statement;
- improves team deployment without requiring a shared install.

Classification: **BUILD NOW**

---

## A2. `system.describe`

Purpose: expose the supported operation registry and safety metadata.

Classification: **BUILD NOW / foundational**

---

## A3. `system.snapshot`

Use a targeted, privacy-minimal `system_profiler -json` diagnostic snapshot with a fixed timeout.

Potential data:

- OS / architecture
- graphics hardware class if materially useful
- storage/network adapter summaries only when needed

Rules:

- diagnostic only;
- never collect serial numbers / hardware UUIDs by default;
- targeted data types only;
- fixed short timeout;
- redact before report export.

Classification: **DIAGNOSTIC ONLY**

---

# 5. Next-Generation Tool Family B — Asset Intelligence

## B1. `asset.manifest`

Create a deterministic inventory of a directory without altering it.

### Quick mode

Collect:

```text
relative path
file/directory type
size
mtime
basic content type
```

No hashes by default.

### Deep mode

Explicit opt-in:

```text
SHA-256
selected metadata
```

### Uses

- project packaging QC;
- before/after validation;
- asset inventory;
- missing-file investigation;
- cache identity;
- detecting unintended source changes.

Classification: **BUILD NOW**

---

## B2. `asset.verify`

Compare a stored manifest against the current folder state.

Return categories such as:

```text
UNCHANGED
ADDED
MISSING
SIZE_CHANGED
MTIME_CHANGED
HASH_CHANGED
UNKNOWN
```

Do not mutate or repair.

Classification: **BUILD AFTER manifest**

---

## B3. `search.candidate`

Use Spotlight (`mdfind`) as an advisory missing-asset locator.

Workflow:

```text
missing filename / facts
        ↓
mdfind -onlyin / -name
        ↓
candidate paths
        ↓
file.inspect / media.inspect
        ↓
optional explicit hash verification
        ↓
ranked evidence
```

Important:

- Spotlight results are advisory and may be incomplete;
- no automatic relinking;
- network-volume indexing may be incomplete or absent;
- return evidence, not a decision.

Classification: **BUILD NOW**

---

## B4. `file.provenance`

Read-only `xattr` inspection.

Potential outputs:

```text
hasExtendedAttributes
quarantinePresent
attributeNames
```

Do not automatically clear quarantine or modify attributes.

Use case: diagnose why a bundled script/package behaves differently after download/copy.

Classification: **BUILD NOW / diagnostics**

---

# 6. Next-Generation Tool Family C — Image Intelligence

## C1. `image.inspect`

Use `sips` to provide structured image facts:

```text
pixelWidth
pixelHeight
format
colorSpace
samplesPerPixel
bitsPerSample
hasAlpha
ICC/profile information
```

This should be distinct from generic `file.inspect`.

Classification: **BUILD NOW**

---

## C2. `image.derivative`

Create a bounded temporary derivative using `sips`.

Examples:

```text
thumbnail
analysis proxy
bounded max dimension
format conversion for temp analysis
```

Rules:

- output only inside MJ temp workspace unless an explicit output path is approved;
- never overwrite source;
- no metadata promises beyond what is explicitly documented;
- output-create semantics declared in `system.describe`.

Classification: **BUILD NOW**

---

## C3. `image.stats` — sips JavaScript Lab

Research whether `sips --js` can safely provide deterministic image statistics using its Canvas/Image APIs.

Target measurements:

```text
mean RGBA
luminance mean
small color histogram
RMS pixel difference
edge / gradient approximation
alpha coverage
```

Why this is attractive:

- stock macOS;
- avoids Python/OpenCV;
- potentially avoids JXA/OpenScripting/XProtect concerns;
- highly reusable for visual QC and Looper.

Promotion gate:

- stable output on target Mac;
- bounded memory/time;
- no source mutation;
- deterministic results across repeated runs;
- verified behavior for PNG/JPEG/TIFF/PSD-derived temp images.

Classification: **HIGH-PRIORITY LAB**

---

## C4. `image.compare`

If `image.stats` succeeds, expose a generic comparison primitive.

Possible response:

```text
pixelRms
luminanceDelta
averageColorDelta
histogramDistance
alphaDelta
```

MographJailed returns metrics only.

It does not say:

```text
"these are the same creative"
"this is the best loop seam"
```

Those decisions belong to the consumer.

Classification: **BUILD AFTER LAB PROOF**

---

# 7. Next-Generation Tool Family D — Media Intelligence

## D1. `media.frame` — AVFoundation Lab

Extract one frame at a requested time using AVFoundation.

Return both:

```text
requestedTime
actualTime
```

plus a temporary derivative path and dimensions.

Critical because requested and actual extraction times can differ.

Classification: **HIGH-PRIORITY LAB**

---

## D2. `media.frames`

Bounded frame sampling at a supplied list or interval of times.

Requirements:

- maximum sample count;
- maximum output dimension;
- cancellation/timeout strategy;
- temporary workspace only;
- requested + actual timestamps;
- never decode the entire media file by default.

Classification: **LAB → production only after D1**

---

## D3. `media.timing` v2

Replace the current deliberately unsupported structured timing path with AVFoundation/Core Media evidence rather than parsing undocumented `avmediainfo` human output.

Potential outputs:

```text
asset duration
track timescale
nominal frame rate when meaningful
sample cadence evidence
requested/actual frame-time tests
VFR evidence
```

Do not overstate nominal frame rate as exact sample cadence.

Classification: **HIGH VALUE / AFTER FRAME LAB**

---

## D4. `media.compareFrames`

Generic metrics between extracted frames.

Potential Looper use:

```text
frame A ↔ frame B
frame A-1 ↔ frame B-1
frame A+1 ↔ frame B+1
```

Native returns similarity/motion evidence; Looper decides whether that evidence supports a seam.

Classification: **BUILD AFTER image.compare + media.frames**

---

# 8. Next-Generation Tool Family E — Perceptual Intelligence

## E1. Vision framework probe

Basic JXA execution with Foundation has already been proven on the target Mac during MJ terminal setup. This does **not** yet prove AVFoundation, Core Image, or Vision production viability.

Create an isolated framework probe for:

```text
Foundation
AVFoundation
CoreImage
Vision
```

No product command should depend on it until qualification passes.

Classification: **LAB**

---

## E2. `image.featurePrint`

Use Vision `VNGenerateImageFeaturePrintRequest` to generate an Apple-native perceptual feature representation.

Do not expose raw implementation assumptions as a universal identity fingerprint.

Return:

```text
framework revision
feature type / metadata
operation success
```

Classification: **LAB**

---

## E3. `image.similarity`

Use Vision feature-print distance to compare images perceptually.

Useful for:

- relocated/renamed asset candidates;
- visually similar source detection;
- scene-level matching;
- coarse filtering before pixel-accurate comparison;
- Looper candidate-frame pruning.

Important: perceptual similarity is not pixel equality.

Classification: **HIGH-VALUE LAB**

---

# 9. Next-Generation Tool Family F — Storage & Network Resilience

## F1. `storage.preflight`

Extend current `volume.inspect` into a consumer-friendly preflight primitive.

Potential data:

```text
local/network classification
filesystem type
free space
readability
writable hint
source path existence
mount state
```

No writes are needed to perform basic preflight.

Classification: **BUILD NOW**

---

## F2. `network.reachability`

Optional advisory `scutil -r` check for an explicitly supplied host.

This reports routing/reachability evidence; it is not proof that an SMB file operation will succeed.

Do not derive or contact arbitrary Internet targets automatically.

Classification: **OPTIONAL DIAGNOSTIC**

---

## F3. Bounded Operation Engine

This is a core architectural requirement before expensive network/media commands expand.

Add per-operation fixed budgets such as:

```text
FAST operation        short fixed budget
network inspection    bounded budget
media frame sample    bounded budget
full hash             explicit heavy operation
```

Goals:

- fail with `OPERATION_TIMEOUT`;
- no orphan subprocesses;
- clean temp workspace;
- preserve useful partial diagnostics where safe;
- never hide an unbounded call behind AE `system.callSystem()`.

Classification: **BUILD BEFORE HEAVY MEDIA FEATURES**

---

# 10. Next-Generation Tool Family G — Audio Intelligence

## G1. `audio.inspect`

Wrap `afinfo` only if its output can be parsed conservatively or use another stable structured source.

Potential facts:

```text
sample rate
channels
format
packet/frame counts when reliable
duration evidence
```

If output stability is insufficient, expose it as diagnostic evidence rather than authoritative structured data.

Classification: **RESEARCH / MEDIUM PRIORITY**

---

## G2. `audio.derivative`

Use `afconvert` for temporary audio analysis/playback derivatives only.

Never treat it as a source-preserving round-trip mechanism.

Classification: **LOWER PRIORITY**

---

# 11. Report / Diagnostic Enhancements

## H1. Structured operation receipt

Every non-trivial operation should progressively standardize provenance fields such as:

```text
sourceTool
sourceFramework
advisory / authoritative
mutationClass
elapsed / cost class
cacheHit
warnings
```

This will make Tech Reports significantly more useful.

Classification: **BUILD WITH Capability Registry 2.0**

---

## H2. Human-readable report export

`textutil` can convert text/HTML/RTF/doc/docx formats, but this should remain an optional report-export adapter rather than a core dependency.

Classification: **OPTIONAL**

---

# 12. Explicit Rejections / Guardrails

Do not turn MographJailed into:

```text
shell.execute
arbitrary process runner
Finder/System Events automation framework
background daemon
MCP server
installer
package manager
cloud client
general media transcoder
asset database
```

Do not add `networkQuality` to normal diagnostics because it intentionally makes Internet connections and uses network data.

Do not use `qlmanage` as a production dependency unless there is no better supported framework path; it is documented primarily as a Quick Look server debug/management tool.

Do not automatically remove quarantine attributes with `xattr`.

Do not use `caffeinate` by default. If ever added, it must be an explicit opt-in wrapper around an approved long operation and terminate with that operation.

---

# 13. Proposed Version Roadmap

## 0.1.0 — Freeze / Promote

Finish the remaining AE round-trip qualification and freeze the hardened core.

No new feature work should destabilize 0.1.0.

---

## 0.2.0 — Asset Intelligence & Runtime Trust

### Foundation

- `system.describe`
- `runtime.verify`
- operation metadata / cost classes
- structured operation provenance
- bounded-operation infrastructure for new commands

### Asset tools

- `asset.manifest`
- `asset.verify`
- `search.candidate`
- `file.provenance`
- `storage.preflight`

### Image tools

- `image.inspect`
- `image.derivative`

This is the recommended **next implementation release**.

---

## 0.3.0 — Native Media Lab Promotion

Research / qualify:

- sips JavaScript image stats
- `image.compare`
- JXA framework probe
- AVFoundation `media.frame`
- bounded `media.frames`
- structured `media.timing`

Nothing promotes until target-Mac tests are clean.

---

## 0.4.0 — Perceptual Media Intelligence

If Vision qualification succeeds:

- `image.featurePrint`
- `image.similarity`
- coarse media-frame similarity filtering

Consumers such as Looper can combine this with exact pixel metrics.

---

## 0.5.0 — Resilience / Scale

- manifest caching
- validated cache keys
- bounded SMB behavior
- performance budgets
- richer diagnostic snapshots
- concurrency/load qualification

---

# 14. Recommended First Engineering Loop

## NG-M1 — Capability Registry 2.0 + Runtime Trust

Use the established four-role MJ loop:

```text
PLAN
→ IMPLEMENT
→ INDEPENDENT REVIEW
→ QA / RED TEAM
→ ITERATE UNTIL GATE PASSES
```

### Scope

1. `system.describe`
2. `runtime.verify`
3. operation metadata schema
4. cost / mutation / authority classifications
5. regression tests proving current V1 commands are unchanged
6. Tech Report integration

### Acceptance criteria

```text
existing RC3 operations remain backward compatible
protocolVersion stays 1 unless a real breaking requirement is found
no source-mutation capability added
no new external dependency
no Internet access
no background service
all operation metadata generated from one canonical registry
consumer can determine interactive-safe vs explicit-heavy operations
source → dist parity remains enforced
```

Only after NG-M1 closes should NG-M2 begin.

---

# 15. NG-M2 — Asset Intelligence

Implement:

```text
asset.manifest
asset.verify
search.candidate
file.provenance
storage.preflight
image.inspect
image.derivative
```

### Special QA

- large directory
- SMB directory
- missing files
- symlink trees
- unreadable files
- filenames with spaces/apostrophes/Unicode
- Spotlight unavailable / incomplete
- image corruption
- source files verified byte-identical before/after

---

# 16. NG-M3 — Native Image Lab

Research `sips --js` before JXA-heavy solutions.

Prototype:

```text
image.stats
image.compare
```

If sips JavaScript cannot provide stable deterministic pixel access, stop and move to Core Image JXA research rather than forcing the approach.

---

# 17. NG-M4 — AVFoundation / Vision Lab

Run read-only target-Mac probes in this order:

```text
JXA Foundation       already proven at basic level
AVFoundation import
Core Image import
Vision import
single local image feature print
single local video frame extraction
requested vs actual time verification
cancellation test
SMB read test
After Effects invocation test
```

No team runtime bundling until these pass without unexpected TCC/Automation prompts.

---

# 18. Strategic Payoff by MJ Product

## MJ_AE_LOOPER

Benefits from:

```text
media.frame
media.frames
image.compare
image.similarity
media.timing
storage.preflight
runtime.verify
```

Native supplies evidence; Looper selects loop strategy.

## MJ_Organize

Benefits from:

```text
asset.manifest
asset.verify
search.candidate
file.provenance
image.inspect
runtime.verify
```

## MJ_Brief

Benefits from:

```text
runtime.verify
package.create
asset.manifest
report receipts
system.describe
```

## Future QC tool

Benefits from nearly all image/media/storage primitives without duplicating native adapters.

---

# 19. Key Planning Decision

The next generation should **not** begin with AVFoundation.

The correct order is:

```text
Capability Registry 2.0
        ↓
Runtime Trust
        ↓
Asset / Image primitives using proven CLI tools
        ↓
Bounded-operation engine
        ↓
sips image-analysis lab
        ↓
AVFoundation / Core Image / Vision lab
        ↓
media intelligence promotion
```

This order increases capability while keeping MographJailed understandable and safe on an active production Mac.

---

# 20. Recommended Immediate Next Task

Start **NG-M1 — Capability Registry 2.0 + Runtime Trust**.

Do not modify the frozen RC3 release in place.

Branch/copy it as the next development line, conceptually:

```text
MographJailed 0.1.0-rc3   frozen qualification candidate
                |
                +--> 0.2.0-dev
                      NG-M1 Capability Registry 2.0
```

The first deliverable should be a dry architecture/spec pass, followed by implementation and full regression against the existing 217-test baseline plus new registry/runtime-trust tests.
