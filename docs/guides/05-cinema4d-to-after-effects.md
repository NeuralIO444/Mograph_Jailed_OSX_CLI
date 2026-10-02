# Tutorial 5: Cinema 4D into After Effects

Run `integrations/cinema4d/MographJailed_C4DScraper.py` under `c4dpy` (read-only) to get a scene receipt, plus an After Effects receipt as in tutorial 3. Then:

```text
$ mj scene last --summary
Logo Sting.c4d (Cinema 4D 2026.3, redshift renderer)

1920 x 1080 at 24 fps, frames 0 to 71 (72 frames, 3.00 seconds).
Output: none set
...
2 textures; 1 missing (tex/chrome_normal.png).
```

`mj scene last` runs the scene lint (rules C001-C009: missing and absolute textures, empty output path, standard materials in Redshift, and so on), each with why, fix and a before/after example.

## The bridge

```text
$ mj bridge last last
Logo Sting.c4d against Summer Sale.aep: 1 layer used in After Effects.
The scene is 1920 x 1080 at 24 fps, 72 frames (3.00 seconds), redshift.

Error: Comp "Sting" runs at 30 fps; the scene is 24 fps.
  ...
```

The first `last` is the scene, the second the After Effects project. The bridge compares frame rate, size, length and the footage names that point at the scene's renders (rules B001-B005).

Note: the Cinema 4D scraper has not yet been validated against a real Cinema 4D; see `docs/MJ_C4D_SCRAPE_1.md`.

Next: [client handoff](06-client-handoff.md).
