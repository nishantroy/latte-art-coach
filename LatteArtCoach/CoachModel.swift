import LatteCore
import SwiftData
import SwiftUI
import UIKit

@MainActor @Observable
final class CoachModel {
  enum State {
    case idle
    case analyzing
    /// Scored but not yet shown: the user rates the pour first.
    case rating(UIImage, PourAnalysis, Pour)
    case result(UIImage, PourAnalysis, Pour?)
    case failed(String)
  }

  private(set) var state: State = .idle
  /// Where scored pours are saved. Set by the view that owns the model.
  var context: ModelContext?

  var isShowingResult: Bool {
    if case .result = state { return true }
    return false
  }

  func reset() { state = .idle }

  /// Shows the score once the user has rated the pour (or skipped).
  func reveal() {
    guard case .rating(let image, let analysis, let pour) = state else { return }
    try? context?.save()
    state = .result(image, analysis, pour)
  }
  func fail(_ message: String) { state = .failed(message) }

  /// Scores the current photo as a different pattern. Analysis takes tens of
  /// milliseconds, so the result is swapped in place without a spinner.
  func rescore(as pattern: Pattern) async {
    guard case .result(let image, let previous, let pour) = state, previous.pattern != pattern, let pour else { return }
    await reanalyze(image: image, pour: pour, as: pattern)
  }

  /// Re-scores with a cup outline the user placed by hand.
  func adjustCup(_ cup: LatteCore.Ellipse?) async {
    guard case .result(let image, let analysis, let pour?) = state else { return }
    pour.manualCup = cup
    await reanalyze(image: image, pour: pour, as: analysis.pattern)
  }

  private func reanalyze(image: UIImage, pour: Pour, as pattern: Pattern) async {
    switch await PourAnalyzer.analyze(pour.photo, as: pattern, cup: pour.manualCup) {
    case .success(let analysis):
      pour.update(from: analysis)
      try? context?.save()
      state = .result(image, analysis, pour)
    case .failure(let failure):
      state = .failed(Self.message(for: failure))
    }
  }

  func analyze(_ data: Data, as pattern: Pattern) async {
    state = .analyzing
    let outcome = await PourAnalyzer.analyze(data, as: pattern)
    let photo = await Task.detached(priority: .userInitiated) { PhotoRendition(data: data) }.value
    switch (outcome, photo) {
    case (.success(let analysis), let photo?):
      let pour = Pour(photo: data, analysis: analysis)
      var latest = FetchDescriptor<Pour>(sortBy: [SortDescriptor(\.date, order: .reverse)])
      latest.fetchLimit = 1
      if let previous = try? context?.fetch(latest).first { pour.copyBrew(from: previous) }
      context?.insert(pour)
      try? context?.save()
      state = .rating(photo.image, analysis, pour)
    case (.success, nil):
      state = .failed(Self.message(for: .unreadableImage))
    case (.failure(let failure), _):
      state = .failed(Self.message(for: failure))
    }
  }

  static func message(for failure: PourAnalysis.Failure) -> String {
    switch failure {
    case .unreadableImage: "That file couldn't be read as a photo."
    case .noCoffeeFound: "No cup of coffee found. Shoot from above with the whole cup in the frame."
    case .noPatternFound: "Found the cup, but no latte art in it. Make sure the foam pattern is in focus."
    }
  }
}

/// A display-sized, orientation-corrected copy of the photo.
struct PhotoRendition: @unchecked Sendable {
  let image: UIImage

  init?(data: Data, maxDimension: Int = 1600) {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
          ] as CFDictionary)
    else { return nil }
    image = UIImage(cgImage: cg)
  }
}
