#!/bin/bash
# Builds AltTabber.app and installs it to ~/Applications.
# Signs ad hoc by default, which means granting Accessibility again after each rebuild.
# Set SIGN_ID to a signing identity of your own to keep the grant across rebuilds.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
app=build/AltTabber.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/AltTabber "$app/Contents/MacOS/AltTabber"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --options runtime --timestamp=none --sign "${SIGN_ID:--}" "$app"

[[ "${1:-}" == "--no-install" ]] && { echo "Built $app"; exit 0; }
pkill -x AltTabber 2>/dev/null || true
rm -rf ~/Applications/AltTabber.app
mkdir -p ~/Applications
cp -R "$app" ~/Applications/
echo "Installed ~/Applications/AltTabber.app"
