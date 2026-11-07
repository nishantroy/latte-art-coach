import FoundationModels
import LatteCore
import SwiftUI

/// The coffee's name and roaster, picked out of a bag's text by the
/// on-device model.
@Generable
struct BagNames {
  @Guide(description: "The coffee's own name exactly as printed, such as the farm, region or blend name. Empty if unclear.")
  var name: String
  @Guide(description: "The roaster or brand exactly as printed. Empty if unclear.")
  var roaster: String
}

/// Reads a bag photo: text recognition, then fixed rules for the details,
/// then the model for name and roaster when it's available.
enum BagScanner {
  struct Result {
    var name: String?
    var roaster: String?
    var label: BeanLabel
    var text: String
  }

  static func scan(_ imageData: Data) async throws -> Result {
    let lines = try await LabelReader.read(imageData: imageData)
    let label = BeanLabelParser.parse(lines)
    let text = lines.map(\.text).joined(separator: "\n")
    var result = Result(name: label.headline, roaster: nil, label: label, text: text)
    if case .available = SystemLanguageModel.default.availability, !lines.isEmpty,
       let names = try? await names(from: lines) {
      result.name = names.name ?? result.name
      result.roaster = names.roaster
    }
    return result
  }

  static func names(from lines: [LabelLine]) async throws -> (name: String?, roaster: String?) {
    let session = LanguageModelSession(instructions: """
      You read text recognized from photos of coffee bags. Use only words that appear in the text. Never invent a name.
      """)
    let biggest = lines.sorted { $0.height > $1.height }.prefix(3).map(\.text)
    let prompt = """
      Text on the bag, top to bottom:
      \(lines.map(\.text).joined(separator: "\n"))

      The largest text: \(biggest.joined(separator: " / ")).
      Which text is the coffee's name, and which is the roaster?
      """
    let names = try await session.respond(to: prompt, generating: BagNames.self).content
    // Only keep answers that are really on the bag.
    let all = lines.map(\.text).joined(separator: " ").lowercased()
    func onBag(_ s: String) -> String? {
      let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
      return !t.isEmpty && all.contains(t.lowercased()) ? t : nil
    }
    return (onBag(names.name), onBag(names.roaster))
  }
}
