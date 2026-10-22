#!/bin/zsh
# Builds Snug.app into ./build, signed with the Apple Development identity so macOS keeps the
# Accessibility grant across rebuilds. Not sandboxed: a sandboxed app can't read or move other
# apps' menu bar icons. Instead the build fails if the binary references any networking API.
set -euo pipefail
cd "${0:A:h}"

swift build -c release
app=build/Snug.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp design/Snug.icns "$app/Contents/Resources/Snug.icns"
cp .build/release/Snug "$app/Contents/MacOS/Snug"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.intentionaut.snug</string>
  <key>CFBundleName</key><string>Snug</string>
  <key>CFBundleExecutable</key><string>Snug</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>CFBundleIconFile</key><string>Snug</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST

./check-no-network.sh .build/release/Snug
codesign --force --sign "Apple Development" "$app"
# Install where a login item can rely on it staying put; build/ is wiped on every build.
mkdir -p ~/Applications
rm -rf ~/Applications/Snug.app
cp -R "$app" ~/Applications/Snug.app
echo "built $app, installed ~/Applications/Snug.app"
