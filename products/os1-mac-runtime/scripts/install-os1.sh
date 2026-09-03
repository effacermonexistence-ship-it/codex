#!/usr/bin/env bash
set -euo pipefail

readonly gateway="https://os1-route-gateway.omar-git-r2-backup.workers.dev"
readonly local_bin="$HOME/.local/bin"
readonly gh_version="2.98.0"
readonly profile_file="$HOME/.zprofile"
readonly path_line='export PATH="$HOME/.local/bin:$PATH"'

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "OS-1 requires macOS 13 or newer." >&2
  exit 1
fi
case "$(uname -m)" in arm64|x86_64) ;; *) echo "Unsupported Mac architecture." >&2; exit 1 ;; esac

os1_major="$(sw_vers -productVersion | cut -d. -f1)"
if (( os1_major < 13 )); then
  echo "OS-1 requires macOS 13 or newer." >&2
  exit 1
fi

os1_tmp="$(mktemp -d /tmp/os1-install.XXXXXX)"
cleanup() { rm -rf "$os1_tmp"; }
trap cleanup EXIT

mkdir -p "$local_bin"
export PATH="$local_bin:/opt/homebrew/bin:/usr/local/bin:/Applications/ChatGPT.app/Contents/Resources:$PATH"
if [[ ! -f "$profile_file" ]] || ! grep -Fqx "$path_line" "$profile_file"; then
  printf '\n%s\n' "$path_line" >> "$profile_file"
fi

if [[ "${OS1_SKIP_PREREQUISITES:-0}" != "1" ]]; then
  if ! command -v codex >/dev/null 2>&1; then
    curl -fsSL --proto '=https' --tlsv1.2 https://chatgpt.com/codex/install.sh | sh
  fi
  if ! command -v claude >/dev/null 2>&1; then
    curl -fsSL --proto '=https' --tlsv1.2 https://claude.ai/install.sh | bash
  fi
  if ! command -v gh >/dev/null 2>&1; then
    case "$(uname -m)" in
      arm64) gh_arch="arm64"; gh_sha256="8cfb027cc5310675f2b830eac8f9865c1155a45ffcf9757f699fdd5a22046ca4" ;;
      x86_64) gh_arch="amd64"; gh_sha256="734c7bbd0bc56a3974500ee9aea74d60f0e5b89be09e92b9d9148939a3a1e0e6" ;;
    esac
    curl -fL --retry 3 --proto '=https' --tlsv1.2 \
      -o "$os1_tmp/gh.zip" \
      "https://github.com/cli/cli/releases/download/v${gh_version}/gh_${gh_version}_macOS_${gh_arch}.zip"
    printf '%s  %s\n' "$gh_sha256" "$os1_tmp/gh.zip" | shasum -a 256 -c -
    unzip -q "$os1_tmp/gh.zip" -d "$os1_tmp/gh"
    install -m 0755 "$os1_tmp/gh/gh_${gh_version}_macOS_${gh_arch}/bin/gh" "$local_bin/gh"
    codesign --verify "$local_bin/gh"
  fi
fi

curl -fL --retry 3 --proto '=https' --tlsv1.2 \
  -o "$os1_tmp/latest.json" "$gateway/v1/releases/latest"
os1_version="$(plutil -extract version raw -o - "$os1_tmp/latest.json")"
os1_sha256="$(plutil -extract sha256 raw -o - "$os1_tmp/latest.json")"
os1_size="$(plutil -extract size raw -o - "$os1_tmp/latest.json")"
[[ "$os1_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$os1_sha256" =~ ^[0-9a-f]{64}$ ]]
[[ "$os1_size" =~ ^[0-9]+$ ]]

curl -fL --retry 3 --proto '=https' --tlsv1.2 \
  -o "$os1_tmp/OS-1.pkg" "$gateway/v1/releases/download"
[[ "$(stat -f '%z' "$os1_tmp/OS-1.pkg")" == "$os1_size" ]]
printf '%s  %s\n' "$os1_sha256" "$os1_tmp/OS-1.pkg" | shasum -a 256 -c -
if ! pkgutil --check-signature "$os1_tmp/OS-1.pkg" >/dev/null 2>&1; then
  echo "OS-1 refused an unsigned or invalid installer package." >&2
  exit 1
fi
if ! spctl --assess --type install "$os1_tmp/OS-1.pkg" >/dev/null 2>&1; then
  echo "OS-1 refused a package that did not pass Apple distribution assessment." >&2
  exit 1
fi
sudo installer -pkg "$os1_tmp/OS-1.pkg" -target /

if [[ "${OS1_SKIP_LOGIN:-0}" != "1" && -t 0 ]]; then
  gh auth status --hostname github.com >/dev/null 2>&1 || \
    gh auth login --hostname github.com --git-protocol https --web
  codex login status >/dev/null 2>&1 || codex login --device-auth
  claude auth status 2>/dev/null | grep -q '"loggedIn": true' || claude auth login
fi

echo "Installed Open OS-1 Codex $os1_version."
if gh auth status --hostname github.com >/dev/null 2>&1 && \
   codex login status >/dev/null 2>&1 && \
   claude auth status 2>/dev/null | grep -q '"loggedIn": true'; then
  /usr/local/bin/os1 register
  /usr/local/bin/os1 doctor
else
  echo "Finish the three one-time logins, then run: os1 register && os1 doctor"
fi
