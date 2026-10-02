# How-to guides

## Find projects that use a plugin or effect

First index your receipts (once, and again when new ones arrive):

```text
$ mj index.add path="$HOME/AE/receipts"
```

Then:

```text
$ mj audit.plugins target=S_Glow            # which projects use it
$ mj audit.plugins                          # every effect and how many projects use it
```

## Trace a missing file or font

```text
$ mj trace.asset format=missing
$ mj trace.asset format=font target="Brandon Grotesque"
```

Each match lists the project and the comp path, for example `Main > Lower Third`, down to the layer.

## Notifications and status line

`mj notify on|off|status` toggles banners. `mj status` prints one line for a prompt. For the menu bar, copy `integrations/swiftbar/mj.10s.sh` into your SwiftBar folder.

## Recipes and batches

A recipe is a text file of steps. Run one on every receipt in a folder:

```text
$ mj batch recipes/check-scrapes.mjrecipe ~/AE/receipts
  ✓ spring.20261001T090000Z.scrape.json
  ✓ spring.20261001T163000Z.scrape.json

2 files: 2 ok, 0 failed
```

## Run a script after every snapshot

`mj config set post_snapshot_hook /absolute/path/script`. The script must be a regular file you own, not writable by group or others, in a folder with safe permissions. It gets 30 seconds, runs in its own process group, and can never make a snapshot fail.

## Verify and pin the install

The installer checks `SHA256SUMS`. To pin an exact release, set `MJ_INSTALL_REF` and `MJ_INSTALL_SHA256`; `MJ_INSTALL_YES=1` runs unattended. Every operation is logged; check the log with `audit.verify`.

## Read an error

Errors show a code such as `STORE_UNAVAILABLE`, what it means and what to do. `mj explain` works on any saved reply. The full list is `docs/man/errors.md` (`mj-man errors`).

## Troubleshooting

`docs/man/troubleshooting.md` (`mj-man troubleshooting`), and always start with `mj doctor`.
