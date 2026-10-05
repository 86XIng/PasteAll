#!/bin/bash
# Builds the ad-hoc signed universal app and packages it for a GitHub Release:
#   dist/PasteAll-<version>.zip and dist/PasteAll-<version>.zip.sha256
# Used by .github/workflows/release.yml until a Developer ID is available.

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${PASTEALL_VERSION:-}"
build_number="${PASTEALL_BUILD_NUMBER:-1}"
artifacts_dir="${PASTEALL_ARTIFACTS_DIR:-$project_root/dist}"
derived_data="${PASTEALL_UNIVERSAL_DERIVED_DATA:-/tmp/PasteAllUniversalDerivedData}"

fail() {
    echo "Packaging failed: $*" >&2
    exit 1
}

[[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || fail "PASTEALL_VERSION must look like 1.0 or 1.0.0"
[[ "$build_number" =~ ^[1-9][0-9]*$ ]] || fail "PASTEALL_BUILD_NUMBER must be a positive integer"

zip_path="$artifacts_dir/PasteAll-$version.zip"
[[ ! -e "$zip_path" ]] || fail "Output already exists: $zip_path"

PASTEALL_VERSION="$version" \
PASTEALL_BUILD_NUMBER="$build_number" \
PASTEALL_UNIVERSAL_DERIVED_DATA="$derived_data" \
    "$project_root/scripts/build-local.sh" universal

app_path="$derived_data/Build/Products/Release/PasteAll.app"
appex_path="$app_path/Contents/PlugIns/PasteAllFinderExtension.appex"

codesign --verify --deep --strict --verbose=2 "$app_path"
architectures="$(lipo -archs "$app_path/Contents/MacOS/PasteAll")"
[[ " $architectures " == *" arm64 "* && " $architectures " == *" x86_64 "* ]] || fail "App is not universal: $architectures"

actual_version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app_path/Contents/Info.plist")"
[[ "$actual_version" == "$version" ]] || fail "App version is $actual_version, expected $version"

[[ -d "$appex_path" ]] || fail "Finder extension is missing"
codesign -d --entitlements - --xml "$appex_path" 2>/dev/null | grep -q "com.apple.security.app-sandbox" \
    || fail "Finder extension is not sandboxed"

mkdir -p "$artifacts_dir"
ditto -c -k --keepParent "$app_path" "$zip_path"
(cd "$artifacts_dir" && shasum -a 256 "$(basename "$zip_path")" >"$(basename "$zip_path").sha256")

echo "Packaged $zip_path"
cat "$zip_path.sha256"
