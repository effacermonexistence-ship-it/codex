import assert from 'node:assert/strict'
import test from 'node:test'
import { CONTENT_FINGERPRINT, RELEASE_ID, RELEASE_MANIFEST, VISIBLE_MODEL,
  evaluateEndpoint } from './src/index.js'

const target = { name: 'production', mode: 'production' }
function healthyBody() {
  return {
    ok: true, fail_close_active: false, preflight_verified: true,
    release: { ok: true, mode: 'production', release_phase: 'active', phase_ready: true,
      release_id: RELEASE_ID, content_fingerprint_sha256: CONTENT_FINGERPRINT,
      release_manifest_sha256: RELEASE_MANIFEST },
    drift: { critical_ok: true, critical_alert_count: 0,
      operational_alert_count: 1, age_ms: 30_000 },
    capability_canary: { required: true, ok: true, voice_ok: true, vision_ok: true,
      visible_model_ok: true, provider_model: VISIBLE_MODEL, age_ms: 60_000 },
    model_identity: { visible_model: VISIBLE_MODEL, executor: 'openai_responses',
      api: 'responses_v1', enforced: true, contract_ok: true,
      cross_model_fallback_allowed: false },
    behavior_contract: { ok: true, failures: [] }
  }
}

test('accepts exact healthy v124 with an operational alert', () => {
  const result = evaluateEndpoint(target, 200, healthyBody())
  assert.equal(result.ok, true)
  assert.equal(result.operational_alert_count, 1)
})
test('rejects fingerprint drift', () => {
  const body = healthyBody(); body.release.content_fingerprint_sha256 = '0'.repeat(64)
  assert.ok(evaluateEndpoint(target, 200, body).reasons.includes('content_fingerprint'))
})
test('rejects failed and stale capabilities', () => {
  const body = healthyBody(); body.capability_canary.voice_ok = false
  body.capability_canary.age_ms = 10_000_000
  const result = evaluateEndpoint(target, 200, body)
  assert.ok(result.reasons.includes('voice_capability'))
  assert.ok(result.reasons.includes('capability_canary_stale'))
})
test('rejects critical drift', () => {
  const body = healthyBody(); body.drift.critical_ok = false
  body.drift.critical_alert_count = 1
  const result = evaluateEndpoint(target, 200, body)
  assert.ok(result.reasons.includes('critical_drift'))
  assert.ok(result.reasons.includes('critical_drift_alerts'))
})
