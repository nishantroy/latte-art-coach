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

  var isShowingResult: Bool {
    if case .result = state { return true }
    return false
  }

  func reset() { state = .idle }
  func fail(_ message: String) { state = .failed(message) }

  func analyze(_ data: Data) async {
    state = .analyzing
    // Decoding and analysis run off the main thread; both are pure functions of the data.
    let outcome = await Task.detached(priority: .userInitiated) { () -> Result<(PhotoRendition, PourAnalysis), PourAnalysis.Failure> in
      do throws(PourAnalysis.Failure) {
        let analysis = try PourAnalysis.analyze(imageData: data)
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
