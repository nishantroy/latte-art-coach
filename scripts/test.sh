#!/usr/bin/env bash
# Runs the LatteCore unit tests, and the app's UI tests only when asked.
# The Simulator uses a lot of memory, so it never starts unless UI=1 is set.
#   scripts/test.sh                       # unit tests only (no Simulator)
#   UI=1 scripts/test.sh                  # also UI tests on the iPhone 17 simulator
#   UI=1 SIM_NAME="iPhone Air" scripts/test.sh
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
SPM=(-c release --package-path Packages/LatteCore --scratch-path "$CACHE/spm-LatteCore")
swift test "${SPM[@]}" --skip PerformanceTests
# The timing test runs alone: tests run in parallel, and sharing the CPU
# (with text recognition especially) makes timings meaningless.
echo "== LatteCore timing"
swift test "${SPM[@]}" --filter PerformanceTests

if [ "${UI:-}" != 1 ]; then
  echo "== Skipping UI tests (set UI=1 to run them in the Simulator)"
  exit 0
fi

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
# Free the Simulator's memory as soon as the tests are done.
xcrun simctl shutdown "$UDID" 2>/dev/null || true
grep -E "Test Case|error:|ANALYSIS|\*\* TEST" "$LOG" || tail -20 "$LOG"
R="$(ls -td "$OUT"/result-*.xcresult | head -1)"
rm -rf "$OUT/screenshots" && xcrun xcresulttool export attachments --path "$R" --output-path "$OUT/screenshots" >/dev/null 2>&1 || true
echo "Full log: $LOG"
echo "Screenshots: $OUT/screenshots"
exit $STATUS
