# Tutorial 7: Studio tools

One-word checks, a project's history, pulling comps into their own project, and bringing a project to your studio's naming. Every output below is real.

## Is it ready? (mj check)

```text
$ mj check "Spring Promo"
Spring Promo.aep: 4 things to fix.

  !! Expressions: 1 error, 0 warnings.
  !! Health: 80 out of 100 (needs a look).
  !! Fonts: 2 missing (Brandon Grotesque, Inter).
  !! Footage: 1 missing (logo.psd).
  ?? Third-party effects to confirm: S_Glow.
```

It exits 1 while anything needs fixing. `--details` prints the full lint, preflight and health reports. With scraper 1.1, the font verdict comes from After Effects itself; otherwise from this Mac's font folders.

## What happened to this project? (mj timeline)

```text
$ mj timeline "Spring Promo"
Spring Promo.aep: 2 scrapes and 1 snapshot, oldest first (times are UTC).
  ...   health  92   first scrape
  ...   health  80   comp "Outro" added (0 layers); comp "Main": frame rate 24 -> 30; layer "Flash" added to "Main"; and 3 more
  ...   snapshot   26b2effec987
```

## Studio naming (mj conform)

```text
$ mj conform "Spring Promo"
Spring Promo.aep against MographJailed studio default: 4 changes.
  Rename comps (1):
    Lower Third -> PRE_Lower_Third
  Rename layers (3):
    Main / Title -> TXT_Title
    Main / Lower Third -> PRE_Lower_Third
    Lower Third / Name -> TXT_Name

This is a plan; nothing was changed.
```

With a scraper 1.1 receipt the plan also covers labels, folders, solids and adjustment layers, and updates every expression that names a renamed comp or layer. Write your own spec (`mj-man studio` lists every key) and set it once: `mj config set studio_spec ~/studio.mjstudio`. `mj conform "Spring Promo" --run` makes the job and sends it to After Effects.

## One comp as its own project (mj extract)

```text
$ mj extract "Spring Promo" "Lower Third" --label lower-third
Made an extract job: "Lower Third" from Spring Promo.aep.
  The new project keeps 1 comp and 1 footage item; 2 other comps and 1 footage item go.
  Job folder: ~/AE/versions/lower-third.mjjob

Your project is not touched: After Effects works on before.aep in the job folder and saves result.aep.
Next:  mj ae run ~/AE/versions/lower-third.mjjob
```

`mj ae run` sends the job to After Effects. The job closes your open project with the usual save prompt, works only on the job's copy, and saves `result.aep` next to it. Afterwards:

```text
$ mj ae verify ~/AE/versions/lower-third.mjjob
```

This confirms that the job ran and the result was saved, and that your original is byte-for-byte unchanged.
