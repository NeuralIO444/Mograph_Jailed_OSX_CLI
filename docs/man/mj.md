# The mj command

`mj` is the command-line front end for every MographJailed operation. It builds the request file, runs the runtime, and prints the JSON response.

```text
mj                                  launch screen (status of hosts, library, audit log, renders)
mj ui                               live dashboard (see mj-man terminal)
mj cd                               go to the MographJailed folder
mj ops                              list operations; required arguments are marked *
mj <operation> name=value ...       run one operation
mj recipe <file> name=value ...     run a recipe
mj last                             show the newest render receipt
mj open-last                        open the newest render folder in Finder
mj status                           one-line status (rendering progress, last render)
mj notify on|off|test|status        notifications when renders, golden checks, recipes finish
```

Values with spaces need quotes: `mj file.inspect "path=/Users/me/My Project/a.aep"`.

## Everyday commands

These are plain-language wrappers over the operations below; every one prints sentences, not JSON.

```text
mj snapshot "Spring Promo"       save a verified version (a path or a name searched under watch_dir)
mj versions [name]               list saved versions, newest first
mj lint [last|<scrape>]          check expressions: what is wrong, why, and the fix
mj health [last|<scrape>] [--record]   0-100 score; --record keeps it for the trend
mj diff last                     what changed between your two newest scrapes
mj diff <older> <newer>          ... or between any two
mj explain [last|<file>]         any receipt or response, in plain language
mj watch on|off|status           automatic versioning of your .aep files
mj doctor                        is this Mac ready? what is missing, and what to do
```

`last` means the newest scrape receipt in your receipts folder (or, for `mj explain`, the newest render).

## Remembered settings

Set a folder once and every tool remembers it:

```text
mj config set versions_dir ~/AE_Versions
mj config set receipts_dir ~/AE_Receipts
mj config set watch_dir ~/Movies
mj config show          settings, and where each value came from (env, file or default)
mj config path          where the file lives (~/.config/mograph-jailed/config)
```

Keys: `versions_dir`, `receipts_dir`, `watch_dir`, `cli`, `post_snapshot_hook`. Precedence is always flag, then environment (`MJ_VERSIONS_DIR`, `MJ_RECEIPTS_DIR`, `MJ_WATCH_DIR`, `MJ_CLI`, `MJ_POST_SNAPSHOT_HOOK`), then the file, then the default. The file is read as plain text and never run as code.

## Snapshot hooks

To run your own script after each new snapshot (copy the receipt to a server, send yourself a message, start a check):

```text
mj config set post_snapshot_hook ~/bin/after-snapshot.sh
```

The watcher runs it with the receipt path as its first argument (and `MJ_SNAPSHOT_RECEIPT`, `MJ_SNAPSHOT_PATH`, `MJ_SOURCE_PATH`, `MJ_SNAPSHOT_SHA256` in its environment). Because it runs unattended, it must be a full path to a regular file you own, executable and not writable by anyone else; otherwise the watcher logs `hook refused (...)` and skips it. It runs directly (not through a shell), with no input, and is stopped after 30 seconds. Its output goes to `hook.log` in the versions folder. A hook that fails, hangs or is refused never affects the snapshot, which is already saved. Hooks run only when a new snapshot was made, not when nothing changed.

## Tab completion

Press Tab after `mj` for the everyday commands and operation names, after a command for what it takes (project files, `last`, `on`/`off`, setting names), and after `name=` for file paths. Argument lists come from the runtime itself (`system.describe`), so they never go stale.

## Recipes

A recipe is a text file with one operation per line.

```text
# render-qa.mjrecipe
golden.check path={{frames}} input={{golden}}
loop.seams path={{frames}} maxResults=3
```

Run it with `mj recipe render-qa.mjrecipe frames=/path/to/frames golden=/path/to/hero.golden.json`.

- Lines starting with `#` and blank lines are ignored.
- `{{name}}` is filled from the command line; a missing value stops the recipe before it starts.
- Every operation and argument name is checked against the runtime before the first step runs.
- Recipes are data. Shell syntax inside a recipe is never executed.
- The recipe stops at the first failing step and returns its exit code.

An example lives in `recipes/render-qa.mjrecipe`.

## Output

On a terminal, `mj` pretty-prints JSON (needs `jq`, which ships with macOS). Piped, it prints the raw envelope: `{ok, data, error, ...}`. Exit codes follow the runtime (65 bad request, 69 unsupported, 73 output problem, 74 operation failed, 77 permission).
