# MJ_Organize Integration

MJ_Organize consumes MographJailed as an evidence/primitive layer. Native does not decide how projects or assets should be organized.

## Recommended startup

```text
runtime.verify
system.describe
storage.preflight
```

`system.describe` now includes Standard Library 1.0 status. Organize should cache it per session and degrade gracefully when an optional module is unavailable.

## High-value evidence

```text
file.inspect
file.hash
file.provenance
asset.manifest
asset.verify
search.candidate
image.inspect
media.inspect
temp.create
temp.clean
report.tech
package.create
```

NativeDB is internal in 0.3.0-dev.1. Organize must not depend on a persistent SQLite store yet; a fixed Organize schema/index will be designed as a later milestone.

`search.candidate` is advisory only and must never automatically relink footage. `file.hash` is size-dependent and should be reserved for explicit deep verification.

MJ_Organize remains responsible for Analyze -> Dry-Run Plan -> User Review -> Process -> Validate -> Receipt.
