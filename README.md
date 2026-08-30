# GitHub to Cloudflare R2 backup

This project keeps every `effacermonexistence` GitHub repository mirrored as a
verified Git bundle in the private Cloudflare R2 bucket
`omar-private-archive`.

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

## Restore on a new computer

Install Git, Node.js, and Python 3, then run:

```bash
./scripts/restore-from-r2.sh <repository-name> [destination]
```

The script authenticates Wrangler when needed, downloads the latest manifest
and bundle, verifies its SHA-256 checksum and Git bundle structure, restores all
available branches and tags, and points `origin` back to GitHub.
