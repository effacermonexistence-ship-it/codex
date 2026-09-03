# SCV Instagram v142 custody

Sanitized public custody surface for the v142 release of the SCV Instagram DM
automation. It contains no credentials, customer messages, media, or CDN URLs.

## Active release

- Release ID: `scv-instagram-single-20260902-v142`
- Sealed at: `2026-09-03T02:17:08.390Z`
- Source fingerprint: `0768f8f4fd892038c2495aab1f8a36e35297e0f9ce5b2112292219a3a63518e1`
- Release manifest SHA-256: `47890eed778b8faa6528f6f896af2b4f6a19ab3a9dc22cc6b93de9a30fcdfff4`
- Production deployment: `26064248-baef-4111-91c8-a85c1bd52f29`
- Staging deployment: `408560b7-0a62-4c86-813c-27c22095548a` (runtime namespace `single-staging-v142`)
- Visible model: `gpt-5.4-mini-2026-03-17` (unchanged)
- Runtime archive in private R2: `scv-instagram-automation/release-ready/20260903T021750Z/v142/scv-instagram-single-20260903T021750Z-v142-identity-revision-authority.tar.gz` SHA-256 `e69f561bbee205680b4bea5fe1a76af6ff8899d15518791fba7ab0d2aedb2dad`

## What v142 fixes

The v141 live red-team left one defect in the double-check revision family:
"the number is wrong its 4155550188" re-issued the checkpoint with the old
number. The controller re-binds name and phone to its active-slot parser after
every annotation pass and fell back to the persisted number; the revision
boundary also looked only at the immediately preceding assistant packet.

- The controller's identity rebind now applies the checkpoint revision grammar
  shared with dm-authority first, and the revision boundary uses the latest
  pending checkpoint even when clarification turns were sent after it.
- A resolved revision phrased as a question ("Can we actually do 3 PM?") is
  answered by the corrected block deterministically instead of taking the
  model lane (15 s live) through the question gate.
- `scv-double-check-divergence-harness.js` v3 replays the whole live sequence
  through the real control plane and the real spawned runner (no stub
  candidate generator) for every deterministic turn; the one model-authored
  date turn uses a model stand-in committed through the control plane. This
  is the seam that hid the v141 regression.

## Verification

- Local full `npm test`: full `npm test` on Node 20.20.2, 172 steps, 0 failures (20m48s under heavy host load; a first run tripped only the generic-info latency guard at 13.4 s under that load and was re-run); `test:single-release` on the sealed tree, 14 suites ok; `scv-double-check-divergence-harness.js` v3, 278 checks, 0 failed.
- Staging container isolated suites: isolated copy of the 252 manifest files plus the descriptor inside the v142 staging container (deployment `408560b7-0a62-4c86-813c-27c22095548a`, clean environment): `test:single-release` exit 0, full `npm test` 172 steps, 0 failures (2026-09-03T02:21:29Z to 02:22:34Z; a first ssh attempt failed on a Railway API timeout before any suite ran).
- Production after deploy: after deploy and again after the reset: release `scv-instagram-single-20260902-v142`, fingerprint `0768f8f4fd892038c2495aab1f8a36e35297e0f9ce5b2112292219a3a63518e1`, `ok: true`, `fail_close_active: false`, `critical_alert_count: 0` (the previous v141 deployment answered the first two polls during the rollover, then v142 took over).

## Hand-over reset for the owner's red-team

operator rendered from the hash-pinned base `d0b2f2ab4b97b512ce816394e1c9ff4197c973ccb492b6497afc6778d9f8812c` (rendered sha `009ed376c064fb004082af7eda5ea76c65c04d9608f3970a6f3961c4af25de42`), executed inside production deployment `26064248-baef-4111-91c8-a85c1bd52f29` on the sealed v142 tree. Receipt `/data/scv-current-snapshots/omar-system-reset-20260903T022532Z/execution.omar-system-purge.json`, sha `2aca9e73cd293fb25be695785b12bef66f5c533852806ea8db7d026fee849070`: pre-audit remaining 28, deleted 28, post-audit remaining 0, 10 workers paused and all 10 resumed. Pre-reset snapshot `20260903T022528Z` (sha `88eeb9eebbc4c2eaa3c01e59e99662cef6f3b5db0e302a87135b61d9ed8f2cae`, 2955544 bytes, 1606 entries, restore drill verified, settle passes 1, capture attempts 1); post-reset snapshot `20260903T022532Z` (sha `60440b2b79c0f361c08033bfbccb2eb5f63c167ed224d0f2bb6bc81b9d16f842`, 2811415 bytes, 1578 entries, restore drill verified, settle passes 1, capture attempts 1). All three artifacts were pulled from the container and hash-verified against the receipt before upload. This reset is the hand-over state for the owner's red-team; no red-team traffic touched production after it.

## R2 timestamped recovery and sentinel

control `20260903T023254Z` (sealed `2026-09-03T02:32:54.000Z`) built from the v141 control `20260902T233313Z` (39 snapshots) plus the two v142 reset points: 41 snapshots, golden `scv-instagram-20260420T152810-local-origin`, current `scv-instagram-20260903T022532Z-v142-post-omar-reset-current`. Catalog sha `bc37b8c84f0fbc4bc27a6ff33f12bbe8a574596ab36ae375794d28effdeacfaf`, seal sha `2bdaac0d494e8dd5fc160d970d341f595952c3aeb8d98d139f402e5298020809`, restore tool sha `4044f96616a504c9049657fbe628b63246b56a626fa57cdb5f67dc1307d3f206`. Reset artifacts at `scv-instagram-automation/timestamped-snapshots/omar-system-reset/20260903T022532Z/` (pre-reset, post-reset, `execution.omar-system-purge.json`), each read back byte-identical. Control objects published under `scv-instagram-automation/timestamped-snapshots/control/20260903T023254Z/` with `scv-instagram-automation/timestamped-snapshots/LATEST.json` written last; every object was read back and hash-matched, and both reset points were restore-drilled from the local control and again from the published control (staged restore receipts `pre-v142-omar-reset-20260903T022528Z.json` sha `b2ef605643bd074ea0fa69f38b8ad87ccdbda9914c7bfb77ab1696d783aecb5d`, `current-post-v142-omar-reset-20260903T022532Z.json` sha `69b9ffbba68bd9b2a7bf72f5f32279df73ed7289910074a9447919ea71a808df`). Drift sentinel: `scv-instagram-drift-sentinel` v8 (schema `scv-instagram-drift-sentinel-2026-09-02-v8-v142-identity-revision-authority-pointer`, Worker version `bc193813-05a9-4691-9838-6529d78dc275`, cron every 5 minutes, 6/6 tests) pins the v142 release fingerprint and manifest, control `None` with None snapshots, current snapshot `None`, the catalog, seal, restore tool and both staged restore receipts, the reset receipt sha and the per-release pre-reset audit count with a zero post-reset point. First v8 attestation `2026-09-03T02:45:16.000Z`: ok, consecutive_failures 0, no credentials and no customer message content in the attestation (`scv-instagram-automation/drift-attestations/LATEST.json`). The v7 sentinel had been reporting the control-version change as drift from the v142 control publish until v8 replaced it.
