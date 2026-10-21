#!/bin/bash
# Builds AltTab.app and installs it to ~/Applications.
# Signed with a stable identity so the Accessibility grant survives rebuilds.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
app=build/AltTab.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/AltTab "$app/Contents/MacOS/AltTab"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign "${SIGN_ID:--}" "$app"

pkill -x AltTab 2>/dev/null || true
rm -rf ~/Applications/AltTab.app
mkdir -p ~/Applications
cp -R "$app" ~/Applications/
echo "Installed ~/Applications/AltTab.app"
