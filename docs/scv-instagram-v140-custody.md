# SCV Instagram v140 custody

Sanitized public custody surface for the v140 release of the SCV Instagram DM
automation. The runtime source stays private; this record carries identifiers,
hashes, verification evidence, and the operating law that changed. It contains
no credentials, customer messages, media, or CDN URLs.

## Active release

- Release ID: `scv-instagram-single-20260902-v140`
- Sealed at: `2026-09-02T21:09:22.689Z`
- Source fingerprint (SHA-256 over the release manifest): `91ee1d30355c3235eec25f65bd7f117bdf7642d066c0d373a54c6a1c0a5f5f6d`
- Release manifest SHA-256: `7e6b12b23987978f9be28241089541f18b405d7a38471571eeaea3d87f74a3f8`
- Production deployment: ``ed8ba4fb-fd6a-4a32-9639-7033f9415b3f` (SUCCESS, 2026-09-02T21:14:58Z); the v139 deployment `98483732-e0bc-4501-8649-b8e506819eec` was removed by the platform`
- Staging deployment: `0ba7ce9b-4bcd-4aea-81f5-42b4cc471f1a` (runtime namespace `single-staging-v140`)
- Visible model: `gpt-5.4-mini-2026-03-17` (unchanged)
- Runtime archive in private R2: `scv-instagram-automation/release-ready/20260902T211203Z/v140/scv-instagram-single-20260902T211203Z-v140-checkpoint-revision-family.tar.gz`
  SHA-256 `937954f5d82a8f3f087f6d3c6d4916ee6de521d8ff37ac534b6b4e266b65338b`, `1,368,212` bytes, uploaded and read
  back byte-identical.

## Why v140 follows v139 within the hour

v139 fixed the exact incident wording ("Can we actually do 3 PM?" now yields
the corrected checkpoint in one deterministic pass) but its own live red-team
on the code-locked debug identity exposed four more holes in the same family:

1. The checkpoint was treated as open only when the immediately preceding
   assistant turn was the checkpoint; a clarification turn in between closed
   it, so "2 or 4?" -> ask -> "4" and "actually can we do the 13th instead" ->
   time ask -> "4pm" fell back to the confirmation wait.
2. The deterministic revision-ask packet was rejected by the control plane's
   receipt gate and by the structured-output field vocabulary, so the correct
   route still degraded to recovery text.
3. A bare numeric message ("4") was rejected as non-text by the ingress and
   replaced with the ISO `received_at` timestamp.
4. The generic recovery line had no rotation; two identical consecutive
   recovery lines tripped the duplicate-visible-text critical check and
   fail-closed production at 2026-09-02T20:33:05Z (automatic replies held
   until the latch is cleared).

## What changed in v140

- Authority layer: the checkpoint stays open until confirmed, superseded, or
  invalidated; a client revision that changed a field marks
  `checkpoint_superseded_by_revision` durably, honoured by the contract, the
  runner, and the history rebuild; restating the committed slot re-affirms it
  (v134 committed-slot polarity preserved); monthless ordinals anchor to the
  checkpoint month in history rebuild too; name-frame fillers are stripped
  from name candidates.
- Control plane: `deterministic_double_check_revision_ask` is admitted by the
  model-less receipt gate under the four revision reasons only.
- Structured-output contract v2: `double_check_revision_field` added; the
  revision reasons own the field they re-ask.
- Ingress: direct numeric replies are kept verbatim; timestamp-shaped values
  and timestamp keys are never candidate text.
- Deterministic recovery v5: the await template is retired and every recovery
  line rotates against recent assistant text.
- Reset operator: settles the namespace before each capture, retries the
  archive, and excludes the supervisor's telemetry file (rewritten by PID 1
  while the workers are stopped) from the inventory and the archive; the
  three unreceipted capture failures on 2026-09-02 were this race.
- Locks: closed-transition contract v73, contract harness lock v116, hard
  harness lock v157, booking policy v4.

## Verification

- `scv-double-check-divergence-harness.js` v2: 249 checks, 0 failed. It replays
  the entire live red-team sequence through the real control plane
  (checkpoint -> "Can we actually do 3 PM?" -> "2 or 4?" -> "4" -> "actually
  can we do the 13th instead" -> "4pm" -> name -> "wait can i change
  something" -> phone -> "looks good"): every deterministic turn is one pass,
  no route-aware recovery, no repeated line, no template.
- `scv-executed-path-booking-harness.js` (71, committed-slot polarity matrix
  intact), `scv-single-control-plane-harness.js` (141),
  `scv-contract-harness.js` (271), `scv-closed-transition-contract-harness.js`
  (10,010), `scv-media-only-inbound-harness.js` (58, numeric ingress locked).
- Local full `npm test`: full `npm test` on Node 20.20.2, 172 steps, 0 failures, 2m29s (the first candidate stopped at the hardened-contract version pin; the pin was corrected and the suite re-run before re-sealing); `test:single-release` on the sealed tree, 14 suites ok.
- Staging container isolated suites: isolated copy of the 251 manifest files plus the descriptor inside the v140 staging container (deployment `0ba7ce9b-4bcd-4aea-81f5-42b4cc471f1a`, clean environment): `test:single-release` exit 0, full `npm test` 172 steps, 0 failures (2026-09-02T21:13:23Z to 21:14:27Z); staging `/readyz` ok with the v140 fingerprint, critical drift 0, fail-close inactive.
- Production `/readyz` after deploy: release `scv-instagram-single-20260902-v140`, fingerprint `91ee1d30…`, manifest `7e6b12b2…`, critical drift 0, operational alerts 2, `ok: false` only because the fail-close latch described below is still active.

## Fail-close latch

The golden fail-close latch on the production volume
(`scv-golden-synthetic-fail-closed.json`) activated at
`2026-09-02T20:33:05.238Z` on v139 with the single failed check
`duplicate_assistant_text_visible_history` (two identical consecutive generic
recovery lines on the code-locked debug thread during the v139 live red-team).
The visible history that carried the duplicate was purged by the receipted
Omar.system reset at `2026-09-02T20:39:47Z` (23 files, settled capture), the
critical count returned to 0, and v140 removes the cause (every recovery
line rotates). The latch itself stays active until it is cleared by the
designed path: a Ben-signed Ed25519 approval receipt verified against
`SCV_BEN_APPROVAL_ED25519_PUBLIC.pem`, or an incident-scoped reconciliation
shipped in code with exact latch evidence (the v124 and v130 precedents).
No automatic clear was added in v140; the owner decides which path to use.
While the latch is active the runtime holds all new automatic replies and
`/readyz` reports `fail_close_active: true`.

## Independent drift sentinel

- Worker: `scv-instagram-drift-sentinel`
- Worker version: `200df95f-3de5-4cb7-82e3-2c717dc1596e` (schema v6); the v5 build
  `35ea7d6e-3f52-47b4-82aa-4759651c26a8` pinned the same v140 expectations but
  its first attestation reported `snapshot_catalog_object_too_large` because
  the 37-snapshot catalog passed the 64 KiB bounded-read guard; v6 raises the
  guard to 1 MiB.
- Schedule: every five minutes; safe health endpoint
  `https://scv-instagram-drift-sentinel.omar-git-r2-backup.workers.dev/health`;
  private attestation pointer `scv-instagram-automation/drift-attestations/LATEST.json`.
- Expectation: release `scv-instagram-single-20260902-v140`, fingerprint
  `91ee1d30…`, manifest `7e6b12b2…`, visible model `gpt-5.4-mini-2026-03-17`,
  control `20260902T211822Z`, 37 snapshots, golden
  `scv-instagram-20260420T152810-local-origin`, current
  `scv-instagram-20260902T211750Z-v140-post-omar-reset-current`, catalog
  `459ca750…`, seal `c941daeb…`, zero-to-zero reset audit, reset receipt
  `6ee8bdeb…`, restore receipts `380b4de5…` / `c1a2fff4…`.
- Attestations are expected to keep failing on the production target
  (`http_status`, `readiness`, `fail_close`) while the fail-close latch is
  active; that failure is the sentinel reporting the hold truthfully, not
  drift. The staging target and the snapshot control are the checks that
  prove custody in the meantime.

## R2 timestamped recovery

- Catalog control version: `20260902T211822Z`; snapshot count `37`
  (31 inherited from `20260902T192026Z`, plus the two v139 resets
  `20260902T202422Z` and `20260902T203947Z` as history, plus the v140 pre/post
  pair `20260902T211747Z` / `20260902T211750Z`); April golden pointer unchanged.
- Catalog SHA-256 `459ca7506e728ad606e43fe1d8fd313e3c735dbe691186924496fc6aebdcf475`;
  seal SHA-256 `c941daeb91b05602708855df8ec0153f6bca8f62d97ecaaf3920dd02c05a2a26`.
- v140 reset receipt `6ee8bdebeeb761e008495b8ce31647dde3b7bea161a4cd4f38190f35236f27ed`
  (pre tree `2599717b…`, post tree `87f6343f…`, 1,528 entries each, audit
  zero to zero, settled capture, all ten workers paused and resumed).
- Every object was uploaded and read back byte-identical; exact-ID staged
  restore drills ran from the locally sealed control and again from the
  published control after `LATEST.json` moved, all with
  `production_mutated: false`.
