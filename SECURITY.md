# Security

- No public raw shell execution operation.
- Commands and argument names are allowlisted.
- Command-specific schemas reject irrelevant or unexpected arguments.
- Request lines and decoded arguments are bounded.
- Untrusted argument values are transported as canonical Base64 and remain data.
- ASCII control characters are rejected at the protocol boundary.
- Native adapters use fixed absolute system utility paths.
- Production startup normalizes `PATH`, locale, IFS, and `COMMAND_MODE`, unsets `SYSTEM_VERSION_COMPAT`, and removes known `ditto`, copyfile, and Perl environment hooks.
- Production invocation uses zsh `-f`; the bundle resets zsh options with `emulate -R zsh`.
- No `eval`, public `sh -c`, public `zsh -c`, or caller-supplied JXA execution is used in the runtime. 0.3.0-dev.2 adds exactly one fixed embedded JXA adapter for `media.frame`; request values enter it only as environment data and cannot select JavaScript source or Objective-C methods.
- V0.1 media operations are read-only.
- Full-file hashing is explicit and checks device+inode+size+mtime before/after the read; obvious source replacement/modification fails with `SOURCE_CHANGED`.
- Temporary cleanup is restricted to marker-validated MJ-owned directories under the current canonical absolute temp root. RC3 markers bind the exact path and effective user.
- Report packaging rejects a symlink as its top-level source, canonicalizes source/output parents, refuses overwrite, stages before publish, and rechecks the source before `ditto` begins.
- Optional capabilities fail closed.
- Expensive operations such as full-file hashing and ZIP packaging are explicit rather than part of routine AE inspection.

## Remaining platform limits

A shell-level path validation cannot make all same-user filesystem replacement races mathematically impossible. Destructive scope is therefore deliberately small: production can remove only proven MJ temp directories and can create, but not overwrite, a requested ZIP output. Target-Mac qualification includes symlink/race-oriented checks.


## NG-M1 runtime trust

`system.describe` is read-only contract introspection. `runtime.verify` compares caller-supplied expected metadata only as data; it does not execute caller-selected binaries or paths. The optional SHA-256 check hashes only the running MographJailed runtime and does not expose the full runtime path in its response.

## NG-M2 Asset Intelligence safety boundary

- `asset.manifest` and `asset.verify` are read-only. SHA-256 remains explicit because it can be expensive on large/network assets.
- `search.candidate` is advisory only. It does not relink, rename, move, copy, or mutate any discovered file.
- `file.provenance` invokes only read/list behavior for `xattr`; production code contains no xattr write, delete, or clear path.
- `image.inspect` is read-only.
- `image.derivative` refuses overwrite, stages into a unique file in the canonical output parent, publishes with non-overwriting move semantics, and checks the source identity before/after processing. The source path is never used as the output path.
- `storage.preflight` reports direct free-space/filesystem facts plus advisory classification/write hints. A positive hint is not proof a later write will succeed.
- macOS-specific adapters fail closed when their native capability is absent.
- Spotlight results are treated as advisory index evidence because indexes can be stale, disabled, incomplete, or unavailable on some network volumes.


## Terminal UX security boundary

The optional terminal UX is project-local and non-privileged. It does not modify `MANPATH`, install system man pages, require sudo, create a daemon, or expose a general command runner. `mj-top` is snapshot-only and executes evidence queries only through allowlisted MographJailed protocol operations. Its `osascript` use is limited to local JSON parsing/rendering and does not automate another application.

## Standard Library 1.0 boundary

- Standard Library 1.0 is an internal capability layer, not a general scripting API.
- `LocalFS` classifies only the caller-selected/existing path. It does not enumerate mounted network shares. New Standard Library automatic operations fail closed unless storage is positively identified as local.
- `NativeDB` exposes fixed internal SQLite capability probes and store-path validation only. There is no public `db.query`, `sql.exec`, arbitrary-SQL, or caller-supplied SQL operation.
- SQLite probes use `/usr/bin/sqlite3 -batch -init /dev/null`, force `PRAGMA temp_store=MEMORY`, and production startup clears `SQLITE_HISTORY` / `SQLITE_TMPDIR` so user CLI configuration cannot alter the fixed probe behavior or redirect SQLite temporary state.
- `MediaProbe` accepts one explicit readable local file, invokes only fixed `avmediainfo` modes, caps the parsed header at 256 lines, and does not enumerate the sample table in `media.timing`.
- `media.timing` is explicitly `LOCAL_ONLY`; network and unknown filesystem classes fail closed before `avmediainfo` runs.
- `ImageKit` centralizes the already-qualified `sips` inspection/derivative helpers; existing non-overwrite and source-identity rules remain unchanged.
- `FrameKit` is a dev.2 candidate, not yet the qualified baseline. `media.frame` accepts one explicit local source/output/time/bound only; it exposes no generic JXA/Objective-C bridge.
- `media.frame` blocks network/unknown storage for both source and canonical output parent, refuses overwrite/symlink output, stages in the canonical local output parent, validates the PNG, and rechecks source identity after decode.
- FrameKit uses zero AVFoundation time tolerance and reports requested and actual time separately; consumers must not assume equality.
- The JXA compatibility adapter uses Apple's deprecated synchronous image-generator method because JXA cannot consume Swift async/await. That implementation detail is isolated and remains target-Mac/AE-child qualification-gated.
- Ruby and Perl are qualified only as auxiliary engineering/QA runtimes. Python/Xcode-dependent execution, Node/npm, FFmpeg, package managers, and downloaded runtimes are not production dependencies.

## Unattended code and downloads (0.4.0-dev.1)

- **Snapshot hooks** are the one place MographJailed runs a user-supplied program. They are opt-in (`post_snapshot_hook`), live in the user's own config, run only from the user-level watcher, and are refused unless the path is absolute and names a regular, executable file owned by the user that no one else can write to. They run directly (no shell), with closed stdin and a 30-second limit, and can never fail or delay a snapshot. The runtime itself still has no way to execute caller-supplied code.
- **The installer** checks the unpacked download against a shipped `SHA256SUMS` and supports pinning a release by tag and zip hash (`MJ_INSTALL_REF`, `MJ_INSTALL_SHA256`). Accepted residual risk: `curl | zsh` runs whatever the server returns, and a list inside the download cannot vouch for itself. Download, read, then run for the strongest assurance.
- **The scraper guard** (`scripts/check-scraper-readonly.sh`, enforced in CI) rejects mutating calls, assignments to settable After Effects properties on anything but its own records, and dynamic code. Accepted residual risk: computed member access (`x["set" + "Value"](...)`) defeats any text search; reviewers must reject it in the scraper.
