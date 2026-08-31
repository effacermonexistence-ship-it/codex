#!/usr/bin/env node

import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'
import { TextDecoder } from 'node:util'

const [sourceArgument, destinationArgument] = process.argv.slice(2)
if (!sourceArgument || !destinationArgument) {
  throw new Error('usage: sanitize-public-mirror.mjs SOURCE DESTINATION')
}

const sourceRoot = path.resolve(sourceArgument)
const destinationRoot = path.resolve(destinationArgument)
if (!fs.statSync(sourceRoot).isDirectory()) throw new Error('source_not_directory')
if (fs.existsSync(destinationRoot)) throw new Error('destination_must_not_exist')

const highRiskFiles = new Set([
  'SCV_DESIGN_INTENT_LOCK.md',
  'cloud-start.js',
  'codex-dm-runner.js',
  'scv-booking-policy-harness.js',
  'scv-closed-lifecycle-harness.js',
  'scv-critical-route-harness.js',
  'scv-deterministic-recovery-harness.js',
  'scv-gmail-form-harness.js',
  'scv-manychat-input-sweep-harness.js',
  'scv-manychat-input-sweep.js',
  'scv-manychat-orphan-recovery.js',
  'scv-media-only-inbound-harness.js',
  'scv-persistent-state-harness.js',
  'scv-persistent-state.js',
  'scv-runner-semantic-repair-harness.js',
  'scv-sandbox-driver.js',
  'scv-single-control-plane-harness.js',
  'scv-visible-english-output-harness.js',
  'KANDO_INTENCHANEL_BOATMAN_ROOT_CAUSE_2026-07-10.md',
  'scv-kando-regression-harness.js',
  'CLAUDE_HANDOFF_SCV_MISSED_INBOUND_AUDIT_2026-06-23.md',
  'SCV_BOOKING_DRIFT_FORENSIC_2026-07-25.md'
])

const replacedDocuments = new Map([
  [
    'KANDO_INTENCHANEL_BOATMAN_ROOT_CAUSE_2026-07-10.md',
    '# Sanitized inbound recovery case\n\n' +
      'The private source contains a production-derived customer incident used to ' +
      'explain duplicate recovery, stale outbox handling, and booking-state repair. ' +
      'Customer identifiers and message text are intentionally omitted from this ' +
      'public mirror. The exact evidence remains in access-restricted R2 custody.\n'
  ],
  [
    'CLAUDE_HANDOFF_SCV_MISSED_INBOUND_AUDIT_2026-06-23.md',
    '# Sanitized missed-inbound audit handoff\n\n' +
      'The private source names customers from a production thread. This public ' +
      'mirror retains only the fact that missed-inbound recovery was audited; names, ' +
      'aliases, thread details, and message content are intentionally omitted.\n'
  ],
  [
    'SCV_BOOKING_DRIFT_FORENSIC_2026-07-25.md',
    '# Sanitized booking-drift forensic note\n\n' +
      'The private source contains production-log-derived client-request excerpts. ' +
      'They are omitted from this public mirror because the source does not prove ' +
      'that every referenced account was synthetic.\n'
  ]
])

const decoder = new TextDecoder('utf-8', { fatal: true })

function listFiles(root) {
  const files = []
  function walk(directory, relative = '') {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const nextRelative = relative ? `${relative}/${entry.name}` : entry.name
      const absolute = path.join(directory, entry.name)
      const stat = fs.lstatSync(absolute)
      if (stat.isSymbolicLink()) throw new Error(`source_symlink_forbidden:${nextRelative}`)
      if (stat.isDirectory()) walk(absolute, nextRelative)
      else if (stat.isFile()) files.push(nextRelative)
      else throw new Error(`source_special_file_forbidden:${nextRelative}`)
    }
  }
  walk(root)
  return files.sort()
}

function readText(file) {
  const bytes = fs.readFileSync(file)
  try {
    return decoder.decode(bytes)
  } catch {
    return null
  }
}

function collectPropertyValues(text, names) {
  const values = new Set()
  const expression = new RegExp(
    `\\b(?:${names.join('|')})\\s*:\\s*(['\"\`])([^'\"\`\\r\\n]+)\\1`,
    'giu'
  )
  for (const match of text.matchAll(expression)) {
    const value = match[2].trim()
    if (value) values.add(value)
  }
  return values
}

function collectContextualHandles(text) {
  const values = new Set()
  const expressions = [
    /real lead\s+\*\*([A-Za-z0-9._-]{3,64})\*\*/giu,
    /log-confirmed victim:\s*`([A-Za-z0-9._-]{3,64})`/giu,
    /made\s+([A-Za-z0-9._-]{3,64})'s/giu,
    /\(([A-Za-z0-9._-]{3,64})\s+class\)/giu,
    /live cases:\s*([A-Za-z0-9._-]{3,64})\s+got/giu
  ]
  for (const expression of expressions) {
    for (const match of text.matchAll(expression)) values.add(match[1])
  }
  return values
}

function replaceEvery(text, search, replacement) {
  if (!search) return text
  return text.split(search).join(replacement)
}

function sanitizeOriginalKandoObject(text, sensitiveStrings) {
  const start = text.indexOf('const original = {')
  if (start < 0) throw new Error('kando_original_fixture_missing')
  const end = text.indexOf('\n  }', start)
  if (end < 0) throw new Error('kando_original_fixture_unterminated')
  const before = text.slice(0, start)
  let block = text.slice(start, end + 4)
  const after = text.slice(end + 4)
  const replacements = {
    contact_id: 'public-sanitized-contact',
    thread_id: 'public-sanitized-thread',
    message_id: 'public-sanitized-message',
    instagram_username: 'public_sanitized_lead',
    text: '[public-sanitized-inbound]',
    received_at: '2026-08-31T00:00:00.000Z'
  }
  for (const [key, replacement] of Object.entries(replacements)) {
    const expression = new RegExp(`(\\b${key}\\s*:\\s*)(['\"\`])([^'\"\`\\r\\n]*)(\\2)`, 'u')
    block = block.replace(expression, (whole, prefix, quote, value) => {
      if (value) sensitiveStrings.add(value)
      return `${prefix}${quote}${replacement}${quote}`
    })
  }
  return before + block + after
}

const sourceFiles = listFiles(sourceRoot)
const sensitiveStrings = new Set()
const sensitiveNumbers = new Set()

for (const relative of sourceFiles) {
  if (!highRiskFiles.has(relative)) continue
  const text = readText(path.join(sourceRoot, relative))
  if (text === null) throw new Error(`high_risk_file_not_text:${relative}`)
  for (const value of collectPropertyValues(text, [
    'instagram_username',
    'ig_username',
    'contact_id',
    'thread_id',
    'message_id'
  ])) sensitiveStrings.add(value)
  for (const value of collectContextualHandles(text)) sensitiveStrings.add(value)
  for (const match of text.matchAll(/(?<![A-Za-z0-9])[0-9]{10,30}(?![A-Za-z0-9])/gu)) {
    sensitiveNumbers.add(match[0])
  }
}

fs.cpSync(sourceRoot, destinationRoot, {
  recursive: true,
  dereference: false,
  errorOnExist: true,
  force: false,
  preserveTimestamps: true
})

let changedFiles = 0
let emailReplacements = 0
let pathReplacements = 0
let identifierReplacements = 0

for (const relative of sourceFiles) {
  const destination = path.join(destinationRoot, relative)
  let text = readText(destination)
  if (text === null) continue
  const original = text

  if (replacedDocuments.has(relative)) {
    text = replacedDocuments.get(relative)
  } else if (relative === 'scv-kando-regression-harness.js') {
    text = sanitizeOriginalKandoObject(text, sensitiveStrings)
  }

  for (const value of sensitiveStrings) {
    if (!value || value.length < 3) continue
    const replacement = value.includes('@')
      ? 'operator@example.invalid'
      : 'public_sanitized_identifier'
    const before = text
    text = replaceEvery(text, value, replacement)
    if (text !== before) identifierReplacements += 1
  }
  for (const value of sensitiveNumbers) {
    const before = text
    text = replaceEvery(text, value, '0'.repeat(value.length))
    if (text !== before) identifierReplacements += 1
  }

  text = text.replace(
    /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/giu,
    match => {
      if (match.toLowerCase().endsWith('@example.invalid')) return match
      emailReplacements += 1
      return 'operator@example.invalid'
    }
  )
  text = text.replace(/\/Users\/[^\s'"`<>)]*/gu, () => {
    pathReplacements += 1
    return '/Users/REDACTED/PRIVATE_PATH'
  })
  text = text.replace(/\/tmp\/[^\s'"`<>)]*/gu, () => {
    pathReplacements += 1
    return '/tmp/REDACTED_PATH'
  })
  text = text.replace(/[^\s'"`<>]*CloudDocs[^\s'"`<>]*/giu, () => {
    pathReplacements += 1
    return '[PUBLIC_REDACTED_PATH]'
  })

  if (text !== original) {
    fs.writeFileSync(destination, text, 'utf8')
    changedFiles += 1
  }
}

const descriptor = path.join(destinationRoot, 'SCV_SINGLE_RELEASE.json')
if (!fs.existsSync(descriptor)) throw new Error('source_descriptor_missing')
fs.unlinkSync(descriptor)

const sanitizedFiles = listFiles(destinationRoot)
for (const relative of sanitizedFiles) {
  const text = readText(path.join(destinationRoot, relative))
  if (text === null) continue
  for (const value of sensitiveStrings) {
    if (value && value.length >= 3 && text.includes(value)) {
      throw new Error(`sensitive_string_remains:${relative}`)
    }
  }
  for (const value of sensitiveNumbers) {
    if (value && text.includes(value)) throw new Error(`sensitive_number_remains:${relative}`)
  }
  if (/\/Users\/(?!REDACTED\/PRIVATE_PATH)/u.test(text)) {
    throw new Error(`private_user_path_remains:${relative}`)
  }
  if (/CloudDocs/iu.test(text)) throw new Error(`clouddocs_path_remains:${relative}`)
  const emails = text.match(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/giu) || []
  if (emails.some(email => !email.toLowerCase().endsWith('@example.invalid'))) {
    throw new Error(`non_placeholder_email_remains:${relative}`)
  }
  if (/-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----/u.test(text)) {
    throw new Error(`private_key_marker_remains:${relative}`)
  }
}

process.stdout.write(`${JSON.stringify({
  ok: true,
  source_files: sourceFiles.length,
  output_files_before_reseal: sanitizedFiles.length,
  changed_files: changedFiles,
  sensitive_string_classes: sensitiveStrings.size,
  sensitive_number_classes: sensitiveNumbers.size,
  identifier_replacement_groups: identifierReplacements,
  email_replacements: emailReplacements,
  path_replacements: pathReplacements,
  descriptor_removed_for_reseal: true
}, null, 2)}\n`)
