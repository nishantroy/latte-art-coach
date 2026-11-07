import Foundation

/// How the drink tasted, as the user logged it. Separate from the art score:
/// a beautiful heart can sit on a sour shot.
public struct DrinkTaste: Sendable, Equatable, Codable {
  /// The espresso's balance, the main dial-in signal.
  public enum Balance: String, CaseIterable, Sendable, Codable, Identifiable {
    /// Sharp, sour or salty: under-extracted.
    case sour
    case balanced
    /// Bitter, harsh or drying: over-extracted.
    case bitter
    /// Thin or watery under the milk.
    case weak
    public var id: String { rawValue }
    public var displayName: String {
      switch self {
      case .sour: "Sour"
      case .balanced: "Balanced"
      case .bitter: "Bitter"
      case .weak: "Weak"
      }
    }
  }

  public var balance: Balance?
  /// How much the user liked the drink, 1–5.
  public var rating: Int?
  /// Flavors the user noticed, e.g. ["blueberry", "chocolate"].
  public var notes: [String]

  public init(balance: Balance? = nil, rating: Int? = nil, notes: [String] = []) {
    self.balance = balance
    self.rating = rating
    self.notes = notes
  }

  public var isEmpty: Bool { self == DrinkTaste() }
}
