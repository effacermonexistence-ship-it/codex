# OS One Cloudex EXO backend

This module adds the private two-Mac EXO cluster as an OS-1 execution
provider. It deliberately changes no product UI files. A future OS One
Cloudex interface calls the existing OS-1 execution endpoint; the existing
Mac Runtime on the selected Mac runs the local EXO adapter.

## Execution path

```text
OS One Cloudex UI
  -> OS-1 route gateway
  -> signed EXO inference ticket
  -> selected Mac's OS-1 Runtime (loopback only)
  -> local EXO API on :52415
  -> Pipeline/MlxRing placement with min_nodes=2
  -> Pro + Air inference
  -> signed result artifact in private R2
```

The public interface never receives a ZeroTier address, an EXO peer ID, or a
direct connection to either Mac. The Runtime only accepts an EXO endpoint at
`http://127.0.0.1:52415`, `http://localhost:52415`, or `http://[::1]:52415`.
EXO's private Pro-to-Air connection stays inside ZeroTier.

## UI contract

The existing `POST /v1/executions` request remains valid:

```json
{ "task": "Summarize these notes." }
```

The OS One Cloudex UI may request the local cluster explicitly:

```json
{
  "task": "Summarize these notes.",
  "capability_request": "local_exo"
}
```

This field is a request, not an authorization bypass. The private route policy
must set `local_exo_enabled` to `true`; otherwise the normal private routing
policy remains in control. When it is enabled, the issued ticket is bound to
exactly `provider: "exo"`, `action: "exo_inference"`, and
`permission_profile: "read_only"`. Any different provider/action pairing is
rejected by the gateway and by the Mac Runtime.

Example private policy fragment (store it as the Worker secret, never in a UI
bundle):

```json
{
  "version": 1,
  "default_provider": "codex",
  "default_permission_profile": "workspace_write",
  "max_steps": 2,
  "local_exo_enabled": true,
  "rules": []
}
```

## Local Runtime behavior

For an EXO ticket, `/usr/local/bin/os1` does all of the following before it
sends a prompt:

1. Reads the local EXO topology and requires at least two distinct peers.
2. Requests `Pipeline` + `MlxRing` placement with `min_nodes=2`.
3. Verifies every selected runner has the same `worldSize` and becomes ready.
4. Calls the OpenAI-compatible local EXO completion endpoint.
5. Deletes its exact temporary EXO instance on either success or failure.

The Runtime refuses the ticket if the Air node is unavailable. It never falls
back to a single-node EXO run, because that would silently violate a user
request to use the two-Mac cluster.

Run this local health check on the Mac hosting the OS-1 Runtime:

```bash
os1 exo-doctor
```

It succeeds only while the local EXO API sees the requested number of nodes.

## Release boundary

The source changes are safe to build and dry-run without deployment. A live
release additionally requires the existing Worker secrets and a deliberate
private-policy update. Do not put GitHub tokens, Cloudflare credentials,
ZeroTier identities, EXO peer IDs, or model credentials in this repository,
the UI, or R2 release artifacts.
