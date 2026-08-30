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
