# MJ_Organize — MographJailed Integration Handoff

## Purpose

MographJailed is the shared zero-install native macOS capability layer for MJ tools. MJ_Organize should consume MographJailed rather than independently implementing shell/macOS adapters.

MographJailed supplies machine, filesystem, asset, image, media, storage, temporary-workspace, report, and package evidence. MJ_Organize remains responsible for organization workflow, After Effects project mutation, relinking decisions, validation, and receipts.

## Responsibility boundary

MographJailed answers questions such as:

```text
What is this file?
Is this source unchanged?
What filesystem is this asset on?
Is storage local or network?
Can Spotlight locate advisory missing-asset candidates?
What extended-attribute names exist?
Can this image be positively identified?
Can a temporary derivative be generated safely?
Can a report be packaged without overwrite?
```

MJ_Organize decides:

```text
Where should this asset be organized?
Should this item be moved?
How should AE folders be structured?
Should footage be relinked?
What plan should the user approve?
How should organization be validated?
```

Do not move Organize business logic into MographJailed.

## Team deployment

Develop MographJailed independently, then bundle a pinned runtime with MJ_Organize.

```text
MJ_Organize/
├── MJ_Organize.jsx
├── runtime/
│   └── MographJailed/
│       ├── mograph-jailed.zsh
│       ├── MographJailed_Client.jsxinc
│       └── VERSION
└── docs/
```

Designers must not need Terminal setup, PATH changes, Homebrew, Xcode, admin rights, or a separate MographJailed installation.

## Startup contract

On Analyze:

```text
runtime.verify
      ↓
system.describe
      ↓
capability-aware Organize session
```

Record Organize version, Native version, protocol, runtime verification, and available capabilities in the Tech Report.

## Recommended first integration milestone — O-N1

Read-only Native integration only:

```text
runtime.verify
system.describe
storage.preflight
file.inspect
```

Then, when useful:

```text
asset.manifest
asset.verify
search.candidate
file.provenance
```

No new Organize mutation should be driven by Native evidence until this layer is qualified.

## High-value operations

### `system.describe`
Primary capability contract. Respect operation cost, authority, mutation scope, interactive safety, and network sensitivity.

### `runtime.verify`
Verify the bundled runtime before use. A failure reduces capability rather than corrupting the project.

### `storage.preflight`
Use before copy/move/create workflows. Treat `writableHint` and storage classification as advisory.

### `file.inspect`
Read-only source facts.

### `file.hash`
Strong identity evidence, but size-dependent and not interactive-safe. Do not automatically hash every production asset, especially over SMB.

### `file.provenance`
Read-only extended-attribute names. Do not clear or mutate xattrs.

### `asset.manifest` / `asset.verify`
Single-asset identity evidence for analysis/validation. Do not reinterpret this as a recursive crawler.

### `search.candidate`
Spotlight-backed candidate search. Advisory only. Never auto-relink from a Spotlight result.

Recommended missing-asset flow:

```text
AE reports missing source
      ↓
search.candidate
      ↓
file.inspect / asset.verify
      ↓
optional explicit deep hash
      ↓
confidence evidence
      ↓
USER REVIEW
      ↓
Organize-controlled relink
```

### `image.inspect` / `image.derivative`
Use for image evidence or temporary analysis/report derivatives. Never modify source imagery.

### `media.inspect`
Conservative advisory metadata only. Do not treat as frame-accurate AE timing authority.

### `temp.create` / `temp.clean`
Use Native-managed temporary workspaces rather than parallel destructive cleanup logic.

### `report.tech` / `package.create`
Use for Native environment receipts and diagnostic packaging. Keep Organize-specific Tech Report content separate.

## Safety model

Preserve the MJ flow:

```text
SCAN / ANALYZE
      ↓
DRY-RUN PLAN
      ↓
USER REVIEW
      ↓
PROCESS
      ↓
VALIDATE
      ↓
RECEIPT
```

Do not add generic Native mutation operations such as `file.move`, `file.delete`, `directory.organize`, or `shell.execute` merely to simplify Organize. Organize owns its deliberate mutation boundary.

## Network storage

Many MJ assets are network-hosted. Treat `networkSensitive:true` as meaningful. Provide separate FAST ANALYZE and DEEP VERIFY behaviors rather than performing full hashes or broad searches synchronously across large SMB projects.

## Failure behavior

If Native is unavailable:

```text
Organize AE analysis          AVAILABLE
Native asset intelligence    UNAVAILABLE
Project mutation             NONE until existing safety requirements pass
```

Native failure must never leave a project partially organized.

## O-N1 definition of done

- Organize locates its bundled Native runtime.
- `runtime.verify` passes.
- `system.describe` is parsed and cached.
- capability failures degrade gracefully.
- project state remains unchanged during Native analysis.
- storage preflight appears in Analyze.
- asset evidence can be gathered read-only.
- Tech Report includes Native status.
- no designer Terminal setup is required.

## Core principle

MographJailed tells Organize what the Mac and asset evidence say.

MJ_Organize decides what organizational action is appropriate.

---

## Standard Library 1.0 addendum — 0.3.0-dev.1

Organize should now treat `system.describe.data.standardLibrary` as part of startup capability discovery.

### LocalFS

Use existing public storage/file operations; Organize does not call LocalFS directly. Standard Library local-only policy means future automatic indexing/caching/DB work must stay on local storage. Do not create MJ SQLite stores on production SMB shares.

### NativeDB

0.3.0-dev.1 qualifies the stock SQLite runtime, JSON, and FTS5 in memory but exposes no persistent database operation. Organize should **not** build a private parallel SQLite layer yet. The next Organize-specific NativeDB milestone should define one fixed, versioned schema for local receipts/index metadata with migrations and integrity checks.

### ImageKit

`image.inspect` / `image.derivative` continue to be the public interface. Their reusable native primitives now live behind ImageKit so Organize should not invoke `sips` directly.

### MediaProbe

`media.timing` is primarily a Looper-facing primitive in this milestone. Organize may use it only for an explicit local-media diagnostic; it should not add synchronous timing probes to routine Analyze.

### Network boundary

Standard Library automatic work is local-only by default. Existing explicit Organize evidence against a caller-supplied path remains product-controlled, but Organize must not use NativeDB, automated indexing, test writes, or caches on network shares.


## FrameKit dev.2 note

`media.frame` is primarily a Looper-facing primitive in this milestone. MJ_Organize should not add automatic frame extraction merely because the operation exists. Organize continues to consume LocalFS, storage, asset, image, provenance, and future fixed-schema NativeDB capabilities. FrameKit remains explicit/local-only and qualification-gated.
