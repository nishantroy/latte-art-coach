# Latte Art Coach — Native iOS Plan

This file is the canonical plan. Scope or architecture changes must update it.

## Product

You say which pattern you poured (heart, tulip or rosetta), then take or pick a photo of it. Within about half a second the app shows a score, an overlay showing what's off, and a couple of specific things to change on the next pour. Everything runs on the device.

## Requirements

- **Speed:** analysis takes under 300 ms on an iPhone 15 Pro. The score and overlay appear right away, and coaching text streams in afterwards, so it never holds up the score. While you frame the photo, the foam overlay updates live. Timing tests enforce these budgets.
- **Deterministic score:** the score comes only from measured geometry. Language models write the coaching and observations but never produce or adjust the score.
- **Private:** photos and results stay on the device. There is no network call.
- **Platform:** a native Swift app (SwiftUI) with no React Native, web or cross-platform layer. The deployment target is iOS 26. Features that need iOS 27 are gated with `#available`. The test device is an iPhone 15 Pro running iOS 27, which supports Apple Intelligence.

## Architecture

- **`LatteArtCoach/`** is the SwiftUI app target. Its Xcode project is generated from `project.yml` by XcodeGen. The `.xcodeproj` isn't checked in.
- **`Packages/LatteCore/`** is a Swift package with no UI dependencies. It holds image preparation, cup detection, foam segmentation, measurements, scoring and the rule-based tips. `swift test` runs it on the Mac in seconds.
- **Patterns:** one shared measurement pass (`PourMetrics`) feeds a per-pattern score (`PourScore`) with its own weights, size ranges and a `definition` component: a solid heart that closes to a point, thick separate tulip stacks, or many thin rosetta leaves. The user picks the intended pattern and can re-score a photo as another one. A conservative classifier (`Pattern.resembling`) points out when the foam clearly reads as a different pattern.
- **Image math** runs on Accelerate (vDSP and vImage) and Core Image rather than per-pixel Swift loops where it matters.
- **Coaching:** Foundation Models (`LanguageModelSession` with `@Generable` output) turns the metrics into specific tips. When Apple Intelligence isn't available, rule-based tips from LatteCore are used instead.
- **Image observations (iOS 27, needs Xcode 27):** the model is also given the photo and adds qualitative notes, such as a smeared base. These are shown beside the score and never feed into it.

## Build order

| Step | Scope | Verified by | Status |
| --- | --- | --- | --- |
| 1 | Scaffold: XcodeGen project, LatteCore package, app shell, `scripts/test.sh` | `swift test`; UI test launches the app | Done |
| 2a | Cup detection: crema region scoring, ellipse fit for angled photos | Six real pours with eye-checked ellipses; timing test | Done |
| 2b | Foam segmentation inside the cup, glare rejection, pattern axis and direction | Fixture axes eye-checked; synthetic patterns at known angles; timing test | Done |
| 2c | Tulip metrics and score: centering, symmetry, contrast, proportion, texture, stack definition | Clear-cut parts of the hand ranking (3 > 4 > 5 > 2 ≈ 6 > 1) asserted | Done |
| 3 | App flow: take or pick a photo, automatic cup detection, results with overlay, score breakdown and rule-based tips | XCUITest in the Simulator; installed on the iPhone 15 Pro | Done, except manual cup adjustment |
| 4 | Foundation Models coaching from metrics, plus the rule-based fallback | Unit tests for the fallback; on-device check | |
| 5 | iOS 27 image observations | Xcode 27, on-device | |
| 6 | Camera capture inside the app | On-device | Basic system camera done in step 3 |
| 3b | Heart and rosetta scoring, pattern picker, re-score as another pattern | Synthetic heart/tulip/rosetta each score best as themselves; UI test re-scores as rosetta | Done; needs real heart and rosetta photos to calibrate |
| 7 | Remove the Expo web MVP from the repo | Clean tree; `scripts/test.sh` | Done |

## Later (tracked, not scheduled)

- Pour history and progress over time, such as symmetry improving this week.
- Real heart and rosetta fixture photos to calibrate their ranges (currently set from synthetic patterns and judgment), plus a heart-notch measurement.

## Heart analysis notes

- A heart is a round blob, so the plain mirror-overlap axis goes diagonal on real hearts (heart-01, 2026-11-05). Hearts take their axis from landmarks instead: the notch (the deepest dent in the outline) and the point (the part farthest from it), fine-tuned for mirror overlap. Hearts with no visible notch fall back to mirror overlap plus a wide-lobes, narrow-point profile.
- Thumbnails hide bubbles: heart-01 scored texture 76 as a 176×234 thumbnail and 3 at full size, which shows the bubbles. Fixtures should be full-size photos.
- Heart-01's curves are poorly defined (flat top, straight sides), but heart shape scored 100. Heart shape now includes lobe roundness, from a circle fit to each lobe's upper outline: clean drawn hearts ~0.01, heart-01 0.038, a flat-topped shield ~0.10. Heart shape weight went from 15% to 25%. A template match against the classic heart curve was tried first and rejected, because it ranked a shield above a clean two-circle heart. Notch depth was tried and dropped as unreliable.
- Up to three tips are shown, so the shape tip isn't crowded out by centering and milk texture.

## Tulip analysis notes

- The six fixture photos in `Packages/LatteCore/Tests/LatteCoreTests/Fixtures/pours/` were all meant as tulips. They came out with wing-shaped, blended stacks that look like rosettas. Telling those apart is a core coaching signal: distinct, rounded stacks mean clean pushes with the flow stopped between them, while thin, wavy layers mean the pitcher kept wiggling.
- Real photos are taken at an angle, so the cup surface is an ellipse. Measurements happen after mapping that ellipse to a circle.
- The handle and the pattern point in any direction, and pour 1 is rotated 90°. The pattern axis comes from the foam itself.
- White countertops look like foam, so all foam analysis is restricted to the detected cup surface.
- The axis is the line of best mirror symmetry. Its direction comes from the crema lines between stacks, which form chevrons pointing at the stem.
- The score is a weighted mean of fixed ramps on measured metrics (`TulipScore.swift`). On the fixtures it gives 3: 84, 5: 84, 6: 82, 2: 74, 4: 65, 1: 64. Decision (2026-11-04): this is a tulip coach, so pour 4's thin, rosetta-like layers are penalized via stack definition (20% weight), and its top tip is "Push, stop, push".
- Silhouette symmetry hardly separates these six pours. It's weighted but shouldn't be trusted to rank on its own until there are more examples.
- Non-latte photos (2026-11-05: a sunset was scored 46) are rejected by plausibility gates rather than scored: the cup candidate must be roundish (minor/major ≥ 0.5) and solid (≥ 0.85 of its ellipse), and the foam must be at least 10 L lighter than the crema. Negative fixtures live in `Fixtures/not-latte/`.
- The foam cleanup step (morphological opening) erases the thin pull-through stem. The stem metric in 2c has to measure it before cleanup or from the raw whiteness.

## Notes

- Debug builds of LatteCore are unoptimized, and analysis takes about 2.5 s in the Simulator. Use Release for real timing: `scripts/install-device.sh` builds Release, and the Mac release timing test covers about 35 ms.

- In a git worktree, `scripts/test.sh` puts all build output under `/Users/nishantroy/code/.build-cache/latte-art-coach/<worktree>/`, as the repository-wide `AGENTS.md` requires. In the main checkout it uses `build/`.
