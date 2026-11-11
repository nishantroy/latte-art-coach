#!/usr/bin/env bash
# Archives a Release build and uploads it to App Store Connect for TestFlight.
#   scripts/testflight.sh            # archive and upload
#   ARCHIVE_ONLY=1 scripts/testflight.sh
# The build number is the commit count, so each upload from a newer commit is
# higher than the last. Uses the Apple ID signed in to Xcode (Settings →
# Accounts); the app must already exist in App Store Connect.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
if [ -f .git ]; then
  CACHE="/Users/nishantroy/code/.build-cache/latte-art-coach/$(basename "$ROOT")"
else
  CACHE="$ROOT/build"
fi
BUILD=$(git rev-list --count HEAD)
ARCHIVE="$CACHE/archives/LatteArtCoach-$BUILD.xcarchive"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "Commit your changes first: build $BUILD would not match its commit." >&2
  exit 1
fi

xcodegen generate --quiet
echo "== Archiving build $BUILD"
xcodebuild archive -project LatteArtCoach.xcodeproj -scheme LatteArtCoach -configuration Release \
  -destination generic/platform=iOS -archivePath "$ARCHIVE" -derivedDataPath "$CACHE/DerivedData" \
  -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD" -quiet
[ -n "${ARCHIVE_ONLY:-}" ] && { echo "Archived to $ARCHIVE"; exit 0; }

echo "== Uploading build $BUILD"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath "$CACHE/export-$BUILD" -allowProvisioningUpdates
echo "Uploaded build $BUILD. It shows in App Store Connect → TestFlight after processing (about 10–30 min)."
