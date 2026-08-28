#!/bin/bash
# Build Nimbus.app into build/. No Xcode required, just the command line tools.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/Nimbus.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Nimbus "$APP/Contents/MacOS/Nimbus"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Bundle the UI sound clips so NSSound can find them under Resources/Sounds.
if [ -d Resources/Sounds ]; then
    cp -R Resources/Sounds "$APP/Contents/Resources/Sounds"
fi

if [ ! -f Resources/Nimbus.icns ]; then
    swift tools/makeicon.swift || true
fi
[ -f Resources/Nimbus.icns ] && cp Resources/Nimbus.icns "$APP/Contents/Resources/Nimbus.icns"

codesign --force --sign - "$APP"
echo "Built $APP"

# Install to /Applications so it's launchable from Spotlight / Launchpad.
DEST="/Applications/Nimbus.app"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
echo "Installed $DEST"
