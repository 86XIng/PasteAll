#!/bin/bash
# Exercises Launch Services delivery and real code-signature authentication.
# Requires a logged-in macOS GUI session. Uses only disposable apps in /tmp.
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$(mktemp -d /tmp/pasteall-ipc.XXXXXX)"
# The sandboxed sender gets a container named after its unique bundle ID.
container="$HOME/Library/Containers/io.github.86xing.IPCTest.$$.Host.FinderExtension"
trap 'rm -rf "$work_dir" "$container"' EXIT
host="$work_dir/Host.app"
extension="$host/Contents/PlugIns/PasteAllFinderExtension.appex"
attacker="$work_dir/Attacker.app"
log="$work_dir/events.log"
touch "$log"

make_bundle() {
    local bundle="$1" identifier="$2"
    mkdir -p "$bundle/Contents/MacOS"
    cat >"$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$identifier</string>
<key>CFBundleExecutable</key><string>Executable</string>
<key>LSUIElement</key><true/>
<key>CFBundleURLTypes</key><array><dict>
<key>CFBundleURLSchemes</key><array><string>pasteall-finder</string></array>
</dict></array>
<key>IPCLogPath</key><string>$log</string>
</dict></plist>
PLIST
}

make_bundle "$host" "io.github.86xing.IPCTest.$$.Host"
make_bundle "$extension" "io.github.86xing.IPCTest.$$.Host.FinderExtension"
make_bundle "$attacker" "io.github.86xing.IPCTest.$$.Host.FinderExtension"
# A copied bundle identifier is not authentication. Give the impostor distinct
# signed contents while keeping its claimed identifier identical.
/usr/libexec/PlistBuddy -c 'Add :IPCImpostor bool true' "$attacker/Contents/Info.plist"
swiftc -parse-as-library \
    "$project_root/Sources/PasteAll/FinderPasteRequest.swift" \
    "$project_root/Tests/FinderIPC/Sender.swift" \
    -o "$extension/Contents/MacOS/Executable"
cp "$extension/Contents/MacOS/Executable" "$attacker/Contents/MacOS/Executable"
swiftc -parse-as-library \
    "$project_root/Sources/PasteAll/FinderPasteRequest.swift" \
    "$project_root/Sources/PasteAll/FinderPasteReceiver.swift" \
    "$project_root/Tests/FinderIPC/Host.swift" \
    -o "$host/Contents/MacOS/Executable"
codesign --force --sign - --entitlements \
    "$project_root/Sources/PasteAllFinderExtension/PasteAllFinderExtension.entitlements" "$extension"
codesign --force --sign - "$attacker"
codesign --force --sign - "$host"

"$extension/Contents/MacOS/Executable" "$host" trusted
"$attacker/Contents/MacOS/Executable" "$host" attacker
# The disposable host exits ten seconds after launch.
sleep 5
cat "$log"
grep -qx 'launchRequest true' "$log"
[[ "$(grep -c '^authenticated$' "$log")" == 2 ]]
[[ "$(grep -c '^rejected$' "$log")" == 2 ]]
grep -qx 'delivered /trusted-cold' "$log"
grep -qx 'delivered /trusted-warm' "$log"
! grep -q '^delivered /attacker' "$log"
echo 'Finder IPC integration passed (sandboxed cold/warm sender; unrelated sender rejected).'
