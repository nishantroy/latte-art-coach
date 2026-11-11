import Foundation

/// The line a poured pattern is built along, and which way it points.
public struct PatternAxis: Sendable, Equatable {
  /// A point on the axis (grid coordinates, y down).
  public var originX: Double
  public var originY: Double
  /// Unit vector from the stem toward the tip.
  public var directionX: Double
  public var directionY: Double
  /// Fraction of foam that lands on foam when mirrored across the axis.
  public var mirrorOverlap: Double
  /// How clearly the stack edges point toward the stem, 0...1.
  public var directionConfidence: Double

  public var angleDegrees: Double { atan2(directionY, directionX) * 180 / .pi }

  /// Finds the pattern's mirror axis, then orients it stem → tip.
  ///
  /// The axis is a line through the foam with near-best mirror overlap,
  /// which stays on the spine even for wide or lopsided patterns. Among
  /// such lines, the one the stacks' chevrons agree on wins (see `orient`).
  public static func find(surface: CupSurface, mask: [UInt8]) -> PatternAxis? {
    let n = surface.size
    var points: [(x: Double, y: Double)] = []
    for y in 0..<n { for x in 0..<n where mask[y * n + x] == 1 { points.append((Double(x) + 0.5, Double(y) + 0.5)) } }
    guard points.count > 50 else { return nil }
    let mx = points.reduce(0) { $0 + $1.x } / Double(points.count)
    let my = points.reduce(0) { $0 + $1.y } / Double(points.count)

    func overlap(theta: Double, offset: Double) -> Double {
      let dx = cos(theta), dy = sin(theta)
      // Line passes through the centroid shifted `offset` along the normal.
      let ox = mx - dy * offset, oy = my + dx * offset
      var hits = 0
      let stride = max(1, points.count / 4000)
      var total = 0
      var i = 0
      while i < points.count {
        let p = points[i]
        let rx = p.x - ox, ry = p.y - oy
        let t = rx * dx + ry * dy, s = -rx * dy + ry * dx
        // Reflect: keep t, negate s.
        let qx = ox + t * dx + s * dy, qy = oy + t * dy - s * dx
        let ix = Int(qx), iy = Int(qy)
        if ix >= 0, iy >= 0, ix < n, iy < n, mask[iy * n + ix] == 1 { hits += 1 }
        total += 1
        i += stride
      }
      return Double(hits) / Double(total)
    }

    // Coarse scan of every angle. An oval outline mirrors well across both
    // its long and short axes, so every local peak close to the best one is
    // a candidate; the stacks inside decide between them (below).
    let coarse = (0..<90).map { overlap(theta: Double($0) * .pi / 90, offset: 0) }
    let top = coarse.max()!
    let peaks = (0..<90).filter { i in
      coarse[i] >= top - candidateMargin && coarse[i] >= coarse[(i + 89) % 90] && coarse[i] >= coarse[(i + 1) % 90]
    }

    let hull = ConvexHull.mask(points: points, size: n, shrink: 4)
    let white = (0..<(n * n)).map { i -> Float in
      surface.inside[i] == 1 ? FoamSegmenter.whiteness(l: surface.l[i], a: surface.a[i], b: surface.b[i]) : 0
    }
    var result: PatternAxis?
    for peak in peaks {
      var best = (theta: Double(peak) * .pi / 90, offset: 0.0, score: coarse[peak])
      // Refine the angle and let the axis slide sideways off the centroid.
      for dTheta in stride(from: -2.0, through: 2.0, by: 0.5) {
        for offset in stride(from: -12.0, through: 12.0, by: 2.0) {
          let theta = Double(peak) * .pi / 90 + dTheta * .pi / 180
          let score = overlap(theta: theta, offset: offset)
          if score > best.score { best = (theta, offset, score) }
        }
      }
      let axis = orient(theta: best.theta, origin: (mx - sin(best.theta) * best.offset, my + cos(best.theta) * best.offset),
                        overlap: best.score, hull: hull, white: white, size: n)
      if result.map({ axis.directionConfidence > $0.directionConfidence }) ?? true { result = axis }
    }
    return result
  }

  /// Mirror-overlap peaks within this much of the best are candidate axes.
  static let candidateMargin = 0.08

  /// Orients the line at `theta` through `origin` stem → tip.
  ///
  /// The crema lines between stacks curve into chevrons whose points face
  /// the stem (as stacks are pushed, each one wraps around the next). Edges
  /// inside the pattern's hull therefore move away from the spine as they
  /// move toward the tip, and the sign of that slope gives the direction.
  /// Across any other line the slopes cancel, so confidence is low.
  static func orient(theta: Double, origin: (x: Double, y: Double), overlap: Double,
                     hull: [UInt8], white: [Float], size n: Int) -> PatternAxis {
    var dx = cos(theta), dy = sin(theta)
    let ox = origin.x, oy = origin.y
    var slope = 0.0, weight = 0.0
    for y in 2..<(n - 2) {
      for x in 2..<(n - 2) where hull[y * n + x] == 1 {
        let i = y * n + x
        let gx = Double(white[i + 1] - white[i - 1]), gy = Double(white[i + n] - white[i - n])
        let g2 = gx * gx + gy * gy
        guard g2 > 400 else { continue }
        // Gradient in axis coordinates (t along axis, s across it).
        let gt = gx * dx + gy * dy, gs = -gx * dy + gy * dx
        let rx = Double(x) + 0.5 - ox, ry = Double(y) + 0.5 - oy
        let s = -rx * dy + ry * dx
        guard abs(s) > 4 else { continue }
        // Edge tangent is (−gs, gt) in (t, s); its slope d|s|/dt sign is
        // sign(s) · (−gs·gt)… expressed without dividing:
        slope += (s > 0 ? 1 : -1) * (-gt * gs) / g2.squareRoot()
        weight += g2.squareRoot()
      }
    }
    // Positive slope: edges spread from the spine toward +t, so +t is the tip.
    if slope < 0 { dx = -dx; dy = -dy }
    // Each term is at most half its edge strength, so 2·|slope|/weight is in 0...1.
    let confidence = weight > 0 ? min(1, 2 * abs(slope) / weight) : 0
    return PatternAxis(originX: ox, originY: oy, directionX: dx, directionY: dy,
                       mirrorOverlap: overlap, directionConfidence: confidence)
  }
}

enum ConvexHull {
  /// Rasterized convex hull of `points`, shrunk inward by `shrink` pixels.
  static func mask(points: [(x: Double, y: Double)], size n: Int, shrink: Double) -> [UInt8] {
    let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
    func cross(_ o: (x: Double, y: Double), _ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double {
      (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    }
    var lower: [(x: Double, y: Double)] = [], upper: [(x: Double, y: Double)] = []
    for p in sorted {
      while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
      lower.append(p)
    }
    for p in sorted.reversed() {
      while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
      upper.append(p)
    }
    let hull = Array(lower.dropLast() + upper.dropLast())
    var out = [UInt8](repeating: 0, count: n * n)
    guard hull.count >= 3 else { return out }
    // Counter-clockwise hull: inside means left of every edge by `shrink`.
    let edges = (0..<hull.count).map { i -> (nx: Double, ny: Double, c: Double) in
      let a = hull[i], b = hull[(i + 1) % hull.count]
      let len = hypot(b.x - a.x, b.y - a.y)
      let nx = -(b.y - a.y) / len, ny = (b.x - a.x) / len
      return (nx, ny, nx * a.x + ny * a.y)
    }
    for y in 0..<n {
      for x in 0..<n {
        let px = Double(x) + 0.5, py = Double(y) + 0.5
        if edges.allSatisfy({ $0.nx * px + $0.ny * py - $0.c >= shrink }) { out[y * n + x] = 1 }
      }
    }
    return out
  }
}
