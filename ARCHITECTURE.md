# MographJailed Architecture

MographJailed is a zero-install, local-first macOS capability and evidence layer for MJ applications.

## Runtime path

```text
MJ consumer (After Effects / MJ tool)
  -> MJ Native request file
  -> /bin/zsh -f dist/mograph-jailed.zsh --request <request-file>
  -> environment normalization
  -> Protocol v1 validation / command schema
  -> public operation handler
  -> MJ Standard Library 1.0
  -> fixed-path stock macOS adapter
  -> versioned JSON response
```

The production bundle begins with `#!/bin/zsh -f` and `emulate -R zsh` so user zsh startup/options do not define runtime behavior. `/etc/zshenv` remains OS/IT-controlled and therefore part of target-Mac qualification.

## Standard Library 1.0

0.3.0-dev.2 continues the internal reusable library boundary under `src/lib/` and adds the FrameKit candidate.

```text
src/lib/
  local_fs.zsh        LocalFS
  native_db.zsh       NativeDB
  media_probe.zsh     MediaProbe
  image_kit.zsh       ImageKit foundation
  frame_kit.zsh       FrameKit fixed JXA/AVFoundation adapter
  standard_library.zsh descriptor/policy
```

### LocalFS

Owns filesystem classification and local-only guard semantics. It does not enumerate network mounts. A caller-supplied path may be classified as `local`, `network`, or `unknown`. Operations marked local-only fail closed on `network` and `unknown`.

### NativeDB

Owns the stock `/usr/bin/sqlite3` capability boundary. In this milestone it performs static `:memory:` probes for runtime execution, JSON, and FTS5. It exposes **no public arbitrary SQL operation** and creates no persistent production database.

Future product stores must be fixed-schema, versioned, local-only, migration-tested, and owned by a specific MJ feature.

### MediaProbe

Normalizes a narrow labeled subset of Apple `avmediainfo` output. It is intentionally not a general parser for undocumented text.

`media.timing`:

- is explicit and non-interactive by default;
- requires a positively identified local filesystem;
- verifies `avmediainfo --brief` completed with zero errors;
- reads only the pre-sample header from `--samples --mediatype video`;
- hard-bounds captured output to 256 lines;
- validates numbers before emitting JSON;
- reports that the sample table was not enumerated.

This gives Looper useful duration/timescale/codec/dimensions/nominal-FPS/minimum-sample-duration/frame-reordering evidence without the cost or brittleness of parsing an entire movie sample table.

### ImageKit

Owns reusable `sips` property/positive-identification primitives. Public handlers still own mutation policy, staging, overwrite refusal, and source-immutability checks.

### FrameKit

FrameKit is implemented in 0.3.0-dev.2 as a **candidate**, not yet the installed production baseline. The public operation is `media.frame`. It accepts one explicit local source, one non-existing local PNG output, one requested time, and an optional bounded pixel dimension.

The adapter is intentionally narrow:

- fixed embedded JXA only; no caller-supplied JavaScript or Objective-C selector;
- AVFoundation `AVAssetImageGenerator`;
- zero requested-time tolerance;
- preferred track transform enabled;
- requested and actual `CMTime` reported independently;
- output dimension bound 64–4096 pixels, default 2048;
- staged PNG publish with no overwrite;
- source identity rechecked after decode;
- both source and output parent must be positively classified local.

The synchronous Objective-C image-generator API used by the JXA bridge is deprecated by Apple, so it is isolated behind the stable `media.frame` contract. Promotion requires the target-Mac and After Effects child-process gates in `tests/FRAMEKIT_M2_MAC_QUALIFICATION.md`.

## Core rules

- No public raw shell execution API.
- No public arbitrary SQL API.
- Request values are data, not shell syntax.
- Source media is not mutated by Native.
- Optional capabilities are probed and fail closed.
- Native executable paths are fixed/absolute.
- Locale, PATH, IFS, macOS compatibility variables, `ditto` hooks, and Perl hooks are normalized/sanitized before adapters execute.
- Temporary deletion is limited to marker-validated MJ-owned directories bound to canonical path and effective user.
- Development source stays modular; distribution bundles deterministically to one zsh file and source-to-dist parity is release-blocking.
- Network volumes are outside automatic Standard Library mutation/index/cache/test behavior.
- JXA is not a general production execution surface. The only production candidate is the fixed FrameKit AVFoundation adapter; Core Image remains outside the promoted adapter set until its own gate passes.

## Public operations vs library modules

The public Protocol remains deliberately small. Internal library modules do not automatically become generic commands.

```text
LocalFS      -> volume.inspect, storage.preflight, media.timing guard
NativeDB     -> capability layer only; no public SQL
MediaProbe   -> media.timing
FrameKit     -> media.frame candidate
ImageKit     -> image.inspect / image.derivative internals
FrameKit     -> no production command yet
```

This prevents a library convenience layer from accidentally becoming an unsafe generic automation API.

## Synchronous After Effects boundary

After Effects `system.callSystem()` waits for invoked work to complete. MographJailed separates low-latency inspection from explicit work.

- `media.inspect` remains the fast/advisory path and does not execute `avmediainfo`.
- `media.timing` is explicit, bounded, local-only, and not marked interactive-safe.
- full SHA-256 remains an explicit size-dependent operation.
- future frame extraction/comparison must remain bounded and cancellable at the product strategy layer.

## Capability Registry 2.0

Consumers discover operation availability, execution cost, mutation scope, semantic authority, interactive safety, network sensitivity, execution scope, and capability dependencies through `system.describe`.

Registry 2.0 now also carries an additive `standardLibrary` descriptor. Protocol v1 is unchanged.

## Runtime trust

`runtime.verify` allows a bundled MJ product to verify Native CLI/protocol/filename and optionally pin the exact runtime SHA-256. Hashing the small Native runtime is inexpensive; hashing production media remains explicit and size-dependent.

## Product responsibility boundary

```text
MographJailed
= machine/filesystem/media evidence + deterministic primitives

MJ_Organize
= organization plan, project/asset mutation, relink decisions, validation

MJ_AE_Looper
= loop analysis/strategy, AE mutation, validation
```

Native should not absorb Organize or Looper business logic merely because it can expose a lower-level primitive.

## Optional Terminal UX

The project-local terminal interface remains outside the production CLI bundle:

```text
mj-man / mj-top
        ↓
scripts/shell + scripts/terminal
        ↓
MJ Native Protocol v1
        ↓
dist/mograph-jailed.zsh
```

`mj-top` remains snapshot-only in this development line.
