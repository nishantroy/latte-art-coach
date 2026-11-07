import Foundation
import Testing
@testable import LatteCore

/// Latency budgets on the Mac. Debug builds are unoptimized, so the budget is
/// only enforced for release (`swift test -c release`), which scripts/test.sh uses.
@Suite struct PerformanceTests {
  @Test func analysisPipelineIsFast() throws {
    let url = Fixtures.pourURL(3)
    // The fastest of several runs: other tests run in parallel (text
    // recognition especially), and a busy neighbor inflates an average
    // without saying anything about this pipeline.
    let runs = 7
    var bestCup = Duration.seconds(10), best = Duration.seconds(10)
    for _ in 0..<runs {
      let start = ContinuousClock.now
      let lab = LabImage(try RGBAImage.load(contentsOf: url))
      let cup = try CupDetector.detect(lab)
      let afterCup = ContinuousClock.now
      let surface = CupSurface(lab: lab, ellipse: cup.ellipse)
      let foam = FoamSegmenter.segment(surface)
      let axis = try #require(PatternAxis.find(surface: surface, mask: foam.mask))
      _ = PourScore(PourMeasurer.measure(surface: surface, foam: foam, axis: axis), pattern: .tulip)
      let end = ContinuousClock.now
      bestCup = min(bestCup, afterCup - start)
      best = min(best, end - start)
    }
    print("decode + cup: \(bestCup), through score: \(best) (fastest of \(runs))")
    #if !DEBUG
    #expect(best < .milliseconds(100))
    #endif
  }
}
