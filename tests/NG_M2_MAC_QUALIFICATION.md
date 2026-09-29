# NG-M2 Target-Mac Qualification

Target: `MographJailed 0.3.0-dev.2`

Run on the managed production Mac without sudo, Homebrew, Xcode/CLT installation, or system configuration changes. Use disposable local test files only. Do not use irreplaceable production assets for derivative tests.

## 1. Baseline

- Run `system.doctor`; require `ready:true` and no unexpected warning.
- Run `system.describe`; require 21 operations and registry version 2.
- Confirm `mdfind`, `xattr`, and `sips` availability is accurately reported.

## 2. Asset manifest / verify

Use a disposable local file and one representative read-only production media file.

- `asset.manifest` fast mode returns filename, size, mtime and `STAT_FINGERPRINT`.
- `asset.manifest` SHA mode returns SHA-256 and a stability check.
- `asset.verify` succeeds for known filename/size/mtime/SHA.
- A deliberately wrong expected field returns `ok:true`, `match:false`.
- Source file size/mtime/hash remain unchanged by every operation.

## 3. File provenance

Use one file with ordinary attributes and, if available, one downloaded/quarantined disposable file.

- `file.provenance` returns attribute **names only**.
- No attribute values are exposed.
- Run `xattr` before/after and confirm no attribute was created, changed, or removed.
- Verify a path containing spaces, apostrophe, and Unicode behaves as data rather than shell syntax.

## 4. Image inspection

Use disposable PNG/JPEG and, if available, a PSD supported by `sips`.

- Compare reported width/height/format/colorspace/alpha with known source facts.
- Verify source hash is unchanged.
- A plain-text/non-image regular file must fail with `INVALID_TARGET`; it must not return a successful null-filled image structure.
- Unsupported/corrupt images fail clearly rather than returning guessed metadata.

## 5. Image derivative

Use a disposable local image.

- Request PNG derivative with a bounded target dimension such as 512.
- Confirm output is newly created and no dimension exceeds the requested bound.
- Hash the source before/after and require exact equality.
- Repeat with the same output path and require overwrite refusal.
- Test output/input paths containing spaces, apostrophe, and Unicode.
- Test invalid targets below/above the allowed range and require fail-closed errors.
- After success and failure cases, confirm no `.MographJailed_Image.*` staging directory remains in the output parent.
- If a staging ownership marker is deliberately removed/tampered in a disposable test setup, cleanup must refuse rather than recursively delete the unproven directory.

## 6. Spotlight candidate search

Create/copy a disposable uniquely named file into an indexed user folder such as Documents and allow Spotlight to observe it.

- Search a scoped root with `search.candidate` and the exact leaf filename.
- Confirm returned paths are advisory and no file is moved/relinked/modified.
- Verify `maxResults` truncation behavior.
- Test a missing name: empty result must be valid, not a fabricated candidate.
- If Spotlight indexing is disabled/incomplete for a root, record that as an advisory-index limitation rather than treating it as an asset absence proof.
- If an SMB share is available, test and document whether Spotlight search is supported/complete there; do not assume it is.

## 7. Storage preflight

On local APFS:

- confirm filesystem/classification/free bytes/readability
- `requiredBytes` less than free space -> `enoughSpace:true`
- a deliberately oversized requirement -> `enoughSpace:false`
- treat `writableHint` as advisory only

If an SMB production share is available, repeat read-only preflight and verify network classification. Do not create/delete test data on the share unless already approved.

## 8. After Effects client

From After Effects, use the bundled client helpers read-only:

- `describe()`
- `can("asset.manifest")`
- `assetManifest(...)`
- `storagePreflight(...)`
- `inspectImage(...)` on a disposable local image

Do not run expensive hash/search/derivative operations in a latency-sensitive production comp during qualification.

## Pass criteria

- no source mutation
- no overwrite
- no Automation/TCC surprise prompt from these CLI paths
- no admin/install requirement
- correct fail-closed behavior when an Apple capability is unavailable
- advisory fields remain labeled advisory
- all paths are handled as data
