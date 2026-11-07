import Foundation

/// What the user's logged drinks say about what they like, and what helps
/// their art. Each finding needs enough drinks behind it to mean something,
/// and says how many.
public struct TastePreferences: Sendable, Equatable {
  public struct Finding: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable { case roast, origin, process, flavor, notes, milk }
    public var kind: Kind
    public var text: String
    public var id: String { kind.rawValue + text }
  }

  /// Broad flavor styles, from the label's tasting notes.
  public enum Style: String, Sendable, CaseIterable {
    case bright, sweet, rich
    public var displayName: String {
      switch self {
      case .bright: "bright, fruity coffees"
      case .sweet: "sweet, balanced coffees"
      case .rich: "rich, chocolatey coffees"
      }
    }

    /// From the mean lighter/darker weight of the notes, nil without known notes.
    public init?(notes: [String]) {
      let weights = notes.compactMap { BeanLabelParser.flavors[$0.lowercased()] }
      guard !weights.isEmpty else { return nil }
      let mean = Double(weights.reduce(0, +)) / Double(weights.count)
      self = mean >= 0.75 ? .bright : mean <= -0.5 ? .rich : .sweet
    }
  }

  public var findings: [Finding]
  public var ratedDrinks: Int

  /// Minimum rated drinks in a group before it's compared.
  public static let minimumDrinks = 3

  public init(records: [PourRecord]) {
    var findings: [Finding] = []
    let rated = records.filter { $0.taste?.rating != nil }
    ratedDrinks = rated.count
    func rating(_ r: PourRecord) -> Double { Double(r.taste!.rating!) }

    func compare(_ kind: Finding.Kind, _ key: (PourRecord) -> String?, name: (String) -> String) {
      let groups = Dictionary(grouping: rated.compactMap { r in key(r).map { ($0, r) } }) { $0.0 }
        .mapValues { $0.map(\.1) }
        .filter { $0.value.count >= Self.minimumDrinks }
      guard groups.count >= 2 else { return }
      let ranked = groups.map { (key: $0.key, mean: Self.mean($0.value.map(rating)), pours: $0.value) }
        .sorted { ($0.mean, $1.key) > ($1.mean, $0.key) }
      let best = ranked.first!, worst = ranked.last!
      guard best.mean - worst.mean >= 0.5 else { return }
      findings.append(Finding(kind: kind, text:
        "You rate \(name(best.key)) highest: \(Self.stars(best.mean)) over \(Self.drinks(best.pours)), vs \(Self.stars(worst.mean)) for \(name(worst.key))."))
    }
    compare(.roast, { $0.brew?.roastLevel?.rawValue }) { raw in
      "\(BeanLabel.RoastLevel(rawValue: raw)!.displayName.lowercased()) roasts"
    }
    compare(.flavor, { Style(notes: $0.brew?.tastingNotes ?? [])?.rawValue }) { Style(rawValue: $0)!.displayName }
    compare(.origin, { $0.brew?.beanOrigin }) { "beans from \($0)" }
    compare(.process, { $0.brew?.beanProcess?.lowercased() }) { "\($0) coffees" }

    // The flavors the user actually picks up.
    let tasted = Dictionary(grouping: records.flatMap { $0.taste?.notes ?? [] }.map { $0.lowercased() }) { $0 }
      .mapValues(\.count).filter { $0.value >= 2 }
      .sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(3)
    if !tasted.isEmpty {
      findings.append(Finding(kind: .notes, text:
        "Flavors you notice most: " + tasted.map { "\($0.key) (\($0.value)×)" }.joined(separator: ", ") + "."))
    }

    // Milk changes how the foam pours, so compare art scores, not taste.
    let byMilk = Dictionary(grouping: records.filter { $0.brew?.milk != nil }) { $0.brew!.milk! }
      .filter { $0.value.count >= Self.minimumDrinks }
    if byMilk.count >= 2 {
      let ranked = byMilk.map { (milk: $0.key, mean: Self.mean($0.value.map { Double($0.score) }), count: $0.value.count) }
        .sorted { ($0.mean, $1.milk.rawValue) > ($1.mean, $0.milk.rawValue) }
      let best = ranked.first!, worst = ranked.last!
      if best.mean - worst.mean >= 5 {
        findings.append(Finding(kind: .milk, text:
          "Your art scores best with \(best.milk.displayName.lowercased()) milk: \(Int(best.mean.rounded())) over \(best.count) pours, vs \(Int(worst.mean.rounded())) with \(worst.milk.displayName.lowercased())."))
      }
    }
    self.findings = findings
  }

  static func mean(_ v: [Double]) -> Double { v.reduce(0, +) / Double(v.count) }
  static func stars(_ v: Double) -> String { String(format: "%.1f★", v) }
  static func drinks(_ pours: [PourRecord]) -> String {
    let bags = Set(pours.compactMap { $0.brew?.beanName }).count
    return "\(pours.count) drinks" + (bags >= 2 ? " from \(bags) bags" : "")
  }
}

/// One bag of beans over time: how its drinks tasted and how the art went.
public struct BeanSummary: Sendable, Equatable {
  public var pourCount: Int
  public var averageScore: Double?
  /// Mean drink rating, 1–5, over rated drinks.
  public var averageRating: Double?
  public var ratedCount: Int
  /// Most common taste balance, when at least two drinks agree.
  public var usualBalance: DrinkTaste.Balance?

  public init(records: [PourRecord]) {
    pourCount = records.count
    averageScore = records.isEmpty ? nil : TastePreferences.mean(records.map { Double($0.score) })
    let ratings = records.compactMap { $0.taste?.rating.map(Double.init) }
    ratedCount = ratings.count
    averageRating = ratings.isEmpty ? nil : TastePreferences.mean(ratings)
    let balances = Dictionary(grouping: records.compactMap { $0.taste?.balance }) { $0 }.mapValues(\.count)
    usualBalance = balances.filter { $0.value >= 2 }.max { ($0.value, $1.key.rawValue) < ($1.value, $0.key.rawValue) }?.key
  }
}
