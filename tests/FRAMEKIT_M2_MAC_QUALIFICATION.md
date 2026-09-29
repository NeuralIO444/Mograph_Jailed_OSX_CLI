# MographJailed 0.3.0-dev.2 — FrameKit M2 Target-Mac Qualification

Scope: local-only validation of the new `media.frame` candidate. Do not install over the qualified `0.3.0-dev.1` baseline until these gates pass.

## Gate A — Terminal/native child

From the extracted dev.2 folder:

```zsh
/bin/zsh tests/run_framekit_m2_target_mac.zsh
```

Required core results:

- FrameKit and `media.frame` available.
- Local H.264 system fixture extracts to a bounded PNG.
- Requested and actual time are both present.
- Zero time tolerance is reported.
- Preferred track transform is applied.
- Source identity is unchanged.
- Existing output is never overwritten.
- End-of-asset request is refused without output.
- Audio-only input is refused as `NO_VIDEO_TRACK`.
- HEVC and ProRes are tested when the stock `avconvert` preset succeeds; inability to create a local derivative is a SKIP, not a fabricated PASS.
- VFR is intentionally SKIP until a qualified local VFR fixture exists.

## Gate B — After Effects child process

With After Effects open, run:

```text
File > Scripts > Run Script File...
tests/MographJailed_FrameKit_AE_Qualification.jsx
```

The script uses only a built-in local macOS movie and `Folder.temp`. It creates and removes one PNG derivative. It performs no network reads/writes and does not use sudo, Python, or Xcode tools.

Expected: PASS with receipt at:

```text
/tmp/MographJailed_FrameKit_AE_Qualification.txt
```

Upload or paste both Gate A output and the Gate B receipt before dev.2 is promoted over the qualified dev.1 installation.

## Promotion boundary

`media.frame` is a candidate public operation in dev.2, but this release remains unqualified until both Terminal and After Effects child-process gates pass on the managed production Mac.
