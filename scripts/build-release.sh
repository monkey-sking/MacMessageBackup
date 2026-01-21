#!/bin/bash
# Mac Message Backup - Release Build Script
# Usage: ./scripts/build-release.sh

set -e  # Exit on error

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
SCHEME="MacMessageBackup"
PROJECT="MacMessageBackup.xcodeproj"

echo "🔧 Building Mac Message Backup (Release)..."
echo "   Project: $PROJECT_DIR"

# Clean build directory
rm -rf "$BUILD_DIR/MacMessageBackup.xcarchive"
mkdir -p "$BUILD_DIR/Release"

# Archive the project
echo ""
echo "📦 Creating archive..."
xcodebuild -project "$PROJECT_DIR/$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$BUILD_DIR/MacMessageBackup.xcarchive" \
    archive \
    -quiet

# Extract .app from archive
echo ""
echo "📂 Extracting application..."
rm -rf "$BUILD_DIR/Release/MacMessageBackup.app"
cp -R "$BUILD_DIR/MacMessageBackup.xcarchive/Products/Applications/MacMessageBackup.app" \
    "$BUILD_DIR/Release/"

# Get version info
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
    "$BUILD_DIR/Release/MacMessageBackup.app/Contents/Info.plist" 2>/dev/null || echo "1.0.0")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" \
    "$BUILD_DIR/Release/MacMessageBackup.app/Contents/Info.plist" 2>/dev/null || echo "1")

# Create zip for distribution (optional)
echo ""
echo "📦 Creating distribution zip..."
cd "$BUILD_DIR/Release"
rm -f "MacMessageBackup-$VERSION.zip"
zip -r -q "MacMessageBackup-$VERSION.zip" MacMessageBackup.app
cd - > /dev/null

# Summary
APP_SIZE=$(du -sh "$BUILD_DIR/Release/MacMessageBackup.app" | cut -f1)
ZIP_SIZE=$(du -sh "$BUILD_DIR/Release/MacMessageBackup-$VERSION.zip" | cut -f1)

echo ""
echo "✅ Build completed successfully!"
echo ""
echo "   Version: $VERSION ($BUILD)"
echo "   Output:  $BUILD_DIR/Release/"
echo ""
echo "   📱 MacMessageBackup.app         ($APP_SIZE)"
echo "   📦 MacMessageBackup-$VERSION.zip ($ZIP_SIZE)"
echo ""
echo "   You can copy the .app to /Applications or distribute the .zip file."
