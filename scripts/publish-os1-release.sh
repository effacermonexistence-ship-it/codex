#!/usr/bin/env bash
set -euo pipefail

readonly repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly runtime_root="$repository_root/products/os1-mac-runtime"
readonly release_dir="$runtime_root/release"

"$runtime_root/scripts/build-release.sh"
os1_version="$(plutil -extract version raw -o - "$release_dir/latest.json")"
os1_object_key="$(plutil -extract object_key raw -o - "$release_dir/latest.json")"
[[ "$os1_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$os1_object_key" == "os1/releases/$os1_version/OS-1-$os1_version.pkg" ]]

cd "$repository_root"
pnpm exec wrangler r2 object put "os1-public-releases/$os1_object_key" \
  --remote --file "$release_dir/OS-1-$os1_version.pkg" \
  --content-type 'application/vnd.apple.installer+xml' \
  --cache-control 'public, max-age=31536000, immutable' --force
pnpm exec wrangler r2 object put 'os1-public-releases/os1/latest.json' \
  --remote --file "$release_dir/latest.json" \
  --content-type 'application/json' --cache-control 'public, max-age=300' --force
pnpm exec wrangler r2 object put 'os1-public-releases/os1/install.sh' \
  --remote --file "$runtime_root/scripts/install-os1.sh" \
  --content-type 'text/x-shellscript' --cache-control 'public, max-age=300' --force

os1_expected="$(plutil -extract sha256 raw -o - "$release_dir/latest.json")"
os1_download="$(mktemp /tmp/os1-release-download.XXXXXX)"
curl -fsSL https://os1-route-gateway.omar-git-r2-backup.workers.dev/v1/releases/download \
  -o "$os1_download"
os1_actual="$(shasum -a 256 "$os1_download" | awk '{print $1}')"
/bin/unlink "$os1_download"
[[ "$os1_expected" == "$os1_actual" ]]
echo "Published and verified Open OS-1 Codex $os1_version ($os1_actual)."
