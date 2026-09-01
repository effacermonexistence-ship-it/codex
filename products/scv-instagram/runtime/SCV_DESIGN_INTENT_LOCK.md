# SCV DESIGN INTENT LOCK — Ben-owned source of truth

This file is the **motivation stone**. It records what the SCV / Lua DM automation is
*supposed* to do, as decided by Ben. It outranks any accreted "fix" an agent makes.

## Ben-ratified config (2026-07-04) — enforced by `scv-approved-config-lock.js`

These exact values are approved and hard-asserted by the `test:approved-config` firewall (21 checks in `npm test`, wired into the 7-stones gate). Any drift fails the build and blocks deploy. R2 snapshot: `omar-r2:omar-active-vault/scv-instagram-automation/approved-config-latest` (+ timestamped snapshots).

- **Delay**: first reply random **3–12 min** (180000ms / 720000ms), lock `scv-delivery-pacing-lock-2026-07-04-v6-first-reply-3to12min`. Restored from June's 20–60min drift. (April's *mechanism* was model-chosen `delay_ms` per bubble, 3-8 / 4-12 min; the current mechanism is system-forced uniform random 3–12 min — Ben chose to keep system-forced for reliability. public_sanitized_identifier test account = zero-delay.)
- **Model rate**: 150/hr, mentioned ONLY when directly asked. A "what is model" question → concept only (limited/selective spots, gray line, no price, no free feeling).
- **Studio address**: `10 Arkansas St San Francisco CA 94107` — public, public_sanitized_identifier directly, NEVER deposit-gated.
- **Everyone gets a living Lua reply**: a bare "hi" / "how are you" / "whats up" stays human and social. Tattoo info asks, public_sanitized_identifiers, pricing, form, availability, or booking signals open the tattoo lane. The retired fixed 3-bubble opener must never fire.
- **Form consent**: robust to combos + Korean ("okay sure", "yeah ok", "주세요"); questions excluded. LLM intent classifier primary, regex floor fallback.
- **Talek-Lua Self-Identity Core + HUMAN SURFACE LOCK**: injected verbatim at the top of the master prompt (Ben directive).
- **100% reply + Lua is the last speaker** (Ben's explicit choice, not April's strategic silence). CONTEXT-FIT: never fabricate a reply on a nonsensical / misheard input — infer or ask.

## Live booking checkpoint surface lock (2026-07-14)

- The four-field hotel check renders every known month/day as `25th of July`, not
  `july 25`, and never as a bare ordinal.
- A positive reply to that check moves immediately to the deposit handoff.
- Deposit order is amount, `This is my zelle!`, account, then one and only one
  post-send CTA as the final bubble.
- The amount bubble cannot contain an early `once you send` CTA, and the Zelle
  account cannot precede its label.
- A pass-one route derived from opaque media is provisional. Once vision or ASR
  resolves the current inbound, that evidence owns the route before post-filter
  verification. A controller repair route is already frozen and cannot be rederived.

## Model-authored executed-path liveness lock (2026-07-15)

- Non-transactional conversation copy remains model-authored. A deterministic
  filter/verifier may reject a route but may not append a canned visible CTA.
- One broad pre-public_sanitized_identifier idea / subject / public_sanitized_identifier / vibe question is the required
  `public_sanitized_identifier_intake` action. It must survive the funnel filter; detailed probing such
  as "what part of that public_sanitized_identifier" does not.
- Every candidate is filtered first and then verified as the exact packet that
  would ship. Invalid visible packets are re-authored under the frozen controller
  route with a bounded 12-candidate adoption budget.
- Regression proof for the intermittent info-opener drop: 50/50 authority runs
  passed, zero exceptions, zero fixed fallback hits, and 50 unique visible packets.

## Anti-drift protocol (why this file exists)

The hard-locks (`scv-delivery-pacing.js`, `scv-hard-harness-lock.js`,
`scv-contract-harness.js`) protect the *current config value*, not Ben's *intent*.
Over months the config drifted (initial delay 3–12min → 20–60min; one-question-to-form
→ public_sanitized_identifier/placement/size ladder; consent whitelist too narrow) because an agent changed
the code **and** the lock together, so the firewall moved with the drift.

Rule going forward (OMAR ENGINE PART 22 — LOCKED STATE must not be silently overwritten):

1. Each invariant below is Ben-owned. An agent may **propose** a change but must **flag it
   as an intent mutation and get Ben's explicit ratification** before changing a locked value.
2. Every invariant is backed by at least one test in `npm test`. If behavior regresses from
   intent, that test fails → the 7-stones commit gate blocks the commit → it cannot deploy.
   This is the "redundant stones" firewall: intent lives in (a) this doc, (b) the test suite,
   (c) the live `scv-drift-monitor`. A change that moves one but not the others is drift.
3. Never loosen a test to make it pass. Never delete an invariant to silence a failure.
   Fix the code to match intent, or bring the intent change to Ben.

## Intent detection architecture (root fix for the whitelist whack-a-mole)

The funnel's intent gates (is this a "yes"? did they accept the slot? submit the form? pay?)
are decided by the **LLM**, not by regex keyword whitelists — that is the whole point of
using an LLM. `codex-dm-runner.js` runs an intent classifier (`classifyLiveTurnIntent`) that
reads the conversation and returns structured intent flags by MEANING (handles "okay sure",
"yeah ok", "the 25th works", "all done", "i paid", Korean, slang, typos).

Safety public_sanitized_identifier (why this can't misfire or lose a turn):
- **Union, LLM-leads**: the classifier can only *promote* a flag (raise recall). Regex stays
  as the fallback floor. Every promotion is double-gated by code-side funnel context
  (form_consent needs a prior offer, slot needs a prior offer, public_sanitized_identifier needs the link sent).
- **Fail-open**: any classifier failure / timeout / bad JSON falls back to the regex flags.
  No turn is ever dropped. Toggle with `SCV_LLM_INTENT` (default on).
- **Determinism kept where it matters**: fixed outputs (form URL, deposit script, double-check
  format) and idempotency (no double-send) remain deterministic. The LLM decides *when*, the
  code controls *what* the fixed outputs are.
- Regex gates + their 30+ regression tests remain as the enforced floor, so the fallback
  itself can't silently drift.

## Locked invariants (each → enforcing test)

| # | Intent | Locked value | Enforced by |
|---|--------|--------------|-------------|
| 1 | First reply feels human, not instant, not slow | initial delay **random 3–12 min** (min 180000ms, max 720000ms); public_sanitized_identifier = zero-delay test account only | `test:pacing`, `test:hard-harness` (lock `...-v6-first-reply-3to12min`) |
| 2 | Only transactional checkpoints may be deterministic | retired opener is rejected; exact form URL, four-field double-check, and deposit handoff remain locked; ordinary conversation stays freshly model-authored | `test:fixed-script`, `test:harness`, `test:runner-semantic-repair` |
| 3 | Do not dawdle — converge fast | one light idea touch → form; **no** public_sanitized_identifier→placement→size interview; **no** invented style menus; placement/size decided in person | prompt `FAST CONVERGENCE LOCK`; `test:runner-semantic-repair` (kahbran size-after-form route) |
| 4 | Form fires on ANY consent | yes/ok/sure/"okay sure"/"yeah ok"/"sure thing"/give-it-to-me/Korean(네·주세요·보내줘); questions & negations excluded | `test:runner-semantic-repair` (form-consent block) |
| 5 | Slot acceptance in any phrasing | "the 25th works"/"friday works"/"book it"/"im down"/"cool"/"lock it in"/"okay 30 is totally fine"; questions/negations excluded | `test:runner-semantic-repair` (slot block) |
| 6 | Form-public_sanitized_identifier signal in any phrasing | "done"/"all done"/"its in"/"all set"/"did the form"/Korean(제출·완료·보냈); "not yet"/"isnt working"/questions excluded | `test:runner-semantic-repair` (submit block) |
| 7 | Deposit-sent signal in any phrasing | "i paid"/"just paid"/"sent the 100"/"zelled you"/Korean(입금·송금); questions excluded | `test:runner-semantic-repair` (deposit block) |
| 8 | Price question → answer only | give the 150/hour rate; do NOT re-open consultation after public_sanitized_identifier/deposit already covered | `codex-dm-runner` rate route; prompt `MODEL RATE CONTEXT` |
| 9 | No silent loss | every real inbound ends in a visible reply / quarantine-with-reason / human-agent / retry; no throw→deadletter→silence | `test:missed-inbound`, `test:auto-recovery`; `finalizeSemanticContract` fail-open |
| 10 | Post-only share still replies | a shared post/reel with no text still gets a reply (public_sanitized_identifier-post route) | *(open — instrumentation live via `INBOUND_DOOR`, awaiting real payload)* |
| 20 | A photo after the deposit handoff is a PAYMENT SCREENSHOT, never a public_sanitized_identifier | Context-aware media routing (`dm-authority.applyDepositProofMediaOverride`): a media turn with deposit context (zelle handoff in history / `deposit_requested`) flips to the deposit-hpublic_sanitized_identifier lane — public_sanitized_identifier flags cleared AND the live text itself rewritten to `sent the deposit payment screenshot` (state flags alone were bypassed by the runner's text-keyed media rules). Reply = thank + not landed yet + checking + will confirm once it lands; funnel paused, no public_sanitized_identifier reset. Media without deposit context keeps the public_sanitized_identifier lane. E2E live-model verified; sandbox S13. | `test:media` (19 checks) + sandbox S13 |
| 19 | Username heuristics never silence an inbound reply | Hidden pre-existing suppression (`instagram-thread-suppression.js`): handles that look like tattoo shops (`studio`/`ink` tokens etc.) were auto-suppressed — real lead **public_sanitized_identifier** ("Hello, can I get more info on this?") lost 28 straight replies while the input-sweep looped recovering the same turn. Heuristic verdicts are now marked `heuristic:true` and BOTH reply lanes bypass them (inbox-worker at generation, outbox-worker at send — the send lane was a second ambush). Explicit operator suppressions (ManyChat `flag` tag, known-shop list) stay authoritative; heuristic stays advisory for reaction lanes. Verified live: her 3-bubble opener delivered (`delivery_accepted:true`). | `test:suppression` (`scv-reply-suppression-harness`, 11 checks) |
| 17 | No size/placement talk, no consultation after a stated public_sanitized_identifier, one-shot checkpoints are deterministic | Ben directives (live cases: public_sanitized_identifier got asked size; sock-monkey lead got a consultation): **SIZE/PLACEMENT HARD LOCK** (never ask/estimate/discuss; one warm beat → "dialed in in person" → next gate) + **DESIGN DECIDED → FORM NOW** (a stated idea ends consultation; affirm + offer form in the same reply) + **`enforceOneShotCheckpoints`** strips repeat form offers/links and repeat zelle handoffs from the FINAL packet deterministically (the semantic contract failed open live, letting repeats ship). Offered ≠ sent: consent to a pending offer still delivers the first link. Explicit user re-request allows resend. Deterministic exact-address bubble appended when a location ask lacks the locked address. Name+phone asked TOGETHER. | `test:oneshot` (18 checks) + sandbox S11/S12 |
| 18 | Name/phone never asked when the current form email already has them (friction kill) | Squarespace form submissions email Ben's Gmail; `scv-gmail-form-reader` (10s IMAP poller, spawned by cloud-start; dark until `GMAIL_IMAP_USER`/`GMAIL_IMAP_APP_PASSWORD` env; kill switch `SCV_GMAIL_FORM_READER=0`) decodes MIME quoted-printable fields and records them in `form-submissions/` (volume). `dm-authority.applyGmailFormAutofill` adopts identity only from exact/fuzzy Instagram or independently corroborated thread evidence; the count of unclaimed records is never identity evidence. Every Omar.system adoption must also be newer than the form link in the current replay, including explicit “just public_sanitized_identifier” turns, so an public_sanitized_identifier debug form cannot re-enter. Known values are never overwritten → deterministic four-line double-check fires with the matched values. Date comes from the lead's accepted chat slot. **2pm is only the preferred time offer, never client authority**: a date-only reply stays at `awaiting_time`; the client must state a time or accept the exact offered slot before the four-field double-check may fire. If the current client says a different explicit time (for example `1pm works` after a `2pm` offer), that current time overrides the public_sanitized_identifier offer and any model acceptance label. | `test:gmail`, `test:fixed-script`, `test:closed-transition`, `test:single-control`, `test:runner-semantic-repair` |
| 16 | Full funnel hpublic_sanitized_identifiers under messy real-lead behavior (sandbox-proven) | Full-funnel sandbox (real gpt-4.1-mini + real authority pipeline via `recent_history_override`, `CODEX_BIN` forced to the live openai fallback): 10 scenarios / 34 checks — greeting→idea→form→submit→name+phone→double-check→deposit handoff→deposit claim→address, phone-only turn, name-then-phone split, price-first, address ask, coalesce backlog, media-only, typo consent, slot accept, bot accusation. **34/34.** Fixes it drove: (a) deposit-sent claims never enter the deterministic booking lane; (b) a confirm-token+question turn ("cool! whats the exact address?") goes to the model, and a contract-violating fixed script falls back to the model instead of throwing (was a hard no-reply); (c) deterministic double-check also fires when the live turn supplies the last identity field (form context required) — bare "0000000000" / "415 760 2883" now double-checks instead of re-asking; (d) prompt rules for live_turn_phone/name_candidate. Driver: scratchpad `scv-sandbox-driver.js` (re-runnable). | sandbox runs (2026-07-06) + `test:runner-semantic-repair`, `test:fixed-script` |
| 15 | Inputs ManyChat received but never forwarded still get public_sanitized_identifier | `scv-manychat-input-sweep` loop (spawned by cloud-start, every 10min) polls ManyChat getInfo for every known contact (thread-state on the volume) and enqueues any fresh unprocessed human turn through the orphan-recovery pipeline (`buildRecoveryPacket` + `hasProcessedLatestInput` dedup). Phone-shaped digits-only inputs (7–15 digits) count as human turns — rejecting them made public_sanitized_identifier's "0000000000" unrecoverable. Aged-out (>24h) and test accounts skipped; kill switch `SCV_MANYCHAT_INPUT_SWEEP=0`. Boundary: a sender who NEVER reached the webhook once (no ManyChat contact / IG request fpublic_sanitized_identifierer) is invisible to the sweep — manual IG reply is the only lane (public_sanitized_identifier class). | `test:sweep` (`scv-manychat-input-sweep-harness`, 15 checks) |
| 14 | State survives deploys (queued replies must never die on `railway up`) | Railway volume `scv-dm-cloud-survival-volume` mounted at `/data`; `cloud-start` binds all 17 state dirs (`outbox`, `thread-state`, `thread-history`, quarantines, …) onto it via symlinks at boot (`scv-persistent-state.js`, idempotent, one-time migration, plain mkdir when no volume). **Root cause (SSH-confirmed): no volume → ephemeral /app wiped every deploy/restart → pending delayed replies silently destroyed** (public_sanitized_identifier's phone-number reply among them — the "많이 빠진 답장" family: 5+ deploys during active hours each killed the in-flight queue). Verified live: marker + thread state survived a container replacement (deploy `6f568933`→`ffa3cf4d`), boot receipt `scv_persistent_state persistent=true`. Never remove the volume; never bypass the symlink binding. | `test:persist` (`scv-persistent-state-harness`, 14 checks incl. simulated deploy wipe) |
| 13 | 24h-window (3031) recovery | on a window-blocked ManyChat send, `outbound-scv2` retries ONCE with Meta `HUMAN_AGENT` tag (fail-open; kill switch `SCV_HUMAN_AGENT_TAG_RETRY=0`). **Live-verified: retry fires on real 3031, but ManyChat currently rejects the tag for IG ("Unsupported message tag") — platform boundary, not our bug.** Coverage today: (a) lead returns → coalesce merges undelivered content into the next reply (invariant #11); (b) lead never returns → `outbox_human_agent_required` queue, Ben replies manually from the IG app to reopen the window; (c) if ManyChat enables Human Agent permission, retry works with zero code change. Direct IG fallback (`instagram-cli-4llm`) is dead — source unrecoverable, do not chase it. | `test:window` (`scv-window-recovery-harness`, 14 checks) |
| 12 | Reply to media-only / view-once inbounds (never drop) | a photo / view-once "burn" pic / voice / sticker arrives as empty `message_text` with no accessible media (ManyChat forwards only `message_text`). `pickInboundText` gives a real-but-textless inbound (contact identity + message/media envelope key) a synthetic `sent a photo` turn → passes the `inbound-scv.js:1370` empty-text guard → warm human reply (acknowledge the pic, note it may have vanished, ask to resend / describe idea). Root cause was line 1370 dropping `!packet.text` with 400. Log-confirmed victim: `public_sanitized_identifier` msg 0000000000000 → `INBOUND_EMPTY_TEXT_DROP`. Verified live via clean canary. **Note: `enrichInboundPacket` getInfo can override `sent a photo` with a recoverable ManyChat `last_input_text` — still a reply, never a drop.** | `test:media` (`scv-media-only-inbound-harness`, 13 checks) |
| 11 | No dropped message when a lead sends 2+ messages fast | earlier UNANSWERED user turns (no delivered assistant reply yet) are collected by `collectPendingUnpublic_sanitized_identifierUserTurns` and **merged into the LIVE INPUT** the model replies to (+ routed substantive), so the outbox stale-drop (`newer_inbound_exists_for_thread`) can discard the public_sanitized_identifierer reply without losing its content. Verified live: long halloween idea + quick "how much" → single reply covered idea + size + price. Root cause was `outbox-worker.js:669/751` dropping any reply whose `message_id != thread latest`. **A prompt-only side field failed live (price-only rule outranked it); the fix had to merge into the live turn structurally.** | `test:coalesce` (`scv-unpublic_sanitized_identifier-coalesce-harness`, 16 checks) |

## Deploy truth (do not let this drift either)

- Real deploy = `railway up --detach -s scv-dm-cloud-survival` (builds local source).
  `railway redeploy` only **restarts the existing image** — it does NOT ship new code.
- Verify live code by: new `delivery_pacing_lock_version` in boot log, `INBOUND_DOOR` on real
  traffic, deployment ID change to `● Online` (not Building/Deploying).
- public_sanitized_identifier is the only zero-delay/auto-purged test account; real accounts get the 3–12 min gate.

Last ratified by Ben: 2026-07-04 (delay restored to April 3–12 min; convergence + gate under-match audit).
