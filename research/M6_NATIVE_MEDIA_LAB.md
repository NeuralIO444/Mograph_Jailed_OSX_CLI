# M6 — Native Media Lab Decision

## Scope

Evaluate whether JXA (`osascript -l JavaScript`) plus JavaScriptObjC can safely become a supported MographJailed adapter for AVFoundation frame extraction and Core Image frame comparison on locked-down production Macs.

## Research findings

### Technical capability exists

Apple's archived Mac Automation documentation states that JavaScriptObjC bridges JavaScript for Automation to Objective-C frameworks. AVFoundation's `AVAssetImageGenerator` provides the media operation MJ needs: frame generation at requested timeline times, a maximum output size, requested-time tolerances, and reporting of actual generated time. Core Image exposes reduction filters such as area-average and area-histogram filters that can produce deterministic image statistics.

### Security/deployment uncertainty is material

Apple's current platform-security documentation states that all AppleScript/JXA execution through OpenScripting is locally inspected by XProtect. macOS privacy controls also protect access to user files and network volumes; managed-device policy can further constrain these services.

MographJailed does not need to send Apple Events to Finder/System Events for this design, so cross-application automation is not a functional requirement. However, the actual permission attribution and managed-device behavior of `osascript` launched as an After Effects child process has not been validated on the target corporate Macs.

### Documentation quality is asymmetric

AVFoundation and Core Image are current, documented frameworks. The JavaScriptObjC/JXA bridge documentation is archived and the bridge-specific behavior needed for Core Media structs, pointers, and callbacks is not sufficiently current to treat it as a production contract without an empirical compatibility matrix.

## Decision

**DO NOT PROMOTE JXA/AVFoundation/Core Image into MographJailed V0.1.**

Keep it in the lab as an optional future adapter. This is a fail-closed decision, not a conclusion that the technique cannot work.

The core project remains:

```text
AE / MJ consumer
  -> MJ Native Protocol
  -> bundled zsh runtime
  -> approved macOS CLI tools
```

## Promotion gate

JXA native media support may be promoted only after all of the following pass on actual managed target Macs:

1. `framework_probe.js` imports Foundation, AVFoundation, and Core Image.
2. Invocation from After Effects produces no unexpected Automation prompt.
3. Local source-media access is repeatable.
4. SMB/network source-media access behavior is documented and acceptable.
5. XProtect does not block the shipped file-based lab script in normal operation.
6. A frame can be extracted at a requested time and the actual returned time is captured.
7. Rotation/orientation is handled with preferred track transforms.
8. Bounded output size works.
9. ProRes, H.264, HEVC, VFR, corrupt media, and long-GOP cases are exercised.
10. Core Image generates a deterministic signature on extracted frames.
11. Repeated runs produce consistent results.
12. Cancellation/failure cannot modify source media.

Until then, MographJailed reports the capability as experimental/unavailable rather than silently invoking it.

## Consequence for MJ_AE_LOOPER

Looper V1 should not depend on native pixel-level seam search. It can still use AE structural analysis, keyframe/effect strategy detection, source metadata, source identity, and deterministic native filesystem/media diagnostics. Pixel-level similarity becomes an optional future enhancement once the lab gate passes.

---

## 2026-09-22 target-machine qualification update

The managed production Mac was probed locally with no sudo, installs, server mutation, or network requests.

Confirmed from Terminal:

- JXA Foundation import: PASS
- JXA AVFoundation import: PASS
- JXA CoreImage import: PASS
- JXA Vision import: PASS
- local temp/cache/TCC-folder reversible access: PASS
- `avmediainfo` real H.264 movie inspection: PASS
- `avmediainfo --samples --mediatype video`: PASS, including decode/presentation timestamps

Confirmed from an After Effects child process:

- local temp/cache/Desktop/Documents/Downloads/Movies/Pictures access: PASS

Still **not** completed:

- JXA framework import launched specifically as an AE child process;
- AVFoundation frame extraction from the AE-child context;
- requested-time vs actual-time capture;
- transform/orientation verification;
- bounded extraction across codec/VFR/corrupt fixtures;
- Core Image frame signature/compare from that same production path.

At the dev.1 checkpoint, the original promotion decision remained in force for FrameKit: Standard Library 1.0 promoted only the bounded CLI-backed MediaProbe path while JXA/AVFoundation/Core Image remained lab-gated.


## 0.3.0-dev.2 FrameKit candidate update

The earlier lab-gated conclusion was intentionally preserved through dev.1. dev.2 now implements a narrowly bounded candidate so the missing evidence can be collected without exposing a generic framework bridge. Promotion still depends on the real managed-Mac CLI and After Effects child-process gates; until those pass, this research record does not claim production qualification.
