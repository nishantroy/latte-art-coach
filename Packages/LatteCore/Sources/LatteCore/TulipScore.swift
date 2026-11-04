import Foundation

/// A 0–100 score built only from measured geometry. Each component maps one
/// metric onto 0...1 with fixed, documented ranges; the overall score is a
/// weighted mean. Nothing here is learned or model-generated.
public struct TulipScore: Sendable, Equatable {
  public enum Component: String, CaseIterable, Sendable {
    case centering, symmetry, contrast, proportion, texture, stackDefinition

    /// Share of the overall score.
    public var weight: Double {
      switch self {
      case .centering: 0.20
      case .symmetry: 0.15
      case .contrast: 0.20
      case .proportion: 0.15
      case .texture: 0.10
      // Distinct, rounded stacks are what make a tulip a tulip.
      case .stackDefinition: 0.20
      }
    }
  }

  /// Each component in 0...1.
  public var components: [Component: Double]
  public var overall: Int

  public init(_ m: TulipMetrics) {
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
    // A tulip should fill about 60–78% of the diameter lengthwise and at
    // least 45% across; overlong, narrow patterns mean the pour drifted.
    let tooLong = ramp(m.length, from: 0.78, to: 0.93)
    let tooShort = ramp(m.length, from: 0.60, to: 0.45)
    let tooNarrow = ramp(m.width, from: 0.45, to: 0.30)
    c[.proportion] = max(0, 1 - tooLong - tooShort - tooNarrow)
    // Bubbles and coarse foam on the crema; 4% rough pixels is very coarse.
    c[.texture] = ramp(m.surfaceRoughness, from: 0.04, to: 0.005)
    // Tulip stacks should be thick, rounded pushes rather than thin layers.
    c[.stackDefinition] = ramp(m.stackThickness, from: 0.12, to: 0.25)
    components = c
    overall = Int((Component.allCases.reduce(0) { $0 + $1.weight * c[$1]! } * 100).rounded())
  }
}
