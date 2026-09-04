# SCV Instagram v141 custody

Sanitized public custody surface for the v141 release of the SCV Instagram DM
automation. It contains no credentials, customer messages, media, or CDN URLs.

## Active release

- Release ID: `scv-instagram-single-20260902-v141`
- Sealed at: `2026-09-02T23:22:36.806Z`
- Source fingerprint: `868bd74370bc400cd7f70d963ac79abfe812d79b93bd04543b1bcf675e2f5cb7`
- Release manifest SHA-256: `caff9348b62f7aa98fdceda35abca92fb40728223251af0bafeda4a9280ad058`
- Production deployment: ``a5021bbc-046b-4863-8dd3-f8643778b2e1` (SUCCESS, 2026-09-02T23:26:45Z)`
- Staging deployment: `6dea8b03-e687-4396-879b-081f6de3aea2` (runtime namespace `single-staging-v141`)
- Visible model: `gpt-5.4-mini-2026-03-17` (unchanged)
- Runtime archive in private R2: `scv-instagram-automation/release-ready/20260902T232247Z/v141/scv-instagram-single-20260902T232247Z-v141-latch-reconciliation.tar.gz` SHA-256 `0eb46eb1af0b5c11c49147d2bfcbc15a17f02a7e068bfacea883ca5f21815be9`

## What v141 adds over v140

v140 already fixed the double-check revision family; v141 is the same runtime
plus the incident-scoped repair path for the fail-close latch that v139's
non-rotating recovery line raised at `2026-09-02T20:33:05.238Z`:

- `scv-golden-fail-close.js` gains `KNOWN_DUPLICATE_RECOVERY_TEXT_INCIDENT`
  and `reconcileKnownDuplicateRecoveryTextFailClose`, mirroring the v124 and
  v130 incident reconciliations. It archives the latch only when every piece
  of evidence matches: the exact latch identity (release, fingerprint,
  activation time, reason, the single failed check
  `duplicate_assistant_text_visible_history`), the replacement release
  `scv-instagram-single-20260902-v141` with a different fingerprint, the
  repaired hard harness lock `…v158-duplicate-recovery-text-reconciliation`,
  the fixed recovery version `…v5-checkpoint-revision-ask-no-template`, a
  fresh zero-critical drift result, and a receipted Omar.system purge of the
  affected debug thread executed after the latch. It writes an audit receipt
  next to the archived latch. Any other latch still requires the Ben-signed
  approval receipt.
- `scv-reconcile-known-duplicate-recovery-text-fail-close.js` is the operator
  CLI that runs inside the production container with the verified single
  release, the live drift status, and the newest post-latch purge receipt.
- `scv-drift-severity-harness.js` locks the evidence gates (seven rejected
  attempts, one accepted, second run refused).
- The owner directed this repair on 2026-09-02 after the root cause was fixed
  in v140 and the debug thread was purged.

## Verification

- Local full `npm test`: full `npm test` on Node 20.20.2, 172 steps, 0 failures, 2m24s; `scv-drift-severity-harness.js` now covers the duplicate-recovery-text reconciliation; `scv-hard-harness-lock.js` v158 and `scv-approved-config-lock.js` pass.
- Staging container isolated suites: isolated copy of the 252 manifest files plus the descriptor inside the v141 staging container (clean environment): `test:single-release` exit 0, full `npm test` 172 steps, 0 failures (2026-09-02T23:24:27Z to 23:25:29Z); staging `/readyz` ok with the v141 fingerprint `868bd743…`.
- Production after deploy: release `scv-instagram-single-20260902-v141`, fingerprint `868bd743…`, critical drift 0; `ok: false` only until the reconciliation below, then `ok: true` with `fail_close_active: false`.

## Latch reconciliation

Run inside the production container at `2026-09-02T23:28:12Z` with the
verified single release, the live drift status, and the newest post-latch
purge receipt (`omar-system-reset-20260902T211750Z`):

```
ok: true, reconciled: true, failures: []
replacement_release_id: scv-instagram-single-20260902-v141
replacement_release_fingerprint_sha256: 868bd74370bc400cd7f70d963ac79abfe812d79b93bd04543b1bcf675e2f5cb7
archived: scv-golden-synthetic-fail-closed.json.reconciled-duplicate-recovery-text-1788391692614.json
audit:    scv-duplicate-recovery-text-reconciliation-1788391692614.json
```

The activation claim was archived alongside the latch. `/readyz` returned
`ok: true`, `fail_close_active: false`, critical drift 0 on the next drift
cycle, and automatic replies resumed. The latch had held all new automatic
replies from `20:33:05Z` to `23:28:12Z`.

## Live red-team after reconciliation

Sixteen cases on the code-locked debug identity after the fresh reset
`20260902T233034Z` (receipt `f9b63489…`). Every reply was provider-accepted;
no reply carried the retired template and no reply repeated the previous
line. The revision family behaved as designed: "Can we actually do 3 PM?"
(15.5 s, corrected checkpoint), "2 or 4?" (3.9 s, "do you want 2pm or
4pm?"), "4" (3.2 s, corrected checkpoint), "actually can we do the 13th
instead" (24.6 s, model-authored time ask), "4pm" (11.1 s, corrected
checkpoint on the 13th), "my name is actually Omar Sys" (4.4 s, corrected
name), "wait can i change something" (3.8 s, which-field ask), "looks good"
(4 s, deposit handoff). One defect remained: "the number is wrong its
4155550188" (3.2 s) re-issued the checkpoint with the old number because the
controller re-binds identity to its active-slot parser after annotation and
fell back to the persisted number. v142 fixes it and proves the whole
sequence through the real control plane and the real spawned runner.

## R2 timestamped recovery and sentinel

- Catalog control version `20260902T233313Z`; snapshot count `39` (37
  inherited from `20260902T211822Z` plus the v141 pre/post pair
  `20260902T233030Z` / `20260902T233034Z`); April golden pointer unchanged.
- Catalog SHA-256 `7db2c95a0785df31cfbcd93b8d848e493f31037c01577eac90129b2f0d16b92a` and seal SHA-256
  `0b322a75e2c9c0231a57ac57d9103d0dfd75397765b0ded96596b58de9408396`; every object uploaded and read back byte-identical;
  exact-ID staged restore drills from the local and the published control with
  `production_mutated: false`.
- Drift sentinel v7 (`4bdbb8f2-c3b4-4a9c-b3f8-e11792e4892c`, schema
  `…v7-v141-latch-reconciled`) first attestation `2026-09-02T23:50:59Z`:
  production ok, staging ok, snapshot control ok, zero consecutive failures.
