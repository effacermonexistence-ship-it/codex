#!/usr/bin/env node

import crypto from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'
import { TextDecoder } from 'node:util'
import { fileURLToPath } from 'node:url'

const RELEASE_ID = 'scv-instagram-public-sanitized-20260831-v1'
const EXPECTED_NODE = 'v20.20.2'
const EXPECTED_DESCRIPTOR_SHA256 =
  '280b13b8fe0d1b9e0d8473f20b403ffa88b7b34d778a50338e081333af1acff7'
const EXPECTED_DESCRIPTOR_BYTES = 39910
const EXPECTED_FINGERPRINT =
  '7521b2b785fcae44bccefbe9d28089519af01898b3ef7c0b8a8ee2989cce155e'
const EXPECTED_INVENTORY_FILES = 229
const EXPECTED_INVENTORY_BYTES = 5231797
const EXPECTED_TOTAL_FILES = 230
const EXPECTED_TOTAL_BYTES = 5271707
const EXPECTED_PROVENANCE_SHA256 =
  '8b5772bbc3616847f51f51ca61aab739c292b1824db4177c788d108a2a4f2ff9'
const EXPECTED_PROVENANCE_BYTES = 3512
const EXPECTED_SANITIZER_SHA256 =
  '48dd71ea072c7fc84210d5e09dd9b68c58944ebfa31ae4ea1dfc81bd226f7ed2'
const EXPECTED_CUSTODY_SHA256 =
  '03a0f820bd4176bab3e02632d29b90de619bdbce001108866842ac76aa76db85'
const DESCRIPTOR_NAME = 'SCV_SINGLE_RELEASE.json'
const SHA256_RE = /^[a-f0-9]{64}$/u
const decoder = new TextDecoder('utf-8', { fatal: true })

const EXPECTED_RAILWAY = {
  project_id: '00000000-0000-4000-8000-000000000001',
  production: {
    environment_id: '00000000-0000-4000-8000-000000000002',
    service_id: '00000000-0000-4000-8000-000000000003'
  },
  staging: {
    environment_id: '00000000-0000-4000-8000-000000000004',
    service_id: '00000000-0000-4000-8000-000000000005'
  }
}

const EXPECTED_PERSISTENCE = {
  root: '/data',
  production_namespace: 'public-sanitized-do-not-deploy',
  staging_namespace: 'public-sanitized-do-not-deploy-staging'
}

const DENIED_SEGMENTS = new Set([
  '.git', '.bkit', '.omc', 'node_modules', 'ops', 'artifacts',
  'inbox', 'outbox', 'reactbox', 'reactbox_done', 'reactbox_failed',
  'logs', 'thread-state', 'thread-history', 'control-events',
  'control-decisions', 'control-locks', 'outbox-idempotency'
])

const DENIED_FILES = new Set([
  '.env', '.npmrc', '.pypirc', '.netrc', 'credentials', 'credentials.json',
  'secrets', 'secrets.json', 'id_rsa', 'id_ed25519',
  'scv_golden_production_release.json',
  'scv_golden_snapshot_manifest.json',
  'scv_immutable_drift_seal.json',
  'scv-production-entry.js',
  'scv-production-activation-latch.js'
])

function fail(message) {
  throw new Error(message)
}

function check(condition, message) {
  if (!condition) fail(message)
}

function sha256(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex')
}

function identity(stat) {
  return {
    dev: stat.dev,
    ino: stat.ino,
    size: stat.size,
    mtimeMs: stat.mtimeMs,
    ctimeMs: stat.ctimeMs,
    nlink: stat.nlink
  }
}

function sameIdentity(left, right) {
  return Object.keys(left).every(key => Object.is(left[key], right[key]))
}

function readStable(file, label, maxBytes = 64 * 1024 * 1024) {
  const before = fs.lstatSync(file)
  check(before.isFile() && !before.isSymbolicLink(), `${label}: regular file required`)
  check(before.nlink === 1, `${label}: hardlink forbidden`)
  check(before.size <= maxBytes, `${label}: file too large`)
  const fd = fs.openSync(file, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0))
  try {
    const opened = fs.fstatSync(fd)
    check(sameIdentity(identity(before), identity(opened)), `${label}: identity changed before read`)
    const bytes = fs.readFileSync(fd)
    const after = fs.fstatSync(fd)
    check(sameIdentity(identity(opened), identity(after)), `${label}: identity changed during read`)
    check(bytes.length === after.size, `${label}: byte count changed during read`)
    return { bytes, identity: identity(after), sha256: sha256(bytes) }
  } finally {
    fs.closeSync(fd)
  }
}

function parseJson(record, label) {
  try {
    return JSON.parse(record.bytes.toString('utf8'))
  } catch (error) {
    fail(`${label}: invalid JSON (${error.message})`)
  }
}

function portableKey(value) {
  return value.normalize('NFC').toLocaleLowerCase('en-US')
}

function safePath(value, label) {
  check(typeof value === 'string' && value.length > 0, `${label}: empty path`)
  check(value.normalize('NFC') === value, `${label}: path must be NFC`)
  check(!value.includes('\\'), `${label}: backslash forbidden`)
  check(!path.posix.isAbsolute(value), `${label}: absolute path forbidden`)
  check(path.posix.normalize(value) === value, `${label}: non-canonical path`)
  const segments = value.split('/')
  check(segments.every(segment => segment && segment !== '.' && segment !== '..'),
    `${label}: unsafe segment`)
  return segments
}

function denylisted(value, segments) {
  const folded = segments.map(portableKey)
  if (folded.some(segment => DENIED_SEGMENTS.has(segment))) return true
  const name = folded.at(-1)
  if (DENIED_FILES.has(name)) return true
  if (name.startsWith('.env.')) return true
  if (/\.(?:key|p12|pfx)$/u.test(name)) return true
  if (/private.*\.pem$/u.test(name)) return true
  return false
}

function walk(root) {
  const rootStat = fs.lstatSync(root)
  check(rootStat.isDirectory() && !rootStat.isSymbolicLink(), 'runtime: safe directory required')
  const files = new Map()
  const directories = new Set()
  function visit(directory, relativeDirectory = '') {
    const entries = fs.readdirSync(directory, { withFileTypes: true })
      .sort((left, right) => left.name.localeCompare(right.name))
    for (const entry of entries) {
      const relative = relativeDirectory ? `${relativeDirectory}/${entry.name}` : entry.name
      const absolute = path.join(directory, entry.name)
      const stat = fs.lstatSync(absolute)
      check(!stat.isSymbolicLink() && !entry.isSymbolicLink(), `${relative}: symlink forbidden`)
      const segments = safePath(relative, relative)
      check(!denylisted(relative, segments), `${relative}: denylisted surface`)
      if (stat.isDirectory() && entry.isDirectory()) {
        directories.add(relative)
        visit(absolute, relative)
      } else {
        check(stat.isFile() && entry.isFile(), `${relative}: special file forbidden`)
        check(stat.nlink === 1, `${relative}: hardlink forbidden`)
        files.set(relative, { absolute, identity: identity(stat) })
      }
    }
  }
  visit(root)
  return { files, directories }
}

function scanPublicText(relative, bytes) {
  let text
  try {
    text = decoder.decode(bytes)
  } catch {
    return
  }
  check(!/-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----/u.test(text),
    `${relative}: private key marker`)
  check(!/\/Users\/(?!REDACTED\/PRIVATE_PATH)/u.test(text),
    `${relative}: private user path`)
  check(!/CloudDocs/iu.test(text), `${relative}: CloudDocs path`)
  const emails = text.match(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/giu) || []
  check(emails.every(email => email.toLowerCase().endsWith('@example.invalid')),
    `${relative}: non-placeholder email`)
  const secretPatterns = [
    /AKIA[0-9A-Z]{16}/gu,
    /gh[pousr]_[A-Za-z0-9]{20,}/gu,
    /Bearer\s+eyJ[A-Za-z0-9._-]{20,}/gu,
    /(?<![A-Za-z0-9])sk-(?:proj-)?[A-Za-z0-9_-]{20,}/gu
  ]
  for (const expression of secretPatterns) {
    for (const match of text.matchAll(expression)) {
      check(/(?:not-a-real|fake|fixture|example|test)/iu.test(match[0]),
        `${relative}: credential-shaped value`)
    }
  }
}

function verifyDescriptor(record, runtimeWalk) {
  check(record.bytes.length === EXPECTED_DESCRIPTOR_BYTES, 'descriptor: byte count mismatch')
  check(record.sha256 === EXPECTED_DESCRIPTOR_SHA256, 'descriptor: SHA-256 mismatch')
  const descriptor = parseJson(record, 'descriptor')
  check(descriptor.release_id === RELEASE_ID, 'descriptor: release id mismatch')
  check(descriptor.content_fingerprint_sha256 === EXPECTED_FINGERPRINT,
    'descriptor: fingerprint mismatch')
  check(descriptor.runtime?.node_version === EXPECTED_NODE, 'descriptor: Node mismatch')
  check(JSON.stringify(descriptor.railway) === JSON.stringify(EXPECTED_RAILWAY),
    'descriptor: production target IDs were not neutralized')
  check(JSON.stringify(descriptor.persistence) === JSON.stringify(EXPECTED_PERSISTENCE),
    'descriptor: persistence namespaces were not neutralized')
  check(Array.isArray(descriptor.files) && descriptor.files.length === EXPECTED_INVENTORY_FILES,
    'descriptor: inventory count mismatch')

  let inventoryBytes = 0
  let previous = ''
  const portable = new Set([portableKey(DESCRIPTOR_NAME)])
  const expectedPaths = new Set([DESCRIPTOR_NAME])
  for (const [index, entry] of descriptor.files.entries()) {
    const label = `descriptor.files[${index}]`
    const segments = safePath(entry.path, `${label}.path`)
    check(!denylisted(entry.path, segments), `${label}.path: denylisted`)
    check(entry.path !== DESCRIPTOR_NAME, `${label}.path: descriptor self-entry`)
    check(previous === '' || previous < entry.path, `${label}.path: unsorted inventory`)
    const key = portableKey(entry.path)
    check(!portable.has(key), `${label}.path: portable collision`)
    check(SHA256_RE.test(entry.sha256), `${label}.sha256: invalid`)
    check(Number.isSafeInteger(entry.bytes) && entry.bytes >= 0, `${label}.bytes: invalid`)
    portable.add(key)
    expectedPaths.add(entry.path)
    previous = entry.path
    inventoryBytes += entry.bytes
    const actual = runtimeWalk.files.get(entry.path)
    check(actual, `${entry.path}: missing`)
    const fileRecord = readStable(actual.absolute, entry.path)
    check(fileRecord.bytes.length === entry.bytes, `${entry.path}: byte count mismatch`)
    check(fileRecord.sha256 === entry.sha256, `${entry.path}: SHA-256 mismatch`)
    scanPublicText(entry.path, fileRecord.bytes)
  }
  check(inventoryBytes === EXPECTED_INVENTORY_BYTES, 'descriptor: inventory bytes mismatch')
  check(sha256(Buffer.from(JSON.stringify(descriptor.files), 'utf8')) === EXPECTED_FINGERPRINT,
    'descriptor: computed fingerprint mismatch')
  check(runtimeWalk.files.size === EXPECTED_TOTAL_FILES, 'runtime: physical file count mismatch')
  check(expectedPaths.size === EXPECTED_TOTAL_FILES, 'runtime: expected path count mismatch')
  for (const actual of runtimeWalk.files.keys()) {
    check(expectedPaths.has(actual), `${actual}: untracked runtime file`)
  }
  let totalBytes = 0
  for (const file of runtimeWalk.files.values()) totalBytes += file.identity.size
  check(totalBytes === EXPECTED_TOTAL_BYTES, 'runtime: physical bytes mismatch')
  return descriptor
}

function finalReverify(runtimeRoot, initialWalk, externalRecords) {
  const finalWalk = walk(runtimeRoot)
  check(finalWalk.files.size === initialWalk.files.size, 'runtime: file count changed')
  for (const [relative, initial] of initialWalk.files) {
    const final = finalWalk.files.get(relative)
    check(final, `${relative}: disappeared during verification`)
    check(sameIdentity(initial.identity, final.identity), `${relative}: path identity changed`)
    const record = readStable(final.absolute, `${relative} final`)
    check(sameIdentity(initial.identity, record.identity), `${relative}: content identity changed`)
  }
  for (const external of externalRecords) {
    const final = readStable(external.file, `${external.label} final`, 2 * 1024 * 1024)
    check(sameIdentity(external.record.identity, final.identity),
      `${external.label}: identity changed`)
    check(external.record.sha256 === final.sha256, `${external.label}: content changed`)
  }
}

function main() {
  check(process.version === EXPECTED_NODE,
    `node: expected ${EXPECTED_NODE}; found ${process.version}`)
  const scriptDirectory = path.dirname(fileURLToPath(import.meta.url))
  const productRoot = path.resolve(scriptDirectory, '..')
  const runtimeRoot = path.join(productRoot, 'runtime')
  const provenanceFile = path.join(
    productRoot, 'provenance', 'releases', `${RELEASE_ID}.json`
  )
  const sanitizerFile = path.join(productRoot, 'scripts', 'sanitize-public-mirror.mjs')
  const custodyFile = path.join(
    productRoot, 'provenance', 'private-custody', 'SCV_V122_PRIVATE_CUSTODY_MANIFEST.json'
  )

  const provenanceRecord = readStable(provenanceFile, 'provenance', 1024 * 1024)
  check(provenanceRecord.bytes.length === EXPECTED_PROVENANCE_BYTES,
    'provenance: byte count mismatch')
  check(provenanceRecord.sha256 === EXPECTED_PROVENANCE_SHA256,
    'provenance: SHA-256 mismatch')
  const provenance = parseJson(provenanceRecord, 'provenance')
  check(provenance.release_id === RELEASE_ID, 'provenance: release id mismatch')
  check(provenance.status === 'public-source-mirror-only', 'provenance: status mismatch')
  check(provenance.deployment_allowed === false, 'provenance: deployment must be forbidden')
  check(provenance.safety?.customer_identifiers_included === false,
    'provenance: customer identifier claim missing')
  check(provenance.source_authority?.public_git_eligible === false,
    'provenance: private source classification missing')

  const sanitizerRecord = readStable(sanitizerFile, 'sanitizer', 1024 * 1024)
  check(sanitizerRecord.sha256 === EXPECTED_SANITIZER_SHA256, 'sanitizer: SHA-256 mismatch')
  const custodyRecord = readStable(custodyFile, 'custody manifest', 1024 * 1024)
  check(custodyRecord.sha256 === EXPECTED_CUSTODY_SHA256,
    'custody manifest: SHA-256 mismatch')
  const custody = parseJson(custodyRecord, 'custody manifest')
  check(custody.data_classification?.public_git_eligible === false,
    'custody manifest: private classification missing')
  check(custody.data_classification?.contains_customer_derived_identifiers === true,
    'custody manifest: customer identifier classification missing')

  const runtimeWalk = walk(runtimeRoot)
  const descriptorPath = path.join(runtimeRoot, DESCRIPTOR_NAME)
  const descriptorRecord = readStable(descriptorPath, 'descriptor', 1024 * 1024)
  const descriptor = verifyDescriptor(descriptorRecord, runtimeWalk)
  finalReverify(runtimeRoot, runtimeWalk, [
    { file: provenanceFile, label: 'provenance', record: provenanceRecord },
    { file: sanitizerFile, label: 'sanitizer', record: sanitizerRecord },
    { file: custodyFile, label: 'custody manifest', record: custodyRecord }
  ])

  process.stdout.write(`${JSON.stringify({
    ok: true,
    release_id: descriptor.release_id,
    status: provenance.status,
    deployment_allowed: false,
    descriptor_sha256: EXPECTED_DESCRIPTOR_SHA256,
    content_fingerprint_sha256: EXPECTED_FINGERPRINT,
    inventory_files: EXPECTED_INVENTORY_FILES,
    physical_regular_files: EXPECTED_TOTAL_FILES,
    customer_identifiers_included: false,
    customer_message_content_included: false,
    private_user_paths_included: false,
    operational_email_included: false,
    private_key_markers: 0,
    runtime_snapshot_reverified: true
  }, null, 2)}\n`)
}

try {
  main()
} catch (error) {
  process.stderr.write(`${JSON.stringify({
    ok: false,
    error: error instanceof Error ? error.message : String(error)
  }, null, 2)}\n`)
  process.exitCode = 1
}
