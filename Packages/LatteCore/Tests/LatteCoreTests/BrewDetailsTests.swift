import Foundation
import Testing
@testable import LatteCore

@Suite struct BrewDetailsTests {
  static let day: TimeInterval = 86_400

  @Test func summarizesTheShot() {
    let brew = BrewDetails(grindSetting: "12", doseGrams: 18, yieldGrams: 36, shotSeconds: 28.4)
    #expect(brew.ratio == 2)
    #expect(brew.shotSummary == "18 g → 36 g (1:2.0) in 28 s · grind 12")
    #expect(BrewDetails(doseGrams: 18.5).shotSummary == "18.5 g in")
    #expect(BrewDetails(milk: .oat).shotSummary == nil)
    #expect(BrewDetails().isEmpty && !BrewDetails(milk: .oat).isEmpty)
  }

  @Test func countsDaysOffRoast() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let roast = Date(timeIntervalSince1970: 10 * Self.day + 3600)
    let brew = BrewDetails(roastDate: roast)
    #expect(brew.daysOffRoast(on: Date(timeIntervalSince1970: 19 * Self.day + 80_000), calendar: calendar) == 9)
    #expect(BrewDetails().daysOffRoast(on: .now) == nil)
  }

  @Test func coachingBriefIncludesOnlyLoggedBrewFacts() throws {
    let a = try PourAnalysis.analyze(imageData: Data(contentsOf: HeartPhotoTests.url), pattern: .heart)
    let brew = BrewDetails(beanName: "Guji Natural", roaster: "Onyx", roastDate: Date(timeIntervalSince1970: 0),
                           doseGrams: 18, yieldGrams: 40, shotSeconds: 31, milk: .oat)
    let prompt = CoachingBrief.prompt(pattern: .heart, score: a.score, tips: a.tips, history: nil, rating: nil,
                                      brew: brew, date: Date(timeIntervalSince1970: 12 * Self.day))
    #expect(prompt.contains("- Espresso shot: 18 g → 40 g (1:2.2) in 31 s."))
    #expect(prompt.contains("- Milk: oat."))
    #expect(prompt.contains("- Beans: Guji Natural from Onyx, roasted 12 days before this pour."))
    let bare = CoachingBrief.prompt(pattern: .heart, score: a.score, tips: a.tips, history: nil, rating: nil, brew: BrewDetails())
    #expect(!bare.contains("How the drink was made"))
  }

  @Test func coachingBriefDescribesTheBeans() throws {
    let a = try PourAnalysis.analyze(imageData: Data(contentsOf: HeartPhotoTests.url), pattern: .heart)
    let brew = BrewDetails(beanName: "Hambela", roaster: "Onyx", beanOrigin: "Ethiopia", beanProcess: "Washed",
                           roastLevel: .light, tastingNotes: ["jasmine", "peach"])
    let prompt = CoachingBrief.prompt(pattern: .heart, score: a.score, tips: a.tips, history: nil, rating: nil, brew: brew)
    #expect(prompt.contains("- Beans: Hambela from Onyx (Ethiopia, washed, light roast), tasting notes jasmine, peach."))
  }

  @Test func exportCarriesBrewDetails() throws {
    let record = PourRecord(date: .now, pattern: .tulip, score: 70, components: [:], rating: 6,
                            brew: BrewDetails(grindSetting: "2.5", doseGrams: 18))
    let data = try HistoryExport(exportedAt: .now, pours: [("p.jpg", record, 1)]).encoded()
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    #expect(try decoder.decode(HistoryExport.self, from: data).pours.first?.brew?.grindSetting == "2.5")
  }
}
