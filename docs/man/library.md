# Search index and preset library

MographJailed keeps one local database in `~/Library/Application Support/MographJailed` (set `MJ_STORE_DIR` to use another folder). It is created with owner-only permissions on the first command that writes to it, and must be on a local drive.

## Indexing

```text
mj index.add path=/work/receipts
mj index.search target="glow logo"
mj index.verify
```

- `index.add` reads scrape receipts, snapshot receipts, golden records and handoff manifests, from a file or a folder (searched recursively). Unchanged files are skipped. Other JSON is ignored.
- `index.search` matches words as prefixes, requires all of them, and ranks the best first. It finds comps, layers, effects, expressions, fonts, footage, snapshots, golden records, handoffs and presets. Punctuation and search operators in your words are ignored.
- `index.verify` checks the database, finds receipts that no longer exist on disk, and re-checks every stored preset against its hash.

Before anything is indexed, search and verify answer `STORE_EMPTY` and create nothing.

## Presets

```text
mj preset.add path=/work/presets/soft_glow.ffx label=soft_glow
mj preset.get label=soft_glow output=/work/out
mj preset.get label=soft_glow output=/work/out version=1
```

- Stores any file (up to 512 MB): `.ffx`, `.aet`, `.mogrt`, expressions, `.c4d`, Redshift materials.
- Each label keeps versions. Adding identical bytes again does not make a new version.
- `preset.get` checks the stored hash, then writes the original filename (or `name-v1.ext` if that exists). It never overwrites.
