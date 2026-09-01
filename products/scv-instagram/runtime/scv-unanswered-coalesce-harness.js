#!/usr/bin/env node
// ============================================================
// SCV UNANSWERED-COALESCE HARNESS — "no dropped message" verification.
//
// Root cause it guards: outbox-worker drops (quarantines) a reply whose message_id
// is not the thread's latest (newer_inbound_exists_for_thread). If a lead sends A
// (a long idea) then B (a short follow-up) before A's delayed reply is delivered,
// A's reply is discarded and B's reply only addresses B -> A's content is lost.
//
// Fix under test: dm-authority.collectPendingUnpublic_sanitized_identifierUserTurns() surfaces every
// earlier user turn that has NOT received a DELIVERED assistant reply, so the live
// reply must cover them all. This harness asserts that set is computed with ZERO
// dropped messages across the scenarios that produced the live bug.
// ============================================================
const path = require('path')
const {
  collectPendingUnpublic_sanitized_identifierUserTurns,
  buildCoalescedRunnerMessage
} = require(path.join(__dirname, 'dm-authority.js'))

function assert(cond, label, detail = '') {
  if (!cond) {
    const err = new Error(`${label}${detail ? ` :: ${detail}` : ''}`)
    err.label = label
    throw err
  }
}

const u = (text, message_id = String(Math.random())) => ({ role: 'user', message_id, text })
const a = (text = 'reply') => ({ role: 'assistant', text })
const aAttempt = (text = 'reply') => ({ role: 'assistant_attempted', text })
const aHuman = (text = 'reply') => ({ role: 'assistant_human_agent_required', text })

function runScvUnpublic_sanitized_identifierCoalesceHarness() {
  let checked = 0
  const eq = (got, want, label) => {
    assert(JSON.stringify(got) === JSON.stringify(want), label, `got=${JSON.stringify(got)} want=${JSON.stringify(want)}`)
    checked++
  }
  const ok = (cond, label, detail = '') => { assert(cond, label, detail); checked++ }

  // recentHistory ALWAYS excludes the current live inbound (loadRecentThreadHistory filters it),
  // so these arrays are "everything before the live turn B".

  // 1. SIERRA CASE: opener delivered, then a long unpublic_sanitized_identifier idea (A). Live turn = pricing (B, excluded).
  //    Backlog must carry the long idea so B's reply covers it.
  eq(
    collectPendingUnpublic_sanitized_identifierUserTurns([a('Hiii!!! thank you so much for reaching out to me!'), u('big halloween haunted house piece with skulls in the tree roots, outer thigh, how big?')]),
    ['big halloween haunted house piece with skulls in the tree roots, outer thigh, how big?'],
    'sierra_long_idea_stays_in_backlog'
  )

  // 2. Already public_sanitized_identifier: user A got a delivered assistant reply -> backlog empty.
  eq(collectPendingUnpublic_sanitized_identifierUserTurns([u('A'), a('public_sanitized_identifier A')]), [], 'public_sanitized_identifier_message_not_in_backlog')

  // 3. Two consecutive unpublic_sanitized_identifier user messages -> both in backlog, public_sanitized_identifierest first.
  eq(collectPendingUnpublic_sanitized_identifierUserTurns([u('A first'), u('B second')]), ['A first', 'B second'], 'two_unpublic_sanitized_identifier_both_kept_in_order')

  // 4. Mixed: public_sanitized_identifier A, then two unpublic_sanitized_identifier B,C -> only B,C.
  eq(collectPendingUnpublic_sanitized_identifierUserTurns([u('A'), a('public_sanitized_identifier A'), u('B'), u('C')]), ['B', 'C'], 'only_after_last_delivered_assistant')

  // 5. ZERO-DROP INVARIANT: K consecutive user messages with no delivered reply ->
  //    backlog has exactly all of them; nothing is dropped.
  const many = [u('m1'), u('m2'), u('m3'), u('m4'), u('m5')]
  eq(collectPendingUnpublic_sanitized_identifierUserTurns(many), ['m1', 'm2', 'm3', 'm4', 'm5'], 'zero_drop_all_consecutive_user_turns_kept')

  // 6. assistant_attempted (delivery failed, user never saw it) does NOT close the backlog.
  eq(collectPendingUnpublic_sanitized_identifierUserTurns([u('A'), aAttempt('failed reply')]), ['A'], 'attempted_reply_does_not_answer')

  // 7. assistant_human_agent_required (never delivered) does NOT close the backlog either.
  eq(collectPendingUnpublic_sanitized_identifierUserTurns([u('A'), aHuman('stuck')]), ['A'], 'human_agent_required_does_not_answer')

  // 8. A delivered assistant AFTER attempted ones still closes correctly (last delivered wins).
  eq(collectPendingUnpublic_sanitized_identifierUserTurns([u('A'), aAttempt(), a('finally delivered'), u('B')]), ['B'], 'last_delivered_assistant_is_boundary')

  // 9. Empty / assistant-only / whitespace robustness.
  eq(collectPendingUnpublic_sanitized_identifierUserTurns([]), [], 'empty_history_empty_backlog')
  eq(collectPendingUnpublic_sanitized_identifierUserTurns([a('hi')]), [], 'assistant_only_empty_backlog')
  eq(collectPendingUnpublic_sanitized_identifierUserTurns([u('   '), u('real')]), ['real'], 'blank_user_text_skipped')
  eq(collectPendingUnpublic_sanitized_identifierUserTurns(null), [], 'null_history_safe')

  // 10. Single normal turn (no earlier unpublic_sanitized_identifier): backlog empty -> no false coalesce, no dup.
  eq(collectPendingUnpublic_sanitized_identifierUserTurns([a('prev reply')]), [], 'normal_single_turn_no_backlog')

  // 11. Field-shape contract used by dm-authority injection (live_turn_has_unpublic_sanitized_identifier_backlog).
  const backlog = collectPendingUnpublic_sanitized_identifierUserTurns([u('idea one'), u('idea two')])
  ok(Array.isArray(backlog) && backlog.length === 2, 'backlog_is_array')
  ok((backlog.length > 0) === true, 'has_backlog_flag_true_when_pending')
  ok((collectPendingUnpublic_sanitized_identifierUserTurns([a()]).length > 0) === false, 'has_backlog_flag_false_when_none')

  // 12. Model context may include the unpublic_sanitized_identifier backlog, but deterministic live
  // gates receive the current atomic turn through a separate immutable field.
  const split = buildCoalescedRunnerMessage('Just public_sanitized_identifier', [
    'sent a voice note saying: I just sent you the form.',
    'sent a voice note saying: I just sent you the form I just public_sanitized_identifier.'
  ])
  ok(split.live_message === 'Just public_sanitized_identifier', 'atomic_live_message_is_not_contaminated_by_backlog', JSON.stringify(split))
  ok(split.message.includes('earlier message 1') && split.message.includes('their latest message just now'), 'model_message_keeps_unpublic_sanitized_identifier_backlog', JSON.stringify(split))
  ok(split.message.endsWith('Just public_sanitized_identifier'), 'model_message_keeps_latest_turn_last', JSON.stringify(split))

  return { ok: true, checked }
}

if (require.main === module) {
  try {
    const r = runScvUnpublic_sanitized_identifierCoalesceHarness()
    console.log(JSON.stringify(r, null, 2))
  } catch (err) {
    console.error(JSON.stringify({ ok: false, error: String(err && err.message ? err.message : err), label: err.label || '' }, null, 2))
    process.exit(1)
  }
}

module.exports = { runScvUnpublic_sanitized_identifierCoalesceHarness }
