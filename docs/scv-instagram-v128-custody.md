# SCV Instagram v128 custody

This is a product-specific custody record. It must not be copied into global
Codex or Claude instructions. Customer-derived state and the deployable runtime
remain private in R2 and must never be committed to this public repository.

## Active release

- Release ID: `scv-instagram-single-20260901-v128`
- Content fingerprint:
  `dd04bfc17ff04171e93549fb9613b21960724cb1f867ec822c4bb03d4424f540`
- Release descriptor SHA-256:
  `81d7830733b3a404e5cc4461873acba41a53c47720a894c4e1571f2856cd2ef2`
- Private application archive:
  `scv-instagram-automation/release-ready/20260901T031348Z/v128/scv-instagram-single-20260901T031348Z-v128-final-release.tar.gz`
- Application archive SHA-256:
  `a95beef809eff2adb021eb1a71a04a605dd001443c695de61836e71d938bc7ba`

The release fixes two interacting date-change failures. Historical form-receipt
language is no longer misclassified as a repeated form-link permission offer,
so that legitimate wording cannot activate the persistent fail-close latch.
The controller also preserves every exact offered date/time pair from a
multi-slot assistant message. A client who changes only the date at the
double-check stage can therefore select the matching historical time without
silently inheriting an unrelated slot. An unoffered date still requires an
explicit time and cannot reach the deposit transition.

Deployment health now uses `/deployz`, which permits a repaired image to
replace a fail-closed image while customer-facing send gates remain closed.
`/readyz` continues to fail closed until the persistent latch is reconciled by
bounded evidence.

## Live incident verification

The previously unanswered date-change turn was recovered once through the
verified stale-operator envelope. Production committed the requested date as
September 7, retained the historically paired 2pm time, emitted one corrected
four-field double-check, and did not request a deposit. The target was removed
from every live queue after ManyChat accepted the send.

The provider receipt is `manychat_accepted_unverified`. The production image
does not contain the optional Instagram session client, so this custody record
does not claim an independent Instagram-visible thread match.

## Timestamped recovery

- Private catalog pointer:
  `scv-instagram-automation/timestamped-snapshots/LATEST.json`
- Catalog control version: `20260901T031917Z`
- Snapshot count: `13`
- April golden snapshot:
  `scv-instagram-20260420T152810-local-origin`
- Pre-fix v124 snapshot:
  `scv-instagram-20260901T023742Z-v124-pre-date-change-fix`
- Current post-fix v128 snapshot:
  `scv-instagram-20260901T031348Z-v128-post-date-change-fix-current`
- Catalog SHA-256:
  `1389d490d005ca9cadedee5936cbf7428b966360df3d7a60e686f041f7026de9`
- Catalog seal SHA-256:
  `0333025d25821760119bc71b076a72fb9f6f50561820abddef23f4e17527fd01`

The golden pointer was not moved. Both new private snapshots were downloaded
from R2, hash-checked, and restored into separate newly created staging
directories. Both receipts record `production_mutated: false`; the catalog
requires an exact snapshot ID and does not implement automatic production
cutover.

## Independent drift sentinel

- Worker: `scv-instagram-drift-sentinel`
- Schedule: every five minutes
- Safe health endpoint:
  `https://scv-instagram-drift-sentinel.omar-git-r2-backup.workers.dev/health`
- Private attestation pointer:
  `scv-instagram-automation/drift-attestations/LATEST.json`

The Worker independently checks the exact v128 release ID, source fingerprint,
release descriptor, critical drift status, voice and vision capabilities, and
the dated visible model. Its source contains no credentials or customer message
content.
