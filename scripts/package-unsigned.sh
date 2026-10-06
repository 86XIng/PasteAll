#!/bin/bash
# Builds the ad-hoc signed universal app and packages it for a GitHub Release:
#   dist/PasteAll-<version>.dmg  drag-to-install image with a bilingual install guide
#   dist/PasteAll-<version>.zip  used by the Homebrew cask
# plus a .sha256 file for each. Used by .github/workflows/release.yml until a
# Developer ID is available.
#
# The DMG layout is written by dmgbuild (PASTEALL_DMGBUILD, or `dmgbuild` on
# PATH); without either, a pinned copy is installed into a temporary venv.

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${PASTEALL_VERSION:-}"
build_number="${PASTEALL_BUILD_NUMBER:-1}"
artifacts_dir="${PASTEALL_ARTIFACTS_DIR:-$project_root/dist}"
derived_data="${PASTEALL_UNIVERSAL_DERIVED_DATA:-/tmp/PasteAllUniversalDerivedData}"
dmgbuild="${PASTEALL_DMGBUILD:-}"
dmgbuild_version="1.6.7"

fail() {
    echo "Packaging failed: $*" >&2
    exit 1
}

# Mounts the image read-only and checks what a user will see in it.
verify_dmg_contents() {
    local mount_point="$work_dir/mount"
    mkdir -p "$mount_point"
    hdiutil attach -quiet -readonly -nobrowse -mountpoint "$mount_point" "$dmg_path"
    local status=0
    [[ -d "$mount_point/PasteAll.app" ]] || status=1
    [[ -L "$mount_point/Applications" ]] || status=1
    [[ -f "$mount_point/安装说明 Install Guide.rtf" ]] || status=1
    [[ -f "$mount_point/.DS_Store" ]] || status=1
    [[ -f "$mount_point/.background.tiff" || -f "$mount_point/.background.png" ]] || status=1
    codesign --verify --deep --strict "$mount_point/PasteAll.app" || status=1
    hdiutil detach -quiet "$mount_point"
    [[ $status -eq 0 ]] || fail "DMG is missing the app, Applications link, guide, layout, or background"
}

[[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || fail "PASTEALL_VERSION must look like 1.0 or 1.0.0"
[[ "$build_number" =~ ^[1-9][0-9]*$ ]] || fail "PASTEALL_BUILD_NUMBER must be a positive integer"

zip_path="$artifacts_dir/PasteAll-$version.zip"
dmg_path="$artifacts_dir/PasteAll-$version.dmg"
for output_path in "$zip_path" "$dmg_path"; do
    [[ ! -e "$output_path" ]] || fail "Output already exists: $output_path"
done

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/paste-all-package.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

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

# The guide is RTF so it opens formatted in TextEdit, with the command easy to copy.
guide_path="$work_dir/安装说明 Install Guide.rtf"
textutil -convert rtf -inputencoding UTF-8 \
    "$project_root/packaging/dmg/install-guide.html" -output "$guide_path"

if [[ -z "$dmgbuild" ]]; then
    if command -v dmgbuild >/dev/null 2>&1; then
        dmgbuild="$(command -v dmgbuild)"
    else
        python3 -m venv "$work_dir/venv"
        "$work_dir/venv/bin/pip" install --quiet --disable-pip-version-check "dmgbuild==$dmgbuild_version"
        dmgbuild="$work_dir/venv/bin/dmgbuild"
    fi
fi

# The volume name, with the version, is the window title and path bar label.
"$dmgbuild" \
    -s "$project_root/packaging/dmg/dmg-settings.py" \
    -D settings_dir="$project_root/packaging/dmg" \
    -D app="$app_path" \
    -D guide="$guide_path" \
    "PasteAll $version" "$dmg_path"
hdiutil verify -quiet "$dmg_path"
verify_dmg_contents

for output_path in "$zip_path" "$dmg_path"; do
    (cd "$artifacts_dir" && shasum -a 256 "$(basename "$output_path")" >"$(basename "$output_path").sha256")
    echo "Packaged $output_path"
    cat "$output_path.sha256"
done
