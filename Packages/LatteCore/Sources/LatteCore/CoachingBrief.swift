import Foundation

/// The facts handed to the on-device language model so it can write
/// coaching. Everything the model may say comes from here: the measured
/// score, what the measurements found (the rule-based tips), the user's
/// history and rating. The model words the advice; it never sees the photo
/// or produces the score.
public enum CoachingBrief {
  public static let instructions = """
    You are a friendly, expert latte art coach helping a home barista improve.
    Rules:
    - Use only the facts provided. Don't invent measurements or numbers, and don't describe things the facts don't mention.
    - The score was measured from the photo. Never change it, argue with it, or give a different score.
    - Give concrete pouring technique: pitcher height, flow rate, spout position and movement, timing, cup tilt, milk texture.
    - Speak directly to the barista as "you", never "the barista". Be encouraging but specific and brief. No emoji.
    """

  /// - Parameters:
  ///   - tips: the rule-based tips for this pour, which describe what the
  ///     measurements found in words.
  ///   - history: summary of the user's earlier pours of this pattern,
  ///     excluding this one.
  public static func prompt(
    pattern: Pattern, score: PourScore, tips: [CoachingTip], history: ProgressSummary?, rating: Int?,
    brew: BrewDetails? = nil, taste: DrinkTaste? = nil, dialIn: [DialInTip] = [], date: Date = .now
  ) -> String {
    var lines: [String] = []
    lines.append("Pattern the barista poured: \(pattern.noun).")
    lines.append("Score: \(score.overall) out of 100.")
    if let rating { lines.append("The barista rated this pour \(rating) out of 10 themselves.") }

    if let brew, !brew.isEmpty { lines += brewLines(brew, date: date) }
    if let taste, !taste.isEmpty { lines += tasteLines(taste) }
    if !dialIn.isEmpty {
      lines.append("")
      lines.append("Espresso dial-in advice from fixed rules (mention the most important one only if it affects the art):")
      for tip in dialIn { lines.append("- \(tip.title): \(tip.detail)") }
    }

    lines.append("")
    lines.append("Parts of the score (100 is perfect), the ones costing the most points first:")
    let parts = PourScore.Component.allCases.sorted {
      (1 - score.components[$0]!) * $0.weight(for: pattern) > (1 - score.components[$1]!) * $1.weight(for: pattern)
    }
    for component in parts {
      let value = Int((score.components[component]! * 100).rounded())
      let share = Int((component.weight(for: pattern) * 100).rounded())
      lines.append("- \(label(component, pattern)): \(value) (\(share)% of the score)")
    }

    lines.append("")
    lines.append("What the measurements found, most important first:")
    for tip in tips { lines.append("- \(tip.title): \(tip.detail)") }

    lines.append("")
    if let h = history {
      lines.append("History: the barista has poured \(h.pourCount) \(pattern.noun)\(h.pourCount == 1 ? "" : "s") before this one.")
      let recent = Int(h.recentAverageScore.rounded())
      if let earlier = h.earlierAverageScore {
        lines.append("Their last \(h.recentCount) averaged \(recent), compared with \(Int(earlier.rounded())) before that.")
      } else {
        lines.append("Their previous \(pattern.noun)\(h.recentCount == 1 ? "" : "s") averaged \(recent).")
      }
      let weak = h.trends.prefix(2).filter { $0.recent < 0.6 }
      if !weak.isEmpty {
        lines.append("Weakest areas lately: " + weak.map { "\(label($0.component, pattern)) (averaging \(Int(($0.recent * 100).rounded())))" }.joined(separator: ", ") + ".")
      }
      let improving = h.trends.filter { ($0.change ?? 0) >= 0.1 }.map { label($0.component, pattern) }
      let slipping = h.trends.filter { ($0.change ?? 0) <= -0.1 }.map { label($0.component, pattern) }
      if !improving.isEmpty { lines.append("Improving: \(improving.joined(separator: ", ")).") }
      if !slipping.isEmpty { lines.append("Getting worse: \(slipping.joined(separator: ", ")).") }
    } else {
      lines.append("History: this is the barista's first \(pattern.noun) in the app.")
    }

    lines.append("")
    lines.append("""
      Write coaching for their next pour: one sentence on the single thing to focus on, then up to three tips. \
      If the history shows a problem that keeps coming back, or something improving, mention it in the progress note; \
      otherwise leave the progress note empty.
      """)
    return lines.joined(separator: "\n")
  }

  /// The drink behind the pour, in plain words. Only logged facts appear.
  static func brewLines(_ brew: BrewDetails, date: Date) -> [String] {
    var lines = ["", "How the drink was made:"]
    if let shot = brew.shotSummary { lines.append("- Espresso shot: \(shot).") }
    if let milk = brew.milk { lines.append("- Milk: \(milk.displayName.lowercased()).") }
    if let name = brew.beanName {
      var beans = "- Beans: \(name)"
      if let roaster = brew.roaster { beans += " from \(roaster)" }
      let character = [brew.beanOrigin, brew.beanProcess?.lowercased(), brew.roastLevel.map { "\($0.displayName.lowercased()) roast" }]
        .compactMap { $0 }
      if !character.isEmpty { beans += " (\(character.joined(separator: ", ")))" }
      if !brew.tastingNotes.isEmpty { beans += ", tasting notes \(brew.tastingNotes.joined(separator: ", "))" }
      if let days = brew.daysOffRoast(on: date) { beans += ", roasted \(days) day\(days == 1 ? "" : "s") before this pour" }
      lines.append(beans + ".")
    } else if let days = brew.daysOffRoast(on: date) {
      lines.append("- Beans roasted \(days) day\(days == 1 ? "" : "s") before this pour.")
    }
    return lines.count > 2 ? lines : []
  }

  static func tasteLines(_ taste: DrinkTaste) -> [String] {
    var parts: [String] = []
    if let balance = taste.balance { parts.append("the espresso tasted \(balance.displayName.lowercased())") }
    if let rating = taste.rating { parts.append("they rated the drink \(rating) out of 5") }
    if !taste.notes.isEmpty { parts.append("they tasted \(taste.notes.joined(separator: ", "))") }
    return ["- Taste: " + parts.joined(separator: "; ") + "."]
  }

  static func label(_ component: PourScore.Component, _ pattern: Pattern) -> String {
    switch component {
    case .centering: "centering"
    case .symmetry: "symmetry"
    case .contrast: "contrast between foam and crema"
    case .proportion: "size"
    case .texture: "milk texture (bubbles)"
    case .definition:
      switch pattern {
      case .heart: "heart shape (round lobes, solid, clean point)"
      case .tulip: "tulip stacks (thick, separate pushes)"
      case .rosetta: "rosetta leaves (many, thin)"
      }
    }
  }
}
