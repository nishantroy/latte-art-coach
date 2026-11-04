import Foundation
import Testing
@testable import LatteCore

@Suite struct PourAnalysisTests {
  @Test(arguments: Fixtures.pours)
  func analyzesFixturePhotosEndToEnd(_ number: Int) throws {
    let data = try Data(contentsOf: Fixtures.pourURL(number))
    let result = try PourAnalysis.analyze(imageData: data)
    #expect(result.imageWidth == 512 || result.imageHeight == 512)
    #expect(!result.tips.isEmpty && result.tips.count <= 2)
    // The axis runs stem → tip, so the tip is "up" for pours 2–6.
    if number != 1 { #expect(result.tip.y < result.stem.y) }
    let tinted = stride(from: 3, to: result.foamOverlay.pixels.count, by: 4).filter { result.foamOverlay.pixels[$0] > 0 }.count
    #expect(tinted > 1000)
  }

  @Test func pour4IsToldToStopWiggling() throws {
    let result = try PourAnalysis.analyze(imageData: Data(contentsOf: Fixtures.pourURL(4)))
    #expect(result.tips.contains { $0.component == .stackDefinition })
  }

  @Test func pour1IsToldAboutBubbles() throws {
    let result = try PourAnalysis.analyze(imageData: Data(contentsOf: Fixtures.pourURL(1)))
    print(result.tips.map(\.title))
    #expect(result.tips.contains { $0.component == .texture || $0.component == .contrast || $0.component == .proportion })
  }

  @Test func rejectsNonImages() {
    #expect(throws: PourAnalysis.Failure.unreadableImage) { try PourAnalysis.analyze(imageData: Data("nope".utf8)) }
  }
}
