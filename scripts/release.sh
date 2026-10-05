#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
artifacts_dir="${PASTEALL_ARTIFACTS_DIR:-$project_root/dist}"
derived_data="${PASTEALL_RELEASE_DERIVED_DATA:-$project_root/.release/DerivedData}"

team_id="${PASTEALL_TEAM_ID:-}"
bundle_id="${PASTEALL_BUNDLE_ID:-}"
notary_profile="${PASTEALL_NOTARY_PROFILE:-paste-all-notary}"
notary_timeout="${PASTEALL_NOTARY_TIMEOUT:-60m}"
version="${PASTEALL_VERSION:-}"
build_number="${PASTEALL_BUILD_NUMBER:-}"
signing_identity="${PASTEALL_SIGNING_IDENTITY:-Developer ID Application}"

fail() {
    echo "Release failed: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

[[ -d "$developer_dir" ]] || fail "Xcode developer directory not found: $developer_dir"
[[ "$team_id" =~ ^[A-Z0-9]{10}$ ]] || fail "PASTEALL_TEAM_ID must be a 10-character Team ID"
[[ "$bundle_id" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || fail "PASTEALL_BUNDLE_ID must be a reverse-DNS identifier"
[[ "$bundle_id" != com.local.* ]] || fail "Replace the local Bundle ID before distribution"
[[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || fail "PASTEALL_VERSION must look like 1.0 or 1.0.0"
[[ "$build_number" =~ ^[1-9][0-9]*$ ]] || fail "PASTEALL_BUILD_NUMBER must be a positive integer"
[[ "$notary_timeout" =~ ^[1-9][0-9]*[smh]$ ]] || fail "PASTEALL_NOTARY_TIMEOUT must look like 3600s, 60m, or 1h"

export DEVELOPER_DIR="$developer_dir"

require_command codesign
require_command ditto
require_command hdiutil
require_command lipo
require_command plutil
require_command security
require_command spctl
require_command xcodebuild
require_command xcrun

identities="$(security find-identity -v -p codesigning)"
[[ "$identities" == *"$signing_identity"* ]] || fail "No '$signing_identity' certificate with private key was found in Keychain"
[[ "$identities" == *"($team_id)"* ]] || fail "No valid signing certificate belongs to Team ID $team_id"

echo "Validating notarization Keychain profile..."
xcrun notarytool history \
    --keychain-profile "$notary_profile" \
    --output-format json >/dev/null

release_name="PasteAll-$version-$build_number"
archive_path="$artifacts_dir/$release_name.xcarchive"
export_path="$artifacts_dir/$release_name-export"
app_path="$export_path/PasteAll.app"
zip_path="$artifacts_dir/$release_name.zip"
dmg_path="$artifacts_dir/$release_name.dmg"

for output_path in "$archive_path" "$export_path" "$zip_path" "$dmg_path"; do
    [[ ! -e "$output_path" ]] || fail "Output already exists: $output_path"
done

mkdir -p "$artifacts_dir" "$derived_data"

temporary_base="${TMPDIR:-/tmp}"
temporary_base="${temporary_base%/}"
work_dir="$(mktemp -d "$temporary_base/paste-all-release.XXXXXX")"

cleanup() {
    case "$work_dir" in
        "$temporary_base"/paste-all-release.*)
            rm -rf -- "$work_dir"
            ;;
    esac
}
trap cleanup EXIT

export_options="$work_dir/ExportOptions.plist"
plutil -create xml1 "$export_options"
plutil -insert destination -string export "$export_options"
plutil -insert method -string developer-id "$export_options"
plutil -insert signingStyle -string manual "$export_options"
plutil -insert signingCertificate -string "$signing_identity" "$export_options"
plutil -insert teamID -string "$team_id" "$export_options"

echo "Archiving universal Release build..."
xcodebuild \
    -project "$project_root/PasteAll.xcodeproj" \
    -scheme PasteAll \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$archive_path" \
    -derivedDataPath "$derived_data" \
    -onlyUsePackageVersionsFromResolvedFile \
    PASTEALL_APP_BUNDLE_ID="$bundle_id" \
    PASTEALL_CORE_BUNDLE_ID="$bundle_id.core" \
    DEVELOPMENT_TEAM="$team_id" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$signing_identity" \
    MARKETING_VERSION="$version" \
    CURRENT_PROJECT_VERSION="$build_number" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    clean archive

echo "Exporting Developer ID signed app..."
xcodebuild \
    -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_path" \
    -exportOptionsPlist "$export_options"

[[ -d "$app_path" ]] || fail "Export did not produce $app_path"

verify_app() {
    local actual_bundle executable core_framework architectures signature_details
    local core_signature_details app_team_id core_team_id entitlements

    codesign --verify --deep --strict --verbose=2 "$app_path"
    actual_bundle="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app_path/Contents/Info.plist")"
    [[ "$actual_bundle" == "$bundle_id" ]] || fail "Exported Bundle ID is $actual_bundle, expected $bundle_id"

    executable="$app_path/Contents/MacOS/PasteAll"
    architectures="$(lipo -archs "$executable")"
    [[ " $architectures " == *" arm64 "* && " $architectures " == *" x86_64 "* ]] || fail "Release is not universal: $architectures"

    signature_details="$(codesign -dv --verbose=4 "$app_path" 2>&1)"
    [[ "$signature_details" == *"Authority=Developer ID Application"* ]] || fail "App is not Developer ID Application signed"
    [[ "$signature_details" == *"runtime"* ]] || fail "Hardened Runtime is not enabled"
    [[ "$signature_details" == *"Timestamp="* ]] || fail "Secure timestamp is missing"

    core_framework="$app_path/Contents/Frameworks/PasteAllCore.framework"
    [[ -d "$core_framework" ]] || fail "Embedded PasteAllCore.framework is missing"
    core_signature_details="$(codesign -dv --verbose=4 "$core_framework" 2>&1)"
    app_team_id="$(sed -n 's/^TeamIdentifier=//p' <<<"$signature_details")"
    core_team_id="$(sed -n 's/^TeamIdentifier=//p' <<<"$core_signature_details")"
    [[ "$app_team_id" == "$team_id" ]] || fail "App Team ID is '${app_team_id:-missing}', expected $team_id"
    [[ "$core_team_id" == "$team_id" ]] || fail "PasteAllCore.framework Team ID is '${core_team_id:-missing}', expected $team_id"

    entitlements="$work_dir/entitlements.plist"
    if codesign -d --entitlements :- "$app_path" >"$entitlements" 2>/dev/null && [[ -s "$entitlements" ]]; then
        if plutil -extract com.apple.security.get-task-allow raw -o - "$entitlements" >/dev/null 2>&1; then
            [[ "$(plutil -extract com.apple.security.get-task-allow raw -o - "$entitlements")" != "true" ]] || fail "Distribution app contains get-task-allow"
        fi
    fi
}

notarize() {
    local payload="$1"
    local label="$2"
    local result_path="$artifacts_dir/$release_name-$label-notary.json"
    local log_path="$artifacts_dir/$release_name-$label-notary-log.json"
    local submission_id status submit_exit

    echo "Submitting $label for notarization..."
    set +e
    xcrun notarytool submit "$payload" \
        --keychain-profile "$notary_profile" \
        --wait \
        --timeout "$notary_timeout" \
        --output-format json >"$result_path"
    submit_exit=$?
    set -e

    [[ -s "$result_path" ]] || fail "notarytool returned no result for $label"
    submission_id="$(plutil -extract id raw -o - "$result_path" 2>/dev/null || true)"
    status="$(plutil -extract status raw -o - "$result_path" 2>/dev/null || true)"

    if [[ -n "$submission_id" ]]; then
        xcrun notarytool log "$submission_id" \
            --keychain-profile "$notary_profile" \
            "$log_path" || true
    fi

    [[ $submit_exit -eq 0 && "$status" == "Accepted" ]] || fail "$label notarization status is '${status:-unknown}'. See $result_path and $log_path"
}

verify_app

echo "Creating ZIP for app notarization..."
ditto -c -k --keepParent "$app_path" "$zip_path"
notarize "$zip_path" app
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
verify_app

echo "Creating DMG..."
dmg_stage="$work_dir/dmg"
mkdir -p "$dmg_stage"
ditto "$app_path" "$dmg_stage/PasteAll.app"
ln -s /Applications "$dmg_stage/Applications"
hdiutil create \
    -volname "PasteAll" \
    -fs HFS+ \
    -format UDZO \
    -srcfolder "$dmg_stage" \
    "$dmg_path"
hdiutil verify "$dmg_path"

notarize "$dmg_path" dmg
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
hdiutil verify "$dmg_path"

echo "Running final Gatekeeper checks..."
spctl --assess --type execute --verbose=4 "$app_path"
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg_path"

echo "Release completed: $dmg_path"
