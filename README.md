# GitHub to Cloudflare R2 backup

This project keeps every `effacermonexistence` GitHub repository mirrored as a
verified Git bundle in the private Cloudflare R2 bucket
`omar-private-archive`.

## Daily operator check

Run this first when Omar OS One Codex feels broken, newly installed, or moved
to another Mac:

```bash
cd ~/Documents/Codex/codex
pnpm run doctor
```

The doctor verifies the local project, installed Codex and Claude guidance,
GitHub CLI login, Claude login, Cloudflare MCP, Wrangler, TypeScript, R2
manifest access, and the backup Worker health endpoint. Use strict mode when a
handoff should fail on warnings too:

```bash
pnpm run doctor:strict
```

## New Mac: one bootstrap command

The durable setup lives in this public repository, not in a laptop or an AI
account's memory. On a new Mac, download and run the reviewed bootstrap:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/effacermonexistence/codex/main/scripts/bootstrap-new-mac.sh \
  -o /tmp/omar-bootstrap-new-mac.sh
sed -n '1,260p' /tmp/omar-bootstrap-new-mac.sh
bash /tmp/omar-bootstrap-new-mac.sh
```

It installs the repository under `~/Documents/Codex/codex`, installs Claude
Code and GitHub CLI when missing, configures the Cloudflare MCP endpoint, and
copies durable non-secret guidance to `~/.codex/AGENTS.md` and
`~/.claude/CLAUDE.md`. Existing instruction files are backed up before they are
replaced.

OAuth credentials are intentionally not copied or committed. Sign in once per
new Mac to Codex/ChatGPT, GitHub, Claude, and Cloudflare. The GitHub-to-R2
workflow itself needs no laptop login because it uses GitHub Actions OIDC.
After bootstrap, confirm readiness with `pnpm run doctor`.

The GitHub workflow uses GitHub Actions OIDC. No long-lived Cloudflare or R2
credential is stored in GitHub. The Worker accepts only tokens issued for
`effacermonexistence` repositories running
`.github/workflows/r2-git-backup.yml`, then streams each bundle to R2 with the
multipart API.

Backups run on every branch or tag push, weekly, and on manual dispatch. The
latest manifest is stored at:

```text
git-bundles/effacermonexistence/<repository>/latest.json
```

## Rebuild or redeploy the gateway

On a new computer, clone this repository and authenticate Wrangler with the
Cloudflare account that owns `omar-private-archive`, then run:

```bash
corepack enable
pnpm install --frozen-lockfile
pnpm run types
pnpm run check
pnpm run deploy
```

The GitHub workflows do not need Cloudflare access keys or repository secrets.
They obtain short-lived GitHub OIDC tokens for each upload request.

## Claude Code

Claude Code uses the authenticated GitHub CLI for repository operations and the
official Cloudflare API MCP server or Wrangler for R2 operations. On a new Mac:

```bash
./scripts/bootstrap-claude-code.sh
claude auth login
gh auth login --hostname github.com --git-protocol https --web
```

Start Claude Code in this repository and run `/mcp` once to authorize the
`cloudflare-api` server. No GitHub PAT or Cloudflare API token is committed.

## Restore on a new computer

Install Git, Node.js, and Python 3, then run:

```bash
./scripts/restore-from-r2.sh <repository-name> [destination]
```

The script authenticates Wrangler when needed, downloads the latest manifest
and bundle, verifies its SHA-256 checksum and Git bundle structure, restores all
available branches and tags, and points `origin` back to GitHub.
