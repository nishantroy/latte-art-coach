import Foundation

/// One scored pour as saved in history: what the app measured and what the
/// user thought of it.
public struct PourRecord: Sendable, Equatable, Codable {
  public var date: Date
  public var pattern: Pattern
  public var score: Int
  /// Each score component in 0...1.
  public var components: [PourScore.Component: Double]
  /// The user's own rating, 1–10, if they gave one.
  public var rating: Int?

  public init(date: Date, pattern: Pattern, score: Int, components: [PourScore.Component: Double], rating: Int?) {
    self.date = date
    self.pattern = pattern
    self.score = score
    self.components = components
    self.rating = rating
  }
}

/// How a pattern is going: recent pours compared with the ones before them.
public struct ProgressSummary: Sendable, Equatable {
  public struct Trend: Sendable, Equatable {
    public var component: PourScore.Component
    /// Mean component value (0...1) over the recent pours.
    public var recent: Double
    /// Mean over the earlier pours, if there are any.
    public var earlier: Double?
    public var change: Double? { earlier.map { recent - $0 } }
  }

  public var pattern: Pattern
  public var pourCount: Int
  public var recentCount: Int
  public var recentAverageScore: Double
  public var earlierAverageScore: Double?
  /// Component trends, weakest recent component first.
  public var trends: [Trend]
  /// Rated pours whose score and rating disagree by more than 2 points
  /// out of 10, as (score, rating).
  public var disagreements: [(score: Int, rating: Int)]
  public var ratedCount: Int

  public static func == (a: Self, b: Self) -> Bool {
    a.pattern == b.pattern && a.pourCount == b.pourCount && a.recentCount == b.recentCount
      && a.recentAverageScore == b.recentAverageScore && a.earlierAverageScore == b.earlierAverageScore
      && a.trends == b.trends && a.ratedCount == b.ratedCount
      && a.disagreements.map(\.score) == b.disagreements.map(\.score)
      && a.disagreements.map(\.rating) == b.disagreements.map(\.rating)
  }

  /// Compares the last `window` pours of `pattern` with the `window` before
  /// them. Returns nil when there are no pours of that pattern.
  public init?(records: [PourRecord], pattern: Pattern, window: Int = 5) {
    let pours = records.filter { $0.pattern == pattern }.sorted { $0.date < $1.date }
    guard !pours.isEmpty else { return nil }
    let recent = Array(pours.suffix(window))
    let earlier = Array(pours.dropLast(recent.count).suffix(window))
    func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
    self.pattern = pattern
    pourCount = pours.count
    recentCount = recent.count
    recentAverageScore = mean(recent.map { Double($0.score) })!
    earlierAverageScore = mean(earlier.map { Double($0.score) })
    trends = PourScore.Component.allCases.map { c in
      Trend(component: c,
            recent: mean(recent.compactMap { $0.components[c] }) ?? 0,
            earlier: mean(earlier.compactMap { $0.components[c] }))
    }
    .sorted { $0.recent < $1.recent }
    let rated = pours.compactMap { p in p.rating.map { (score: p.score, rating: $0) } }
    ratedCount = rated.count
    disagreements = rated.filter { abs(Double($0.score) / 10 - Double($0.rating)) > 2 }
  }
}

/// The export format: one JSON file describing every pour, alongside the
/// original photos, so pours can be added as test fixtures.
public struct HistoryExport: Codable, Sendable {
  public struct Entry: Codable, Sendable {
    public var photo: String
    public var date: Date
    public var pattern: Pattern
    public var score: Int
    public var rating: Int?
    public var components: [String: Double]
    public var analysisVersion: Int
  }

  public var exportedAt: Date
  public var pours: [Entry]

  public init(exportedAt: Date, pours: [(photo: String, record: PourRecord, analysisVersion: Int)]) {
    self.exportedAt = exportedAt
    self.pours = pours.map { p in
      Entry(photo: p.photo, date: p.record.date, pattern: p.record.pattern, score: p.record.score,
            rating: p.record.rating,
            components: Dictionary(uniqueKeysWithValues: p.record.components.map { ($0.key.rawValue, $0.value) }),
            analysisVersion: p.analysisVersion)
    }
  }

  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(self)
  }
}
