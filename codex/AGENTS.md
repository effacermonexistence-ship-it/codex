# Persistent GitHub and R2 environment

This machine is part of the `effacermonexistence` development environment.
The durable, non-secret source of truth is:

- GitHub repository: `https://github.com/effacermonexistence/codex`
- GitHub owner: `effacermonexistence`
- Cloudflare R2 bucket: `omar-private-archive`
- Backup Worker: `omar-git-r2-backup`
- Backup workflow: `.github/workflows/r2-git-backup.yml`

When the user asks to restore or configure a new Mac, fetch and inspect the
bootstrap script from the source-of-truth repository, then run it:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/effacermonexistence/codex/main/scripts/bootstrap-new-mac.sh \
  -o /tmp/omar-bootstrap-new-mac.sh
sed -n '1,260p' /tmp/omar-bootstrap-new-mac.sh
bash /tmp/omar-bootstrap-new-mac.sh
```

After bootstrap, complete only the unavoidable per-device OAuth logins for
Codex/ChatGPT, GitHub, Claude, and Cloudflare. Never copy authentication caches
between personal Macs and never commit tokens, passwords, OAuth codes, API
keys, Wrangler credentials, GitHub PATs, or Claude credentials.

Use the authenticated `gh` CLI for GitHub operations. Use the official
Cloudflare API MCP server or the repository's pinned Wrangler dependency for
Cloudflare and R2 operations. Do not change repository visibility, branch
protection, billing, or access permissions without the user's explicit request.

The GitHub-to-R2 backup itself is machine-independent and uses GitHub Actions
OIDC; it must not depend on a laptop credential. Validate changes with the
repository checks and verify the resulting R2 manifest when access is
available.

## Global completion persistence

This rule applies to every Codex task on this machine. Treat terminal phrases
such as `finish`, `complete`, `끝까지 해`, `완료해`, `다 끝내`, `멈추지 마`,
and `100%가 될 때까지` as explicit persistence requirements.

- Do not end the turn with a success or completion claim until every in-scope
  completion criterion has been implemented and verified with evidence.
- After each intermediate success, immediately continue to the next unmet
  criterion without waiting for the user to say `continue` again.
- Never use `done`, `complete`, `100%`, `완료`, or equivalent language to mean
  started, mostly complete, uploaded but not merged, deployed but not verified,
  or blocked.
- For long-running builds, deployments, backups, restores, and monitors, keep
  waiting or checking with the available task mechanism until they reach a
  terminal state. An intermediate milestone is not a terminal state.
- Before the final response, run a completion audit against the user's requested
  outcome and report only verified results and genuine limitations.
- If an unavoidable blocker requires new user authority, user-only input, or an
  external state change, first exhaust safe in-scope alternatives. Then state
  the exact blocker and remaining work; never describe a blocker as completion.
- Persistence does not expand the user's authorized scope and does not override
  safety, security, privacy, or destructive-action constraints.

## Direct setup and recovery phrases

Treat `시스템 세팅해`, `시스템 셋업해`, `새 맥 세팅해`, `맥 세팅해`,
`맥북 복구해`, and an equivalent request to set up or restore the system as an
explicit request to execute the new-Mac bootstrap, not merely explain it. Do
not ask which account the user means before inspecting the non-secret state
already available on the Mac. Fetch, inspect, and run the source-of-truth
bootstrap command above. Continue through installation and verification; pause
only for an unavoidable per-device OAuth approval that cannot be completed by
the existing authenticated CLI or connector. Never ask the user to paste a
password, token, OAuth code, or API key into chat.

After installing or changing this global file, explain that new Codex tasks
load it automatically. Existing Codex sessions load global guidance once per
session and must be restarted to see an updated file.

## Connection discovery and publishing fallback

Before asking the user to sign in, inspect existing connectivity without
printing secrets:

- GitHub: first inspect every already-connected authentication surface. Check
  the GitHub app/connector and its target-repository permissions when that tool
  is available, then run `gh auth status --hostname github.com`, `gh api user`,
  and inspect the CLI account's `permissions.push` value. The connector and CLI
  may represent different GitHub accounts with different permissions.
- Do not infer that GitHub is disconnected, open a login page, or ask the user
  to authenticate solely because the CLI account lacks upstream permission.
  Exhaust the existing GitHub app/connector, CLI accounts, and authorized task
  context first. When an existing connector has `push` or `admin` permission,
  use it for the requested repository operation instead of requesting a login.
- Cloudflare/R2: prefer the official `cloudflare-api` MCP connection. Otherwise
  use the repository-pinned Wrangler and inspect `wrangler whoami` before
  opening a dashboard login.

When the user explicitly says to ask or use an existing `admin` task, use the
Codex task-coordination tools to find that task, send the question or requested
operation directly, and wait for its result. Do not make the user relay state
between Codex tasks when the app can coordinate them.

For an authorized GitHub publication, use an existing connector or CLI identity
with upstream `push` permission when one is already available. Only when every
existing authenticated surface has `permissions.push: false`, create or reuse
the authenticated account's fork, push the verified branch and tag there, and
open a pull request to the source-of-truth repository. Clearly distinguish
"uploaded to GitHub" from "merged upstream". Do not broaden repository
permissions or request an account password as a workaround.
