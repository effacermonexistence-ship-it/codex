#!/usr/bin/env node
const fs = require('fs')
const path = require('path')
const {
  SCV_CONTRACT_HARNESS_LOCK_VERSION,
  packetLiteralizesEmojiName,
  packetHasNamePhoneDateTimeDoubleCheck,
  liveConfirmsDoubleCheck,
  packetSendsDepositDetails,
  packetGatesExactAddressBehindDeposit,
  formPermissionTextWasAsked,
  PREFERRED_FORM_LINK
} = require(path.join(__dirname, 'scv-contract-harness.js'))
const {
  runStateQuarantineSweep
} = require(path.join(__dirname, 'scv-state-quarantine.js'))
const {
  SCV_DELIVERY_PACING_LOCK_VERSION
} = require(path.join(__dirname, 'scv-delivery-pacing.js'))
const {
  SCV_HARD_HARNESS_LOCK_VERSION,
  runScvHardHarnessLock
} = require(path.join(__dirname, 'scv-hard-harness-lock.js'))
const {
  isConversationVisibleAssistantEvent
} = require(path.join(__dirname, 'scv-history-visibility.js'))
const { hmacSha256, errorMetrics } = require(path.join(__dirname, 'scv-machine-log.js'))

// Tests may isolate mutable drift receipts without changing SCV_ROOT, because
// SCV_ROOT is also the authority root used by the nested hard harness.
const ROOT = process.env.SCV_DRIFT_ROOT || process.env.SCV_ROOT || __dirname
const LOG_DIR = path.join(ROOT, 'logs')
const DRIFT_ALERTS_FILE = path.join(LOG_DIR, 'drift-alerts.ndjson')
const DRIFT_STATUS_FILE = path.join(LOG_DIR, 'drift-status.json')
const MONITOR_INTERVAL_MS = Math.max(5000, Number(process.env.SCV_DRIFT_MONITOR_INTERVAL_MS || 60000))
const QUEUE_STALE_MS = Math.max(60000, Number(process.env.SCV_QUEUE_STALE_MS || (10 * 60 * 1000)))

const QUEUE_DIRS = [
  'inbox',
  'outbox',
  'reactbox'
]

const QUARANTINE_DIRS = [
  'inbox_quarantine_deadletter',
  'outbox_quarantine_contract_harness',
  'outbox_quarantine_failed',
  'outbox_human_agent_required',
  'thread-state_quarantine_contaminated',
  'thread-history_quarantine_contaminated'
]

function ensureLogDir() {
  fs.mkdirSync(LOG_DIR, { recursive: true })
}

function appendNdjson(file, obj) {
  ensureLogDir()
  fs.appendFileSync(file, JSON.stringify(obj) + '\n')
}

function safeReadJson(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')) } catch { return null }
}

function listFilesRecursive(dir) {
  if (!fs.existsSync(dir)) return []
  const files = []
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const file = path.join(dir, entry.name)
    if (entry.isDirectory()) files.push(...listFilesRecursive(file))
    else if (entry.isFile()) files.push(file)
  }
  return files
}

function normalizeText(value) {
  return String(value || '').toLowerCase().replace(/\s+/g, ' ').trim()
}

function packetFromText(text) {
  return { bubbles: [{ text: String(text || '') }] }
}

function eventInput(historyEvents, idx) {
  const recent = historyEvents.slice(Math.max(0, idx - 8), idx).map((event) => ({
    role: isConversationVisibleAssistantEvent(event) ? 'assistant' : String(event.role || ''),
    text: String(event.text || event.message || ''),
    message_id: String(event.message_id || '')
  }))
  const live = historyEvents[idx] || {}
  return {
    message: String(live.text || live.message || ''),
    recent_history: recent,
    structured_state: {}
  }
}

function hasConsecutiveDuplicateAssistant(events, idx) {
  const event = events[idx]
  if (!isConversationVisibleAssistantEvent(event)) return false
  const text = normalizeText(event?.text || '')
  if (!text) return false
  for (let i = idx - 1; i >= 0; i -= 1) {
    const prev = events[i]
    if (!isConversationVisibleAssistantEvent(prev)) continue
    return normalizeText(prev?.text || '') === text
  }
  return false
}

function scanThreadHistory(file) {
  const history = safeReadJson(file)
  const events = Array.isArray(history?.events) ? history.events : []
  const alerts = []
  let formOfferSeen = false
  let formLinkSeen = false

  for (let i = 0; i < events.length; i += 1) {
    const event = events[i]
    const text = String(event?.text || '')
    if (!text) continue

    if (isConversationVisibleAssistantEvent(event)) {
      const packet = packetFromText(text)
      const asksFormPermission = formPermissionTextWasAsked(text)
      const sendsFormLink = text.includes(PREFERRED_FORM_LINK)
      if (sendsFormLink) formLinkSeen = true
      if (asksFormPermission) {
        if (formOfferSeen || formLinkSeen) {
          alerts.push({ reason: 'repeated_form_link_permission_offer_visible_history', file, index: i, message_id: event.message_id || '', text: text.slice(0, 180) })
        }
        formOfferSeen = true
      }
      if (packetLiteralizesEmojiName(packet)) {
        alerts.push({ reason: 'emoji_name_literalization_visible_history', file, index: i, message_id: event.message_id || '' })
      }
      if (packetGatesExactAddressBehindDeposit(packet)) {
        alerts.push({ reason: 'address_gated_behind_deposit_visible_history', file, index: i, message_id: event.message_id || '' })
      }
      if (hasConsecutiveDuplicateAssistant(events, i)) {
        alerts.push({ reason: 'duplicate_assistant_text_visible_history', file, index: i, message_id: event.message_id || '' })
      }
    }

    if (String(event.role || '') === 'user' && liveConfirmsDoubleCheck(eventInput(events, i))) {
      const prior = events.slice(Math.max(0, i - 8), i)
      const sawDoubleCheck = prior.some((prev) => (
        isConversationVisibleAssistantEvent(prev) &&
        packetHasNamePhoneDateTimeDoubleCheck(packetFromText(prev.text || ''))
      ))
      if (sawDoubleCheck) {
        const nextAssistant = events.slice(i + 1).find(isConversationVisibleAssistantEvent)
        if (nextAssistant && !packetSendsDepositDetails(packetFromText(nextAssistant.text || ''))) {
          alerts.push({ reason: 'double_check_confirmed_without_deposit_history', file, index: i, message_id: event.message_id || '', next_text: String(nextAssistant.text || '').slice(0, 180) })
        }
      }
    }
  }

  return alerts
}

function scanQueueDir(dirName) {
  const dir = path.join(ROOT, dirName)
  const files = listFilesRecursive(dir)
  const now = Date.now()
  const stale = []
  const future_due = []
  for (const file of files) {
    try {
      const stat = fs.statSync(file)
      const packet = safeReadJson(file)
      const dueAtMs = Number.isFinite(Date.parse(String(packet?.due_at || ''))) ? Date.parse(String(packet?.due_at || '')) : null
      if (dirName === 'outbox' && dueAtMs && dueAtMs > now) {
        future_due.push({ file, due_in_ms: Math.round(dueAtMs - now) })
        continue
      }
      const ageBasisMs = dirName === 'outbox' && dueAtMs ? dueAtMs : stat.mtimeMs
      if (now - ageBasisMs > QUEUE_STALE_MS) {
        stale.push({ file, age_ms: Math.round(now - ageBasisMs), due_at: dueAtMs ? new Date(dueAtMs).toISOString() : undefined })
      }
    } catch {}
  }
  return { dir: dirName, count: files.length, stale, future_due: future_due.slice(0, 10) }
}

function scanQuarantineDir(dirName) {
  const dir = path.join(ROOT, dirName)
  const files = listFilesRecursive(dir)
  return { dir: dirName, count: files.length, recent: files.slice(-5) }
}

function runScvDriftMonitorOnce() {
  ensureLogDir()
  const stateSweep = runStateQuarantineSweep()
  const alerts = []
  const pausedMaintenance = String(process.env.SCV_PAUSE_ALL || '') === '1'

  for (const file of listFilesRecursive(path.join(ROOT, 'thread-history')).filter((name) => name.endsWith('.json'))) {
    alerts.push(...scanThreadHistory(file))
  }

  const queues = QUEUE_DIRS.map(scanQueueDir)
  if (!pausedMaintenance) {
    for (const queue of queues) {
      for (const stale of queue.stale) {
        alerts.push({ reason: 'queue_file_stale', queue: queue.dir, file: stale.file, age_ms: stale.age_ms })
      }
    }
  }

  const quarantines = QUARANTINE_DIRS.map(scanQuarantineDir)
  if (!pausedMaintenance) {
    for (const q of quarantines) {
      if (q.count > 0) {
        alerts.push({ reason: 'quarantine_not_empty', dir: q.dir, count: q.count, recent: q.recent })
      }
    }
  }

  for (const quarantined of stateSweep.quarantined || []) {
    alerts.push({ reason: 'state_quarantine_sweep_moved_file', ...quarantined })
  }

  let hardHarness = null
  try {
    hardHarness = runScvHardHarnessLock()
  } catch (err) {
    hardHarness = { ok: false, lock_version: SCV_HARD_HARNESS_LOCK_VERSION, error: String(err && err.message ? err.message : err), failures: err.failures || [] }
    alerts.push({ reason: 'hard_harness_lock_failed', hard_harness: hardHarness })
  }

  const status = {
    ok: alerts.length === 0,
    at: new Date().toISOString(),
    lock_version: SCV_CONTRACT_HARNESS_LOCK_VERSION,
    delivery_pacing_lock_version: SCV_DELIVERY_PACING_LOCK_VERSION,
    hard_harness_lock_version: SCV_HARD_HARNESS_LOCK_VERSION,
    hard_harness: hardHarness,
    paused_maintenance: pausedMaintenance,
    alert_count: alerts.length,
    alerts: alerts.slice(-50),
    queues,
    quarantines,
    state_sweep: stateSweep
  }

  fs.writeFileSync(DRIFT_STATUS_FILE, JSON.stringify(status, null, 2) + '\n')
  if (alerts.length) {
    appendNdjson(DRIFT_ALERTS_FILE, {
      at: status.at,
      lock_version: SCV_CONTRACT_HARNESS_LOCK_VERSION,
      alert_count: alerts.length,
      alerts: alerts.slice(-25)
    })
  }

  return status
}

function driftStatusLogSummary(status = {}) {
  const alerts = Array.isArray(status.alerts) ? status.alerts : []
  const alertReasons = alerts.map((alert) => String(alert?.reason || '')).sort()
  return {
    ok: status.ok === true,
    at: String(status.at || ''),
    lock_version: String(status.lock_version || ''),
    delivery_pacing_lock_version: String(status.delivery_pacing_lock_version || ''),
    hard_harness_lock_version: String(status.hard_harness_lock_version || ''),
    alert_count: Number(status.alert_count || alerts.length || 0),
    alert_reasons_hmac_sha256: hmacSha256(alertReasons.join('\n')),
    queue_count: Array.isArray(status.queues) ? status.queues.length : 0,
    quarantine_count: Array.isArray(status.quarantines) ? status.quarantines.length : 0
  }
}

async function loop() {
  while (true) {
    try {
      const status = runScvDriftMonitorOnce()
      console.log(JSON.stringify({ event: 'scv_drift_monitor_tick', ...driftStatusLogSummary(status) }))
    } catch (err) {
      console.error(JSON.stringify({ event: 'scv_drift_monitor_error', ...errorMetrics(err) }))
    }
    await new Promise((resolve) => setTimeout(resolve, MONITOR_INTERVAL_MS))
  }
}

if (require.main === module) {
  if (process.argv.includes('--loop')) {
    loop()
  } else {
    const status = runScvDriftMonitorOnce()
    process.stdout.write(JSON.stringify(status, null, 2) + '\n')
    if (!status.ok && process.argv.includes('--fail-on-alert')) process.exit(1)
  }
}

module.exports = {
  runScvDriftMonitorOnce,
  driftStatusLogSummary,
  scanThreadHistory
}
