/// Latte art patterns the app can score. The user says which one they meant
/// to pour; the score judges the pour against that pattern.
public enum Pattern: String, CaseIterable, Sendable, Identifiable {
  case heart, tulip, rosetta

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .heart: "Heart"
    case .tulip: "Tulip"
    case .rosetta: "Rosetta"
    }
  }

  /// Lowercase name for use mid-sentence.
  public var noun: String { rawValue }

  /// The pattern the foam shape most resembles, from the measured metrics.
  /// Only clear-cut shapes are named; anything ambiguous returns nil.
  /// - A heart is one solid blob with no crema lines inside it.
  /// - A rosetta has many thin leaves.
  /// - A tulip has a few thick, separate stacks.
  public static func resembling(_ m: PourMetrics) -> Pattern? {
    if m.stackCount <= 1 && m.fill >= 0.9 { return .heart }
    if m.stackCount >= 5 && m.stackThickness < 0.14 { return .rosetta }
    if (2...5).contains(m.stackCount) && m.stackThickness >= 0.2 { return .tulip }
    return nil
  }
}
