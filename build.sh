#!/bin/bash
# Builds AltTabber.app and installs it to ~/Applications.
# Signs ad hoc by default, which means granting Accessibility again after each rebuild.
# Set SIGN_ID to a signing identity of your own to keep the grant across rebuilds.
set -euo pipefail
cd "$(dirname "$0")"

# Universal: runs on Apple silicon and Intel.
swift build -c release --arch arm64 --arch x86_64
app=build/AltTabber.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/apple/Products/Release/AltTabber "$app/Contents/MacOS/AltTabber"
cp Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
codesign --force --options runtime --timestamp=none --sign "${SIGN_ID:--}" "$app"

[[ "${1:-}" == "--no-install" ]] && { echo "Built $app"; exit 0; }
pkill -x AltTabber 2>/dev/null || true
rm -rf ~/Applications/AltTabber.app
mkdir -p ~/Applications
cp -R "$app" ~/Applications/
echo "Installed ~/Applications/AltTabber.app"
