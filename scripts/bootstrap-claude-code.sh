#!/usr/bin/env bash
set -euo pipefail

readonly install_dir="$HOME/.local/bin"
readonly gh_version="2.98.0"
readonly node_version="24.20.0"
readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly project_root="$(cd "$script_dir/.." && pwd)"
readonly claude_config_dir="${OMAR_CLAUDE_CONFIG_DIR:-$HOME/.claude}"

bootstrap_tmp="$(mktemp -d)"
cleanup() {
  rm -rf "$bootstrap_tmp"
}
trap cleanup EXIT

mkdir -p "$install_dir"
export PATH="$HOME/.local/share/node-v${node_version}/bin:$install_dir:$PATH"

profile_file="$HOME/.zprofile"
path_line="export PATH=\"\$HOME/.local/share/node-v${node_version}/bin:\$HOME/.local/bin:\$PATH\""
if [[ ! -f "$profile_file" ]] || ! grep -Fqx "$path_line" "$profile_file"; then
  printf '\n%s\n' "$path_line" >> "$profile_file"
fi

if ! command -v claude >/dev/null 2>&1; then
  curl -fsSL --proto '=https' --tlsv1.2 \
    https://claude.ai/install.sh \
    -o "$bootstrap_tmp/claude-install.sh"
  bash "$bootstrap_tmp/claude-install.sh"
fi

if ! command -v gh >/dev/null 2>&1; then
  case "$(uname -m)" in
    arm64)
      gh_arch="arm64"
      gh_sha256="8cfb027cc5310675f2b830eac8f9865c1155a45ffcf9757f699fdd5a22046ca4"
      ;;
    x86_64)
      gh_arch="amd64"
      gh_sha256="734c7bbd0bc56a3974500ee9aea74d60f0e5b89be09e92b9d9148939a3a1e0e6"
      ;;
    *)
      echo "Unsupported macOS architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac

  gh_archive="gh_${gh_version}_macOS_${gh_arch}.zip"
  curl -fL --retry 3 \
    -o "$bootstrap_tmp/gh.zip" \
    "https://github.com/cli/cli/releases/download/v${gh_version}/${gh_archive}"
  printf '%s  %s\n' "$gh_sha256" "$bootstrap_tmp/gh.zip" | shasum -a 256 -c -
  unzip -q "$bootstrap_tmp/gh.zip" -d "$bootstrap_tmp/unpacked"
  install -m 0755 \
    "$bootstrap_tmp/unpacked/gh_${gh_version}_macOS_${gh_arch}/bin/gh" \
    "$install_dir/gh"
  codesign --verify "$install_dir/gh"
fi

if ! claude mcp get cloudflare-api >/dev/null 2>&1; then
  claude mcp add --transport http --scope user \
    cloudflare-api https://mcp.cloudflare.com/mcp
fi

claude_mcp_status="$(claude mcp get cloudflare-api 2>/dev/null || true)"
if [[ "$claude_mcp_status" == *"Needs authentication"* ]]; then
  echo "Cloudflare MCP login is required: claude mcp login cloudflare-api"
fi

if ! claude auth status 2>/dev/null | grep -q '"loggedIn": true'; then
  echo "Claude login is required: claude auth login"
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub login is required: gh auth login --hostname github.com --git-protocol https --web"
fi

for required_path in \
  "$project_root/claude/hooks/remote-backup-guard.mjs" \
  "$project_root/claude/settings.json" \
  "$project_root/scripts/install-claude-remote-backup-hook.mjs"; do
  if [[ ! -f "$required_path" ]]; then
    echo "Missing Claude remote completion component: $required_path" >&2
    exit 1
  fi
done

mkdir -p "$claude_config_dir/hooks"
install -m 0755 \
  "$project_root/claude/hooks/remote-backup-guard.mjs" \
  "$claude_config_dir/hooks/remote-backup-guard.mjs"
node "$project_root/scripts/install-claude-remote-backup-hook.mjs" \
  "$project_root/claude/settings.json" \
  "$claude_config_dir/settings.json"

echo "Claude Code: $(claude --version)"
echo "GitHub CLI: $(gh --version | head -1)"
echo "Cloudflare MCP: configured (OAuth is checked separately)"
echo "Remote completion guard: configured"
echo "PATH persistence: $profile_file"
