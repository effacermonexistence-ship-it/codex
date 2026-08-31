const SENTINEL_SCHEMA = 'scv-instagram-drift-sentinel-2026-08-31-v1'
const RELEASE_ID = 'scv-instagram-single-20260831-v123'
const CONTENT_FINGERPRINT = '740cc56ee25fe33cb2bef82a077814aa595c0e4734c737a8e62dc859f10fc870'
const RELEASE_MANIFEST = 'dc851f3331cd0aacfa426d24d1e6eedea97d94869ac520bba29a20c98e65b468'
const VISIBLE_MODEL = 'gpt-5.4-mini-2026-03-17'
const MAX_CANARY_AGE_MS = 90 * 60 * 1000
const MAX_DRIFT_AGE_MS = 3 * 60 * 1000
const FETCH_TIMEOUT_MS = 20_000
const MAX_BODY_BYTES = 64 * 1024
const PREFIX = 'scv-instagram-automation/drift-attestations'

const TARGETS = Object.freeze([
  Object.freeze({
    name: 'production', mode: 'production',
    url: 'https://scv-dm-cloud-survival-production.up.railway.app/readyz'
  }),
  Object.freeze({
    name: 'staging', mode: 'staging',
    url: 'https://scv-stg-ab25da488a5a-golden-stg-ab25da488a5a.up.railway.app/readyz'
  })
])

function boundedNumber(value) {
  const number = Number(value)
  return Number.isFinite(number) && number >= 0 ? number : Number.POSITIVE_INFINITY
}

function evaluateEndpoint(target, status, body) {
  const reasons = []
  const check = (condition, reason) => { if (!condition) reasons.push(reason) }
  check(status === 200, 'http_status')
  check(body?.ok === true, 'readiness')
  check(body?.fail_close_active === false, 'fail_close')
  check(body?.preflight_verified === true, 'preflight')
  check(body?.release?.ok === true, 'release_gate')
  check(body?.release?.mode === target.mode, 'release_mode')
  check(body?.release?.release_phase === 'active', 'release_phase')
  check(body?.release?.phase_ready === true, 'release_phase_ready')
  check(body?.release?.release_id === RELEASE_ID, 'release_id')
  check(body?.release?.content_fingerprint_sha256 === CONTENT_FINGERPRINT, 'content_fingerprint')
  check(body?.release?.release_manifest_sha256 === RELEASE_MANIFEST, 'release_manifest')
  check(body?.drift?.critical_ok === true, 'critical_drift')
  check(Number(body?.drift?.critical_alert_count) === 0, 'critical_drift_alerts')
  check(boundedNumber(body?.drift?.age_ms) <= MAX_DRIFT_AGE_MS, 'drift_status_stale')
  check(body?.capability_canary?.required === true, 'capability_canary_required')
  check(body?.capability_canary?.ok === true, 'capability_canary')
  check(body?.capability_canary?.voice_ok === true, 'voice_capability')
  check(body?.capability_canary?.vision_ok === true, 'vision_capability')
  check(body?.capability_canary?.visible_model_ok === true, 'visible_model_capability')
  check(body?.capability_canary?.provider_model === VISIBLE_MODEL, 'provider_model')
  check(boundedNumber(body?.capability_canary?.age_ms) <= MAX_CANARY_AGE_MS,
    'capability_canary_stale')
  check(body?.model_identity?.visible_model === VISIBLE_MODEL, 'visible_model_identity')
  check(body?.model_identity?.executor === 'openai_responses', 'visible_executor')
  check(body?.model_identity?.api === 'responses_v1', 'visible_api')
  check(body?.model_identity?.enforced === true, 'model_identity_enforcement')
  check(body?.model_identity?.contract_ok === true, 'model_identity_contract')
  check(body?.model_identity?.cross_model_fallback_allowed === false, 'cross_model_fallback')
  check(body?.behavior_contract?.ok === true, 'behavior_contract')
  check(Array.isArray(body?.behavior_contract?.failures) &&
    body.behavior_contract.failures.length === 0, 'behavior_contract_failures')
  return {
    ok: reasons.length === 0,
    name: target.name,
    mode: target.mode,
    http_status: status,
    release_id: String(body?.release?.release_id || ''),
    content_fingerprint_sha256: String(body?.release?.content_fingerprint_sha256 || ''),
    release_manifest_sha256: String(body?.release?.release_manifest_sha256 || ''),
    critical_drift_ok: body?.drift?.critical_ok === true,
    critical_alert_count: Number(body?.drift?.critical_alert_count || 0),
    operational_alert_count: Number(body?.drift?.operational_alert_count || 0),
    drift_age_ms: Number.isFinite(boundedNumber(body?.drift?.age_ms))
      ? boundedNumber(body?.drift?.age_ms) : null,
    capability_canary_ok: body?.capability_canary?.ok === true,
    voice_ok: body?.capability_canary?.voice_ok === true,
    vision_ok: body?.capability_canary?.vision_ok === true,
    visible_model_ok: body?.capability_canary?.visible_model_ok === true,
    provider_model: String(body?.capability_canary?.provider_model || ''),
    capability_age_ms: Number.isFinite(boundedNumber(body?.capability_canary?.age_ms))
      ? boundedNumber(body?.capability_canary?.age_ms) : null,
    fail_close_active: body?.fail_close_active === true,
    reasons
  }
}

async function checkTarget(target, fetchImpl = fetch) {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS)
  try {
    const response = await fetchImpl(target.url, {
      method: 'GET', headers: { accept: 'application/json', 'user-agent': SENTINEL_SCHEMA },
      redirect: 'manual', signal: controller.signal
    })
    const text = await response.text()
    if (new TextEncoder().encode(text).byteLength > MAX_BODY_BYTES) {
      return { ok: false, name: target.name, mode: target.mode,
        http_status: response.status, reasons: ['response_too_large'] }
    }
    let body
    try { body = JSON.parse(text) } catch {
      return { ok: false, name: target.name, mode: target.mode,
        http_status: response.status, reasons: ['invalid_json'] }
    }
    return evaluateEndpoint(target, response.status, body)
  } catch (error) {
    const failure = {
      ok: false,
      name: target.name,
      mode: target.mode,
      http_status: 0,
      reasons: [error?.name === 'AbortError' ? 'request_timeout' : 'request_failed'],
      error_name: String(error?.name || 'Error').slice(0, 80),
      error_message: String(error?.message || error || 'request_failed').slice(0, 240)
    }
    console.error(JSON.stringify({ event: 'scv_sentinel_target_fetch_failed', ...failure }))
    return failure
  } finally { clearTimeout(timer) }
}

async function sha256(bytes) {
  const digest = await crypto.subtle.digest('SHA-256', bytes)
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

async function readState(archive) {
  try {
    const object = await archive.get(`${PREFIX}/STATE.json`)
    return object ? await object.json() : null
  } catch { return null }
}

async function runSentinel(env, options = {}) {
  const checkedAt = new Date(options.now || Date.now()).toISOString()
  const checks = await Promise.all(TARGETS.map((target) =>
    checkTarget(target, options.fetchImpl || fetch)))
  const ok = checks.every((check) => check.ok === true)
  const previous = await readState(env.ARCHIVE)
  const consecutiveFailures = ok ? 0 : Number(previous?.consecutive_failures || 0) + 1
  const receipt = {
    schema: SENTINEL_SCHEMA, ok, checked_at_utc: checkedAt,
    trigger: String(options.trigger || 'scheduled'),
    expected_release: {
      release_id: RELEASE_ID,
      content_fingerprint_sha256: CONTENT_FINGERPRINT,
      release_manifest_sha256: RELEASE_MANIFEST,
      visible_model: VISIBLE_MODEL
    },
    checks, consecutive_failures: consecutiveFailures,
    contains_credentials: false, contains_customer_message_content: false
  }
  const bytes = new TextEncoder().encode(`${JSON.stringify(receipt, null, 2)}\n`)
  const receiptSha256 = await sha256(bytes)
  const key = `${PREFIX}/${checkedAt.slice(0, 10)}/${checkedAt.replace(/[-:.]/g, '')}.json`
  await env.ARCHIVE.put(key, bytes, { httpMetadata: { contentType: 'application/json' } })
  const state = {
    schema: `${SENTINEL_SCHEMA}-state`, updated_at_utc: checkedAt, ok,
    consecutive_failures: consecutiveFailures, latest_attestation_key: key,
    latest_attestation_sha256: receiptSha256
  }
  await env.ARCHIVE.put(`${PREFIX}/STATE.json`, `${JSON.stringify(state, null, 2)}\n`, {
    httpMetadata: { contentType: 'application/json' }
  })
  const latest = {
    schema: `${SENTINEL_SCHEMA}-pointer`, updated_at_utc: checkedAt, ok,
    consecutive_failures: consecutiveFailures,
    attestation: { bucket: 'omar-private-archive', key, sha256: receiptSha256 },
    expected_release: receipt.expected_release
  }
  await env.ARCHIVE.put(`${PREFIX}/LATEST.json`, `${JSON.stringify(latest, null, 2)}\n`, {
    httpMetadata: { contentType: 'application/json' }
  })
  return receipt
}

function json(value, status = 200) {
  return new Response(`${JSON.stringify(value, null, 2)}\n`, {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store', 'x-content-type-options': 'nosniff' }
  })
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url)
    if (request.method !== 'GET' || url.pathname !== '/health') {
      return json({ ok: false, error: 'not_found' }, 404)
    }
    const latestObject = await env.ARCHIVE.get(`${PREFIX}/LATEST.json`)
    const latest = latestObject ? await latestObject.json() : null
    return json({
      ok: latest?.ok === true, schema: SENTINEL_SCHEMA, schedule: 'every_5_minutes',
      latest: latest ? {
        updated_at_utc: String(latest.updated_at_utc || ''), ok: latest.ok === true,
        consecutive_failures: Number(latest.consecutive_failures || 0),
        attestation_sha256: String(latest.attestation?.sha256 || '')
      } : null,
      expected_release: { release_id: RELEASE_ID,
        content_fingerprint_sha256: CONTENT_FINGERPRINT,
        release_manifest_sha256: RELEASE_MANIFEST }
    }, latest?.ok === true ? 200 : 503)
  },
  async scheduled(controller, env) {
    const receipt = await runSentinel(env, {
      trigger: 'scheduled', now: controller?.scheduledTime || Date.now()
    })
    if (!receipt.ok) throw new Error('scv_instagram_drift_sentinel_failed')
  }
}

export { CONTENT_FINGERPRINT, RELEASE_ID, RELEASE_MANIFEST, SENTINEL_SCHEMA,
  VISIBLE_MODEL, evaluateEndpoint, runSentinel }
