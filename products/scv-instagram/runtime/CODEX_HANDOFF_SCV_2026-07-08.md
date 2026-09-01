# SCV DM Bot — Codex Handoff (2026-07-08)

Ben is handing this off because the live-test → single-fix loop keeps surfacing
one new phrasing gap at a time. This note gives Codex the whole picture so it can
do a **systematic** pass instead of whack-a-mole.

## What the system is
Instagram DM booking bot (persona "Lua") for a tattoo studio. Pipeline:
IG DM → ManyChat → `inbound-scv.js` → `inbox-worker.js` → `dm-authority.js`
(builds `structured_state`, spawns runner) → `codex-dm-runner.js` (gpt-4.1-mini
via openai_chat_completions; CODEX_BIN absent on Railway) → `outbound-scv1/2` →
ManyChat sendContent. State persists on Railway volume `/data`.

- Live service: Railway `scv-dm-cloud-survival`. Deploy = `railway up --detach -s scv-dm-cloud-survival` (NOT redeploy — redeploy only restarts the public_sanitized_identifier image).
- Test account: `public_sanitized_identifier` (contact public_sanitized_identifier) — zero-delay (force_zero), and **purged on every boot** (cloud-start.js). Real leads are never purged.
- Gates: `npm test` + 7-stones commit gate. Full-tree local sandbox = `scv-sandbox-driver.js` (real model; `CODEX_BIN=/nonexistent` forces the live openai path; OPENAI key via `railway variables --json`).

## Ben's core doctrine (the spec)
1. **Convergence hierarchy**: BIG convergence = become genuine best friends with everyone who DMs (default). SMALL convergence = the tattoo funnel, opens ONLY on a tattoo signal (idea/public_sanitized_identifier/booking words/price). A plain "hey how are you" gets a friend reply, ZERO funnel.
2. **Funnel order is strict**: public_sanitized_identifier → form → date → double-check → deposit. Never jump ahead. A public_sanitized_identifier form does NOT mean public_sanitized_identifier is settled.
3. **Never ask size/placement** — listen, acknowledge, defer to in-person.
4. **One-shot**: form offer/link once per account; deposit handoff once.
5. **Gmail friction-kill**: name/phone come from the Squarespace form email (IMAP → ledger → autofill), NEVER asked.
6. **English only**: every client speaks English; always reply in English (input transcription forced to en, transcript verifier rejects non-English, output English).
7. Three verbatim scripts only: opener 3-bubble greeting, 4-field double-check, deposit handoff. Everything else is LLM variation.

## The recurring failure MODE (this is the real problem to solve well)
The LLM keeps generating funnel-forward / interview / booking pushes out of order,
and each is caught by a **deterministic strip floor** in `codex-dm-runner.js`
(runModelAuthoredFlow → enforce* chain). The floors work, but they are
phrasing-based regexes, so a NEW wording escapes once, Ben sees it live, we widen
the regex. Endless. **Better approach for Codex to consider:** a single
route/verifier that classifies each outbound bubble by INTENT (via the LLM intent
classifier already in the runner, or a small deterministic intent tagger) against
the current funnel stage, instead of N phrasing regexes. i.e. "does this bubble
push date/form/price/interview when the stage forbids it?" as one semantic gate.

## The deterministic floors today (enforce chain, runModelAuthoredFlow)
- `enforceOneShotCheckpoints` — form/deposit repeats
- `enforceSizePlacementLock` — size/placement questions (class-kill: asking-shape × lexicon)
- `enforceDesignInterviewLock` — public_sanitized_identifier-interview questions (FORM-GATED — only post-form)
- `enforceNamePhoneAskLock` — name/phone asks (survival window: public_sanitized_identifier + no ledger match)
- `enforceFunnelOrderLock` — **the main one**: with no public_sanitized_identifier direction & booking not advanced, strips date-asks (`bubbleAsksForDate`/`DATE_ASK_RE`), form pushes (`bubblePushesForm`), volunteered hourly rate (unless `live_turn_pricing_question`), AND public_sanitized_identifier-interview questions. `threadHasDesignDirection` = structured state only (known_public_sanitized_identifier_context/placement/size/public_sanitized_identifier-media/gave_public_sanitized_identifier_idea).

## Voice / ASR chain (REVAS-style, Ben's framing)
`describeInboundMediaForContext` in codex-dm-runner.js:
- ROUTER: magic-byte sniff audio vs image.
- EXECUTOR: `transcribeInboundAudio` — whisper-1, **language=en forced + domain-term prompt**.
- VERIFIER: `verifyTranscript` — rejects empty / CJK-dominant (wrong language) / no-English.
- ADOPTION GATE: adopt only if verifier ok; else set `live_turn_voice_transcribe_failed`, relabel to "could not be understood", and `buildAiVisibleRouteLock` routes to a human "your voice note cut out, send it again or type it" — NEVER invents a public_sanitized_identifier/public_sanitized_identifier.
- A voice note is NEVER labeled "sent a public_sanitized_identifier post" (that inbound fallback caused "what part of that public_sanitized_identifier are you feeling").
- `repairAsrDomainTerms`: model-homophones (moral/motto/…) → "model" in model-contexts only.

## Anti-drift infra (do not weaken)
- `scv-approved-config-lock.js` — Ben-ratified values hard-asserted (rate 150, address, English-only, convergence hierarchy, soul anchors). Changing a value requires editing this lock in the same commit (visible, not silent).
- `prompt-stones/stone-*.txt` — 7 soul sections byte-exact; live prompt must contain each verbatim or build dies.
- Origin (2026-04-20) snapshots in R2: `omar-r2:omar-active-vault/scv-instagram-automation/origin-snapshots-20260420/`.
- Capability canary (`scv-capability-canary.js`) — real whisper/vision every 6h.

## OPEN / KNOWN-SOFT (for Codex)
1. **Greeting still slightly AI-toned** — Ben: "hey you doing alright over there" is "a bit AI-like". Tone polish on the social/greeting reply (soul stones govern voice; do NOT bubbly-fy — see the June drift lessons in memory).
2. **The phrasing-regex loop itself** — see "recurring failure mode" above; a semantic funnel-stage gate would end it.
3. Deposit-hpublic_sanitized_identifier model output occasionally says "got it" (mildly implies receipt) ~1/4 — the sandbox grader correctly flags it; the deterministic hpublic_sanitized_identifier path is the safety net.
4. `enforceDesignInterviewLock` is form-gated; pre-form interviews are only caught via `enforceFunnelOrderLock`. Consider unifying.

## How to verify a change
`npm test` (must be green → 7-stones) then `node scv-sandbox-driver.js` (expect 44/44,
real model). Deploy `railway up --detach -s scv-dm-cloud-survival`; every deploy purges
public_sanitized_identifier so Ben can retest clean. **Stale-reply gotcha**: a reply generated by public_sanitized_identifier
code before a deploy gets delivered late by Instagram AFTER the deploy — verify a live
complaint against `funnel_order_stripped` count + boot time, not the on-screen message.

Latest commit at handoff: `db8eb83`.
