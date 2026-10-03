# Plan: persona tests ("Hello Kitty meets Neo")

Status: draft for review. Nothing here is implemented yet except where marked **exists**.

## Why

The suites we have prove the machinery: contracts, exit codes, hostile input (`tests/run_hall_of_horror.sh`), and a live After Effects run (`tests/live/run_ae_hall_of_horror.zsh`). They are written by someone who knows the tool. The gap is the person who does not: the designer who types `mj` in the wrong folder, the studio lead with 4,000 projects, the pipeline TD who scripts everything and trusts nothing.

Each persona below is a **scripted person**: a fixed sequence of what they would actually type, in the order and with the mistakes they would actually make, run against a scratch HOME. A scenario passes only if the outcome would leave that person unhurt, informed and moving, not merely if the exit code was documented.

## The four questions every scenario answers

1. **Safe?** Did anything outside the scratch HOME, or any original project, change? (Checked by hashing before/after.)
2. **Understandable?** Is the last thing the person saw in plain words that name what happened and what to do next? No raw JSON, traceback, error code alone, or silence.
3. **Recoverable?** Can they get back to a working state with the next obvious command?
4. **Fast enough?** Interactive commands under 1 s warm, under 3 s cold; anything longer says it is working.

A scenario can fail any of the four with exit code 0.

## Personas (noob to seasoned)

| # | Persona | Who they are | What they stress |
|---|---|---|---|
| P1 | **Kiki**, first-week junior | Motion design student. Has never used Terminal beyond pasting commands. Copy-pastes from the README and from Slack with smart quotes. | Install, first run, typos, wrong folder, pasted text, no After Effects open |
| P2 | **Marcus**, freelance generalist | Fast in After Effects, Terminal-curious. Works from a laptop and a desktop sharing Dropbox. | Real folder layouts, iCloud/Dropbox placeholders, spaces and emoji in names, two Macs, interrupted work |
| P3 | **Dana**, studio producer | Not technical, owns delivery. Runs checks before sending to clients, files must be right the first time. | `mj check`, `mj qc`, specs, deadlines, "it said ready" trust |
| P4 | **Sol**, senior designer | Lives in expressions and precomps. Opinionated naming. Builds house specs. | `conform` and `extract` on ugly real projects, studio specs, expressions, labels |
| P5 | **Ines**, Cinema 4D / Redshift lead | Heavy scenes, Redshift, texture libraries on network volumes. | C4D receipts, `bridge`, absolute and missing textures, network mounts, huge files |
| P6 | **Theo**, pipeline TD | Writes scripts. Wants JSON, exit codes, idempotence, concurrency. | Request protocol, recipes, batch, parallel runs, cron-style use, weird environments |
| P7 | **Neo**, adversary / paranoid sysadmin | Locked-down Mac, no admin, MDM. Reads the code. Tries to break the sandbox. | Injection, symlinks, TOCTOU, permissions, tampered installs, forged signatures, resource exhaustion |
| P8 | **Hello Kitty** (cross-cutting) | A chaos persona: any of the above on a bad day. Cat on the keyboard, laptop at 3% battery, lid closed mid-job, disk full, clock wrong. | Everything interrupted, half-done, out of order, or hostile by accident |

## Scenarios

Format: **setup** -> **what they do** -> **sharp edge we are probing**. IDs are stable so failures can be tracked.

### P1 Kiki: the first hour

- **K01 cold install, wrong order.** Unzip, never open the installer, type `mj` in Terminal. Expect: a plain "not installed, here is how", not `command not found` with no help. *Edge: nothing we ship can answer before install; the README and the zip's README-FIRST must.*
- **K02 install, skip setup, run `mj check "My Project"`.** Expect: "no folder set, run `mj setup`" in words she understands, and the exact command. *Edge: the first-run dead end.*
- **K03 smart quotes and dashes.** Paste `mj snapshot “Spring Promo”` (curly quotes) and `mj conform proj —apply` (em dash). Expect: recognised and explained, not "no project found for “Spring". *Edge: copy-paste from chat apps. Likely a real bug today.*
- **K04 case and abbreviations.** `mj Check spring`, `MJ SETUP`, `mj snapshot spr`. Expect: case-insensitive project match works; verbs are lowercase-only and the message says so.
- **K05 ten wrong commands in a row.** `mj help me`, `mj --help`, `mj -h`, `mj how`, `mj install`, `mj update`, `mj uninstall`, `mj version`, `mj --version`, `mj fix`. Expect: every one answers usefully (the intended verb, or "use X"). *Edge: she will try verbs that sound right. We should have `mj version`.*
- **K06 runs the After Effects script with no project saved.** Scraper on an unsaved project. Expect: it says "save the project first", writes nothing broken. *Edge: `projectPath` is empty; downstream tools must cope.* (needs live AE)
- **K07 Terminal window too narrow / light theme / `TERM=dumb`.** `mj`, `mj help`, `mj ui`. Expect: readable, no garbled escape codes, no wrapped table soup.
- **K08 double Return, Ctrl-C everywhere.** In `mj setup`, press Return through everything, then rerun and Ctrl-C at each prompt. Expect: safe both ways, no half-written config.
- **K09 installs twice, then deletes the folder by hand.** Drag `MographJailed` to Trash, open a new Terminal. Expect: `~/.zshrc` block must not print an error on every new window (`mj-init.zsh: no such file`). *Edge: very likely real; the block is guarded with `[ -r ... ]`, verify.*
- **K10 uses `mj` on a project she has open in After Effects.** Snapshot and check while AE has it open and unsaved changes pending. Expect: honest about "this is the saved version".

### P2 Marcus: real folders, real mess

- **M01 Dropbox online-only placeholders.** Project and footage are cloud placeholders (size 0 or dataless). `snapshot`, `check`, `extract`. Expect: "this file is not downloaded yet", never a zero-byte snapshot reported as verified. *Edge: dataless files read as empty or trigger a download mid-hash.*
- **M02 iCloud Desktop & Documents.** Install root in `~/Documents` is synced; versions folder inside Dropbox. Concurrent sync conflict copies ("Spring Promo (Marcus's MacBook's conflicted copy).aep"). Expect: `versions`/`timeline` don't choke on conflict names; project resolve says "more than one match".
- **M03 two Macs, one shared folder.** Both run the watcher on the same projects. Expect: no duplicate versions, no lock fights over a network/sync folder, clear message if the lock lives on a synced volume.
- **M04 names from hell.** Project `Spring Promo FINAL v2 (client edit) — NEW!!.aep`, folder with `#`, `%`, `'`, `&`, leading dash, 200 chars, emoji, decomposed Unicode (NFD) vs composed (NFC) for the same name. Expect: found by typing the visible name either way. *Edge: macOS filenames are NFD; typed names are NFC. The classic invisible mismatch.*
- **M05 two projects, same name.** `~/Clients/A/Main.aep` and `~/Clients/B/Main.aep`. `mj check Main`, `mj extract Main ...`. Expect: asks which; never picks silently. (partly covered)
- **M06 project moved after scraping.** Scrape, move/rename the .aep, run `mj conform`. Expect: PROJECT_SCRAPE_MISMATCH explained in words with the fix.
- **M07 the lid closes mid-snapshot.** Kill -9 during `snapshot`, during `conform --apply`, during `space clean`. Expect: re-run is clean; no `.partial` clutter forever; no half cache emptied without saying so.
- **M08 external SSD unplugged mid-job.** Versions folder on a volume that disappears. Expect: error names the volume, not a stack trace; later runs recover when it returns.
- **M09 timezone and clock.** Travelling (TZ change), clock set a year in the past/future. Expect: `timeline` ordering and snapshot freshness stay sane.
- **M10 huge .aep (2 GB+) and a full disk.** `snapshot` with 100 MB free. Expect: refuses up front ("needs about X, Y free"), leaves nothing behind.

### P3 Dana: trust before delivery

- **D01 "Ready" must mean ready.** Project with one missing font (not installed), one proxy-only footage, one expression error, one disabled-but-broken layer. `mj check` must not say ready. Then fix each and re-check. *Edge: false reassurance is the worst bug for this persona.*
- **D02 stale report.** Edit and save the project after the report was made, then `mj check`. Expect: warns the report is older than the project file. *Edge: probable gap; the check can pass on yesterday's report.*
- **D03 delivery matrix.** One master rendered five ways (ProRes 4444, H.264 1080p, vertical, 23.976 vs 24 vs 25, with/without audio, mono vs stereo, 44.1 vs 48). `mj qc` against each spec. Expect: every wrong file fails for the right, named reason; every right file passes.
- **D04 sneaky audio.** Silent file; one channel silent; left/right out of phase (cancels in mono); clipping at +3 dBFS float; 5.1 with LFE loud; a 1-second clip; 8-hour audio (disk check). Expect: reported accurately or "not measured" with the reason.
- **D05 misleading container.** `.mp4` that is really ProRes `.mov`; a `.mov` with zero-length video track; truncated file; HDR/10-bit; variable frame rate. Expect: honest reading or "cannot read", never a pass by accident.
- **D06 client spec as email text.** Dana writes a spec file in TextEdit (rich text, smart quotes, `loudness: -24`). Expect: a spec that cannot be parsed says exactly what line and what to change.
- **D07 she re-runs everything 20 times.** Same `mj check` repeatedly, with `--record`. Expect: trend stays meaningful; no growth of junk files; same answer each time.

### P4 Sol: studio specs on real projects

- **S01 expressions in the wild.** Conform a project whose expressions use: `thisComp.layer(index)`, `layer("A").effect("B")("Slider")`, `comp(name)` with a variable, `thisLayer.name`, string concatenation to build layer names, `eval`, JavaScript expressions with `//` comments containing quoted names, ES6 template strings, `sourceText` expressions, controllers pointing at `Null 1` that also exist in precomps. Expect: renames only what is certain; lists what it could not follow; after running in After Effects, **zero new expression errors compared with before**. (live AE; the strongest test we can write.)
- **S02 expression parity oracle.** For a corpus of projects, evaluate every expression before and after conform in After Effects and compare values at several times. Differences are bugs. *This is the property that matters: conform must not change what the project looks like.*
- **S03 round trip.** conform, then conform again with the same spec: second plan must be empty (idempotent). Then conform with a different spec: no `_2` explosions, no double prefixes.
- **S04 collisions.** Layers `A`, `A_2`, `TXT_A`, `Text A`; comps differing only by case, trailing space, NFC/NFD, or only by an emoji. Expect: unique, stable, reversible, nothing silently merged.
- **S05 spec hostility.** House spec with prefixes containing spaces, slashes, `%`, 64-char values, labels 0 and 16, empty everything, duplicate keys, Windows line endings, a BOM, tabs. Expect: valid specs work, invalid fail with the line.
- **S06 extract chain.** Extract a comp that precomps 30 levels deep, shares footage with an unextracted comp, uses a font and a plugin, has a time-remap and a track matte across precomps, plus an expression reading a comp left behind. Expect: the new project opens with no missing items beyond those warned about. (live AE)
- **S07 extract then conform then extract.** Chain the three operations on the same project; every intermediate verified.
- **S08 undo story.** After a bad conform, Sol wants the old names back. Expect: the job's `before.aep` is a one-step answer, and `mj` says where it is.
- **S09 text layers.** Source text with styled runs, text animators with expression selectors, fonts missing at open time, text layer names equal to their contents (After Effects auto-renames until a manual rename). Expect: no data loss.
- **S10 big project.** 3,000 layers, 400 comps, 8,000 footage items (truncation paths in the scraper and planner). Expect: truncation said loudly in plain words; never a plan built on partial data without saying so.

### P5 Ines: Cinema 4D and the bridge

- **I01 absolute texture paths on three drives.** Textures on an unmounted network share, a mounted SMB share, a local SSD, `~`-relative, and a UDIM sequence. Expect: each classified correctly; the network ones are never touched (no hang).
- **I02 slow/hung mount.** Network share that stalls (simulate with a FIFO or a blocked FUSE-like stub). Expect: bounded time, a named reason.
- **I03 scene with 20,000 textures.** Scraper truncation shown in plain words.
- **I04 AE comp at 30 fps against a 24 fps scene across five layers, two retimed, one pre-composed.** `mj bridge` identifies exactly the right layers and the right fix; no false alarms on correctly retimed ones.
- **I05 Redshift-only features** (proxies, IPR, RS Light Dome, AOV list) in the scrape: names pass through without breaking planners.
- **I06 `.c4d` in Dropbox, saved by two people.** Versions of `.c4d` and `.aep` with the same base name in one folder; `latest` pointers must not cross.
- **I07 no licence for headless `c4dpy`.** The scraper is run and prompts for a licence. Expect: `mj scraper`-style guidance, no hang.

### P6 Theo: scripts, scale, concurrency

- **T01 contract fuzz from the outside.** Property tests over `request_schema_for`: every operation, every arg missing/duplicated/oversized/Unicode/NUL, expecting a documented code, one envelope, bounded time. (extends the hall of horror)
- **T02 10,000 receipts.** `mj batch`, `index.add`, `trace.asset`, `audit.plugins` at scale: time and memory bounds; FTS correctness (diacritics, quotes, `NEAR`, `OR`, `*`, SQL-ish text in the query).
- **T03 parallelism.** 32 simultaneous mixed operations on one store (snapshot + index + health --record + space inspect + conform plan): no lost writes, no corrupt DB, no deadlock, every result valid.
- **T04 cron environment.** Run verbs with an empty environment: no `HOME`, `PATH=/usr/bin:/bin`, `LANG=C`, no TTY, stdin closed, stdout a pipe closed early (SIGPIPE), `TMPDIR` unwritable, read-only HOME. Expect: documented failure, never a hang or half-write.
- **T05 recipes.** Recipes with `{{` oddities, missing params, 1,000 steps, a step that fails in the middle, a recipe that writes and is run twice (idempotence).
- **T06 exit codes as an API.** A table-driven test that every documented exit code is reachable and that no undocumented one ever is.
- **T07 JSON consumers.** `jq`/Python consumers on every operation's output with random inputs: always valid JSON, UTF-8, one line (NDJSON-safe).
- **T08 version skew.** Newer scrape schema fields, older scraper (1.0), unknown extra keys, missing optional keys, numbers as strings. Expect: tolerant reader, clear warnings.
- **T09 upgrade in place.** Install version N, populate store/config, install version N+1 (and N-1 over N): store migrates (or refuses cleanly), config survives, no stale cache (`describe-*.json`) misbehaves.

### P7 Neo: the paranoid

- **N01 installer attacks.** Zip with: path traversal entries (`../../.zshrc`), symlinks pointing out of the tree, absolute-path entries, case-folding collisions, a huge file (zip bomb), device nodes, setuid bits, `._*` files with payloads, an `__MACOSX` folder, a `SHA256SUMS` that lists `../x`. Expect: refused or neutralised; nothing outside the install folder ever written.
- **N02 signature games.** Valid signature over a different file; signature with another namespace; truncated `.sig`; `allowed_signers` swapped by the attacker (documented limit: the key travels with the zip; the plan must say what is and is not protected).
- **N03 `.zshrc` attacks.** Existing file is a symlink to somewhere else; read-only; contains our markers twice or only the opening marker; has CRLF; is huge; is a directory. Expect: refuse or repair safely; never truncate the user's file.
- **N04 symlinks everywhere.** Every path argument as a symlink to `/etc`, to a directory, to a FIFO, to a path that changes target between check and use (TOCTOU race with a flipper process). Expect: no read/write outside the intended location.
- **N05 cache.clean abuse.** A cache folder replaced by a symlink to `~/Documents` between inspect and clean; a cache id from another user; running as a different user's HOME; deleting while the app is mid-write.
- **N06 job runner abuse.** Edit `plan.json` to point at `/etc` or the original project; replace `before.aep`; replace `run.jsx` with something else (documented: a user can always run their own script; the claim is only about our runner). `project.jobcheck` must catch plan/copy tampering.
- **N07 resource exhaustion.** 50,000 expressions in one scrape; a 8 MB expression; a layer name of 1 MB; a font name of 100 KB; regex catastrophic backtracking inputs in expressions (`("A"*40)+"!"` against the lint and conform regexes). Expect: bounded time (< 5 s) and memory.
- **N08 log/UI injection.** Names containing ANSI escapes, OSC 8 hyperlinks, terminal title changes, bidi overrides (U+202E), zero-width characters, carriage returns that rewrite the previous line. Expect: sanitised in every human-readable output (`mj_explain`, `mj ui`, notifications).
- **N09 notification injection.** A project name that tries AppleScript/shell in `mj notify` text. Expect: shown literally.
- **N10 audit log tampering.** Edit, delete, reorder, truncate, duplicate lines; clock set back; symlinked log. `audit.verify` flags each.
- **N11 privilege.** Run as root, run with `sudo -u other`, run in a read-only home, run with a quarantined (`com.apple.quarantine`) runtime. Expect: sensible refusal or working; never a quiet root-owned file in the user's home.
- **N12 network.** `strace`-style check that no operation opens a socket (use `nettop`/`lsof` on macOS, `unshare -n` on Linux CI): the "local only" promise as a test.

### P8 Hello Kitty: chaos, run against every persona

A chaos driver injects one disruption per run into any persona script:

| Disruption | Where |
|---|---|
| kill -9 at a random point | any write operation |
| SIGSTOP for 30 s then SIGCONT | locks, timeouts |
| disk full (small tmpfs or a quota file) | snapshot, cache decode, job copy |
| out of file descriptors (`ulimit -n 16`) | scans, batch |
| low memory (`ulimit -v`) | font scan, scrape load |
| clock jump +/- 1 year, DST boundary, leap second-ish timestamps | timeline, snapshot names, freshness |
| the cat: random keys into every prompt, 200 chars of garbage, Return held down | all prompts |
| battery low: `caffeinate` off, laptop sleeps mid-run | long ops |
| second terminal opened, same command | locks |
| files edited during the run (project saved by AE while we copy) | snapshot, extract |
| Finder/Dropbox renames a folder mid-batch | batch, watcher |

Pass criterion for chaos: **after any disruption, the next normal command works, and nothing the person owned is lost or silently half-changed.**

## How to build it

### Harness (`tests/personas/`)

- `lib/persona.sh`: shared sandbox (scratch HOME, config, store, fake `/Applications`, fixtures from `tests/support/make_tutorial_fixtures.py` plus generators for hostile names and big corpora), a `say <line>` runner that records the exact command and the whole transcript, and assertions: `safe` (hash tree before/after), `plain` (no JSON/traceback/raw code in the last screen), `next_step` (output names a runnable command), `fast` (time budget), `recovers` (follow-up command works).
- `lib/pty.py`: pseudo-terminal driver (stdlib) so prompts, narrow widths, `TERM=dumb`, Ctrl-C and held keys can be tested as a person experiences them. (A pty driver existed during early development; recreate it as `ptydrive.py`, not `pty.py`, which would shadow the standard library.)
- `lib/chaos.sh`: the Hello Kitty disruptions as wrappers: `with_kill_at <ms>`, `with_disk_full`, `with_fd_limit`, `with_clock <offset>`, `with_second_terminal`.
- One file per persona: `p1_kiki.sh` ... `p8_chaos.sh`, scenarios named by ID, each printing `ID title: PASS|FAIL|XFAIL(reason)`.
- `tests/personas/ledger.md`: the **sharp-edge ledger**. Every failing scenario becomes a row: ID, what the person saw, severity, owner, fix commit, regression test. A scenario that is a known gap is committed as `XFAIL` with an issue link so the suite stays green while the gap stays visible; fixing it flips it to a hard assertion.

### Live After Effects (opt-in, like `tests/live/`)

S01, S02, S06, S09, K06 need After Effects. They extend `run_ae_hall_of_horror.zsh`: build the project, snapshot **expression values before**, run the job, evaluate **after**, diff. Gate on a visible AE and no open project; never run in CI.

### Corpus

- Synthetic generators (names, expressions, nesting depth, counts) so tests are deterministic and shareable.
- A small **donated corpus** of real, anonymised scrape receipts (layer names scrubbed, structure kept) from studios willing to share, since synthetic data never has the weirdness of a real project. Collect via a documented `mj anonymize` (to build) rather than asking for raw files.

### CI placement

| Tier | Runs | Contents |
|---|---|---|
| Fast (every push, Linux+macOS) | < 5 min | P1, P3, P6, most of P7 scenarios that need no AE, 3 chaos disruptions |
| Nightly (macOS) | < 40 min | scale (T02, S10, I03), full chaos matrix, N07 resource bounds, upgrade matrix T09 |
| Live (manual, AE open) | ~5 min | AE-dependent scenarios, expression parity oracle |

## Likely real bugs to look at first (hypotheses, not yet verified)

1. Smart quotes and em dashes from pasted commands (K03).
2. NFC/NFD names (M04): typed name vs on-disk name.
3. Stale report passes `mj check` after the project was saved again (D02).
4. Dataless cloud files read as empty (M01).
5. `~/.zshrc` block errors in every new window after the folder is deleted (K09).
6. Terminal escape / bidi characters from project names reach the screen unsanitised (N08).
7. Catastrophic regex backtracking on long expressions (N07).
8. Lock files on synced or network folders (M03).
9. `mj version` and other natural verbs missing (K05).
10. `conform` changes behaviour that is not a name (S02): the property test will tell.

## Done means

- All scenarios exist as either PASS or an XFAIL with an owner; the ledger has a row for each failure ever found.
- Every bug found has a regression test next to the persona scenario that found it.
- The expression parity oracle runs clean on the corpus.
- A new contributor can read one persona file and understand who the tool is for.

## Phases

1. **Harness and ledger** (pty driver, sandbox, assertions, chaos wrappers). Smallest runnable: K01 to K05.
2. **P1 to P3** (the people most likely to be hurt): K, M, D scenarios.
3. **P4 and the live oracle** (conform/extract correctness).
4. **P6 and P7** (protocol, scale, adversary).
5. **P5 and P8** (C4D, chaos matrix), nightly tier.
6. **Corpus and `mj anonymize`**.

Open questions for review: which real-world paths to prioritise (Dropbox vs iCloud vs SMB), whether to require Windows-line-ending and BOM tolerance in specs, whether `mj version` and `mj update` should exist, and who can donate anonymised receipts.
