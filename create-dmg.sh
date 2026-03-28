#!/bin/bash
set -e

echo ""
echo "  🦀 Claw'd Notch — DMG Builder"
echo "  =============================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ClawdNotch"
DMG_NAME="Clawd-Notch"
BUILD_DIR="$SCRIPT_DIR/build"
DMG_DIR="$BUILD_DIR/dmg"
DMG_OUTPUT="$SCRIPT_DIR/$DMG_NAME.dmg"

# --- Step 1: Build Release ---
echo "→ Building release..."
xcodebuild -project "$SCRIPT_DIR/ClawdNotch.xcodeproj" \
    -scheme ClawdNotch \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGN_IDENTITY="-" \
    -quiet 2>&1 | tail -1

APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "  ✗ Build failed"
    exit 1
fi
echo "  ✓ Built successfully"

# --- Step 2: Create DMG contents ---
echo "→ Preparing DMG..."
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

# Copy app
cp -r "$APP_PATH" "$DMG_DIR/$APP_NAME.app"

# Create Applications symlink
ln -s /Applications "$DMG_DIR/Applications"

# --- Step 3: Create DMG ---
echo "→ Creating DMG..."
rm -f "$DMG_OUTPUT"
hdiutil create \
    -volname "Claw'd Notch" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_OUTPUT" \
    > /dev/null 2>&1

echo "  ✓ DMG created: $DMG_OUTPUT"

# --- Cleanup ---
rm -rf "$DMG_DIR"

SIZE=$(du -h "$DMG_OUTPUT" | cut -f1)
echo ""
echo "  ✓ $DMG_NAME.dmg ($SIZE)"
echo "  Users drag ClawdNotch.app → Applications, hooks auto-configure on first launch."
echo ""
