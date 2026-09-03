# SCV Instagram GOLD-2 custody record (2026-09-03)

GOLD-2 is the owner-verified v145 production state, frozen on 2026-09-03 after the owner red-teamed it end to end and accepted it. This record carries the identities and hashes only; every artifact lives in the private R2 bucket and the private archives. It replaces the mid-April 2026 golden reference as the behavioral bar.

## What is frozen

| object | identity |
|---|---|
| runtime release | `scv-instagram-single-20260902-v145`, fingerprint `c17312eca28ae28da3ab2fbd796240426b0bc9c0e8363dfb580bef8a030649a5`, manifest sha `2df6c5a672d8f0d4f769672c7477f7b5b377ced497bed90b1d3de029ca44cb53` |
| runtime artifact in R2 | `scv-instagram-automation/release-ready/20260903T074729Z/v145/scv-instagram-single-20260903T074729Z-v145-revision-outranks-heuristics.tar.gz` (sha `a6a7940e46c996be8c73c04bcb9b16911dcf210dd423fb6e770beac1d13c3ed1`, read back byte-identical) |
| production state snapshot (non-destructive, all 10 workers paused, in-place restore drill) | `scv-instagram-automation/timestamped-snapshots/gold/20260903T144940Z/prod-v145-gold.tar.gz` (sha `82270f2f3fc91155176b8a13607d4ae2504776476db02af1c4364595c64d67c6`, namespace tree sha `74b94cbb09a3b7d54c6188d5fb98f504885a70c5fa445fabd9bed3d403388e7f`, `1783` entries, receipt sha `3ea449b90b717aad15cfe4acf570f79cb567628ee8df83bc40e05b256f9ec6ed`) |
| clean baseline | R2 control `20260903T075940Z`, current snapshot `scv-instagram-20260903T075852Z-v145-post-omar-reset-current` |
| environment | 99 production variables recorded by name, length and value hash (secret values never stored); model pins `gpt-5.4-mini-2026-03-17` (DM), `gpt-4.1-mini-2025-04-14` (intent, vision, ASR) |
| golden conversations | ``gold-a-v145-live-red-team.json` (sha `693280cd7f43aabbc97c3af3381b86053cebc535bab5652f6fca96d694d78231`, 17 turns), `gold-b-owner-red-team.json` (sha `52f27857200172d18bd706969d63ea4c16e45d8a482fa3c2d3d17050c2fdda20`, 7 turns)` |
| gold manifest | sha `372d14702a5e3f98b80c2d3d1f1b3d93ea0ae623fac1cdcfc52649df3e9eb529` (R2 `scv-instagram-automation/gold/SCV_GOLD_MANIFEST_v145.json`, pointer `scv-instagram-automation/gold/LATEST.json`) |
| sentinel | ``scv-instagram-drift-sentinel` v11 (schema `scv-instagram-drift-sentinel-2026-09-03-v11-gold2-manifest-pin`) pins the v145 release, the v145 control and the GOLD-2 manifest hash; first attestation `2026-09-03T15:50:43.000Z` ok` |

## Restore drill (staging sandbox)

Inside the staging container (namespace `single-staging-v145`, the same sealed v145 runtime as production): every runtime worker was killed with SIGKILL and the process supervisor revived the full set with new PIDs (9 workers); all workers were then SIGSTOPped, the staging namespace was deleted outright (30 entries gone), the gold archive was delivered from the R2 read-back copy and extracted, and the restored tree hashed to `74b94cbb09a3b7d54c6188d5fb98f504885a70c5fa445fabd9bed3d403388e7f` with 1783 entries, identical to the capture receipt; the workers resumed (9 running, none stopped). Finding from the first destructive pass: deleting the namespace outright kills the process supervisor (its status writer needs `/app/logs`, a symlink into the namespace) and the container exits; a Railway redeploy of the same sealed image boots again with a fresh empty namespace (28 entries), after which the R2 restore rebuilds the gold state. Recovery from a wiped volume is therefore redeploy, then restore from R2, then verify the tree hash. Readiness after restore: ok. Isolated container suites on the restored namespace: `test:single-release` exit 0, full `npm test` 172 step lines, 0 failures. Golden conversation replays inside the restored container with the live model: gold-a 17 turns, 17 exact, 10 deterministic executors, 0 failed (gold replies as model candidates); gold-b 7 turns, 7 exact, 4 deterministic executors, 0 failed (gold replies as model candidates).

## Anti-drift gate

`scv-gold-guard.sh <candidate-tree> <change-card.json>` (private tooling, `gold-v145/gate/`): materializes the gold runtime from R2 and verifies its fingerprint; diffs the candidate against gold and requires every changed, added or removed file to be declared with a reason in the change card (locked files need `owner_approval: true`); runs the full local suite without the single-release protocol variable; runs `scv-gold-conversation-replay.js` on both golden conversations (deterministic executors must match byte for byte or within the generic-info rotation family; model-authored turns must stay contract-valid under the locked route). Self-test on the sealed v145 tree with an empty change card: PASS. Local replays on the sealed tree: gold-a 17 turns, 17 exact, 10 deterministic executors, 0 failed (gold replies as model candidates); gold-b 7 turns, 7 exact, 4 deterministic executors, 0 failed (gold replies as model candidates).

## Laws

- The production tree is the R2 gold artifact; working folders on any machine are consumable and never the source of truth.
- A change reaches a seal only through the gold guard: a declared change card, a diff against gold materialized from R2, the full local suite, and the golden conversation replays (deterministic turns byte-identical, model turns contract-valid under the locked route). Locked files (prompt authority, policy contracts, April tone floor, booking policy, structured-state schema, config lock, prompt stones) need explicit owner approval.
- Every deployed release is sealed, staging-tested in an isolated container, live red-teamed on the debug identity, left with a fresh hand-over reset, published to R2 with readback and restore drills, and pinned by a new sentinel version.
- Model identity is pinned and enforced at boot; deterministic lanes answer booking turns; a resolved revision outranks classifier flags.
