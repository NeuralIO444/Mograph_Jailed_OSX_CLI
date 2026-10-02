# Tutorial 4: Render and verify

Rendering needs the real app installed. Everything here is a request to the allowlisted runtime; `mj explain` turns the JSON reply into plain language.

1. **Render**: `mj ae.render ...` runs `aerender`; `mj c4d.render ...` runs Cinema 4D's command-line renderer. Progress is written to a file that `mj ui` (Renders tab) and `mj status` read. See `docs/man/render.md` for arguments (`mj-man render`).
2. **Check the loop**: `mj loop.seams` compares the last and first frames of a render and tells you if the loop jumps.
3. **Check the frames**: `mj golden.record` stores approved reference frames and `mj golden.check` compares a new render with them.
4. **Silent failures**: if `aerender` exits 0 but nothing rendered (After Effects is waiting on a dialog), the reply carries a hint telling you to open After Effects once and clear the prompt.

Run `mj ui` for a live dashboard: Overview, Renders, Library, Audit (read-only).

Next: [Cinema 4D into After Effects](05-cinema4d-to-after-effects.md).
