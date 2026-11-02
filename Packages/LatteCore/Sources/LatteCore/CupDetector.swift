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
      // Foam and glare punch holes in a real surface; a plain brown object has none.
      let holes = 1 - Double(component.size) / fit.count
      let pattern = holes > 0.03 ? 1.0 : 0.3
      let border = component.touchesBorder ? 0.25 : 1.0
      let score = fit.count * pow(solidity, 4) * pattern * border
      if score > (best?.score ?? 0) {
        best = (score, Result(ellipse: fit.ellipse, surface: filled, cremaFraction: Double(component.size) / fit.count))
      }
    }
    guard let best else { throw Failure.noCoffeeFound }
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
