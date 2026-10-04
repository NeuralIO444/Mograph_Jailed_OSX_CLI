# Fix report: issues #34 and #35

Commit `9f07497`, 2026-10-03. CI: green on all five jobs (Linux and macOS suites, fuzz, dist parity, read-only guards, sanitize guard). Both issues were closed automatically by the commit message. Found by the persona tests (`tests/personas/`); see `docs/reports/QA_AND_PERSONA_REPORT_0.4.0-dev.3.md`.

## #34: the installer must not delete a user's own `~/.zshrc` lines

**Cause.** `tools/install-local.zsh` and `tools/uninstall-local.zsh` removed the MographJailed block with an awk filter that starts skipping at the opening marker and stops at the closing one. With the closing marker missing, awk skipped to the end of the file and dropped everything the person had written after it. Reproduced by hand before the fix: a `MY_IMPORTANT_PATH` export and an alias vanished (a dated backup existed but nothing mentioned it).

**Fix.** Both scripts classify the block first (`block_state`: none / ok / bad). Only a complete, ordered, non-nested block is replaced or removed. For any other shape (lone opening marker, lone closing marker, reversed, nested, repeated) the file is left byte-identical and the person is told, in words, what is wrong and how to fix it by hand. Complete duplicate blocks left by older installs still collapse to one.

**Tests.** `tests/run_install.sh` grew from 77 to 113 checks: five malformed shapes, each verified unchanged after both install and uninstall (and no backup created, since nothing changed), duplicate complete blocks, and a lookalike line that is not a marker. Persona scenario **N03** passes.

## #35: never "verify" an empty or cloud-only project

**Cause.** Nothing checked that a project's bytes were on the Mac before copying and hashing it. A Dropbox, iCloud or Google Drive file that has not downloaded either reads as empty or triggers a download mid-copy, and the designer was told it was backed up.

**Fix.** `file_require_materialized()` in `src/modules/file.zsh` looks at file metadata only (it never reads the file, so it cannot start a download):

- a 0-byte file -> `FILE_EMPTY` (exit 65);
- a macOS "dataless" file (`SF_DATALESS`, 0x40000000), meaning stored online only -> `FILE_NOT_DOWNLOADED` (exit 74).

Both messages say, in plain words, to make the file available offline and try again. The check runs in `project.snapshot`, `project.restore`, `handoff.package`, the `project.extract` and `project.conform` jobs, and `ae.render` / `c4d.render`. New error codes are documented in `docs/man/errors.md`. The test bundle has a hook (`MJ_TEST_DATALESS=<path>`) to mark one file as a placeholder; it is not in the production bundle.

**Real-world verification.** This Mac has real placeholders. A Google Drive `.c4d` and a Dropbox `.aep` both report a normal size (419,622 and 304,780 bytes) with flags `0x40000060` and 0 blocks, so a 0-byte check alone would have missed them. Both were refused with `FILE_NOT_DOWNLOADED`; nothing was written; their flags and block counts were identical afterwards (no download was triggered).

**Tests.** New `tests/run_materialized.sh` (25 checks): empty `.aep` and `.c4d` through snapshot, handoff, extract, conform, restore and render; the placeholder case through four operations; real and 1-byte files still work; nothing is written on refusal; and the plain-language message through `mj`. Persona scenario **M01** passes.

## Notes

- While testing, `mj snapshot Empty.aep` still answered "matches more than one project" because the typed extension is ignored. That is issue **#39**, not part of this change.
- The persona ledger (`tests/personas/ledger.md`) marks F01 and F02 as fixed.
- Remaining open persona issues: #36-#49 (14).
