# Tutorial 3: Find and fix what is wrong

In After Effects, run the scraper script (`integrations/after-effects/MographJailed_ProjectScraper.jsx`) once per project. It only reads, and writes a receipt into `receipts_dir`. Everything below works from those receipts, with After Effects closed.

## Lint the expressions

```text
$ mj lint last
Checked 1 expression.
Found 1 problem: 1 error, 0 warnings, 0 notes.

Error in "Main" > Title > Transform/Position
  Expression references layer "Logo Mark", which does not exist in comp "Main".
  Why it matters: ...
  Fix: Fix the name, or pick-whip the layer so the link follows renames.
  Example, before:  thisComp.layer("Logo old").transform.position
  Example, after:   thisComp.layer("Logo").transform.position   // or pick-whip it
```

`last` means the newest receipt. You can also pass a project name or a receipt path.

## Health score

```text
$ mj health last --record
Spring Promo.aep health: 80 out of 100 (needs a look).
  footage: lost 12 of 35 points. Missing footage items: 1; unlinked: 0.
  expressions: lost 8 of 40 points. Expression errors: 1; warnings: 0.
Trend over 2 recorded scores: getting worse
Score formula version 1.
```

`--record` stores the score so the trend works. The score is footage (35) + expressions (40) + snapshot freshness (25), counting only what could be measured.

## What changed since last time

```text
$ mj diff last
Comparing spring.20261001T090000Z.scrape.json with spring.20261001T163000Z.scrape.json.
  1 comp added
  1 comp changed
  ...
  - comp "Main": frame rate 24 -> 30
  - footage "logo.psd" went missing
```

`mj diff last` compares the newest two receipts of the same project.

Next: [render and verify](04-render-and-verify.md).
