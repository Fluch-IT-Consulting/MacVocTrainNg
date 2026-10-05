#!/bin/zsh
# Builds a distributable disk image: build/release/MacVocTrain-<version>.dmg
#
# Without options the app is ad-hoc signed: it runs on other Macs, but Gatekeeper
# asks the recipient to allow it once (System Settings → Privacy & Security →
# Open Anyway).
#
# With an Apple Developer ID the app is signed properly and, if a notary profile
# is given, notarised, so it opens without any warning:
#
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
#   NOTARY_PROFILE=macvoctrain \
#   Tools/make-release.sh
#
# Create the notary profile once with:
#   xcrun notarytool store-credentials macvoctrain --apple-id <id> --team-id <TEAMID>

set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUILD_DIR=build/release
APP_NAME=MacVocTrain
VERSION=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' MacVocTrainNg.xcodeproj/project.pbxproj | head -1)
DMG="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

echo "▸ Building $APP_NAME $VERSION (Release, Apple Silicon + Intel)"
rm -rf "$BUILD_DIR"
xcodebuild -project MacVocTrainNg.xcodeproj -scheme MacVocTrainNg -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    build -quiet

APP="$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME.app"
echo "  architectures: $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"

# Always re-sign: Xcode's local signing adds the debugging entitlement
# get-task-allow, which doesn't belong in a distributed app.
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    echo "▸ Signing with $SIGN_IDENTITY"
    codesign --force --options runtime --timestamp \
        --entitlements MacVocTrainNg/MacVocTrainNg.entitlements \
        --sign "$SIGN_IDENTITY" "$APP"
else
    echo "▸ Signing ad hoc (recipients must allow the app once)"
    codesign --force --options runtime \
        --entitlements MacVocTrainNg/MacVocTrainNg.entitlements \
        --sign - "$APP"
fi
codesign --verify --strict "$APP"

echo "▸ Creating disk image"
STAGING="$BUILD_DIR/dmg"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" -quiet
rm -rf "$STAGING"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        echo "▸ Notarising (this can take a few minutes)"
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
    fi
fi

echo "✓ $DMG ($(du -h "$DMG" | cut -f1))"
