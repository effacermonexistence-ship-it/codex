#!/usr/bin/env node
const fs = require('fs')
const os = require('os')
const path = require('path')

const {
  debugAccountIdentity,
  isDebugAccountPacket,
  pauseDebugAccountsEnabled,
  isPausedForPacket
} = require(path.join(__dirname, 'scv-pause-gate.js'))

const LOCK_VERSION = 'scv-pause-gate-harness-2026-08-25-v4-exact-debug-identity-pair'

function runHarness() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'scv-pause-gate-'))
  let checked = 0
  const ok = (condition, label, detail = '') => {
    checked += 1
    if (!condition) throw new Error(`${label}${detail ? `:${detail}` : ''}`)
  }

  try {
    const production = {
      RAILWAY_ENVIRONMENT_NAME: 'production',
      SCV_RELEASE_MODE: 'production',
      SCV_ROOT: root,
      SCV_PERSIST_ROOT: root,
      SCV_PAUSE_ALL: '0',
      SCV_PAUSE_NON_TEST: '0',
      SCV_FAST_TARGET_USERNAMES: 'public_sanitized_identifier',
      SCV_FAST_TARGET_CONTACT_IDS: 'public_sanitized_identifier'
    }

    ok(pauseDebugAccountsEnabled(production) === true, 'production_debug_pause_defaults_on')
    ok(isPausedForPacket({ instagram_username: 'public_sanitized_identifier', contact_id: 'public_sanitized_identifier' }, production) === true, 'exact_omar_pair_held')
    ok(isPausedForPacket({ instagram_username: 'OMAL_SYSTEM', contact_id: 'public_sanitized_identifier' }, production) === true, 'exact_alias_contact_pair_held')
    ok(isPausedForPacket({ instagram_username: 'public_sanitized_identifier', contact_id: 'x' }, production) === false, 'omar_username_only_does_not_expand_debug_scope')
    ok(isPausedForPacket({ instagram_username: 'public_sanitized_identifier', contact_id: 'public_sanitized_identifier' }, production) === false, 'omar_contact_only_does_not_expand_debug_scope')
    ok(isPausedForPacket({ instagram_username: 'public_sanitized_identifier', contact_id: '2001', text: 'public_sanitized_identifier sent me here' }, production) === false, 'message_mention_does_not_match_identity')
    ok(isDebugAccountPacket({ instagram_username: 'customer', contact_id: '2002' }, production) === false, 'ordinary_identity_not_debug')
    ok(debugAccountIdentity(production).usernames.has('public_sanitized_identifier'), 'default_debug_username_present')

    for (let index = 0; index < 50; index += 1) {
      ok(
        isPausedForPacket({ instagram_username: `lead.${index}`, contact_id: String(900000 + index) }, production) === false,
        `real_account_${index}_flows`
      )
    }

    const staging = {
      RAILWAY_ENVIRONMENT_NAME: 'staging',
      SCV_RELEASE_MODE: 'staging',
      SCV_ROOT: root,
      SCV_PERSIST_ROOT: root,
      SCV_PAUSE_ALL: '0',
      SCV_PAUSE_NON_TEST: '1',
      SCV_PAUSE_DEBUG_ACCOUNTS: '0',
      SCV_PAUSE_ALLOW_USERNAMES: 'public_sanitized_identifier',
      SCV_PAUSE_ALLOW_CONTACT_IDS: 'public_sanitized_identifier'
    }
    ok(isPausedForPacket({ instagram_username: 'public_sanitized_identifier', contact_id: 'public_sanitized_identifier' }, staging) === false, 'isolated_staging_debug_flows')
    ok(isPausedForPacket({ instagram_username: 'public_sanitized_identifier', contact_id: '2003' }, staging) === true, 'isolated_staging_real_lead_held')

    const armedStaging = {
      ...staging,
      SCV_STAGING_CAPABILITY_MODE: 'provider_bound',
      SCV_STAGING_REAL_E2E_ARMED: '1',
      SCV_FAST_TARGET_USERNAMES: 'public_sanitized_identifier',
      SCV_FAST_TARGET_CONTACT_IDS: 'public_sanitized_identifier',
      SCV_PAUSE_ALLOW_USERNAMES: '',
      SCV_PAUSE_ALLOW_CONTACT_IDS: ''
    }
    ok(isPausedForPacket({
      instagram_username: 'public_sanitized_identifier', contact_id: 'public_sanitized_identifier'
    }, armedStaging) === false, 'armed_staging_exact_omar_pair_flows')
    ok(isPausedForPacket({
      instagram_username: 'public_sanitized_identifier', contact_id: 'wrong-contact'
    }, armedStaging) === true, 'armed_staging_username_only_match_held')
    ok(isPausedForPacket({
      instagram_username: 'wrong.username', contact_id: 'public_sanitized_identifier'
    }, armedStaging) === true, 'armed_staging_contact_only_match_held')
    ok(isPausedForPacket({
      instagram_username: '', contact_id: 'public_sanitized_identifier'
    }, armedStaging) === true, 'armed_staging_missing_username_held')
    ok(isPausedForPacket({
      instagram_username: 'public_sanitized_identifier', contact_id: ''
    }, armedStaging) === true, 'armed_staging_missing_contact_held')
    ok(isPausedForPacket({
      instagram_username: 'public_sanitized_identifier', contact_id: 'public_sanitized_identifier'
    }, {
      ...armedStaging,
      RAILWAY_ENVIRONMENT_NAME: 'production'
    }) === true, 'mixed_production_staging_identity_fails_closed')

    const hardStop = { ...production, SCV_PAUSE_ALL: '1' }
    ok(isPausedForPacket({ instagram_username: 'public_sanitized_identifier', contact_id: '2004' }, hardStop) === true, 'pause_all_hpublic_sanitized_identifiers_real')
    ok(isPausedForPacket({ instagram_username: 'public_sanitized_identifier', contact_id: 'public_sanitized_identifier' }, hardStop) === true, 'pause_all_hpublic_sanitized_identifiers_debug')

    return { ok: true, lock_version: LOCK_VERSION, checked }
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
}

if (require.main === module) {
  try {
    console.log(JSON.stringify(runHarness(), null, 2))
  } catch (error) {
    console.error(JSON.stringify({ ok: false, error: String(error?.message || error) }, null, 2))
    process.exit(1)
  }
}

module.exports = { LOCK_VERSION, runHarness }
