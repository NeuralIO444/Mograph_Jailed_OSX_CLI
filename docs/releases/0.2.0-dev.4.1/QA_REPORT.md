# MographJailed 0.2.0-dev.4.1 QA Report

## Scope

Target-Mac qualification hotfix for two defects discovered after installing dev.4 on the managed production Mac:

1. `runtime.verify` reported incompatible from `mj-top` because zsh changes `$0` inside shell functions when `FUNCTION_ARGZERO` is active.
2. `mj-top` inherited Apple Terminal session-exit hooks through an interactive subshell, producing `Saving session...` noise after the snapshot.

## Fixes

- `runtime_self_path` now prefers zsh's stable `ZSH_ARGZERO` when running under zsh and falls back to `$0` elsewhere.
- `mj-top` is now a thin sourced wrapper that launches `scripts/terminal/mj-top-run.zsh` using `/bin/zsh -f`.
- The worker owns its temp cleanup trap and exits without inheriting interactive Apple Terminal shell-session hooks.
- The dashboard still calls only audited MographJailed protocol operations: `system.doctor`, `system.describe`, `runtime.verify`, and `storage.preflight`.

## Portable QA

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
| dev.4 terminal/registry | 63/63 |
| dev.4.1 Mac hotfix | 12/12 |
| **Deterministic total** | **421/421** |
| Protocol fuzz | **1,000/1,000; 0 failures** |

## Remaining target-Mac gate

The release is not considered fully Mac-qualified until the updated dashboard is rerun on the production Mac and confirms:

- `Runtime verify` = PASS
- no `Saving session...` output after `mj-top`
- normal/ascii/plain snapshots return cleanly
- no `mj-top-*` temp files remain after normal exit or Ctrl-C
