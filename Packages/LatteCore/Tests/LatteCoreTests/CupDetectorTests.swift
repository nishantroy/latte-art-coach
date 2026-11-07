import Foundation
import Testing
@testable import LatteCore

@Suite struct CupDetectorTests {
  /// Cup surfaces at 512 px, checked by eye against debug overlays
  /// (run with LATTE_DEBUG_DIR=/some/dir to regenerate them).
  static let expected: [Int: (x: Double, y: Double, major: Double, minor: Double)] = [
    1: (282, 187, 122, 119),
    2: (183, 213, 127, 121),
    3: (208, 226, 139, 129),
    4: (187, 255, 143, 133),
    5: (207, 226, 140, 129),
    6: (213, 238, 127, 120),
  ]

  @Test(arguments: Fixtures.pours)
  func findsTheCupInRealPhotos(_ number: Int) throws {
    let image = try RGBAImage.load(contentsOf: Fixtures.pourURL(number))
    let result = try CupDetector.detect(LabImage(image))
    DebugRender.write(image, ellipse: result.ellipse, tint: result.surface, name: "cup-\(number)")
    let e = result.ellipse, want = try #require(Self.expected[number])
    #expect(abs(e.centerX - want.x) < 6 && abs(e.centerY - want.y) < 6, "center (\(e.centerX), \(e.centerY))")
    #expect(abs(e.semiMajor - want.major) < 6 && abs(e.semiMinor - want.minor) < 6, "axes \(e.semiMajor)/\(e.semiMinor)")
  }

  /// A tan stoneware mug: its rim and handle pass as crema and join the
  /// coffee. The fit must follow the round rim, not stretch over the handle.
  /// (A crop of an in-app screenshot, so the old overlay is still drawn on it.)
  @Test func ignoresAStonewareHandle() throws {
    let url = try #require(Bundle.module.url(forResource: "stoneware-handle", withExtension: "jpg", subdirectory: "Fixtures/cups"))
    let image = try RGBAImage.load(contentsOf: url)
    let result = try CupDetector.detect(LabImage(image))
    DebugRender.write(image, ellipse: result.ellipse, tint: result.surface, name: "cup-stoneware-handle")
    let e = result.ellipse
    #expect(abs(e.centerX - 207) < 6 && abs(e.centerY - 247) < 6, "center (\(e.centerX), \(e.centerY))")
    #expect(abs(e.semiMajor - 150) < 6 && abs(e.semiMinor - 144) < 6, "axes \(e.semiMajor)/\(e.semiMinor)")
  }

  @Test func outlineFitIgnoresAnAttachedBlob() throws {
    // A disc of radius 40 with a 30×30 square stuck to its right side.
    let w = 160, h = 120
    var mask = [UInt8](repeating: 0, count: w * h)
    for y in 0..<h {
      for x in 0..<w {
        let inDisc = hypot(Double(x) + 0.5 - 60, Double(y) + 0.5 - 60) < 40
        let inBlob = x >= 95 && x < 125 && y >= 45 && y < 75
        if inDisc || inBlob { mask[y * w + x] = 1 }
      }
    }
    let e = try #require(CupDetector.fitOutline(mask, width: w, height: h))
    #expect(abs(e.centerX - 60) < 1.5 && abs(e.centerY - 60) < 1.5, "center (\(e.centerX), \(e.centerY))")
    #expect(abs(e.semiMajor - 40) < 1.5 && abs(e.semiMinor - 40) < 1.5, "axes \(e.semiMajor)/\(e.semiMinor)")
  }

  @Test func rejectsAPhotoWithNoCoffee() {
    let gray = RGBAImage(width: 64, height: 64, pixels: Array(repeating: [200, 200, 200, 255], count: 64 * 64).flatMap { $0 })
    #expect(throws: CupDetector.Failure.noCoffeeFound) { try CupDetector.detect(LabImage(gray)) }
  }

  @Test func ignoresABrownRegionWithoutAPattern() throws {
    // A plain crema-colored disc with no foam next to a smaller cup with foam.
    let w = 200, h = 100
    var pixels = [UInt8](repeating: 230, count: w * h * 4)
    for y in 0..<h {
      for x in 0..<w {
        let i = (y * w + x) * 4
        let inPlain = hypot(Double(x - 50), Double(y - 50)) < 45
        let inCup = hypot(Double(x - 150), Double(y - 50)) < 35
        let inFoam = hypot(Double(x - 150), Double(y - 50)) < 12
        if inFoam { pixels[i] = 245; pixels[i + 1] = 242; pixels[i + 2] = 235 }
        else if inPlain || inCup { pixels[i] = 190; pixels[i + 1] = 120; pixels[i + 2] = 60 }
      }
    }
    let result = try CupDetector.detect(LabImage(RGBAImage(width: w, height: h, pixels: pixels)))
    #expect(abs(result.ellipse.centerX - 150) < 2)
  }
}
