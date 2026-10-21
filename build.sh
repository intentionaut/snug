#!/bin/zsh
# Builds Barkeep.app into ./build, signed with the Apple Development identity so macOS keeps the
# Accessibility grant across rebuilds. Not sandboxed: a sandboxed app can't read or move other
# apps' menu bar icons. Instead the build fails if the binary references any networking API.
set -euo pipefail
cd "${0:A:h}"

swift build -c release
app=build/Barkeep.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp design/Barkeep.icns "$app/Contents/Resources/Barkeep.icns"
cp .build/release/Barkeep "$app/Contents/MacOS/Barkeep"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.elle.barkeep</string>
  <key>CFBundleName</key><string>Barkeep</string>
  <key>CFBundleExecutable</key><string>Barkeep</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>CFBundleIconFile</key><string>Barkeep</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST

./check-no-network.sh .build/release/Barkeep
codesign --force --sign "Apple Development" "$app"
# Install where a login item can rely on it staying put; build/ is wiped on every build.
mkdir -p ~/Applications
rm -rf ~/Applications/Barkeep.app
cp -R "$app" ~/Applications/Barkeep.app
echo "built $app, installed ~/Applications/Barkeep.app"
