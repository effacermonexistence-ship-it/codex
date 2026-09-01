#!/usr/bin/env node
// ============================================================
// SCV CAPABILITY CANARY — "지금 되는 보이스/이미지가 나중에 조용히 죽으면?" (Ben).
//
// Voice transcription and vision depend on EXTERNAL moving parts (OpenAI endpoints,
// model behavior, auth). They are fail-open by public_sanitized_identifier, which means they can die
// SILENTLY — the funnel keeps replying, just dumber. This canary runs the REAL
// transcription and vision paths against baked-in fixtures on boot and every
// interval, and screams in the logs when a capability regresses:
//   scv_capability_check {voice_ok, vision_ok, ...}   — heartbeat
//   SCV_CAPABILITY_ALERT ...                          — regression, loud
// Kill switch: SCV_CAPABILITY_CANARY=0.
// ============================================================
const fs = require('fs')
const path = require('path')
const { transcribeInboundAudio, describeImageBuffer } = require(path.join(__dirname, 'codex-dm-runner.js'))

const CANARY_ENABLED = String(process.env.SCV_CAPABILITY_CANARY || '1').trim() !== '0'
const CANARY_INTERVAL_MS = Number(process.env.SCV_CAPABILITY_CANARY_INTERVAL_MS || 6 * 60 * 60 * 1000)
const VOICE_FIXTURE = path.join(__dirname, 'canary-voice.m4a')
const IMAGE_FIXTURE = path.join(__dirname, 'canary-image.png')

async function checkOnce(options = {}) {
  const result = { type: 'scv_capability_check', at: new Date().toISOString(), voice_ok: false, vision_ok: false, voice_preview: '', vision_preview: '' }
  try {
    const voiceBuf = fs.readFileSync(VOICE_FIXTURE)
    const transcript = await transcribeInboundAudio(voiceBuf, 'audio/mp4')
    result.voice_preview = String(transcript || '').slice(0, 60)
    // The fixture says "snake tattoo test" — any non-empty transcript containing a
    // recognizable word proves the path end-to-end.
    result.voice_ok = /snake|tattoo|test/i.test(String(transcript || ''))
  } catch (err) {
    result.voice_error = String(err?.message || err).slice(0, 100)
  }
  try {
    const imgBuf = fs.readFileSync(IMAGE_FIXTURE)
    const desc = await describeImageBuffer(imgBuf, 'image/png')
    result.vision_preview = String(desc || '').slice(0, 60)
    // The fixture is big block text "SNAKE" — the vision prompt names motifs, so a
    // faithful read mentions snake/text/letters. Non-empty alone would let refusal
    // text or pure hallucination pass as vision_ok.
    result.vision_ok = /snake|text|letter|word/i.test(String(desc || ''))
  } catch (err) {
    result.vision_error = String(err?.message || err).slice(0, 100)
  }

  if (options.silent !== true) console.log(JSON.stringify(result))
  if (options.silent !== true && (!result.voice_ok || !result.vision_ok)) {
    console.error(JSON.stringify({
      type: 'SCV_CAPABILITY_ALERT',
      alert: 'capability_regression',
      voice_ok: result.voice_ok,
      vision_ok: result.vision_ok,
      detail: result
    }))
  }
  return result
}

async function main() {
  if (!CANARY_ENABLED) {
    console.log(JSON.stringify({ type: 'scv_capability_canary_disabled' }))
    if (process.argv.includes('--loop')) setInterval(() => {}, 1 << 30)
    return
  }
  if (!process.env.OPENAI_API_KEY) {
    console.log(JSON.stringify({ type: 'scv_capability_canary_waiting_for_key' }))
    if (process.argv.includes('--loop')) setInterval(() => {}, 1 << 30)
    return
  }
  const run = () => checkOnce().catch((err) => console.error(JSON.stringify({ type: 'SCV_CAPABILITY_ALERT', alert: 'canary_crashed', error: String(err?.message || err) })))
  await run()
  if (process.argv.includes('--loop')) setInterval(run, CANARY_INTERVAL_MS)
}

if (require.main === module) {
  main().catch((err) => {
    console.error(JSON.stringify({ ok: false, error: String(err?.message || err) }))
    process.exit(1)
  })
}

module.exports = { checkOnce }
