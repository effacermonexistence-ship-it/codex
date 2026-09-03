# SCV Instagram v145 custody record (2026-09-03)

v145 replaces v144 on production after the v144 live red-team. It is sealed from the v144 tree plus the fixes below; the private runtime source stays private. This record carries the identities, evidence and R2 custody for v145; the v138 to v144 records are retained alongside it.

## Active release

- Release id: `scv-instagram-single-20260902-v145`
- Sealed at: `2026-09-03T07:46:57.368Z`
- Content fingerprint (sha256): `c17312eca28ae28da3ab2fbd796240426b0bc9c0e8363dfb580bef8a030649a5`
- Release manifest sha256: `2df6c5a672d8f0d4f769672c7477f7b5b377ced497bed90b1d3de029ca44cb53`
- Production Railway deployment: `08c0a725-b137-48b0-b14d-0e667fbea36b`
- Staging Railway deployment: `3d8ac118-6807-4490-9424-7863d3dd792c`
- Runtime archive in R2: `scv-instagram-automation/release-ready/20260903T074729Z/v145/scv-instagram-single-20260903T074729Z-v145-revision-outranks-heuristics.tar.gz` (sha256 `a6a7940e46c996be8c73c04bcb9b16911dcf210dd423fb6e770beac1d13c3ed1`, read back byte-identical)

## What v145 fixes

Found by the v144 live red-team. Case 08, "Can we actually do 3 PM?" right after the model-spot explanation, got no reply at all: the route was the corrected checkpoint, but the semantic rule that handles placement-possibility questions saw spot / there in the surrounding assistant text, reinterpreted the time revision as a placement question and rejected every candidate through the terminal recovery. Case 11, "actually can we do the 13th instead", carried a stochastic decline flag from the intent classifier and the decline branch swallowed the date revision into the generic recovery ask.

1. A live turn that revised or invalidated the open checkpoint, or that resolved to a booking date or time candidate, is a booking move: the decline branch never takes it, whatever the intent classifier said.
2. The placement-possibility semantic rule yields to a live turn resolved to a booking time (as it already did for a resolved booking date) and to any checkpoint revision or invalidation.
3. The executed-checkpoint state recording runs only after every adoption gate, immediately before the commit.

Everything in v143 and v144 carries over unchanged. Versions: closed-transition contract v75, contract-harness lock v118, hard harness lock v161, divergence harness v6 (adds the two hijack cases at the contract and semantic layers, plus a genuine decline that still declines).

## Verification

- Local: full `npm test` on Node 20.20.2 on the v145 tree (without the single-release protocol variable), 86 scripts / 172 step lines, exit 0 (07:40:48Z to 07:45:39Z, six expected `ok: false` sub-results inside test:outbox-adoption); `scv-double-check-divergence-harness.js` v6, 317 checks, 0 failed, including the two v144 live hijacks reproduced at the contract and semantic layers ("Can we actually do 3 PM?" after the model-spot explanation routes to the corrected checkpoint and the semantic layer accepts it; "actually can we do the 13th instead" with a stale decline flag still routes to the time ask and clears the sibling time) and a genuine decline that still declines; the v143 executed-path replay and the v141 sequences unchanged.
- Staging container: isolated copy of the 254 manifest files plus the descriptor inside the v145 staging container (deployment `3d8ac118-6807-4490-9424-7863d3dd792c`, clean environment): `test:single-release` exit 0, full `npm test` 172 step lines, 0 `ok: false` (2026-09-03T07:48:50Z to 07:49:51Z).
- Production readiness: after deploy and after each reset: release `scv-instagram-single-20260902-v145`, fingerprint `c17312eca28ae28da3ab2fbd796240426b0bc9c0e8363dfb580bef8a030649a5`, `ok: true`, `fail_close_active: false`, `critical_alert_count: 0`.
- Live red-team on production (debug identity, after deploy, before the hand-over reset): 17 cases on the code-locked debug identity right after the clean baseline reset, all 17 provider-accepted, 9 of 9 expected checks passed, 0 template hits, no repeated assistant line, max 33.1 s (a model-authored design turn); Instagram visibility is never claimed, production has no thread client. Incident case `v145-redteam-07b-info-at-checkpoint` PASS in 3.2 s: model-spot explanation plus resume line, checkpoint kept open. `v145-redteam-08-actually-3pm` PASS in 3.4 s: corrected checkpoint with 3pm (the v144 no-reply is gone). `v145-redteam-11-ordinal-date` info in 12.6 s: time ask for the new date (model-authored, no decline hijack), then `v145-redteam-12-time-again` PASS in 10.6 s: corrected checkpoint with the 13th and 4pm. `v145-redteam-09-ambiguous` PASS in 3.5 s, `v145-redteam-10-bare-hour` PASS in 3.5 s, `v145-redteam-13-name` PASS in 4.4 s, `v145-redteam-14-unspecified` PASS in 3.8 s, `v145-redteam-15-phone` PASS in 3.6 s, `v145-redteam-16-confirm` PASS in 4.2 s: all deterministic single-pass replies. Receipts, thread inspection and evaluation are in the private v145 archive.

## Hand-over reset for the owner's red-team

Two resets on deployment `08c0a725-b137-48b0-b14d-0e667fbea36b`, operator rendered from the hash-pinned base `d0b2f2ab4b97b512ce816394e1c9ff4197c973ccb492b6497afc6778d9f8812c`. Reset 1 (clean baseline before the live red-team): pre `20260903T075315Z`, post `20260903T075320Z`, receipt sha `ce408a20e76486200b6368a6f3d7e10521deedc83ee2e8cff98035d3cda51581`, deleted 0, post-audit remaining 0. Reset 2 (hand-over): pre `20260903T075849Z`, post `20260903T075852Z`, receipt sha `f3e12b8451769d3de99e32d02c42ec4cedaa5b97b3637e6482fa4e9e2dd0b3f8`, pre-audit remaining 32, deleted 32, post-audit remaining 0, all 10 workers resumed. No traffic touched production after it; this is the hand-over state for the owner's own red-team. All artifacts pulled from the container and hash-verified against the receipts.

## R2 timestamped recovery and sentinel

control `20260903T075940Z` (sealed `2026-09-03T07:59:40.000Z`) built from the v144 control `20260903T073545Z` (49 snapshots) plus the four v145 reset points: 53 snapshots, current `scv-instagram-20260903T075852Z-v145-post-omar-reset-current`. Reset artifacts at `scv-instagram-automation/timestamped-snapshots/omar-system-reset/20260903T075320Z/` and `.../omar-system-reset/20260903T075852Z/`, each read back byte-identical; control objects under `scv-instagram-automation/timestamped-snapshots/control/20260903T075940Z/` with `LATEST.json` written last, every object read back and hash-matched, both hand-over reset points restore-drilled from the local and the published control. Drift sentinel: `scv-instagram-drift-sentinel` v10 (schema `scv-instagram-drift-sentinel-2026-09-03-v10-v145-revision-outranks-heuristics-pointer`, Worker version `b2832197-4965-49e4-b788-cd7fad610405`, cron every 5 minutes, 6/6 tests) pins the v145 release fingerprint and manifest, control `20260903T075940Z` with 53 snapshots, current snapshot `scv-instagram-20260903T075852Z-v145-post-omar-reset-current`, the catalog, seal, restore tool, both staged restore receipts, the reset receipt sha and the per-release pre-reset audit count. First v10 attestation `2026-09-03T08:05:49.000Z` (pointer `scv-instagram-automation/drift-attestations/2026-09-03/20260903T080549000Z.json` sha `6f7e22e6b0dfe4c17a348eb6b5831edb10cc1e47d3431cbf02174f01dbe60442`): ok on production, staging and snapshot control, consecutive_failures 0, no credentials and no customer message content.
