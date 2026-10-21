#!/bin/zsh
# Builds Barkeep.app into ./build. Sandboxed, no network entitlement, ad-hoc signed.
set -euo pipefail
cd "${0:A:h}"

swift build -c release
app=build/Barkeep.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
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
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST

codesign --force --sign - --entitlements Barkeep.entitlements "$app"
codesign -d --entitlements - "$app" 2>/dev/null | grep -q network && { echo "FAIL: network entitlement present"; exit 1; }
echo "built $app"
