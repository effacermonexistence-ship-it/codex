#!/usr/bin/env node

const path = require('path')
const {
  LOCKED_DEPOSIT_HANDOFF_BUBBLES
} = require(path.join(__dirname, 'scv-contract-harness.js'))
const {
  decorateDeterministicPacket
} = require(path.join(__dirname, 'scv-structured-output-contract.js'))

const DETERMINISTIC_RECOVERY_VERSION =
  'scv-explicit-verbatim-checkpoints-and-send-form-liveness-2026-08-25-v12-context-only-clarification'

const SEND_FORM_RECOVERY_MIN_MODEL_CANDIDATES = 3
const PREFERRED_FORM_LINK = 'https://www.effacermonexistence.com/apply'

const SAFE_CLARIFICATION_TEXT = Object.freeze({
  generic: 'sorry i didnt catch that clearly can you say that again',
  voice: 'sorry i couldnt hear that clearly can you send it again or type it here'
})
const ROUTE_AWARE_VISIBLE_RECOVERY_VERSION =
  'scv-route-aware-visible-recovery-2026-08-29-v4-booking-continuity-and-discounted-model-rate'

function bubble(text) {
  return { text: String(text || '').trim(), delay_ms: 0 }
}

function compact(value) {
  return String(value || '').replace(/\s+/g, ' ').trim()
}

function fieldValue(plan, state, ...names) {
  for (const name of names) {
    const fromPlan = compact(plan?.fields?.[name])
    if (fromPlan) return fromPlan
    const fromState = compact(state?.[name])
    if (fromState) return fromState
  }
  return ''
}

function doubleCheckPacket(input, plan) {
  const state = input.structured_state || {}
  const name = fieldValue(plan, state, 'name', 'known_name_used_on_form')
  const phone = fieldValue(plan, state, 'phone', 'known_phone_used_on_form')
  const date = fieldValue(plan, state, 'date', 'proposed_date', 'known_requested_date', 'accepted_offered_date')
  const time = fieldValue(plan, state, 'time', 'known_requested_time', 'accepted_offered_time')
  if (!name || !phone || !date || !time) {
    throw new Error('deterministic_exact_double_check_fields_missing')
  }
  return decorateDeterministicPacket(input, {
    bubbles: [bubble(
      `Name : ${name}\nPhone Number : ${phone}\nAppointment date : ${date}\nTime : ${time}\n\ncan you double check this just to make sure`
    )]
  }, {
    plan,
    nextAction: plan.action,
    acknowledgedFields: ['name', 'phone_number', 'appointment_date', 'appointment_time'],
    questionedFields: ['double_check_confirmation']
  })
}

function sendFormRecoveryAsksPrice(input, plan) {
  const obligations = new Set(
    Array.isArray(plan?.obligations)
      ? plan.obligations.map((value) => String(value || '').trim()).filter(Boolean)
      : []
  )
  if (obligations.has('answer_model_rate')) return true
  if (input?.structured_state?.live_turn_pricing_question === true) return true
  const live = compact(input.live_message || input.message || input.structured_state?.live_turn_text)
  return /\b(?:how much|price|pricing|cost|rate|free)\b/i.test(live)
}

function sendFormCheckpointPacket(input, plan, recoveryAuthority) {
  const reason = String(plan?.reason || '')
  const candidateCount = Number(recoveryAuthority?.model_candidate_count || 0)
  const linkVisibleInHistory = (Array.isArray(input?.recent_history) ? input.recent_history : [])
    .some((event) => {
      const role = String(event?.role || event?.sender || event?.actor || '').trim().toLowerCase()
      const assistant = ['assistant', 'lua', 'artist', 'bot', 'business'].includes(role)
      return assistant && String(event?.text || event?.message || event?.content || '').includes(PREFERRED_FORM_LINK)
    })
  const firstDelivery =
    input?.structured_state?.form_link_sent !== true &&
    !linkVisibleInHistory
  const authorized =
    recoveryAuthority?.model_drafts_exhausted === true &&
    candidateCount >= SEND_FORM_RECOVERY_MIN_MODEL_CANDIDATES &&
    firstDelivery &&
    [
      'explicit_form_request_or_open_offer_consent',
      'accepted_slot_requires_form_link'
    ].includes(reason)

  if (!authorized) {
    throw new Error('deterministic_send_form_recovery_unauthorized')
  }

  const answersPrice = sendFormRecoveryAsksPrice(input, plan)
  const bubbles = []
  if (answersPrice) {
    bubbles.push(bubble("it isnt free this is my discounted model rate at $150 per hour when the finished piece stays in my style"))
  } else {
    bubbles.push(bubble('yeah here you go'))
  }
  bubbles.push(bubble(PREFERRED_FORM_LINK))
  bubbles.push(bubble("send me a couple days that work for you here and i'll check the schedule"))

  return decorateDeterministicPacket(input, {
    authority_transport_flags: {
      atomic_send_form_recovery: true,
      model_drafts_exhausted: true,
      model_candidate_count: candidateCount,
      deterministic_recovery_version: DETERMINISTIC_RECOVERY_VERSION,
      reason: 'authorized_send_form_checkpoint_after_model_exhaustion'
    },
    bubbles
  }, {
    plan,
    nextAction: plan.action,
    acknowledgedFields: answersPrice
      ? ['form_offer', 'form_link', 'price']
      : ['form_offer', 'form_link'],
    questionedFields: ['appointment_date']
  })
}

function buildSafeClarificationRecoveryPacket(input = {}) {
  const state = input.structured_state || {}
  const voice =
    state.live_turn_voice_transcribe_failed === true ||
    state.live_turn_voice_context_unresolved === true ||
    /voice note that could not be understood/i.test(
      String(input.live_message || input.message || state.live_turn_text || '')
    )
  const plan = {
    action: 'resolve_context',
    reason: 'unintelligible',
    obligations: [],
    fields: {}
  }
  return decorateDeterministicPacket(input, {
    authority_transport_flags: {
      safe_nontransactional_recovery: true,
      reason: voice
        ? 'voice_media_unavailable_or_unintelligible'
        : 'model_adoption_exhausted'
    },
    bubbles: [bubble(voice ? SAFE_CLARIFICATION_TEXT.voice : SAFE_CLARIFICATION_TEXT.generic)]
  }, {
    plan,
    nextAction: plan.action,
    acknowledgedFields: [],
    questionedFields: ['missing_context']
  })
}

function routeAwareRecoveryQuestionedFields(action, plan = {}, state = {}) {
  if (action === 'offer_form' || action === 'clarify_form_permission') return ['form_link']
  if (action === 'post_form_availability') return ['appointment_date']
  if (action === 'post_form_time') return ['appointment_time']
  if (action === 'post_form_identity' || action === 'accepted_slot_progress') {
    const date = fieldValue(plan, state, 'date', 'known_requested_date', 'accepted_offered_date')
    const time = fieldValue(plan, state, 'time', 'known_requested_time', 'accepted_offered_time')
    if (!date) return ['appointment_date']
    if (!time) return ['appointment_time']
    return ['name', 'phone_number']
  }
  if (['send_form', 'double_check', 'await_double_check_confirmation', 'deposit_handoff', 'deposit_hpublic_sanitized_identifier', 'deposit_pending_continue'].includes(action)) {
    return []
  }
  return ['missing_context']
}

function routeAwareRecoveryText(input = {}, originalPlan = {}) {
  const action = String(originalPlan?.action || 'general_continue')
  const state = input.structured_state || {}
  const asksPrice = sendFormRecoveryAsksPrice(input, originalPlan)
  const date = fieldValue(
    originalPlan,
    state,
    'date',
    'proposed_date',
    'known_requested_date',
    'accepted_offered_date',
    'live_turn_date_phrase'
  )

  if (action === 'send_form') {
    return asksPrice
      ? "yes this is my discounted model rate at $150 per hour when the finished piece stays in my style i have your yes on the form too while i get the link"
      : "got you, you said yes to the form. i haven't marked anything complete while i verify the link"
  }
  if (action === 'offer_form' || action === 'clarify_form_permission') {
    const liveText = String(
      input.live_message || input.message || state.live_turn_text || ''
    )
    const public_sanitized_identifierTurn =
      state.live_turn_is_media_public_sanitized_identifier === true ||
      /^sent a (?:public_sanitized_identifier post|photo|media)\b/i.test(liveText)
    return public_sanitized_identifierTurn
      ? 'yeah we can use that as a starting point and make it custom in my style want me to send the application form?'
      : 'want me to send the application form?'
  }
  if (action === 'post_form_availability') {
    if (String(originalPlan?.reason || '') === 'form_handoff_coarse_day_constraint_requires_grounded_slot') {
      const groundedDate = fieldValue(originalPlan, state, 'last_offered_date')
      const groundedTime = fieldValue(originalPlan, state, 'last_offered_time') || '2pm'
      if (groundedDate) return `i can do ${groundedDate} at ${groundedTime} for the weekend does that work for you?`
    }
    return state.form_public_sanitized_identifier === true || originalPlan?.live_intent?.form_public_sanitized_identifier === true
      ? "got it i have your form what date would you like me to check?"
      : "what date would you like me to check?"
  }
  if (action === 'post_form_time') {
    if (String(originalPlan?.reason || '') === 'public_sanitized_identifier_form_time_before_minimum') {
      const proposed = fieldValue(
        originalPlan,
        state,
        'proposed_time',
        'live_turn_time_candidate'
      )
      return `${proposed || 'that time'} is a little early for me i start at 1pm or later would 1 or 2 work?`
    }
    return date
      ? `yeah ${date} works what time are you thinking?`
      : 'what time are you thinking?'
  }
  if (action === 'post_form_identity' || action === 'accepted_slot_progress') {
    const time = fieldValue(originalPlan, state, 'time', 'known_requested_time', 'accepted_offered_time')
    if (!date) return 'what date do you want me to check?'
    if (!time) return `i have ${date} in mind what time works for you?`
    return `perfect ${date} at ${time} works what name and phone number did you use on the form?`
  }
  if (action === 'double_check' || action === 'deposit_handoff') {
    throw new Error(`route_aware_recovery_transactional_checkpoint_forbidden:${action}`)
  }
  if (action === 'await_double_check_confirmation') {
    return "got you, i have your confirmation, but i haven't sent or marked the deposit step while i verify the handoff"
  }
  if (action === 'deposit_hpublic_sanitized_identifier' || action === 'deposit_pending_continue') {
    return "got it, i have your message and i haven't changed the deposit status. i'm checking the handoff before anything moves"
  }
  if (asksPrice) {
    return 'this is my discounted model rate at $150 per hour when the finished piece stays in my style'
  }
  return "got you, i have your message, but i haven't changed anything while i verify the next step. what would you like me to handle first?"
}

function routeAwareRecoverySurfaceText(input = {}, originalPlan = {}) {
  return routeAwareRecoveryText(input, originalPlan)
    .replace(/,/g, '')
    .replace(/\.(?=\s|$)/g, '')
    .replace(/\s+/g, ' ')
    .trim()
}

function buildRouteAwareVisibleRecoveryPacket(input = {}, originalPlan = {}) {
  const originalAction = String(originalPlan?.action || 'general_continue')
  const recoveryPlan = {
    action: 'resolve_context',
    reason: 'verifier_exhausted_route_recovery',
    obligations: [],
    fields: {},
    recovery: {
      previous_action: originalAction,
      previous_reason: String(originalPlan?.reason || '')
    }
  }
  return decorateDeterministicPacket(input, {
    authority_transport_flags: {
      safe_nontransactional_recovery: true,
      route_aware_visible_recovery: true,
      route_aware_visible_recovery_version: ROUTE_AWARE_VISIBLE_RECOVERY_VERSION,
      original_action: originalAction,
      original_reason: String(originalPlan?.reason || '')
    },
    bubbles: [bubble(routeAwareRecoverySurfaceText(input, originalPlan))]
  }, {
    plan: recoveryPlan,
    nextAction: recoveryPlan.action,
    acknowledgedFields: [],
    questionedFields: routeAwareRecoveryQuestionedFields(originalAction, originalPlan, input.structured_state || {})
  })
}

function isRouteAwareVisibleRecoveryPacket(packet = {}, input = {}, originalPlan = {}) {
  const bubbles = Array.isArray(packet?.bubbles) ? packet.bubbles : []
  const text = bubbles.length === 1 ? compact(bubbles[0]?.text) : ''
  const expectedText = compact(routeAwareRecoverySurfaceText(input, originalPlan))
  const originalAction = String(originalPlan?.action || 'general_continue')
  const flags = packet?.authority_transport_flags || {}
  return Boolean(
    text && text === expectedText &&
    compact(packet.reply_text) === expectedText &&
    !text.includes(PREFERRED_FORM_LINK) &&
    !/effacermonexistence|contact@omarprotocol|\bzelle\b/i.test(text) &&
    String(packet.next_action_reflected || '') === 'resolve_context' &&
    Array.isArray(packet.acknowledged_fields) &&
    packet.acknowledged_fields.length === 0 &&
    Array.isArray(packet.questioned_fields) &&
    packet.questioned_fields.length === routeAwareRecoveryQuestionedFields(originalAction, originalPlan, input.structured_state || {}).length &&
    packet.questioned_fields.every((value, index) => (
      value === routeAwareRecoveryQuestionedFields(originalAction, originalPlan, input.structured_state || {})[index]
    )) &&
    flags.safe_nontransactional_recovery === true &&
    flags.route_aware_visible_recovery === true &&
    flags.route_aware_visible_recovery_version === ROUTE_AWARE_VISIBLE_RECOVERY_VERSION &&
    String(flags.original_action || '') === originalAction &&
    String(flags.original_reason || '') === String(originalPlan?.reason || '')
  )
}

function inputAuthorizesSafeClarificationRecovery(input = {}) {
  const plan = input.control_transition_contract || {}
  const state = input.structured_state || {}
  return Boolean(
    String(plan.action || '') === 'resolve_context' &&
    String(plan.reason || '') === 'unintelligible' &&
    (
      state.live_turn_voice_transcribe_failed === true ||
      state.live_turn_voice_context_unresolved === true ||
      String(state.live_turn_context_relation || '') === 'unintelligible' ||
      state.live_turn_context_needs_clarification === true
    )
  )
}

function isSafeClarificationRecoveryPacket(packet = {}) {
  const bubbles = Array.isArray(packet?.bubbles) ? packet.bubbles : []
  const text = bubbles.length === 1 ? compact(bubbles[0]?.text) : ''
  return Boolean(
    Object.values(SAFE_CLARIFICATION_TEXT).includes(text) &&
    compact(packet.reply_text) === text &&
    String(packet.next_action_reflected || '') === 'resolve_context' &&
    Array.isArray(packet.acknowledged_fields) && packet.acknowledged_fields.length === 0 &&
    Array.isArray(packet.questioned_fields) &&
    packet.questioned_fields.length === 1 &&
    packet.questioned_fields[0] === 'missing_context' &&
    packet.authority_transport_flags?.safe_nontransactional_recovery === true
  )
}

function isSendFormRecoveryPacket(packet = {}) {
  const bubbles = Array.isArray(packet?.bubbles) ? packet.bubbles : []
  if (bubbles.length !== 3) return false

  const texts = bubbles.map((entry) => compact(entry?.text))
  // The recovery source carries semantic copy while the runner's final client
  // surface removes commas before controller adoption and receipt binding.
  const priceReply = "it isnt free this is my discounted model rate at $150 per hour when the finished piece stays in my style"
  const genericReply = 'yeah here you go'
  const availabilityReply = "send me a couple days that work for you here and i'll check the schedule"
  const answersPrice = texts[0] === priceReply
  const expectedAcknowledged = answersPrice
    ? ['form_offer', 'form_link', 'price']
    : ['form_offer', 'form_link']
  const modelCandidateCount = Number(packet?.authority_transport_flags?.model_candidate_count || 0)

  return Boolean(
    [genericReply, priceReply].includes(texts[0]) &&
    texts[1] === PREFERRED_FORM_LINK &&
    texts[2] === availabilityReply &&
    compact(packet.reply_text) === compact(texts.join('\n')) &&
    Array.isArray(packet.acknowledged_fields) &&
    packet.acknowledged_fields.length === expectedAcknowledged.length &&
    packet.acknowledged_fields.every((value, index) => value === expectedAcknowledged[index]) &&
    Array.isArray(packet.questioned_fields) &&
    packet.questioned_fields.length === 1 &&
    packet.questioned_fields[0] === 'appointment_date' &&
    String(packet.next_action_reflected || '') === 'send_form' &&
    packet.authority_transport_flags?.atomic_send_form_recovery === true &&
    packet.authority_transport_flags?.model_drafts_exhausted === true &&
    modelCandidateCount === SEND_FORM_RECOVERY_MIN_MODEL_CANDIDATES &&
    packet.authority_transport_flags?.deterministic_recovery_version === DETERMINISTIC_RECOVERY_VERSION &&
    packet.authority_transport_flags?.reason === 'authorized_send_form_checkpoint_after_model_exhaustion'
  )
}

// Ben's explicit booking checkpoints remain deliberately narrow. Open dialogue
// is authored afresh by the Responses model. SEND_FORM is a transaction/liveness
// checkpoint, not open dialogue: only an already-authorized controller route may
// use its final packet, and only after the bounded model draft budget is proved
// exhausted. The packet sends /apply once, answers the atomic price side-question
// when present, and leaves availability as the next move.
function buildDeterministicRecoveryPacket(input = {}, planOverride = null, recoveryAuthority = {}) {
  const plan = planOverride || input.control_transition_contract || {
    action: 'general_continue',
    reason: 'missing_plan',
    obligations: [],
    fields: {}
  }
  const action = String(plan.action || 'general_continue')

  if (action === 'deposit_handoff') {
    return decorateDeterministicPacket(input, {
      authority_transport_flags: {
        atomic_deposit_handoff: true,
        reason: 'exact_checkpoint_recovery_after_one_reauthor'
      },
      bubbles: LOCKED_DEPOSIT_HANDOFF_BUBBLES.map(bubble)
    }, {
      plan,
      nextAction: action,
      acknowledgedFields: ['double_check_confirmation', 'deposit'],
      questionedFields: []
    })
  }

  if (action === 'double_check') return doubleCheckPacket(input, plan)
  if (action === 'send_form') return sendFormCheckpointPacket(input, plan, recoveryAuthority)

  throw new Error(`deterministic_visible_recovery_forbidden:${action}`)
}

module.exports = {
  DETERMINISTIC_RECOVERY_VERSION,
  SEND_FORM_RECOVERY_MIN_MODEL_CANDIDATES,
  PREFERRED_FORM_LINK,
  SAFE_CLARIFICATION_TEXT,
  ROUTE_AWARE_VISIBLE_RECOVERY_VERSION,
  buildSafeClarificationRecoveryPacket,
  buildRouteAwareVisibleRecoveryPacket,
  inputAuthorizesSafeClarificationRecovery,
  isSafeClarificationRecoveryPacket,
  isRouteAwareVisibleRecoveryPacket,
  isSendFormRecoveryPacket,
  buildDeterministicRecoveryPacket
}
