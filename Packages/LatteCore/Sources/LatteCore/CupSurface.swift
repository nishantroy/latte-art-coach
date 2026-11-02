import Foundation

/// The coffee surface resampled onto a square grid where the cup is a circle.
///
/// The cup's ellipse is mapped to a circle with the symmetric transform
/// `R·diag(a, b)·Rᵀ`, which undoes the foreshortening of an angled photo
/// without rotating the content, so "up" in the grid is still "up" in the photo.
public struct CupSurface: Sendable {
  /// Grid side in pixels; the cup circle has radius `size / 2`.
  public let size: Int
  public var l: [Float]
  public var a: [Float]
  public var b: [Float]
  /// 1 where the pixel lies inside the analyzed part of the cup.
  public var inside: [UInt8]
  public let ellipse: Ellipse
  /// Fraction of the cup radius that is analyzed; the rim edge is excluded.
  public static let analyzedRadius: Double = 0.94

  public init(lab: LabImage, ellipse: Ellipse, size: Int = 256) {
    self.size = size
    self.ellipse = ellipse
    let count = size * size
    var l = [Float](repeating: 0, count: count)
    var a = [Float](repeating: 0, count: count)
    var b = [Float](repeating: 0, count: count)
    var inside = [UInt8](repeating: 0, count: count)
    let c = cos(ellipse.angle), s = sin(ellipse.angle)
    let ma = ellipse.semiMajor, mb = ellipse.semiMinor
    // M = R diag(a, b) Rᵀ maps the unit disk onto the ellipse.
    let m00 = ma * c * c + mb * s * s
    let m01 = (ma - mb) * c * s
    let m11 = ma * s * s + mb * c * c
    let half = Double(size) / 2
    let r2 = CupSurface.analyzedRadius * CupSurface.analyzedRadius
    for gy in 0..<size {
      let v = (Double(gy) + 0.5 - half) / half
      for gx in 0..<size {
        let u = (Double(gx) + 0.5 - half) / half
        let i = gy * size + gx
        let x = ellipse.centerX + m00 * u + m01 * v - 0.5
        let y = ellipse.centerY + m01 * u + m11 * v - 0.5
        guard let sample = lab.bilinear(x: x, y: y) else { continue }
        l[i] = sample.l; a[i] = sample.a; b[i] = sample.b
        if u * u + v * v <= r2 { inside[i] = 1 }
      }
    }
    self.l = l
    self.a = a
    self.b = b
    self.inside = inside
  }

  /// Maps a grid point back to source-image pixel coordinates.
  public func imagePoint(gridX gx: Double, gridY gy: Double) -> (x: Double, y: Double) {
    let half = Double(size) / 2
    let u = (gx - half) / half, v = (gy - half) / half
    let c = cos(ellipse.angle), s = sin(ellipse.angle)
    let ma = ellipse.semiMajor, mb = ellipse.semiMinor
    let m00 = ma * c * c + mb * s * s, m01 = (ma - mb) * c * s, m11 = ma * s * s + mb * c * c
    return (ellipse.centerX + m00 * u + m01 * v, ellipse.centerY + m01 * u + m11 * v)
  }
}

extension LabImage {
  func bilinear(x: Double, y: Double) -> (l: Float, a: Float, b: Float)? {
    guard x >= 0, y >= 0, x < Double(width - 1), y < Double(height - 1) else { return nil }
    let x0 = Int(x), y0 = Int(y)
    let fx = Float(x - Double(x0)), fy = Float(y - Double(y0))
    let i = y0 * width + x0
    func mix(_ p: [Float]) -> Float {
      let top = p[i] + (p[i + 1] - p[i]) * fx
      let bottom = p[i + width] + (p[i + width + 1] - p[i + width]) * fx
      return top + (bottom - top) * fy
    }
    return (mix(l), mix(a), mix(b))
  }
}
