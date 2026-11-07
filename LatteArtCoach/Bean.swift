import Foundation
import LatteCore
import SwiftData

/// A bag of coffee, entered by hand or read off the bag's label.
@Model
final class Bean {
  var name: String
  var roaster: String?
  var roastDate: Date?
  var origin: String?
  var process: String?
  var variety: String?
  var altitude: String?
  var roastLevelRaw: String?
  /// The roast level wasn't printed; it was guessed from the tasting notes.
  var roastLevelIsGuess = false
  var tastingNotes: [String] = []
  /// Everything read off the bag, kept so it can be re-read as parsing improves.
  var labelText: String?
  var addedAt: Date
  /// The user's own notes on the bag.
  var notes: String?
  @Relationship(deleteRule: .nullify, inverse: \Pour.bean) var pours: [Pour] = []

  init(name: String, roaster: String? = nil, roastDate: Date? = nil) {
    self.name = name
    self.roaster = roaster
    self.roastDate = roastDate
    addedAt = .now
  }

  /// Pours with these beans, oldest first.
  var records: [PourRecord] { pours.sorted { $0.date < $1.date }.map(\.record) }

  var summary: BeanSummary { BeanSummary(records: records) }

  var roastLevel: BeanLabel.RoastLevel? {
    get { roastLevelRaw.flatMap(BeanLabel.RoastLevel.init(rawValue:)) }
    set { roastLevelRaw = newValue?.rawValue }
  }
}
