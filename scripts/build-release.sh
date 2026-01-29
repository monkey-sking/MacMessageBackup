#!/bin/bash
# Mac Message Backup - Release Build Script
# Usage: ./scripts/build-release.sh

set -e  # Exit on error

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
SCHEME="MacMessageBackup"
PROJECT="MacMessageBackup.xcodeproj"

# Load local config if exists
if [ -f "$PROJECT_DIR/scripts/config.sh" ]; then
    source "$PROJECT_DIR/scripts/config.sh"
fi

echo "🔧 Building Mac Message Backup (Release)..."
echo "   Project: $PROJECT_DIR"

# Check if TEAM_ID is set
if [ -z "$TEAM_ID" ]; then
    echo "⚠️  Warning: TEAM_ID not set in scripts/config.sh. Signing may fail."
    CODE_SIGN_FLAGS=()
else
    CODE_SIGN_FLAGS=(
        "DEVELOPMENT_TEAM=$TEAM_ID" 
        "CODE_SIGN_STYLE=Manual" 
        "CODE_SIGN_IDENTITY=Developer ID Application"
    )
    
    # Generate ExportOptions.plist dynamically to avoid hardcoding Team ID
    cat <<EOF > "$PROJECT_DIR/scripts/ExportOptions.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>destination</key>
    <string>export</string>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
</dict>
</plist>
EOF
fi

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
    "${CODE_SIGN_FLAGS[@]}" \
    archive \
    -quiet

# Export the signed app
echo ""
echo "🚢 Exporting signed application..."
rm -rf "$BUILD_DIR/Release/MacMessageBackup.app"

if [ -f "$PROJECT_DIR/scripts/ExportOptions.plist" ]; then
    xcodebuild -exportArchive \
        -archivePath "$BUILD_DIR/MacMessageBackup.xcarchive" \
        -exportOptionsPlist "$PROJECT_DIR/scripts/ExportOptions.plist" \
        -exportPath "$BUILD_DIR/Release" \
        -quiet
else
    echo "📂 Extracting application without signing..."
    cp -R "$BUILD_DIR/MacMessageBackup.xcarchive/Products/Applications/MacMessageBackup.app" \
        "$BUILD_DIR/Release/"
fi

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
