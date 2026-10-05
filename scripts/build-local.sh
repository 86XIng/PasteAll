#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
derived_data="${PASTEALL_DERIVED_DATA:-/tmp/PasteAllDerivedData}"
universal_derived_data="${PASTEALL_UNIVERSAL_DERIVED_DATA:-/tmp/PasteAllUniversalDerivedData}"
# Optional: a codesigning identity that stays the same across builds (for
# example "Apple Development: …"), so macOS keeps the Accessibility approval.
local_identity="${PASTEALL_LOCAL_SIGNING_IDENTITY:-}"
version="${PASTEALL_VERSION:-}"
build_number="${PASTEALL_BUILD_NUMBER:-}"
action="${1:-all}"

if [[ ! -d "$developer_dir" ]]; then
    echo "Xcode developer directory not found: $developer_dir" >&2
    echo "Install full Xcode or set DEVELOPER_DIR before running this script." >&2
    exit 1
fi

export DEVELOPER_DIR="$developer_dir"

# Ad-hoc ("Sign to Run Locally") signing applies the Finder extension's sandbox
# entitlement; macOS refuses to load an unsigned or unsandboxed extension.
signing_settings=(
    CODE_SIGN_IDENTITY=-
    CODE_SIGN_STYLE=Manual
    DEVELOPMENT_TEAM=
)

version_settings=()
[[ -z "$version" ]] || version_settings+=(MARKETING_VERSION="$version")
[[ -z "$build_number" ]] || version_settings+=(CURRENT_PROJECT_VERSION="$build_number")

build() {
    xcodebuild \
        -quiet \
        -project "$project_root/PasteAll.xcodeproj" \
        -scheme PasteAll \
        -configuration Debug \
        -destination "generic/platform=macOS" \
        -derivedDataPath "$derived_data" \
        -onlyUsePackageVersionsFromResolvedFile \
        "${signing_settings[@]}" \
        ${version_settings[@]+"${version_settings[@]}"} \
        build

    resign_if_requested "$derived_data/Build/Products/Debug/PasteAll.app"
}

test_project() {
    xcodebuild \
        -quiet \
        -project "$project_root/PasteAll.xcodeproj" \
        -scheme PasteAll \
        -configuration Debug \
        -destination "platform=macOS,arch=$(uname -m)" \
        -derivedDataPath "$derived_data" \
        -onlyUsePackageVersionsFromResolvedFile \
        "${signing_settings[@]}" \
        test
}

build_universal() {
    # Hardened Runtime library validation rejects ad-hoc signed frameworks, so
    # it stays off until the app is signed with a Developer ID (release.sh).
    xcodebuild \
        -quiet \
        -project "$project_root/PasteAll.xcodeproj" \
        -scheme PasteAll \
        -configuration Release \
        -destination "generic/platform=macOS" \
        -derivedDataPath "$universal_derived_data" \
        -onlyUsePackageVersionsFromResolvedFile \
        "${signing_settings[@]}" \
        ${version_settings[@]+"${version_settings[@]}"} \
        ENABLE_HARDENED_RUNTIME=NO \
        ARCHS="arm64 x86_64" \
        ONLY_ACTIVE_ARCH=NO \
        build

    local app_path="$universal_derived_data/Build/Products/Release/PasteAll.app"
    local signature_details

    [[ -d "$app_path" ]] || {
        echo "Universal build did not produce $app_path" >&2
        exit 1
    }

    signature_details="$(codesign -dv --verbose=4 "$app_path" 2>&1)"
    if [[ "$signature_details" == *"runtime"* ]]; then
        echo "Ad-hoc universal build unexpectedly enables Hardened Runtime" >&2
        exit 1
    fi

    resign_if_requested "$app_path"
}

# Re-signs inside-out with a stable identity, keeping each bundle's entitlements.
resign_if_requested() {
    local app_path="$1"
    [[ -n "$local_identity" ]] || return 0

    echo "Signing with '$local_identity'..."
    local nested
    for nested in "$app_path"/Contents/Frameworks/*.framework "$app_path"/Contents/PlugIns/*.appex; do
        [[ -e "$nested" ]] || continue
        codesign --force --sign "$local_identity" \
            --preserve-metadata=identifier,entitlements,flags "$nested"
    done
    codesign --force --sign "$local_identity" \
        --preserve-metadata=identifier,entitlements,flags "$app_path"
    codesign --verify --deep --strict "$app_path"
}

case "$action" in
    build)
        build
        ;;
    test)
        test_project
        ;;
    all)
        build
        test_project
        ;;
    universal)
        build_universal
        ;;
    *)
        echo "Usage: $0 [build|test|all|universal]" >&2
        exit 2
        ;;
esac

echo "Local $action completed successfully."
