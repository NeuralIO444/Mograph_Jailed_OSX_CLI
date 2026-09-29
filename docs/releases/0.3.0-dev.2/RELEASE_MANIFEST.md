# MographJailed 0.3.0-dev.2 — Release Manifest

## Identity

- CLI: `0.3.0-dev.2`
- Protocol: `1`
- Capability Registry: `2`
- Standard Library: `1.0`
- Terminal UX: `1`
- Release class: SL-M2 FrameKit target-Mac qualification candidate

## Public protocol surface

21 allowlisted operations. dev.2 adds exactly one operation: `media.frame`. Existing command schemas remain unchanged.

`media.frame` reports:

- `cost`: `FRAME_DECODE`
- `mutation`: `DERIVATIVE_CREATE`
- `authority`: `NATIVE_FRAME_DERIVATIVE`
- `executionScope`: `LOCAL_ONLY`
- `interactiveSafe`: `false`
- required capabilities: `avmediainfo`, `osascript`, `jq`, `sips`, `awk`, `df`, `mktemp`, `mv`, `rm`, `stat`, `uname`

## FrameKit candidate

- fixed embedded JXA only; no public JXA/Objective-C execution surface;
- AVFoundation `AVAssetImageGenerator`;
- zero time tolerance;
- preferred-track transform;
- requested + actual media time;
- PNG max dimension 64–4096, default 2048;
- source and output parent must be positively classified local;
- non-overwriting staged publish;
- source identity rechecked after decode.

## Runtime dependencies

No downloaded runtime is added. `media.frame` uses stock `/usr/bin/osascript`, `/usr/bin/jq`, `/usr/bin/sips`, `/usr/bin/avmediainfo`, and Apple AVFoundation/CoreMedia/CoreGraphics/AppKit frameworks.

Explicitly not required: Python, Ruby, Perl, Node/npm, FFmpeg, Homebrew, MacPorts, Docker, sudo, admin installation, or Xcode-license acceptance.

## Portable QA

- deterministic: 515/515
- protocol fuzz: 1,000/1,000, 0 failures
- deterministic production CLI SHA-256: `bc86c562dbcd20ce10e07013eaeaf7d1639565e4b24f17831a5821b49eb4072c`
- source rebuild parity: PASS
- generic shell/JXA/SQL public-surface scan: clean

## Target-Mac promotion gate

Do **not** replace the qualified `0.3.0-dev.1` install yet. Run both:

1. `tests/run_framekit_m2_target_mac.zsh`
2. `tests/MographJailed_FrameKit_AE_Qualification.jsx` from After Effects

The CLI gate uses only local macOS fixtures and `/tmp`; it performs no server mutation, sudo, Python, or Xcode-tool execution. A real VFR fixture remains a separate qualification requirement.
