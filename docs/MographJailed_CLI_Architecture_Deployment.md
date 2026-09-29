# MographJailed — CLI Architecture, Deployment & Team Integration

**Project:** MographJailed  
**CLI:** `mograph-jailed` / `dist/mograph-jailed.zsh`  
**Current engineering release:** `0.1.0-rc3`  
**Protocol:** `MOGRAPHJAILED` v1  
**Document date:** 2026-09-18  
**Status:** Portable QA complete; target-Mac qualification substantially complete; After Effects round-trip and SMB qualification remain.

---

## 1. Executive Summary

MographJailed is the shared, zero-install macOS capability layer for MJ tools.

Its purpose is to give After Effects JSX and other MJ applications a small, secure, deterministic interface to capabilities already present in stock macOS without requiring Homebrew, Python packages, Node/npm, FFmpeg, Xcode Command Line Tools, admin rights, a daemon, or a cloud service.

The central rule is:

> **MJ products ask for named native capabilities. They do not execute arbitrary shell commands.**

MographJailed is developed and tested as its own project, then a pinned runtime copy is bundled inside products such as MJ_AE_LOOPER for team distribution.

```text
MJ_AE_LOOPER
MJ_Organize
MJ_Brief
Future MJ tools
        │
        ▼
  MJ Native Protocol
        │
        ▼
     MographJailed
      mograph-jailed
        │
        ▼
 approved stock macOS tools
```

---

## 2. Why This Project Exists

The production environment is a locked-down Mac where installing development dependencies may require IT approval and may disrupt normal production work.

The project therefore assumes:

- no `sudo`;
- no Homebrew or MacPorts;
- no Xcode or Command Line Tools requirement;
- no Git requirement;
- no Python runtime/package dependency;
- no Node/npm runtime dependency;
- no FFmpeg/OpenCV dependency;
- no Docker;
- no LaunchAgent or daemon;
- no persistent local server;
- no cloud-processing requirement;
- no system-wide configuration changes;
- no modification of original production media.

If a capability is missing, the preferred approach is to build the needed behavior from stock macOS components or disable the feature gracefully.

This is an active production machine, so changes must remain local, reversible, conservative, and fail-closed.

---

## 3. Project Boundary

### MographJailed is responsible for

- macOS capability discovery;
- filesystem inspection;
- explicit file hashing;
- volume/filesystem inspection;
- managed temporary workspaces;
- advisory media metadata inspection;
- privacy-minimal native Tech Report data;
- non-overwriting ZIP packaging;
- the stable request/response protocol used by MJ clients.

### MographJailed is NOT responsible for

- After Effects business logic;
- deciding how an animation should loop;
- arbitrary shell execution;
- general application automation;
- a workflow orchestration server;
- MCP hosting;
- asset-management databases;
- full media transcoding;
- background services.

For example:

```text
MographJailed
= "What can this Mac safely inspect or perform?"

MJ_AE_LOOPER
= "What looping strategy should be used in this AE project?"
```

---

## 4. Runtime Architecture

Production runtime flow:

```text
MJ consumer
(for example After Effects JSX)
        │
        ▼
structured MJ Native request file
        │
        ▼
/bin/zsh -f dist/mograph-jailed.zsh --request <request-file>
        │
        ▼
environment normalization
        │
        ▼
protocol validation + command-specific schema
        │
        ▼
allowlisted MographJailed module
        │
        ▼
fixed-path macOS adapter
        │
        ▼
versioned JSON response
```

The bundled runtime also starts with a zsh-safe execution model so user shell plugins and aliases do not define application behavior.

The production runtime does **not** depend on the user's `.zshrc` or the convenience commands configured on the development Mac.

---

## 5. Source and Distribution Model

MographJailed remains modular during development.

Conceptually:

```text
src/
├── protocol/
├── system/
├── file/
├── volume/
├── temp/
├── media/
├── report/
└── package/
```

Release builds are deterministically bundled into:

```text
dist/mograph-jailed.zsh
```

Source-to-distribution parity is part of QA. A release is not valid if modular source and `dist/mograph-jailed.zsh` diverge.

This separation gives the project both:

- maintainable non-monolithic development source; and
- a simple one-file zero-install macOS runtime.

---

## 6. MJ Native Protocol v1

Request files use a deliberately small text format so production does not need `jq`, Python, Node, or another parser.

Example:

```text
MOGRAPHJAILED_REQUEST 1
requestId=terminal-doctor
command=system.doctor
```

Arguments are transported as canonical Base64 values rather than inserted into shell syntax.

Example concept:

```text
arg.path=<Base64 encoded UTF-8 path>
```

Important protocol properties:

- commands are compile-time allowlisted;
- argument names are command-specific allowlists;
- unknown fields fail closed;
- extra arguments fail with `UNEXPECTED_ARGUMENT`;
- malformed protocol versions fail explicitly;
- decoded values are validated before use;
- control-character paths are rejected by design;
- requests have line/value/size limits;
- there is no raw command-line field;
- stdout is reserved for the protocol response;
- failures contain non-empty machine error codes and human-readable messages.

Responses use a JSON envelope containing:

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

---

## 7. Current Public Command Surface

RC3 exposes only named operations:

| Command | Purpose | Typical cost |
|---|---|---|
| `system.probe` | Discover OS/version/architecture/native capabilities | Fast |
| `system.doctor` | Determine overall MographJailed readiness | Fast |
| `file.inspect` | Read filesystem/type information | Fast |
| `file.hash` | Explicit SHA-256 fingerprint with source-stability check | Potentially slow on large/network files |
| `volume.inspect` | Filesystem, free space, local/network classification hints | Fast/bounded |
| `temp.create` | Create an MJ-owned temporary workspace | Fast |
| `temp.clean` | Remove only a validated MJ-owned temporary workspace | Fast |
| `media.inspect` | Advisory file + Spotlight media metadata | Usually fast/bounded |
| `report.tech` | Produce privacy-minimal native environment/report data | Fast |
| `package.create` | Create non-overwriting ZIP packages using native `ditto` | Size-dependent |

There is intentionally no command such as:

```text
shell.execute
raw.exec
command.run
```

---

## 8. macOS Native Capability Layer

The current target Mac reports **26/26 capabilities available** through `system.doctor`.

Detected native capabilities include tools such as:

```text
/bin/zsh
sw_vers
stat
file
df
mktemp
plutil
sips
ditto
sha256
shasum
mdls
avmediainfo
avconvert
afinfo
afconvert
mdfind
xattr
osascript
base64
awk
uname
sed
rm
mv
pwd
```

Not every detected tool is automatically used in normal production paths.

Availability and production use are separate concepts.

For example, `avmediainfo` is currently detected but is **not** executed by default by `media.inspect`, because its human-oriented output is not being treated as a stable structured timing API.

---

## 9. Media Philosophy

V0.1 treats source media as immutable.

Allowed operations include:

```text
read
inspect
hash
decode metadata
generate temporary derivatives when explicitly supported
create reports
```

Not allowed:

```text
overwrite source
transcode source in place
rename source
move source
delete source
silently change metadata
```

`media.inspect` currently returns advisory information such as:

- file size;
- basic media type;
- duration from `mdls` when available;
- pixel dimensions from `mdls` when available;
- content type;
- whether optional native media tools are available.

It does not pretend that advisory metadata is authoritative frame timing.

Advanced structured frame/timing analysis remains a separate research track.

---

## 10. File Hashing

`file.hash` is explicit rather than part of the default interactive media path.

On the qualified target Mac, the preferred native SHA-256 implementation is available.

A hash operation also performs a lightweight pre/post stability check using:

```text
device + inode + size + modification time
```

If the source visibly changes while hashing, the operation fails closed rather than presenting the result as a stable asset fingerprint.

This is particularly important for large or network-hosted production media.

---

## 11. Temporary Workspace Safety

Temporary storage is managed by MographJailed rather than allowing callers to recursively delete arbitrary paths.

The lifecycle is:

```text
temp.create
   ↓
canonical MJ-owned directory
   ↓
owner/path marker
   ↓
work
   ↓
temp.clean
   ↓
containment + marker validation
   ↓
remove only the validated MJ directory
```

If ownership/containment cannot be proven, cleanup refuses to run.

---

## 12. Packaging Safety

`package.create` uses stock macOS `ditto` for ZIP creation.

Important rules:

- package output is staged and published conservatively;
- destination parents are canonicalized;
- existing output is never overwritten silently;
- an existing destination returns `OUTPUT_EXISTS`;
- source report contents are preserved inside the archive;
- packaging is explicit because large reports may take time.

---

## 13. After Effects Integration

Adobe After Effects communicates with MographJailed through an AE-side client library.

Development integration currently contains:

```text
integrations/after-effects/
├── MographJailed_Client.jsxinc
└── MographJailed_AE_Spike.jsx
```

`MographJailed_Client.jsxinc` is the reusable AE-native integration layer.

The old `MographJailed_AE_Spike.jsx` is only an M4 qualification harness and should eventually be replaced by a dedicated qualification utility.

Intended flow:

```text
After Effects JSX
      │
      ▼
MographJailed_Client.jsxinc
      │
      ▼
system.callSystem()
      │
      ▼
/bin/zsh -f
      │
      ▼
mograph-jailed.zsh
      │
      ▼
MJ Native JSON
      │
      ▼
AE client parses response
```

### Important synchronous boundary

After Effects `system.callSystem()` waits for the native command to finish.

Therefore normal interactive AE operations should prefer fast/bounded commands.

Do not automatically run expensive work such as:

- full SHA-256 of very large production media;
- large package creation;
- unbounded media scans;
- deep network operations.

Expensive operations should remain explicit and clearly labeled.

---

## 14. Relationship to MJ_AE_LOOPER

MJ_AE_LOOPER should consume MographJailed rather than reimplement macOS access itself.

Example:

```text
MJ_AE_LOOPER
      │
      ├── reads AE comps/layers/keyframes/effects itself
      │
      └── asks MographJailed for native source/filesystem capabilities
```

Looper owns decisions such as:

```text
Exact Cycle
Periodic Expression
Spatial Wrap
Cycle Evolution
Ping-Pong
Overlap Blend
Retimed Seam
Manual Review
```

MographJailed owns primitives such as:

```text
media.inspect
file.inspect
file.hash
volume.inspect
temp.create
system.doctor
```

Future reusable media-analysis primitives may eventually include concepts such as:

```text
media.frame
media.sample
media.compare
media.seamCandidates
```

but only after they are proven deterministic, safe, reusable, and compatible with the zero-install production environment.

They should not contain Looper-specific strategy decisions.

---

## 15. Team Distribution Model

MographJailed should remain a standalone shared engineering project, but team products should ship a **pinned private runtime copy**.

Recommended Looper distribution:

```text
MJ_AE_LOOPER/
│
├── MJ_AE_LOOPER.jsx
│
├── runtime/
│   └── MographJailed/
│       ├── mograph-jailed.zsh
│       ├── MographJailed_Client.jsxinc
│       └── VERSION
│
├── docs/
│   ├── QUICK_START.md
│   └── TROUBLESHOOTING.md
│
└── manifest.json
```

### Why bundle instead of globally install

Do **not** require team members to configure:

```text
/usr/local/bin
/opt/homebrew
PATH
~/.zshrc
/Application Support shared runtime
admin installers
```

The product should resolve its own bundled runtime relative to itself.

Benefits:

- no installer;
- no admin rights;
- no global version conflict;
- no user shell setup;
- no Homebrew dependency;
- one folder/ZIP can be copied to another qualified Mac;
- every MJ product records exactly which Native runtime it shipped with.

Example product receipt:

```text
MJ_AE_LOOPER
Version: 0.8.0

Bundled Native runtime: 0.1.0
Native protocol: 1
Compatibility: PASS
```

During early development it is acceptable for different products to pin different known-good MographJailed versions.

---

## 16. Local Engineering Terminal Helpers

The current engineering Mac has optional shell conveniences:

```text
mj
mj-open
mj-status
mj-doctor
mj-help
```

These are for the local engineering workstation only.

They are **not MographJailed runtime dependencies** and must not be required for team deployment.

Current project root on the engineering Mac:

```text
~/Documents/MographJailed
```

Current production CLI path:

```text
~/Documents/MographJailed/dist/mograph-jailed.zsh
```

Shell helper source:

```text
~/Documents/MographJailed/scripts/shell/mj-shell.zsh
```

Known-good local recovery config:

```text
~/Documents/MographJailed/config/shell/
```

The engineering shell is intentionally separate from production execution. Product calls use `/bin/zsh -f` and do not rely on `.zshrc` aliases or functions.

---

## 17. Current Target-Mac Qualification Status

Target production Mac observed during qualification:

```text
macOS:        15.7.5
Build:        24G624
Architecture: arm64 / Apple Silicon
CLI:          0.1.0-rc3
Native tools: 26/26 available
Warnings:     0
```

### Passed on the actual Mac

- `system.probe` — PASS
- `system.doctor` — PASS (`ready:true`)
- APFS `volume.inspect` — PASS
- filesystem classification via macOS `df -Y` — PASS
- `file.hash` using native SHA-256 — PASS
- hash source-stability reporting — PASS
- `temp.create` — PASS
- marker-bound `temp.clean` — PASS
- physical temp deletion verification — PASS
- `media.inspect` on real QuickTime `.mov` — PASS
- `mdls` duration/dimensions on real media — PASS
- `package.create` through native `ditto` — PASS
- archive extraction/content verification — PASS
- overwrite refusal (`OUTPUT_EXISTS`) — PASS
- local `mj-status`/doctor shell helpers — PASS
- fresh Terminal session recovery/initialization — PASS

### Still required before production 0.1.0

- real After Effects JSX → `system.callSystem()` → MographJailed round-trip;
- dedicated AE qualification utility to replace the generic M4 spike;
- SMB/network-volume `volume.inspect` qualification;
- confirm no unexpected TCC/Automation prompts in the final AE path;
- final release receipt after those gates pass.

---

## 18. QA State of RC3

RC3 was produced after multiple adversarial review passes.

Recorded QA includes:

```text
Deterministic test suite: 217/217
Protocol fuzz:            1,000/1,000
Concurrency checks:       included
Source/dist parity:       verified
Clean extraction rebuild: verified
```

Major issues found and corrected during review included:

- shell helper state leaking into caller variables;
- source vs generated distribution drift;
- incorrect macOS filesystem classification assumptions;
- required-argument error propagation;
- unsafe or overly broad environment assumptions;
- default media operations doing work that was not needed;
- file hashing without sufficient source-stability signaling.

The project intentionally remains a release candidate until target-Mac qualification is complete.

---

## 19. Security Model

Core production rules:

1. No arbitrary shell execution API.
2. Fixed native executable paths where appropriate.
3. User input is data, not shell syntax.
4. Command and argument schemas are allowlisted.
5. Original production media is immutable.
6. Destructive temp cleanup requires containment and ownership validation.
7. Package creation refuses overwrite.
8. Optional capabilities degrade gracefully.
9. Unknown/unsupported states return explicit errors instead of guesses.
10. User shell customization is not trusted by application execution.
11. No background service is required.
12. No external network is required.

---

## 20. Versioning and Compatibility

There are two important versions:

```text
cliVersion
protocolVersion
```

`cliVersion` can evolve while protocol v1 remains compatible.

A client can accept a newer CLI when the supported protocol remains compatible.

Breaking request/response semantics should trigger an explicit protocol-version decision rather than silently changing behavior.

For team deployment, every MJ product should record:

```text
Product version
Bundled MographJailed version
Native protocol version
Capability/doctor result
```

---

## 21. Recommended Next Engineering Sequence

### Phase A — Finish target-Mac qualification

1. Build `MographJailed_AE_Qualify.jsx`.
2. Use `MographJailed_Client.jsxinc` as the actual client layer.
3. Validate AE → `/bin/zsh -f` → Native → JSON.
4. Confirm no unwanted macOS permission prompts.
5. Test one representative SMB/network volume.
6. Record the resulting qualification receipt.

### Phase B — Promote Native

If all target-Mac gates pass:

```text
0.1.0-rc3
   ↓
final qualification
   ↓
MographJailed 0.1.0
```

Do not add unrelated features before that promotion.

### Phase C — Looper integration

1. Add a small Native client adapter to MJ_AE_LOOPER.
2. Bundle a pinned MographJailed runtime inside Looper.
3. Run `system.doctor` before Native-dependent features.
4. Keep Looper functional in an AE-only degraded mode if optional Native capabilities are missing.
5. Include Native status/version in the Looper Tech Report.

### Phase D — Advanced native media research

Only after core deployment is stable, revisit:

- AVFoundation frame extraction;
- Core Image comparisons;
- deterministic frame signatures;
- candidate seam search;
- motion-continuity approximations.

JXA/AVFoundation/Core Image remain experimental until proven safe on managed production Macs.

---

## 22. Long-Term MJ Model

MographJailed should become the stable macOS abstraction layer underneath the MJ ecosystem.

```text
                 MographJailed
                      │
       ┌──────────────┼──────────────┐
       │              │              │
MJ_AE_LOOPER   MJ_Organize   MJ_Brief
       │              │              │
 media/source     filesystem      diagnostics
 inspection       hashing         packaging
 native QC        volumes         environment
```

The engineering library is shared.

The team-facing runtime is bundled and pinned per product.

That preserves reuse without turning MographJailed into a machine-wide dependency or installation requirement.

---

## 23. Operating Principle

The long-term design rule is:

> **Develop MographJailed once, test it independently, and bundle the validated runtime with each MJ product that needs it.**

For the managed production environment:

```text
Stock macOS first.
Local first.
Zero install where possible.
No admin requirement.
Originals immutable.
Analyze before mutation.
Explicit capability probing.
Fail closed.
Bundle dependencies with the product.
Keep recovery and documentation local.
```

