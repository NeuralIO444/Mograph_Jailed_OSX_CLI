# MographJailed + MJ_AE_LOOPER

MographJailed is the native evidence/primitive layer. Looper remains responsible for loop strategy and After Effects project mutation.

## Standard Library 1.0 priority

Looper should consume Native contracts rather than parse Apple tools directly.

Immediate high-value flow:

```text
runtime.verify
system.describe
media.inspect        fast/advisory
media.timing         explicit bounded local timing
```

`media.timing` is the first Standard Library 1.0 Looper primitive. It is local-only, non-interactive by default, and returns normalized native timing without enumerating the full sample table.

Candidate flow in dev.2:

```text
media.frame           one exact-time local PNG derivative
Future media.frames  bounded multi-frame sampling
ImageKit analysis     future image.stats / image.compare
```

`media.frame` is implemented but not yet promoted over dev.1. It must pass the managed-Mac CLI gate and the After Effects child-process qualification. Looper should use the reported `actualTime` rather than assuming the requested frame time was returned exactly.

Native must not decide whether Looper should use cycle, ping-pong, spatial wrap, overlap blend, time remap, or another animation strategy.

Team deployment should bundle a pinned MographJailed runtime inside Looper. Designers should not need Terminal configuration, PATH changes, Xcode setup, or a separate Native installation.
