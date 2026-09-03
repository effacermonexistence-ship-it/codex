#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly runtime_root="$(cd "$script_dir/.." && pwd)"
readonly repository_root="$(cd "$runtime_root/../.." && pwd)"
readonly policy_candidate="${1:?policy candidate path required}"
readonly release_id="${2:?release id required}"
readonly archive_dir="/tmp/os1-private-archive.${release_id}"
readonly package_path="$runtime_root/release/OS-1-0.8.0.pkg"
readonly beta_bundle_path="$runtime_root/release/OS-1-0.8.0-macOS-beta.zip"
readonly release_manifest="$runtime_root/release/latest.json"

[[ "$release_id" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
[[ -f "$policy_candidate" && -f "$package_path" && -f "$beta_bundle_path" && -f "$release_manifest" ]]
[[ ! -e "$archive_dir" ]]

if find \
  "$runtime_root/.private-core" \
  "$repository_root/products/os1-route-core" \
  "$repository_root/products/os1-private-route-core" \
  "$repository_root/products/os1-result-evaluator" \
  -type f \( -name '.dev.vars' -o -name '*.pem' -o -name '*.p12' -o -name '*.key' -o -name '*credentials*' \) \
  -not -path '*/node_modules/*' -not -path '*/dist/*' -print -quit | grep -q .; then
  echo "Refusing credential-like files in private archive input." >&2
  exit 1
fi
if rg -l --hidden \
  -g '!**/node_modules/**' -g '!**/.build*/**' -g '!**/release/**' -g '!**/dist/**' \
  '(gho_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{20,}|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|password\s*[:=]\s*[^< ]|api[_-]?key\s*[:=]\s*[A-Za-z0-9_-]{16,})' \
  "$runtime_root/.private-core" \
  "$repository_root/products/os1-route-core" \
  "$repository_root/products/os1-private-route-core" \
  "$repository_root/products/os1-result-evaluator" >/dev/null 2>&1; then
  echo "Refusing credential-like content in private archive input." >&2
  exit 1
fi

mkdir -m 0700 "$archive_dir"
COPYFILE_DISABLE=1 tar \
  --exclude='node_modules' --exclude='dist' --exclude='.wrangler' \
  --exclude='.build' --exclude='.build-*' --exclude='release' --exclude='.DS_Store' \
  -czf "$archive_dir/source-private.tar.gz" \
  -C "$repository_root" \
  .github/workflows/os1-route-core-security.yml \
  docs/os1-route-core-security-handoff.md \
  products/os1-mac-runtime \
  products/os1-route-core \
  products/os1-private-route-core \
  products/os1-result-evaluator \
  products/os1-auth-service \
  products/os1-device-registry \
  pnpm-lock.yaml pnpm-workspace.yaml package.json

install -m 0600 "$package_path" "$archive_dir/OS-1-0.8.0-development.pkg"
install -m 0600 "$beta_bundle_path" "$archive_dir/OS-1-0.8.0-macOS-beta.zip"
install -m 0600 "$release_manifest" "$archive_dir/latest-development.json"
install -m 0600 "$policy_candidate" "$archive_dir/policy-candidate.json"

node -e '
  const { createHash } = require("node:crypto");
  const { readFileSync, statSync, writeFileSync } = require("node:fs");
  const [manifestPath, releaseId, gitRevision, ...files] = process.argv.slice(1);
  const artifacts = files.map((file) => {
    const bytes = readFileSync(file);
    return { name: file.split("/").pop(), bytes: statSync(file).size,
      sha256: createHash("sha256").update(bytes).digest("hex") };
  });
  writeFileSync(manifestPath, JSON.stringify({ schema: 1, release_id: releaseId,
    git_revision: gitRevision, artifacts }, null, 2) + "\n", { mode: 0o600 });
' "$archive_dir/manifest.json" "$release_id" "$(git -C "$repository_root" rev-parse HEAD)" \
  "$archive_dir/source-private.tar.gz" \
  "$archive_dir/OS-1-0.8.0-development.pkg" \
  "$archive_dir/OS-1-0.8.0-macOS-beta.zip" \
  "$archive_dir/latest-development.json" \
  "$archive_dir/policy-candidate.json"

echo "$archive_dir"
