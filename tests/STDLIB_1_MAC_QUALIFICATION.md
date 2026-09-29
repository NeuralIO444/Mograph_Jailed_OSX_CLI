# Standard Library 1.0 — Target-Mac Qualification

Target: `MographJailed 0.3.0-dev.2`

This gate is local-only. It must not use sudo, accept the Xcode license, touch server volumes, install software, or change system settings.

## One-command gate

From the extracted MographJailed folder:

```text
/bin/zsh -f tests/run_stdlib_1_target_mac.zsh
```

Expected release-blocking results:

- Registry / Standard Library 1.0: PASS
- NativeDB stock SQLite runtime + JSON + FTS5: PASS
- MediaProbe availability and `LOCAL_ONLY` policy: PASS
- `media.timing` against a built-in local macOS movie: PASS
- policy static check: PASS
- failures: `0`

The script creates request files only under the normal local temp directory and removes them on exit. It does not create a persistent SQLite database.

## Manual response review

`media.timing` should report:

- schema `MJ_MEDIA_TIMING_2`
- `bounded:true`
- `scope.classification:"local"`
- `scope.policy:"LOCAL_ONLY"`
- positive duration
- at least one video track
- positive dimensions and nominal frame rate
- `sampleTableEnumerated:false`

The operation is a bounded timing summary, not per-sample enumeration.

## FrameKit remains gated

Passing this checklist does **not** promote JXA/AVFoundation frame extraction. FrameKit needs a separate After Effects child-process qualification.
