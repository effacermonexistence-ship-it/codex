# SCV Instagram v138 custody

This is a product-specific custody record. It must not be copied into global
Codex or Claude instructions. Customer-derived state, the deployable runtime,
and private media remain private in R2 or the production platform and must
never be committed to this public repository.

## Active release

- Release ID: `scv-instagram-single-20260902-v138`
- Content fingerprint:
  `f113716920061dea80bd1eca7387258e8761460be6b3947b6fe2c2d01d5d683b`
- Release manifest SHA-256:
  `d10d9c6c63203439354e74162f54ced1e790a561ca2502b6906038c45947cf70`
- Private application archive:
  `scv-instagram-automation/release-ready/20260902T053527Z/v138/scv-instagram-single-20260902T053527Z-v138-generic-info-fast-path-transport-truth.tar.gz`
- Application archive SHA-256:
  `ed1e2506f2d81092aafaa7a64433260582cbb4bfbf9f8d145f43437a54937074`
- Production deployment: `439efca7-66ea-4ffa-b301-0060045c59aa`
- Staging deployment: `eab497f9-345f-4902-b603-31aca12dd898`

The v138 incident had two independent causes, both observed on the code-locked
debug identity. First, a self-contained general information request was routed
correctly but then spent 53 seconds in three model/verifier re-author passes,
exhausted the bounded budget, and shipped the generic recovery line instead of an
answer. Second, ManyChat accepted the send with a bare success body and no
provider message id, the runtime recorded that acceptance as
`manychat_accepted_unverified` while also logging the outcome as not ambiguous,
and a later client message would have been treated as a conversation boundary
that implied the earlier reply had been seen. The owner reported that the reply
never appeared in the Instagram thread; production has no thread client, so
visibility was never actually known.

v138 answers a self-contained general information request with a bounded
deterministic packet before the optional intent classifier and before any model
call. The packet explains the model spot, points at profile and story highlights
as inspiration, keeps custom ideas open, leaves exactly one next move, and
carries no form, rate, date, deposit, or double-check wording. Stale booking
state never resumes an old stage on that turn. Concrete motifs, price questions,
media turns, deposit claims, and controller repair passes stay on their existing
lanes. The packet is still contract-checked; a rejected packet falls back to the
existing model lane unchanged.

v138 also separates provider acceptance from Instagram visibility with four
explicit states: confirmed visible, provider accepted with visibility unknown,
confirmed failure, and transport exception with outcome unknown. Provider
acceptance is never promoted to visible success. Every accepted attempt opens an
entry in a private reconciliation ledger that survives outbox removal and closes
only through a real thread probe or an explicit operator resolution. The
accepted-unverified conversation boundary remains a dialogue-ledger inclusion
rule only and is labelled as such; a strictly newer inbound is never visibility
proof. Readiness and the admin stability endpoint expose the visibility summary,
the drift monitor reports the unconfirmed backlog as an operational alert that
never latches, and blind resend stays forbidden.

## Verification

The exact Node `v20.20.2` full suite and sealed single-release suite passed
locally and inside the deployed staging container from an isolated copy of the
sealed release tree with a sanitized environment. Focused evidence includes the
following:

- 442 generic-information fast-path checks, including the exact production
  phrase, casing and typo variants, greeting return, stale double-check and
  deposit state ownership, duplicate-text avoidance, a child-process proof that
  no provider call happens, and the full controller adopting the packet on the
  first pass with zero verifier rejections;
- 41 delivery-visibility truth checks covering all four states, provider
  timeout, 5xx, retry exception, definitive rejection, ledger deduplication,
  operator resolution, evidence preservation, and the rule that a newer inbound
  never confirms visibility; and
- the complete existing identity, authority, reply-liveness, media, date-change,
  double-check divergence, drift, prompt, and April-tone regression suite.

The sealed v138 archive contains 251 manifest-listed files plus its manifest.
Every manifest hash was reproduced from a fresh local restore before upload.
Staging and production both return HTTP 200 from `/readyz` with the exact v138
release coordinates, zero critical drift, inactive fail-close, healthy voice and
vision canaries, the dated visible model, and the new `delivery_visibility`
block. All ten production workers were running with the exact expected command set after the required reset. Production's one operational alert remains unrelated preserved queue or quarantine state and is not a critical drift alert.

## Timestamped recovery

- Private catalog pointer:
  `scv-instagram-automation/timestamped-snapshots/LATEST.json`
- Catalog control version: `20260902T055310Z`
- Snapshot count: `29`
- April golden snapshot, unchanged:
  `scv-instagram-20260420T152810-local-origin`
- v138 state immediately before the required post-fix Omar.system reset:
  `scv-instagram-20260902T054849Z-v138-pre-omar-reset`
- Current v138 state immediately after the reset:
  `scv-instagram-20260902T054852Z-v138-post-omar-reset-current`
- Catalog SHA-256:
  `05c70aea169f065d1e727bb4586c89a0e0ae8b903831f7993bd49930b3c41485`
- Catalog seal SHA-256:
  `bddd904ee1f3a71218501bc768d5de6e9d0d6dab21161be9bff0a0cc523da86a`
- Pre-reset production-state archive SHA-256:
  `ac97b363fb7fe18e55df1c1a89dc0daab59688dfd8df46ca81697f24de81524c`
- Post-reset production-state archive SHA-256:
  `5e6e1378e131864faeebfa489a635b406065293809493ab1a7fd06769572da59`
- Exact-target reset receipt SHA-256:
  `2e3af658b6a0c22b940c74e35d9d5ab44c521f6c922d1c8b23689b53a249de11`
- Pre-reset staged-restore receipt SHA-256:
  `c3b536365dd1934a89403c429998cf14a01db4635fe8a6f292552c1ee3ebd806`
- Post-reset staged-restore receipt SHA-256:
  `484f183b08411b5aad97fa8f43c7861a9e027911e644012265c28eca3a8e084e`

All ten production workers were stopped and verified before capture. The
code-locked debug audit changed from six matching artifacts to zero, the reset
watermark and Gmail tombstones were written, and all ten workers resumed. The
pre-reset tree has 1,442 entries with tree hash
`1eb6ee20f107f474f314964566e1b912d8ccb85e627a8439b41fcf6a9b2e3ded`.
The post-reset tree has 1,436 entries with tree hash
`8e71d7520c6f57e898503adb8517709ee57848663fb95c5138f27e5abc3de30b`.
Both archives and the reset receipt were downloaded from the production
container, hashed byte for byte against the operator output, and restored into
new local directories where the tree hashes and entry counts were reproduced.

The runtime archive, both state archives, reset receipt, catalog, seal, and
restore receipts were uploaded to R2 after the owner re-authenticated the pinned
Wrangler, then downloaded again and checked byte for byte. The restore tool
first restored both exact v138 timestamps from the locally sealed control, and
then again from the published control after `LATEST.json` moved to
`20260902T055310Z`; every drill reported `production_mutated: false` and
reproduced the receipt tree hashes and entry counts. The April golden pointer
remained separate, the v138 post-reset point became current, and the v137
current point was retained as history.

## Second Omar.system reset before the owner's red-team

After the v138 live red-team cycle (which consumed the `20260902T054852Z`
reset point), a fresh exact-target Omar.system reset was executed on the same
production deployment so that the owner's own red-team starts from a receipted
clean state. The catalog control moved forward and the previous v138 points
were retained as history.

- Catalog control version: `20260902T192026Z`
- Snapshot count: `31`
- April golden snapshot, unchanged:
  `scv-instagram-20260420T152810-local-origin`
- State immediately before the second reset:
  `scv-instagram-20260902T191130Z-v138-pre-omar-reset-2`
- Current state immediately after the second reset:
  `scv-instagram-20260902T191131Z-v138-post-omar-reset-2-current`
- Catalog SHA-256:
  `6b376d3b1d4f04d69f1c1a394aa9815989569a93682c9fbb6ed6426f065a03ed`
- Catalog seal SHA-256:
  `83bb0c7a7e4746e02eac324d6b6696c503578dd3724f16b774432b2b69fdcd4d`
- Pre-reset production-state archive SHA-256:
  `65e1d2dd618d101a3151c5beed1f8425278fcb53b941e380ea4890491edccfa1`
- Post-reset production-state archive SHA-256:
  `0f0c069096bb17a4a278b874fd87827d39b259c4b2f4b0cdde7f5f46b350942e`
- Exact-target reset receipt SHA-256:
  `6bf342e97aa17760f8dbd4048f94d2fda1ef8bf6162165362f266c5998fa7e46`
- Pre-reset staged-restore receipt SHA-256:
  `e73c55c1393630cc5fe06150623e969085da79d1aeb03978e2a8432761a2647c`
- Post-reset staged-restore receipt SHA-256:
  `de7eb25dce039dc76fd00aec16b8bd195e9fd1b544b1adacd314b63e8a4b09cc`

The receipted reset ran at `2026-09-02T19:11:31Z` with all ten workers stopped
and the pause barrier verified. Both the pre-reset and post-reset code-locked
audits were zero, because an operator run started one minute earlier had
already purged the red-team state (19 namespace entries: one thread state, one
thread history, two failed reaction records, fifteen outbox idempotency keys)
and then failed closed during its post-reset capture when the namespace tree
inventory changed between the two capture passes; that run wrote no receipt and
resumed every worker. The receipted run is the authoritative reset point, and
the unreceipted purge is documented as such rather than folded into the
receipt. Both trees have 1,464 entries; the pre-reset tree hash is
`17a7e2fb6234766453f4f23556b95c4a9308c9686ae69cb445eb46b2a366ba7a` and the
post-reset tree hash is
`22acf23f1fd00f44f3d584e65b3960bd9710f851961553d0215420f0833b0a61`.

The archives and receipt were downloaded from the production container and
hashed byte for byte against the operator output, uploaded to R2 under
`omar-system-reset/20260902T191131Z/`, downloaded again and re-hashed, and
restored by exact snapshot ID from the locally sealed control and then again
from the published control after `LATEST.json` moved to `20260902T192026Z`.
Every drill reported `production_mutated: false`.

## Live red-team and visibility boundary

After the fresh reset, thirteen live cases were injected through the
authenticated inbound path for the code-locked debug identity only: two generic
information requests, a concrete motif, an explicit form request, a price
question, a form-submitted claim, a name-and-phone turn, a date proposal, a time
change during the double-check, an unrelated studio-location question, a
confirmation, a short acknowledgement, and a duplicate re-post of the last
inbound. Every case produced a provider-accepted reply; the duplicate was dropped
as a duplicate without a new delivery. Both generic information requests were
answered by the deterministic fast path in under five seconds with different
wording. Four cases exposed pre-existing verifier-exhaustion behaviour that v138
does not change: the motif and price turns shipped route-aware recovery text
after three rejections, the name-and-phone turn was classified as unintelligible
and answered with a clarification, and the final short acknowledgement fell to a
recovery line that repeated an earlier time. These are recorded in the private
red-team receipt for the next fix cycle.

Every red-team reply was recorded as `provider_accepted_visibility_unknown` with
`delivery_confirmed: false`. Production has no Instagram thread client, so no
reply in this record is claimed to be visible in the Instagram thread; the
reconciliation ledger holds one open entry per accepted bubble until a real
probe or an explicit operator resolution closes it.

## Independent drift sentinel

- Worker: `scv-instagram-drift-sentinel`
- Worker version: `429d7638-6a6c-40f1-97b1-f7c9de84e3af` (sentinel schema v4; the v3 version `c3dc52f3-f530-4172-b345-be7fa19f15f0` attested the first v138 control)
- Schedule: every five minutes
- Safe health endpoint:
  `https://scv-instagram-drift-sentinel.omar-git-r2-backup.workers.dev/health`
- Private attestation pointer:
  `scv-instagram-automation/drift-attestations/LATEST.json`

The Worker checks the exact v138 release ID, source fingerprint, release
manifest, critical drift, fail-close state, voice and vision capabilities, and
dated visible model. It also verifies the sealed 31-snapshot R2 timeline, the
distinct April golden and v138 current pointers, the pre-to-post link of the
second reset, the zero-to-zero debug audit of that receipted reset, the reset
receipt hash, and both exact-ID staged restore receipt hashes. Its source contains no credentials or customer message
content. Between the v138 production deployment and the Worker redeploy its
scheduled attestations failed closed against the retired v137 expectation, which
is the intended behaviour for a release the sentinel has not been told about.
The first scheduled v138 attestation at `2026-09-02T18:55:28.000Z` passed
production, staging, and snapshot control with zero consecutive failures; its
SHA-256 is
`3e74c7f2b43407cfcef9a3128a2dd5bd780efa3541c181aef01770040702e924`.
After the second reset the control moved to `20260902T192026Z` and the v4
Worker was deployed before the next tick; the first v4 attestation at
`2026-09-02T19:25:28.000Z` passed production, staging, and the 31-snapshot
control with zero consecutive failures. Its SHA-256 is
`7a5caee49554261fd9cdf3da10a3fe4808f3a61c337af04298021b46df416904` and it is
stored at
`scv-instagram-automation/drift-attestations/2026-09-02/20260902T192528000Z.json`.
