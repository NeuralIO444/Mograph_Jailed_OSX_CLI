# MographJailed 0.3.0-dev.2 — FrameKit SL-M2 QA Report

Status: **portable engineering complete; target-Mac + After Effects qualification pending.**

## Implemented

- fixed `FrameKit` JXA/AVFoundation adapter;
- `media.frame` public operation;
- local-only source/output-parent enforcement;
- zero time tolerance and requested/actual time reporting;
- preferred track transform;
- bounded PNG derivative;
- staged no-overwrite publish;
- source identity before/after decode;
- AE client helper and qualification JSX;
- target-Mac H.264 gate plus optional locally derived HEVC/ProRes coverage.

## Review findings

- JXA is restricted to fixed embedded source; request values are environment data only.
- FrameKit cannot select arbitrary Objective-C methods or scripts.
- The synchronous AVAssetImageGenerator Objective-C API is deprecated by Apple; it is isolated behind the stable operation contract and therefore requires target-Mac regression evidence.
- `media.frame` does not parse/enumerate the sample table; MediaProbe supplies bounded duration/timescale/decode evidence first.
- network/unknown storage is blocked before frame decode and before output staging.
- VFR is not marked qualified without a real local VFR fixture.

## Portable QA

| Suite | Result |
|---|---:|
| M1 | 21/21 |
| M2 | 26/26 |
| M3 | 8/8 |
| M4 | 14/14 |
| M5 | 12/12 |
| M6 | 7/7 |
| QA swarm | 35/35 |
| RC3 hardening | 32/32 |
| Concurrency | 62/62 |
| Contract parity | 4/4 |
| NG-M1 | 39/39 |
| NG-M2 | 64/64 |
| Stage hardening | 25/25 |
| Standard Library 1.0 | 54/54 |
| FrameKit M2 portable | 37/37 |
| dev.4 terminal/registry | 63/63 |
| dev.4.1 Mac hotfix | 12/12 |
| **Deterministic total** | **515/515** |
| Protocol fuzz | **1,000/1,000; 0 failures** |

Production CLI SHA-256: `bc86c562dbcd20ce10e07013eaeaf7d1639565e4b24f17831a5821b49eb4072c`. Exact ZIP hash is recorded in the external milestone handoff after packaging because a ZIP cannot contain its own final hash.
