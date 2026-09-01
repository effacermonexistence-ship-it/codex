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
- Catalog control version: `20260901T061502Z`
- Snapshot count: `16`
- April golden snapshot:
  `scv-instagram-20260420T152810-local-origin`
- Previous current v128 snapshot, retained as history:
  `scv-instagram-20260901T031348Z-v128-post-date-change-fix-current`
- v129 snapshot before the explicit Omar.system reset, retained as history:
  `scv-instagram-20260901T040911Z-v129-human-word-choice-current`
- Paused v129 state immediately before the Omar.system reset:
  `scv-instagram-20260901T061104Z-v129-pre-omar-reset`
- Current paused v129 state immediately after the Omar.system reset:
  `scv-instagram-20260901T061107Z-v129-post-omar-reset-current`
- Catalog SHA-256:
  `8c868399b47ace1744083e2004104d0ed51e3b19c39324d4644d700fe850d890`
- Catalog seal SHA-256:
  `e7f3ceced05a8595bec384f01f0b6177cbfdce78f21a2e2ccbe954ce9e182e2a`
- Pre-reset production-state archive SHA-256:
  `16e4cbc338c6c2f3b4cea1a663526df98ef5cb795eb19b480258df4add9ee0db`
- Current post-reset production-state archive SHA-256:
  `cbecefbdfc5838edb41935aafe7c0c337aea129b521ed0be4604e682f5a80fa1`
- Exact-scope reset receipt SHA-256:
  `eebb15794de2e73645a825eb52ddcebd96dd89e8af875ed47ce115e34eaa706a`

The golden pointer was not moved or overlaid. The reset suspended all ten v129
runtime workers and verified their stopped state before capturing the full
production namespace. The code-locked target was the canonical debug identity
pair only. Its audit changed from 21 matching files to zero; customer scope was
not allowed. All ten workers were then resumed.

The pre-reset and post-reset v129 runtime/state pairs were each selected by
their exact snapshot ID, downloaded from R2, restored into different new
staging directories, and hash-checked. The pre-reset restore reproduced 21
debug-account matches and the post-reset restore reproduced zero. Both restore
receipts record `production_mutated: false`. The catalog does not implement
automatic production cutover. All new control objects were downloaded from R2
and verified before `LATEST.json` was published last.

## Independent drift sentinel

- Worker: `scv-instagram-drift-sentinel`
- Worker version: `23303742-086c-4d79-a182-32351775efd2`
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
