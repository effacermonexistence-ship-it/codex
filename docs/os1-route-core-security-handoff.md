# OS-1 route-core security engineering handoff

## Status

**UNVERIFIED — public gateway controls implemented; end-to-end release approval blocked on missing Mac Runtime and private services.**

This branch establishes the server boundary that can be verified without
placing any proprietary routing material in the repository. It does not claim
that OS-1 is unhackable or that black-box behavioral extraction is eliminated.

## Implemented architecture

```text
Mac Runtime
  │ authenticated task / signed result binding
  ▼
OS-1 Route Gateway (this package)
  ├── AUTH_SERVICE              identity + device binding
  ├── DEVICE_REGISTRY           registered P-256 public key
  ├── PRIVATE_ROUTE_CORE        private RCC/REVAS decision service
  ├── RESULT_EVALUATOR          independent artifact verification
  └── EXECUTIONS Durable Object nonce/sequence/result state
```

The gateway never receives internal reasoning from the private route service.
Its strict parser accepts only `status` or the minimal
`provider/action/permission_profile` decision. Any extra field fails closed.
The response builder accepts only an eight-field ticket or a complete marker.

### Cryptographic split

- Server tickets use Ed25519. Only the server private key signs; clients embed
  a public verification key.
- Result reports are signed by the device P-256 key. The signed bytes bind
  `execution_id`, `sequence`, `nonce`, `result_hash`, and `artifact_ref`.
- No symmetric signing secret is shipped to the client.
- Device signatures prove possession of the registered device key, not that a
  rooted client executed honestly. Independent server-side artifact evaluation
  is therefore mandatory.

### Result trust flow

1. Verify the server ticket signature and expiry.
2. Verify the authenticated device and its P-256 result signature.
3. Atomically claim the ticket nonce and sequence in a per-execution Durable
   Object.
4. Ask `RESULT_EVALUATOR` to fetch and verify the private artifact.
5. Compare the evaluator's verified hash with the client-bound hash using a
   timing-safe comparison.
6. Pass only the evaluator's bounded outcome to `PRIVATE_ROUTE_CORE`.
7. Persist the next ticket or completion response before returning it. An
   identical retry after finalization receives the exact stored response; a
   concurrent duplicate or changed replay fails.

## Red-team acceptance mapping

| Requirement | Implemented evidence | Remaining release blocker |
| --- | --- | --- |
| P1-1 delivery hygiene / T1 | Gateway emits only the eight ticket fields; semantic fields are enum-bounded; protected canary denylist is a secret. | Capture the real Mac Runtime → Codex/Claude stdin/socket payload. No Mac Runtime exists in this repository. |
| P1-2 injection isolation / T4 | User task is tagged `untrusted_user_data`; internal decision outputs reject every extra field; public egress is allowlisted. | The private RCC/REVAS service must implement role/data separation and pass an end-to-end injection suite. |
| P1-3 opaque egress / T3 | One fixed-shape error response; bounded JSON; logs contain only event class and request ID; internal field names never pass the public parser. | Run malformed-input sweeps against deployed auth/private/evaluator services and verify network-level headers, size buckets, and timing. |
| P1-4 result integrity / T5 | Ed25519 ticket verification, P-256 device signature, independent evaluator contract, timing-safe hash match, atomic nonce/sequence ledger, idempotent response persistence. | Secure Enclave client implementation, real device attestation/revocation, evaluator implementation, and active oracle measurements are absent. |
| P1-5 build hygiene / T7 | Client artifact scanner rejects forbidden paths/content, high-entropy tokens, and symlinks without printing leaked content. A separately controlled production policy can supply real protected fingerprints. Scanner behavior is tested. | Run it on an actual signed `.app` and every updater package, then sign and retain each report. No client release artifact is present, so T7 cannot pass yet. |
| P2-1 device binding | Registry and P-256 possession contracts exist. | Secure Enclave key generation, attestation validation, DPoP/mTLS, and per-device revocation service. |
| P2-2 asymmetric tickets | Implemented with Ed25519 PKCS#8/SPKI keys. | Production key rotation and overlapping verification-key rollout procedure. |
| P2-3 atomic result submission | SQLite Durable Object state enforces sequence, nonce, result hash, and one stored response. | Cloudflare integration/concurrency test against a deployed namespace. |
| P2-4 extraction resistance | None claimed. | Account/global budgets, distributed/Sybil detection, cost-bound identity and measured extraction-query threshold. |
| P2-5 side-channel normalization | Fixed error status/body and no diagnostic headers. | Success payload bucketing and measured response-time/size normalization. |

## Automated evidence in this branch

The test suite currently covers:

- strict request and internal service schemas;
- rejection of route-core over-disclosure;
- Ed25519 ticket tamper detection;
- bounded streaming JSON input without trusting `Content-Length`;
- one opaque fixed-shape error response;
- delivery canary failure behavior;
- nonce replay with altered result content;
- rejection of concurrent duplicates and cross-device stored-response replay;
- idempotent return of the stored next-step response after finalization; and
- release artifact scanning without echoing protected fragments.

CI also regenerates Wrangler bindings, type-checks the Worker, and performs a
Cloudflare dry-run bundle. A successful dry run is not a production deployment.

## Private service implementation contracts

### `PRIVATE_ROUTE_CORE`

The service must keep all RCC/REVAS material internally and return one of:

```json
{ "status": "complete" }
```

```json
{
  "status": "step",
  "provider": "codex",
  "action": "agent_run",
  "permission_profile": "workspace_write"
}
```

Reasoning, scores, candidates, policy identifiers, thresholds, prompts,
versions, and future steps are prohibited. The gateway rejects rather than
redacts an over-broad response so a regression cannot become a silent leak.

### `RESULT_EVALUATOR`

The evaluator receives an R2 reference and expected SHA-256 hash, fetches the
artifact itself, and returns only a bounded outcome and its independently
verified hash. It must never accept a client `success` boolean or a client score
as authoritative.

## Client artifact gate

Run the gate only with explicit release paths:

```bash
pnpm --dir products/os1-route-core scan:client -- \
  /absolute/path/to/OS-1.app \
  /absolute/path/to/OS-1-update.pkg
```

High-entropy allowlisting uses SHA-256 fingerprints so an allowlist does not
need to contain a token verbatim. The allowlist must cover only intentionally
public material such as the ticket verification public key. Scanner findings
report fingerprints and offsets, never the matched protected string.

For a release, point `OS1_CLIENT_SCAN_POLICY_PATH` at a separately controlled
policy containing real protected prompt fingerprints and constants. Do not
commit that private policy to this repository.

## Release decision

This branch is an implementation foundation, not a release approval. Promote
from **UNVERIFIED** only after the five P1 rows above have real end-to-end
evidence. Behavioral surrogate routing and decision-boundary approximation
remain structural residual risks and must be measured and documented rather
than marked resolved.
