#!/bin/bash
# Builds 7 Term in Release and installs it in /Applications.
# Run from anywhere:   tools/install.sh
# Xcode needs to be installed, but doesn't have to be open.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="7 Term"
DEST="/Applications/$APP_NAME.app"
BUILD="build/DerivedData"

if command -v xcodegen >/dev/null; then
    echo "› Generating the Xcode project"
    xcodegen generate --quiet
fi

# Use the pinned package versions (Package.resolved in the repo root).
RESOLVED="SevenTerm.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "$RESOLVED"
cp Package.resolved "$RESOLVED/Package.resolved"

# Without your team ID the app is signed ad hoc (for this Mac only), and an
# ad hoc app with the hardened runtime can't load Sparkle.framework. The
# hardened runtime only matters for notarized releases, so leave it out then.
EXTRA=()
TEAM_ID="$(sed -n 's/^ *DEVELOPMENT_TEAM: *"\{0,1\}\([A-Z0-9]*\)"\{0,1\}.*/\1/p' project.yml | head -1)"
if [ -z "$TEAM_ID" ]; then
    echo "› No DEVELOPMENT_TEAM in project.yml: building for this Mac only"
    EXTRA+=(ENABLE_HARDENED_RUNTIME=NO)
fi

echo "› Building (Release). The first build takes a minute or two."
xcodebuild \
    -project SevenTerm.xcodeproj \
    -scheme SevenTerm \
    -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath "$BUILD" \
    -quiet \
    build ${EXTRA[@]+"${EXTRA[@]}"}

BUILT="$BUILD/Build/Products/Release/$APP_NAME.app"
[ -d "$BUILT" ] || { echo "Build finished but $BUILT is missing." >&2; exit 1; }

if pgrep -xq "$APP_NAME"; then
    echo "› Quitting the running 7 Term"
    osascript -e "quit app \"$APP_NAME\"" || true
    for _ in {1..20}; do pgrep -xq "$APP_NAME" || break; sleep 0.25; done
fi

echo "› Installing to $DEST"
rm -rf "$DEST"
ditto "$BUILT" "$DEST"

echo "› Done. Opening 7 Term."
open "$DEST"
