# MographJailed 0.3.0-dev.2 — Target-Mac Hotfix Qualification

Run on the managed production Mac with no sudo, Homebrew, Xcode/CLT installation, or system-wide changes. Keep the dev.4 backup until all checks pass.

## 1. Health

Run `mj-status`.

Expected: READY, Core PASS, warnings 0, CLI `0.3.0-dev.2`.

## 2. Dashboard runtime verification

Run `mj-top`.

Expected:

- Runtime verify = PASS
- no `Saving session...` output when the dashboard returns to the prompt
- dashboard returns after one snapshot

## 3. Presentation fallbacks

Run:

- `mj-top --ascii`
- `mj-top --plain`
- `NO_COLOR=1 mj-top --ascii`
- `COLUMNS=50 mj-top --ascii`

All must return cleanly without terminal corruption.

## 4. Temp cleanup

Compare `/tmp/mj-top-*` before and after normal `mj-top` execution and after an interrupted run. No dashboard temp files should remain.

## 5. Registry serialization

Run `system.describe` under `/bin/zsh -f` and reconfirm dependency arrays remain separate string elements.

## Pass criteria

- CLI `0.3.0-dev.2`
- Runtime verify PASS
- no Apple Terminal session-save noise from dashboard worker
- all presentation fallbacks return cleanly
- no dashboard temp residue
- Registry arrays remain correct
