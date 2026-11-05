#!/bin/bash
# Builds, signs, notarizes and publishes a 7 Term release.
#
#   tools/release.sh 1.0.0              everything, ending with a GitHub release
#   tools/release.sh 1.0.0 --no-publish everything except the GitHub release
#
# One-time setup (certificate, notarization login, Sparkle key, gh): see
# docs/releasing.md. Nothing secret is read from the repo: the signing
# identity, the notarization password and Sparkle's private key all stay in
# your Keychain.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
PUBLISH=1
[ "${2:-}" = "--no-publish" ] && PUBLISH=0
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Usage: tools/release.sh 1.2.3 [--no-publish]" >&2; exit 1; }

APP_NAME="7 Term"
REPO="networkitout/7term"
TAG="v$VERSION"
NOTARY_PROFILE="${NOTARY_PROFILE:-7term-notary}"
# Built outside the repo on purpose: if ~/Documents syncs with iCloud Drive,
# iCloud tags new files there with extended attributes, and codesign and
# notarization reject an app carrying them ("detritus not allowed").
# ~/Library/Caches never syncs.
RELEASE_ROOT="${RELEASE_DIR:-$HOME/Library/Caches/7term-release}"
OUT="$RELEASE_ROOT/$VERSION"
DERIVED="$RELEASE_ROOT/DerivedData"
TEAM_ID="$(sed -n 's/^ *DEVELOPMENT_TEAM: *"\{0,1\}\([A-Z0-9]*\)"\{0,1\}.*/\1/p' project.yml | head -1)"
SPARKLE_KEY="$(sed -n 's/^ *SPARKLE_PUBLIC_KEY: *"\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p' project.yml | head -1)"
# Each release needs a higher build number for Sparkle; the commit count works.
BUILD_NUMBER="$(git rev-list --count HEAD)"

step() { printf '\n› %s\n' "$*"; }
fail() { echo "✗ $*" >&2; exit 1; }

step "Checking"
[ -n "$TEAM_ID" ] || fail "Set DEVELOPMENT_TEAM in project.yml (docs/releasing.md, step 1)."
[ -n "$SPARKLE_KEY" ] || fail "Set SPARKLE_PUBLIC_KEY in project.yml (docs/releasing.md, step 3)."
[ -z "$(git status --porcelain)" ] || fail "Commit or stash your changes first; a release is built from a clean commit."
git rev-parse "$TAG" >/dev/null 2>&1 && fail "Tag $TAG already exists."
security find-identity -v -p codesigning | grep -q "Developer ID Application: .*($TEAM_ID)" \
    || fail "No 'Developer ID Application' certificate for team $TEAM_ID in your Keychain (docs/releasing.md, step 1)."
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || fail "No notarization login saved as '$NOTARY_PROFILE' (docs/releasing.md, step 2)."
if [ "$PUBLISH" = 1 ]; then
    command -v gh >/dev/null && gh auth status >/dev/null 2>&1 || fail "gh isn't installed or signed in (docs/releasing.md, step 4)."
fi
echo "  version $VERSION (build $BUILD_NUMBER), team $TEAM_ID"

rm -rf "$OUT" && mkdir -p "$OUT"

step "Generating the project with pinned package versions"
command -v xcodegen >/dev/null && xcodegen generate --quiet
mkdir -p SevenTerm.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
cp Package.resolved SevenTerm.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

step "Archiving (Release)"
xcodebuild archive \
    -project SevenTerm.xcodeproj -scheme SevenTerm -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED" \
    -archivePath "$OUT/7Term.xcarchive" \
    -disableAutomaticPackageResolution \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    -quiet

step "Signing with your Developer ID"
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$OUT/7Term.xcarchive" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT/export" -quiet
APP="$OUT/export/$APP_NAME.app"
# Drop any Finder or file-provider metadata before checking the signature.
xattr -cr "$APP"
codesign --verify --deep --strict "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Authority=Developer ID Application|TeamIdentifier" | sed 's/^/  /'

step "Notarizing the app (a few minutes)"
ditto -c -k --keepParent "$APP" "$OUT/app.zip"
xcrun notarytool submit "$OUT/app.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"

step "Making the disk image"
DMG_NAME="7Term-$VERSION.dmg"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -format UDZO -ov "$OUT/$DMG_NAME" -quiet
IDENTITY="$(security find-identity -v -p codesigning | sed -n "s/.*\"\(Developer ID Application: .*($TEAM_ID)\)\"/\1/p" | head -1)"
codesign --sign "$IDENTITY" --timestamp "$OUT/$DMG_NAME"

step "Notarizing the disk image"
xcrun notarytool submit "$OUT/$DMG_NAME" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$OUT/$DMG_NAME"
spctl --assess --type open --context context:primary-signature -v "$OUT/$DMG_NAME" 2>&1 | sed 's/^/  /'

step "Writing the update feed (appcast.xml)"
GENERATE_APPCAST="$(find "$DERIVED/SourcePackages/artifacts" -path '*Sparkle*/bin/generate_appcast' -type f | head -1)"
[ -x "$GENERATE_APPCAST" ] || fail "Couldn't find Sparkle's generate_appcast under $DERIVED/SourcePackages/artifacts."
# The feed lists only this release, and no delta updates: every link in it
# must point at a file this release uploads. Older DMGs and deltas would get
# this tag's download prefix too and 404 (and GitHub renames assets with
# spaces, such as "7 Term33-24.delta"). Sparkle only needs the newest item.
UPDATES="$RELEASE_ROOT/updates"
mkdir -p "$UPDATES"
cp "$OUT/$DMG_NAME" "$UPDATES/"
"$GENERATE_APPCAST" \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    --link "https://github.com/$REPO" \
    --maximum-versions 1 \
    --maximum-deltas 0 \
    -o "$OUT/appcast.xml" "$UPDATES"
# Fail before publishing if the feed links anything not being uploaded.
LINKED="$(grep -o "releases/download/$TAG/[^\"]*" "$OUT/appcast.xml" | sed "s|.*/||" | sort -u)"
[ "$LINKED" = "$DMG_NAME" ] || fail "appcast.xml links files other than $DMG_NAME: $LINKED"

SHA="$(shasum -a 256 "$OUT/$DMG_NAME" | cut -d' ' -f1)"
echo "  $DMG_NAME  sha256 $SHA"

if [ "$PUBLISH" = 0 ]; then
    step "Done (not published). Everything is in $OUT/"
    exit 0
fi

step "Publishing $TAG on GitHub"
git tag -a "$TAG" -m "7 Term $VERSION"
git push origin "$TAG"
gh release create "$TAG" "$OUT/$DMG_NAME" "$OUT/appcast.xml" \
    --repo "$REPO" --title "7 Term $VERSION" --generate-notes \
    --notes "SHA-256 of $DMG_NAME: \`$SHA\`"
step "Released: https://github.com/$REPO/releases/tag/$TAG"
