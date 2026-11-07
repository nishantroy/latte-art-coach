import Foundation
import SwiftData

/// A bag of coffee. For now entered by hand; scanning the bag's label to
/// fill these in comes next.
@Model
final class Bean {
  var name: String
  var roaster: String?
  var roastDate: Date?
  var addedAt: Date
  @Relationship(deleteRule: .nullify, inverse: \Pour.bean) var pours: [Pour] = []

  init(name: String, roaster: String? = nil, roastDate: Date? = nil) {
    self.name = name
    self.roaster = roaster
    self.roastDate = roastDate
    addedAt = .now
  }
}
