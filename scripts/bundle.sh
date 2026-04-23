#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="SnapDress"

cd "$PROJECT_DIR"

ARCH=$(uname -m)
BUILD_DIR=".build/${ARCH}-apple-macosx/release"

# Step 1: Initial build to generate resource_bundle_accessor.swift files
echo "==> Building $APP_NAME (release, pass 1)..."
swift build -c release 2>&1 | tail -1

# Step 2: Patch SPM-generated resource accessors to use Bundle.main.resourceURL
echo "==> Patching resource bundle accessors..."
find .build -name "resource_bundle_accessor.swift" | while read f; do
    if grep -q 'bundleURL' "$f"; then
        sed -i '' 's/Bundle\.main\.bundleURL/Bundle.main.resourceURL!/g' "$f"
        echo "   Patched: $(basename "$(dirname "$(dirname "$f")")")"
    fi
done

# Step 3: Rebuild with patched accessors
echo "==> Building $APP_NAME (release, pass 2)..."
swift build -c release

if [ ! -f "$BUILD_DIR/$APP_NAME" ]; then
    echo "ERROR: Binary not found at $BUILD_DIR/$APP_NAME"
    exit 1
fi

# Step 4: Create .app bundle
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
echo "==> Creating app bundle..."
rm -rf "$APP_BUNDLE"

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy resource bundles to Contents/Resources/
for bundle in "$BUILD_DIR"/*.bundle; do
    if [ -d "$bundle" ]; then
        echo "   Copying: $(basename "$bundle")"
        cp -R "$bundle" "$APP_BUNDLE/Contents/Resources/"
    fi
done

# Generate Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.snapdress.app</string>
    <key>CFBundleName</key>
    <string>SnapDress</string>
    <key>CFBundleDisplayName</key>
    <string>SnapDress</string>
    <key>CFBundleExecutable</key>
    <string>SnapDress</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>SnapDress needs screen recording permission to capture screenshots of your selected region.</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Generate .icns from icon PNGs
ICONSET="$PROJECT_DIR/.iconset-staging.iconset"
ICON_SRC="$PROJECT_DIR/SnapDress/Assets.xcassets/AppIcon.appiconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
cp "$ICON_SRC/icon_16x16.png"      "$ICONSET/icon_16x16.png"
cp "$ICON_SRC/icon_16x16@2x.png"   "$ICONSET/icon_16x16@2x.png"
cp "$ICON_SRC/icon_32x32.png"       "$ICONSET/icon_32x32.png"
cp "$ICON_SRC/icon_32x32@2x.png"    "$ICONSET/icon_32x32@2x.png"
cp "$ICON_SRC/icon_128x128.png"     "$ICONSET/icon_128x128.png"
cp "$ICON_SRC/icon_128x128@2x.png"  "$ICONSET/icon_128x128@2x.png"
cp "$ICON_SRC/icon_256x256.png"     "$ICONSET/icon_256x256.png"
cp "$ICON_SRC/icon_256x256@2x.png"  "$ICONSET/icon_256x256@2x.png"
cp "$ICON_SRC/icon_512x512.png"     "$ICONSET/icon_512x512.png"
cp "$ICON_SRC/icon_512x512@2x.png"  "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"
echo "   Created AppIcon.icns"

# PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Step 5: Code sign
echo "==> Code signing..."
# Sign nested bundles first
find "$APP_BUNDLE/Contents/Resources" -name "*.bundle" -exec codesign --force --sign - {} \;
# Sign the main app
codesign --force --sign - "$APP_BUNDLE"

# Step 6: Kill existing instance and install
echo "==> Installing to /Applications..."
pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null && sleep 0.5 || true
if [ -d "/Applications/$APP_NAME.app" ]; then
    rm -rf "/Applications/$APP_NAME.app"
fi
cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
xattr -cr "/Applications/$APP_NAME.app" 2>/dev/null || true

echo ""
echo "✅ Done! $APP_NAME.app installed to /Applications"
echo "   Launch with: open /Applications/$APP_NAME.app"
echo ""
echo "NOTE: On first launch, grant Screen Recording permission in"
echo "      System Settings > Privacy & Security > Screen Recording"
