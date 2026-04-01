#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="SnapDress"
VERSION="1.0.0"
DMG_NAME="${APP_NAME}-${VERSION}"

cd "$PROJECT_DIR"

# Step 1: Build and bundle the app first
echo "==> Building app..."
"$SCRIPT_DIR/bundle.sh"

APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
if [ ! -d "$APP_BUNDLE" ]; then
    echo "ERROR: $APP_BUNDLE not found"
    exit 1
fi

# Step 2: Create a temporary directory for DMG contents
DMG_STAGING="$PROJECT_DIR/.dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

# Copy app bundle
cp -R "$APP_BUNDLE" "$DMG_STAGING/"

# Create symlink to /Applications for drag-and-drop install
ln -s /Applications "$DMG_STAGING/Applications"

# Step 3: Create the DMG
DMG_OUTPUT="$PROJECT_DIR/$DMG_NAME.dmg"
rm -f "$DMG_OUTPUT"

echo "==> Creating DMG..."
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_OUTPUT"

# Clean up staging
rm -rf "$DMG_STAGING"

echo ""
echo "✅ DMG created: $DMG_OUTPUT"
echo "   Share this file with your friends!"
echo ""
echo "   They just need to:"
echo "   1. Open the DMG"
echo "   2. Drag $APP_NAME to Applications"
echo "   3. Launch and grant Screen Recording permission"
