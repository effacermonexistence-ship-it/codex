# SCV Instagram v136 custody

This is a product-specific custody record. It must not be copied into global
Codex or Claude instructions. Customer-derived state, the deployable runtime,
and private media remain private in R2 or the production platform and must
never be committed to this public repository.

## Active release

- Release ID: `scv-instagram-single-20260901-v136`
- Content fingerprint:
  `eef5fffce5341fd1c56e96f7b004d47a6227e0f6bd9a5379fb2e55919950e577`
- Release manifest SHA-256:
  `e26ad84da2802bbbeeaccdd39bf1eca015d73b152e635e8f2a7e71ef9e33af13`
- Private application archive:
  `scv-instagram-automation/release-ready/20260902T002700Z/v136/scv-instagram-single-20260902T002700Z-v136-media-attachment-continuity.tar.gz`
- Application archive SHA-256:
  `11f4e637d51d020e3b6f68a3a9fb11b6c5bb7f5e7ed67b732930fc5979c145a8`
- Production deployment: `2fe3bac8-563b-48d7-a266-4afe2ba77ed9`
- Staging deployment: `cff96950-681b-4dc8-b898-6dffbef093bb`

The incident had two independent causes. The provider delivered valid CDN
media URLs but left `media_type` empty, while the legacy runner treated every
MP4 as voice. A valid screenshot packet was then followed four seconds later
by a same-thread referring text packet. Inbox latest-wins handling quarantined
the media packet before the runner could inspect it, so the text turn lost its
attachment context.

v136 classifies trusted media from container tracks and file signatures rather
than a missing provider label. An MP4 with a video track is not sent to voice
transcription: a bounded representative JPEG frame is extracted and passed to
the existing vision path. Audio-only containers keep the voice path, and image
signatures keep the direct image path. The production image now includes
`ffmpeg`, and startup fails closed if the frame-extraction runtime is absent.

Inbox coalescing now carries a trusted attachment into a same-provider,
same-thread referring turn only inside a 20-second window. The authority layer
accepts only the code-created provenance marker. Cross-thread, stale, future,
untrusted, and divergent attachments are rejected. Unsupported, expired, or
unsafe media follows a deterministic visible clarification path instead of
pretending that the attachment was inspected.

## Verification

The exact Node `v20.20.2` full suite and sealed single-release suite passed in
the deployed staging container. Focused evidence includes the following:

- 27 media-continuity checks, including the exact screenshot-to-referring-text
  timing and all cross-thread, stale, future, untrusted, and divergence gates;
- the complete existing regression suite, including date-change, information
  authority, reply-liveness, closed-transition, identity, and April-tone
  controls; and
- single-release checks that recorded zero protected legacy-runtime reads.

The incident video and screenshot were downloaded only into isolated staging,
verified against their local SHA-256 values, exercised through the deployed
runtime, and then removed. The video was classified from an ISO-BMFF video
track, its representative JPEG frame was extracted, and the vision path
returned nonempty descriptions for both that frame and the direct screenshot.
No private media or derived description is present in this repository.

Production and staging return HTTP 200 from `/readyz` with the exact v136
release coordinates, zero critical drift, inactive fail-close, healthy voice
and vision canaries, and the dated visible model. Production's one operational
alert remains unrelated preserved queue or quarantine state and is not a
critical drift alert.

## Timestamped recovery

- Private catalog pointer:
  `scv-instagram-automation/timestamped-snapshots/LATEST.json`
- Catalog control version: `20260902T003213Z`
- Snapshot count: `25`
- April golden snapshot, unchanged:
  `scv-instagram-20260420T152810-local-origin`
- v136 state immediately before the required post-fix Omar.system reset:
  `scv-instagram-20260902T002908Z-v136-pre-omar-reset`
- Current v136 state immediately after the reset:
  `scv-instagram-20260902T002911Z-v136-post-omar-reset-current`
- Catalog SHA-256:
  `8847950b7950e2e37bcb48556752b2591e0426bc078ee06f623d943a4b58de96`
- Catalog seal SHA-256:
  `6a325a450dbe2e453e92d1ac845e0aecd9e2859ed01b25e81d88bf4c13e8a15b`
- Pre-reset production-state archive SHA-256:
  `958c03fb39be91aa6edd3622b22c8eec9a9efbe53e9cce3306be9c2a2f3474c1`
- Post-reset production-state archive SHA-256:
  `0afdce3df55ab7a0552dd87745c054989d88dfada247cd098c2ee527473581c1`
- Exact-target reset receipt SHA-256:
  `7bea9c570975ad247756b44713da0d948cd03960729e529a4d3e3e7df4e56302`
- Pre-reset staged-restore receipt SHA-256:
  `02a73e51befb45e4c04864d369e0dbf63ff3e75c4408306bade311e2875d00e6`
- Post-reset staged-restore receipt SHA-256:
  `cd629f420a38a6d9473ec208972f7a528b0a295c37a5a80a3e77b7ec263ed10e`

All ten production workers were stopped and verified before capture. The
code-locked debug audit changed from ten matching artifacts to zero, the reset
watermark and Gmail tombstones were written, and all ten workers resumed. The
pre-reset tree has 1,422 entries with tree hash
`daed17887f6bdf94109ccce2d8810eb604e6237b0be5cd5aaf6460190c83433e`.
The post-reset tree has 1,412 entries with tree hash
`6916227bff40bb333a08183a7fd3fcd0abba8bbde9ecafcee981cd4e6fc8e6ce`.

The runtime archive, both state archives, reset receipt, catalog, seal, and
restore receipts were downloaded from R2 and checked byte for byte. The
published restore tool then restored both exact v136 timestamps into new
directories and reproduced the expected ten-to-zero debug audit without
mutating production. The April golden pointer remained separate, automatic
production cutover remained disabled, and the previous v135 current point was
retained as history.

## Independent drift sentinel

- Worker: `scv-instagram-drift-sentinel`
- Worker version: `97d1a472-8dff-430b-bb21-ac9830b14024`
- Schedule: every five minutes
- Safe health endpoint:
  `https://scv-instagram-drift-sentinel.omar-git-r2-backup.workers.dev/health`
- Private attestation pointer:
  `scv-instagram-automation/drift-attestations/LATEST.json`

The Worker checks the exact v136 release ID, source fingerprint, release
manifest, critical drift, fail-close state, voice and vision capabilities, and
dated visible model. It also verifies the sealed 25-snapshot R2 timeline, the
distinct April golden and v136 current pointers, the pre-to-post reset link,
the ten-to-zero debug audit, the reset receipt hash, and both exact-ID staged
restore receipt hashes. Its source contains no credentials or customer message
content. The first scheduled v136 attestation at
`2026-09-02T00:40:03.000Z` passed production, staging, and snapshot control with
zero consecutive failures; its SHA-256 is
`e250eaa3f51152fb808cc7171961c7ab6ddd84498e94a50bae3c61d4e9a6a02b`.
