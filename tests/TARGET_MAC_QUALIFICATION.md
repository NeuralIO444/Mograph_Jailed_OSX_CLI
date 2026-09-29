# MographJailed 0.1.0-rc3 target-Mac qualification

Run these gates on the managed production/test Mac before promoting RC3 to `0.1.0`:

1. `M2_MAC_TEST_CHECKLIST.md` — local APFS + SMB filesystem classification, advisory write hints, and native hash adapter.
2. `M3_MAC_TEST_CHECKLIST.md` — `mdls` metadata behavior and proof that default inspection does not execute `avmediainfo`.
3. `M4_MAC_TEST_CHECKLIST.md` — After Effects request/response integration, `/bin/zsh -f`, clean stdout, Unicode/quote paths, and UI responsiveness.
4. `M5_MAC_TEST_CHECKLIST.md` — native `ditto` ZIP creation, canonical output behavior, symlink refusal, and no-overwrite behavior.

Additional environment checks:

- Record `system.probe` output for macOS version/build and architecture.
- Confirm no Python, Node, Homebrew, FFmpeg, Xcode/CLT, daemon, or local server is needed for production execution.
- Confirm no surprise Automation/TCC prompt appears during normal M1-M5 use.
- Confirm `system.probe`/`system.doctor` stdout contains exactly one MJ JSON envelope and is not contaminated by enterprise shell startup output.

M6 JXA/AVFoundation/Core Image is intentionally **not** a V0.1 promotion requirement.

Record macOS version/build, architecture, After Effects version, and pass/fail notes in a qualification receipt. Do not include usernames, machine serials, credentials, or confidential production paths in the exported receipt.
