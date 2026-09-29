# MographJailed — Code Audit & Roadmap to Finish

_Audit date: September 29, 2026. Codebase: 0.3.0-dev.2 (SL-M2 FrameKit candidate)._

## Audit verdict

The code is in good shape. This is a carefully built, well-tested codebase — not a prototype with hidden rot. The security architecture is the real thing: every command goes through one allowlist, arguments travel as Base64 (never shell text), outputs are staged before publishing, source media is never overwritten, and network storage fails closed. 515 portable tests pass, 1,000 fuzz cases pass, and as of today that all runs green in CI on every push.

**By the numbers:**
- 2,674 lines of zsh source → 1 deterministic `dist/mograph-jailed.zsh` bundle (2,733 lines)
- 21 operations behind a single compile-time allowlist — one choke point, easy to audit
- Zero TODO/FIXME/HACK markers in source
- 416-line After Effects client library + spike script
- Full doc set: protocol, architecture, security, capability registry, dependency audit, per-release QA reports

## What's blocking "finished"

One thing, and it's not code — it's a Mac. The new frame-extraction feature (`media.frame`) is built and portable-tested, but the project's own promotion rule says no dev release replaces the qualified baseline until it passes two gates **on your managed Mac**:

- **Gate A:** run `/bin/zsh tests/run_framekit_m2_target_mac.zsh` in Terminal
- **Gate B:** run `tests/MographJailed_FrameKit_AE_Qualification.jsx` from inside After Effects (File > Scripts > Run Script File)

Until those pass, the older 0.3.0-dev.1 stays the production baseline. I can't run these for you — they need your Mac and your After Effects.

**Honest risks worth knowing:**
1. Frame extraction uses an Apple API that Apple has deprecated (the synchronous image-generator). It works, it's isolated behind the operation contract, but it needs the target-Mac regression evidence from Gate A/B to prove it.
2. Variable-frame-rate video is explicitly not qualified yet — no real VFR test fixture exists. The code refuses to claim what it hasn't proven, which is the right call.
3. The consumers don't exist yet. MJ_Organize and MJ_AE_Looper are named targets; today there's a handoff doc and a spike script. The library is built ahead of its products.

## Roadmap

### Phase 0 — Repo foundation ✅ DONE (Sept 29, 2026)
Sanitized port to the public repo, MIT license, README quickstart, CI with three jobs: sanitize guard (fails the build if old internal names ever reappear), dist-parity check (source-to-bundle rebuild must be clean), portable suite + fuzz. All green.

### Phase 1 — Qualify 0.3.0-dev.2 👉 YOUR ACTION, on your Mac
1. Extract the release, run Gate A in Terminal.
2. Open After Effects, run Gate B, check the receipt lands in `/tmp/`.
3. If the gates surface adapter-specific behavior (especially around that deprecated Apple API), record it — that's evidence, not failure.
4. Bonus if you have one: qualify a real variable-frame-rate clip so VFR stops being a SKIP.
5. Tag it `0.3.0` qualified. Dev.2 replaces dev.1 as the baseline.

This is the only phase I can't do. Everything after it unblocks once this is done.

### Phase 2 — SL-M3: ImageKit analysis (buildable next)
Two new operations for the loop-seam use case:
- `image.stats` — deterministic bounded histogram / area-average signatures
- `image.compare` — one interpretable similarity score between two frames, for coarse loop-seam ranking

Same pattern as M2: implement behind the adapter boundary, portable contract + security tests, QA report, target-Mac gate before promotion. No new production dependencies.

### Phase 3 — SL-M4: NativeDB product stores (needs product schemas first)
Don't build this until MJ_Organize's schema is designed:
- Fixed-schema local receipts, optional local asset indexes
- FTS5 search over MJ-owned metadata, migrations, integrity receipts

Hard boundaries that must survive: no arbitrary-SQL operation, no databases on network volumes.

### Phase 4 — 0.4.x: Perceptual Intelligence Lab (research-gated)
Vision feature prints, image similarity, coarse candidate filtering, OCR/visual evidence — only where a real MJ product has a concrete need. This stays a lab until a consumer justifies each piece.

### Standing rules (don't break these getting to done)
- No dev release replaces the qualified baseline until its target-Mac gates pass.
- Protocol v1 stays additive — existing operation schemas don't change silently.
- No sudo, no package manager, no daemon, no network, no arbitrary shell/SQL. Ever.
- Source media is never mutated; derivatives never overwrite.
- CI stays green: sanitize guard, dist parity, full suite + fuzz.

## Suggested order of operations
1. You run Gates A/B on your Mac → 0.3.0 qualified.
2. Then greenlight SL-M3 (`image.stats` / `image.compare`) — the smallest honest next slice, directly serves the Looper.
3. Park SL-M4 until MJ_Organize's schema exists; park 0.4.x until a product needs it.
