import Foundation

/// What a language model read off a bag's text, field by field, as plain
/// strings (empty when it didn't say). The model only sees recognized text,
/// and a small model will sometimes answer with something plausible that
/// isn't on the bag, so `merge` keeps only answers it can check.
public struct ModelReading: Sendable, Equatable {
  public var name = "", roaster = "", origin = "", process = "", variety = "", altitude = ""
  public var roastDate = "", roastLevel = ""
  public var tastingNotes: [String] = []
  public init() {}
}

extension BeanLabelParser {
  /// Combines the rules' reading with the model's.
  ///
  /// - Text answers count only if they appear in the bag's text.
  /// - Exact formats (dates, altitudes) come from the rules first; the
  ///   model's must still parse and, for a date, be a plausible roast date.
  /// - A roast level printed on the bag wins; the model's reading of the
  ///   description beats a guess from the tasting notes, but is still a guess.
  /// - Tasting notes come from the model when it found any on the bag, since
  ///   it reads descriptions and skips badges; the rules' notes fill in.
  public static func merge(_ rules: BeanLabel, _ model: ModelReading, lines: [LabelLine],
                           today: Date = .now, calendar: Calendar = .current) -> BeanLabel {
    let bag = squash(lines.map(\.text).joined(separator: " "))
    func onBag(_ s: String) -> String? {
      let t = s.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
      return t.count >= 2 && bag.contains(squash(t)) ? t : nil
    }
    var label = rules
    label.roaster = rules.roaster ?? onBag(model.roaster)
    // A big brand mark ("HUCK" for Huckleberry Roasters) is the roaster,
    // not the coffee's name.
    let name = onBag(model.name).flatMap { name in
      label.roaster.map { $0.lowercased().contains(name.lowercased()) } == true ? nil : wholeTitle(name, in: lines)
    }
    label.name = rules.name ?? name
    // With no roaster printed, the model may offer the coffee's own name.
    if rules.roaster == nil, let roaster = label.roaster, let name = label.name ?? rules.headline,
       squash(name).contains(squash(roaster)) || squash(roaster).contains(squash(name)) {
      label.roaster = nil
    }
    label.origin = rules.origin ?? onBag(model.origin)
    label.process = rules.process ?? onBag(model.process).map(\.capitalizedFirst)
    label.variety = rules.variety ?? onBag(model.variety)
    label.altitude = rules.altitude ?? onBag(model.altitude).flatMap { altitude(in: $0) }
    if rules.roastDate == nil, let printed = onBag(model.roastDate) {
      label.roastDate = roastDate(in: [printed], today: today, calendar: calendar)
    }
    if rules.roastLevel == nil || rules.roastLevelIsGuess,
       let level = BeanLabel.RoastLevel(reading: model.roastLevel) {
      label.roastLevel = level
      label.roastLevelIsGuess = true
    }

    // Words from a date heading or the roast line aren't flavors, unless the
    // rules (which know a "Notes:" list) found them too.
    let notes = model.tastingNotes.compactMap { note -> String? in
      guard let t = onBag(note)?.lowercased(), t.split(separator: " ").count <= 3 else { return nil }
      let heading = ["date", "roast", "blend", "process", "origin", "notes"].contains { t.contains($0) }
      return heading && !rules.tastingNotes.contains(t) ? nil : t
    }
    var merged: [String] = []
    for note in notes + rules.tastingNotes where !merged.contains(where: { $0.contains(note) || note.contains($0) }) {
      merged.append(note)
    }
    label.tastingNotes = Array(merged.prefix(8))
    return label
  }

  /// The whole short line a name was taken from, when the model only kept
  /// part of it ("KICKER" from "TIRE KICKER").
  static func wholeTitle(_ name: String, in lines: [LabelLine]) -> String {
    let line = lines.map(\.text).first { text in
      squash(text).contains(squash(name)) && (1...4).contains(text.split(separator: " ").count)
        && !text.contains(where: \.isNumber)
    }
    return line ?? name
  }

  /// The known name `text` is a misreading of: within a couple of letters,
  /// ignoring case and punctuation. Nil when none is that close.
  public static func closest(_ text: String, among known: [String]) -> String? {
    let target = Array(squash(text))
    func distance(_ a: [Character], _ b: [Character]) -> Int {
      var row = Array(0...b.count)
      for (i, ca) in a.enumerated() {
        var next = [i + 1]
        for (j, cb) in b.enumerated() { next.append(min(row[j + 1] + 1, next[j] + 1, row[j] + (ca == cb ? 0 : 1))) }
        row = next
      }
      return row[b.count]
    }
    return known.map { ($0, distance(target, Array(squash($0)))) }
      .filter { $0.1 <= max(1, min(3, target.count / 6)) }
      .min { $0.1 < $1.1 }?.0
  }

  /// Lowercased with every run of spaces and punctuation as one space, so
  /// "Dark Sugars" matches "dark sugars • chocolate".
  static func squash(_ s: String) -> String {
    let parts = s.lowercased().split { !$0.isLetter && !$0.isNumber }
    return " " + parts.joined(separator: " ") + " "
  }
}

extension BeanLabel.RoastLevel {
  /// "medium-dark", "Medium Dark Roast", "light" and the like.
  init?(reading: String) {
    let s = BeanLabelParser.squash(reading)
    if s.contains(" medium dark ") { self = .mediumDark }
    else if s.contains(" light ") { self = .light }
    else if s.contains(" medium ") { self = .medium }
    else if s.contains(" dark ") { self = .dark }
    else { return nil }
  }
}

extension String {
  var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
