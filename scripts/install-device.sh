#!/usr/bin/env bash
# Builds an optimized (Release) app, installs it on a connected iPhone and launches it.
#   scripts/install-device.sh                 # first paired, available iPhone
#   DEVICE=<CoreDevice identifier> scripts/install-device.sh
# Signing uses the development team in project.yml. Unlock the phone to launch.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
if [ -f .git ]; then
  CACHE="/Users/nishantroy/code/.build-cache/latte-art-coach/$(basename "$ROOT")"
else
  CACHE="$ROOT/build"
fi
mkdir -p "$CACHE"

JSON="$CACHE/devices.json"
xcrun devicectl list devices --json-output "$JSON" >/dev/null
read -r DEVICE_ID UDID NAME < <(python3 - "$JSON" "${DEVICE:-}" <<'PY'
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
want = sys.argv[2]
for d in devices:
    hw, props = d.get("hardwareProperties", {}), d.get("deviceProperties", {})
    if hw.get("platform") != "iOS" or d.get("connectionProperties", {}).get("pairingState") != "paired":
        continue
    if want and want not in (d["identifier"], hw.get("udid")):
        continue
    print(d["identifier"], hw.get("udid"), props.get("name", "iPhone").replace(" ", "_"))
    break
PY
)
[ -n "${DEVICE_ID:-}" ] || { echo "No paired iPhone found. Connect it and trust this Mac."; exit 1; }
echo "== Building for $NAME"

xcodegen generate --quiet
LOG="$CACHE/device-build.log"
if ! xcodebuild -project LatteArtCoach.xcodeproj -scheme LatteArtCoach -configuration Release \
  -destination "id=$UDID" -derivedDataPath "$CACHE/DerivedData-device" \
  -allowProvisioningUpdates build > "$LOG" 2>&1; then
  grep -E "error:" "$LOG" | head -20
  echo "Build failed; full log: $LOG"
  exit 1
fi
APP="$CACHE/DerivedData-device/Build/Products/Release-iphoneos/LatteArtCoach.app"

echo "== Installing"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP" >/dev/null
echo "== Launching (unlock the phone if this fails)"
xcrun devicectl device process launch --device "$DEVICE_ID" com.nishantroy.latteartcoach >/dev/null \
  && echo "Launched on $NAME." \
  || echo "Installed. Unlock the phone and open Latte Coach."
