import Foundation
import Testing
@testable import LatteCore

/// Latency budgets on the Mac. Debug builds are unoptimized, so the budget is
/// only enforced for release (`swift test -c release`), which scripts/test.sh uses.
@Suite struct PerformanceTests {
  @Test func analysisPipelineIsFast() throws {
    let url = Fixtures.pourURL(3)
    let runs = 5
    var cupTime = Duration.zero, total = Duration.zero
    for _ in 0..<runs {
      let start = ContinuousClock.now
      let lab = LabImage(try RGBAImage.load(contentsOf: url))
      let cup = try CupDetector.detect(lab)
      let afterCup = ContinuousClock.now
      let surface = CupSurface(lab: lab, ellipse: cup.ellipse)
      let foam = FoamSegmenter.segment(surface)
      _ = PatternAxis.find(surface: surface, mask: foam.mask)
      let end = ContinuousClock.now
      cupTime += afterCup - start
      total += end - start
    }
    print("decode + cup: \(cupTime / runs), through axis: \(total / runs)")
    #if !DEBUG
    #expect(total / runs < .milliseconds(100))
    #endif
  }
}
