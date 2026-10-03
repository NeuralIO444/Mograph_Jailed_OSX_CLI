# Persona test ledger

First full run of `python3 tests/personas/run_personas.py` against the production build (`dist/mograph-jailed.zsh`), branch `main` at commit `7f82847`, macOS, After Effects 26.5 present but not driven. 47 scenarios across 8 personas: **30 pass, 16 fail, 1 skip** after harness corrections (below). Every FAIL was read in full; the serious ones were reproduced by hand.

Filed as GitHub issues #34-#49 (milestone *Persona findings (0.4.0)*); full narrative in `docs/reports/QA_AND_PERSONA_REPORT_0.4.0-dev.3.md`.

Severity: **high** = a person is misled, loses data or is stuck; **medium** = confusing or unsafe at the edges; **low** = rough edge. "Fix" is a suggestion, not done. Each finding becomes a regression assertion when fixed (flip its scenario from known-gap to hard check).

## Findings, most serious first

| ID | Scenario | Sev | What the person experiences | Fix |
|---|---|---|---|---|
| [F01](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/34) #34 | N03 | **high** | **The installer deletes the user's own `~/.zshrc` lines.** If the opening marker exists without the closing one (hand-edited, interrupted), everything after it is dropped. Reproduced: `export MY_IMPORTANT_PATH=...` and an alias vanished. (A `.mj-backup-<date>` copy exists, but nothing says so.) | Remove a block only when both markers are present; if unbalanced, leave the file alone and say so. Same in the uninstaller. |
| [F02](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/35) #35 | M01 | **high** | **A 0-byte project is "verified".** `mj snapshot Cloud` on an empty `.aep` (what an un-downloaded Dropbox/iCloud placeholder looks like) prints "Saved a verified copy ... 0 bytes". The designer believes the project is backed up. | Refuse a 0-byte project; recognise dataless/placeholder files (`SF_DATALESS` / `st_blocks == 0` with size > 0) and say "this file is not downloaded yet". |
| [F03](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/36) #36 | D02 | **high** | **`mj check` judges a stale report without saying so.** Project saved after the report was made: still "ready"/"fine". Producers trust a verdict about the wrong version of the file. | Compare the report's `scrapedAt` with the project file's modification time; if the project is newer, say "this report is older than the project; run the After Effects script again" and do not call it ready. |
| [F04](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/37) #37 | M04 | **high** | **Accented names can't be found.** A project saved as `Cafe` + combining accent (what macOS stores) cannot be found by typing `Café` (one character). Looks identical on screen. | Normalise both sides (NFC) before comparing names in `_mj_resolve_project`, the report finder and the timeline. |
| [F05](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/38) #38 | M11 | **high** | **Projects deeper than 3 folders are not found by name.** `Client/Job/03_Motion/AE/Projects/Spot_v07.aep` (7 deep) -> "no project found". Real studio trees look like this. | Search deeper (a cached project index, or the already-built SQLite index, or a bounded `mdfind`); say how deep it looked when it gives up. |
| [F06](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/39) #39 | I06 | **high** | **`Logo.aep` and `Logo.c4d` cannot be chosen by name.** `mj snapshot Logo.aep`, `Logo.c4d` and `Logo` all answer "matches more than one project" and list three files; the extension is ignored. | Honour a typed extension as a filter; prefer an exact full-name match. |
| [F07](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/40) #40 | K02 | **high** | **First-run dead end.** Before `mj setup`, `check`, `snapshot`, `versions`, `lint`, `timeline` say "receipts folder not found... Set it once: `mj config set receipts_dir <folder>`". A newcomer is sent to a power-user command, not `mj setup`. | When a folder isn't set or doesn't exist, the first line should be `Run: mj setup`. |
| [F08](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/41) #41 | N01 | medium | **Non-regular files in a download bypass the "no extra files" check.** A symlink in the zip (`docs/etc-link -> /etc`) is installed as a symlink pointing outside the install folder; a FIFO makes the installer hang forever (123 s until killed). The checksum list covers regular files only. | Reject any non-regular file (symlink, FIFO, device) in the unpacked folder before copying. |
| [F09](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/42) #42 | N08 | medium | **Terminal escape characters in project names reach the screen.** A layer/comp/footage name containing `ESC[31m`, OSC 8 links, `ESC[2J` or a bidi override is printed raw by `mj check`, `mj conform` and `mj explain` (the other verbs are clean). A hostile or just unlucky project can repaint the display or spoof text. | Strip or visibly escape C0/C1 controls and bidi overrides in `mj_explain.py` before printing any name. |
| [F10](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/43) #43 | N07 | medium | **Giant names.** A 1 MB layer name makes `mj conform` print 977 KB and `mj check` take 11 s. | Truncate names for display (e.g. 120 chars + "..."); cap per-field work in planners. |
| [F11](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/44) #44 | D08 | medium | **The verdict and the bullets disagree.** A tidy project with no saved versions: "Tidy.aep: ready." directly above "!! Health: 75 out of 100 (needs a look)". | Either don't flag health when the only loss is "no snapshots yet", or don't say "ready" while a line is flagged. |
| [F12](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/45) #45 | S05 | medium | **House spec files with a BOM are rejected** ("unknown key ﻿name"): TextEdit/Notepad write them. Also: the studio-spec error text is worded for a *delivery* spec; duplicate keys silently take the last value. | Strip a UTF-8 BOM; reword per spec kind; warn on duplicate keys. |
| [F13](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/46) #46 | K03 | medium | **Curly quotes from Slack/Notes/web pages.** `mj snapshot “Spring Promo”` -> `no project found for "“Spring"`. An em dash typed for `--` (`—apply`) is treated as part of a name. | Normalise “ ” ‘ ’ to quotes and — / – to -- in the arguments, or at least say "that looks like a curly quote". |
| [F14](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/47) #47 | S01 | low | **Conform rewrites text inside expression comments.** `// thisComp.layer("Color") is an old name` becomes `TXT_`-renamed. No behavioural effect, but it edits what the author wrote. Everything else in 12 tricky expression forms (variable-held comps, computed names, `eval`, line-broken `.layer`) was left alone or flagged correctly. | Skip `//` and `/* */` regions in the rewriter. |
| [F15](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/48) #48 | K06 | low | `mj version` -> `Did you mean "mj versions"?` (a different command). No `mj version` / `mj --version` / `mj -V`. Support will ask for the version. | Add it. |
| [F16](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/49) #49 | M07 | low | A snapshot killed mid-copy (`kill -9`, lid closed) leaves `.Name.<time>.<hash>.partial.<pid>` in the Versions folder forever. The next snapshot works. | Sweep stale `.partial.*` files whose pid is gone on the next run. |

Known limit, not a defect: `audit.verify` cannot detect lines deleted from the **end** of the log (a hash chain needs the head hash kept elsewhere). Documented here so nobody is surprised.

## Not findings (harness corrections made during the run)

| What looked wrong | Why it wasn't |
|---|---|
| ~/.zshrc as a symlink: install wrote through it | That is what dotfile managers want; the test now fails only if the link is replaced. |
| `index.add` printed JSON in the parallel test | It is an operation, JSON is its output; the test now flags only failures. |
| Several "not found" results | The scratch config and sample reports still pointed at the base fixture folder; fixed in the harness. |
| A "good" ProRes master failed `broadcast-us` | The test file was at -21 LUFS and had no colour tags; the tool was right. The corrected master passes, and a further nine bad files (silent, one dead channel, out-of-phase, clipping, mono 44.1 kHz, 5.1, 1 s, H.264 .mp4, vertical) are all judged correctly. |

## What held up (worth knowing)

- **`mj check` says "not ready" for** a missing font, footage deleted after the report, an expression pointing at a layer that doesn't exist, and proxy-only footage (D01).
- **Delivery QC (D03/D05/D06):** ten generated files and six broken ones (truncated, zero-byte, text renamed .mov, a symlink to /etc/hosts, a FIFO, a ProRes file named .mp4) judged correctly; unparseable specs fail with the line.
- **Concurrency:** 32 mixed commands on one store, 4 terminals snapshotting one project (exactly one version), 20 repeat runs, a stale lock from a dead process, a file edited during its own snapshot, a killed snapshot - all recover (T03, H04, H05, M07 aside from F16).
- **Scale:** 10,000 reports (`check`/`timeline`/`index.add` inside budget), 3,200 layers, 20,000 textures, version-skewed and truncated reports (T02, S10, I02, T08).
- **Hostile input:** symlinks/FIFOs/devices as arguments, catastrophic-regex expressions (no hang), cron-style environments (no HOME, empty PATH, LANG=C, closed stdout), 14 spec variants (S05, minus F12), look-alike names with NFC/NFD pairs (S04), idempotent conform (S03).
- **The "local only" promise:** nine common commands run unchanged with the network denied by `sandbox-exec` (N12).
- **Upgrade over an existing install keeps settings, store and a fresh operation list** (T09).

## Not run yet

H02 (disk full) skipped: the disk-image helper did not mount on this Mac; to be redone. The live After Effects personas (K06 unsaved project, S02 expression parity oracle, S06 extract chain) need an open After Effects and are designed in `docs/PLAN_PERSONA_TESTS.md`. The chaos matrix beyond kill, concurrent terminals, fd/memory limits and garbage input (clock jumps, low battery/sleep) is still to build.
