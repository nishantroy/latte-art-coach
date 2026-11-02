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
