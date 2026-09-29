# MographJailed 0.3.0-dev.2 — FrameKit SL-M2 Milestone Receipt

Status: **portable candidate complete; target-Mac + AE promotion gates outstanding.**

## Delivered

- 21st explicit Protocol v1 operation: `media.frame`;
- fixed local-only FrameKit adapter;
- requested/actual time evidence;
- transform and zero-tolerance configuration;
- bounded non-overwriting PNG derivative;
- portable security/contract tests;
- target-Mac and AE child-process qualification harnesses.

## Portable metrics

- deterministic: **515/515**;
- protocol fuzz: **1,000/1,000**, 0 failures;
- no generic shell/JXA/SQL surface;
- no network mutation;
- no sudo/admin/install requirement.

## Baseline rule

Do not replace the target-Mac-qualified `0.3.0-dev.1` install until both FrameKit target gates pass.
