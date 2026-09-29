# M2 macOS filesystem / volume gate

Run these checks on a target Mac before promoting the release candidate:

1. Run `volume.inspect` against a known local APFS path.
   - `filesystem` should report `apfs` when `df -Y` is available.
   - `classification` should report `local`.
   - `filesystemSource` should report `df -Y`.
   - `writableHint` must be present and treated as advisory only.
2. Run `volume.inspect` against a mounted SMB production/test share.
   - `filesystem` should report `smbfs` when exposed by macOS `df -Y`.
   - `classification` should report `network`.
   - `writableHint` must not be interpreted as proof that a write will succeed.
3. If the target macOS does not support the expected filesystem-type path, the command must return `filesystem:null` / `classification:"unknown"`; it must not invent a filesystem type.
4. Confirm free-space values are plausible for both local and SMB paths.
5. Run `file.hash` on a small disposable local file.
   - Confirm `algorithm:"SHA-256"`.
   - Record whether `source` is `sha256` or `shasum`.
   - Confirm `stabilityCheck:"device+inode+size+mtime"`.
6. Confirm source files remain byte-identical and no mount/unmount or filesystem mutation occurs.
