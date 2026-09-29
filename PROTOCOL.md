# MJ Native Protocol v1

Request files use a deliberately small text format so the runtime does not depend on `jq`, Python, Node, or another downloaded parser.

```text
MOGRAPHJAILED_REQUEST 1
requestId=<restricted ASCII token>
command=<allowlisted command>
arg.path=<canonical Base64 of UTF-8 value>
```

Rules:

- Commands and argument names are compile-time allowlists.
- Each command has its own accepted/required argument schema; extra arguments fail with `UNEXPECTED_ARGUMENT`.
- Argument values use canonical Base64 so production paths never become shell syntax.
- Decoded Base64 is round-tripped before use; unsupported byte sequences fail closed.
- ASCII control characters are rejected in protocol arguments. This deliberately excludes unusual but legal filenames containing tabs/newlines/control bytes in exchange for a smaller, auditable boundary.
- NUL cannot be represented and is rejected by canonical encoding behavior.
- Request IDs are capped at 128 characters.
- A request is capped at 32 lines, each line at 32,768 characters, and each decoded argument at 16,384 characters.
- Unknown request fields are rejected.
- No request can contain a raw command line.

Responses are JSON envelopes containing `protocol`, `protocolVersion`, `cliVersion`, `requestId`, `command`, `ok`, `data`, `warnings`, and `error`.

Every failure response must contain a non-empty error `code` and `message`. stdout is protocol-only; diagnostics belong on stderr.

## Compatibility policy

- `protocolVersion` governs breaking request/response contract changes.
- `cliVersion` may change while protocol v1 remains compatible.
- A client may accept any CLI version that returns a supported protocol version.
- Consumers should ignore unknown additive response fields.
- A breaking command schema or semantic change after V1 qualification requires a protocol-version decision rather than silent reinterpretation.
- Unsupported request protocol versions fail with `BAD_REQUEST_VERSION`.


## NG-M1 additive operations

Protocol v1 now also allowlists `system.describe` and `runtime.verify`.

`runtime.verify` requires canonical Base64 arguments `expectedCliVersion` and `expectedProtocolVersion`; `expectedFilename` and `expectedSha256` are optional. Runtime mismatches are returned as a successful diagnostic operation with `data.compatible:false`, while malformed verification arguments fail closed with a normal protocol error envelope.

The capability registry is a data contract layered on Protocol v1; its own schema is `MOGRAPHJAILED_CAPABILITY_REGISTRY_2`.

## NG-M2 additive operations

Protocol v1 additionally allowlists the following operations:

- `asset.manifest`: required `path`; optional `format` (`fast` or `sha256`)
- `asset.verify`: required `path`; one or more of `expectedFilename`, `expectedSizeBytes`, `expectedModifiedEpoch`, `expectedSha256`
- `search.candidate`: required `path` (search root) and `target` (leaf filename); optional `maxResults`
- `file.provenance`: required `path`
- `image.inspect`: required `path`
- `image.derivative`: required `input`, `output`, and `target` (bounded maximum pixel dimension)
- `storage.preflight`: required `path`; optional `requiredBytes`

All argument values remain canonical Base64. New argument names are compile-time allowlisted. Search candidates are advisory; asset mismatches are returned as successful diagnostic results with `match:false`; image derivatives refuse overwrite and do not mutate the input.


## 0.2.0-dev.4.1 contract correction

Protocol v1 command schemas are unchanged. Capability Registry 2.0 now guarantees `requires.all` and `optionalCapabilities` are emitted as true arrays with one capability per string element under production zsh as well as QA shells. This corrects representation only; it does not add or reinterpret a public operation.

## 0.3.0-dev.1 / Standard Library 1.0 additive contract

Protocol v1 transport remains unchanged. dev.1 retained 20 public commands; dev.2 grows additively to 21 with `media.frame`.

Registry 2.0 adds a top-level `standardLibrary` descriptor and per-operation `executionScope`. These are additive fields.

The existing `media.timing` command is now implemented when the required Standard Library MediaProbe capabilities are present. Its request schema remains:

```text
command=media.timing
arg.path=<Base64 absolute path>
```

The operation is `LOCAL_ONLY`. A positively identified network filesystem returns `NETWORK_SCOPE_BLOCKED`; an unclassified filesystem returns `STORAGE_SCOPE_UNKNOWN`. The default adapter does not enumerate a full sample table.

No `db.*`, `sql.*`, or generic shell command is added. NativeDB remains an internal fixed-capability layer in this milestone.


## 0.3.0-dev.2 / FrameKit SL-M2 additive contract

Protocol v1 additionally allowlists `media.frame`. No existing command schema is reinterpreted.

Request schema:

```text
command=media.frame
arg.path=<Base64 absolute local media path>
arg.output=<Base64 absolute new .png path>
arg.timeSeconds=<Base64 non-negative decimal seconds>
arg.maxPixels=<Base64 integer 64..4096>   # optional; default 2048
```

`path`, `output`, and `timeSeconds` are required. The operation is `LOCAL_ONLY`, refuses overwrite, and returns schema `MJ_MEDIA_FRAME_1` with requested time, actual generated time, delta, dimensions, output facts, transform/tolerance evidence, source-stability evidence, and adapter identity.

The operation does not accept JavaScript, Objective-C selectors, shell commands, SQL, codec settings, or arbitrary AVFoundation options.
