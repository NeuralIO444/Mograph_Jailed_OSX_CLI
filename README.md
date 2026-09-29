# MographJailed

Zero-install native macOS capability and evidence layer for MJ applications.

Development source is modular zsh. Deployment bundles deterministically to one `dist/mograph-jailed.zsh` runtime. Product code submits allowlisted structured requests; there is no public arbitrary-shell or arbitrary-SQL command.

## Runtime requirements

- stock macOS with `/bin/zsh`
- no Python, Node/npm, Homebrew, FFmpeg, OpenCV, Xcode/CLT, daemon, local server, cloud API, or admin installation required
- optional Apple-native capabilities are probed and fail closed
- After Effects invocation uses `/bin/zsh -f` to avoid user shell-startup state
- Standard Library 1.0 is local-first; network volumes are outside automatic execution/mutation paths

Ruby/Perl, Xcode tools, Python, Node, and GNU utilities may be used by isolated development/QA work when available, but they are not production runtime dependencies.

## Current development line

`0.3.0-dev.2` advances **MJ Standard Library 1.0** with the SL-M2 FrameKit candidate. Protocol v1 is preserved and the public surface grows additively from 20 to 21 allowlisted operations with `media.frame`.

The first library slice is aimed at **MJ_Organize** and **MJ_AE_Looper**:

- **LocalFS** — shared filesystem classification and local-only execution guard
- **NativeDB** — stock SQLite runtime/JSON/FTS5 capability layer with no public SQL API
- **MediaProbe** — bounded normalized `avmediainfo` timing adapter
- **ImageKit foundation** — reusable `sips` inspection primitives
- **FrameKit** — implemented as a local-only `media.frame` candidate; target-Mac + After Effects child-process qualification is still required before promotion

`media.timing` remains the bounded local-only timing primitive. `media.frame` adds one explicit, non-overwriting PNG derivative operation backed by a fixed JXA/AVFoundation adapter. It requests zero time tolerance, applies preferred track transforms, returns requested and actual media time, and re-checks source identity around decode.

The target-Mac-qualified `0.3.0-dev.1` install remains the production baseline until the dev.2 FrameKit gates pass.

## Existing asset intelligence

The 0.2 line remains intact:

- `asset.manifest`
- `asset.verify`
- `search.candidate`
- `file.provenance`
- `image.inspect`
- `image.derivative`
- `storage.preflight`

These are evidence providers, not workflow automation. Search never relinks automatically, provenance exposes xattr names only, derivatives never overwrite source media, and storage writability remains advisory.

## Performance boundary

After Effects `system.callSystem()` is synchronous. Consumers should respect Capability Registry metadata. `file.hash`, Spotlight search, derivative creation, package creation, `media.timing`, and `media.frame` are explicit/non-interactive operations. Routine UI paths should favor fast inspection operations.

## Standard Library policy

The Standard Library is intentionally narrow. It wraps approved macOS primitives behind stable MJ contracts so consumer tools do not parse native command output or depend on implementation details directly.

```text
MJ_Organize / MJ_AE_Looper
        ↓
MJ Native Protocol v1
        ↓
MJ Standard Library 1.0
        ↓
fixed stock-macOS adapters
```

No generic `shell.execute`, `db.query`, or similar escape hatch is introduced.

## Key documents

- `PROJECT_PLAN.md`
- `ARCHITECTURE.md`
- `PROTOCOL.md`
- `SECURITY.md`
- `CAPABILITY_REGISTRY.md`
- `DEPENDENCY_AUDIT.md`
- `docs/releases/0.3.0-dev.2/QA_REPORT.md`
- `docs/releases/0.3.0-dev.2/RELEASE_MANIFEST.md`
- `tests/FRAMEKIT_M2_MAC_QUALIFICATION.md`
- `docs/integrations/MJ_Organize_Native_Handoff.md`
- `tests/STDLIB_1_MAC_QUALIFICATION.md`
