import Foundation

public struct CoachingTip: Sendable, Equatable, Identifiable {
  public var id: String { title }
  public var title: String
  public var detail: String
  /// The score component this tip addresses, if any.
  public var component: TulipScore.Component?
}

/// Rule-based coaching from measured metrics. This is the fallback when the
/// on-device language model isn't available, and the source of truth for
/// which problems matter most.
public enum Coach {
  /// Up to `limit` tips for the components that cost the most points.
  public static func tips(metrics m: TulipMetrics, score: TulipScore, offsetAlongAxis: Double, limit: Int = 2) -> [CoachingTip] {
    let losses = TulipScore.Component.allCases
      .map { ($0, (1 - score.components[$0]!) * $0.weight) }
      .filter { $0.1 > 0.02 }
      .sorted { $0.1 > $1.1 }
    var tips = losses.prefix(limit).map { tip(for: $0.0, metrics: m, offsetAlongAxis: offsetAlongAxis) }
    if tips.isEmpty {
      tips.append(CoachingTip(
        title: "That's a clean tulip",
        detail: "Centered, symmetric and well defined. Try adding one more stack while keeping each one this round.",
        component: nil))
    }
    return tips
  }

  static func tip(for component: TulipScore.Component, metrics m: TulipMetrics, offsetAlongAxis: Double) -> CoachingTip {
    switch component {
    case .centering:
      let detail = offsetAlongAxis > 0.05
        ? "The pattern sits toward the far side of the cup. Start your first push a little closer to you so the finished tulip lands in the middle."
        : offsetAlongAxis < -0.05
          ? "The pattern sits toward your side of the cup. Start the first push nearer the center, and let each push travel forward a bit more."
          : "The pattern drifts to one side. Keep the spout over the cup's center line from the first push to the pull-through."
      return CoachingTip(title: "Center the tulip", detail: detail, component: component)
    case .symmetry:
      return CoachingTip(
        title: "Even out the sides",
        detail: "One side of the tulip is fuller than the other. Keep the cup level, aim the spout straight down the middle, and push straight forward rather than at an angle.",
        component: component)
    case .contrast:
      return CoachingTip(
        title: "Make the white pop",
        detail: "The foam blends into the crema. Pour from higher while filling so the milk dives under, then bring the spout right down to the surface before the first push so the foam sits on top.",
        component: component)
    case .proportion:
      if m.width < 0.45 {
        return CoachingTip(
          title: "Push wider stacks",
          detail: "The stacks are narrow. Give each push a little more flow so it spreads sideways before you stop.",
          component: component)
      }
      return CoachingTip(
        title: m.length > 0.78 ? "Shorten the pattern" : "Make it bigger",
        detail: m.length > 0.78
          ? "The tulip runs nearly rim to rim. Start the first push closer to the center and keep each push short."
          : "The tulip is small for the cup. Start pushing a little earlier, while there's more room left in the cup.",
        component: component)
    case .texture:
      return CoachingTip(
        title: "Smoother milk",
        detail: "There are a lot of bubbles on the surface. Stretch the milk for less time, then tap and swirl the pitcher until it looks glossy before you pour.",
        component: component)
    case .stackDefinition:
      return CoachingTip(
        title: "Push, stop, push",
        detail: "Your stacks are thin, wavy layers, which is rosetta technique. For a tulip, push one blob of foam, stop the flow completely, then push the next blob into it.",
        component: component)
    }
  }
}
