# MographJailed 0.3.0-dev.2 — SL-M2 FrameKit Planning

## Goal

Add the first deterministic native frame-derivative primitive for MJ_AE_Looper without weakening the dev.1 local-only/no-admin architecture.

## Scope

- one new Protocol v1 operation: `media.frame`;
- fixed JXA/AVFoundation adapter only;
- one local source, one requested time, one new local PNG output;
- requested/actual CMTime evidence;
- preferred-track transform;
- bounded output;
- source immutability and no-overwrite publication;
- target-Mac and After Effects child-process qualification harnesses.

## Non-goals

- no generic JXA/Objective-C execution;
- no `media.frames` batch operation yet;
- no Core Image statistics/comparison yet;
- no network media execution;
- no automatic server scan/test/mutation;
- no public database/SQL API;
- no Python/Node/FFmpeg/Homebrew/Xcode-license dependency;
- no replacement of the qualified dev.1 install before Mac gates pass.

## Promotion gates

1. all legacy + new portable deterministic QA;
2. 1,000 protocol fuzz cases;
3. source-to-dist and packaged-ZIP rebuild parity;
4. `tests/run_framekit_m2_target_mac.zsh`;
5. `tests/MographJailed_FrameKit_AE_Qualification.jsx`;
6. real VFR fixture evidence remains required before claiming VFR qualification.
