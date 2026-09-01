#!/usr/bin/env node
// One authoritative parser for booking identity supplied in the live DM turn.
// Both the state builder and the deterministic booking checkpoint import this
// module so name/phone extraction cannot drift between route selection and the
// visible four-field verification packet.

function extractBookingPhone(value) {
  const raw = String(value || '').trim()
  if (!raw || /https?:\/\//i.test(raw)) return ''

  const spans = raw.match(/[+\d][+\d\s().-]{5,}\d/g) || []
  for (let index = spans.length - 1; index >= 0; index -= 1) {
    const digits = String(spans[index] || '').replace(/\D/g, '')
    if (digits.length >= 7 && digits.length <= 15) return digits
  }

  const digits = raw.replace(/\D/g, '')
  return digits.length >= 7 && digits.length <= 15 ? digits : ''
}

// A phone-looking span is not automatically the booking client's identity.
// Keep this classifier in the shared identity module so live parsing and cpublic_sanitized_identifier
// history rebuild cannot disagree after a restart.  Ambiguous third-person
// phrasing fails closed: asking the client to restate their own form details is
// safer than attaching another person's contact information to the booking.
function textFramesThirdPartyBookingIdentity(value) {
  const raw = String(value || '')
    .normalize('NFKC')
    .replace(/[\u2018\u2019\u02bc\uff07]/g, "'")
    .replace(/\s+/g, ' ')
    .trim()
  if (!raw || !extractBookingPhone(raw)) return false

  const contactField = '(?:phone(?:\\s+number)?|number|cell|mobile|contact)'
  const thirdPartyRole = '(?:friend|mom|mother|dad|father|parent|sister|brother|wife|husband|partner|boyfriend|girlfriend|fiance|fiancee|cousin|aunt|uncle|grandmother|grandfather|grandma|grandpa|son|daughter|child|roommate|coworker|colleague|client|customer|assistant|manager|artist|doctor|nurse|lawyer|boss|employee)'

  const patterns = [
    new RegExp(`\\b(?:his|her|their|someone(?:\\s+else)?'s|somebody(?:\\s+else)?'s)\\s+${contactField}\\b`, 'iu'),
    new RegExp(`\\b(?:my|our|the|a|an)\\s+${thirdPartyRole}(?:'s|s')?\\b`, 'iu'),
    // Proper-name and open-vocabulary possessives: "Alex's phone" and
    // "my doctor's phone" must remain ordinary conversation facts.
    new RegExp(`(?:^|[^\\p{L}\\p{N}_])(?:[\\p{L}\\p{M}][\\p{L}\\p{M}.'-]{0,39})(?:'s|s')\\s+${contactField}\\b`, 'iu'),
    new RegExp(`\\b(?:call|text|contact|reach)\\s+(?!me\\b|us\\b)(?:him|her|them|(?:my|our|the)\\s+${thirdPartyRole}|[\\p{L}][\\p{L}\\p{M}.'-]{0,39})(?:\\s+[\\p{L}][\\p{L}\\p{M}.'-]{0,39}){0,2}\\s+(?:at|on)\\b`, 'iu'),
    new RegExp(`\\b(?:he|she|they|[\\p{L}][\\p{L}\\p{M}.'-]{1,39})\\s+(?:can\\s+be\\s+)?(?:reached|contacted|called|texted)\\s+(?:at|on)\\b`, 'iu'),
    new RegExp(`\\b${contactField}\\s+(?:belongs\\s+to|is\\s+for)\\s+(?!me\\b|us\\b)(?:him|her|them|${thirdPartyRole}|[\\p{L}][\\p{L}\\p{M}.'-]{1,39})\\b`, 'iu')
  ]
  return patterns.some((pattern) => pattern.test(raw))
}

// Parse booking field labels as structure instead of assuming one display
// order.  The form/client may paste comma-, semicolon-, or newline-separated
// fields in any order. Duplicate labels fail closed so a conflicting payload
// cannot silently pick one value.
function extractLabeledBookingFields(value) {
  const raw = String(value || '').normalize('NFKC').trim()
  const empty = {
    detected: false,
    valid: false,
    duplicate_fields: [],
    present_fields: [],
    name: '',
    phone: '',
    date_text: '',
    time_text: ''
  }
  if (!raw) return empty

  const labelPattern = /(?:^|[,;\n]\s*)(name|phone(?:\s+number)?|appointment\s+date|date|time)\s*[:=]\s*/gim
  const matches = [...raw.matchAll(labelPattern)]
  if (matches.length < 2) return empty

  const fields = {}
  const duplicates = new Set()
  for (let index = 0; index < matches.length; index += 1) {
    const match = matches[index]
    const label = String(match[1] || '').toLowerCase().replace(/\s+/g, ' ')
    const key = label.startsWith('phone')
      ? 'phone'
      : label.endsWith('date')
        ? 'date'
        : label
    const valueStart = Number(match.index || 0) + String(match[0] || '').length
    const valueEnd = index + 1 < matches.length ? Number(matches[index + 1].index || raw.length) : raw.length
    const fieldValue = raw.slice(valueStart, valueEnd)
      .replace(/^[\s,;]+|[\s,;]+$/g, '')
      .trim()
    if (Object.prototype.hasOwnProperty.call(fields, key)) duplicates.add(key)
    else fields[key] = fieldValue
  }

  const presentFields = Object.keys(fields).sort()
  const name = sanitizeBookingIdentityName(fields.name || '')
  const phone = extractBookingPhone(fields.phone || '')
  const valid = duplicates.size === 0 && presentFields.length === matches.length
  return {
    detected: true,
    valid,
    duplicate_fields: [...duplicates].sort(),
    present_fields: presentFields,
    name: valid ? name : '',
    phone: valid ? phone : '',
    date_text: valid ? String(fields.date || '').trim() : '',
    time_text: valid ? String(fields.time || '').trim() : ''
  }
}

// Shared structural parser for the two complete client payload shapes accepted
// by the live controller and cpublic_sanitized_identifier history rebuild. It performs no calendar
// availability decision; callers bind the returned date to their immutable
// ingress snapshot. `detected` remains true for malformed four-field-looking
// input so downstream broad extractors cannot salvage a phone/date fragment.
function extractExplicitFourFieldBookingPayload(value) {
  const raw = String(value || '').normalize('NFKC').trim()
  const empty = {
    detected: false,
    valid: false,
    source: '',
    reason: 'not_four_field_payload',
    name: '',
    phone: '',
    date_text: '',
    time_text: ''
  }
  if (!raw) return empty

  const datePattern = '(?:(?:the\\s+)?\\d{1,2}(?:st|nd|rd|th)?\\s+(?:of\\s+)?(?:january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec)|(?:january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec)\\s+(?:the\\s+)?\\d{1,2}(?:st|nd|rd|th)?)'
  const timePattern = '\\d{1,2}(?::\\d{2})?\\s*(?:a\\.?m\\.?|p\\.?m\\.?)'
  const labeled = extractLabeledBookingFields(raw)
  if (labeled.detected) {
    const complete = (
      labeled.valid &&
      labeled.present_fields.length === 4 &&
      ['date', 'name', 'phone', 'time'].every((key) => labeled.present_fields.includes(key))
    )
    const valid = Boolean(
      complete &&
      labeled.name &&
      labeled.phone &&
      new RegExp(`^${datePattern}$`, 'iu').test(labeled.date_text) &&
      new RegExp(`^${timePattern}$`, 'iu').test(labeled.time_text)
    )
    if (!valid || textFramesThirdPartyBookingIdentity(raw)) {
      return { ...empty, detected: true, source: 'labeled', reason: 'invalid_labeled_four_field_payload' }
    }
    return {
      detected: true,
      valid: true,
      source: 'labeled',
      reason: '',
      name: labeled.name,
      phone: labeled.phone,
      date_text: labeled.date_text,
      time_text: labeled.time_text
    }
  }

  const looksUnlabeled = (raw.match(/,/g) || []).length === 3
  const match = raw.match(new RegExp(
    `^([\\p{L}][\\p{L}\\p{M} .'-]{0,59})\\s*,\\s*([+\\d][+\\d\\s().-]{5,}\\d)\\s*,\\s*(${datePattern})\\s*,\\s*(${timePattern})\\s*[.!?]*$`,
    'iu'
  ))
  if (!match) {
    return looksUnlabeled
      ? { ...empty, detected: true, source: 'unlabeled', reason: 'invalid_unlabeled_four_field_payload' }
      : empty
  }
  const name = sanitizeBookingIdentityName(match[1])
  const phone = extractBookingPhone(match[2])
  if (!name || !phone || textFramesThirdPartyBookingIdentity(raw)) {
    return { ...empty, detected: true, source: 'unlabeled', reason: 'invalid_unlabeled_four_field_identity' }
  }
  return {
    detected: true,
    valid: true,
    source: 'unlabeled',
    reason: '',
    name,
    phone,
    date_text: String(match[3] || '').trim(),
    time_text: String(match[4] || '').trim()
  }
}

function sanitizeBookingIdentityName(value) {
  let name = String(value || '')
    .replace(/[\r\n\t]+/g, ' ')
    .replace(/\s+/g, ' ')
    // Remove punctuation left behind after a terminal phone span before
    // stripping "and my phone is".  The public_sanitized_identifier order preserved that phrase and
    // polluted the durable name on a normal sentence ending in a period.
    .replace(/[\s"'`~!.,:;()]+$/g, '')
    .trim()

  name = name
    .replace(/^(?:i\s+(?:used|put|entered)|i\s+public_sanitized_identifier(?:\s+it)?\s+under|the\s+name(?:\s+i\s+used)?(?:\s+(?:is|was))?|(?:my\s+)?name(?:\s+(?:is|was))?|it(?:'s|\s+is)|i(?:'m|\s+am))\s*[:;,]?\s*/i, '')
    .replace(/\s+(?:and|with)?\s*(?:(?:my|the)\s+)?(?:phone(?:\s+number)?|number|cell|mobile)(?:\s+(?:is|was))?\s*$/i, '')
    .replace(/\s+(?:and|with)\s*$/i, '')
    .replace(/^(?:and|with)\s+/i, '')
    .replace(/^[\s"'`~!.,:;()]+|[\s"'`~!.,:;()]+$/g, '')
    .trim()

  if (!name || name.length > 60 || !/[\p{L}가-힣]/u.test(name)) return ''
  return name
}

function extractBookingNameNextToPhone(value) {
  const raw = String(value || '').trim()
  if (!extractBookingPhone(raw)) return ''

  const withoutPhone = raw
    .replace(/[+\d][+\d\s().-]{5,}\d/g, ' ')
    .replace(/[()]/g, ' ')
    .replace(/[\s"'`~!.,:;]+$/g, '')
    .replace(/\b(?:phone(?:\s+number)?|number|cell|mobile)\s*[:=]?\s*$/i, ' ')
    .replace(/\s+/g, ' ')
    .trim()

  return sanitizeBookingIdentityName(withoutPhone)
}

module.exports = {
  extractBookingPhone,
  extractBookingNameNextToPhone,
  extractExplicitFourFieldBookingPayload,
  extractLabeledBookingFields,
  sanitizeBookingIdentityName,
  textFramesThirdPartyBookingIdentity
}
