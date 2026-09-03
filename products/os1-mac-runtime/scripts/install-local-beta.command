#!/usr/bin/env bash
set -euo pipefail

readonly bundle_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly package_path="$bundle_dir/OS-1.pkg"
readonly manifest_path="$bundle_dir/latest.json"
readonly installer_path="$bundle_dir/install-os1.sh"

if [[ ! -f "$package_path" || ! -f "$manifest_path" || ! -f "$installer_path" ]]; then
  echo "This OS-1 beta bundle is incomplete. Keep every bundled file in the same folder." >&2
  exit 1
fi

export OS1_ALLOW_UNNOTARIZED_BETA=1
export OS1_BETA_PACKAGE_PATH="$package_path"
export OS1_BETA_MANIFEST_PATH="$manifest_path"
exec /bin/bash "$installer_path"
