import Foundation
import Testing
@testable import LatteCore

@Suite struct FoamTests {
  /// Stem → tip direction in degrees (image y points down, so -90° is "up"),
  /// checked by eye against debug overlays. Pour 1 was poured sideways.
  static let expectedAxis: [Int: Double] = [1: 13, 2: -76, 3: -79, 4: -89, 5: -78, 6: -85]

  @Test(arguments: Fixtures.pours)
  func segmentsFoamAndFindsAxis(_ number: Int) throws {
    let image = try RGBAImage.load(contentsOf: Fixtures.pourURL(number))
    let lab = LabImage(image)
    let cup = try CupDetector.detect(lab)
    let surface = CupSurface(lab: lab, ellipse: cup.ellipse)
    let foam = FoamSegmenter.segment(surface)
    let axis = try #require(PatternAxis.find(surface: surface, mask: foam.mask))
    DebugRender.write(surface: surface, foam: foam.mask, axis: axis, name: "foam-\(number)")
    #expect((0.15...0.4).contains(foam.coverage), "coverage \(foam.coverage)")
    #expect(angleDifference(axis.angleDegrees, Self.expectedAxis[number]!) < 10, "axis \(axis.angleDegrees)°")
    #expect(axis.directionConfidence > 0.3)
  }

  /// Chevron stacks pointing at the stem, rotated to known angles.
  @Test(arguments: [-90.0, 0, 35, 140, -150])
  func findsTheAxisOfASyntheticPattern(_ tipAngle: Double) throws {
    let n = 320
    let image = SyntheticPour.chevrons(size: n, tipAngleDegrees: tipAngle)
    let lab = LabImage(image)
    let cup = try CupDetector.detect(lab)
    let surface = CupSurface(lab: lab, ellipse: cup.ellipse)
    let foam = FoamSegmenter.segment(surface)
    let axis = try #require(PatternAxis.find(surface: surface, mask: foam.mask))
    #expect(angleDifference(axis.angleDegrees, tipAngle) < 6, "axis \(axis.angleDegrees)°")
    #expect(axis.mirrorOverlap > 0.9)
  }

  @Test func otsuSplitsTwoClusters() {
    let values = Array(repeating: Float(10), count: 50) + Array(repeating: Float(60), count: 50)
    let t = FoamSegmenter.otsu(values)
    #expect(t > 10 && t < 60)
  }
}

func angleDifference(_ a: Double, _ b: Double) -> Double {
  let d = abs((a - b).truncatingRemainder(dividingBy: 360))
  return min(d, 360 - d)
}

enum SyntheticPour {
  /// A light counter, a crema disc, and foam chevrons (V shapes pointing at
  /// the stem) along an axis whose tip points at `tipAngleDegrees`.
  static func chevrons(size n: Int, tipAngleDegrees: Double) -> RGBAImage {
    var pixels = [UInt8](repeating: 0, count: n * n * 4)
    let theta = tipAngleDegrees * .pi / 180
    let dx = cos(theta), dy = sin(theta)
    let c = Double(n) / 2, radius = Double(n) * 0.4
    for y in 0..<n {
      for x in 0..<n {
        let rx = Double(x) + 0.5 - c, ry = Double(y) + 0.5 - c
        let t = rx * dx + ry * dy, s = -rx * dy + ry * dx
        let o = (y * n + x) * 4
        var rgb: (UInt8, UInt8, UInt8) = (225, 222, 218)
        if hypot(rx, ry) < radius {
          rgb = (185, 118, 58)
          let band = t - 0.6 * abs(s)
          if abs(s) < radius * 0.45, band > -radius * 0.55, band < radius * 0.45,
             (band + 200).truncatingRemainder(dividingBy: 24) < 15 {
            rgb = (246, 242, 234)
          }
        }
        pixels[o] = rgb.0; pixels[o + 1] = rgb.1; pixels[o + 2] = rgb.2; pixels[o + 3] = 255
      }
    }
    return RGBAImage(width: n, height: n, pixels: pixels)
  }
}
