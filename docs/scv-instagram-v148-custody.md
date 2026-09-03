# SCV Instagram v148 custody record (2026-09-03)

v148 replaces v147 on production (v147 went live at 18:05Z with a 10/10 live red-team and published its own R2 control `20260903T181548Z`, but was superseded by v148 before a GOLD freeze and has no separate custody document; v146 before it was superseded within twelve minutes after its live red-team failed two cases and has no record of its own; every executed reset of v146 and v147 is a point of the v147 control that the v148 control extends). v148 is the owner-accepted v145 (GOLD-2) plus the one polish item the owner ordered after accepting it, plus the fixes for the two drifts that the v146 live red-team exposed, plus the design-turn robustness that the v147 live red-team exposed (56 s verifier loop on a volunteered placement); the private runtime source stays private. v146, v147 and v148 were all sealed through the GOLD-2 anti-drift gate (declared change card, diff against the gold artifact materialized from R2, full suite, golden conversation replays); v148 is frozen as GOLD-3 (`docs/scv-instagram-gold-3-2026-09-03.md`). The v138 to v145 records are retained alongside it.

## Active release

- Release id: `scv-instagram-single-20260902-v148`
- Sealed at: `2026-09-03T20:39:52.926Z`
- Content fingerprint (sha256): `3a9a18631443f4738d13dd803f080979ff4d21ab0d9de1f5054b2f26e2ea3609`
- Release manifest sha256: `b3e9d7ba794fa9c6cb33a32727cf1870c9af2a2c54a1e191c0321cab9ff0f0ec`
- Production Railway deployment: `5d6e1dff-586e-4f20-b024-2a04087566f5`
- Staging Railway deployment: `d2018c73-97b0-4619-907b-8d4719602357`
- Runtime archive in R2: `scv-instagram-automation/release-ready/20260903T204032Z/v148/scv-instagram-single-20260903T204032Z-v148-acknowledge-and-defer-placement-size-on-the-design-turn.tar.gz` (sha256 `a8b26655c3418173541cc474f71037d487bb9415f83a63901ffd072ac461aba4`, read back byte-identical)

## What v148 changes

Found by the owner's own red-team on v145 (the run he accepted): "Can we do fifth of September?" right after the form link took 70 s and a model-authored decline. Two causes (fixed in v146): the booking policy read only numeric days ("5th", "September 5"), so the ordinal word never became a calendar candidate; and the deterministic outside-window decline was gated on a matched form submission, so a date answered before the form match fell through to the generic tattoo lane.

1. Ordinal words first through thirty-first (hyphenated or spaced) read as calendar days before every calendar scan (booking policy v5; the invariant fingerprint moved).
2. A date answer to the assistant's date ask after the form link is an availability turn whether or not the form submission has been matched yet; the outside-window decline is the deterministic packet with the earliest opening (closed-transition contract v76).
3. The contextual calendar-day reply ("can we do the fifth?") also opens after the form link when the assistant's open question is the date, routing to the month clarification instead of a generic model turn (dm-authority).

Everything in v143 to v145 carries over unchanged.

The v146 live red-team on production (16:36Z to 16:46Z) then exposed two drifts that the local suites and the GOLD-2 replays cannot see, because they run without the intent classifier and without the production history shape:

4. "Can we do fifth of September?" before the form match carried no live date status (dm-authority began booking context at the form match); the intent classifier labelled it a stand-alone question and the outside-window route flipped to social, three verifier passes and the recovery line "what date would you like me to check?" (56 s). Now the assistant's open date ask after the form link is booking context, a resolved live calendar proposal outranks the classifier's stand-alone flags (contract v77), and the decline is authored before the classifier runs (runner pre-intent lane).
5. That recovery line plus later ordinary replies were fused by the four-field double-check detector's sliding window across turns into one "sent double-check"; the real block at the identity turn was rejected as a duplicate, the model re-authored it, the executed block was not recorded (deterministic executor only) and the next three turns routed as "identity missing" (68 s, 88 s). Now a double-check object is one assistant reply (never fused across client turns; contract-harness lock v119) and the executed four-field block persists identity and the open checkpoint whichever executor produced it.

6. The v147 live red-team's design turn ("i'm thinking a small dagger on my inner forearm, black and grey") took 56 s: the verifier demands that a volunteered placement/size be acknowledged and deferred to the appointment, nothing told the model so up front, three passes failed and the bare recovery line "want me to send the application form?" went out. Now the route carries an `acknowledge_and_defer_placement_size` obligation that the model instructions state before the first pass (contract v78), and the form-offer recovery line itself acknowledges the detail and defers it (route-aware recovery v7).

Versions: booking policy v5, closed-transition contract v78, contract-harness lock v119, hard harness lock v164, route-aware recovery v7, booking policy harness v10, divergence harness v9.

## Verification

- Gold guard (GOLD-2 gate) on the candidate tree with change card `change-card-v148.json` (10 declared files, two of them locked with owner approval): gold materialized from R2 and fingerprint-verified, diff fully declared, full local suite exit 0, golden replays ok for gold-a (17 turns, 17 exact) and ok for gold-b (7 turns, 6 exact, the declared gold-b-04 divergence: the model-authored decline became the deterministic decline packet). Verdict: PASSED.
- Local: full `npm test` on Node 20.20.2 on the v148 tree (without the single-release protocol variable), exit 0, twice (stand-alone and inside the guard).
- Staging container: isolated copy of the 254 manifest files plus the descriptor inside the v148 staging container (deployment `d2018c73-97b0-4619-907b-8d4719602357`, clean environment): isolated suites on the sealed v148 in the staging container: test:single-release exit 0, full npm test 172 steps, 0 failures
- Production readiness: after deploy and after each reset: release `scv-instagram-single-20260902-v148`, fingerprint `3a9a18631443f4738d13dd803f080979ff4d21ab0d9de1f5054b2f26e2ea3609`, `ok: true`, `fail_close_active: false`, `critical_alert_count: 0`.
- Live red-team on production (debug identity, after deploy, before the hand-over reset): 18 cases, 18 provider-accepted, 10 of 10 expected checks passed, 0 template hits, 0 repeated assistant lines, max 37 s. The target case "Can we do fifth of September?" right after the form link answered deterministically (too soon, earliest opening) and the whole checkpoint sequence stayed deterministic. Instagram visibility is never claimed; production has no thread client.

## Hand-over reset for the owner's red-team

Two resets on deployment `5d6e1dff-586e-4f20-b024-2a04087566f5`, operator rendered from the hash-pinned base `d0b2f2ab4b97b512ce816394e1c9ff4197c973ccb492b6497afc6778d9f8812c`. Reset 1 (clean baseline before the live red-team): pre `20260903T204620Z`, post `20260903T204624Z`, receipt sha `31b999f09a6077b0908757509252e3fcb23583e9790ba07bdae07f3489c8e4aa`, deleted 0, post-audit remaining 0. Reset 2 (hand-over): pre `20260903T205142Z`, post `20260903T205146Z`, receipt sha `29e45bf551b4762f1c8a4320483327a6219f81da66b19b8e0430868cf4d75d81`, pre-audit remaining 36, deleted 36, post-audit remaining 0, all workers resumed. The GOLD-3 state capture that followed paused every worker, purged nothing and modified no state; no other traffic touched production after the hand-over reset. All artifacts pulled from the container and hash-verified against the receipts.

## R2 timestamped recovery and sentinel

control `20260903T205303Z` (sealed `2026-09-03T20:53:03.000Z`) built from the v145 control `20260903T075940Z` (53 snapshots) plus the four v148 reset points: 65 snapshots, current `scv-instagram-20260903T205146Z-v148-post-omar-reset-current`. Reset artifacts at `scv-instagram-automation/timestamped-snapshots/omar-system-reset/20260903T204624Z/` and `.../omar-system-reset/20260903T205146Z/`, each read back byte-identical; control objects under `scv-instagram-automation/timestamped-snapshots/control/20260903T205303Z/` with `LATEST.json` written last, every object read back and hash-matched, both hand-over reset points restore-drilled from the local and the published control. Drift sentinel: `scv-instagram-drift-sentinel` v12 (schema `scv-instagram-drift-sentinel-2026-09-03-v12-v148-ordinal-dates-pointer-pointer`, Worker version `8c204740-531e-4a8d-b2f3-1abce464e4ba`, cron every 5 minutes) pins the v148 release fingerprint and manifest, control `20260903T205303Z` with 65 snapshots, current snapshot `scv-instagram-20260903T205146Z-v148-post-omar-reset-current`, the catalog, seal, restore tool, both staged restore receipts, the reset receipt sha, the per-release pre-reset audit count, and the GOLD-3 pointer and manifest (`scv-instagram-automation/gold/SCV_GOLD_MANIFEST_v148.json`, sha `31ea4507381e6ec2c3ce4458d70af4a311f331a4a26651f5d9234a01312766cc`); first ok attestation `None`.

## GOLD-3

`docs/scv-instagram-gold-3-2026-09-03.md`: gold state capture `scv-instagram-automation/timestamped-snapshots/gold/20260903T205411Z/prod-v148-gold.tar.gz` (sha `9b8fa2605dec31d3709641fc77d529b9febc47b144d827f7ad3eef081224e795`), golden conversations `gold-a-v145-live-red-team.json`, `gold-b-owner-red-team.json`, `gold-c-v148-live-red-team.json`, restore drill True, gold manifest sha `31ea4507381e6ec2c3ce4458d70af4a311f331a4a26651f5d9234a01312766cc`.

## Boundaries

- ManyChat acceptance is not Instagram visibility; no reply in this record is claimed visible.
- The v148 live red-team and the GOLD-3 capture were performed by the operator session on the debug identity; the owner has not yet red-teamed v146, v147 or v148 himself.
- v146 (fingerprint `a4c39dcf239f94b9f13231a17bb6f69a8721f799614445bee9f916ceaa3d3ffb`, deployment `7e45ae41-8c0d-434a-bfa8-5d20917eb8f2`) served production from 16:36Z to the v147 deploy at 18:05Z; its live red-team failed cases 03b and 09 (evaluation kept in the private archive), its two resets are prior points of the v148 control, and it has no custody record of its own.
- Private runtime source, incident media, customer messages and CDN URLs stay out of this repository; this record carries identities and hashes only.
