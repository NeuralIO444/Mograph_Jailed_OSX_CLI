# MographJailed — Code Audit & Roadmap to Finish

_Audit date: September 29, 2026. Codebase: 0.3.0-dev.3 (SL-M3 qualified)._

## Audit verdict

The code is in good shape. This is a carefully built, well-tested codebase — not a prototype with hidden rot. The security architecture is the real thing: every command goes through one allowlist, arguments travel as Base64 (never shell text), outputs are staged before publishing, source media is never overwritten, and network storage fails closed. 515+ portable tests pass, 1,000 fuzz cases pass, and as of today that all runs green in CI on every push.

**By the numbers:**
- 2,674 lines of zsh source → 1 deterministic `dist/mograph-jailed.zsh` bundle
- 23 operations behind a single compile-time allowlist — one choke point, easy to audit
- Zero TODO/FIXME/HACK markers in source
- After Effects client library + qualification scripts
- Full doc set: protocol, architecture, security, capability registry, dependency audit, per-release QA reports

## Where things stand (updated Sept 29, 2026)

- **0.3.0** is the qualified production baseline. Both target-Mac gates passed on Matt's Mac Studio (Gate A 9 pass / 0 fail / 1 skip in Terminal, Gate B 13/13 After Effects). Supersedes 0.3.0-dev.1.
- **0.3.0-dev.3 (SL-M3)** is qualified and tagged. Both gates passed (Gate A 8/8, Gate B 15/15). Adds `image.stats` and `image.compare`.

**Honest risks worth knowing:**
1. Frame extraction uses an Apple API that Apple has deprecated (the synchronous image-generator). It works, it's isolated behind the operation contract, and it has real target-Mac regression evidence now — but it's the piece most likely to break on a future macOS update.
2. Variable-frame-rate video is explicitly not qualified yet — no real VFR test fixture exists. The code refuses to claim what it hasn't proven, which is the right call.
3. The consumers don't exist yet. MJ_Organize and MJ_AE_Looper are named targets; today there's a handoff doc and a spike script. The library is built ahead of its products.

## Roadmap

### Phase 0 — Repo foundation ✅ DONE (Sept 29, 2026)
Sanitized port to the public repo, MIT license, README quickstart, CI with three jobs: sanitize guard (fails the build if old internal names ever reappear), dist-parity check (source-to-bundle rebuild must be clean), portable suite + fuzz. All green.

### Phase 1 — Qualify 0.3.0 ✅ DONE (Sept 29, 2026)
Gate A passed 9 pass / 0 fail / 1 skip in Terminal on Matt's Mac Studio (~2:25 PM; VFR was the honest skip). Gate B passed 13/13 in After Effects (~2:35 PM). Fixed one real AE client scoping bug along the way (`$.global` anchoring). Tagged `0.3.0` qualified; dev.2 replaced dev.1 as the baseline. VFR remains an honest SKIP until a real fixture exists.

### Phase 2 — SL-M3: ImageKit analysis ✅ DONE (Sept 29, 2026)
Two new operations for the loop-seam use case, qualified on the target Mac:
- `image.stats` — deterministic 64-bin RGB histogram + 8×8 grid averages via Python 3 stdlib PNG decoder (no PIL/NumPy, no network)
- `image.compare` — one interpretable 0.0–1.0 similarity score between two frames, for coarse loop-seam ranking

Gate A 8/8, Gate B 15/15, CI green, tagged `0.3.0-dev.3`. QA report at `docs/releases/0.3.0-dev.3/QA_REPORT_SL_M3.md`.

### Phase 3 — SL-M4: NativeDB product stores (needs product schemas first) ⏸ PARKED
Don't build this until MJ_Organize's schema is designed:
- Fixed-schema local receipts, optional local asset indexes
- FTS5 search over MJ-owned metadata, migrations, integrity receipts

Hard boundaries that must survive: no arbitrary-SQL operation, no databases on network volumes.

### Phase 4 — 0.4.x: Perceptual Intelligence Lab (research-gated) 🔬
Vision feature prints, image similarity, coarse candidate filtering, OCR/visual evidence — only where a real MJ product has a concrete need. This stays a lab until a consumer justifies each piece.

### Standing rules (don't break these getting to done)
- No dev release replaces the qualified baseline until its target-Mac gates pass.
- Protocol v1 stays additive — existing operation schemas don't change silently.
- No sudo, no package manager, no daemon, no network, no arbitrary shell/SQL. Ever.
- Source media is never mutated; derivatives never overwrite.
- CI stays green: sanitize guard, dist parity, full suite + fuzz.

## Suggested order of operations
1. ~~You run Gates A/B on your Mac → 0.3.0 qualified.~~ ✅ Done
2. ~~Then greenlight SL-M3~~ ✅ Done and tagged 0.3.0-dev.3
3. Park SL-M4 until MJ_Organize's schema exists; park 0.4.x until a product needs it. **Nothing is currently authorized to build.**

