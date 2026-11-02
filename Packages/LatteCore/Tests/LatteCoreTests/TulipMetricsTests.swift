import Foundation
import Testing
@testable import LatteCore

@Suite struct TulipMetricsTests {
  static func measure(_ number: Int) throws -> TulipMetrics {
    let lab = LabImage(try RGBAImage.load(contentsOf: Fixtures.pourURL(number)))
    let cup = try CupDetector.detect(lab)
    let surface = CupSurface(lab: lab, ellipse: cup.ellipse)
    let foam = FoamSegmenter.segment(surface)
    let axis = try #require(PatternAxis.find(surface: surface, mask: foam.mask))
    return TulipAnalyzer.measure(surface: surface, foam: foam, axis: axis)
  }

  @Test func scoresAgreeWithTheClearCutRankings() throws {
    var scores: [Int: Int] = [:]
    print("pour score  offset sym  len  wid  contrast stacks thick rough | components")
    for number in Fixtures.pours {
      let m = try Self.measure(number)
      let score = TulipScore(m)
      scores[number] = score.overall
      let parts = TulipScore.Component.allCases.map { "\($0.rawValue)=\(Int((score.components[$0]! * 100).rounded()))" }
      print(String(format: "%d    %3d    %.3f  %.2f %.2f %.2f %5.1f    %d      %.3f %.3f | ",
                   number, score.overall, m.centerOffset, m.symmetry, m.length, m.width, m.contrast,
                   m.stackCount, m.stackThickness, m.surfaceRoughness) + parts.joined(separator: " "))
    }
    // The hand ranking is 3 > 4 > 5 > 2 ≈ 6 > 1. Only the clear-cut parts
    // are asserted; pour 4 is pending a decision on how much to penalize
    // rosetta-like layering in a tulip.
    #expect(scores[3]! == scores.values.max()!, "pour 3 should score highest")
    #expect(scores[1]! == scores.values.min()!, "pour 1 should score lowest")
    for better in [3, 5] { for worse in [2, 1] { #expect(scores[better]! > scores[worse]!) } }
  }

  @Test func perfectMetricsScore100() {
    let ideal = TulipMetrics(centerOffset: 0.02, symmetry: 0.95, detailSymmetry: 0.9, length: 0.7, width: 0.55,
                             coverage: 0.3, contrast: 40, edgeSharpness: 1, stackCount: 4, stackThickness: 0.3,
                             stemLength: 0.1, surfaceRoughness: 0.002)
    #expect(TulipScore(ideal).overall == 100)
  }

  @Test func weightsSumToOne() {
    #expect(abs(TulipScore.Component.allCases.reduce(0) { $0 + $1.weight } - 1) < 1e-9)
  }
}
