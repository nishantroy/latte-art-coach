import CoreGraphics
import Foundation
import Vision

/// Recognizes the text on a photo of a coffee bag, on the device.
public enum LabelReader {
  public static func read(_ image: CGImage) async throws -> [LabelLine] {
    var request = RecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.minimumTextHeightFraction = 0.005
    let observations = try await request.perform(on: image)
    // Top to bottom, as printed (Vision's y axis points up).
    return observations
      .sorted { $0.boundingBox.origin.y + $0.boundingBox.height > $1.boundingBox.origin.y + $1.boundingBox.height }
      .compactMap { obs in
        obs.topCandidates(1).first.map { LabelLine($0.string, height: Double(obs.boundingBox.height)) }
      }
  }

  public static func read(imageData: Data) async throws -> [LabelLine] {
    let image = try RGBAImage.load(data: imageData, maxDimension: 2400)
    guard let cg = image.makeCGImage() else { return [] }
    return try await read(cg)
  }
}
