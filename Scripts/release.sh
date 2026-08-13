#!/bin/bash
# Builds a signed Release, packages a notarized DMG, signs it with Sparkle's
# (from the login Keychain), and regenerates appcast.xml at the repo root.
#
# Usage: Scripts/release.sh
# Output: dist/bulletproof-<version>.dmg and appcast.xml
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="$ROOT/DerivedData"
DIST="$ROOT/dist"
REPO_SLUG="myusuf3/bulletproof"

fail() { echo "error: $*" >&2; exit 1; }

# Releases must be Developer ID signed + notarized - a silent fallback to
# development signing ships an artifact Gatekeeper blocks on every download.
# Set ALLOW_DEV_SIGNING=1 only for local pipeline testing, never to publish.
if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    IDENTITY="Developer ID Application"
    SIGN_ARGS=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$IDENTITY")
elif [ "${ALLOW_DEV_SIGNING:-0}" = "1" ]; then
    IDENTITY="Apple Development"
    SIGN_ARGS=("CODE_SIGN_IDENTITY=$IDENTITY")
    echo "warning: ALLOW_DEV_SIGNING=1 - this artifact must not be published."
else
    fail "no Developer ID Application certificate in the keychain - unlock it or fix the cert. Refusing to build a Gatekeeper-blocked release."
fi
echo "==> Signing identity: $IDENTITY"

if [ "$IDENTITY" = "Developer ID Application" ]; then
    # Archive + export-for-Developer-ID is the only build path that satisfies
    # notarization: it strips get-task-allow, signs with secure timestamps,
    # and re-signs Sparkle's nested Updater.app/Autoupdate binaries.
    echo "==> Archiving Release"
    ARCHIVE="$DERIVED/bulletproof.xcarchive"
    rm -rf "$ARCHIVE"
    xcodebuild -project "$ROOT/bulletproof.xcodeproj"  -skipPackagePluginValidation -skipMacroValidation \
        -scheme bulletproof \
        -configuration Release \
        -derivedDataPath "$DERIVED" \
        -archivePath "$ARCHIVE" \
        archive | tail -3
    echo "==> Exporting with Developer ID signing"
    rm -rf "$DERIVED/export"
    xcodebuild -exportArchive  -skipPackagePluginValidation -skipMacroValidation \
        -archivePath "$ARCHIVE" \
        -exportOptionsPlist "$ROOT/Scripts/ExportOptions.plist" \
        -exportPath "$DERIVED/export" | tail -3
    APP="$DERIVED/export/bulletproof.app"
else
    echo "==> Building Release"
    xcodebuild -project "$ROOT/bulletproof.xcodeproj"  -skipPackagePluginValidation -skipMacroValidation \
        -scheme bulletproof \
        -configuration Release \
        -derivedDataPath "$DERIVED" \
        "${SIGN_ARGS[@]}" \
        build | tail -3
    APP="$DERIVED/Build/Products/Release/bulletproof.app"
fi
[ -d "$APP" ] || fail "built app not found at $APP"

echo "==> Verifying code signature"
codesign --verify --strict --deep "$APP"
codesign -dv "$APP" 2>&1 | grep -E "^(Identifier|Authority|TeamIdentifier)" || true

VERSION="$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)"
BUILD="$(defaults read "$APP/Contents/Info" CFBundleVersion)"
MIN_OS="$(defaults read "$APP/Contents/Info" LSMinimumSystemVersion)"
[ -n "$VERSION" ] || fail "could not read CFBundleShortVersionString"
defaults read "$APP/Contents/Info" SUFeedURL >/dev/null || fail "SUFeedURL missing from app Info.plist"
defaults read "$APP/Contents/Info" SUPublicEDKey >/dev/null || fail "SUPublicEDKey missing from app Info.plist"

# Notarize + staple when Developer ID signed. Requires one-time credential
# setup: xcrun notarytool store-credentials bulletproof-notary
if [ "$IDENTITY" = "Developer ID Application" ]; then
    NOTARY_PROFILE="${NOTARY_PROFILE:-bulletproof-notary}"
    echo "==> Notarizing (keychain profile: $NOTARY_PROFILE)"
    SUBMIT_ZIP="$(mktemp -d)/bulletproof-notarize.zip"
    ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"
    NOTARY_OUT="$(xcrun notarytool submit "$SUBMIT_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)" || {
        echo "$NOTARY_OUT"
        fail "notarytool submit failed"
    }
    echo "$NOTARY_OUT" | tail -4
    echo "$NOTARY_OUT" | grep -q "status: Accepted" || {
        SUBMISSION_ID="$(echo "$NOTARY_OUT" | awk '/^  id:/{print $2; exit}')"
        fail "notarization not accepted - inspect with: xcrun notarytool log $SUBMISSION_ID --keychain-profile $NOTARY_PROFILE"
    }
    rm -f "$SUBMIT_ZIP"
    echo "==> Stapling notarization ticket"
    xcrun stapler staple "$APP" | tail -1
    spctl --assess --type execute "$APP" && echo "    Gatekeeper assessment: accepted"
fi

# DMG for both the release download (drag-to-Applications guides users to
# replace stale copies) and the Sparkle enclosure (Sparkle 2 mounts DMGs).
echo "==> Building DMG for v$VERSION (build $BUILD)"
mkdir -p "$DIST"
DMG="$DIST/bulletproof-$VERSION.dmg"
rm -f "$DMG"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "bulletproof" -srcfolder "$STAGING" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGING"

if [ "$IDENTITY" = "Developer ID Application" ]; then
    echo "==> Signing and notarizing DMG"
    codesign --sign "Developer ID Application" --timestamp "$DMG"
    DMG_NOTARY_OUT="$(xcrun notarytool submit "$DMG" --keychain-profile "${NOTARY_PROFILE:-bulletproof-notary}" --wait 2>&1)" || {
        echo "$DMG_NOTARY_OUT"
        fail "DMG notarization submit failed"
    }
    echo "$DMG_NOTARY_OUT" | grep -q "status: Accepted" || fail "DMG notarization not accepted"
    xcrun stapler staple "$DMG" | tail -1
    spctl --assess --type open --context context:primary-signature "$DMG" && echo "    DMG Gatekeeper assessment: accepted"
fi

SIGN_UPDATE="$(find "$DERIVED/SourcePackages/artifacts" -type f -name sign_update -not -path "*old_dsa*" | head -1)"
[ -x "$SIGN_UPDATE" ] || fail "sign_update not found under $DERIVED/SourcePackages (run xcodebuild -resolvePackageDependencies first)"

# Interactive runs read the key from the login Keychain (macOS prompts to
# allow sign_update on first use). Non-interactive runs can export the key
# with `generate_keys -x <file>` and point SPARKLE_ED_KEY_FILE at it.
if [ -n "${SPARKLE_ED_KEY_FILE:-}" ]; then
    echo "==> Signing DMG with Sparkle EdDSA key file"
    SIG_ATTRS="$("$SIGN_UPDATE" --ed-key-file "$SPARKLE_ED_KEY_FILE" "$DMG")"
else
    echo "==> Signing DMG with Sparkle EdDSA key (login Keychain)"
    SIG_ATTRS="$("$SIGN_UPDATE" "$DMG")"
fi
echo "    $SIG_ATTRS"
echo "$SIG_ATTRS" | grep -q 'sparkle:edSignature="' || fail "sign_update did not produce an EdDSA signature"

echo "==> Writing appcast.xml"
DOWNLOAD_URL="https://github.com/$REPO_SLUG/releases/download/v$VERSION/bulletproof-$VERSION.dmg"
PUB_DATE="$(LC_ALL=en_US date -u '+%a, %d %b %Y %H:%M:%S +0000')"
cat > "$ROOT/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>bulletproof</title>
        <item>
            <title>Version $VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$BUILD</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
            <enclosure
                url="$DOWNLOAD_URL"
                $SIG_ATTRS
                type="application/octet-stream"/>
        </item>
    </channel>
</rss>
EOF

echo "==> Done"
echo "    artifact: $DMG"
echo "    appcast:  $ROOT/appcast.xml"
echo ""
echo "Next: gh release create v$VERSION \"$DMG\" --title \"bulletproof v$VERSION\" --notes-file <notes>"
echo "Then commit appcast.xml to main (the feed URL points at main)."
