import Foundation
import Testing
@testable import LatteCore

/// Latency budgets on the Mac. Debug builds are unoptimized, so the budget is
/// only enforced for release (`swift test -c release`), which scripts/test.sh uses.
@Suite struct PerformanceTests {
  @Test func cupDetectionIsFast() throws {
    let url = Fixtures.pourURL(3)
    let start = ContinuousClock.now
    let runs = 5
    for _ in 0..<runs {
      let image = try RGBAImage.load(contentsOf: url)
      _ = try CupDetector.detect(LabImage(image))
    }
    let perRun = (ContinuousClock.now - start) / runs
    print("decode + Lab + cup detection: \(perRun)")
    #if !DEBUG
    #expect(perRun < .milliseconds(60))
    #endif
  }
}
