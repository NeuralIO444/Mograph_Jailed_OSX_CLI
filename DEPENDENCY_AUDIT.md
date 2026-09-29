# MographJailed 0.3.0-dev.2 Dependency Audit

MographJailed remains zero-install and local-first. The production runtime invokes fixed absolute macOS paths only; it does not rely on user `PATH`, Homebrew, a package manager, a daemon, or a network service.

This audit reflects **Standard Library 1.0 / 0.3.0-dev.2** rather than the older RC3 surface.

## Production runtime

### Core / protocol / filesystem

| Path | Role |
|---|---|
| `/bin/zsh` | production runtime / AE invocation |
| `/usr/bin/awk` | JSON quoting, Base64 compaction, bounded native-output parsing |
| `/usr/bin/base64` | protocol argument decode / canonical round-trip |
| `/usr/bin/uname` | platform / architecture detection |
| `/usr/bin/stat` | file facts and hash-stability evidence |
| `/usr/bin/file` | advisory basic file type |
| `/bin/df` | free-space and filesystem classification (`-Y` on macOS) |
| `/usr/bin/mktemp` | guarded temp/staging workspaces |
| `/usr/bin/sed` | ownership-marker reads / small bounded transforms |
| `/bin/rm` | deletion only after MJ ownership/scope validation |
| `/bin/mv` | non-overwriting staged publish |
| `/bin/pwd` | canonical directory resolution |

### Qualified operation-specific adapters

| Path | Role |
|---|---|
| `/usr/bin/sips` | `image.inspect`, `image.derivative`, Standard Library ImageKit |
| `/usr/bin/mdfind` | advisory `search.candidate` |
| `/usr/bin/xattr` | names-only `file.provenance`; values are never requested |
| `/usr/bin/mdls` | advisory Spotlight metadata for `media.inspect` |
| `/usr/bin/avmediainfo` | explicit, bounded Standard Library MediaProbe / `media.timing` |
| `/usr/bin/sqlite3` | Standard Library NativeDB capability; static in-memory feature probe only; no public arbitrary SQL |
| `/usr/bin/ditto` | explicit non-overwriting package creation |
| `/sbin/sha256` or `/usr/bin/sha256` | preferred SHA-256 adapter where available |
| `/usr/bin/shasum` | legacy SHA-256 fallback when approved native `sha256` is unavailable |

### Capability-reported / auxiliary, not required by a public 0.3.0-dev.2 operation

| Path | Current role |
|---|---|
| `/usr/bin/jq` | strict JSON validation/parsing for the fixed `media.frame` adapter |
| `/usr/bin/avconvert` | qualified machine capability; future bounded media conversion |
| `/usr/bin/afinfo` | qualified machine capability; future audio inspection |
| `/usr/bin/afconvert` | qualified machine capability; future audio derivative/conversion |
| `/usr/bin/osascript` | fixed embedded JXA/AVFoundation FrameKit candidate for `media.frame`; no caller-supplied script |
| `/usr/bin/plutil` | capability-reported / future structured plist use |

## Standard Library 1.0 dependency policy

### LocalFS

Uses only `df`, `awk`, and `uname` to classify an explicitly supplied path. It does not enumerate mounted servers. Operations marked `LOCAL_ONLY` fail closed on positively identified network filesystems and on unknown filesystem classes.

### NativeDB

Uses `/usr/bin/sqlite3` only. `system.describe` performs static `:memory:` probes for:

- runtime execution;
- SQLite JSON support;
- FTS5 support.

No public arbitrary-SQL operation exists. 0.3.0-dev.2 does not create a persistent production SQLite store.

### MediaProbe

Uses `/usr/bin/avmediainfo` plus `awk`, `df`, and `uname`. `media.timing` first proves the target is on a local filesystem, then parses a hard-bounded pre-sample header. The full sample table is not enumerated by the default operation.

### ImageKit

Uses `/usr/bin/sips` and `/usr/bin/awk`. Source-image mutation remains unavailable; derivative creation is staged, non-overwriting, and separately guarded by the public handler.

### FrameKit

`media.frame` is an explicit dev.2 candidate. It requires `/usr/bin/osascript`, `/usr/bin/jq`, `/usr/bin/sips`, MediaProbe, LocalFS, staging tools, and the system AVFoundation/CoreMedia/CoreGraphics/AppKit frameworks. The JXA source is fixed in the bundle; caller values are data only.

The adapter requests exact-time generation with zero tolerance, applies the preferred track transform, encodes a staged PNG, and reports requested/actual time separately. It remains promotion-gated until both the target-Mac CLI gate and After Effects child-process gate pass.

## Explicitly excluded as production dependencies

- Python / Python 3
- Ruby
- Perl
- Node / npm
- Homebrew / MacPorts
- FFmpeg / ffprobe
- OpenCV / ImageMagick
- Docker
- background daemon / LaunchAgent / local web server
- cloud API
- Xcode / Xcode Command Line Tools

Ruby and Perl are usable on the target Mac and may be used by isolated developer/QA utilities, but they are not production runtime requirements. Python is present only through the installed Xcode toolchain and triggers the unaccepted Xcode license/admin boundary; MographJailed does not use it.

## Xcode / developer-tool boundary

The target Mac contains Xcode/CLT artifacts, but MographJailed does not invoke `python3`, `swift`, `clang`, `gcc`, `make`, `git`, `xcrun`, or `xcode-select` in production. No workflow may require accepting an Xcode license, using `sudo`, or changing developer-tool configuration.

## Network boundary

Network volumes may be detected/classified when the caller explicitly supplies a path, but Standard Library 1.0 does not:

- enumerate SMB/NFS shares;
- create test/scratch files on them;
- place SQLite databases on them;
- cache to them;
- automatically scan/index them;
- mutate them.

`media.timing` and `media.frame` are explicitly `LOCAL_ONLY` in 0.3.0-dev.2.

## QA/build-only dependencies

The portable review harness may use Bash, jq, Node, Python, ffmpeg, GNU `sha256sum`, and GNU utilities to create synthetic fixtures and test the source tree. These are development/QA dependencies only and do not appear in the production execution path.

## Terminal UX

Project-local `mj-man` / `mj-top` may additionally use stock macOS `awk`, `less`, and `osascript` for presentation. Terminal UX remains outside the production CLI dependency contract used by bundled MJ applications.
