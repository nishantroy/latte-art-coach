import Foundation
import LatteCore
import SwiftData
import UIKit

/// A scored pour saved in history. The original photo is kept so the pour
/// can be re-scored when the analysis improves, and exported as a test
/// fixture.
@Model
final class Pour {
  var date: Date
  var patternRaw: String
  var score: Int
  /// Score components (0...1) keyed by `PourScore.Component.rawValue`.
  var componentScores: [String: Double]
  /// The user's own rating, 1–10.
  var rating: Int?
  @Attribute(.externalStorage) var photo: Data
  @Attribute(.externalStorage) var thumbnail: Data?
  /// `PourAnalysis.version` the score was computed with.
  var analysisVersion: Int
  // How the drink was made. All optional; new pours start from the last pour's.
  var bean: Bean?
  var grindSetting: String?
  var doseGrams: Double?
  var yieldGrams: Double?
  var shotSeconds: Double?
  var milkRaw: String?
  /// The model's coaching and the exact facts it was written from; reused
  /// while the facts are unchanged.
  var coachingData: Data?
  var coachingPrompt: String?

  init(photo: Data, analysis: PourAnalysis, date: Date = .now) {
    self.date = date
    self.photo = photo
    thumbnail = PhotoRendition(data: photo, maxDimension: 300)?.image.jpegData(compressionQuality: 0.8)
    patternRaw = analysis.pattern.rawValue
    score = analysis.score.overall
    componentScores = [:]
    analysisVersion = PourAnalysis.version
    update(from: analysis)
  }

  var pattern: Pattern { Pattern(rawValue: patternRaw) ?? .tulip }

  var savedCoaching: SavedCoaching? {
    get { coachingData.flatMap { try? JSONDecoder().decode(SavedCoaching.self, from: $0) } }
    set { coachingData = newValue.flatMap { try? JSONEncoder().encode($0) } }
  }

  var milk: BrewDetails.Milk? {
    get { milkRaw.flatMap(BrewDetails.Milk.init(rawValue:)) }
    set { milkRaw = newValue?.rawValue }
  }

  var brew: BrewDetails {
    BrewDetails(beanName: bean?.name, roaster: bean?.roaster, roastDate: bean?.roastDate, beanOrigin: bean?.origin,
                beanProcess: bean?.process, roastLevel: bean?.roastLevel, tastingNotes: bean?.tastingNotes ?? [],
                grindSetting: grindSetting,
                doseGrams: doseGrams, yieldGrams: yieldGrams, shotSeconds: shotSeconds, milk: milk)
  }

  /// Starts this pour's brew details from another pour's: most mornings
  /// only the shot time changes.
  func copyBrew(from other: Pour) {
    bean = other.bean
    grindSetting = other.grindSetting
    doseGrams = other.doseGrams
    yieldGrams = other.yieldGrams
    shotSeconds = other.shotSeconds
    milkRaw = other.milkRaw
  }

  func update(from analysis: PourAnalysis) {
    patternRaw = analysis.pattern.rawValue
    score = analysis.score.overall
    componentScores = Dictionary(uniqueKeysWithValues: analysis.score.components.map { ($0.key.rawValue, $0.value) })
    analysisVersion = PourAnalysis.version
  }

  var record: PourRecord {
    PourRecord(
      date: date, pattern: pattern, score: score,
      components: Dictionary(uniqueKeysWithValues: componentScores.compactMap { key, value in
        PourScore.Component(rawValue: key).map { ($0, value) }
      }),
      rating: rating, brew: brew.isEmpty ? nil : brew)
  }
}

enum PourAnalyzer {
  /// Runs the analysis off the main thread.
  static func analyze(_ data: Data, as pattern: Pattern) async -> Result<PourAnalysis, PourAnalysis.Failure> {
    await Task.detached(priority: .userInitiated) { () -> Result<PourAnalysis, PourAnalysis.Failure> in
      do throws(PourAnalysis.Failure) { return .success(try PourAnalysis.analyze(imageData: data, pattern: pattern)) }
      catch { return .failure(error) }
    }.value
  }

  /// Re-scores pours saved with an older version of the analysis.
  @MainActor
  static func rescoreOutdated(_ pours: [Pour], context: ModelContext) async {
    for pour in pours where pour.analysisVersion < PourAnalysis.version {
      if case .success(let analysis) = await analyze(pour.photo, as: pour.pattern) {
        pour.update(from: analysis)
      } else {
        pour.analysisVersion = PourAnalysis.version
      }
    }
    try? context.save()
  }
}
