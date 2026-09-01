# SCV Instagram v124 custody

This is a product-specific custody record. It must not be copied into global
Codex or Claude instructions. Customer-derived state and the deployable runtime
remain private in R2 and must never be committed to this public repository.

## Active release

- Release ID: `scv-instagram-single-20260831-v124`
- Content fingerprint:
  `fd4e7d064e68b27125c2530d9e369080feb0a4ca89db20c47e2f09689fb0da66`
- Release descriptor SHA-256:
  `afc47a8423f59bb5a3bfd81d2823a5b59fa36a517494021fc360838af2dbce77`
- Private application archive:
  `scv-instagram-automation/release-ready/20260831T233545Z/v124/scv-instagram-single-20260831T233545Z-v124-final-release.tar.gz`
- Application archive SHA-256:
  `83e48057d97b9b0da3f1a56aa169f33f06173e0e882314eb6ccf6f983fb5687f`

The release connects every critical drift result to the production persistent
fail-close latch. The queue, final sender, and reaction gates re-read that latch
at their network mutation boundaries. An isolated historical quarantine alert
remains operational and visible without falsely stopping an otherwise healthy
runtime.

## Timestamped recovery

- Private catalog pointer:
  `scv-instagram-automation/timestamped-snapshots/LATEST.json`
- Catalog control version: `20260831T233713Z`
- April golden snapshot:
  `scv-instagram-20260420T152810-local-origin`
- Pre-v123 rollback snapshot:
  `scv-instagram-20260831T230134Z-v122-pre-v123`
- v123 rollback snapshot:
  `scv-instagram-20260831T231133Z-v123-current`
- Current v124 snapshot:
  `scv-instagram-20260831T233545Z-v124-current`
- Catalog SHA-256:
  `492317085f9b096c8b555072554d281ec82a4af64b43e4b545ed61bb9ed8b593`

The v124 staged restore downloaded both private components, verified their
exact hashes, restored into a newly created target, and recorded
`production_mutated: false`.

## Independent drift sentinel

- Worker: `scv-instagram-drift-sentinel`
- Schedule: every five minutes
- Safe health endpoint:
  `https://scv-instagram-drift-sentinel.omar-git-r2-backup.workers.dev/health`
- Private attestation pointer:
  `scv-instagram-automation/drift-attestations/LATEST.json`

The Worker independently checks the exact v124 release ID, source fingerprint,
release descriptor, critical drift status, voice and vision capabilities, and
the dated visible model. Its source contains no credentials or customer message
content.
