#!/bin/zsh
# Builds ExposeLabels.app from source. No dependencies beyond the Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"
APP=build/ExposeLabels.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# App icon
if [[ ! -f build/AppIcon.icns ]]; then
  swiftc -O tools/make-icon.swift -o build/make-icon && build/make-icon build/icon-1024.png
  ISET=build/AppIcon.iconset; rm -rf $ISET; mkdir -p $ISET
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon-1024.png --out $ISET/icon_${s}x${s}.png >/dev/null
    sips -z $((s*2)) $((s*2)) build/icon-1024.png --out $ISET/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns $ISET -o build/AppIcon.icns && rm -rf $ISET build/make-icon
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
swiftc -O -target arm64-apple-macos14.0 Sources/*.swift -o build/el-arm64
swiftc -O -target x86_64-apple-macos14.0 Sources/*.swift -o build/el-x86_64
lipo -create build/el-arm64 build/el-x86_64 -output "$APP/Contents/MacOS/ExposeLabels"
rm build/el-arm64 build/el-x86_64
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.uros.exposelabels</string>
  <key>CFBundleName</key><string>ExposeLabels</string>
  <key>CFBundleExecutable</key><string>ExposeLabels</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
