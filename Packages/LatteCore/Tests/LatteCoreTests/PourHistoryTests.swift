import Foundation
import Testing
@testable import LatteCore

@Suite struct PourHistoryTests {
  static func record(day: Int, pattern: Pattern = .heart, score: Int, centering: Double, rating: Int? = nil) -> PourRecord {
    var components = Dictionary(uniqueKeysWithValues: PourScore.Component.allCases.map { ($0, 0.8) })
    components[.centering] = centering
    return PourRecord(date: Date(timeIntervalSince1970: Double(day) * 86_400), pattern: pattern, score: score,
                      components: components, rating: rating)
  }

  @Test func comparesRecentPoursWithEarlierOnes() throws {
    // Centering improves from 0.2 to 0.7; scores from 50 to 70. Tulips are ignored.
    var records = (0..<5).map { Self.record(day: $0, score: 50, centering: 0.2) }
    records += (5..<10).map { Self.record(day: $0, score: 70, centering: 0.7) }
    records.append(Self.record(day: 11, pattern: .tulip, score: 10, centering: 0))
    let summary = try #require(ProgressSummary(records: records.shuffled(), pattern: .heart))
    #expect(summary.pourCount == 10 && summary.recentCount == 5)
    #expect(summary.recentAverageScore == 70 && summary.earlierAverageScore == 50)
    let centering = try #require(summary.trends.first { $0.component == .centering })
    #expect(abs(centering.change! - 0.5) < 1e-9)
    #expect(summary.trends.first?.component == .centering, "weakest component first")
  }

  @Test func handlesAFirstPour() throws {
    let summary = try #require(ProgressSummary(records: [Self.record(day: 0, score: 61, centering: 0)], pattern: .heart))
    #expect(summary.earlierAverageScore == nil && summary.trends.allSatisfy { $0.earlier == nil })
    #expect(ProgressSummary(records: [], pattern: .heart) == nil)
  }

  @Test func flagsScoresThatDisagreeWithTheUsersRating() throws {
    let records = [
      Self.record(day: 0, score: 61, centering: 0, rating: 3),  // 6.1 vs 3: disagrees
      Self.record(day: 1, score: 80, centering: 0, rating: 7),  // 8.0 vs 7: agrees
      Self.record(day: 2, score: 50, centering: 0),
    ]
    let summary = try #require(ProgressSummary(records: records, pattern: .heart))
    #expect(summary.ratedCount == 2)
    #expect(summary.disagreements.map(\.score) == [61])
  }

  @Test func exportRoundTrips() throws {
    let record = Self.record(day: 3, score: 56, centering: 0, rating: 4)
    let data = try HistoryExport(exportedAt: Date(timeIntervalSince1970: 0), pours: [("pour-1.jpg", record, PourAnalysis.version)]).encoded()
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let back = try decoder.decode(HistoryExport.self, from: data)
    #expect(back.pours.first?.rating == 4 && back.pours.first?.pattern == .heart && back.pours.first?.photo == "pour-1.jpg")
    #expect(back.pours.first?.components["centering"] == 0)
    #expect(String(decoding: data, as: UTF8.self).contains("\"rating\" : 4"))
  }
}
