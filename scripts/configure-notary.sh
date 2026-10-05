#!/bin/bash

set -euo pipefail

developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
profile="${PASTEALL_NOTARY_PROFILE:-paste-all-notary}"

if [[ ! -d "$developer_dir" ]]; then
    echo "Xcode developer directory not found: $developer_dir" >&2
    exit 1
fi

export DEVELOPER_DIR="$developer_dir"

read -r -p "Apple ID email: " apple_id
read -r -p "Developer Team ID: " team_id

if [[ -z "$apple_id" || ! "$team_id" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "Apple ID is required and Team ID must be 10 uppercase letters or digits." >&2
    exit 2
fi

echo "The next prompt asks for an app-specific password and stores it in your login Keychain."
xcrun notarytool store-credentials "$profile" \
    --apple-id "$apple_id" \
    --team-id "$team_id"

echo "Stored notarization credentials in Keychain profile: $profile"
