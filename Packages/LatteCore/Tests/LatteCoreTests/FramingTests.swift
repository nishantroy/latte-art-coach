import Foundation
import Testing
@testable import LatteCore

@Suite struct FramingTests {
  /// The six real pours were all shot well enough to score.
  @Test(arguments: Fixtures.pours)
  func realPoursAreReady(_ number: Int) throws {
    let image = try RGBAImage.load(contentsOf: Fixtures.pourURL(number), maxDimension: 512)
    let check = Framing.check(image, pattern: .tulip)
    #expect(check.framing == .ready)
    #expect(check.foamOverlay != nil)
  }

  @Test func sunsetHasNoCup() throws {
    let url = try #require(Bundle.module.url(forResource: "sunset", withExtension: "jpg", subdirectory: "Fixtures/not-latte"))
    let check = Framing.check(try RGBAImage.load(contentsOf: url), pattern: .tulip)
    #expect(check.framing == .noCup && check.cup == nil)
  }

  /// Pour 3 shrunk into the corner of a pale countertop.
  @Test func smallCupMeansMoveCloser() throws {
    let pour = try RGBAImage.load(contentsOf: Fixtures.pourURL(3), maxDimension: 220)
    let w = 400, h = 520
    var pixels = [UInt8](repeating: 228, count: w * h * 4)
    for i in stride(from: 3, to: pixels.count, by: 4) { pixels[i] = 255 }
    for y in 0..<pour.height {
      for x in 0..<pour.width {
        let s = (y * pour.width + x) * 4, d = ((y + 140) * w + x + 90) * 4
        for c in 0..<4 { pixels[d + c] = pour.pixels[s + c] }
      }
    }
    let check = Framing.check(RGBAImage(width: w, height: h, pixels: pixels), pattern: .tulip)
    #expect(check.framing == .moveCloser)
  }

  @Test func geometry() {
    func framing(x: Double = 200, y: Double = 260, a: Double = 140, b: Double = 130) -> Framing {
      Framing.framing(cup: Ellipse(centerX: x, centerY: y, semiMajor: a, semiMinor: b, angle: 0), width: 400, height: 520)
    }
    #expect(framing() == .ready)
    #expect(framing(a: 80, b: 78) == .moveCloser)
    #expect(framing(x: 290) == .centerCup)
    #expect(framing(b: 100) == .holdFlatter)
  }
}

@Suite struct ManualCupTests {
  @Test func placedCupMatchesTheDetectedOne() throws {
    let data = try Data(contentsOf: Fixtures.pourURL(3))
    let auto = try PourAnalysis.analyze(imageData: data, pattern: .tulip)
    let placed = try PourAnalysis.analyze(imageData: data, pattern: .tulip, cup: auto.cup)
    #expect(placed.score == auto.score)
  }

  @Test func aMisplacedCupChangesTheScore() throws {
    let data = try Data(contentsOf: Fixtures.pourURL(3))
    let auto = try PourAnalysis.analyze(imageData: data, pattern: .tulip)
    var off = auto.cup
    off.centerX += off.semiMajor * 0.3
    let placed = try PourAnalysis.analyze(imageData: data, pattern: .tulip, cup: off)
    #expect(placed.cup == off)
    #expect(placed.score.components[.centering] != auto.score.components[.centering])
  }

  @Test func ellipseRoundTripsThroughJSON() throws {
    let e = Ellipse(centerX: 1, centerY: 2, semiMajor: 3, semiMinor: 2.5, angle: 0.4)
    #expect(try JSONDecoder().decode(Ellipse.self, from: JSONEncoder().encode(e)) == e)
  }
}
