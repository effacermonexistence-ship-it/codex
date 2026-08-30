#!/usr/bin/env bash
set -euo pipefail

readonly install_dir="$HOME/.local/bin"
readonly gh_version="2.98.0"

mkdir -p "$install_dir"
export PATH="$install_dir:$PATH"

if ! command -v claude >/dev/null 2>&1; then
  curl -fsSL https://claude.ai/install.sh | bash
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

  bootstrap_tmp="$(mktemp -d)"
  trap 'rm -rf "$bootstrap_tmp"' EXIT
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

if ! claude auth status 2>/dev/null | grep -q '"loggedIn": true'; then
  echo "Claude login is required: claude auth login"
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub login is required: gh auth login --hostname github.com --git-protocol https --web"
fi

echo "Claude Code: $(claude --version)"
echo "GitHub CLI: $(gh --version | head -1)"
echo "Cloudflare MCP: configured"
