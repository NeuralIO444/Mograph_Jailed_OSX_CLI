# Hosts and rendering

MographJailed can find and drive After Effects and Cinema 4D (2024 or newer) for renders. It never edits your projects or scenes.

## host.detect

```text
mj host.detect
```

Reports macOS version and chip, GPU and Metal support, whether you are at the console session, and each installed host: version, whether it is complete, whether it is supported (2024+), the render CLIs found, and whether Redshift is installed. Licensing is shown as `unverified`; it is only observed when a host actually runs.

Hosts are found only in `/Applications` as `Adobe After Effects <year>` and `Maxon Cinema 4D <year>`. Requests cannot name a host path.

## ae.render and c4d.render

```text
mj ae.render path=/work/hero.aep target="Main Comp" output=/work/renders label=hero range=0-119
mj c4d.render path=/work/logo.c4d output=/work/renders label=logo range=0-95 target="Hero Take"
```

- `output` must be an existing local folder. Each render gets its own new folder, `<label>.<UTC time>`, and never reuses one.
- Frames are PNG sequences. After Effects is forced to PNG output; Cinema 4D uses the scene's own renderer (Redshift or Physical) and only overrides the image path and format.
- `range` is START-END, inclusive. `timeoutSeconds` (10-86400, default 3600) is a hard limit. `version` picks a host year if you have several.
- After Effects is launched fresh (never reusing a running copy), and the project is closed without saving.

## The receipt

`render.json` in the render folder records the host and version, the exact command, frames rendered against frames expected, SHA-256 of the first and last frame, and the source file's SHA-256 before and after (`source.unchanged` must be true). `render.log` holds the host's output. Failed renders get receipts too.

Result codes: `RENDER_FAILED`, `RENDER_INCOMPLETE` (frames missing), `RENDER_TIMEOUT`, `RENDER_BUSY`, `LICENCE_NOT_CONFIGURED`.

## One at a time

Renders run one at a time per Mac, because they share one GPU and one licence. A second request while one is running returns `RENDER_BUSY`. A lock left by a crashed run is cleared automatically.

## Cinema 4D licensing

Cinema 4D's command-line tools ask which licence method to use the first time they run. MographJailed never answers that prompt: it stops the host and reports `LICENCE_NOT_CONFIGURED`. Run Cinema 4D's command line once by hand to set licensing up, then try again.

## After rendering

Rendered folders feed straight into `mj-man frames`: `loop.seams` and `golden.check` work on them as they are.
