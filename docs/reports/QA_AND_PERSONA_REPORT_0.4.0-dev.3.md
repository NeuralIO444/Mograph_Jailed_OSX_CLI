# QA, speed, designer experience, installer and persona-test report

Version 0.4.0-dev.3. Window covered: from the independent review agents (commit `7949d28` onward) through the first full persona run (`ae59c9d`). Date: 2026-10-02/03. Test machine: Apple silicon Mac, macOS 26, After Effects 26.5 and Cinema 4D 2026 installed.

This report joins two pieces of work: **Part A**, the QA/speed/designer review with the fixes and the installer that followed; **Part B**, the persona tests that were run against the result. Part B's findings are open GitHub issues #34 to #49 (milestone *Persona findings (0.4.0)*).

## Summary

- Two independent review agents audited the repository: one for correctness and safety, one for speed, designer experience and installation. 13 QA findings and about 25 measured or observed UX/speed items came back. **All QA findings that were defects were fixed and tested; the measured speed items worth the risk were fixed; the installer was built.**
- Speed (measured on this Mac): `system.describe` 2.3 s -> 0.5 s; `mj ops`, tab completion and recipes 2.3 s -> 10 ms on repeat runs; preflight font scan 0.5 s -> 0.2 s.
- A double-click installer, an uninstaller, a signed-release build and a shared install core now exist (77 installer checks).
- The persona tests (47 scenarios, 8 personas from first-week junior to adversary) then found **16 more problems, one of which is data loss** (the installer can delete a user's own `~/.zshrc` lines). They are filed as issues #34-#49. Nothing from Part B has been fixed yet.
- CI is green on every commit after `dcf2c73`. (One earlier run, `7949d28`, failed on Linux only; see "Honest notes".)

---

# Part A: review, fixes, speed, designer experience, installer

## A1. What was reviewed and how

| Reviewer | Scope | Method |
|---|---|---|
| QA agent | correctness and safety of the whole repo, focus on the newest work (preflight, cache clean, QC, extract/conform/jobs, the `mj` verbs) | read the code, built the test bundle, crafted requests in a sandbox HOME, reproduced every finding; findings it could not reproduce were dropped |
| Speed / UX / installer agent | latency of common commands, a new designer's first hour, the installer | timed 13 commands, counted process launches with xtrace, walked a scripted install into a scratch HOME, read the guides for jargon |

I verified findings before acting, and every fix below has a test.

## A2. QA findings and what was done

| # | Finding (as reported) | Severity | Result |
|---|---|---|---|
| 1 | `cache.clean` deleted the Adobe media cache while Media Encoder/Premiere ran (it matched `Adobe Media Encoder`, but the real executable is `Adobe Media Encoder 2026`) | high | **Fixed.** Matches a name or `<name> <anything>`; adds After Effects Render Engine and Cinema 4D Team Render. Test uses the real executable path. |
| 2 | Conform pointed `comp("X").layer("Y")` (also across a line break, or through a variable) at the wrong comp's layer | high | **Fixed.** A layer lookup is followed only when its comp is certain (`thisComp`, or `comp("..")` directly before `.layer`); other cases are left alone and counted as `DYNAMIC_REFERENCES`. Four expression shapes tested. |
| 3 | Two cache folders for one version got the same id; `clean` silently picked one; the test locked the bug in | medium | **Fixed.** Distinct ids (`-2`); test updated. |
| 4 | `mj extract`/`mj conform` looped forever when a flag (`--spec`, `--label`, `--out`) was the last word | medium | **Fixed.** `needs a value`, exit 64. |
| 5 | Extract could keep the wrong comps and report done (two clients each have a `Main.aep`; the report was matched by project name only) | medium | **Fixed.** Reports are matched by full resolved path; the engine refuses a mismatch (`PROJECT_SCRAPE_MISMATCH`, exit 65); the After Effects runner treats a name mismatch as an error. |
| 6 | `media.qc` spec validation was loose: tolerance 0 became 1; typos (`audio = requried`) and a spec with zero checks passed; `fps = abc` gave an undocumented error; the doc example broke when copied | medium | **Fixed.** Every value is validated up front (`INVALID_SPEC`, exit 65); tolerance 0 means exact; an empty result is an error; the doc was rewritten as a table. 15 new checks. |
| 7 | A network share with " (" in its name was classified local | low-medium | **Fixed.** Mount-table parse anchored on the last " (". |
| 8 | Default job labels over 64 characters; `mj` returned exit 1 instead of the runtime's 65 | low | **Fixed.** Stem cut to 40 characters; exit codes propagate. |
| 9 | Conform renamed layers/comps that already matched the spec and could collide | low | **Fixed.** Names that already match are reserved first. |
| 10 | `mj timeline` crashed on a report with no `scrapedAt` | low | **Fixed.** |
| 11 | `mj qc` usage printed the extract/conform help | low | **Fixed.** |
| 12 | `media.qc` decoded audio to TMPDIR with no space check; clips under 0.4 s reported "silent" | low | **Fixed.** Estimated size vs free space (loudness skipped with the reason); sub-0.4 s clips reported as not measurable. |
| 13 | The web installer merged into the old folder, leaving stale files | low | **Fixed** by the new install core (clean swap). |
| doc | `errors.md` says "89 codes" but lists about 124 rows; `HOST_BUSY`/`POLICY_DENIED` sit under "Renders" | doc | **Not done.** Low value; tracked in the backlog below. |

The QA agent also listed what it checked and found solid: symlink-safe deletion in `cache.clean`, cache id validation, job folders written with exclusive create and SHA-verified copies, embedding the job plan as ASCII JSON, `jobcheck` refusing plans that point outside their folder, the job runner's ES3 correctness and its guard, `mj ae run` passing the path as an argument, base64 on every request argument, glob-escaping in project resolution, and the BS.1770 meter (coefficients match libebur128; a 60 s stereo file measures in about 2 s).

## A3. Speed

Measured by the review agent before the changes, and by me after, on the same Mac (warm runs):

| Command | Before | After | How |
|---|---|---|---|
| `system.describe` (and anything that uses it) | 2,260-2,340 ms | **~530 ms** | `json_quote` rewritten in pure zsh: it started one `awk` per string (652 launches for one describe). Verified byte-identical to the old output on 3,022 strings in UTF-8 and C locales; a NUL byte regression was caught by the hall of horror and fixed. |
| `mj ops`, tab completion, recipes, each file in `mj batch` | 2,260 ms each | **10 ms** repeat | The operation list is cached on disk, keyed on the runtime's size and mtime (the old in-memory cache never filled: it was filled inside a pipe, which is a subshell). Refreshed daily; safe to delete. |
| `project.preflight` (font scan of 1,445 files) | 530-850 ms | **~210 ms** | Incremental font index in the private store; only changed files are re-read. |
| `mj check` | 1,440-1,690 ms | not re-measured | the three steps now run side by side |
| `mj timeline` (2 reports) | 1,285 ms | not re-measured | per-report health/diff run side by side |
| Finding a project's reports | one `jq` per report (+4 ms each; 202 reports: 1.3 s -> 2.1 s) | one process | `mj_find.py` |

Not done (judged lower value for the risk): removing the two extra `python3` launches per operation (about 70 ms each, around 30% of `lint`), caching the GPU line of `host.detect` (454 ms, used by the home screen). `zcompile` was measured and rejected (saves only ~10 ms).

## A4. Designer experience

Changes made (from the agent's walk-through of a first hour):

- `mj setup`: finds the projects folder (the usual places, the one with the most projects), creates the Reports and Versions folders, saves the settings, and shows the one After Effects step left; `mj scraper` reveals the script.
- `mj doctor` is now a checklist: After Effects / Cinema 4D found, projects/reports/versions folders, report count, automatic versioning, one fix per line.
- `mj help` rewritten in plain language ("First time", "Every day", "Fix and tidy", then "For scripts and pros").
- Typos: `mj chekc` -> `Did you mean "mj check"?`; unknown words no longer print a raw JSON envelope; failures on a terminal are explained, scripts still get JSON.
- Project names match by prefix in any case (`mj check spring`); ambiguity lists the names.
- The After Effects script's folder dialog says what it wants and pre-selects the Reports folder.
- The shell hookup is one file, `mj-init.zsh`, so moving the install folder only means changing `MOGRAPHJAILED_ROOT`.

Reported but **not** done: the home-screen hints still show developer commands (`mj index.add path=<receipts>`, `mkdir -p ~/Library/Logs/...`); the guides still use "receipt" 15 times and "scrape" 14 times; guide 01 does not yet start from "open Terminal". These are in the backlog.

## A5. The installer

- **Release package** from `sh scripts/make-release.sh` (optionally signed with an ed25519 key; verified on the Mac with stock `ssh-keygen`): `Install MographJailed.command`, `Uninstall MographJailed.command`, `README-FIRST.txt`, and a `payload/` of tracked files minus tests, research and CI, with its own checksum list. `ditto --norsrc --noextattr` keeps macOS metadata files out of the zip.
- **One shared core**, `tools/install-local.zsh`, also used by the web installer: verifies every file against `SHA256SUMS` and rejects extra regular files; stages a copy; **tests the new copy before touching an existing install**; swaps cleanly (no stale files; a folder that is not MographJailed is kept as `.previous`); strips quarantine from its own copy; adds one marked block to `~/.zshrc` (backed up first, idempotent); runs `mj setup`.
- **Uninstall** removes the folder and the marked block; never touches projects, versions or reports; asks before removing settings and the index.
- No sudo, nothing outside `$HOME`, no network after the download.
- **Known limit:** a downloaded `.command` file triggers macOS's "can't be opened" prompt; the user must click **Open Anyway** once in System Settings > Privacy & Security (no password). Removing that needs an Apple Developer ID and a notarised package. Documented in the zip and the README.
- 77 installer checks, including a tampered file, an extra file, a forged signature, and a re-install over an older copy.
- **Part B found defects in this installer** (#34, #41). They are real.

## A6. Test status at the end of Part A

`bash tests/run_all.sh` passes locally and on both CI platforms for commit `465b748`: the portable suite, macOS suite, fuzz, dist parity, checksum list and the two read-only guards. Notable counts: hall of horror 257, installer 77, After Effects jobs 89, delivery QC 51, studio 30, spaces 33, json_quote 4. The live After Effects hall of horror (`tests/live/run_ae_hall_of_horror.zsh`, 28 checks) was re-run on After Effects 26.5 after the conform/extract changes and passed.

---

# Part B: persona tests

## B1. What was built

`tests/personas/run_personas.py` (stdlib Python): scripted people use the **production build** (`dist/mograph-jailed.zsh`) and the real `mj` front end in a scratch HOME, and are judged on four questions: *safe* (nothing outside the sandbox or in an original changed), *plain* (words, not JSON/tracebacks/codes), *recoverable* (a next step is named), *fast*. Design: `docs/PLAN_PERSONA_TESTS.md`.

Eight personas: **Kiki** (first-week junior), **Marcus** (freelancer on Dropbox/iCloud), **Dana** (producer who delivers), **Sol** (senior designer, conform/extract), **Ines** (Cinema 4D/Redshift lead), **Theo** (pipeline TD), **Neo** (adversary), **Hello Kitty** (chaos).

## B2. Result

47 scenarios: **30 pass, 16 fail, 1 skip** (after four harness corrections, listed in B5). Every failure was read in full; F01 was reproduced by hand. Findings are filed as issues; each issue names the scenario that must pass when it is fixed.

## B3. Findings

| Issue | ID | Sev | Finding |
|---|---|---|---|
| [#34](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/34) | F01 | **high / data loss** | The installer (and uninstaller) delete the user's own `~/.zshrc` lines after an opening marker whose closing marker is missing. Reproduced. A backup is made but never mentioned. |
| [#35](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/35) | F02 | high | A 0-byte project (what an un-downloaded Dropbox/iCloud file looks like) is reported as a verified snapshot. |
| [#36](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/36) | F03 | high | `mj check` judges a stale report (project saved after it was made) without saying so. |
| [#37](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/37) | F04 | high | Accented names can't be found: composed (typed) vs decomposed (macOS) Unicode. |
| [#38](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/38) | F05 | high | Projects deeper than three folders are not found by name (`find -maxdepth 3`). |
| [#39](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/39) | F06 | high | `Logo.aep` vs `Logo.c4d` cannot be chosen by name or extension. |
| [#40](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/40) | F07 | high | First-run dead end: errors say `mj config set ...`, not `mj setup`. |
| [#41](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/41) | F08 | medium | Symlinks/FIFOs in a download bypass the extra-file check; a symlink to `/etc` is installed; a FIFO hangs the installer (123 s). |
| [#42](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/42) | F09 | medium | Terminal escape and bidi characters in project names reach the screen (`check`, `conform`, `explain`). |
| [#43](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/43) | F10 | medium | A 1 MB name makes `conform` print 977 KB and `check` take 11 s. |
| [#44](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/44) | F11 | medium | `mj check` says "ready" directly above a line flagged `!!`. |
| [#45](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/45) | F12 | medium | Spec files with a BOM are rejected; studio-spec errors are worded as delivery-spec errors; duplicate keys silent. |
| [#46](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/46) | F13 | medium | Curly quotes / em dashes pasted from chat apps are not understood. |
| [#47](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/47) | F14 | low | Conform rewrites text inside expression comments. |
| [#48](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/48) | F15 | low | No `mj version` (it suggests `mj versions`). |
| [#49](https://github.com/NeuralIO444/Mograph_Jailed_OSX_CLI/issues/49) | F16 | low | A killed snapshot leaves a hidden `.partial` file in Versions forever. |

Pattern worth noting: **eight of the sixteen are about finding things** (names, depth, Unicode, extensions, stale reports, empty files) and **three are about the installer** (F01, F08, and F07's first-run path). The deep verification paths (QC, concurrency, scale, hostile input) held up; the weak spots are the human edges of the front end and the installer's treatment of files it does not own.

## B4. What held up

- `mj check` correctly refuses "ready" for a missing font, footage deleted after the report, an expression that points at a layer that does not exist, and proxy-only footage.
- Delivery QC judged ten generated deliveries and six broken files correctly (silent, one dead channel, out-of-phase, clipping, mono 44.1 kHz, 5.1, a 1 s clip, H.264 against a ProRes spec; truncated, zero-byte, text renamed `.mov`, a symlink to `/etc/hosts`, a FIFO, a ProRes file named `.mp4`); unparseable specs fail with the line number.
- Concurrency: 32 mixed commands on one store; four terminals snapshotting one project (exactly one version); a stale lock from a dead process; a file edited during its own snapshot; a snapshot killed mid-copy (the next one works).
- Scale: 10,000 reports; 400 comps / 3,200 layers; 20,000 textures; reports from other scraper versions, with extra keys, numbers as strings, no layers, no date.
- Hostile input: symlinks, FIFOs and devices as arguments; catastrophic-regex expressions (no hang); cron-style environments (no HOME, empty PATH, `LANG=C`, closed stdout); 14 spec variants; look-alike names including NFC/NFD pairs; conform is idempotent.
- The "local only" promise: nine common commands ran unchanged with the network denied by `sandbox-exec`.
- Upgrade over an existing install kept settings, the store and a fresh operation list.

## B5. Harness corrections (not findings)

Four early failures were the harness's fault and were fixed before counting: the scratch config and sample reports pointed at the base fixture folder; a test re-created a file it had just deleted; `index.add` legitimately prints JSON; a "good" ProRes master was at -21 LUFS with no colour tags (the tool was right). Two assertions were relaxed because the behaviour is by design: writing through a symlinked `~/.zshrc` (what dotfile managers want), and `audit.verify` not detecting lines removed from the **end** of the log (inherent to a hash chain unless the head hash is kept elsewhere; documented).

## B6. Not run

- **H02, disk full:** the disk-image helper would not mount on this Mac; skipped.
- **Live After Effects personas** (unsaved project, the expression-parity oracle, the extract chain on a real tree) need After Effects open; designed in the plan, not built.
- **Chaos matrix** beyond kill, concurrent terminals, fd/memory limits and garbage input: clock jumps, sleep/low battery, filesystem renames mid-batch.
- The **donated real-project corpus** and `mj anonymize` (to build).

---

# Honest notes

- The commit `7949d28` (hall of horror) failed on Linux CI only: with no media tools installed, a bad `media.qc` spec name was reported as "unsupported" instead of "invalid argument". Fixed in `dcf2c73`; the hall now has a case that hides the tools.
- My first `json_quote` rewrite was byte-identical on 3,022 strings and still wrong for a NUL byte; the hall of horror caught it. The comparison corpus did not include NUL until after.
- A helper edit during the QA fixes deleted three shell functions (`_mj_comp_ids`, `_mj_ae_app`, `_mj_ae`); the After Effects job tests caught it immediately and they were restored.
- Part B has not been peer-reviewed by an independent agent; the findings were verified by reading the full failure text and, for F01, reproducing by hand.

# Backlog and next steps

1. Fix Part B in this order: **#34** (data loss), **#35**, **#36**, then **#40, #37, #38, #39, #46** (the new-designer path), then **#41, #42, #43**, then the rest. Each flips its scenario to a hard assertion; then wire `run_personas.py` into `run_all.sh` (fast tier) and a nightly tier.
2. Build the live After Effects personas (expression-parity oracle first) and the rest of the chaos matrix.
3. Small items from Part A: the `errors.md` count and sectioning; the home-screen hints; removing "receipt"/"scrape" from the guides; removing the two extra Python launches per operation if `lint` latency matters.
4. Apple Developer ID and a notarised package to remove the "Open Anyway" step.

# Where things are

| What | Where |
|---|---|
| Persona plan | `docs/PLAN_PERSONA_TESTS.md` |
| Persona harness and ledger | `tests/personas/run_personas.py`, `tests/personas/ledger.md` |
| Issues | #34-#49, milestone *Persona findings (0.4.0)*, labels `persona-test`, `data-loss`, `designer-ux`, `hardening` |
| Installer | `tools/install-local.zsh`, `uninstall-local.zsh`, `Install/Uninstall MographJailed.command`, `scripts/make-release.sh`, `tests/run_install.sh` |
| Hall of horror | `tests/run_hall_of_horror.sh`, `tests/live/run_ae_hall_of_horror.zsh` |
| Change history | `CHANGELOG.md` (0.4.0-dev.3) |
