# Latte Art Coach

## Native iOS app (in progress)

The app is being rebuilt from scratch in Swift. See [PLAN.md](./PLAN.md). It needs Xcode 26 or later and XcodeGen (`brew install xcodegen`).

```bash
scripts/test.sh                 # LatteCore unit tests, then UI tests on the iPhone 17 simulator
SKIP_UI=1 scripts/test.sh       # LatteCore unit tests only
xcodegen generate && open LatteArtCoach.xcodeproj
```

- `LatteArtCoach/` is the SwiftUI app. Its Xcode project is generated from `project.yml`.
- `Packages/LatteCore/` is the analysis package and has no UI dependencies.
- `LatteArtCoachUITests/` holds the Simulator UI tests.

The Expo web MVP described below is kept as a reference until it's removed in step 7 of the plan.

A local-only Expo Router web app that reviews heart-shaped latte art from an uploaded photo. Images are analyzed in browser memory and are discarded on refresh.

## Run locally

```bash
pnpm install
pnpm web
```

Then open the local URL printed by Expo. Use the system picker to choose a JPEG, PNG, or WebP photo.

## Verify

```bash
pnpm test
pnpm typecheck
pnpm build:web
```

The pure TypeScript analysis engine lives in `src/analysis-core`. It performs Lab color conversion, deterministic two-cluster foam segmentation, mask cleanup, geometric measurement, scoring, and rules-based coaching without a backend or model call.

See [PLAN.md](./PLAN.md) for the canonical product and implementation plan.
