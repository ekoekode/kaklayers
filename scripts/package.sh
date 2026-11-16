#!/bin/zsh
# Builds dist/KaKLayers.app from the release binary (Command Line Tools only, ad-hoc signed).
set -e
cd "$(dirname "$0")/.."
swift build -c release 2>&1 | grep -E "error|Build complete"
BIN="$(swift build -c release --show-bin-path 2>/dev/null | tail -1)/KaKLayers"
APP=dist/KaKLayers.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/KaKLayers"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>KāKLayers</string>
<key>CFBundleDisplayName</key><string>KāKLayers</string>
<key>CFBundleExecutable</key><string>KaKLayers</string>
<key>CFBundleIdentifier</key><string>app.kaklayers.KaKLayers</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PL
codesign --force --deep --sign - "$APP" 2>&1 | tail -1
codesign --verify --deep --strict "$APP" && echo "signature OK"
(cd dist && rm -f KaKLayers.zip && ditto -c -k --keepParent KaKLayers.app KaKLayers.zip)
echo "built: $PWD/$APP"
