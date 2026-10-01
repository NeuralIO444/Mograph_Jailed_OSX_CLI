# Audit log, protecting work, and project audits

## Audit log

Create a folder once to turn it on:

```text
mkdir -p ~/Library/Logs/MographJailed
```

From then on every request adds one line to `audit.jsonl` there: time, command, arguments, exit code, and the SHA-256 of the previous line. Check it any time:

```text
mj audit.verify path=$HOME/Library/Logs/MographJailed/audit.jsonl
```

An edited, inserted or deleted line breaks the chain at that point and `audit.verify` reports the line. Keep a copy of the reported `headHash` elsewhere to also detect a cut-off tail. Remove the folder to turn logging off. Logging never changes any result.

## Restore, dependencies, handoff

```text
mj project.restore path=/work/versions/hero.<snapshot>.aep output=/work/restored
mj deps.graph path=/work/receipts/hero.scrape.json
mj handoff.package path=/work/hero.aep input=/work/receipts/hero.scrape.json output=/work/out label=client_v1
```

- `project.restore` copies a snapshot out as a new `.aep`. If the snapshot has a receipt, its bytes must still match or the restore is refused.
- `deps.graph` lists each comp's footage, precomps and effects, what is missing, and which dependencies would break the most comps (a missing file in a precomp breaks every comp that nests it).
- `handoff.package` builds `<label>.handoff/` with the project, local footage (image sequences included), `MANIFEST.json` with a SHA-256 for every file, and a `README.txt` listing fonts, plug-ins and missing footage. The project is not relinked; the README says how.

Footage on network volumes is never opened or copied. It is reported as unverified or skipped.

## Project audits

These read the local index (see `mj-man library`), built from After Effects scrape receipts.

```text
mj trace.asset format=missing
mj trace.asset target="logo.psd"
mj trace.asset format=font target="Brandon Grotesque"
mj audit.plugins target=S_Glow
mj audit.plugins
```

- `trace.asset` shows, for each project, every layer that uses the asset or font and the full nesting chain from a root comp down, for example `Main > Mid > Inner`. `format=missing` lists every missing asset. Add `path=/the/project.aep` to look at one project.
- `audit.plugins target=<matchName>` lists the unique projects that use that exact effect (case-sensitive). With no target it lists every effect `matchName` in the index with how many projects use it, which is the annual plugin audit.
- Only each project's newest indexed scrape counts. Projects that were never scraped are not covered.
