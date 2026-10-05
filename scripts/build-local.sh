#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
derived_data="${PASTEALL_DERIVED_DATA:-/tmp/PasteAllDerivedData}"
universal_derived_data="${PASTEALL_UNIVERSAL_DERIVED_DATA:-/tmp/PasteAllUniversalDerivedData}"
action="${1:-all}"

if [[ ! -d "$developer_dir" ]]; then
    echo "Xcode developer directory not found: $developer_dir" >&2
    echo "Install full Xcode or set DEVELOPER_DIR before running this script." >&2
    exit 1
fi

export DEVELOPER_DIR="$developer_dir"

build() {
    xcodebuild \
        -quiet \
        -project "$project_root/PasteAll.xcodeproj" \
        -scheme PasteAll \
        -configuration Debug \
        -destination "generic/platform=macOS" \
        -derivedDataPath "$derived_data" \
        -onlyUsePackageVersionsFromResolvedFile \
        CODE_SIGNING_ALLOWED=NO \
        build
}

test_project() {
    xcodebuild \
        -quiet \
        -project "$project_root/PasteAll.xcodeproj" \
        -scheme PasteAll \
        -configuration Debug \
        -destination "platform=macOS" \
        -derivedDataPath "$derived_data" \
        -onlyUsePackageVersionsFromResolvedFile \
        CODE_SIGNING_ALLOWED=NO \
        test
}

build_universal() {
    xcodebuild \
        -quiet \
        -project "$project_root/PasteAll.xcodeproj" \
        -scheme PasteAll \
        -configuration Release \
        -destination "generic/platform=macOS" \
        -derivedDataPath "$universal_derived_data" \
        -onlyUsePackageVersionsFromResolvedFile \
        CODE_SIGNING_ALLOWED=NO \
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
        echo "Unsigned universal build unexpectedly enables Hardened Runtime" >&2
        exit 1
    fi
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
