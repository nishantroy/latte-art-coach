import LatteCore
import SwiftUI
import UIKit

@MainActor @Observable
final class CoachModel {
  enum State {
    case idle
    case analyzing
    case result(UIImage, PourAnalysis)
    case failed(String)
  }

  private(set) var state: State = .idle
  /// The last photo, kept so it can be re-scored as a different pattern.
  private var lastData: Data?

  var isShowingResult: Bool {
    if case .result = state { return true }
    return false
  }

  func reset() { state = .idle; lastData = nil }
  func fail(_ message: String) { state = .failed(message) }

  /// Scores the last photo as a different pattern. Analysis takes tens of
  /// milliseconds, so the result is swapped in place without a spinner.
  func rescore(as pattern: Pattern) async {
    guard let data = lastData, case .result(let image, let previous) = state, previous.pattern != pattern else { return }
    let outcome = await Task.detached(priority: .userInitiated) { () -> Result<PourAnalysis, PourAnalysis.Failure> in
      do throws(PourAnalysis.Failure) { return .success(try PourAnalysis.analyze(imageData: data, pattern: pattern)) }
      catch { return .failure(error) }
    }.value
    switch outcome {
    case .success(let analysis): state = .result(image, analysis)
    case .failure(let failure): state = .failed(Self.message(for: failure))
    }
  }

  func analyze(_ data: Data, as pattern: Pattern) async {
    state = .analyzing
    lastData = data
    // Decoding and analysis run off the main thread; both are pure functions of the data.
    let outcome = await Task.detached(priority: .userInitiated) { () -> Result<(PhotoRendition, PourAnalysis), PourAnalysis.Failure> in
      do throws(PourAnalysis.Failure) {
        let analysis = try PourAnalysis.analyze(imageData: data, pattern: pattern)
        guard let photo = PhotoRendition(data: data) else { return .failure(.unreadableImage) }
        return .success((photo, analysis))
      } catch {
        return .failure(error)
      }
    }.value
    switch outcome {
    case .success(let (photo, analysis)):
      state = .result(photo.image, analysis)
    case .failure(let failure):
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
