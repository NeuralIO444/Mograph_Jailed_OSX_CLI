# NG-M1 Target-Mac Qualification

Target: `MographJailed 0.2.0-dev.1`

Run on the managed production Mac without replacing the qualified 0.1.x copy.

## 1. system.describe

Create a normal Protocol v1 request for `system.describe`.

Pass criteria:

- response `ok:true`
- `cliVersion` is `0.2.0-dev.1`
- `data.schema` is `MOGRAPHJAILED_CAPABILITY_REGISTRY_2`
- `registryVersion` is `2`
- all 13 public operations are present
- `file.hash.interactiveSafe` is false
- `media.inspect.authority` is `ADVISORY_METADATA`
- `media.timing.state` is `LAB_GATED`
- `package.create.available` is true on the qualified Mac when `/usr/bin/ditto` is present

## 2. runtime.verify: version/protocol/filename

Call `runtime.verify` with:

- `expectedCliVersion=0.2.0-dev.1`
- `expectedProtocolVersion=1`
- `expectedFilename=mograph-jailed.zsh`

Pass criteria:

- `ok:true`
- `data.compatible:true`
- CLI/protocol/filename checks are true
- SHA check is null when no expected digest is supplied

## 3. runtime.verify: SHA-256

Calculate the release SHA-256 from the release manifest and pass it as `expectedSha256`.

Pass criteria:

- `data.compatible:true`
- `checks.sha256:true`
- `actual.sha256` equals the manifest digest
- `hashSource` is an approved native SHA adapter

## 4. Negative compatibility test

Repeat with an intentionally wrong expected CLI version.

Pass criteria:

- command execution still returns a valid response envelope
- `data.compatible:false`
- `checks.cliVersion:false`
- no project/media mutation occurs

## 5. After Effects client

From After Effects, verify that the updated `MographJailed_Client.jsxinc` can:

- call `describe()`
- report `can("media.inspect")`
- report `isInteractiveSafe("file.hash") == false`
- call `verifyRuntime()` against the bundled runtime

No Finder/System Events automation or admin/TCC prompt should be required.
