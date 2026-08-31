#!/usr/bin/env node
// Persistent production fail-close latch for the immutable gpublic_sanitized_identifieren release.
//
// The latch lives on the namespaced Railway volume, not in the deployment
// filesystem. A failed synthetic check therefore survives process restarts and
// hpublic_sanitized_identifiers every outbound path until an explicitly approved operator clear.
const fs = require('fs')
const path = require('path')
const crypto = require('crypto')
const {
  runtimeNamespaceFromEnv,
  namespacedPersistRoot
} = require(path.join(__dirname, 'scv-runtime-namespace.js'))

const SCV_GOLDEN_FAIL_CLOSE_VERSION = 'scv-gpublic_sanitized_identifieren-fail-close-2026-07-25-v2'
const LATCH_FILE = 'scv-gpublic_sanitized_identifieren-synthetic-fail-closed.json'
const ALERT_CLAIM_FILE = 'scv-gpublic_sanitized_identifieren-synthetic-alert-claimed'
const ACTIVATION_CLAIM_FILE = 'scv-gpublic_sanitized_identifieren-synthetic-activation-claimed'
const DEFAULT_ALERT_LEASE_MS = 5 * 60 * 1000

function isProductionEnv(env = process.env) {
  return String(env.RAILWAY_ENVIRONMENT_NAME || '').trim().toLowerCase() === 'production' ||
    String(env.SCV_RELEASE_MODE || '').trim().toLowerCase() === 'production'
}

function latchDirectory({ env = process.env, root = env.SCV_ROOT || __dirname } = {}) {
  const persistRoot = String(env.SCV_PERSIST_ROOT || env.RAILWAY_VOLUME_MOUNT_PATH || '').trim()
  if (isProductionEnv(env)) {
    if (!persistRoot) throw new Error('production_persistent_control_root_missing')
    if (!path.isAbsolute(persistRoot)) {
      throw new Error(`production_persistent_control_root_not_absolute:${persistRoot}`)
    }
    if (!fs.existsSync(persistRoot) || !fs.statSync(persistRoot).isDirectory()) {
      throw new Error(`production_persistent_control_root_unavailable:${persistRoot}`)
    }
  }
  if (persistRoot && fs.existsSync(persistRoot) && fs.statSync(persistRoot).isDirectory()) {
    return path.join(
      namespacedPersistRoot(persistRoot, runtimeNamespaceFromEnv(env)),
      'control-locks'
    )
  }
  return path.join(root, 'control-locks')
}

function latchPath(options = {}) {
  return path.join(latchDirectory(options), LATCH_FILE)
}

function alertClaimPath(options = {}) {
  return path.join(latchDirectory(options), ALERT_CLAIM_FILE)
}

function activationClaimPath(options = {}) {
  return path.join(latchDirectory(options), ACTIVATION_CLAIM_FILE)
}

function safeDetail(value, depth = 0) {
  if (depth > 4) return '[depth-limited]'
  if (value === null || value === undefined) return value
  if (typeof value === 'string') return value
    .replace(/Bearer\s+[A-Za-z0-9._~+/-]+/gi, 'Bearer [REDACTED]')
    .replace(/(?:password|token|secret|api[_-]?key)\s*[:=]\s*[^\s,;]+/gi, '$1=[REDACTED]')
    .slice(0, 1000)
  if (typeof value === 'number' || typeof value === 'boolean') return value
  if (Array.isArray(value)) return value.slice(0, 30).map((entry) => safeDetail(entry, depth + 1))
  if (typeof value === 'object') {
    const out = {}
    for (const [key, entry] of Object.entries(value).slice(0, 50)) {
      if (/password|token|secret|api.?key|authorization/i.test(key)) out[key] = '[REDACTED]'
      else out[key] = safeDetail(entry, depth + 1)
    }
    return out
  }
  return String(value).slice(0, 1000)
}

function atomicWriteJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true })
  const nonce = crypto.randomBytes(8).toString('hex')
  const temp = `${file}.${process.pid}.${nonce}.tmp`
  fs.writeFileSync(temp, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 })
  fs.renameSync(temp, file)
}

function readFailClose(options = {}) {
  const file = latchPath(options)
  try {
    const state = JSON.parse(fs.readFileSync(file, 'utf8'))
    if (!state || state.active !== true) {
      return { active: false, file, reason: 'inactive_or_invalid_latch' }
    }
    return { ...state, active: true, file }
  } catch (error) {
    if (error && error.code === 'ENOENT') {
      const activationFile = activationClaimPath(options)
      if (isProductionEnv(options.env || process.env) && fs.existsSync(activationFile)) {
        let activationState = {}
        try {
          activationState = JSON.parse(fs.readFileSync(activationFile, 'utf8'))
        } catch {}
        return {
          ...activationState,
          active: true,
          file,
          reason: 'activation_claim_without_latch',
          activation_claim_file: activationFile
        }
      }
      return { active: false, file, reason: 'latch_absent' }
    }
    // A corrupt or unreadable safety latch is itself a fail-close condition in
    // production. Never silently treat unknown latch state as healthy.
    return {
      active: isProductionEnv(options.env || process.env),
      file,
      reason: 'latch_read_error',
      error: String(error && error.message ? error.message : error).slice(0, 300)
    }
  }
}

function isFailClosed(options = {}) {
  return readFailClose(options).active === true
}

function activateFailClose({
  env = process.env,
  root = env.SCV_ROOT || __dirname,
  releaseId = '',
  releaseFingerprint = '',
  reason = 'synthetic_check_failed',
  failedChecks = [],
  detail = {}
} = {}) {
  const options = { env, root }
  const existing = readFailClose(options)
  if (existing.active) return { created: false, state: existing }

  fs.mkdirSync(latchDirectory(options), { recursive: true })
  const now = new Date().toISOString()
  const state = {
    schema: SCV_GOLDEN_FAIL_CLOSE_VERSION,
    active: true,
    activated_at_utc: now,
    release_id: String(releaseId || ''),
    release_fingerprint_sha256: String(releaseFingerprint || ''),
    reason: String(reason || 'synthetic_check_failed').slice(0, 200),
    failed_checks: Array.from(new Set((Array.isArray(failedChecks) ? failedChecks : [])
      .map((entry) => String(entry || '').slice(0, 160))
      .filter(Boolean))),
    detail: safeDetail(detail),
    response_policy: 'hpublic_sanitized_identifier_all_new_automatic_replies_preserve_current_gpublic_sanitized_identifieren_release',
    alert: {
      attempted_at_utc: '',
      delivered_at_utc: '',
      channel: '',
      delivery_status: 'not_attempted'
    }
  }
  const activationFile = activationClaimPath(options)
  let activationFd
  try {
    activationFd = fs.openSync(activationFile, 'wx', 0o600)
    fs.writeFileSync(activationFd, `${JSON.stringify(state, null, 2)}\n`)
  } catch (error) {
    if (error && error.code === 'EEXIST') {
      return {
        created: false,
        state: readFailClose(options),
        reason: 'activation_already_claimed'
      }
    }
    throw error
  } finally {
    if (activationFd !== undefined) fs.closeSync(activationFd)
  }

  const file = latchPath(options)
  try {
    // A rolling-overlap process may have recovered the activation record and
    // materialized the latch while this creator still held the claim. Preserve
    // that newer alert state instead of overwriting it.
    if (fs.existsSync(file)) {
      return { created: false, state: readFailClose(options) }
    }
    atomicWriteJson(file, state)
  } catch (error) {
    try { fs.unlinkSync(activationFile) } catch {}
    throw error
  }
  return { created: true, state: { ...state, file } }
}

function readAlertClaim(file) {
  try {
    const value = JSON.parse(fs.readFileSync(file, 'utf8'))
    return value && typeof value === 'object' ? value : null
  } catch {
    return null
  }
}

function alertTerminal(state) {
  return ['delivered', 'failed'].includes(String(state?.alert?.delivery_status || ''))
}

function claimSingleAlertAttempt({
  env = process.env,
  root = env.SCV_ROOT || __dirname,
  leaseMs = DEFAULT_ALERT_LEASE_MS,
  nowMs = Date.now()
} = {}) {
  const options = { env, root }
  const state = readFailClose(options)
  if (!state.active) return { claimed: false, reason: 'latch_inactive', state }
  if (alertTerminal(state)) {
    return { claimed: false, reason: 'alert_terminal', state }
  }
  fs.mkdirSync(latchDirectory(options), { recursive: true })
  const claimFile = alertClaimPath(options)
  const lease = Math.max(1000, Number(leaseMs) || DEFAULT_ALERT_LEASE_MS)
  const claimedAt = new Date(nowMs).toISOString()
  const claimId = crypto.randomUUID()
  const claimState = {
    schema: 'scv-gpublic_sanitized_identifieren-alert-lease-2026-07-25-v1',
    claim_id: claimId,
    claimed_at_utc: claimedAt,
    lease_ms: lease,
    status: 'attempting'
  }

  for (let attempt = 0; attempt < 4; attempt += 1) {
    let claimFd
    try {
      claimFd = fs.openSync(claimFile, 'wx', 0o600)
      fs.writeFileSync(claimFd, `${JSON.stringify(claimState, null, 2)}\n`)
      fs.closeSync(claimFd)
      claimFd = undefined
      break
    } catch (error) {
      if (claimFd !== undefined) fs.closeSync(claimFd)
      if (!error || error.code !== 'EEXIST') throw error
      const existing = readAlertClaim(claimFile)
      const existingAt = Date.parse(String(existing?.claimed_at_utc || ''))
      const ageMs = Number.isFinite(existingAt) ? Math.max(0, nowMs - existingAt) : lease
      if (ageMs < lease) {
        return {
          claimed: false,
          reason: 'alert_attempt_in_progress',
          retry_after_ms: Math.max(1000, lease - ageMs),
          state: readFailClose(options)
        }
      }
      const staleFile = `${claimFile}.stale-${nowMs}-${crypto.randomBytes(4).toString('hex')}`
      try {
        fs.renameSync(claimFile, staleFile)
      } catch (renameError) {
        if (renameError && renameError.code === 'ENOENT') continue
        throw renameError
      }
      if (attempt === 3) {
        throw new Error('alert_claim_recovery_exhausted')
      }
    }
  }

  if (!fs.existsSync(claimFile)) throw new Error('alert_claim_not_materialized')
  const next = {
    ...state,
    alert: {
      ...(state.alert || {}),
      attempted_at_utc: claimedAt,
      claim_id: claimId,
      claimed_at_utc: claimedAt,
      lease_ms: lease,
      delivery_status: 'attempting'
    }
  }
  delete next.file
  atomicWriteJson(latchPath(options), next)
  return {
    claimed: true,
    claim_id: claimId,
    state: { ...next, file: latchPath(options) }
  }
}

function completeSingleAlertAttempt({
  env = process.env,
  root = env.SCV_ROOT || __dirname,
  claimId = '',
  delivered = false,
  channel = '',
  error = ''
} = {}) {
  const options = { env, root }
  const state = readFailClose(options)
  if (!state.active) return state
  if (!claimId || String(state.alert?.claim_id || '') !== String(claimId)) {
    return {
      ...state,
      completion_applied: false,
      completion_reason: 'alert_claim_mismatch'
    }
  }
  const completedAt = new Date().toISOString()
  const next = {
    ...state,
    alert: {
      ...(state.alert || {}),
      delivered_at_utc: delivered ? completedAt : '',
      completed_at_utc: completedAt,
      channel: String(channel || '').slice(0, 80),
      delivery_status: delivered ? 'delivered' : 'failed',
      error: delivered ? '' : safeDetail(String(error || 'alert_delivery_failed'))
    }
  }
  delete next.file
  atomicWriteJson(latchPath(options), next)
  atomicWriteJson(alertClaimPath(options), {
    schema: 'scv-gpublic_sanitized_identifieren-alert-lease-2026-07-25-v1',
    claim_id: String(claimId),
    claimed_at_utc: String(state.alert?.claimed_at_utc || state.alert?.attempted_at_utc || ''),
    completed_at_utc: completedAt,
    status: delivered ? 'delivered' : 'failed',
    channel: String(channel || '').slice(0, 80)
  })
  return {
    ...next,
    file: latchPath(options),
    completion_applied: true
  }
}

function clearFailCloseWithVerifiedApproval({
  env = process.env,
  root = env.SCV_ROOT || __dirname,
  approval,
  publicKeyPem
} = {}) {
  const file = latchPath({ env, root })
  const current = readFailClose({ env, root })
  if (!current.active) return { cleared: false, reason: 'already_clear', file }
  const {
    verifyFailCloseClearApprovalReceipt
  } = require(path.join(__dirname, 'scv-release-approval.js'))
  const verification = verifyFailCloseClearApprovalReceipt(
    approval,
    current,
    publicKeyPem
  )
  if (!verification.ok) {
    throw new Error(`fail_close_clear_requires_verified_ben_approval:${verification.failures.join(',')}`)
  }
  const archived = `${file}.cleared-${Date.now()}.json`
  fs.renameSync(file, archived)
  for (const claim of [alertClaimPath({ env, root }), activationClaimPath({ env, root })]) {
    if (!fs.existsSync(claim)) continue
    fs.renameSync(claim, `${claim}.cleared-${Date.now()}`)
  }
  return {
    cleared: true,
    cleared_at_utc: new Date().toISOString(),
    archived_file: archived,
    approval_id: String(approval.approval_id || '')
  }
}

module.exports = {
  SCV_GOLDEN_FAIL_CLOSE_VERSION,
  LATCH_FILE,
  ALERT_CLAIM_FILE,
  ACTIVATION_CLAIM_FILE,
  DEFAULT_ALERT_LEASE_MS,
  isProductionEnv,
  latchDirectory,
  latchPath,
  alertClaimPath,
  activationClaimPath,
  safeDetail,
  atomicWriteJson,
  readFailClose,
  isFailClosed,
  activateFailClose,
  readAlertClaim,
  alertTerminal,
  claimSingleAlertAttempt,
  completeSingleAlertAttempt,
  clearFailCloseWithVerifiedApproval
}
