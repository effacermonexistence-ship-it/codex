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
