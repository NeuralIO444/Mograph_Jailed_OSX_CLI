# MographJailed 0.3.0-dev.1 — Standard Library 1.0 Planning

## Goal

Create the first reusable MJ-owned native standard-library layer for MJ_Organize and MJ_AE_Looper without adding an installer, server, downloaded runtime, generic shell boundary, or automatic network behavior.

## First production slice

- **LocalFS** — shared filesystem classification and fail-closed local-only policy.
- **NativeDB** — fixed SQLite runtime/JSON/FTS5 capability layer and local store-path validation; no public arbitrary SQL.
- **MediaProbe** — normalized bounded `avmediainfo` timing/header evidence.
- **ImageKit** — reusable boundary around qualified `sips` image primitives.
- **FrameKit** — descriptor only, `LAB_GATED` pending AE-child JXA/frame extraction qualification.

## Consumer priorities

### MJ_AE_Looper

1. reliable local media duration/timescale/FPS evidence;
2. future exact frame extraction and frame sampling;
3. future image statistics/comparison for loop-boundary analysis.

### MJ_Organize

1. shared local filesystem/safety policy;
2. deterministic local metadata/index primitives;
3. future fixed-schema SQLite stores for receipts/index/cache state;
4. reusable image inspection/derivative primitives.

## Guardrails

- local-only by default for new automatic Standard Library work;
- no SMB enumeration, test files, cache/database placement, or automatic mutation;
- no sudo/admin/setup/license changes;
- no Python, Node/npm, FFmpeg, Homebrew, MacPorts, or downloaded runtime requirement;
- no public generic SQL or raw shell operation;
- all mutations staged/non-overwriting and product-specific;
- capability/advisory evidence must remain distinct from product decisions.
