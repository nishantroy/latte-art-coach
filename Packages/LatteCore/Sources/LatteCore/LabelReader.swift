import CoreGraphics
import Foundation
import Vision

/// Recognizes the text on a photo of a coffee bag, on the device.
public enum LabelReader {
  /// A line taller than this fraction of the photo is a giant brand mark.
  static let giant = 0.12

  /// - Parameter forceBands: rereads in bands even without giant text (tests).
  public static func read(_ image: CGImage, forceBands: Bool = false) async throws -> [LabelLine] {
    var found = try await recognize(image, band: 0...1)
    // Some versions of text recognition read a giant word printed down the
    // bag ("HUCK") as one block and drop the small lines set between its
    // letters ("HUCKLEBERRY ROASTERS"). Reread that stretch in short bands,
    // each holding only a slice of the big letters, and keep what's new.
    let spans = found.filter { $0.line.height > giant }.map { $0.top - $0.line.height ... $0.top }
    for span in forceBands && spans.isEmpty ? [0.0...1.0] : spans {
      let size = min(0.25, span.upperBound - span.lowerBound), step = size * 0.6
      var bottom = span.lowerBound
      while bottom < span.upperBound - size * 0.4 {
        let band = bottom ... min(1, bottom + size)
        for extra in try await recognize(image, band: band) where !found.contains(where: { covers($0.line.text, extra.line.text) }) {
          found.append(extra)
        }
        bottom += step
      }
    }
    // Top to bottom, as printed (Vision's y axis points up).
    return found.sorted { $0.top > $1.top }.map(\.line)
  }

  /// Lines in a horizontal band of the image (normalized, y up), with their
  /// top edge and height converted back to the whole image.
  static func recognize(_ image: CGImage, band: ClosedRange<Double>) async throws -> [(line: LabelLine, top: Double)] {
    let h = Double(image.height), span = band.upperBound - band.lowerBound
    let rect = CGRect(x: 0, y: ((1 - band.upperBound) * h).rounded(), width: Double(image.width), height: (span * h).rounded())
    guard let crop = span < 1 ? image.cropping(to: rect) : image else { return [] }
    var request = RecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.minimumTextHeightFraction = Float(0.005 / span)
    return try await request.perform(on: crop).compactMap { obs in
      let box = obs.boundingBox
      // A line cut by the band's edge reads as junk ("VET W").
      if span < 1, box.origin.y < 0.02 || box.origin.y + box.height > 0.98 { return nil }
      return obs.topCandidates(1).first.map {
        (LabelLine($0.string, height: Double(box.height) * span, left: Double(box.origin.x)),
         band.lowerBound + Double(box.origin.y + box.height) * span)
      }
    }
  }

  /// Whether `line` already holds `piece`, ignoring case and punctuation.
  static func covers(_ line: String, _ piece: String) -> Bool {
    BeanLabelParser.squash(line).contains(BeanLabelParser.squash(piece))
  }

  public static func read(imageData: Data, forceBands: Bool = false) async throws -> [LabelLine] {
    let image = try RGBAImage.load(data: imageData, maxDimension: 2400)
    guard let cg = image.makeCGImage() else { return [] }
    return try await read(cg, forceBands: forceBands)
  }
}
