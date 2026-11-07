import Foundation

/// One piece of espresso advice: what to change on the grinder or scale.
public struct DialInTip: Sendable, Equatable, Identifiable {
  public enum Kind: String, Sendable, CaseIterable {
    /// Shot time or taste says change the grind.
    case grind
    /// Yield against dose.
    case ratio
    /// Days off roast.
    case freshness
    /// What worked in the user's own earlier pours.
    case history
  }

  public var kind: Kind
  public var title: String
  public var detail: String
  public var id: String { kind.rawValue }

  public init(kind: Kind, title: String, detail: String) {
    self.kind = kind
    self.title = title
    self.detail = detail
  }
}

/// Dial-in rules: shot time, brew ratio and freshness against common
/// targets for the roast level, plus what the user's own pours of the same
/// beans show. Rules only; nothing here is a measurement of the photo.
public enum DialIn {
  /// A usual starting window for a milk drink's espresso.
  public struct Target: Sendable, Equatable {
    public var ratio: ClosedRange<Double>
    public var seconds: ClosedRange<Double>
  }

  public static func target(for roast: BeanLabel.RoastLevel?) -> Target {
    switch roast {
    case .light: Target(ratio: 2.0...2.5, seconds: 26...34)
    case .medium, nil: Target(ratio: 1.8...2.2, seconds: 25...32)
    case .mediumDark: Target(ratio: 1.7...2.1, seconds: 24...30)
    case .dark: Target(ratio: 1.5...2.0, seconds: 22...28)
    }
  }

  /// Beans younger than this are still gassy: big, pale, unstable crema.
  public static let restDays = 4
  /// Older than this and crema thins out, so art has less contrast.
  public static func staleDays(for roast: BeanLabel.RoastLevel?) -> Int {
    switch roast {
    case .light: 45
    case .medium, nil: 35
    case .mediumDark, .dark: 28
    }
  }

  /// - Parameters:
  ///   - brew: this pour's shot and beans.
  ///   - taste: how the drink tasted, if logged.
  ///   - contrast: this pour's contrast score (0...1), to tie the shot to the art.
  ///   - history: earlier pours, any pattern; only those with the same beans are used.
  public static func tips(brew: BrewDetails, taste: DrinkTaste.Balance? = nil, contrast: Double? = nil,
                          date: Date = .now, history: [PourRecord] = [], calendar: Calendar = .current) -> [DialInTip] {
    let target = target(for: brew.roastLevel)
    var tips: [DialInTip] = []
    let paleCrema = (contrast ?? 1) < 0.6
    let contrastNote = paleCrema ? " It also gives thin, pale crema, which is why the contrast came out low." : ""

    // Grind: taste first (it's the real signal), then the clock.
    let fast = brew.shotSeconds.map { $0 < target.seconds.lowerBound - 2 } ?? false
    let slow = brew.shotSeconds.map { $0 > target.seconds.upperBound + 2 } ?? false
    let time = brew.shotSeconds.map { "\(Int($0.rounded())) s" }
    let window = "\(Int(target.seconds.lowerBound))–\(Int(target.seconds.upperBound)) s"
    switch (taste, fast, slow) {
    case (.sour, true, _), (.weak, true, _):
      tips.append(DialInTip(kind: .grind, title: "Grind finer",
        detail: "\(taste == .sour ? "Sour" : "Weak") and fast (\(time!)) means under-extracted. Go a step or two finer and aim for \(window).\(contrastNote)"))
    case (.sour, false, _):
      tips.append(DialInTip(kind: .grind, title: "Extract a little more",
        detail: "Sour\(time.map { " at \($0)" } ?? "") means under-extracted. Grind slightly finer, or pull a bit more yield."))
    case (.bitter, _, true):
      tips.append(DialInTip(kind: .grind, title: "Grind coarser",
        detail: "Bitter and slow (\(time!)) means over-extracted. Go a step coarser and aim for \(window)."))
    case (.bitter, _, false):
      tips.append(DialInTip(kind: .grind, title: "Extract a little less",
        detail: "Bitter\(time.map { " at \($0)" } ?? "") means over-extracted. Grind slightly coarser, or stop the shot a little earlier."))
    case (.weak, false, _):
      tips.append(DialInTip(kind: .ratio, title: "Make it stronger",
        detail: "Weak under the milk: pull a shorter shot (less yield for the same dose) or dose a gram more."))
    case (_, true, _):
      tips.append(DialInTip(kind: .grind, title: "Grind finer",
        detail: "\(time!) is fast for \(roastName(brew.roastLevel)). Go finer to land in \(window).\(contrastNote)"))
    case (_, _, true):
      tips.append(DialInTip(kind: .grind, title: "Grind coarser",
        detail: "\(time!) is slow for \(roastName(brew.roastLevel)). Go coarser to land in \(window)."))
    default:
      break
    }

    // Ratio, unless the grind tip already covers it.
    if let ratio = brew.ratio, let dose = brew.doseGrams, !tips.contains(where: { $0.kind == .ratio }) {
      let low = dose * target.ratio.lowerBound, high = dose * target.ratio.upperBound
      let range = "\(Int(low.rounded()))–\(Int(high.rounded())) g"
      if ratio < target.ratio.lowerBound - 0.1 {
        tips.append(DialInTip(kind: .ratio, title: "Pull a longer shot",
          detail: "1:\(String(format: "%.1f", ratio)) is short for \(roastName(brew.roastLevel)). Aim for \(range) out from \(BrewDetails.grams(dose)) in."))
      } else if ratio > target.ratio.upperBound + 0.1 {
        tips.append(DialInTip(kind: .ratio, title: "Pull a shorter shot",
          detail: "1:\(String(format: "%.1f", ratio)) is long for \(roastName(brew.roastLevel)) and gets lost in milk. Aim for \(range) out from \(BrewDetails.grams(dose)) in."))
      }
    }

    if let days = brew.daysOffRoast(on: date, calendar: calendar) {
      if days < restDays {
        tips.append(DialInTip(kind: .freshness, title: "Let the beans rest",
          detail: "Roasted \(days) day\(days == 1 ? "" : "s") ago, they're still gassy: the crema comes out foamy and pale, so art has less contrast. They settle after about a week."))
      } else if days > staleDays(for: brew.roastLevel) {
        tips.append(DialInTip(kind: .freshness, title: "Beans are getting old",
          detail: "\(days) days off roast, the crema gets thinner and lighter, which makes art fade into it. Fresher beans give a darker canvas."))
      }
    }

    if let best = bestSettings(for: brew, in: history) { tips.append(best) }
    return tips
  }

  /// The grind setting that has worked best with these beans, when the
  /// user's pours show a clear difference and this pour isn't using it.
  public static func bestSettings(for brew: BrewDetails, in history: [PourRecord]) -> DialInTip? {
    guard let name = brew.beanName else { return nil }
    let roaster = brew.roaster
    let same: [PourRecord] = history.filter { record in
      guard let b = record.brew, b.grindSetting != nil else { return false }
      return b.beanName == name && b.roaster == roaster
    }
    let groups: [String: [PourRecord]] = Dictionary(grouping: same) { $0.brew!.grindSetting! }.filter { $0.value.count >= 2 }
    guard groups.count >= 2 else { return nil }
    func mean(_ v: [Double]) -> Double { v.reduce(0, +) / Double(v.count) }
    // Rank by how the drinks tasted when every group has ratings, else by art score.
    let tasted = groups.values.allSatisfy { $0.filter { $0.taste?.rating != nil }.count >= 2 }
    func value(_ pours: [PourRecord]) -> Double {
      tasted ? mean(pours.compactMap { $0.taste?.rating.map(Double.init) }) : mean(pours.map { Double($0.score) })
    }
    let ranked = groups.map { (grind: $0.key, value: value($0.value), count: $0.value.count) }
      .sorted { ($0.value, $1.grind) > ($1.value, $0.grind) }
    let best = ranked[0], next = ranked[1]
    guard best.grind != brew.grindSetting, best.value - next.value >= (tasted ? 0.5 : 5) else { return nil }
    let shots = same.filter { $0.brew!.grindSetting == best.grind }.compactMap { $0.brew?.shotSeconds }
    let shot = shots.isEmpty ? "" : ", around \(Int(mean(shots).rounded())) s"
    let measure = tasted
      ? "rated \(String(format: "%.1f", best.value))★ over \(best.count) drinks, vs \(String(format: "%.1f", next.value))★ at grind \(next.grind)"
      : "art averaged \(Int(best.value.rounded())) over \(best.count) pours, vs \(Int(next.value.rounded())) at grind \(next.grind)"
    return DialInTip(kind: .history, title: "Grind \(best.grind) worked best",
      detail: "With \(name), your shots at grind \(best.grind)\(shot) \(measure).")
  }

  static func roastName(_ roast: BeanLabel.RoastLevel?) -> String {
    roast.map { "a \($0.displayName.lowercased()) roast" } ?? "espresso"
  }
}
