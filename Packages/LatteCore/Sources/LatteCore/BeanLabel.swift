import Foundation

/// What a coffee bag's label says, as far as fixed rules can tell from the
/// recognized text. Name and roaster are only filled in when the label says
/// so plainly ("Huckleberry Roasters", "Civitas Blend"); otherwise they're
/// left to the language model (or the user), since a label's biggest words
/// could be either. Anything not found is nil.
public struct BeanLabel: Sendable, Equatable {
  public enum RoastLevel: String, CaseIterable, Sendable, Codable, Identifiable {
    case light, medium, mediumDark, dark
    public var id: String { rawValue }
    public var displayName: String {
      switch self {
      case .light: "Light"
      case .medium: "Medium"
      case .mediumDark: "Medium-dark"
      case .dark: "Dark"
      }
    }
  }

  public var origin: String?
  public var process: String?
  public var variety: String?
  /// Meters above sea level, e.g. "1,900–2,100 m".
  public var altitude: String?
  public var roastDate: Date?
  public var roastLevel: RoastLevel?
  /// True when the roast level wasn't printed and was guessed from the
  /// tasting notes.
  public var roastLevelIsGuess = false
  public var tastingNotes: [String] = []
  /// The largest line of text, a starting point for the name.
  public var headline: String?
  /// A name the label spells out as one, such as "Civitas Blend".
  public var name: String?
  /// A line naming the roaster, such as "Huckleberry Roasters".
  public var roaster: String?

  public init() {}
}

/// One line of recognized text, with its height as a fraction of the image
/// (bigger text is more likely the coffee's name or the roaster).
public struct LabelLine: Sendable, Equatable {
  public var text: String
  public var height: Double
  /// Left edge as a fraction of the image width, when known.
  public var left: Double?
  public init(_ text: String, height: Double = 0, left: Double? = nil) {
    self.text = text
    self.height = height
    self.left = left
  }
}

public enum BeanLabelParser {
  public static func parse(_ lines: [LabelLine], today: Date = .now, calendar: Calendar = .current) -> BeanLabel {
    var label = BeanLabel()
    let texts = lines.map(\.text)
    let joined = texts.joined(separator: "\n")
    let lower = joined.lowercased()

    label.name = blendName(in: lines)
    label.roaster = roaster(in: texts) ?? brandMark(in: lines)
    // The biggest text that isn't the roaster's mark.
    label.headline = lines.filter { line in
      line.text.count >= 3 && !line.text.contains(where: \.isNumber)
        && label.roaster.map { squash($0).contains(squash(line.text)) } != true
    }.max { $0.height < $1.height }?.text
    label.roastDate = roastDate(in: texts, today: today, calendar: calendar)
    // Every origin, in the order printed ("Oaxaca, Mexico / Churupampa, Peru").
    label.origin = origins.filter { lower.contains($0.lowercased()) }
      .sorted { lower.range(of: $0.lowercased())!.lowerBound < lower.range(of: $1.lowercased())!.lowerBound }
      .joined(separator: ", ").nilIfEmpty
    label.process = processes.first { lower.contains($0.match) }?.name
    label.variety = varieties(in: lower)
    label.altitude = altitude(in: joined)
    label.tastingNotes = tastingNotes(in: texts)

    if let printed = printedRoastLevel(lower) ?? texts.lazy.compactMap({ roastLevelAlone($0) }).first {
      label.roastLevel = printed
    } else if let guess = guessRoastLevel(from: label.tastingNotes) {
      label.roastLevel = guess
      label.roastLevelIsGuess = true
    }
    return label
  }

  // MARK: Name and roaster

  /// "Civitas Blend", printed on one line or, as text recognition often
  /// returns it, as "Civitas" over "Blend", sometimes with a badge ("Trade")
  /// read in between. Sentences that mention a blend don't count.
  static func blendName(in lines: [LabelLine]) -> String? {
    func words(_ s: String) -> [Substring] { s.split(separator: " ") }
    func isTitle(_ s: String) -> Bool { (1...4).contains(words(s).count) && !s.contains(where: \.isNumber) }
    for (i, line) in lines.enumerated() {
      let text = line.text.trimmingCharacters(in: .whitespaces)
      guard let last = words(text).last, last.lowercased() == "blend", isTitle(text) else { continue }
      if words(text).count > 1 { return text }
      // "Blend" alone: the first word is one of the two lines above, set
      // flush with it, or failing that the one closest in size. A badge sits
      // off to one side and is set smaller. Ties go to the nearer line.
      let candidates = lines[max(0, i - 2)..<i].reversed().filter { isTitle($0.text) && words($0.text).count <= 2 }
      let first = candidates.min { a, b in
        if let l = line.left, let la = a.left, let lb = b.left { return abs(la - l) < abs(lb - l) }
        return abs(a.height - line.height) < abs(b.height - line.height)
      }
      if let first { return first.text + " " + text }
    }
    return nil
  }

  /// The first line naming a roaster ("Huckleberry Roasters", "Onyx Coffee
  /// Roastery"), not a sentence that mentions roasting. Text recognition
  /// may split the name over two lines or tack a stray letter on the end.
  static func roaster(in texts: [String]) -> String? {
    let pattern = /^(.*?\b(?:roasters?|roastery|roasting co\.?|roasting company|coffee co\.?|coffee company))\b(.{0,3})$/.ignoresCase()
    func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
    for (i, text) in texts.enumerated() {
      guard let m = clean(text).firstMatch(of: pattern) else { continue }
      var name = String(m.1)
      // "ROASTERS" alone: the name is on the line above.
      if name.split(separator: " ").count == 1, i > 0 { name = clean(texts[i - 1]) + " " + name }
      guard (2...5).contains(name.split(separator: " ").count), !name.contains(where: \.isNumber) else { continue }
      // Labels set the roaster in capitals; "HUCKLEBERRY ROASTERS" reads
      // better as "Huckleberry Roasters".
      return name == name.uppercased() ? name.capitalized : name
    }
    return nil
  }

  /// A big brand mark naming the roaster, such as "MOTORING" over "COFFEE"
  /// or "SEY COFFEE": one or two words and "Coffee", among the largest text
  /// on the bag. Smaller lines ("A bag of tasty coffee") don't count.
  static func brandMark(in lines: [LabelLine]) -> String? {
    guard let biggest = lines.map(\.height).max(), biggest > 0 else { return nil }
    func words(_ s: String) -> [Substring] { s.split(separator: " ") }
    for (i, line) in lines.enumerated() where line.height >= 0.6 * biggest {
      let text = line.text.trimmingCharacters(in: .whitespaces)
      guard words(text).last?.lowercased() == "coffee", !text.contains(where: \.isNumber) else { continue }
      var name = text
      // "COFFEE" alone: the name is the line above, set as big.
      if words(text).count == 1 {
        guard i > 0, (1...2).contains(words(lines[i - 1].text).count), lines[i - 1].height >= 0.6 * line.height,
              !lines[i - 1].text.contains(where: \.isNumber) else { continue }
        name = lines[i - 1].text + " " + text
      }
      guard (2...3).contains(words(name).count) else { continue }
      return name == name.uppercased() ? name.capitalized : name
    }
    return nil
  }

  // MARK: Roast date

  /// A date on a line that mentions roasting, else any plausible date: not in
  /// the future and within the last six months.
  static func roastDate(in texts: [String], today: Date, calendar: Calendar) -> Date? {
    let earliest = calendar.date(byAdding: .day, value: -183, to: today)!
    let latest = calendar.date(byAdding: .day, value: 1, to: today)!
    func plausible(_ d: Date) -> Bool { d >= earliest && d <= latest }
    let roastLines = texts.enumerated().filter { $0.element.lowercased().contains("roast") }
    // The date may sit on the line after "Roasted on".
    let nearRoast = roastLines.flatMap { [texts[$0.offset]] + ($0.offset + 1 < texts.count ? [texts[$0.offset + 1]] : []) }
    for text in nearRoast { if let d = dates(in: text, calendar: calendar).first(where: plausible) { return d } }
    for text in texts { if let d = dates(in: text, calendar: calendar).first(where: plausible) { return d } }
    return nil
  }

  static func dates(in text: String, calendar: Calendar) -> [Date] {
    var found: [Date] = []
    // ISO-like 2025-10-28 / 2025.10.28 / 2025/10/28, which the detector can miss.
    let iso = /(20\d{2})[.\-\/](\d{1,2})[.\-\/](\d{1,2})/
    for m in text.matches(of: iso) {
      if let y = Int(m.1), let mo = Int(m.2), let d = Int(m.3),
         let date = calendar.date(from: DateComponents(year: y, month: mo, day: d)) {
        found.append(date)
      }
    }
    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
      let range = NSRange(text.startIndex..., in: text)
      for match in detector.matches(in: text, range: range) {
        // The detector answers with a time in the system time zone; keep
        // only the calendar day it read.
        guard let date = match.date else { continue }
        let day = Calendar.current.dateComponents(in: match.timeZone ?? .current, from: date)
        if let normalized = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day)) {
          found.append(normalized)
        }
      }
    }
    return found
  }

  // MARK: Origin, process, variety, altitude

  static let origins = [
    "Ethiopia", "Kenya", "Colombia", "Brazil", "Guatemala", "Costa Rica", "Honduras", "El Salvador", "Nicaragua",
    "Panama", "Peru", "Bolivia", "Ecuador", "Mexico", "Rwanda", "Burundi", "Uganda", "Tanzania", "Yemen",
    "Sumatra", "Indonesia", "Papua New Guinea", "India", "Myanmar", "Yunnan", "China", "Congo", "Malawi",
    "Zambia", "Jamaica", "Hawaii", "Vietnam", "Taiwan", "Thailand", "Laos", "Timor",
  ]

  static let processes: [(match: String, name: String)] = [
    ("carbonic maceration", "Carbonic maceration"), ("anaerobic", "Anaerobic"), ("wet hulled", "Wet-hulled"),
    ("wet-hulled", "Wet-hulled"), ("pulped natural", "Pulped natural"), ("semi-washed", "Semi-washed"),
    ("black honey", "Black honey"), ("red honey", "Red honey"), ("yellow honey", "Yellow honey"),
    ("white honey", "White honey"), ("honey", "Honey"), ("natural", "Natural"), ("washed", "Washed"),
  ]

  static let varieties = [
    "Gesha", "Geisha", "Pink Bourbon", "Bourbon", "Typica", "Caturra", "Catuai", "Catuaí", "SL28", "SL34",
    "Heirloom", "Landrace", "Pacamara", "Castillo", "Ruiru", "Batian", "Mundo Novo", "Sidra", "Java",
    "74110", "74112", "Maragogype", "Villa Sarchi", "Wush Wush", "Catimor", "Red Bourbon", "Yellow Bourbon",
  ]

  /// Varieties in the order printed, dropping ones contained in a longer
  /// match ("Bourbon" inside "Yellow Bourbon").
  static func varieties(in lower: String) -> String? {
    let hits = varieties.filter { lower.contains($0.lowercased()) }
    let kept = hits.filter { hit in !hits.contains { $0 != hit && $0.lowercased().contains(hit.lowercased()) } }
    return kept.sorted { lower.range(of: $0.lowercased())!.lowerBound < lower.range(of: $1.lowercased())!.lowerBound }
      .joined(separator: ", ").nilIfEmpty
  }

  static func altitude(in text: String) -> String? {
    let pattern = /(\d{1,2}[,.]?\d{3})(?:\s*(?:-|–|to)\s*(\d{1,2}[,.]?\d{3}))?\s*(?:m\.?a\.?s\.?l\.?|masl|meters|metres|m\b)/
      .ignoresCase()
    guard let m = text.firstMatch(of: pattern) else { return nil }
    func clean(_ s: Substring) -> String { s.replacingOccurrences(of: ".", with: ",") }
    if let high = m.2 { return "\(clean(m.1))–\(clean(high)) m" }
    return "\(clean(m.1)) m"
  }

  // MARK: Tasting notes and roast level

  /// Flavor words common on specialty labels, with whether they suggest a
  /// lighter (+1) or darker (−1) roast. Neutral words count as notes only.
  static let flavors: [String: Int] = [
    "jasmine": 2, "floral": 2, "bergamot": 2, "hibiscus": 2, "rose": 1, "lavender": 2, "tea": 1, "black tea": 1,
    "lemon": 2, "lime": 2, "citrus": 2, "grapefruit": 2, "orange": 1, "orange peel": 1, "tangerine": 1, "mandarin": 1, "yuzu": 2,
    "blueberry": 1, "strawberry": 1, "raspberry": 1, "blackberry": 1, "berry": 1, "cranberry": 1, "cherry": 1,
    "black currant": 1, "blackcurrant": 1, "grape": 1, "peach": 1, "apricot": 1, "stone fruit": 1, "nectarine": 1,
    "plum": 0, "mango": 1, "passion fruit": 1, "pineapple": 1, "tropical": 1, "papaya": 1, "lychee": 2,
    "apple": 1, "green apple": 1, "pear": 1, "melon": 1, "watermelon": 1, "kiwi": 1, "rhubarb": 1,
    "honey": 0, "honeysuckle": 2, "cane sugar": 0, "panela": 0, "raisin": 0, "fig": 0, "date": 0, "red wine": 0,
    "wine": 0, "rum": 0, "vanilla": 0, "almond": 0, "hazelnut": -1, "nutty": -1, "peanut": -1, "walnut": -1,
    "pecan": -1, "milk chocolate": -1, "chocolate": -1, "cocoa": -1, "caramel": -1, "toffee": -1,
    "butterscotch": -1, "brown sugar": -1, "dark sugar": -1, "dark sugars": -1, "maple": -1, "dark chocolate": -2, "molasses": -2, "smoky": -2,
    "smoke": -2, "tobacco": -2, "cedar": -1, "spice": -1, "cinnamon": -1, "clove": -1, "licorice": -2,
    "earthy": -2, "malt": -1,
  ]

  static func tastingNotes(in texts: [String]) -> [String] {
    var notes: [String] = []
    // Lines about roasting ("Roasted on…", "Medium roast") aren't notes,
    // nor is a heading such as "BLEND DATE" or "Best before date".
    let dateHeading = /\b(?:blend|roast(?:ed)?|pack(?:ed)?|best(?: before| by)?|harvest|production|bag|crop)\s+date\b/.ignoresCase()
    for text in texts where !text.lowercased().contains("roast") && text.firstMatch(of: dateHeading) == nil
      && !(text == text.uppercased() && text.lowercased().contains("date")) {
      let line = text.lowercased()
      // Split descriptor lists: "Jasmine, peach & black tea" / "Cocoa · Cherry | Toffee".
      let parts = line.replacingOccurrences(of: " and ", with: ",").split(whereSeparator: { ",·|/&•+".contains($0) })
      for raw in parts {
        let part = raw.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
          .replacingOccurrences(of: "tasting notes", with: "").replacingOccurrences(of: "notes of", with: "")
          .replacingOccurrences(of: "notes", with: "").trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        // Prefer the longest flavor phrase in this part ("dark chocolate" over "chocolate").
        if let hit = flavors.keys.filter({ part == $0 || part.hasSuffix(" " + $0) || part.hasPrefix($0 + " ") })
          .max(by: { $0.count < $1.count }),
          // A process line ("honey process") isn't a tasting note.
          !(hit == "honey" && (line.contains("process") || line.contains("honey processed"))) {
          if !notes.contains(hit) { notes.append(hit) }
        }
      }
    }
    return notes
  }

  static func printedRoastLevel(_ lower: String) -> BeanLabel.RoastLevel? {
    if lower.contains("medium-dark") || lower.contains("medium dark") { return .mediumDark }
    if lower.contains("light roast") || lower.contains("light-roast") || lower.contains("roast: light") || lower.contains("roast level: light") { return .light }
    if lower.contains("medium roast") || lower.contains("roast: medium") || lower.contains("roast level: medium") { return .medium }
    if lower.contains("dark roast") || lower.contains("roast: dark") || lower.contains("roast level: dark") { return .dark }
    return nil
  }

  /// A roast level printed on its own, as in a label's header row ("MEDIUM").
  static func roastLevelAlone(_ text: String) -> BeanLabel.RoastLevel? {
    switch squash(text).replacingOccurrences(of: " roast ", with: " ") {
    case " light ": .light
    case " medium ": .medium
    case " medium dark ": .mediumDark
    case " dark ": .dark
    default: nil
    }
  }

  /// Bright fruit and florals point to lighter roasts; chocolate, molasses
  /// and smoke to darker ones.
  static func guessRoastLevel(from notes: [String]) -> BeanLabel.RoastLevel? {
    let weights = notes.compactMap { flavors[$0] }
    guard !weights.isEmpty else { return nil }
    let mean = Double(weights.reduce(0, +)) / Double(weights.count)
    switch mean {
    case 0.75...: return .light
    case -0.25..<0.75: return .medium
    case -1.25 ..< -0.25: return .mediumDark
    default: return .dark
    }
  }
}

extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
