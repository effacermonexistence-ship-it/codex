# OS-1 Route Gateway security boundary

This package is the public server gateway for the OS-1 step-ticket protocol. It
does **not** contain RCC/REVAS routing prompts, weights, thresholds, evaluation
rubrics, datasets, or policy logic.

The gateway accepts an authenticated user task, sends it to a separately
deployed private route service as explicitly untrusted data, and emits either:

- one Ed25519-signed eight-field execution ticket; or
- `{ "status": "complete" }`.

All failures use one opaque fixed-shape body. Extra fields from internal
services are rejected rather than silently removed.

## Required private service bindings

| Binding | Required response |
| --- | --- |
| `AUTH_SERVICE` | `{ subject, device_id }` |
| `DEVICE_REGISTRY` | `{ subject, device_id, p256_public_jwk }` |
| `PRIVATE_ROUTE_CORE` | `{ status: "complete" }` or the minimal step decision |
| `RESULT_EVALUATOR` | `{ outcome, verified_artifact_hash }` |

The private route and result evaluator Workers are intentionally absent from
this public package. The evaluator must fetch the artifact from private storage
and independently verify its hash and outcome. A client-provided success/fail
claim is never accepted as a routing input.

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

The current release posture is **UNVERIFIED** because there is no Mac Runtime
release candidate or deployed private route/evaluator implementation to run the
T1/T4/T5/T7 acceptance tests against. See
[`docs/os1-route-core-security-handoff.md`](../../docs/os1-route-core-security-handoff.md).
