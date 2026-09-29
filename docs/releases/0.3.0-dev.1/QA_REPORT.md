# MographJailed 0.3.0-dev.1 — Standard Library 1.0 QA Report

## Scope

First Standard Library 1.0 engineering slice for MJ_Organize and MJ_AE_Looper.

Implemented:

- `LocalFS` shared filesystem/local-only policy helpers;
- internal `NativeDB` SQLite/JSON/FTS5 capability layer with no public arbitrary-SQL API;
- `MediaProbe` bounded native timing adapter;
- `ImageKit` extraction of reusable qualified `sips` primitives;
- additive Standard Library descriptor in `system.describe` and `report.tech`;
- promoted `media.timing` implementation with `LOCAL_ONLY` execution scope;
- After Effects client convenience methods for Standard Library introspection and `media.timing`;
- target-Mac one-command Standard Library qualification gate.

`FrameKit` remains `LAB_GATED`; frame extraction was not promoted in this release.

## Review findings addressed during implementation

1. **Duplicate video-track parsing risk** — initial MediaProbe design combined `avmediainfo --brief` and a samples header, which could double-count the first video track. Fixed by using `--brief` only as an analysis-success gate and parsing one bounded samples header.
2. **SQLite user-configuration drift** — SQLite CLI can inherit user initialization/temp settings. NativeDB now invokes `sqlite3 -batch -init /dev/null`, forces `PRAGMA temp_store=MEMORY`, and production startup clears `SQLITE_HISTORY` / `SQLITE_TMPDIR`.
3. **Audio-only normalization** — regression fixture verifies media with no video track is represented as `video.trackCount=0` rather than guessed/fabricated video fields.
4. **Media parser fail-closed behavior** — malformed timing fixture missing required nominal FPS is rejected.
5. **Network boundary** — `media.timing` rejects network/unknown filesystems before invoking `avmediainfo`; no Standard Library runtime path contains a hard-coded `/Volumes` target.

## Portable deterministic QA

| Suite | Result |
|---|---:|
| M1 | 21/21 |
| M2 | 26/26 |
| M3 | 8/8 |
| M4 | 14/14 |
| M5 | 12/12 |
| M6 | 7/7 |
| QA swarm | 32/32 |
| RC3 hardening | 32/32 |
| Concurrency | 62/62 |
| Contract parity | 4/4 |
| NG-M1 | 39/39 |
| NG-M2 | 64/64 |
| Stage hardening | 25/25 |
| Standard Library 1.0 | 54/54 |
| dev.4 terminal/registry | 63/63 |
| dev.4.1 Mac hotfix | 12/12 |
| **Deterministic total** | **475/475** |
| Protocol fuzz | **1,000/1,000; 0 failures** |

The Linux QA harness still emits the pre-existing `TERM environment variable not set` presentation message after some terminal tests. It does not change test results or production behavior.

## Deterministic build / static review

- modular-source rebuild SHA-256 before: `e563f74e094988e01c3c5bb47149f7f68a7fc2b496a273eee8a653adfc09752c`
- modular-source rebuild SHA-256 after:  `e563f74e094988e01c3c5bb47149f7f68a7fc2b496a273eee8a653adfc09752c`
- exact match: yes
- generic SQL/shell public-surface scan: clean
- Standard Library `/Volumes` literal scan: clean
- production xattr value/mutation flag scan: clean

## Target-Mac evidence already established before packaging

The managed production Mac independently qualified the native primitives this slice relies on:

- `/usr/bin/sqlite3` 3.43.2 with JSON + FTS5, local WAL database and integrity check;
- `/usr/bin/jq` 1.7.1-apple;
- `avmediainfo` real-video metadata and decode/presentation sample timing;
- `sips` inspection and local derivative creation;
- Foundation / AVFoundation / CoreImage / Vision imports through JXA;
- Terminal and an After Effects child process local access to temp/cache/Desktop/Documents/Downloads/Movies/Pictures;
- two SMB shares detected but not mutated or recursively scanned.

Python is deliberately excluded because executing `/usr/bin/python3` crosses the Xcode-license/admin boundary on this machine. Ruby and Perl were qualified only as auxiliary engineering tools and are not production dependencies.

## Remaining promotion gate

Run `tests/run_stdlib_1_target_mac.zsh` from this exact release on the managed Mac. It verifies the bundled runtime's Standard Library descriptor, SQLite features, LocalFS policy, and the new `media.timing` operation against a built-in local macOS movie.

No server/network mutation is performed by that gate.
