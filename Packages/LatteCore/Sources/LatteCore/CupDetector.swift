import Foundation

/// Finds the coffee surface in a photo and fits an ellipse to it.
///
/// Crema is a distinctive saturated orange-brown, unlike countertops (low
/// chroma), the cup rim (dark), and most backgrounds. The detector fills the
/// holes in each connected crema region (the foam pattern and glare sit inside
/// it), keeps the region that best looks like a coffee surface, and fits an
/// ellipse to its moments, so cups
/// photographed at an angle come out as ellipses rather than circles.
public enum CupDetector {
  public struct Result: Sendable {
    public var ellipse: Ellipse
    /// Filled surface mask (1 = inside the coffee surface), image-sized.
    public var surface: [UInt8]
    /// Fraction of the filled region that is crema rather than foam or glare.
    public var cremaFraction: Double
  }

  public enum Failure: Error, Equatable { case noCoffeeFound }

  /// Semi-minor / semi-major. Real cups measure 0.92–0.98; 0.5 allows a
  /// photo taken about 60° off vertical.
  static let minAspectRatio = 0.5
  /// Filled region / fitted ellipse area. Real cups measure 1.0.
  static let minSolidity = 0.85

  public static func detect(_ lab: LabImage) throws -> Result {
    let w = lab.width, h = lab.height, count = w * h
    var crema = [UInt8](repeating: 0, count: count)
    for i in 0..<count where isCrema(l: lab.l[i], a: lab.a[i], b: lab.b[i]) { crema[i] = 1 }

    // Other brown things (wood, leather, a second drink) can be large too, so
    // score every sizeable region on how much it looks like a coffee surface.
    var best: (score: Double, result: Result)?
    for component in components(crema, width: w, height: h, minSize: count / 50) {
      let filled = fillHoles(component.mask, width: w, height: h)
      let fit = fitEllipse(filled, width: w, height: h)
      let ellipseArea = Double.pi * fit.ellipse.semiMajor * fit.ellipse.semiMinor
      // A filled ellipse covers its moment-fitted ellipse almost exactly.
      let solidity = min(1, fit.count / ellipseArea)
      // A cup seen from above is round, or a mildly squashed ellipse at an
      // angle. Long bands (a sunset, a wooden shelf) and ragged shapes are not
      // coffee surfaces, so they are rejected rather than merely scored down.
      guard fit.ellipse.semiMinor / fit.ellipse.semiMajor >= minAspectRatio, solidity >= minSolidity else { continue }
      // Foam and glare punch holes in a real surface; a plain brown object has none.
      let holes = 1 - Double(component.size) / fit.count
      let pattern = holes > 0.03 ? 1.0 : 0.3
      let border = component.touchesBorder ? 0.25 : 1.0
      let score = fit.count * pow(solidity, 4) * pattern * border
      if score > (best?.score ?? 0) {
        best = (score, Result(ellipse: fit.ellipse, surface: filled, cremaFraction: Double(component.size) / fit.count))
      }
    }
    guard var best else { throw Failure.noCoffeeFound }
    // A tan stoneware rim or handle can pass as crema and join the coffee,
    // dragging the moment fit toward the handle. Most of the region's outline
    // is still the round rim, so fit the outline and ignore what strays.
    if let outline = fitOutline(best.result.surface, width: w, height: h) { best.result.ellipse = outline }
    return best.result
  }

  static func fitEllipse(_ mask: [UInt8], width w: Int, height h: Int) -> (ellipse: Ellipse, count: Double) {
    var sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0, n = 0.0
    for y in 0..<h {
      let fy = Double(y) + 0.5
      for x in 0..<w where mask[y * w + x] == 1 {
        let fx = Double(x) + 0.5
        sx += fx; sy += fy; sxx += fx * fx; syy += fy * fy; sxy += fx * fy; n += 1
      }
    }
    return (Ellipse.fromMoments(sumX: sx, sumY: sy, sumXX: sxx, sumYY: syy, sumXY: sxy, count: n), n)
  }

  /// Fits an ellipse to the outline of `mask` that most outline pixels lie
  /// on (RANSAC), so an attached handle or a smear of brown counter, which
  /// make up a minority of the outline, don't pull the fit. Nil if no ellipse
  /// explains enough of the outline.
  static func fitOutline(_ mask: [UInt8], width w: Int, height h: Int) -> Ellipse? {
    var points: [(x: Double, y: Double)] = []
    for y in 1..<(h - 1) {
      for x in 1..<(w - 1) where mask[y * w + x] == 1 {
        let i = y * w + x
        if mask[i - 1] == 0 || mask[i + 1] == 0 || mask[i - w] == 0 || mask[i + w] == 0 {
          points.append((Double(x) + 0.5, Double(y) + 0.5))
        }
      }
    }
    guard points.count >= 40 else { return nil }
    // Center and scale the points so the conic fit is well conditioned.
    let mx = points.map(\.x).reduce(0, +) / Double(points.count)
    let my = points.map(\.y).reduce(0, +) / Double(points.count)
    let scale = (points.map { ($0.x - mx) * ($0.x - mx) + ($0.y - my) * ($0.y - my) }.reduce(0, +) / Double(points.count)).squareRoot()
    guard scale > 0 else { return nil }
    let unit = points.map { (x: ($0.x - mx) / scale, y: ($0.y - my) / scale) }
    let tolerance = max(2, 0.008 * Double(max(w, h))) / scale

    func inliers(_ q: Conic) -> [Int] {
      unit.indices.filter { q.distance(unit[$0].x, unit[$0].y) < tolerance }
    }
    func isCupLike(_ q: Conic) -> Bool {
      guard let e = q.ellipse else { return false }
      return e.semiMinor / e.semiMajor >= minAspectRatio && e.semiMajor < 2
    }

    var random = SplitMix(seed: 1)
    var best: [Int] = []
    for _ in 0..<300 {
      var sample: Set<Int> = []
      while sample.count < 5 { sample.insert(Int(random.next() % UInt64(unit.count))) }
      guard let q = Conic.fit(sample.map { unit[$0] }), isCupLike(q) else { continue }
      let found = inliers(q)
      if found.count > best.count { best = found }
    }
    // The rim must account for most of the outline.
    guard best.count >= unit.count * 2 / 5 else { return nil }
    var conic: Conic?
    for _ in 0..<2 {
      guard let q = Conic.fit(best.map { unit[$0] }), isCupLike(q) else { break }
      conic = q
      best = inliers(q)
    }
    guard let e = conic?.ellipse else { return nil }
    // Outline pixel centers sit half a pixel inside the region's edge.
    return Ellipse(centerX: mx + e.centerX * scale, centerY: my + e.centerY * scale,
                   semiMajor: e.semiMajor * scale + 0.5, semiMinor: e.semiMinor * scale + 0.5, angle: e.angle)
  }

  /// `a·x² + b·xy + c·y² + d·x + e·y + f = 0`, normalized so `a + c = 1`.
  struct Conic {
    var a, b, c, d, e, f: Double

    /// Least-squares fit (exact for five points).
    static func fit(_ points: [(x: Double, y: Double)]) -> Conic? {
      // With c = 1 - a: a(x² - y²) + b·xy + d·x + e·y + f = -y².
      var m = [[Double]](repeating: [Double](repeating: 0, count: 6), count: 5)
      for p in points {
        let row = [p.x * p.x - p.y * p.y, p.x * p.y, p.x, p.y, 1]
        let rhs = -p.y * p.y
        for i in 0..<5 {
          for j in 0..<5 { m[i][j] += row[i] * row[j] }
          m[i][5] += row[i] * rhs
        }
      }
      guard let s = solve(&m) else { return nil }
      return Conic(a: s[0], b: s[1], c: 1 - s[0], d: s[2], e: s[3], f: s[4])
    }

    /// Approximate geometric distance (Sampson): |Q| / |∇Q|.
    func distance(_ x: Double, _ y: Double) -> Double {
      let q = a * x * x + b * x * y + c * y * y + d * x + e * y + f
      let gx = 2 * a * x + b * y + d, gy = b * x + 2 * c * y + e
      return abs(q) / max(1e-9, (gx * gx + gy * gy).squareRoot())
    }

    var ellipse: Ellipse? {
      let det = 4 * a * c - b * b
      guard det > 0 else { return nil }
      let x0 = (b * e - 2 * c * d) / det, y0 = (b * d - 2 * a * e) / det
      let f0 = f + (d * x0 + e * y0) / 2
      let r = (((a - c) / 2) * ((a - c) / 2) + (b / 2) * (b / 2)).squareRoot()
      let small = (a + c) / 2 - r, large = (a + c) / 2 + r
      guard small * f0 < 0, large * f0 < 0 else { return nil }
      // The major axis follows the smaller eigenvalue.
      let v1 = (b / 2, small - a), v2 = (small - c, b / 2)
      let v = hypot(v1.0, v1.1) >= hypot(v2.0, v2.1) ? v1 : v2
      let angle = r < 1e-12 ? 0 : atan2(v.1, v.0)
      return Ellipse(centerX: x0, centerY: y0, semiMajor: (-f0 / small).squareRoot(),
                     semiMinor: (-f0 / large).squareRoot(), angle: angle)
    }

    /// Gaussian elimination with partial pivoting on an augmented n×(n+1) matrix.
    private static func solve(_ m: inout [[Double]]) -> [Double]? {
      let n = m.count
      for col in 0..<n {
        guard let pivot = (col..<n).max(by: { abs(m[$0][col]) < abs(m[$1][col]) }), abs(m[pivot][col]) > 1e-12 else { return nil }
        m.swapAt(col, pivot)
        for row in (col + 1)..<n {
          let k = m[row][col] / m[col][col]
          for j in col...n { m[row][j] -= k * m[col][j] }
        }
      }
      var x = [Double](repeating: 0, count: n)
      for row in stride(from: n - 1, through: 0, by: -1) {
        var sum = m[row][n]
        for j in (row + 1)..<n { sum -= m[row][j] * x[j] }
        x[row] = sum / m[row][row]
      }
      return x
    }
  }

  /// Small deterministic generator, so a photo always gets the same fit.
  struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z >> 31)
    }
  }

  @inline(__always) static func isCrema(l: Float, a: Float, b: Float) -> Bool {
    let chroma = (a * a + b * b).squareRoot()
    guard chroma > 18, l > 25, l < 85 else { return false }
    let hue = atan2(b, a) * 180 / .pi
    return hue > 40 && hue < 85
  }

  struct Component {
    var mask: [UInt8]
    var size: Int
    var touchesBorder: Bool
  }

  /// 4-connected regions of `mask` with at least `minSize` pixels.
  static func components(_ mask: [UInt8], width w: Int, height h: Int, minSize: Int) -> [Component] {
    var labels = [Int32](repeating: 0, count: w * h)
    var stack: [Int] = []
    var found: [(label: Int32, size: Int, border: Bool)] = []
    var next: Int32 = 0
    for start in 0..<(w * h) where mask[start] == 1 && labels[start] == 0 {
      next += 1
      labels[start] = next
      stack.append(start)
      var size = 0, border = false
      while let p = stack.popLast() {
        size += 1
        let x = p % w, y = p / w
        if x == 0 || y == 0 || x == w - 1 || y == h - 1 { border = true }
        if x > 0, mask[p - 1] == 1, labels[p - 1] == 0 { labels[p - 1] = next; stack.append(p - 1) }
        if x < w - 1, mask[p + 1] == 1, labels[p + 1] == 0 { labels[p + 1] = next; stack.append(p + 1) }
        if y > 0, mask[p - w] == 1, labels[p - w] == 0 { labels[p - w] = next; stack.append(p - w) }
        if y < h - 1, mask[p + w] == 1, labels[p + w] == 0 { labels[p + w] = next; stack.append(p + w) }
      }
      if size >= minSize { found.append((next, size, border)) }
    }
    return found.map { f in
      Component(mask: labels.map { $0 == f.label ? 1 : 0 }, size: f.size, touchesBorder: f.border)
    }
  }

  /// Marks everything not reachable from the border without crossing the mask.
  static func fillHoles(_ mask: [UInt8], width w: Int, height h: Int) -> [UInt8] {
    var outside = [UInt8](repeating: 0, count: w * h)
    var stack: [Int] = []
    func seed(_ p: Int) { if mask[p] == 0 && outside[p] == 0 { outside[p] = 1; stack.append(p) } }
    for x in 0..<w { seed(x); seed((h - 1) * w + x) }
    for y in 0..<h { seed(y * w); seed(y * w + w - 1) }
    while let p = stack.popLast() {
      let x = p % w, y = p / w
      if x > 0 { seed(p - 1) }
      if x < w - 1 { seed(p + 1) }
      if y > 0 { seed(p - w) }
      if y < h - 1 { seed(p + w) }
    }
    return outside.map { 1 - $0 }
  }
}
