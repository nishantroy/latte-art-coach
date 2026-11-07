import Foundation

/// How the drink behind a pour was made. Every field is optional: users log
/// what they know, and anything unknown stays unknown.
public struct BrewDetails: Sendable, Equatable, Codable {
  public enum Milk: String, CaseIterable, Sendable, Codable, Identifiable {
    case whole, reduced, skim, oat, almond, soy, other
    public var id: String { rawValue }
    public var displayName: String {
      switch self {
      case .whole: "Whole"
      case .reduced: "2%"
      case .skim: "Skim"
      case .oat: "Oat"
      case .almond: "Almond"
      case .soy: "Soy"
      case .other: "Other"
      }
    }
  }

  public var beanName: String?
  public var roaster: String?
  public var roastDate: Date?
  /// The beans' character, from the bag: e.g. "Ethiopia, washed, light roast".
  public var beanOrigin: String?
  public var beanProcess: String?
  public var roastLevel: BeanLabel.RoastLevel?
  public var tastingNotes: [String] = []
  /// Free text: grinders use numbers, clicks or letters.
  public var grindSetting: String?
  public var doseGrams: Double?
  public var yieldGrams: Double?
  public var shotSeconds: Double?
  public var milk: Milk?

  public init(beanName: String? = nil, roaster: String? = nil, roastDate: Date? = nil, beanOrigin: String? = nil,
              beanProcess: String? = nil, roastLevel: BeanLabel.RoastLevel? = nil, tastingNotes: [String] = [],
              grindSetting: String? = nil, doseGrams: Double? = nil, yieldGrams: Double? = nil,
              shotSeconds: Double? = nil, milk: Milk? = nil) {
    self.beanName = beanName
    self.roaster = roaster
    self.roastDate = roastDate
    self.beanOrigin = beanOrigin
    self.beanProcess = beanProcess
    self.roastLevel = roastLevel
    self.tastingNotes = tastingNotes
    self.grindSetting = grindSetting
    self.doseGrams = doseGrams
    self.yieldGrams = yieldGrams
    self.shotSeconds = shotSeconds
    self.milk = milk
  }

  public var isEmpty: Bool { self == BrewDetails() }

  /// Yield / dose, e.g. 2.0 for 18 g in, 36 g out.
  public var ratio: Double? {
    guard let dose = doseGrams, let yield = yieldGrams, dose > 0 else { return nil }
    return yield / dose
  }

  /// Whole days between roasting and `date`.
  public func daysOffRoast(on date: Date, calendar: Calendar = .current) -> Int? {
    guard let roastDate else { return nil }
    return calendar.dateComponents([.day], from: calendar.startOfDay(for: roastDate), to: calendar.startOfDay(for: date)).day
  }

  /// The shot in one line, e.g. "18 g → 36 g (1:2.0) in 28 s · grind 12".
  public var shotSummary: String? {
    var parts: [String] = []
    switch (doseGrams, yieldGrams) {
    case let (dose?, yield?): parts.append("\(Self.grams(dose)) → \(Self.grams(yield)) (1:\(String(format: "%.1f", yield / dose)))")
    case let (dose?, nil): parts.append("\(Self.grams(dose)) in")
    case let (nil, yield?): parts.append("\(Self.grams(yield)) out")
    case (nil, nil): break
    }
    if let shotSeconds { parts.append("\(Int(shotSeconds.rounded())) s") }
    var line = parts.joined(separator: " in ")
    if let grindSetting, !grindSetting.isEmpty { line += (line.isEmpty ? "" : " · ") + "grind \(grindSetting)" }
    return line.isEmpty ? nil : line
  }

  static func grams(_ value: Double) -> String {
    value == value.rounded() ? "\(Int(value)) g" : String(format: "%.1f g", value)
  }
}
