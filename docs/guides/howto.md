# How-to guides

## Check a render before it goes out

```text
$ mj qc render.mov broadcast-us
```

It checks the codec, size, frame rate, audio and loudness, and exits 1 if a check fails. The built-in specs are broadcast-us, broadcast-eu, web, social-vertical and prores-master; you can also write your own spec file (`mj-man qc`). Set a default once with `mj config set qc_spec broadcast-us`.

## Free disk space

```text
$ mj space
$ mj space clean leftovers --yes
```

`mj space` lists After Effects, Adobe media and Redshift caches by size and flags the ones left over from versions you no longer have. Cleaning takes a cache id, never a path, and refuses while the owning app is running (`mj-man space`).

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
