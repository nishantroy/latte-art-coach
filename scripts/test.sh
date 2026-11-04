#!/usr/bin/env bash
# Runs every check: LatteCore unit tests, then the app's UI tests in a simulator.
#   scripts/test.sh                       # iPhone 17 simulator
#   SIM_NAME="iPhone Air" scripts/test.sh
#   SKIP_UI=1 scripts/test.sh             # package tests only
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

# Worktrees keep build output outside the checkout (see /Users/nishantroy/code/AGENTS.md).
if [ -f .git ]; then
  CACHE="/Users/nishantroy/code/.build-cache/latte-art-coach/$(basename "$ROOT")"
else
  CACHE="$ROOT/build"
fi
mkdir -p "$CACHE"

echo "== LatteCore unit tests"
swift test -c release --package-path Packages/LatteCore --scratch-path "$CACHE/spm-LatteCore"

[ "${SKIP_UI:-}" = 1 ] && exit 0

echo "== Generate Xcode project"
xcodegen generate --quiet

SIM_NAME="${SIM_NAME:-iPhone 17}"
OUT="$CACHE/test-output"
mkdir -p "$OUT"
LOG="$OUT/xcodebuild.log"
UDID="$(xcrun simctl list devices available | grep -F "    $SIM_NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
[ -n "$UDID" ] || { echo "Simulator '$SIM_NAME' not found"; exit 1; }
# Boot up front: letting xcodebuild cold-boot the simulator can fail to launch the runner.
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
# The flow test picks the newest library photo; make that fixture pour 3.
xcrun simctl addmedia "$UDID" Packages/LatteCore/Tests/LatteCoreTests/Fixtures/pours/pour-03.jpg
echo "== UI tests on $SIM_NAME"
set +e
xcodebuild test \
  -project LatteArtCoach.xcodeproj \
  -scheme LatteArtCoach \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$CACHE/DerivedData" \
  -resultBundlePath "$OUT/result-$(date +%Y%m%d-%H%M%S).xcresult" > "$LOG" 2>&1
STATUS=$?
set -e
grep -E "Test Case|error:|ANALYSIS|\*\* TEST" "$LOG" || tail -20 "$LOG"
R="$(ls -td "$OUT"/result-*.xcresult | head -1)"
rm -rf "$OUT/screenshots" && xcrun xcresulttool export attachments --path "$R" --output-path "$OUT/screenshots" >/dev/null 2>&1 || true
echo "Full log: $LOG"
echo "Screenshots: $OUT/screenshots"
exit $STATUS
