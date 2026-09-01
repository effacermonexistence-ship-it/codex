#!/usr/bin/env bash
set -euo pipefail

readonly repo_owner="effacermonexistence"
readonly repo_name="codex"
readonly repo_branch="main"
readonly default_install_root="$HOME/Documents/Codex/codex"
readonly install_root="${OMAR_CODEX_HOME:-$default_install_root}"
readonly codex_config_dir="${OMAR_CODEX_CONFIG_DIR:-$HOME/.codex}"
readonly claude_config_dir="${OMAR_CLAUDE_CONFIG_DIR:-$HOME/.claude}"
readonly archive_url="https://github.com/${repo_owner}/${repo_name}/archive/refs/heads/${repo_branch}.tar.gz"

bootstrap_tmp="$(mktemp -d)"
cleanup() {
  rm -rf "$bootstrap_tmp"
}
trap cleanup EXIT

echo "Downloading ${repo_owner}/${repo_name}..."
curl -fL --retry 3 --proto '=https' --tlsv1.2 \
  -o "$bootstrap_tmp/repository.tar.gz" "$archive_url"
tar -xzf "$bootstrap_tmp/repository.tar.gz" -C "$bootstrap_tmp"

mkdir -p "$install_root"
ditto "$bootstrap_tmp/${repo_name}-${repo_branch}" "$install_root"
chmod 0755 \
  "$install_root/scripts/bootstrap-new-mac.sh" \
  "$install_root/scripts/bootstrap-claude-code.sh" \
  "$install_root/scripts/restore-from-r2.sh" \
  "$install_root/products/os1-mac-runtime/scripts/install-os1.sh"

"$install_root/scripts/bootstrap-claude-code.sh"
if [[ "${OMAR_SKIP_OS1:-0}" != "1" ]]; then
  "$install_root/products/os1-mac-runtime/scripts/install-os1.sh"
fi

install_with_backup() {
  local source_file="$1"
  local destination_file="$2"
  local destination_dir
  local backup_file

  destination_dir="$(dirname "$destination_file")"
  mkdir -p "$destination_dir"

  if [[ -f "$destination_file" ]] && cmp -s "$source_file" "$destination_file"; then
    return
  fi

  if [[ -e "$destination_file" ]]; then
    backup_file="${destination_file}.before-omar-bootstrap.$(date -u +%Y%m%dT%H%M%SZ)"
    cp -p "$destination_file" "$backup_file"
    echo "Preserved existing file: $backup_file"
  fi

  install -m 0644 "$source_file" "$destination_file"
}

install_with_backup "$install_root/codex/AGENTS.md" "$codex_config_dir/AGENTS.md"
install_with_backup "$install_root/CLAUDE.md" "$claude_config_dir/CLAUDE.md"

echo
echo "Installed durable setup at: $install_root"
echo "Installed Codex instructions: $codex_config_dir/AGENTS.md"
echo "Installed Claude instructions: $claude_config_dir/CLAUDE.md"
echo "Installed Open OS-1 Codex: /Applications/Open OS-1 Codex.app"
echo
echo "One-time logins still required on each new Mac:"
echo "  Codex/ChatGPT: sign in to the Codex or ChatGPT desktop app"
echo "  GitHub:        gh auth login --hostname github.com --git-protocol https --web"
echo "  Claude:        claude auth login"
echo "  Cloudflare:    authorize cloudflare-api from Claude /mcp, or run pnpm exec wrangler login"
echo
echo "No GitHub PAT, Cloudflare API token, or R2 secret is required by the backup workflow."
