# SCV Instagram v123 custody

This is a product-specific custody record. It must not be copied into global
Codex or Claude instructions. Customer-derived state and the deployable runtime
remain private in R2 and must never be committed to this public repository.

## Active release

- Release ID: `scv-instagram-single-20260831-v123`
- Content fingerprint:
  `740cc56ee25fe33cb2bef82a077814aa595c0e4734c737a8e62dc859f10fc870`
- Release descriptor SHA-256:
  `dc851f3331cd0aacfa426d24d1e6eedea97d94869ac520bba29a20c98e65b468`
- Private application archive:
  `scv-instagram-automation/release-ready/20260831T230927Z/v123/scv-instagram-single-20260831T230927Z-v123-final-release.tar.gz`
- Application archive SHA-256:
  `531f9229a08ad2a7963c2ba85c0cfa83392d194cba45a80d66d23328d320bab2`

## Timestamped recovery

- Private catalog pointer:
  `scv-instagram-automation/timestamped-snapshots/LATEST.json`
- Catalog control version: `20260831T231250Z`
- April golden snapshot:
  `scv-instagram-20260420T152810-local-origin`
- Pre-v123 rollback snapshot:
  `scv-instagram-20260831T230134Z-v122-pre-v123`
- Current v123 snapshot:
  `scv-instagram-20260831T231133Z-v123-current`
- Catalog SHA-256:
  `53e130a7a86685537c3c7e7c294c985a6cb950b275bda0c09f26832d8f2d16c8`

Each snapshot requires its exact ID, restores only into a new staging target,
and has a receipt proving `production_mutated: false`.

## Independent drift sentinel

- Worker: `scv-instagram-drift-sentinel`
- Schedule: every five minutes
- Safe health endpoint:
  `https://scv-instagram-drift-sentinel.omar-git-r2-backup.workers.dev/health`
- Private attestation pointer:
  `scv-instagram-automation/drift-attestations/LATEST.json`

The Worker verifies the exact release ID, source fingerprint, release
descriptor, critical drift status, voice and vision capabilities, and the
dated visible model. Its source is in
`products/scv-instagram-drift-sentinel`; it contains no credentials or customer
message content.
