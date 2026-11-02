/// Latte art patterns the app can analyze. Each one gets its own analyzer.
public enum Pattern: String, CaseIterable, Sendable {
  case heart

  public var displayName: String {
    switch self {
    case .heart: "Heart"
    }
  }
}
