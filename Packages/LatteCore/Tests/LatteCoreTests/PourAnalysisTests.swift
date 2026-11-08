import Foundation
import Testing
@testable import LatteCore

@Suite struct PourAnalysisTests {
  @Test(arguments: Fixtures.pours)
  func analyzesFixturePhotosEndToEnd(_ number: Int) throws {
    let data = try Data(contentsOf: Fixtures.pourURL(number))
    let result = try PourAnalysis.analyze(imageData: data, pattern: .tulip)
    #expect(result.imageWidth == 512 || result.imageHeight == 512)
    #expect(!result.tips.isEmpty && result.tips.count <= 3)
    // The axis runs stem → tip, so the tip is "up" for pours 2–6.
    if number != 1 { #expect(result.tip.y < result.stem.y) }
    let tinted = stride(from: 3, to: result.foamOverlay.pixels.count, by: 4).filter { result.foamOverlay.pixels[$0] > 0 }.count
    #expect(tinted > 1000)
  }

  @Test func pour4IsToldToStopWiggling() throws {
    let result = try PourAnalysis.analyze(imageData: Data(contentsOf: Fixtures.pourURL(4)), pattern: .tulip)
    #expect(result.tips.contains { $0.component == .definition })
  }

  @Test func pour1IsToldAboutBubbles() throws {
    let result = try PourAnalysis.analyze(imageData: Data(contentsOf: Fixtures.pourURL(1)), pattern: .tulip)
    print(result.tips.map(\.title))
    #expect(result.tips.contains { $0.component == .texture || $0.component == .contrast || $0.component == .proportion })
  }

  @Test func rejectsNonImages() {
    #expect(throws: PourAnalysis.Failure.unreadableImage) { try PourAnalysis.analyze(imageData: Data("nope".utf8), pattern: .tulip) }
  }
}

@Suite struct NotLatteArtTests {
  /// A sunset over water, cropped from an app screenshot (with the app's old
  /// overlay baked in). The orange sky band used to be taken for a cup and scored.
  @Test func rejectsASunset() throws {
    let url = try #require(Bundle.module.url(forResource: "sunset", withExtension: "jpg", subdirectory: "Fixtures/not-latte"))
    #expect(throws: PourAnalysis.Failure.noCoffeeFound) { try PourAnalysis.analyze(imageData: Data(contentsOf: url), pattern: .tulip) }
  }

  @Test func rejectsALongOrangeBand() {
    // Gray sky over an orange horizon band with a lighter streak: crema-colored
    // with a "hole", but far too elongated to be a cup.
    let w = 300, h = 200
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    for y in 0..<h {
      for x in 0..<w {
        let i = (y * w + x) * 4
        let rgb: (UInt8, UInt8, UInt8) =
          (90..<120).contains(y) && (40..<260).contains(x)
            ? ((100..<106).contains(y) && (100..<200).contains(x) ? (235, 235, 230) : (230, 140, 60))
            : (120, 130, 140)
        pixels[i] = rgb.0; pixels[i + 1] = rgb.1; pixels[i + 2] = rgb.2; pixels[i + 3] = 255
      }
    }
    #expect(throws: CupDetector.Failure.noCoffeeFound) { try CupDetector.detect(LabImage(RGBAImage(width: w, height: h, pixels: pixels))) }
  }

  @Test func rejectsACupWithoutLighterFoam() throws {
    // A crema disc whose "pattern" is a slightly paler crema: Otsu splits it,
    // but nothing is white enough to be milk.
    let n = 200
    var pixels = [UInt8](repeating: 230, count: n * n * 4)
    for y in 0..<n {
      for x in 0..<n {
        let i = (y * n + x) * 4
        let r = hypot(Double(x - 100), Double(y - 100))
        guard r < 80 else { continue }
        let paler = abs(x - 100) < 20 && abs(y - 100) < 40
        let rgb: (UInt8, UInt8, UInt8) = paler ? (175, 120, 75) : (160, 100, 55)
        pixels[i] = rgb.0; pixels[i + 1] = rgb.1; pixels[i + 2] = rgb.2
      }
    }
    let image = RGBAImage(width: n, height: n, pixels: pixels)
    #expect(throws: PourAnalysis.Failure.noPatternFound) { try PourAnalysis.analyze(image: image, pattern: .tulip) }
  }
}

@Suite struct HeartPhotoTests {
  /// A clean, solid heart that sits toward the top of the cup, tilted a
  /// little, with a slightly bigger left lobe and big bubbles in the crema.
  static let url = Bundle.module.url(forResource: "heart-01", withExtension: "jpg", subdirectory: "Fixtures/hearts")!

  @Test func findsTheNotchToPointAxis() throws {
    let result = try PourAnalysis.analyze(imageData: Data(contentsOf: Self.url), pattern: .heart)
    // Point at the bottom, notch at the top, tilted about 10° (checked by eye).
    let angle = atan2(result.tip.y - result.stem.y, result.tip.x - result.stem.x) * 180 / .pi
    #expect(angleDifference(angle, -100) < 10, "axis \(angle)")
    #expect(result.resembles == .heart)
  }

  @Test func scoresBestAsAHeartAndIsToldToCenterItAndSmoothTheMilk() throws {
    let data = try Data(contentsOf: Self.url)
    let scores = try Pattern.allCases.map { try PourAnalysis.analyze(imageData: data, pattern: $0).score.overall }
    #expect(scores[0] > scores[1] && scores[0] > scores[2], "\(scores)")
    let heart = try PourAnalysis.analyze(imageData: data, pattern: .heart)
    #expect(heart.tips.map(\.component) == [.centering, .texture, .definition])
    #expect(heart.tips.last?.title == "Rounder lobes")
    #expect(heart.score.components[.contrast]! > 0.9)
    // The curves are poorly defined: the top is flat and the
    // sides straight. Lobe roundness should land well short of a clean heart.
    #expect((0.025...0.06).contains(heart.metrics.lobeRoundness), "lobes \(heart.metrics.lobeRoundness)")
    #expect(heart.score.components[.definition]! < 0.85)
  }
}

@Suite struct LoblessHeartTests {
  /// An off-center, lopsided blob with no lobes, poured as a heart, on
  /// smooth milk with crisp contrast. Rated 2/10; good milk and a
  /// tidy outline once lifted it to 55.
  @Test func scoresLow() throws {
    let url = try #require(Bundle.module.url(forResource: "heart-02-blob", withExtension: "jpg", subdirectory: "Fixtures/hearts"))
    let result = try PourAnalysis.analyze(imageData: Data(contentsOf: url), pattern: .heart)
    #expect(result.score.components[.definition]! < 0.1)
    #expect(result.score.components[.contrast]! > 0.8, "the milk itself was good")
    #expect((10...30).contains(result.score.overall), "overall \(result.score.overall)")
  }
}

@Suite struct SwirlTests {
  /// Two thick white masses swirled off to one side, poured as a tulip.
  /// Rated 1/10; the two blobs once counted as perfect tulip stacks.
  @Test func isNotATulip() throws {
    let url = try #require(Bundle.module.url(forResource: "swirl", withExtension: "jpg", subdirectory: "Fixtures/misses"))
    let result = try PourAnalysis.analyze(imageData: Data(contentsOf: url), pattern: .tulip)
    #expect(result.score.components[.definition]! < 0.2)
    print("swirl as tulip: \(result.score.overall)")
    #expect(result.score.overall <= 20, "overall \(result.score.overall)")
  }
}

