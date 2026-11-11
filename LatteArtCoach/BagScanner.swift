import FoundationModels
import LatteCore
import SwiftUI

/// Every detail of a coffee bag, picked out of its recognized text by the
/// on-device model.
@Generable
struct BagReading {
  @Guide(description: "The coffee's own name exactly as printed, such as the farm, region or blend name. Not the roaster's logo or a badge. Empty if unclear.")
  var name: String
  @Guide(description: "The roaster or brand exactly as printed. Empty if unclear.")
  var roaster: String
  @Guide(description: "Country or region the beans come from, as printed. Empty for a blend that doesn't say.")
  var origin: String
  @Guide(description: "Processing method as printed, such as washed, natural or honey. Empty if not printed.")
  var process: String
  @Guide(description: "Coffee varieties as printed, such as Bourbon or SL28. Empty if not printed.")
  var variety: String
  @Guide(description: "Growing altitude exactly as printed, with its unit. Empty if not printed.")
  var altitude: String
  @Guide(description: "The roast or blend date exactly as printed, such as 10/30/26. Not a best-by date. Empty if not printed.")
  var roastDate: String
  @Guide(description: "How dark the roast is: light, medium, medium-dark or dark, from what the bag prints or describes. Empty if it gives no hint.")
  var roastLevel: String
  @Guide(description: "Flavors the bag lists or describes, each a word or two as printed, such as chocolate or dark sugars. Not headings, dates or badges.", .maximumCount(8))
  var tastingNotes: [String]
}

/// Reads a bag photo: text recognition, then fixed rules, then the model
/// when Apple Intelligence is on. `BeanLabelParser.merge` keeps only model
/// answers that check out against the bag's text.
enum BagScanner {
  struct Result {
    var name: String?
    var roaster: String?
    var label: BeanLabel
    var text: String
  }

  static func scan(_ imageData: Data) async throws -> Result {
    let lines = try await LabelReader.read(imageData: imageData)
    var label = BeanLabelParser.parse(lines)
    if case .available = SystemLanguageModel.default.availability, !lines.isEmpty,
       let reading = try? await read(lines) {
      label = BeanLabelParser.merge(label, reading, lines: lines)
    }
    // Labels often set the name in capitals: "TIRE KICKER" reads better as
    // "Tire Kicker".
    let name = (label.name ?? label.headline).map { $0 == $0.uppercased() ? $0.capitalized : $0 }
    return Result(name: name, roaster: label.roaster, label: label,
                  text: lines.map(\.text).joined(separator: "\n"))
  }

  static func read(_ lines: [LabelLine]) async throws -> ModelReading {
    let session = LanguageModelSession(instructions: """
      You read text recognized from photos of coffee bags. Copy answers word for word from the text. \
      Never invent anything; leave a field empty when the text doesn't say.
      """)
    let biggest = lines.sorted { $0.height > $1.height }.prefix(3).map(\.text)
    let prompt = """
      Text on the bag, top to bottom:
      \(lines.map(\.text).joined(separator: "\n"))

      The largest text: \(biggest.joined(separator: " / ")).
      Fill in what this bag says about its coffee.
      """
    let r = try await session.respond(to: prompt, generating: BagReading.self).content
    var reading = ModelReading()
    reading.name = r.name; reading.roaster = r.roaster; reading.origin = r.origin
    reading.process = r.process; reading.variety = r.variety; reading.altitude = r.altitude
    reading.roastDate = r.roastDate; reading.roastLevel = r.roastLevel; reading.tastingNotes = r.tastingNotes
    return reading
  }
}
