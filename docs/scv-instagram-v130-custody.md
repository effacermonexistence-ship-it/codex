# SCV Instagram v130 custody

This is a product-specific custody record. It must not be copied into global
Codex or Claude instructions. Customer-derived state, the deployable runtime,
and private writing references remain private in R2 or the production platform
and must never be committed to this public repository.

## Active release

- Release ID: `scv-instagram-single-20260901-v130`
- Content fingerprint:
  `21fd9e5f430e54236d00495b823686b9a0a042944d86211b6e701d5aee852b59`
- Release manifest SHA-256:
  `7ed809bd67c32f5a479a467e0a8acf4e99baf396de9d9e6087805d794c43f2f5`
- Private application archive:
  `scv-instagram-automation/release-ready/20260901T070849Z/v130/scv-instagram-single-20260901T070849Z-v130-double-check-divergence.tar.gz`
- Application archive SHA-256:
  `338fc56d5ac3c6d381bddaa84dcb6fc49ec2761ed3b608c6a2c23da68c79d0f8`
- Production deployment: `b83bc42d-a01e-4788-88c1-98c1838f7ce6`
- Production image:
  `sha256:1befd782e5ca5e23f233872834a6764183af1091d2ddae4587d9eb4d06b8a809`
- Staging deployment: `ee88c421-02b0-454b-ae8a-f1371022d219`
- Staging image:
  `sha256:b3fefcf62b9eb7d1993e30c4930e2cced81a2af7f217c9c0a1b535f92bfae502`

The release fixes the post-checkpoint revision boundary. A client message that
changes a name, phone number, date, or time after the visible four-field double
check now outranks the older assistant checkpoint, invalidates confirmation,
and re-enters the matching field route. Exact, ambiguous, vague, bounded, and
rejected date/time forms are handled separately. The open revision grammar
covers modal and filler variants, change/move/switch/reschedule wording,
field-label forms, case, and punctuation.

The reply path also has a route-aware liveness invariant. If an input cannot be
classified or every semantic candidate is rejected, the first complete
verifier cycle arms a visible, non-transactional answer. It does not silently
confirm, change, send, or mark a booking or deposit.

No customer identifiers or message text are present in this repository.

## Verification

The focused divergence suite passed all 78 checks from the source tree, the
staging container, the production container, and an R2-restored runtime. It
includes the production-shaped checkpoint sequence, open grammar families,
exact and non-exact revisions, all four booking fields, and the unclassified
minimum-visible-reply path.

The supported single-release suite also passed under the pinned Node 20
toolchain. Its gates included 756 booking-policy, 140 booking-history, 17
checkpoint-lane, 25 deterministic-recovery, 55 recovery-surface, 22 transport-
timeout, 59 closed-lifecycle, 271 contract, 10,010 closed-transition, 141
single-control, 83 accepted-boundary, and 109 hard-lock checks.

Production and staging returned HTTP 200 from `/deployz` and `/readyz`, reported
the exact release ID and hashes above, zero critical drift alerts, valid voice
and vision canaries, and the dated visible model. The production operational
alert is historical durable quarantine evidence and is not a critical drift.

## Timestamped recovery

- Private catalog pointer:
  `scv-instagram-automation/timestamped-snapshots/LATEST.json`
- Catalog control version: `20260901T071327Z`
- Snapshot count: `17`
- April golden snapshot:
  `scv-instagram-20260420T152810-local-origin`
- Previous current v129 snapshot, retained as history:
  `scv-instagram-20260901T061107Z-v129-post-omar-reset-current`
- Current v130 snapshot:
  `scv-instagram-20260901T070849Z-v130-double-check-divergence-current`
- Catalog SHA-256:
  `f25d069bd6eb8be2db7e115bc6e207e51365fc3c0a83ddc9feab7e4c01695b52`
- Catalog seal SHA-256:
  `904917305a6192f3b881cbbd3a3ae71a2d4186a1c818f840385c3cd2b9875cb4`
- Current production-state archive SHA-256:
  `86c9cdc0c05ba8eb8ebf0938fa45e21b063833dcddb50e5adfdf4cc8920c65d0`
- Current snapshot manifest SHA-256:
  `50c710bb7fcdd2f3570130668c906b3da144f5b60ebc60fcf4a41f6cb2fac5db`
- Current staged-restore receipt SHA-256:
  `24a82147d2d5e0c61e1eb89227c7aafcd3519f23be0ff6cc9a2d7edb0ac89783`

The golden pointer was not moved or overlaid. The current runtime and production
state were uploaded under a new timestamp and selected only by their exact
snapshot ID. The restore tool downloaded both archives from R2, verified their
hashes, sizes, and tar inventories, and restored them into a newly created
staging directory with `production_mutated: false`. After publication, every
control object was downloaded again and compared byte-for-byte with its local
source. The downloaded control set then completed a second exact-ID staged
restore. `LATEST.json` was published last.

## Independent drift sentinel

- Worker: `scv-instagram-drift-sentinel`
- Worker version: `d309cf7b-3936-4889-b70c-e5b38ad0301c`
- Schedule: every five minutes
- Safe health endpoint:
  `https://scv-instagram-drift-sentinel.omar-git-r2-backup.workers.dev/health`
- Private attestation pointer:
  `scv-instagram-automation/drift-attestations/LATEST.json`

The Worker checks the exact v130 release ID, source fingerprint, release
manifest, critical drift status, voice and vision capabilities, and dated
visible model. It also verifies the private R2 control version, catalog object
hash, snapshot count, distinct golden and current pointers, exact-ID restore
requirement, and disabled automatic production cutover. Its source contains no
credentials, customer messages, or private writing-reference content.
