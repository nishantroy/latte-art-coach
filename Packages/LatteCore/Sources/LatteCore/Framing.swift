import Foundation

/// Live guidance while framing a shot in the camera: is the cup there, big
/// enough, centered and seen from above? Runs the full analysis on a camera
/// frame, but only the geometry is used; the score isn't shown before the
/// user rates the pour.
public enum Framing: Sendable, Equatable {
  case noCup
  case noPattern
  case moveCloser
  case centerCup
  case holdFlatter
  case ready

  public var hint: String {
    switch self {
    case .noCup: "Point the camera down at the cup"
    case .noPattern: "Found the cup. Keep the foam in focus"
    case .moveCloser: "Move a little closer"
    case .centerCup: "Center the cup"
    case .holdFlatter: "Hold the phone flatter, right above the cup"
    case .ready: "Looks good. Take it"
    }
  }

  /// Cup diameter (major axis) as a fraction of the frame's shorter side.
  public static let minimumCupSize = 0.45
  /// Cup center's distance from the frame center, as a fraction of the shorter side.
  public static let maximumOffset = 0.15
  /// Minor/major axis: 1 is straight down.
  public static let minimumRoundness = 0.8

  public struct Check: Sendable {
    public var framing: Framing
    /// The cup, in the checked image's pixels, when found.
    public var cup: Ellipse?
    /// Foam tinted over the frame, when found.
    public var foamOverlay: RGBAImage?
  }

  public static func check(_ image: RGBAImage, pattern: Pattern) -> Check {
    let analysis: PourAnalysis
    do {
      analysis = try PourAnalysis.analyze(image: image, pattern: pattern)
    } catch .noPatternFound {
      return Check(framing: .noPattern, cup: try? CupDetector.detect(LabImage(image)).ellipse)
    } catch {
      return Check(framing: .noCup)
    }
    return Check(framing: framing(cup: analysis.cup, width: image.width, height: image.height),
                 cup: analysis.cup, foamOverlay: analysis.foamOverlay)
  }

  static func framing(cup: Ellipse, width: Int, height: Int) -> Framing {
    let side = Double(min(width, height))
    if cup.semiMajor * 2 < minimumCupSize * side { return .moveCloser }
    if hypot(cup.centerX - Double(width) / 2, cup.centerY - Double(height) / 2) > maximumOffset * side { return .centerCup }
    if cup.semiMinor / cup.semiMajor < minimumRoundness { return .holdFlatter }
    return .ready
  }
}
