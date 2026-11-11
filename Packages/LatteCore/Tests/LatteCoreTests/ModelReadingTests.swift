import Foundation
import Testing
@testable import LatteCore

/// Checks how the model's answers are combined with the rules'. The model
/// itself only runs on a device with Apple Intelligence.
@Suite struct ModelReadingTests {
  typealias T = BeanLabelTests
  static let huckleberry = [
    "HUCK", "HUCKLEBERRY ROASTERS", "DENVER, COLORADO", "Civitas", "Trade", "Blend",
    "dark sugars • chocolate • toffee", "Our Civitas blend is slightly darker roasted with a pleasant nuttiness",
    "ROAST/BLEND DATE", "10/30/26",
  ].map { LabelLine($0, height: 0.015, left: $0 == "Trade" ? 0.51 : 0.33) }

  static func merge(_ lines: [LabelLine], _ model: ModelReading) -> BeanLabel {
    BeanLabelParser.merge(BeanLabelParser.parse(lines, today: T.today, calendar: T.utc), model, lines: lines,
                          today: T.today, calendar: T.utc)
  }

  @Test func takesCheckedAnswersAndDropsInventedOnes() {
    var model = ModelReading()
    model.name = "HUCK"                       // the brand mark
    model.origin = "Colombia"                 // not on the bag
    model.roastLevel = "Medium-dark"
    model.tastingNotes = ["Dark Sugars", "chocolate", "toffee", "nuttiness", "blend date", "cherry"]
    let label = Self.merge(Self.huckleberry, model)
    #expect(label.name == "Civitas Blend")
    #expect(label.roaster == "Huckleberry Roasters")
    #expect(label.origin == nil, "invented")
    #expect(label.roastDate == T.day(2026, 10, 30))
    #expect(label.roastLevel == .mediumDark && label.roastLevelIsGuess)
    #expect(label.tastingNotes == ["dark sugars", "chocolate", "toffee", "nuttiness"])
  }

  /// The phone missed "HUCKLEBERRY ROASTERS"; the model then named the
  /// coffee as its own roaster.
  @Test func aRoasterIsNotTheCoffeesName() {
    let lines = Self.huckleberry.filter { $0.text != "HUCKLEBERRY ROASTERS" }
    var model = ModelReading()
    model.name = "Civitas Blend"; model.roaster = "Civitas"
    let label = Self.merge(lines, model)
    #expect(label.name == "Civitas Blend" && label.roaster == nil)
  }

  /// The phone reads Motoring's stylized M as "VI".
  @Test func snapsAMisreadRoasterToASavedOne() {
    let saved = ["Huckleberry Roasters", "Motoring Coffee"]
    #expect(BeanLabelParser.closest("Viotoring Coffee", among: saved) == "Motoring Coffee")
    #expect(BeanLabelParser.closest("HUCKLEBERRY ROASTERS", among: saved) == "Huckleberry Roasters")
    #expect(BeanLabelParser.closest("Onyx Coffee Lab", among: saved) == nil)
    #expect(BeanLabelParser.closest("Sey", among: ["Onyx"]) == nil)
  }

  @Test func fillsWhatTheRulesMissed() {
    let lines = ["ONYX", "Guji Hambela", "Ethiopia", "Washed", "74158", "elevation 2,100 m", "packed 11.01.26", "Peach tea, jasmine"]
      .map { LabelLine($0) }
    var model = ModelReading()
    model.name = "Guji Hambela"; model.roaster = "ONYX"; model.variety = "74158"
    model.roastDate = "11.01.26"; model.tastingNotes = ["peach tea", "jasmine"]
    let label = Self.merge(lines, model)
    #expect(label.name == "Guji Hambela" && label.roaster == "ONYX")
    #expect(label.variety == "74158")
    #expect(label.altitude == "2,100 m")
    #expect(label.tastingNotes == ["peach tea", "jasmine"])
  }

  @Test func printedRoastLevelAndRuleDatesWin() {
    let lines = ["Brazil Cerrado", "Medium Roast", "Roasted on 2026-10-30", "Best by 2026-11-01"].map { LabelLine($0) }
    var model = ModelReading()
    model.roastLevel = "dark"; model.roastDate = "2026-11-01"
    let label = Self.merge(lines, model)
    #expect(label.roastLevel == .medium && !label.roastLevelIsGuess)
    #expect(label.roastDate == T.day(2026, 10, 30))
  }

  @Test func rejectsAnImplausibleModelDate() {
    var model = ModelReading()
    model.roastDate = "Best by 2027-05-01"
    #expect(Self.merge(["Colombia", "Best by 2027-05-01"].map { LabelLine($0) }, model).roastDate == nil)
  }
}
