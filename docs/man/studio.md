# Studio tools: check, timeline, extract, conform

These work from scrape receipts (run the After Effects scraper, version 1.1 or later, on the project first). Extract and conform need After Effects to finish the job, and only ever change a copy.

## mj check

```text
mj check "Spring Promo"          newest scrape of that project
mj check last --details          also print the lint, preflight and health reports
```

One verdict from three checks: expressions (`expression.lint`), the health score (`project.health`), and `project.preflight`. Exits 1 when something must be fixed, so scripts can gate on it.

`project.preflight path=<scrape>` answers "will this open cleanly on this Mac?":

- Fonts: After Effects' own missing-font report (scraper 1.1 on After Effects 24.0+) wins; otherwise the font files in /System/Library/Fonts, /Library/Fonts, ~/Library/Fonts, Adobe Fonts and macOS downloadable fonts are read (PostScript and family names). Fonts from a font manager's own vault are not seen; add its folder with `MJ_FONT_DIRS=/path:/other`.
- Footage reported missing, or gone from disk since the scrape. Network volumes are never touched.
- Third-party effects (anything not ADBE, CC, APC, Keylight, ...) to confirm are installed.

## mj timeline

```text
mj timeline "Spring Promo" [--all]
```

Every scrape (with its health score and what changed since the one before) and every snapshot of the project, oldest first, in UTC. The newest 10 scrapes, or 50 with `--all`.

## mj extract

```text
mj extract "Spring Promo" "Lower Third" "End Card" [--label NAME] [--out FOLDER] [--run]
mj extract "Spring Promo" '#12'                   a comp by id, when two share a name
```

Makes a job that keeps those comps and everything they use (precomps, footage, solids) as a new project, using After Effects' own Reduce Project. Job folders go in your versions folder unless you pass `--out`.

## mj conform

```text
mj conform "Spring Promo"                 the plan only; nothing changes
mj conform "Spring Promo" --apply         make a job
mj conform "Spring Promo" --run           make a job and send it to After Effects
mj conform "Spring Promo" --spec house.mjstudio
```

Brings a project to a studio spec: comp names (precomps get a prefix), layer names by kind, labels by kind, project-panel folders, and every expression that refers by name to a comp or layer being renamed. A broken reference with exactly one close match (`"Nme"` when `"Name"` exists) is suggested; with `fixBrokenRefs = apply` it is fixed. Names are only ever prefixed once; duplicates get `_2`, `_3`.

The studio spec is UTF-8 `key = value` text (`mj config set studio_spec <file>` to make it the default); a leading UTF-8 BOM is ignored. If a key is repeated, the last value is used and the result carries a `DUPLICATE_SPEC_KEY` warning naming both line numbers. Every key, with the built-in default:

```text
name = MographJailed studio default
precompPrefix = PRE_
mainCompPrefix =
spaces = _                       keep, _ or -
layerPrefix.text = TXT_          also: shape SHP_, solid SOL_, null NULL_, adjustment ADJ_,
                                 camera CAM_, light LGT_, precomp PRE_, footage (none), audio AUD_
label.text = 1                   0-16, or empty to leave labels alone; also shape 8, solid 2, null 11,
                                 adjustment 5, camera 4, light 6, precomp 15, footage 14, audio 7
label.mainComp = 9
label.precompItem = 15
folder.mainComps = 01_Comps      empty to leave items where they are
folder.precomps = 02_Precomps
folder.footage = 03_Footage
folder.solids = 04_Solids
folder.audio = 05_Audio
fixBrokenRefs = suggest          off, suggest or apply
```

An empty value turns that rule off.

## Jobs

`mj extract` and `mj conform --apply` write `<label>.mjjob/` holding `before.aep` (a verified copy of your project), `plan.json` (every step, with the value each item must still have) and `run.jsx`.

```text
mj ae run <job>       send it to the newest After Effects (macOS may ask to let Terminal control it)
mj ae verify <job>    did it run, is result.aep saved, is the original untouched?
```

Or in After Effects: File > Scripts > Run Script File, and pick `run.jsx`. The runner asks After Effects to close the open project (you get the usual Save prompt), opens `before.aep`, applies the plan, skipping any step whose item no longer matches, saves `result.aep` as a new file and writes `result.json`. Your original project is never opened. After Effects needs Settings > Scripting & Expressions > Allow Scripts to Write Files and Access Network.
