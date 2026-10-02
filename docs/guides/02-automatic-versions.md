# Tutorial 2: Automatic versions

Instead of remembering to snapshot, let the watcher do it.

1. Make sure `watch_dir` and `versions_dir` are set ([tutorial 1](01-first-hour.md)).
2. Turn it on: `mj watch on`. This installs a per-user LaunchAgent (no daemon, no admin rights); `mj watch off` removes it.
3. Check it: `mj watch status` shows whether it is on and the last few log lines; `mj status` shows the one-line state.

```text
$ mj status
MJ - idle
$ mj notify status
notifications off  (mj notify on)
```

Turn on notifications with `mj notify on` to get a macOS banner when a version is saved or something fails. Add the status to your prompt or menu bar with `mj status` or `integrations/swiftbar/mj.10s.sh`.

Every save of a `.aep` or `.c4d` in the watched folder becomes a verified copy. Unchanged saves are skipped. To run a script after each snapshot (back it up, ping a channel), see the [hook how-to](howto.md#run-a-script-after-every-snapshot).

Next: [find and fix what is wrong](03-find-and-fix.md).
