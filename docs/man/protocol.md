# MOGRAPHJAILED Protocol v1

MographJailed accepts a request file rather than arbitrary shell text.

Minimal request:

```text
MOGRAPHJAILED_REQUEST 1
requestId=my-request-001
command=system.doctor
```

Invoke:

```text
/bin/zsh -f ~/Documents/MographJailed/dist/mograph-jailed.zsh --request /tmp/request.req
```

Arguments are passed as named protocol fields. Path-like argument values are Base64-encoded so filenames are not interpolated into arbitrary shell commands.

Responses are JSON envelopes containing:

```text
protocol
protocolVersion
cliVersion
requestId
command
ok
data
warnings
error
```

On failure, `ok` is false and `error.code` / `error.message` explain the fail-closed result.

Do not add a general `shell.execute`, `raw.exec`, or equivalent operation.
