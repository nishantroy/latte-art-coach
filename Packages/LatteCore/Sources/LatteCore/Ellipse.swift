import Foundation

/// An ellipse in image pixel coordinates. `angle` is the direction of the
/// major axis in radians, measured from +x toward +y (image y points down).
public struct Ellipse: Sendable, Equatable {
  public var centerX: Double
  public var centerY: Double
  public var semiMajor: Double
  public var semiMinor: Double
  public var angle: Double

  public init(centerX: Double, centerY: Double, semiMajor: Double, semiMinor: Double, angle: Double) {
    self.centerX = centerX
    self.centerY = centerY
    self.semiMajor = semiMajor
    self.semiMinor = semiMinor
    self.angle = angle
  }

  /// The ellipse whose second moments match those of a filled pixel region.
  /// For a solid ellipse the covariance eigenvalues are (a/2)² and (b/2)².
  static func fromMoments(sumX: Double, sumY: Double, sumXX: Double, sumYY: Double, sumXY: Double, count: Double) -> Ellipse {
    let mx = sumX / count, my = sumY / count
    let cxx = sumXX / count - mx * mx
    let cyy = sumYY / count - my * my
    let cxy = sumXY / count - mx * my
    let trace = cxx + cyy
    let diff = sqrt(max(0, (cxx - cyy) * (cxx - cyy) / 4 + cxy * cxy))
    let major = trace / 2 + diff, minor = max(0, trace / 2 - diff)
    let angle = 0.5 * atan2(2 * cxy, cxx - cyy)
    return Ellipse(centerX: mx, centerY: my, semiMajor: 2 * sqrt(major), semiMinor: 2 * sqrt(minor), angle: angle)
  }

  /// Maps a point in the unit disk (x, y in -1...1) onto the ellipse.
  public func point(unitX u: Double, unitY v: Double) -> (x: Double, y: Double) {
    let c = cos(angle), s = sin(angle)
    let px = u * semiMajor, py = v * semiMinor
    return (centerX + px * c - py * s, centerY + px * s + py * c)
  }

  public func scaled(by factor: Double) -> Ellipse {
    Ellipse(centerX: centerX * factor, centerY: centerY * factor,
            semiMajor: semiMajor * factor, semiMinor: semiMinor * factor, angle: angle)
  }
}
