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
