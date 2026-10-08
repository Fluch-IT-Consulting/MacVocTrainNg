#!/bin/zsh
# Builds a distributable disk image: build/release/MacVocTrain-<version>.dmg
#
# The app is signed with SIGN_IDENTITY if given, otherwise with the certificate Xcode
# signs local builds with (Config/Signing.local.xcconfig), otherwise ad hoc. Unless
# it is notarised, Gatekeeper asks the recipient to allow the app once (System
# Settings → Privacy & Security → Open Anyway). An ad-hoc signature changes with
# every build, so it asks again after every update; a certificate keeps the
# signature, and `brew upgrade` carries the approval over to the new version.
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
#
# --draft attaches the image to a GitHub release draft v<version> on the current
# commit. Publishing the draft creates the tag and updates the Homebrew cask
# (.github/workflows/tap-bump.yml). It needs a clean checkout of origin/main and a
# version without a release, and refuses to sign ad hoc.
#
# --build-only only builds and checks the app, with warnings as errors, and stops
# before signing, the disk image and notarisation. The CI (.github/workflows/ci.yml)
# runs it, so the release settings live only here.

set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
    echo "usage: $0 [--draft | --build-only]" >&2
    exit 2
}

DRAFT=false
BUILD_ONLY=false
(( $# <= 1 )) || usage
case "${1:-}" in
    "") ;;
    --draft) DRAFT=true ;;
    --build-only) BUILD_ONLY=true ;;
    *) usage ;;
esac

fail() {
    echo "✗ $1" >&2
    exit 1
}

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUILD_DIR=build/release
APP_NAME=MacVocTrain
VERSION=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' MacVocTrainNg.xcodeproj/project.pbxproj | head -1)
TAG="v$VERSION"
DMG="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

# Checked before the build, which takes a while.
if $DRAFT; then
    [[ -z "$(git status --porcelain)" ]] || fail "The working tree is not clean."
    git fetch --quiet origin main
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "HEAD is not origin/main."
    if gh release view "$TAG" >/dev/null 2>&1; then
        fail "Release $TAG already exists; raise MARKETING_VERSION."
    fi
    if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null; then
        fail "Tag $TAG already exists; raise MARKETING_VERSION."
    fi
fi

BUILD_SETTINGS=(ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO)
if $BUILD_ONLY; then
    BUILD_SETTINGS+=(SWIFT_TREAT_WARNINGS_AS_ERRORS=YES)
fi

echo "▸ Building $APP_NAME $VERSION (Release, Apple Silicon + Intel)"
rm -rf "$BUILD_DIR"
xcodebuild -project MacVocTrainNg.xcodeproj -scheme MacVocTrainNg -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    "${BUILD_SETTINGS[@]}" \
    build -quiet

APP="$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME.app"
echo "  architectures: $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"

if $BUILD_ONLY; then
    echo "✓ $APP"
    exit 0
fi

IDENTITY="${SIGN_IDENTITY:-}"
IDENTITY_NAME="$IDENTITY"
XCODE_SIGNATURE=$(codesign -dvv "$APP" 2>&1)
if [[ -z "$IDENTITY" && "$XCODE_SIGNATURE" != *Signature=adhoc* ]]; then
    # Xcode signed with the certificate from Config/Signing.local.xcconfig. Its hash
    # names exactly that one; its name would also match a renewed certificate.
    codesign -d --extract-certificates="$BUILD_DIR/cert" "$APP" 2>/dev/null
    IDENTITY=$(openssl x509 -inform DER -in "$BUILD_DIR/cert0" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')
    IDENTITY_NAME=$(awk -F= '/^Authority=/ {print $2; exit}' <<< "$XCODE_SIGNATURE")
    rm -f "$BUILD_DIR"/cert*
fi

# Always re-sign: Xcode's local signing adds the debugging entitlement
# get-task-allow, which doesn't belong in a distributed app.
if [[ -n "$IDENTITY" ]]; then
    echo "▸ Signing with $IDENTITY_NAME"
    codesign --force --options runtime --timestamp \
        --entitlements MacVocTrainNg/MacVocTrainNg.entitlements \
        --sign "$IDENTITY" "$APP"
else
    if $DRAFT; then
        fail "A release needs a certificate: with an ad-hoc signature Homebrew can't carry the approval over to the next version. See Config/Signing.xcconfig."
    fi
    echo "▸ Signing ad hoc (recipients must allow the app once and after every update)"
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

if $DRAFT; then
    echo "▸ Creating release draft $TAG"
    gh release create "$TAG" "$DMG" --draft --target "$(git rev-parse HEAD)" \
        --title "$TAG" --generate-notes
fi
