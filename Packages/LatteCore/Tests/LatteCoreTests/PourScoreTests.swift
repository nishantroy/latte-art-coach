import Foundation
import Testing
@testable import LatteCore

@Suite struct PourScoreTests {
  static func measure(_ image: RGBAImage, pattern: Pattern = .tulip) throws -> PourMetrics {
    let lab = LabImage(image)
    let cup = try CupDetector.detect(lab)
    let surface = CupSurface(lab: lab, ellipse: cup.ellipse)
    let foam = FoamSegmenter.segment(surface)
    var axis = try #require(PatternAxis.find(surface: surface, mask: foam.mask))
    if pattern == .heart { axis = try #require(PourMeasurer.heartAxis(mask: foam.mask, size: surface.size)) }
    return PourMeasurer.measure(surface: surface, foam: foam, axis: axis)
  }

  @Test func tulipScoresAgreeWithTheClearCutRankings() throws {
    var scores: [Int: Int] = [:]
    print("pour score  offset sym  len  wid  contrast stacks thick fill taper rough | resembles | components")
    for number in Fixtures.pours {
      let m = try Self.measure(try RGBAImage.load(contentsOf: Fixtures.pourURL(number)))
      let score = PourScore(m, pattern: .tulip)
      scores[number] = score.overall
      let parts = PourScore.Component.allCases.map { "\($0.rawValue)=\(Int((score.components[$0]! * 100).rounded()))" }
      print(String(format: "%d    %3d    %.3f  %.2f %.2f %.2f %5.1f    %d      %.3f %.2f %.2f  %.3f | ",
                   number, score.overall, m.centerOffset, m.symmetry, m.length, m.width, m.contrast,
                   m.stackCount, m.stackThickness, m.fill, m.tipTaper, m.surfaceRoughness)
            + "\(Pattern.resembling(m)?.rawValue ?? "-") | " + parts.joined(separator: " "))
    }
    // The hand ranking is 3 > 4 > 5 > 2 ≈ 6 > 1; the clear-cut parts are asserted.
    #expect(scores[3]! == scores.values.max()!, "pour 3 should score highest")
    #expect(scores[1]! == scores.values.min()!, "pour 1 should score lowest")
    for better in [3, 5] { for worse in [2, 1] { #expect(scores[better]! > scores[worse]!) } }
  }

  /// Each synthetic pattern scores best when judged as itself, and is
  /// recognized as itself.
  @Test(arguments: Pattern.allCases)
  func syntheticPatternsScoreBestAsThemselves(_ pattern: Pattern) throws {
    let image = SyntheticPour.make(pattern)
    let cup = try CupDetector.detect(LabImage(image))
    DebugRender.write(image, ellipse: cup.ellipse, name: "synthetic-\(pattern.rawValue)")
    var scores: [Pattern: Int] = [:]
    for judged in Pattern.allCases {
      let m = try Self.measure(image, pattern: judged)
      scores[judged] = PourScore(m, pattern: judged).overall
      if judged == pattern {
        print("synthetic \(pattern): stacks=\(m.stackCount) thick=\(m.stackThickness) fill=\(m.fill) taper=\(m.tipTaper) len=\(m.length) wid=\(m.width)")
        #expect(Pattern.resembling(m) == pattern)
      }
    }
    print("synthetic \(pattern) scores: \(scores)")
    for other in Pattern.allCases where other != pattern { #expect(scores[pattern]! > scores[other]!) }
    #expect(scores[pattern]! >= 80)
  }

  @Test func heartStemIsAtThePoint() throws {
    // The synthetic heart's point is at the bottom of the image.
    let image = SyntheticPour.make(.heart)
    let result = try PourAnalysis.analyze(image: image, pattern: .heart)
    #expect(result.stem.y > result.tip.y)
  }

  @Test(arguments: Pattern.allCases)
  func perfectMetricsScore100(_ pattern: Pattern) {
    var ideal = PourMetrics(centerOffset: 0.02, symmetry: 0.95, detailSymmetry: 0.9, length: 0.7, width: 0.55,
                            coverage: 0.3, contrast: 40, edgeSharpness: 1, stackCount: 4, stackThickness: 0.3,
                            stemLength: 0.1, fill: 0.95, tipTaper: 0.3, lobeRoundness: 0.01, surfaceRoughness: 0.002)
    switch pattern {
    case .heart: ideal.stackCount = 1; ideal.length = 0.6; ideal.width = 0.6
    case .tulip: break
    case .rosetta: ideal.stackCount = 8; ideal.stackThickness = 0.08; ideal.length = 0.85
    }
    #expect(PourScore(ideal, pattern: pattern).overall == 100)
  }

  /// Smooth milk and crisp contrast can't carry a shapeless pour; once the
  /// shape is recognizable they count in full.
  @Test(arguments: Pattern.allCases)
  func greatMilkDoesNotLiftAPoorShape(_ pattern: Pattern) {
    let milkShare = PourScore.milkComponents.reduce(0) { $0 + $1.weight(for: pattern) }
    func score(shape: Double, milk: Double) -> Double {
      PourScore.combine(Dictionary(uniqueKeysWithValues: PourScore.Component.allCases.map {
        ($0, PourScore.milkComponents.contains($0) ? milk : shape)
      }), pattern: pattern)
    }
    // A blob: milk adds a third of its share, not all of it.
    #expect(abs(score(shape: 0.2, milk: 1) - ((1 - milkShare) * 0.2 + milkShare / 3)) < 1e-9)
    #expect(score(shape: 0, milk: 1) == 0)
    // A recognizable shape gets the plain weighted mean.
    #expect(abs(score(shape: 0.7, milk: 0.5) - ((1 - milkShare) * 0.7 + milkShare * 0.5)) < 1e-9)
  }

  @Test(arguments: Pattern.allCases)
  func weightsSumToOne(_ pattern: Pattern) {
    #expect(abs(PourScore.Component.allCases.reduce(0) { $0 + $1.weight(for: pattern) } - 1) < 1e-9)
  }
}

extension SyntheticPour {
  /// A crema disc on a light counter with an idealized pattern whose stem is
  /// at the bottom of the image and tip at the top.
  static func make(_ pattern: Pattern, size n: Int = 320) -> RGBAImage {
    var pixels = [UInt8](repeating: 0, count: n * n * 4)
    let c = Double(n) / 2, radius = Double(n) * 0.4
    for y in 0..<n {
      for x in 0..<n {
        // u right, v up, in cup radii.
        let u = (Double(x) + 0.5 - c) / radius, v = (c - Double(y) - 0.5) / radius
        var rgb: (UInt8, UInt8, UInt8) = (225, 222, 218)
        if hypot(u, v) < 1 {
          rgb = foam(pattern, u: u, v: v) ? (246, 242, 234) : (185, 118, 58)
        }
        let o = (y * n + x) * 4
        pixels[o] = rgb.0; pixels[o + 1] = rgb.1; pixels[o + 2] = rgb.2; pixels[o + 3] = 255
      }
    }
    return RGBAImage(width: n, height: n, pixels: pixels)
  }

  private static func foam(_ pattern: Pattern, u: Double, v: Double) -> Bool {
    switch pattern {
    case .heart:
      // (x² + y² − 1)³ − x²y³ ≤ 0: lobes up, point down at y = −1.
      let k = 0.55 / 1.14
      let x = u / k, y = (v + 0.06) / k
      let a = x * x + y * y - 1
      return a * a * a - x * x * y * y * y <= 0
    case .tulip:
      // Three stacks, largest at the top. The crema line between two stacks
      // is the lower arc of the upper one where the next one wraps it.
      let stacks: [(v: Double, r: Double)] = [(0.30, 0.34), (-0.12, 0.28), (-0.45, 0.20)]
      guard stacks.contains(where: { hypot(u, v - $0.v) < $0.r }) else { return false }
      for k in 0..<(stacks.count - 1) {
        let upper = stacks[k], lower = stacks[k + 1]
        if abs(hypot(u, v - upper.v) - upper.r) < 0.03, hypot(u, v - lower.v) < lower.r + 0.06, v < upper.v { return false }
      }
      return true
    case .rosetta:
      // Thin V-shaped leaves opening toward the tip, narrowing toward the
      // top, joined by the pull-through line.
      guard v > -0.82, v < 0.78 else { return false }
      let halfWidth = 0.40 - 0.15 * (v + 0.82) / 1.6
      if abs(u) < 0.012 { return true }
      guard abs(u) < halfWidth else { return false }
      let band = v - 0.6 * abs(u)
      return (band + 10).truncatingRemainder(dividingBy: 0.09) < 0.05
    }
  }
}

@Suite struct HeartShapeTests {
  static func lobes(_ inside: @escaping (Double, Double) -> Bool) throws -> Double {
    let n = 320
    var pixels = [UInt8](repeating: 0, count: n * n * 4)
    let c = Double(n) / 2, radius = Double(n) * 0.4
    for y in 0..<n {
      for x in 0..<n {
        let u = (Double(x) + 0.5 - c) / radius, v = (c - Double(y) - 0.5) / radius
        var rgb: (UInt8, UInt8, UInt8) = (225, 222, 218)
        if hypot(u, v) < 1 { rgb = inside(u, v) ? (246, 242, 234) : (185, 118, 58) }
        let o = (y * n + x) * 4
        pixels[o] = rgb.0; pixels[o + 1] = rgb.1; pixels[o + 2] = rgb.2; pixels[o + 3] = 255
      }
    }
    return try PourAnalysis.analyze(image: RGBAImage(width: n, height: n, pixels: pixels), pattern: .heart).metrics.lobeRoundness
  }

  @Test func roundLobesBeatAFlatToppedShield() throws {
    let twoCircles = try Self.lobes { u, v in
      if hypot(u - 0.14, v - 0.12) < 0.16 || hypot(u + 0.14, v - 0.12) < 0.16 { return true }
      return v < 0.12 && v > -0.38 && abs(u) < 0.29 * (v + 0.38) / 0.5
    }
    // Flat top, straight sides converging to a point, a slit for a notch.
    let shield = try Self.lobes { u, v in
      guard v < 0.3, v > -0.4 else { return false }
      if v > 0.22 && abs(u) < 0.04 { return false }
      return abs(u) < 0.3 * min(1, (v + 0.4) / 0.35)
    }
    #expect(twoCircles < 0.02, "two circles \(twoCircles)")
    #expect(shield > 0.07, "shield \(shield)")
  }
}
