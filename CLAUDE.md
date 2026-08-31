# GitHub to R2 infrastructure

This repository is the source of truth for the automatic GitHub-to-R2 backup.

- GitHub owner: `effacermonexistence`.
- Cloudflare R2 bucket: `omar-private-archive`.
- Worker: `omar-git-r2-backup`.
- Worker endpoint: `https://omar-git-r2-backup.omar-git-r2-backup.workers.dev`.
- GitHub workflow path: `.github/workflows/r2-git-backup.yml`.
- Use the authenticated `gh` CLI for GitHub operations.
- Use the `cloudflare-api` MCP server or `pnpm exec wrangler` for Cloudflare and R2 operations.
- Never commit API tokens, OAuth tokens, Wrangler credential files, or GitHub PATs.
- Never change repository visibility, branch protection, or billing settings unless the user explicitly requests it.

Before deploying Worker changes:

```bash
corepack enable
pnpm install --frozen-lockfile
pnpm run types
pnpm run check
pnpm run deploy:dry-run
```

Restore a repository:

```bash
./scripts/restore-from-r2.sh <repository-name> [destination]
```

Treat `시스템 세팅해`, `시스템 셋업해`, `새 맥 세팅해`, and `맥북 복구해`
as direct authorization to fetch, inspect, and run
`scripts/bootstrap-new-mac.sh`. Inspect `gh` and Cloudflare/Wrangler connection
state before asking the user to sign in. Never ask the user to paste passwords,
tokens, OAuth codes, or API keys. If the authenticated GitHub account cannot
push upstream, use its fork and open a pull request without claiming that the
upstream branch was merged.
