import Foundation
import Testing
@testable import LatteCore

@Suite struct CoachingBriefTests {
  static func heart() throws -> PourAnalysis {
    try PourAnalysis.analyze(imageData: Data(contentsOf: HeartPhotoTests.url), pattern: .heart)
  }

  @Test func listsTheCostliestPartsFirstAndTheFindings() throws {
    let a = try Self.heart()
    let prompt = CoachingBrief.prompt(pattern: .heart, score: a.score, tips: a.tips, history: nil, rating: 4)
    print(prompt)
    #expect(prompt.contains("Score: \(a.score.overall) out of 100."))
    #expect(prompt.contains("rated this pour 4 out of 10"))
    // Centering (0, 20% of the score) costs the most points on this heart.
    let parts = prompt.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect(parts.first == "- centering: 0 (20% of the score)")
    for tip in a.tips { #expect(prompt.contains(tip.detail)) }
    #expect(prompt.contains("first heart in the app"))
  }

  @Test func describesHistory() throws {
    let a = try Self.heart()
    var records = (0..<5).map { PourHistoryTests.record(day: $0, score: 40, centering: 0.1) }
    records += (5..<10).map { PourHistoryTests.record(day: $0, score: 55, centering: 0.3) }
    let history = ProgressSummary(records: records, pattern: .heart)
    let prompt = CoachingBrief.prompt(pattern: .heart, score: a.score, tips: a.tips, history: history, rating: nil)
    #expect(prompt.contains("poured 10 hearts before this one"))
    #expect(prompt.contains("last 5 averaged 55, compared with 40 before that"))
    #expect(prompt.contains("Weakest areas lately: centering (averaging 30)"))
    #expect(prompt.contains("Improving: centering."))
    #expect(!prompt.contains("rated this pour"))
  }
}
