# SCV Instagram v129 custody

This is a product-specific custody record. It must not be copied into global
Codex or Claude instructions. Customer-derived state, the deployable runtime,
and the private writing reference remain private in R2 or the production
platform and must never be committed to this public repository.

## Active release

- Release ID: `scv-instagram-single-20260901-v129`
- Content fingerprint:
  `629c91f60b29124133d8020b596ea485581e8fb1fe296dbde49177d9ff4264a9`
- Release descriptor SHA-256:
  `43da079ec4cd49917c1c7dc09ac8a5ac32a74ff49926662f286cdbfe6f30a7cc`
- Private application archive:
  `scv-instagram-automation/release-ready/20260901T040911Z/v129/scv-instagram-single-20260901T040911Z-v129-human-word-choice.tar.gz`
- Application archive SHA-256:
  `ab39f73ddd572a5c6482825bfeabab30ea6ac9e3cece7da01e15223f6bbb821c`
- Production deployment:
  `cc13ec9c-43e1-4078-8e9a-0ff2c0e324c4`
- Staging deployment:
  `99863f9c-e3a3-4ade-8010-804aaf7a061b`

The release adds a deterministic, visible-output word-choice gate for ordinary
Instagram conversations. It rejects corporate or generic AI phrasing and asks
the language model to write the reply again using short, concrete verbs. The
gate does not replace rejected text with canned prose and cannot send its own
fallback message.

The private writing reference was used only to derive aggregate word-choice
rules. Its text, contact details, transaction details, and phrases were not
copied into the runtime, prompts, logs, this repository, or the R2 release
archive. The runtime explicitly marks the source as non-retrievable and not a
phrase library.

## Verification

The active single-release suite passed from both the source tree and a clean
R2-restored runtime under the pinned Node 20 toolchain. Focused checks included
25 word-choice cases, 271 contract cases, 109 hard-lock cases, 212 semantic
repair cases, 449 visible-identity adversarial cases, and 33 visible-English
cases. Staging also ran provider-bound held-output checks: six outputs reached
final adoption with no word-choice hit, broader AI-tone hit, deterministic
recovery, transport, outbox, or send. Three other synthetic cases were rejected
by pre-existing booking or permission gates and were not sent.

Production and staging both returned HTTP 200 from `/deployz` and `/readyz`,
reported the exact release ID and hashes above, kept the dated visible model,
and reported zero critical drift alerts. The one production operational
quarantine is preserved durable evidence and is not a critical release drift.

## Timestamped recovery

- Private catalog pointer:
  `scv-instagram-automation/timestamped-snapshots/LATEST.json`
- Catalog control version: `20260901T041232Z`
- Snapshot count: `14`
- April golden snapshot:
  `scv-instagram-20260420T152810-local-origin`
- Previous current v128 snapshot, retained as history:
  `scv-instagram-20260901T031348Z-v128-post-date-change-fix-current`
- Current v129 snapshot:
  `scv-instagram-20260901T040911Z-v129-human-word-choice-current`
- Catalog SHA-256:
  `b8c1a42e03c7fb1f21bb6aa41bd90facdbdb21092a4a2329a2ac678438dfe504`
- Catalog seal SHA-256:
  `48f20b24802201400a5108ee9e9d278f6e567511079d47504b6afdfb411e7201`
- Current production-state archive SHA-256:
  `8f05309cdf0e6aef52bfc4f9a6876dd848af80aeb91e3d407fd186a50936f207`

The golden pointer was not moved or overlaid. The v129 runtime and production
state were restored into a newly created staging directory, hash-checked, and
retested. The receipt records `production_mutated: false`. The catalog requires
an exact snapshot ID and does not implement automatic production cutover. All
new control objects were downloaded from R2 and verified before `LATEST.json`
was published last.

## Independent drift sentinel

- Worker: `scv-instagram-drift-sentinel`
- Worker version: `1e1f82a8-c2eb-45da-a738-d1866ffa20bc`
- Schedule: every five minutes
- Safe health endpoint:
  `https://scv-instagram-drift-sentinel.omar-git-r2-backup.workers.dev/health`
- Private attestation pointer:
  `scv-instagram-automation/drift-attestations/LATEST.json`

The Worker checks the exact v129 release ID, source fingerprint, release
descriptor, critical drift status, voice and vision capabilities, and dated
visible model. It also verifies the private R2 control version, catalog object
hash, snapshot count, distinct golden and current pointers, exact-ID restore
requirement, and disabled automatic production cutover. Its source contains no
credentials, customer messages, or private writing-reference content.
