import Foundation

/// A 0–100 score built only from measured geometry. Each component maps one
/// metric onto 0...1 with fixed, documented ranges; the overall score is a
/// weighted mean whose weights depend on the pattern. Nothing here is learned
/// or model-generated.
public struct PourScore: Sendable, Equatable {
  public enum Component: String, CaseIterable, Sendable {
    /// `definition` is the pattern's signature: a solid heart with a clean
    /// point, thick separate tulip stacks, or many fine rosetta leaves.
    case centering, symmetry, contrast, proportion, texture, definition

    /// Share of the overall score for `pattern`.
    public func weight(for pattern: Pattern) -> Double {
      switch (pattern, self) {
      case (_, .centering): pattern == .rosetta ? 0.15 : 0.20
      // A heart is judged mostly on its shape: a clean outline and symmetry.
      case (.heart, .symmetry): 0.20
      case (.tulip, .symmetry): 0.15
      case (.rosetta, .symmetry): 0.20
      case (_, .contrast): pattern == .tulip ? 0.20 : 0.15
      case (.heart, .proportion): 0.10
      case (_, .proportion): 0.15
      case (_, .texture): 0.10
      case (.heart, .definition): 0.25
      case (.tulip, .definition): 0.20
      case (.rosetta, .definition): 0.25
      }
    }
  }

  public let pattern: Pattern
  /// Each component in 0...1.
  public var components: [Component: Double]
  public var overall: Int

  public init(_ m: PourMetrics, pattern: Pattern) {
    self.pattern = pattern
    func ramp(_ value: Double, from bad: Double, to good: Double) -> Double {
      min(1, max(0, (value - bad) / (good - bad)))
    }
    var c: [Component: Double] = [:]
    // A pattern centered within 5% of the radius is perfect; 30% off is a miss.
    c[.centering] = ramp(m.centerOffset, from: 0.30, to: 0.05)
    // Silhouette mirror IoU; 0.6 is visibly lopsided, 0.9 is near-perfect.
    c[.symmetry] = ramp(m.symmetry, from: 0.60, to: 0.90)
    // Foam vs crema L*; 15 is muddy, 35 is crisp white on dark crema.
    c[.contrast] = ramp(m.contrast, from: 15, to: 35)
    // Bubbles and coarse foam on the crema; 4% rough pixels is very coarse.
    c[.texture] = ramp(m.surfaceRoughness, from: 0.04, to: 0.005)

    switch pattern {
    case .heart:
      // About half to two thirds of the diameter, and roughly as wide as long.
      let tooLong = ramp(m.length, from: 0.72, to: 0.88)
      let tooShort = ramp(m.length, from: 0.45, to: 0.30)
      let tooNarrow = ramp(m.width / max(m.length, 0.01), from: 0.80, to: 0.60)
      c[.proportion] = max(0, 1 - tooLong - tooShort - tooNarrow)
      // Two round lobes, a solid blob (no crema lines inside), and a clean
      // point. Thin crema lines barely dent the fill, so separate stacks
      // also count. Lobe ranges: clean drawn hearts ~0.01, the user's
      // flat-topped heart-01 0.038, a shield shape ~0.10.
      let solid = m.stackCount <= 1 ? 1.0 : m.stackCount == 2 ? 0.6 : 0.3
      c[.definition] = solid * (0.15 * ramp(m.fill, from: 0.75, to: 0.92)
        + 0.25 * ramp(m.tipTaper, from: 0.70, to: 0.35)
        + 0.60 * ramp(m.lobeRoundness, from: 0.07, to: 0.015))
    case .tulip:
      // About 60–78% of the diameter lengthwise and at least 45% across;
      // overlong, narrow patterns mean the pour drifted.
      let tooLong = ramp(m.length, from: 0.78, to: 0.93)
      let tooShort = ramp(m.length, from: 0.60, to: 0.45)
      let tooNarrow = ramp(m.width, from: 0.45, to: 0.30)
      c[.proportion] = max(0, 1 - tooLong - tooShort - tooNarrow)
      // Thick, rounded pushes rather than thin layers, and more than one of them.
      c[.definition] = ramp(m.stackThickness, from: 0.12, to: 0.25) * (m.stackCount >= 2 ? 1 : 0.4)
    case .rosetta:
      // A rosetta should run most of the way across the cup.
      let tooLong = ramp(m.length, from: 0.92, to: 0.99)
      let tooShort = ramp(m.length, from: 0.65, to: 0.45)
      let tooNarrow = ramp(m.width, from: 0.40, to: 0.25)
      c[.proportion] = max(0, 1 - tooLong - tooShort - tooNarrow)
      // Many leaves, each a thin layer.
      c[.definition] = 0.5 * ramp(Double(m.stackCount), from: 3, to: 7) + 0.5 * ramp(m.stackThickness, from: 0.22, to: 0.12)
    }
    components = c
    overall = Int((Component.allCases.reduce(0) { $0 + $1.weight(for: pattern) * c[$1]! } * 100).rounded())
  }
}
