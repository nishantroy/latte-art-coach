import Foundation

/// Separates white milk foam from crema on a normalized cup surface.
public enum FoamSegmenter {
  public struct Result: Sendable {
    /// 1 = foam, on the `CupSurface` grid.
    public var mask: [UInt8]
    /// Whiteness threshold chosen for this photo.
    public var threshold: Float
    /// Fraction of the analyzed cup area covered by foam.
    public var coverage: Double
  }

  /// Foam is light and nearly colorless; crema is darker and saturated.
  @inline(__always) static func whiteness(l: Float, a: Float, b: Float) -> Float {
    l - (a * a + b * b).squareRoot()
  }

  /// - Parameter bias: shifts the automatic threshold (positive = less foam).
  public static func segment(_ surface: CupSurface, bias: Float = 0) -> Result {
    let n = surface.size, count = n * n
    var score = [Float](repeating: 0, count: count)
    var values: [Float] = []
    values.reserveCapacity(count)
    for i in 0..<count where surface.inside[i] == 1 {
      score[i] = whiteness(l: surface.l[i], a: surface.a[i], b: surface.b[i])
      values.append(score[i])
    }
    let threshold = otsu(values) + bias
    var mask = [UInt8](repeating: 0, count: count)
    for i in 0..<count where surface.inside[i] == 1 && score[i] > threshold { mask[i] = 1 }

    // Opening removes bubble and glare speckles; then drop small islands,
    // which are glare spots or stray foam rather than the poured pattern.
    mask = Morphology.dilate(Morphology.erode(mask, size: n), size: n)
    let insideCount = surface.inside.reduce(0) { $0 + Int($1) }
    mask = Morphology.removeSmallComponents(mask, size: n, minPixels: max(8, insideCount / 300))
    mask = removeGlare(mask, surface: surface)
    let foam = mask.reduce(0) { $0 + Int($1) }
    return Result(mask: mask, threshold: threshold, coverage: Double(foam) / Double(max(1, insideCount)))
  }

  /// Mean speckle above which a foam region is a reflection, not milk.
  /// Poured foam measures 0.3–1.4 in the fixtures; glare on wet crema 3.8–8.2.
  static let glareSpeckle: Float = 2.5

  /// Drops regions that are glare on the crema rather than poured foam.
  /// Microfoam is smooth; a reflection on wet crema is bright but speckled
  /// with bubbles and ripples. Speckle is each pixel's L* distance from the
  /// mean of its 5×5 neighbors in the same region, so a region's crisp
  /// outline doesn't count against it.
  static func removeGlare(_ mask: [UInt8], surface: CupSurface) -> [UInt8] {
    let n = surface.size
    var out = mask
    for region in CupDetector.components(mask, width: n, height: n, minSize: 1) {
      var speckle: Float = 0, count = 0
      for y in 2..<(n - 2) {
        for x in 2..<(n - 2) where region.mask[y * n + x] == 1 {
          let i = y * n + x
          var sum: Float = 0, neighbors = 0
          for oy in -2...2 {
            for ox in -2...2 where region.mask[i + oy * n + ox] == 1 { sum += surface.l[i + oy * n + ox]; neighbors += 1 }
          }
          speckle += abs(surface.l[i] - sum / Float(neighbors)); count += 1
        }
      }
      if count > 0, speckle / Float(count) > glareSpeckle {
        for i in 0..<(n * n) where region.mask[i] == 1 { out[i] = 0 }
      }
    }
    return out
  }

  /// Otsu always splits the surface in two, even when there is no milk. Real
  /// foam is clearly lighter than the crema around it (26–32 L brighter in
  /// the fixtures; a weak, blended pour still clears 10), so a split without
  /// that difference is not latte art.
  public static func foamStandsOut(_ surface: CupSurface, mask: [UInt8], minLightness: Float = 10) -> Bool {
    var foam: [Float] = [], crema: [Float] = []
    for i in 0..<(surface.size * surface.size) where surface.inside[i] == 1 {
      if mask[i] == 1 { foam.append(surface.l[i]) } else { crema.append(surface.l[i]) }
    }
    guard !foam.isEmpty, !crema.isEmpty else { return false }
    func median(_ v: [Float]) -> Float { v.sorted()[v.count / 2] }
    return median(foam) - median(crema) >= minLightness
  }

  /// Otsu's threshold over a 256-bin histogram of the value range.
  static func otsu(_ values: [Float]) -> Float {
    guard let lo = values.min(), let hi = values.max(), hi > lo else { return values.first ?? 0 }
    let bins = 256
    var hist = [Double](repeating: 0, count: bins)
    let scale = Float(bins - 1) / (hi - lo)
    for v in values { hist[Int((v - lo) * scale)] += 1 }
    let total = Double(values.count)
    let sumAll = hist.enumerated().reduce(0.0) { $0 + Double($1.offset) * $1.element }
    var wB = 0.0, sumB = 0.0, best = 0.0, bestBin = 0
    for t in 0..<bins {
      wB += hist[t]
      if wB == 0 { continue }
      let wF = total - wB
      if wF == 0 { break }
      sumB += Double(t) * hist[t]
      let mB = sumB / wB, mF = (sumAll - sumB) / wF
      let between = wB * wF * (mB - mF) * (mB - mF)
      if between > best { best = between; bestBin = t }
    }
    return lo + (Float(bestBin) + 0.5) / scale
  }
}

enum Morphology {
  static func erode(_ m: [UInt8], size n: Int) -> [UInt8] { apply(m, size: n, keepIf: { $0 == 9 }) }
  static func dilate(_ m: [UInt8], size n: Int) -> [UInt8] { apply(m, size: n, keepIf: { $0 > 0 }) }

  private static func apply(_ m: [UInt8], size n: Int, keepIf: (Int) -> Bool) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: n * n)
    for y in 1..<(n - 1) {
      for x in 1..<(n - 1) {
        let i = y * n + x
        var sum = 0
        for dy in -1...1 { for dx in -1...1 { sum += Int(m[i + dy * n + dx]) } }
        if keepIf(sum) { out[i] = 1 }
      }
    }
    return out
  }

  static func removeSmallComponents(_ m: [UInt8], size n: Int, minPixels: Int) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: n * n)
    var seen = [Bool](repeating: false, count: n * n)
    var stack: [Int] = [], region: [Int] = []
    for start in 0..<(n * n) where m[start] == 1 && !seen[start] {
      seen[start] = true
      stack.append(start)
      region.removeAll(keepingCapacity: true)
      while let p = stack.popLast() {
        region.append(p)
        let x = p % n
        for q in [p - 1, p + 1, p - n, p + n] where q >= 0 && q < n * n && m[q] == 1 && !seen[q] {
          if (q == p - 1 && x == 0) || (q == p + 1 && x == n - 1) { continue }
          seen[q] = true
          stack.append(q)
        }
      }
      if region.count >= minPixels { for p in region { out[p] = 1 } }
    }
    return out
  }
}
