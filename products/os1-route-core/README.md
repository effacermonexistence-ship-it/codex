# OS-1 Route Gateway security boundary

This package is the public server gateway for the OS-1 step-ticket protocol. It
does **not** contain RCC/REVAS routing prompts, weights, thresholds, evaluation
rubrics, datasets, or policy logic.

The gateway accepts an authenticated user task, sends it to a separately
deployed private route service as explicitly untrusted data, and emits either:

- one Ed25519-signed eight-field execution ticket; or
- `{ "status": "complete" }` or the opaque terminal `{ "status": "failed" }`.

All failures use one opaque fixed-shape body. Extra fields from internal
services are rejected rather than silently removed.

Auto routing also accepts a coarse `capacity_plan` for the two installed
backends. The private route core combines that user preference with a rolling
seven-day per-principal usage ledger and protected specialist rules. Counts,
weights, rule matches, and rationale never cross the private service boundary;
the client still receives only the signed eight-field ticket.

The same private decision assigns an execution tier through the ticket's
existing `action` field. The Mac runtime maps that tier to the configured Codex
or Claude model, but the private route state independently stores the expected
model and effort. REVAS rejects an artifact if a modified client substitutes a
different model, effort, action, permission, or executor contract. Rule terms,
weights, match state, scores, and future routes remain private.

## Required private service bindings

| Binding | Required response |
| --- | --- |
| `AUTH_SERVICE` | `{ subject, device_id }` |
| `DEVICE_REGISTRY` | `{ subject, device_id, p256_public_jwk }` |
| `PRIVATE_ROUTE_CORE` | `{ status: "complete" }` or the minimal step decision |

The private route core, device registry, authentication service, and result
evaluator are separate internal Workers. The private route core loads one
immutable policy bundle from access-restricted R2 and verifies the object bytes
against the SHA-256 pinned in its deployment configuration. It never follows a
mutable `latest` pointer at runtime. Policy contents are absent from the public
repository, gateway bundle, Mac application, package, ticket, and result
artifact. The evaluator is reachable from the private route core only, fetches
the original artifact from private R2, verifies object metadata and its hash,
and returns only an opaque outcome. A client-provided success/fail claim is
never accepted as a routing input.

The Mac runtime pins a public executor-contract version and hash. Codex receives
that generic contract through its developer-instruction channel; Claude Code
receives it through its appended system-prompt channel. The contract contains
execution hygiene only—not routing rules, scoring policy, thresholds, or future
steps. REVAS independently binds the artifact's backend, action, permission
profile, exact model, reasoning effort, and contract provenance to the
server-side route. New executions are also subject to a per-principal hourly
start budget; this raises automated extraction cost but does not eliminate
black-box behavioral approximation.

## Public package boundary

The public Mac package is built from an explicit file allowlist. It contains
only the universal GUI/CLI executables, public images, the ticket verification
key, public endpoint and executor configuration, and the upgrade cleanup
script. It does not contain a local routing core, RCC/REVAS source, policy
bundle, benchmark priors, prompt lineage, router state, scoring rules, or
fallback routing graph. The post-install migration removes the exact legacy
product-owned private-core directory left by older packages.

This construction protects source and policy contents because those bytes are
absent from the client. It cannot make the service "unhackable": a device owner
can observe inputs and the returned provider/action labels and may approximate
behavior through repeated queries. Server-side budgets and monitoring mitigate
that residual oracle risk.

## Local verification

```bash
pnpm install --frozen-lockfile
pnpm --dir products/os1-route-core types
pnpm --dir products/os1-route-core check
pnpm --dir products/os1-route-core test
pnpm --dir products/os1-route-core deploy:dry-run
```

Real keys and protected canary fragments belong in Cloudflare secrets. Copy
`.dev.vars.example` to an ignored `.dev.vars` only for local development; never
commit it.

The local hardened release candidate includes a universal Mac Runtime, Secure
Enclave device signing, private services, R2 artifact storage, a SHA-256-pinned
package format, and red-team contract tests. Distribution mode deliberately
fails unless Developer ID application/package identities and a notarization
profile are supplied. The network installer also refuses unsigned or
unnotarized packages. See
[`docs/os1-route-core-security-handoff.md`](../../docs/os1-route-core-security-handoff.md).
