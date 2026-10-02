# MographJailed Troubleshooting

## Quick health check

```text
mj-status
```

Expected healthy state:

```text
Status          : READY
Core            : PASS
Warnings        : 0
```

For the full response:

```text
mj-doctor
```

## Runtime path

```text
~/Documents/MographJailed/dist/mograph-jailed.zsh
```

## Direct usage

```text
/bin/zsh -f ~/Documents/MographJailed/dist/mograph-jailed.zsh --request /tmp/request.req
```

## If an operation says unavailable

Run `system.describe` or `mj-doctor`. Do not install missing third-party dependencies. A missing optional native capability should degrade gracefully.

## Error codes

Every error `code` (`OUTPUT_EXISTS`, `TEMP_REFUSED`, `STAGE_CLEANUP_REFUSED`, …) is explained, with the exit code and what to do, in `mj-man errors`.

## If a new development build behaves unexpectedly

Do not delete the timestamped updater backup. Use `mj-man recovery`.

## Dashboard won't start

**`mj-observe-dash: CLI not executable`** — the dashboard can't find the CLI. It defaults to `dist/mograph-jailed.zsh` inside the repo; point it at your CLI explicitly:

```text
tools/mj-observe-dash.zsh --cli /path/to/mograph-jailed.zsh --versions ~/AE_Versions
```

**`MJ VERSION metadata is incomplete` (mj-top exits 66)** — `mj-top` needs the repo's `VERSION` file to have both a version line and a protocol line:

```text
MographJailed 0.4.0-dev.3
Protocol 1
```

The protocol number must match the protocol the CLI speaks (see `MOGRAPHJAILED_PROTOCOL_VERSION` in the CLI). Don't hand-edit it — it ships with the repo.

## Is After Effects reachable?

With After Effects open and no project loaded:

```text
zsh tests/live/run_ae_hall_of_horror.zsh
```

It checks that After Effects is found, answers AppleScript and may write files. Then it builds a deliberately hostile project and runs the whole pipeline on it in After Effects: scrape, check, conform, extract, the runner's refusals. It confirms the original never changes. If the first steps fail, allow Terminal to control After Effects (System Settings > Privacy & Security > Automation), clear any open dialog, and turn on Allow Scripts to Write Files and Access Network. Add `--keep` to keep the scratch folder.

`bash tests/run_hall_of_horror.sh` is the portable half (part of the test suite). It throws about 250 hostile inputs at the CLI: odd paths, FIFOs, a 9 GB sparse file, JSON bombs, broken receipts, protocol abuse, injection strings, odd locales and time zones, and racing snapshots and indexes.

