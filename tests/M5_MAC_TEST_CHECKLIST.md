# M5 macOS package gate

1. Create a disposable report folder containing JSON/text/images.
2. Submit `package.create` with an absolute, non-existing `.zip` output path.
3. Confirm `ok:true`, `sourceTool:"ditto"`, a canonical `resolvedOutput`, and a non-zero archive size.
4. Open the ZIP and verify the source folder is retained as the archive root.
5. Re-run against the same output and confirm `OUTPUT_EXISTS`; the archive must remain byte-identical.
6. Test source/output paths containing spaces, apostrophes, and Unicode.
7. Test a symlink as the top-level package source and confirm `INVALID_TARGET`.
8. If practical on disposable paths, test an output parent reached through a symlink and confirm the returned `resolvedOutput` is the canonical parent path.
9. Confirm source files remain byte-identical and no archive is overwritten.
