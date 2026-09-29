# M4 macOS / After Effects integration gate

Run `integrations/after-effects/MographJailed_AE_Spike.jsx` through **File > Scripts > Run Script File** after placing the project folder locally.

Acceptance checks:

- After Effects has **Allow Scripts to Write Files and Access Network** enabled (required by Adobe for script file I/O).
- The client invokes only `/bin/zsh -f` with the bundled CLI and a MJ-owned request-file path.
- `system.probe` returns one valid JSON MJ Native response with no startup text before/after it.
- Select local media with a normal path.
- Repeat with a filename containing spaces, apostrophe, and Unicode.
- Default inspection reports `Source unchanged (size+mtime): PASS`.
- Default `media.inspect` does not execute `avmediainfo`.
- No Finder/System Events/Terminal automation prompt appears.
- No source file modification occurs.
- Repeat the default inspection from an SMB-mounted source if available and record UI responsiveness.
- On one small disposable media file, separately call the explicit `inspectMediaImmutable()` SHA-256 verification path and confirm before/after hashes match.
- Do **not** use the double-SHA verification path as the default test for very large or network-hosted media; `system.callSystem()` is synchronous.
- If `/etc/zshenv` or enterprise shell policy emits output that contaminates stdout, record the machine as **qualification failed** until that environment behavior is understood; the client must not silently ignore non-JSON startup output.
