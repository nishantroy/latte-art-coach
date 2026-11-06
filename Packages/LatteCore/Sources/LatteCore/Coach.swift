import Foundation

public struct CoachingTip: Sendable, Equatable, Identifiable {
  public var id: String { title }
  public var title: String
  public var detail: String
  /// The score component this tip addresses, if any.
  public var component: PourScore.Component?
}

/// Rule-based coaching from measured metrics. This is the fallback when the
/// on-device language model isn't available, and the source of truth for
/// which problems matter most.
public enum Coach {
  /// Up to `limit` tips for the components that cost the most points.
  public static func tips(metrics m: PourMetrics, score: PourScore, offsetAlongAxis: Double, limit: Int = 2) -> [CoachingTip] {
    let pattern = score.pattern
    let losses = PourScore.Component.allCases
      .map { ($0, (1 - score.components[$0]!) * $0.weight(for: pattern)) }
      .filter { $0.1 > 0.02 }
      .sorted { $0.1 > $1.1 }
    var tips = losses.prefix(limit).map { tip(for: $0.0, pattern: pattern, metrics: m, offsetAlongAxis: offsetAlongAxis) }
    if tips.isEmpty {
      tips.append(CoachingTip(title: "That's a clean \(pattern.noun)", detail: nextChallenge(pattern), component: nil))
    }
    return tips
  }

  static func nextChallenge(_ pattern: Pattern) -> String {
    switch pattern {
    case .heart: "Centered, symmetric and solid. Next, try a tulip: the same push, done two or three times."
    case .tulip: "Centered, symmetric and well defined. Try adding one more stack while keeping each one this round."
    case .rosetta: "Centered, symmetric, with fine leaves. Try fitting in a few more by wiggling faster as you move back."
    }
  }

  static func tip(for component: PourScore.Component, pattern: Pattern, metrics m: PourMetrics, offsetAlongAxis: Double) -> CoachingTip {
    let name = pattern.noun
    switch component {
    case .centering:
      let detail = offsetAlongAxis > 0.05
        ? "The pattern sits toward the far side of the cup. Start pouring the pattern a little closer to you so the finished \(name) lands in the middle."
        : offsetAlongAxis < -0.05
          ? "The pattern sits toward your side of the cup. Start the pattern nearer the center, and let it travel forward a bit more."
          : "The pattern drifts to one side. Keep the spout over the cup's center line from start to the pull-through."
      return CoachingTip(title: "Center the \(name)", detail: detail, component: component)
    case .symmetry:
      return CoachingTip(
        title: "Even out the sides",
        detail: "One side of the \(name) is fuller than the other. Keep the cup level, aim the spout straight down the middle, and pull through in a straight line.",
        component: component)
    case .contrast:
      return CoachingTip(
        title: "Make the white pop",
        detail: "The foam blends into the crema. Pour from higher while filling so the milk dives under, then bring the spout right down to the surface before you start the pattern so the foam sits on top.",
        component: component)
    case .proportion:
      return proportionTip(pattern: pattern, metrics: m)
    case .texture:
      return CoachingTip(
        title: "Smoother milk",
        detail: "There are a lot of bubbles on the surface. Stretch the milk for less time, then tap and swirl the pitcher until it looks glossy before you pour.",
        component: component)
    case .definition:
      return definitionTip(pattern: pattern, metrics: m)
    }
  }

  static func proportionTip(pattern: Pattern, metrics m: PourMetrics) -> CoachingTip {
    let name = pattern.noun
    switch pattern {
    case .heart where m.width < 0.8 * m.length:
      return CoachingTip(
        title: "Let the heart spread",
        detail: "The heart is narrow. Hold the spout still in one spot with a steady flow so the foam can spread sideways before you pull through.",
        component: .proportion)
    case .tulip where m.width < 0.45:
      return CoachingTip(
        title: "Push wider stacks",
        detail: "The stacks are narrow. Give each push a little more flow so it spreads sideways before you stop.",
        component: .proportion)
    case .rosetta where m.width < 0.40:
      return CoachingTip(
        title: "Wider wiggles",
        detail: "The leaves are narrow. Swing the pitcher a little further side to side so each leaf spreads wider.",
        component: .proportion)
    default:
      let tooLong = m.length > (pattern == .heart ? 0.72 : pattern == .tulip ? 0.78 : 0.92)
      return CoachingTip(
        title: tooLong ? "Shorten the pattern" : "Make it bigger",
        detail: tooLong
          ? "The \(name) runs nearly rim to rim. Start the pattern closer to the center and finish before you reach the near edge."
          : "The \(name) is small for the cup. Start the pattern a little earlier, while there's more room left in the cup.",
        component: .proportion)
    }
  }

  static func definitionTip(pattern: Pattern, metrics m: PourMetrics) -> CoachingTip {
    switch pattern {
    case .heart:
      if m.fill < 0.85 || m.stackCount > 1 {
        return CoachingTip(
          title: "One solid blob",
          detail: "There are crema lines inside the heart. Keep the spout low and in one spot with a steady flow, without wiggling, so the foam grows as one round blob.",
          component: .definition)
      }
      return CoachingTip(
        title: "Finish with a point",
        detail: "The bottom of the heart stays round. Lift the pitcher slightly and pull straight through the middle in one quick motion so it closes to a point.",
        component: .definition)
    case .tulip:
      if m.stackCount < 2 {
        return CoachingTip(
          title: "Add more stacks",
          detail: "This came out as a single blob. For a tulip, push a little foam, stop the flow, then push the next blob into it, two or three times before the pull-through.",
          component: .definition)
      }
      return CoachingTip(
        title: "Push, stop, push",
        detail: "Your stacks are thin, wavy layers, which is rosetta technique. For a tulip, push one blob of foam, stop the flow completely, then push the next blob into it.",
        component: .definition)
    case .rosetta:
      if m.stackThickness >= 0.17 {
        return CoachingTip(
          title: "Thinner leaves",
          detail: "The leaves are thick, more like tulip stacks. Keep the flow steady and wiggle the pitcher quickly with small side-to-side motions instead of pushing.",
          component: .definition)
      }
      return CoachingTip(
        title: "More leaves",
        detail: "There are only a few leaves. Start wiggling as soon as the foam appears and move the pitcher back slowly, so more leaves fit before you reach the edge.",
        component: .definition)
    }
  }
}
