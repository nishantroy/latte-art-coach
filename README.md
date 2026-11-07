# Latte Art Coach

A native iOS app that scores your latte art and coaches your next pour. Pick the pattern you poured (heart, tulip or rosetta), take or choose a photo from above, and get a score out of 100, an overlay of what it measured, and tips. Everything runs on the device. See [PLAN.md](./PLAN.md) for the product plan and design notes.

It needs Xcode 26 or later and XcodeGen (`brew install xcodegen`).

```bash
scripts/test.sh                 # LatteCore unit tests (never starts the Simulator)
UI=1 scripts/test.sh            # also UI tests on the iPhone 17 simulator (memory-heavy)
scripts/install-device.sh       # optimized build, installed and launched on a connected iPhone
xcodegen generate && open LatteArtCoach.xcodeproj
```

Installing on a phone needs it paired with this Mac, with Developer Mode on. Signing uses the team in `project.yml`.

- `LatteArtCoach/` is the SwiftUI app. Its Xcode project is generated from `project.yml`.
- `Packages/LatteCore/` is the analysis package (cup detection, foam segmentation, measurement, scoring, rule-based tips, bag-label parsing, dial-in rules, taste preferences). It has no UI dependencies, and its tests run on the Mac with real and synthetic photos.
- `LatteArtCoachUITests/` holds the Simulator UI tests.
