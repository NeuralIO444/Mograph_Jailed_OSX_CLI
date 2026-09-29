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

## If a new development build behaves unexpectedly

Do not delete the timestamped updater backup. Use `mj-man recovery`.
