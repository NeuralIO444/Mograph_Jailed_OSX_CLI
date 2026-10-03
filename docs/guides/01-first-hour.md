# Tutorial 1: Your first hour

You will install MographJailed, tell it where your folders are, and save your first verified project copy. About 10 minutes.

## 0. Install

Unzip the download and double-click **Install MographJailed.command** (if macOS objects, *System Settings > Privacy & Security > Open Anyway*). Then open a new Terminal window. There is nothing to type to install it.

```text
$ mj setup
```

`mj setup` asks where your projects live and where to keep reports and versions (Enter accepts each suggestion), then shows the one After Effects step left: File > Scripts > Run Script File, pick the script it names, and save the report into your Reports folder. The rest of this tutorial shows the same settings being made by hand, so you can see what `mj setup` did.

## 1. Check the Mac

```text
$ mj doctor
This Mac is ready. All 56 operations can run.
```

If something is missing, `mj doctor` says what and how to fix it.

## 2. Tell mj where things live

```text
$ mj config set versions_dir ~/AE/versions
saved: versions_dir
$ mj config set receipts_dir ~/AE/receipts
saved: receipts_dir
$ mj config set watch_dir ~/AE/projects
saved: watch_dir
$ mj config show
config file: ~/.config/mograph-jailed/config
  versions_dir         (file)    ~/AE/versions
  receipts_dir         (file)    ~/AE/receipts
  watch_dir            (file)    ~/AE/projects
```

`versions_dir` is where copies go, `receipts_dir` is where the After Effects scraper script drops its reports, `watch_dir` is the folder of projects to watch. Settings come from a flag first, then an environment variable, then this file.

## 3. Take a snapshot

```text
$ mj snapshot "Spring Promo"
Saved a verified copy of Spring Promo.aep.
  ~/AE/versions/Spring Promo.<time>.26b2effec987.aep
  15 bytes copied instantly (copy-on-write); the copy and the original were checked and match.

$ mj snapshot "Spring Promo"
Nothing to save: Spring Promo.aep has not changed since the last snapshot.
```

The name is enough; `mj` finds the project. It never overwrites an older version and never touches your original. `.c4d` scenes work the same way.

```text
$ mj versions
Versions in ~/AE/versions (newest first):
  Spring Promo                 <date> <time>     15 bytes   26b2effec987
```

Next: [automatic versions](02-automatic-versions.md).
