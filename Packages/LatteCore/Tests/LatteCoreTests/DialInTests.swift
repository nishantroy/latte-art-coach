import Foundation
import Testing
@testable import LatteCore

@Suite struct DialInTests {
  static let day: TimeInterval = 86_400

  func kinds(_ tips: [DialInTip]) -> [DialInTip.Kind] { tips.map(\.kind) }

  @Test func onTargetShotNeedsNoAdvice() {
    let brew = BrewDetails(doseGrams: 18, yieldGrams: 36, shotSeconds: 28)
    #expect(DialIn.tips(brew: brew).isEmpty)
  }

  @Test func fastShotMeansFinerAndExplainsPaleCrema() {
    let brew = BrewDetails(doseGrams: 18, yieldGrams: 36, shotSeconds: 18)
    let tips = DialIn.tips(brew: brew, contrast: 0.4)
    #expect(kinds(tips) == [.grind])
    #expect(tips[0].title == "Grind finer")
    #expect(tips[0].detail.contains("25–32 s") && tips[0].detail.contains("pale crema"))
    #expect(!DialIn.tips(brew: brew, contrast: 0.9)[0].detail.contains("pale crema"))
  }

  @Test func slowShotMeansCoarser() {
    let tips = DialIn.tips(brew: BrewDetails(shotSeconds: 40))
    #expect(tips.first?.title == "Grind coarser")
  }

  @Test func tasteOutranksTheClock() {
    // In the time window but sour: still under-extracted.
    let brew = BrewDetails(doseGrams: 18, yieldGrams: 36, shotSeconds: 28)
    #expect(DialIn.tips(brew: brew, taste: .sour).first?.title == "Extract a little more")
    #expect(DialIn.tips(brew: brew, taste: .bitter).first?.title == "Extract a little less")
    #expect(DialIn.tips(brew: BrewDetails(shotSeconds: 38), taste: .bitter).first?.title == "Grind coarser")
    #expect(DialIn.tips(brew: BrewDetails(shotSeconds: 19), taste: .sour).first?.title == "Grind finer")
    #expect(DialIn.tips(brew: brew, taste: .weak).first?.kind == .ratio)
    #expect(DialIn.tips(brew: brew, taste: .balanced).isEmpty)
  }

  @Test func ratioDependsOnRoast() {
    // 1:1.6 is fine for a dark roast, short for a light one.
    let short = BrewDetails(roastLevel: .light, doseGrams: 18, yieldGrams: 29, shotSeconds: 30)
    let tip = DialIn.tips(brew: short).first
    #expect(tip?.title == "Pull a longer shot")
    #expect(tip?.detail.contains("36–45 g") == true)
    #expect(DialIn.tips(brew: BrewDetails(roastLevel: .dark, doseGrams: 18, yieldGrams: 29, shotSeconds: 25)).isEmpty)
    #expect(DialIn.tips(brew: BrewDetails(doseGrams: 18, yieldGrams: 50, shotSeconds: 28)).first?.title == "Pull a shorter shot")
  }

  @Test func freshness() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let roast = Date(timeIntervalSince1970: 100 * Self.day)
    let brew = BrewDetails(roastDate: roast)
    func tip(after days: Double) -> DialInTip? {
      DialIn.tips(brew: brew, date: Date(timeIntervalSince1970: (100 + days) * Self.day), calendar: calendar).first
    }
    #expect(tip(after: 2)?.title == "Let the beans rest")
    #expect(tip(after: 10) == nil)
    #expect(tip(after: 50)?.title == "Beans are getting old")
  }

  func record(grind: String, score: Int, rating: Int? = nil, seconds: Double = 28, bean: String = "Hambela") -> PourRecord {
    PourRecord(date: .now, pattern: .heart, score: score, components: [:], rating: nil,
               brew: BrewDetails(beanName: bean, grindSetting: grind, shotSeconds: seconds),
               taste: rating.map { DrinkTaste(rating: $0) })
  }

  @Test func remembersTheGrindThatWorked() {
    let history = [
      record(grind: "12", score: 82, seconds: 29), record(grind: "12", score: 84, seconds: 27),
      record(grind: "14", score: 70), record(grind: "14", score: 72),
      record(grind: "10", score: 90, bean: "Other"), record(grind: "10", score: 90, bean: "Other"),
    ]
    let now = BrewDetails(beanName: "Hambela", grindSetting: "14", shotSeconds: 28)
    let tip = DialIn.tips(brew: now, history: history).last
    #expect(tip?.kind == .history)
    #expect(tip?.title == "Grind 12 worked best")
    #expect(tip?.detail == "With Hambela, your shots at grind 12, around 28 s art averaged 83 over 2 pours, vs 71 at grind 14.")
    // Already there, or no clear difference: nothing to say.
    #expect(DialIn.tips(brew: BrewDetails(beanName: "Hambela", grindSetting: "12", shotSeconds: 28), history: history).isEmpty)
    let close = [record(grind: "12", score: 80), record(grind: "12", score: 80), record(grind: "14", score: 78), record(grind: "14", score: 78)]
    #expect(DialIn.tips(brew: now, history: close).isEmpty)
  }

  @Test func tasteRatingsBeatArtScoresForGrind() {
    let history = [
      record(grind: "12", score: 90, rating: 2), record(grind: "12", score: 90, rating: 3),
      record(grind: "14", score: 70, rating: 5), record(grind: "14", score: 70, rating: 4),
    ]
    let tip = DialIn.tips(brew: BrewDetails(beanName: "Hambela", grindSetting: "12", shotSeconds: 28), history: history).last
    #expect(tip?.title == "Grind 14 worked best")
    #expect(tip?.detail.contains("4.5★") == true)
  }

  @Test func coachingBriefCarriesTasteAndDialIn() throws {
    let a = try PourAnalysis.analyze(imageData: Data(contentsOf: HeartPhotoTests.url), pattern: .heart)
    let brew = BrewDetails(shotSeconds: 18)
    let prompt = CoachingBrief.prompt(pattern: .heart, score: a.score, tips: a.tips, history: nil, rating: nil, brew: brew,
                                      taste: DrinkTaste(balance: .sour, rating: 2, notes: ["lemon"]),
                                      dialIn: DialIn.tips(brew: brew, taste: .sour))
    #expect(prompt.contains("- Taste: the espresso tasted sour; they rated the drink 2 out of 5; they tasted lemon."))
    #expect(prompt.contains("- Grind finer: Sour and fast (18 s)"))
  }
}

@Suite struct TastePreferencesTests {
  func drink(_ rating: Int, roast: BeanLabel.RoastLevel? = nil, notes: [String] = [], bean: String = "A",
             milk: BrewDetails.Milk? = nil, score: Int = 70, tasted: [String] = []) -> PourRecord {
    PourRecord(date: .now, pattern: .heart, score: score, components: [:], rating: nil,
               brew: BrewDetails(beanName: bean, roastLevel: roast, tastingNotes: notes, milk: milk),
               taste: DrinkTaste(rating: rating, notes: tasted))
  }

  @Test func needsEnoughDrinksToSayAnything() {
    let few = [drink(5, roast: .light), drink(5, roast: .light), drink(1, roast: .dark)]
    #expect(TastePreferences(records: few).findings.isEmpty)
  }

  @Test func comparesRoastsAndFlavorStyles() {
    let light = ["jasmine", "lemon"], dark = ["dark chocolate", "molasses"]
    let records = [
      drink(5, roast: .light, notes: light, bean: "A"), drink(4, roast: .light, notes: light, bean: "B"),
      drink(5, roast: .light, notes: light, bean: "B"),
      drink(2, roast: .dark, notes: dark), drink(3, roast: .dark, notes: dark), drink(2, roast: .dark, notes: dark),
    ]
    let texts = TastePreferences(records: records).findings.map(\.text)
    #expect(texts.contains("You rate light roasts highest: 4.7★ over 3 drinks from 2 bags, vs 2.3★ for dark roasts."))
    #expect(texts.contains("You rate bright, fruity coffees highest: 4.7★ over 3 drinks from 2 bags, vs 2.3★ for rich, chocolatey coffees."))
  }

  @Test func milkComparesArtNotTaste() {
    let records = (0..<3).map { _ in drink(3, milk: .whole, score: 82) } + (0..<3).map { _ in drink(3, milk: .oat, score: 68) }
    #expect(TastePreferences(records: records).findings.map(\.text)
      == ["Your art scores best with whole milk: 82 over 3 pours, vs 68 with oat."])
  }

  @Test func countsNoticedFlavors() {
    let records = [drink(4, tasted: ["Blueberry", "cocoa"]), drink(4, tasted: ["blueberry"]), drink(4, tasted: ["cocoa", "blueberry"])]
    #expect(TastePreferences(records: records).findings.map(\.text) == ["Flavors you notice most: blueberry (3×), cocoa (2×)."])
  }

  @Test func summarizesABean() {
    let records = [
      PourRecord(date: .now, pattern: .heart, score: 80, components: [:], rating: nil, taste: DrinkTaste(balance: .sour, rating: 3)),
      PourRecord(date: .now, pattern: .heart, score: 70, components: [:], rating: nil, taste: DrinkTaste(balance: .sour)),
      PourRecord(date: .now, pattern: .heart, score: 60, components: [:], rating: nil, taste: DrinkTaste(rating: 5)),
    ]
    let s = BeanSummary(records: records)
    #expect(s.pourCount == 3 && s.averageScore == 70 && s.averageRating == 4 && s.ratedCount == 2 && s.usualBalance == .sour)
  }
}
