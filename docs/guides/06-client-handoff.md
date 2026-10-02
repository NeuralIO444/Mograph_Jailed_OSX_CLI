# Tutorial 6: Client handoff

Collect a project, its footage and its fonts list into one folder with a checksum for every file.

```text
$ mj handoff.package path=".../Spring Promo.aep" input=".../spring....scrape.json" output="$HOME/AE/out" label=spring_v2 > handoff.json
$ mj explain handoff.json
Built the handoff folder: .../AE/out/spring_v2.handoff
  2 files collected (2 bytes).
  Fonts to install: Brandon Grotesque, Inter.
  A manifest with a checksum for every file is inside.
```

The folder holds `project/`, `footage/`, `MANIFEST.json` and a plain-text `README.txt`. Paths must be absolute. Nothing is overwritten; a second run with the same label is refused.

Next: [studio tools](07-studio-tools.md).
