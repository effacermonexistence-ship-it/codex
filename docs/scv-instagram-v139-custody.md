# SCV Instagram v139 custody

> Superseded within the hour by v140: the v139 live red-team exposed further
> holes in the same revision family and a production fail-close; see
> `docs/scv-instagram-v140-custody.md`.

This record is the sanitized public custody surface for the v139 release of the
SCV Instagram DM automation. The runtime source stays private; this document
carries identifiers, hashes, verification evidence, and the operating law that
changed. It contains no credentials, customer messages, media, or CDN URLs.

## Active release

- Release ID: `scv-instagram-single-20260902-v139`
- Sealed at: `2026-09-02T20:18:25.688Z`
- Source fingerprint (SHA-256 over the 251-file manifest):
  `01d8485f4848d4fb967137d1eb13b90814feabab7c5eec633a9f2f0f932f9855`
- Release manifest SHA-256:
  `82f3f74b71aed606b080dd0686e18fea441bab92312c7b0b316355e82150f485`
- Production deployment: `98483732-e0bc-4501-8649-b8e506819eec` (SUCCESS,
  2026-09-02T20:21:23Z); previous v138 deployment
  `439efca7-66ea-4ffa-b301-0060045c59aa` removed by the platform.
- Staging deployment: `f71f4802-61cb-4747-a995-23db89ad10de`, runtime
  namespace `single-staging-v139`.
- Visible model: `gpt-5.4-mini-2026-03-17` (unchanged).
- Runtime archive in private R2:
  `scv-instagram-automation/release-ready/20260902T201851Z/v139/scv-instagram-single-20260902T201851Z-v139-checkpoint-revision-no-template.tar.gz`
  SHA-256 `b0eb721fbe916d4cc152d21f3c8cccd992a61b805b3c7b1f759401f269fec0f9`,
  1,362,067 bytes, 252 entries, uploaded and read back byte-identical.

## Incident and root cause

During the owner's red-team of v138 (2026-09-02 19:46Z, code-locked debug
identity only) the four-field checkpoint was answered with "Can we actually do
3 PM?". The time-revision grammar rejected the modal frame because the
discourse filler "actually" had no slot, so the checkpoint was not invalidated;
the closed-transition controller froze on the confirmation wait, rejected
three model drafts (non-authoring guard, backtrack while awaiting, duplicate
double-check), and after 69 seconds shipped the fixed recovery line "got you i
saw that and i haven't changed or confirmed the booking yet what detail do you
want me to update?". The same turn also overwrote the thread's design context
with scheduling text. Every downstream step behaved correctly for an
unclassified turn; the classification was the breaking variable.

## What changed

- Booking policy `scv-booking-policy-2026-09-02-v4-checkpoint-revision-fillers-and-bare-hour`:
  modal revision frames accept discourse fillers (actually, honestly, just,
  like, maybe, then, please, …) and the change verbs push / bump / shift / set /
  put / change / reschedule; inside an open four-field checkpoint a suffixless
  hour ("3", "3:30", "three", "hmm 4") is a clock candidate on the tattoo-day
  clock (8 to 11 am, 12 noon, 1 to 7 pm). Phones, money, sizes, quantities,
  ordinals, and calendar days are never hours.
- Authority layer: a resolved revision of time, date, name, or phone
  invalidates the checkpoint and re-issues the corrected block
  deterministically on the first pass; a monthless ordinal belongs to the
  checkpoint's month; while the checkpoint is open the live turn never
  authors design context.
- Closed-transition contract `scv-closed-transition-contract-2026-09-02-v72-checkpoint-revision-routes`:
  unresolved revisions route to the exact field
  (`double_check_time_revision_unresolved`,
  `double_check_date_revision_unresolved`,
  `double_check_identity_revision_unresolved`,
  `double_check_revision_unclassified_ask_which_field`) with matching
  verifier asks.
- Deterministic recovery
  `scv-route-aware-visible-recovery-2026-09-02-v5-checkpoint-revision-ask-no-template`:
  the await-stage template is retired; every ask is built from the live turn
  and the checkpoint values ("do you want 2pm or 3pm?", "what time do you
  want instead of 3pm?", "which part do you want me to change the time the
  date or the name and number?"), rotates wording, and never repeats the
  previous assistant line. The runner answers these routes before any model
  call.
- Hard harness lock `scv-hard-harness-lock-2026-09-02-v156-checkpoint-revision-routes`.

## Verification

- Local Node 20.20.2: full `npm test` (172 steps, 0 failures, 2m22s) and
  `test:single-release` on the sealed tree (14 suites ok).
- `scv-double-check-divergence-harness` v2: 199 checks, 0 failed. It replays
  the exact incident wording through the real authority and controller path
  (one deterministic pass, corrected checkpoint, design context untouched),
  locks the filler and bare-hour grammar families with their negative
  boundaries, the four unresolved routes and their asks, and the absence of
  the retired template from the recovery source.
- Staging container (isolated copy of the manifest files, clean environment):
  `test:single-release` exit 0, full `npm test` 172 steps, 0 failures.
- Staging and production `/readyz`: `ok`, v139 fingerprint and manifest,
  critical drift 0, fail-close inactive.


## Live red-team outcome (superseding note)

Cases 01–08 of the v139 live red-team passed and the incident wording
"Can we actually do 3 PM?" produced the corrected checkpoint in 14 seconds.
Cases 09–12 fell to generic recovery for the reasons recorded in the v140
custody record, case 13 timed out, and cases 14–16 were refused because the
duplicate-visible-text critical check fail-closed production at
`2026-09-02T20:33:05Z`. A receipted Omar.system reset at `20:39:47Z` purged
the debug thread (23 files; settled capture, `settle_passes` 2,
`capture_attempts` 2). v139 is retained as history; v140 is the active
release.
