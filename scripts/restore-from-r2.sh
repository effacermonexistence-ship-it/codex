#!/usr/bin/env bash
set -euo pipefail

readonly backup_bucket="omar-private-archive"
readonly backup_owner="effacermonexistence"

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
if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 is required." >&2
  exit 1
fi

if command -v wrangler >/dev/null 2>&1; then
  wrangler_command=(wrangler)
elif command -v npx >/dev/null 2>&1; then
  wrangler_command=(npx --yes wrangler@latest)
else
  echo "Wrangler or Node.js with npx is required." >&2
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
  python3 - "$manifest_path" "$backup_owner/$repository_name" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    manifest = json.load(source)

if manifest.get("version") != 1 or manifest.get("repository") != sys.argv[2]:
    raise SystemExit("The R2 manifest does not match the requested repository")
key = manifest.get("key")
sha256 = manifest.get("sha256")
ref = manifest.get("ref")
if not isinstance(key, str) or not key.startswith(f"git-bundles/{sys.argv[2]}/"):
    raise SystemExit("The R2 manifest has an invalid object key")
if not isinstance(sha256, str) or not re.fullmatch(r"[0-9a-f]{64}", sha256):
    raise SystemExit("The R2 manifest has an invalid checksum")
if not isinstance(ref, str):
    raise SystemExit("The R2 manifest has an invalid ref")
print(key, sha256, ref, sep="\t")
PY
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

actual_sha256="$(python3 - "$bundle_path" <<'PY'
import hashlib
import sys

digest = hashlib.sha256()
with open(sys.argv[1], "rb") as source:
    for chunk in iter(lambda: source.read(8 * 1024 * 1024), b""):
        digest.update(chunk)
print(digest.hexdigest())
PY
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
