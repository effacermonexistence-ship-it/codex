# SCV Instagram v135 custody

This is a product-specific custody record. It must not be copied into global
Codex or Claude instructions. Customer-derived state, the deployable runtime,
and private writing references remain private in R2 or the production platform
and must never be committed to this public repository.

## Active release

- Release ID: `scv-instagram-single-20260901-v135`
- Content fingerprint:
  `1497a548217e657d958646546c3c0ab9ff5251dc41a3ee4ee9311110c4ef1697`
- Release manifest SHA-256:
  `12461756cc699407a8c7a06d540fc85b15b7bf1bdd4274bce766a8e54fd0651b`
- Private application archive:
  `scv-instagram-automation/release-ready/20260901T221200Z/v135/scv-instagram-single-20260901T221200Z-v135-info-authority-precedence.tar.gz`
- Application archive SHA-256:
  `680f933a10e2edee1a205ebf18674b95848ca28221f497bc745c1fcd6874a220`
- Production deployment: `37ac6248-471d-405b-a591-699c8e0be629`
- Staging deployment: `a8e1f64c-fe57-4a27-babd-8d568ac9cfda`

The incident input was a direct request for more information ending in the
word “here.” The deterministic discourse classifier treated that terminal word
as an unresolved referent. A successful optional model classification could
correct the flag, but a failed or unavailable classifier left the turn on the
`resolve_context` route. That route conflicted with the information-answer
verifier, so three candidate replies were rejected and the generic recovery
line was selected.

v135 makes direct information requests self-contained before optional model
classification can affect routing. An open-vocabulary information request with
no concrete design motif owns the current turn and outranks stale booking
state. A request that does contain a concrete motif keeps the design-complete
route. Real unresolved references still use context resolution. This separates
information authority, design evidence, and conversation history instead of
letting one broad word-shape rule decide all three.

The April reference remains a tone and regression floor. Its own source receipt
does not claim that the retained April origin snapshot contains a complete live
transcript corpus, so no such claim is made here.

## Verification

The exact Node `v20.20.2` full suite and the sealed single-release suite passed.
Focused evidence includes the following:

- 19 information-precedence checks, including the exact incident wording,
  open-vocabulary variants, stale booking state, unresolved-reference controls,
  concrete-design controls, and a full-controller first-pass acceptance with
  zero verifier rejections;
- 78 post-double-check divergence cases, including a changed `3 PM` proposal;
- 271 contract cases, 10,010 closed-transition cases, 141 single-control cases,
  35 reply-liveness cases, and 449 visible-identity adversarial cases;
- 19 April-tone fixtures with the source limitation above preserved; and
- single-release checks that recorded zero reads from protected legacy runtime
  surfaces.

Staging ran the 19-case information-precedence harness inside the deployed
container under the production model-identity requirement. Production and
staging returned HTTP 200 from `/readyz` with the v135 release ID and hashes,
zero critical drift, inactive fail-close, healthy voice and vision canaries,
and the dated visible model. Production's one operational alert remains
unrelated quarantine evidence and is not a critical drift alert.

## Timestamped recovery

- Private catalog pointer:
  `scv-instagram-automation/timestamped-snapshots/LATEST.json`
- Catalog control version: `20260901T222100Z`
- Snapshot count: `23`
- April golden snapshot, unchanged:
  `scv-instagram-20260420T152810-local-origin`
- v135 state immediately before the required post-fix Omar.system reset:
  `scv-instagram-20260901T221418Z-v135-pre-omar-reset`
- Current v135 state immediately after the reset:
  `scv-instagram-20260901T221420Z-v135-post-omar-reset-current`
- Catalog SHA-256:
  `d8153ebf64da0aff2c6a2757b1d447ec327b1cce14b31e5d25f2f03fd9142b24`
- Catalog seal SHA-256:
  `0c12dd66817344d48e01b23ced62a0d89f44733440cc8f9cf14dd52245526d5d`
- Pre-reset production-state archive SHA-256:
  `312fe5caaf93a6cc231a7534d63798759f08d6bd602de9c495fd1685cefd6d06`
- Post-reset production-state archive SHA-256:
  `54267005e2f8617be3c43d2f5dddd5789f33e4c707785d9b2bef6587d86d0865`
- Exact-target reset receipt SHA-256:
  `060c964e926d51b992e91274969d555d79ca349a8db68b10840f97706f714a9f`
- Pre-reset staged-restore receipt SHA-256:
  `d643c44526cc4061a3c1dcb35096b1d1909ff8074e002b031177b1d60e18edfd`
- Post-reset staged-restore receipt SHA-256:
  `23e636edaf0370f851ba22fc21b384662cd2db9ac5a6ff2c30ce8a93bdffebcb`

All ten production workers were stopped and verified before capture. The
code-locked debug audit changed from four matching artifacts to zero, the reset
watermark advanced to `2026-09-01T22:14:20.743Z`, Gmail tombstones remained in
place, and all ten workers resumed. The pre-reset tree contains 1,399 entries
with tree hash
`fe7c349e9b637e58eeac31bbd2c5485d3642538de9ca0fd03e26eeb5f1a3cb2b`.
The post-reset tree contains 1,395 entries with tree hash
`ea60b94d06a73fb92c38123bbec42d7711e89762292767c25daa8ef3624383d3`.

The runtime and both state archives were downloaded from R2, checked byte for
byte, and restored into new staging directories. The downloaded pre-reset copy
reproduced four debug matches and the downloaded post-reset copy reproduced
zero. After the new control objects were published, the control set was
downloaded again and performed a second exact-ID restore of both timestamps.
Every restore receipt records `production_mutated: false`. The golden pointer
was never moved or overlaid, and automatic production cutover remains disabled.

## Independent drift sentinel

- Worker: `scv-instagram-drift-sentinel`
- Worker version: `f72003cc-7a2d-47d8-9d5e-de62e467ae1d`
- Schedule: every five minutes
- Safe health endpoint:
  `https://scv-instagram-drift-sentinel.omar-git-r2-backup.workers.dev/health`
- Private attestation pointer:
  `scv-instagram-automation/drift-attestations/LATEST.json`

The Worker checks the exact v135 release ID, source fingerprint, release
manifest, critical drift, fail-close state, voice and vision capabilities, and
dated visible model. It also verifies the sealed 23-snapshot R2 timeline, the
distinct April golden and v135 current pointers, the pre-to-post reset link,
the four-to-zero debug audit, the reset receipt hash, and both exact-ID staged
restore receipt hashes. Its source contains no credentials or customer message
content. The first scheduled v135 attestation at
`2026-09-01T22:30:03.000Z` passed production, staging, and snapshot control with
zero consecutive failures; its SHA-256 is
`c42a0f4a51f8a1227fc165b20d441f95b7fc5d77b820e72fcd47d3401cdb4171`.
