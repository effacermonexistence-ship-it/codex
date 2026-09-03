#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly runtime_root="$(cd "$script_dir/.." && pwd)"
readonly repository_root="$(cd "$runtime_root/../.." && pwd)"
readonly version="${OS1_VERSION:-0.7.13}"
readonly output_dir="${OS1_RELEASE_OUTPUT_DIR:-$runtime_root/release}"
readonly stage_dir="$output_dir/stage"
readonly component_pkg="$output_dir/OS-1-component.pkg"
readonly unsigned_pkg="$output_dir/OS-1-${version}-unsigned.pkg"
readonly final_pkg="$output_dir/OS-1-${version}.pkg"
readonly private_core_source="${OS1_PRIVATE_CORE_SOURCE:-$runtime_root/.private-core}"
readonly allow_ci_private_core_fixture="${OS1_ALLOW_CI_PRIVATE_CORE_FIXTURE:-0}"
readonly arm64_build_dir="${OS1_ARM64_BUILD_DIR:-$runtime_root/.build-release-arm64}"
readonly x86_64_build_dir="${OS1_X86_64_BUILD_DIR:-$runtime_root/.build-release-x86_64}"
readonly skip_build="${OS1_SKIP_BUILD:-0}"
readonly codesign_identity="${OS1_CODESIGN_IDENTITY:--}"
readonly installer_identity="${OS1_INSTALLER_IDENTITY:-}"

case "$output_dir" in
  "$runtime_root"/release|/tmp/os1-release.*) ;;
  *) echo "Refusing unexpected release output: $output_dir" >&2; exit 1 ;;
esac

rm -rf "$output_dir"
mkdir -p \
  "$stage_dir/Applications/Open OS-1 Codex.app/Contents/MacOS" \
  "$stage_dir/Applications/Open OS-1 Codex.app/Contents/Resources" \
  "$stage_dir/usr/local/bin" \
  "$stage_dir/Library/Application Support/OS-1/private-core"

[[ -f "$private_core_source/os1_local_core.py" ]]
if [[ "$allow_ci_private_core_fixture" == "1" ]]; then
  if [[ "${CI:-}" != "true" ]]; then
    echo "Refusing the public private-core fixture outside CI." >&2
    exit 1
  fi
  if [[ "$private_core_source" != "$runtime_root/Fixtures/ci-private-core" ]]; then
    echo "Refusing an unrecognized CI private-core fixture path." >&2
    exit 1
  fi
  echo "Using fail-closed public CI private-core fixture; this package is not a production release."
else
  printf '%s  %s\n' \
    '3e28b1db2b40a8a88bfb8064250c5c1169d631a45860375dc261dac9daea6466' \
    "$private_core_source/OMAR_LUA_RCC_ENGINE_v26_CLEAN_CONSOLIDATED.txt" | shasum -a 256 -c -
  printf '%s  %s\n' \
    '274886b0db8df88c86046d9c5be8140f245e97d01250f9827cae1f1dcb28c093' \
    "$private_core_source/darwin_routed_rcc.py" | shasum -a 256 -c -
  printf '%s  %s\n' \
    'c56310562d5336c86f46a7f278e8580d50c200c0ba1b98b28d6e7d14f5347de2' \
    "$private_core_source/darwin_benchmark_priors.json" | shasum -a 256 -c -
  printf '%s  %s\n' \
    '92f8bb1c4fbba8e3dd9fb7d1e73ec204877a69fc7256457a2a4dff02efe919a5' \
    "$private_core_source/darwin_prompt_lineage.json" | shasum -a 256 -c -
  printf '%s  %s\n' \
    '6ebfffbb585ef451c4028fda92ee53977a7de2bad2e9302d92bd4011390d60b4' \
    "$private_core_source/darwin_router_state.json" | shasum -a 256 -c -
  printf '%s  %s\n' \
    '92c54350e9eb6fcba28155db5efbbba4bde29a9936f291a058c319448247ba6a' \
    "$private_core_source/hinton_forward_forward_state.json" | shasum -a 256 -c -
  python3 "$private_core_source/os1_local_core.py" self-test
fi

if [[ "$skip_build" == "1" ]]; then
  [[ -x "$arm64_build_dir/arm64-apple-macosx/release/os1" ]]
  [[ -x "$arm64_build_dir/arm64-apple-macosx/release/OS1App" ]]
  [[ -x "$x86_64_build_dir/x86_64-apple-macosx/release/os1" ]]
  [[ -x "$x86_64_build_dir/x86_64-apple-macosx/release/OS1App" ]]
else
  swift build --package-path "$runtime_root" -c release \
    --triple arm64-apple-macosx13.0 \
    --build-path "$arm64_build_dir"
  swift build --package-path "$runtime_root" -c release \
    --triple x86_64-apple-macosx13.0 \
    --build-path "$x86_64_build_dir"
fi

lipo -create \
  "$arm64_build_dir/arm64-apple-macosx/release/os1" \
  "$x86_64_build_dir/x86_64-apple-macosx/release/os1" \
  -output "$stage_dir/usr/local/bin/os1"
install -m 0755 "$stage_dir/usr/local/bin/os1" \
  "$stage_dir/Applications/Open OS-1 Codex.app/Contents/Resources/os1"
lipo -create \
  "$arm64_build_dir/arm64-apple-macosx/release/OS1App" \
  "$x86_64_build_dir/x86_64-apple-macosx/release/OS1App" \
  -output "$stage_dir/Applications/Open OS-1 Codex.app/Contents/MacOS/OS1App"

install -m 0644 "$runtime_root/Resources/Info.plist" \
  "$stage_dir/Applications/Open OS-1 Codex.app/Contents/Info.plist"
install -m 0644 "$runtime_root/Resources/OmarAGI.png" \
  "$stage_dir/Applications/Open OS-1 Codex.app/Contents/Resources/OmarAGI.png"
install -m 0644 "$runtime_root/Resources/Codex.png" \
  "$stage_dir/Applications/Open OS-1 Codex.app/Contents/Resources/Codex.png"
install -m 0644 "$runtime_root/Resources/ClaudeCode.png" \
  "$stage_dir/Applications/Open OS-1 Codex.app/Contents/Resources/ClaudeCode.png"
install -m 0644 "$runtime_root/Resources/Constellation.png" \
  "$stage_dir/Applications/Open OS-1 Codex.app/Contents/Resources/Constellation.png"
install -m 0644 "$runtime_root/Resources/OmarAGI.icns" \
  "$stage_dir/Applications/Open OS-1 Codex.app/Contents/Resources/OmarAGI.icns"
install -m 0644 "$runtime_root/Config/production.json" \
  "$stage_dir/Applications/Open OS-1 Codex.app/Contents/Resources/config.json"
install -m 0644 "$runtime_root/Config/production.json" \
  "$stage_dir/Library/Application Support/OS-1/config.json"
for private_file in \
  os1_local_core.py OMAR_LUA_RCC_ENGINE_v26_CLEAN_CONSOLIDATED.txt \
  darwin_routed_rcc.py darwin_benchmark_priors.json \
  darwin_prompt_lineage.json darwin_router_state.json hinton_forward_forward_state.json; do
  install -m 0644 "$private_core_source/$private_file" \
    "$stage_dir/Library/Application Support/OS-1/private-core/$private_file"
done
xattr -cr "$stage_dir"

codesign --force --sign "$codesign_identity" --options runtime \
  --identifier com.omaragi.os1.runtime "$stage_dir/usr/local/bin/os1"
codesign --force --sign "$codesign_identity" --options runtime \
  --identifier com.omaragi.os1.runtime.bundled \
  "$stage_dir/Applications/Open OS-1 Codex.app/Contents/Resources/os1"
codesign --force --sign "$codesign_identity" --options runtime \
  --entitlements "$runtime_root/Resources/OS1.entitlements" \
  --identifier com.omaragi.os1 "$stage_dir/Applications/Open OS-1 Codex.app"
codesign --verify --strict --verbose=2 "$stage_dir/usr/local/bin/os1"
codesign --verify --deep --strict --verbose=2 "$stage_dir/Applications/Open OS-1 Codex.app"
lipo -archs "$stage_dir/usr/local/bin/os1" | grep -q 'x86_64 arm64\|arm64 x86_64'
lipo -archs "$stage_dir/Applications/Open OS-1 Codex.app/Contents/MacOS/OS1App" | grep -q 'x86_64 arm64\|arm64 x86_64'
"$stage_dir/usr/local/bin/os1" self-test
"$stage_dir/Applications/Open OS-1 Codex.app/Contents/MacOS/OS1App" --self-test

COPYFILE_DISABLE=1 pkgbuild \
  --root "$stage_dir" \
  --identifier com.omaragi.os1 \
  --version "$version" \
  --install-location / \
  "$component_pkg"
productbuild --package "$component_pkg" "$unsigned_pkg"

if [[ -n "$installer_identity" ]]; then
  productsign --sign "$installer_identity" "$unsigned_pkg" "$final_pkg"
else
  cp "$unsigned_pkg" "$final_pkg"
fi

pkgutil --check-signature "$final_pkg" || [[ -z "$installer_identity" ]]
pkgutil --payload-files "$final_pkg" | grep -q 'usr/local/bin/os1'
pkgutil --payload-files "$final_pkg" | grep -q 'Applications/Open OS-1 Codex.app'
pkgutil --payload-files "$final_pkg" | grep -q 'Applications/Open OS-1 Codex.app/Contents/Resources/Codex.png'
pkgutil --payload-files "$final_pkg" | grep -q 'Applications/Open OS-1 Codex.app/Contents/Resources/ClaudeCode.png'
pkgutil --payload-files "$final_pkg" | grep -q 'Applications/Open OS-1 Codex.app/Contents/Resources/Constellation.png'
pkgutil --payload-files "$final_pkg" | grep -q 'Library/Application Support/OS-1/private-core/os1_local_core.py'

node "$repository_root/products/os1-route-core/scripts/client-artifact-scan.mjs" \
  "$stage_dir/usr/local/bin/os1" \
  "$stage_dir/Applications/Open OS-1 Codex.app" \
  "$stage_dir/Library/Application Support/OS-1/config.json"

readonly package_sha256="$(shasum -a 256 "$final_pkg" | awk '{print $1}')"
readonly package_size="$(stat -f '%z' "$final_pkg")"
printf '{"version":"%s","object_key":"os1/releases/%s/OS-1-%s.pkg","sha256":"%s","size":%s,"minimum_macos":"13.0"}\n' \
  "$version" "$version" "$version" "$package_sha256" "$package_size" \
  > "$output_dir/latest.json"

echo "Release package: $final_pkg"
echo "Release manifest: $output_dir/latest.json"
echo "SHA-256: $package_sha256"
