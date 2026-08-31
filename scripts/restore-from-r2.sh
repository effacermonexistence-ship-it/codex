#!/usr/bin/env bash
set -euo pipefail

readonly backup_bucket="omar-private-archive"
readonly backup_owner="effacermonexistence"
readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly project_root="$(cd "$script_dir/.." && pwd)"

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <repository-name> [destination]" >&2
  exit 2
fi

readonly repository_name="$1"
readonly destination="${2:-$repository_name}"

if [[ ! "$repository_name" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Invalid repository name: $repository_name" >&2
  exit 2
fi

if [[ -e "$destination" ]]; then
  echo "Destination already exists: $destination" >&2
  exit 2
fi

if ! command -v git >/dev/null 2>&1; then
  echo "Git is required." >&2
  exit 1
fi
if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is required. Run ./scripts/bootstrap-new-mac.sh first." >&2
  exit 1
fi

if [[ -x "$project_root/node_modules/.bin/wrangler" ]]; then
  wrangler_command=("$project_root/node_modules/.bin/wrangler")
else
  echo "The repository's pinned Wrangler is not installed." >&2
  echo "Run: pnpm --dir \"$project_root\" install --frozen-lockfile" >&2
  exit 1
fi

restore_tmp="$(mktemp -d)"
trap 'rm -rf "$restore_tmp"' EXIT

manifest_path="$restore_tmp/latest.json"
manifest_key="git-bundles/$backup_owner/$repository_name/latest.json"

download_manifest() {
  "${wrangler_command[@]}" r2 object get \
    "$backup_bucket/$manifest_key" \
    --remote \
    --file "$manifest_path"
}

if ! download_manifest; then
  "${wrangler_command[@]}" login --use-keyring
  download_manifest
fi

IFS=$'\t' read -r bundle_key expected_sha256 source_ref < <(
  node - "$manifest_path" "$backup_owner/$repository_name" <<'JS'
const fs = require("node:fs");

const [manifestPath, expectedRepository] = process.argv.slice(2);
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));

if (manifest.version !== 1 || manifest.repository !== expectedRepository) {
  throw new Error("The R2 manifest does not match the requested repository");
}
const { key, sha256, ref } = manifest;
if (
  typeof key !== "string" ||
  !key.startsWith(`git-bundles/${expectedRepository}/`)
) {
  throw new Error("The R2 manifest has an invalid object key");
}
if (typeof sha256 !== "string" || !/^[0-9a-f]{64}$/.test(sha256)) {
  throw new Error("The R2 manifest has an invalid checksum");
}
if (typeof ref !== "string") {
  throw new Error("The R2 manifest has an invalid ref");
}
process.stdout.write(`${key}\t${sha256}\t${ref}\n`);
JS
)

readonly bundle_key
readonly expected_sha256
readonly source_ref
readonly bundle_path="$restore_tmp/repository.bundle"
readonly mirror_path="$restore_tmp/repository.git"
readonly verify_path="$restore_tmp/verify.git"

"${wrangler_command[@]}" r2 object get \
  "$backup_bucket/$bundle_key" \
  --remote \
  --file "$bundle_path"

actual_sha256="$(node - "$bundle_path" <<'JS'
const fs = require("node:fs");
const crypto = require("node:crypto");

const digest = crypto.createHash("sha256");
const source = fs.createReadStream(process.argv[2]);
source.on("data", (chunk) => digest.update(chunk));
source.on("error", (error) => {
  console.error(error.message);
  process.exitCode = 1;
});
source.on("end", () => console.log(digest.digest("hex")));
JS
)"

if [[ "$actual_sha256" != "$expected_sha256" ]]; then
  echo "R2 bundle checksum verification failed." >&2
  exit 1
fi

git init --bare "$verify_path"
git --git-dir="$verify_path" bundle verify "$bundle_path"
git clone --bare "$bundle_path" "$mirror_path"

while read -r object_id bundled_ref; do
  case "$bundled_ref" in
    refs/remotes/origin/HEAD)
      ;;
    refs/remotes/origin/*)
      restored_ref="refs/heads/${bundled_ref#refs/remotes/origin/}"
      git check-ref-format "$restored_ref"
      git --git-dir="$mirror_path" update-ref "$restored_ref" "$object_id"
      ;;
    refs/heads/* | refs/tags/*)
      git check-ref-format "$bundled_ref"
      git --git-dir="$mirror_path" update-ref "$bundled_ref" "$object_id"
      ;;
  esac
done < <(git bundle list-heads "$bundle_path")

if [[ "$source_ref" == refs/heads/* ]]; then
  source_branch="${source_ref#refs/heads/}"
  if git --git-dir="$mirror_path" show-ref --verify --quiet "refs/heads/$source_branch"; then
    git --git-dir="$mirror_path" symbolic-ref HEAD "refs/heads/$source_branch"
  fi
fi

git clone "$mirror_path" "$destination"
git -C "$destination" remote set-url origin \
  "https://github.com/$backup_owner/$repository_name.git"

echo "Restored $backup_owner/$repository_name to $destination"
echo "Origin is set to https://github.com/$backup_owner/$repository_name.git"
