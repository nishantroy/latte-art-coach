# Latte Art Coach — Native iOS Plan

This file is the canonical plan. Scope or architecture changes must update it.

## Product

You take or pick a photo of a tulip you poured. Within about half a second the app shows a score, an overlay showing what's off, and a couple of specific things to change on the next pour. Everything runs on the device.

## Requirements

- **Speed:** analysis takes under 300 ms on an iPhone 15 Pro. The score and overlay appear right away, and coaching text streams in afterwards, so it never holds up the score. While you frame the photo, the foam overlay updates live. Timing tests enforce these budgets.
- **Deterministic score:** the score comes only from measured geometry. Language models write the coaching and observations but never produce or adjust the score.
- **Private:** photos and results stay on the device. There is no network call.
- **Platform:** a native Swift app (SwiftUI) with no React Native, web or cross-platform layer. The deployment target is iOS 26. Features that need iOS 27 are gated with `#available`. The test device is an iPhone 15 Pro running iOS 27, which supports Apple Intelligence.

## Architecture

- **`LatteArtCoach/`** is the SwiftUI app target. Its Xcode project is generated from `project.yml` by XcodeGen. The `.xcodeproj` isn't checked in.
- **`Packages/LatteCore/`** is a Swift package with no UI dependencies. It holds image preparation, cup detection, foam segmentation, measurements, scoring and the rule-based tips. `swift test` runs it on the Mac in seconds.
- **Pattern analyzers:** each pattern implements a shared analyzer protocol. The tulip is the first one. Heart and rosetta can be added later without touching the tulip code.
- **Image math** runs on Accelerate (vDSP and vImage) and Core Image rather than per-pixel Swift loops where it matters.
- **Coaching:** Foundation Models (`LanguageModelSession` with `@Generable` output) turns the metrics into specific tips. When Apple Intelligence isn't available, rule-based tips from LatteCore are used instead.
- **Image observations (iOS 27, needs Xcode 27):** the model is also given the photo and adds qualitative notes, such as a smeared base. These are shown beside the score and never feed into it.

## Build order

| Step | Scope | Verified by | Status |
| --- | --- | --- | --- |
| 1 | Scaffold: XcodeGen project, LatteCore package, app shell, `scripts/test.sh` | `swift test`; UI test launches the app | Done |
| 2a | Cup detection: crema region scoring, ellipse fit for angled photos | Six real pours with eye-checked ellipses; timing test | Done |
| 2b | Foam segmentation inside the cup, glare rejection, pattern axis and direction | Fixture tests; debug overlays | |
| 2c | Tulip metrics and score: centering, symmetry, contrast, size, stack count and separation, stem | Score order matches the hand ranking of the fixtures | |
| 3 | App flow: pick a photo, frame it (auto cup detection with manual adjust), results with overlay | XCUITest in the Simulator | |
| 4 | Foundation Models coaching from metrics, plus the rule-based fallback | Unit tests for the fallback; on-device check | |
| 5 | iOS 27 image observations | Xcode 27, on-device | |
| 6 | Camera capture inside the app | On-device | |
| 7 | Remove the Expo web MVP from the repo | Clean tree; `scripts/test.sh` | |

## Later (tracked, not scheduled)

- Pour history and progress over time, such as symmetry improving this week.
- Heart and rosetta patterns.

## Tulip analysis notes

- The six fixture photos in `Packages/LatteCore/Tests/LatteCoreTests/Fixtures/pours/` were all meant as tulips. They came out with wing-shaped, blended stacks that look like rosettas. Telling those apart is a core coaching signal: distinct, rounded stacks mean clean pushes with the flow stopped between them, while thin, wavy layers mean the pitcher kept wiggling.
- Real photos are taken at an angle, so the cup surface is an ellipse. Measurements happen after mapping that ellipse to a circle.
- The handle and the pattern point in any direction, and pour 1 is rotated 90°. The pattern axis comes from the foam itself.
- White countertops look like foam, so all foam analysis is restricted to the detected cup surface.

## Notes

- The Expo web MVP (`app/`, `src/`, `package.json`) remains until step 7. It's a reference only. The Swift analysis is a fresh design, and the old scoring formula doesn't carry over.
- In a git worktree, `scripts/test.sh` puts all build output under `/Users/nishantroy/code/.build-cache/latte-art-coach/<worktree>/`, as the repository-wide `AGENTS.md` requires. In the main checkout it uses `build/`.
