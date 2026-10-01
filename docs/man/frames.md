# Frame tools: loop seams and golden frames

These work on a folder of PNG frames, such as render output. Frames are the regular `.png` files in the folder, sorted by name (8- or 16-bit, up to 2,000). Sources are never changed.

## loop.seams

```text
mj loop.seams path=/work/renders/hero.20261001T120000Z minFrames=24 maxResults=5
```

Ranks the best start and end frames for a seamless loop. The loop plays `startFrame` to `endFrame-1`, and `endFrame` is the frame that should match `startFrame`.

- `minFrames` is the shortest loop to consider (default: half the frames).
- Scores run 0 to 1; higher means the end frame looks more like the start frame. Near-duplicate results are removed.
- Compares color distribution and an 8x8 brightness/colour grid, so it is a fast coarse ranking, not a pixel diff.

## golden.record and golden.check

Use these to catch a look changing after a plugin, Redshift or macOS update.

```text
mj golden.record path=/work/renders/hero_v1 output=/work/golden label=hero_master
mj golden.check  path=/work/renders/hero_v2 input=/work/golden/hero_master.golden.json threshold=0.98
```

`golden.record` saves a SHA-256 and a signature for every frame to `<label>.golden.json`. It will not overwrite an existing record.

`golden.check` compares a new render, frame by name:

- `identical`: same bytes.
- `pass`: bytes differ but the score is at or above `threshold` (default 0.98).
- `changed`: score below `threshold`.
- `missing`: frame not in the folder. Frames not in the record are listed as `extraFrames`.

The result has `passed`, `framesFailed` and `worstScore`.
