import Foundation

/// Raw measurements of a pour, for any pattern, all scale-free (fractions of the cup
/// radius or of the pattern) so photos of any size compare directly.
public struct PourMetrics: Sendable, Equatable {
  /// Distance from the pattern's center to the cup's center, / cup radius.
  public var centerOffset: Double
  /// Mirror overlap (intersection over union) of the pattern's silhouette.
  public var symmetry: Double
  /// Mirror overlap of the detailed foam mask, which also checks that the
  /// stacks on each side line up.
  public var detailSymmetry: Double
  /// Pattern length along the axis, / cup diameter.
  public var length: Double
  /// Pattern width across the axis, / cup diameter.
  public var width: Double
  /// Fraction of the cup covered by foam.
  public var coverage: Double
  /// Median L* of foam minus median L* of crema.
  public var contrast: Double
  /// Mean whiteness gradient on the foam outline, / contrast. Higher = crisper.
  public var edgeSharpness: Double
  /// Distinct foam stacks, counted on lines parallel to the spine.
  public var stackCount: Int
  /// Mean stack thickness along those lines, / cup radius. Tulip stacks are
  /// thick and rounded; thin layers mean the pitcher wiggled (rosetta-like).
  public var stackThickness: Double
  /// Length of the thin pull-through line beyond the base, / cup radius.
  public var stemLength: Double
  /// Foam area / silhouette area. A heart is one solid blob (near 1); crema
  /// lines between tulip stacks or rosetta leaves lower it.
  public var fill: Double
  /// Silhouette width over the 15% of the pattern nearest the stem, / its
  /// widest point. A heart that closes to a clean point is low (~0.3).
  public var tipTaper: Double
  /// Fraction of crema pixels that differ sharply from their neighborhood
  /// (bubbles and coarse microfoam).
  public var surfaceRoughness: Double
}

public enum PourMeasurer {
  /// The pattern's outline: gaps between stacks closed and holes filled.
  static func silhouette(_ mask: [UInt8], size n: Int) -> [UInt8] {
    var m = mask
    for _ in 0..<4 { m = Morphology.dilate(m, size: n) }
    for _ in 0..<4 { m = Morphology.erode(m, size: n) }
    return CupDetector.fillHoles(m, width: n, height: n)
  }

  /// Silhouette width along the axis, in 1-pixel steps from the stem end
  /// (`t` increasing toward the tip).
  static func widthProfile(_ silhouette: [UInt8], size n: Int, axis: PatternAxis) -> [Double] {
    let dx = axis.directionX, dy = axis.directionY
    var rows: [Int: (lo: Double, hi: Double)] = [:]
    for y in 0..<n {
      for x in 0..<n where silhouette[y * n + x] == 1 {
        let rx = Double(x) + 0.5 - axis.originX, ry = Double(y) + 0.5 - axis.originY
        let t = Int((rx * dx + ry * dy).rounded(.down)), s = -rx * dy + ry * dx
        let r = rows[t] ?? (s, s)
        rows[t] = (min(r.lo, s), max(r.hi, s))
      }
    }
    guard let lo = rows.keys.min(), let hi = rows.keys.max() else { return [] }
    return (lo...hi).map { t in rows[t].map { $0.hi - $0.lo + 1 } ?? 0 }
  }

  /// The axis of a heart: the line from its notch to its point.
  ///
  /// A heart is a round blob, so the plain mirror-overlap search can settle
  /// on a diagonal that fits almost as well, especially when one lobe is
  /// bigger. Along the true axis the heart is lopsided end to end: wide at
  /// the lobes and narrowing to a point where the pull-through exits. So each
  /// candidate line is scored on mirror overlap plus that end-to-end
  /// difference, and the narrow end becomes the stem.
  public static func heartAxis(mask: [UInt8], size n: Int) -> PatternAxis? {
    let sil = silhouette(mask, size: n)
    var points: [(x: Double, y: Double)] = []
    for y in 0..<n { for x in 0..<n where sil[y * n + x] == 1 { points.append((Double(x) + 0.5, Double(y) + 0.5)) } }
    guard points.count > 50 else { return nil }
    let mx = points.reduce(0) { $0 + $1.x } / Double(points.count)
    let my = points.reduce(0) { $0 + $1.y } / Double(points.count)

    func candidate(theta: Double, offset: Double) -> (score: Double, axis: PatternAxis) {
      let dx = cos(theta), dy = sin(theta)
      let ox = mx - dy * offset, oy = my + dx * offset
      var hits = 0
      for p in points {
        let rx = p.x - ox, ry = p.y - oy
        let t = rx * dx + ry * dy, s = -rx * dy + ry * dx
        let ix = Int(ox + t * dx + s * dy), iy = Int(oy + t * dy - s * dx)
        if ix >= 0, iy >= 0, ix < n, iy < n, sil[iy * n + ix] == 1 { hits += 1 }
      }
      let iou = Double(hits) / Double(2 * points.count - hits)
      var axis = PatternAxis(originX: ox, originY: oy, directionX: dx, directionY: dy, mirrorOverlap: iou, directionConfidence: 0)
      let profile = widthProfile(sil, size: n, axis: axis)
      let k = max(1, profile.count / 5)
      let start = profile.prefix(k).reduce(0, +), end = profile.suffix(k).reduce(0, +)
      let asymmetry = max(start, end) > 0 ? 1 - min(start, end) / max(start, end) : 0
      axis.directionConfidence = asymmetry
      if end < start { axis.directionX = -dx; axis.directionY = -dy }
      return (iou + 0.5 * asymmetry, axis)
    }

    var best = candidate(theta: 0, offset: 0)
    for step in stride(from: 3.0, to: 180, by: 3) {
      let c = candidate(theta: step * .pi / 180, offset: 0)
      if c.score > best.score { best = c }
    }
    let base = atan2(best.axis.directionY, best.axis.directionX)
    for dAngle in stride(from: -3.0, through: 3.0, by: 1) {
      for offset in stride(from: -8.0, through: 8.0, by: 2) {
        let c = candidate(theta: base + dAngle * .pi / 180, offset: offset)
        if c.score > best.score { best = c }
      }
    }
    return best.axis
  }

  public static func measure(surface: CupSurface, foam: FoamSegmenter.Result, axis: PatternAxis) -> PourMetrics {
    let n = surface.size
    let radius = Double(n) / 2
    let mask = foam.mask
    let dx = axis.directionX, dy = axis.directionY
    func frame(_ x: Double, _ y: Double) -> (t: Double, s: Double) {
      let rx = x - axis.originX, ry = y - axis.originY
      return (rx * dx + ry * dy, -rx * dy + ry * dx)
    }
    func point(t: Double, s: Double) -> (x: Double, y: Double) {
      (axis.originX + t * dx - s * dy, axis.originY + t * dy + s * dx)
    }
    var white = [Float](repeating: 0, count: n * n)
    for i in 0..<(n * n) where surface.inside[i] == 1 {
      white[i] = FoamSegmenter.whiteness(l: surface.l[i], a: surface.a[i], b: surface.b[i])
    }
    func whiteAt(_ x: Double, _ y: Double) -> Float {
      let ix = Int(x), iy = Int(y)
      guard ix >= 0, iy >= 0, ix < n, iy < n, surface.inside[iy * n + ix] == 1 else { return -.infinity }
      return white[iy * n + ix]
    }

    // Extent in the axis frame.
    var tMin = Double.infinity, tMax = -Double.infinity, sMin = Double.infinity, sMax = -Double.infinity
    var foamL: [Float] = [], cremaL: [Float] = []
    for y in 0..<n {
      for x in 0..<n where surface.inside[y * n + x] == 1 {
        let i = y * n + x
        if mask[i] == 1 {
          let f = frame(Double(x) + 0.5, Double(y) + 0.5)
          tMin = min(tMin, f.t); tMax = max(tMax, f.t); sMin = min(sMin, f.s); sMax = max(sMax, f.s)
          foamL.append(surface.l[i])
        } else {
          cremaL.append(surface.l[i])
        }
      }
    }
    let center = point(t: (tMin + tMax) / 2, s: (sMin + sMax) / 2)
    let centerOffset = hypot(center.x - radius, center.y - radius) / radius
    let contrast = Double(median(foamL) - median(cremaL))

    // Edge sharpness along the foam outline.
    var edgeSum = 0.0, edgeCount = 0.0
    for y in 1..<(n - 1) {
      for x in 1..<(n - 1) {
        let i = y * n + x
        guard mask[i] == 1, mask[i - 1] == 0 || mask[i + 1] == 0 || mask[i - n] == 0 || mask[i + n] == 0 else { continue }
        let gx = Double(white[i + 1] - white[i - 1]) / 2, gy = Double(white[i + n] - white[i - n]) / 2
        edgeSum += hypot(gx, gy); edgeCount += 1
      }
    }
    let edgeSharpness = edgeCount > 0 && contrast > 0 ? edgeSum / edgeCount / contrast : 0

    // Stacks: stacks usually join at the spine, so count foam runs on lines
    // parallel to it, a third and two thirds of the way out on each side.
    var counts: [Int] = [], lengths: [Int] = []
    let halfWidth = (sMax - sMin) / 2, sMid = (sMax + sMin) / 2
    for fraction in [-0.6, -0.3, 0.3, 0.6] {
      let s = sMid + fraction * halfWidth
      var runs: [Int] = [], current = 0, gap = 0
      for step in stride(from: tMin, through: tMax, by: 1) {
        let p = point(t: step, s: s)
        let ix = Int(p.x), iy = Int(p.y)
        if ix >= 0, iy >= 0, ix < n, iy < n, mask[iy * n + ix] == 1 {
          if gap >= 2, current > 0 { runs.append(current); current = 0 }
          current += 1; gap = 0
        } else {
          gap += 1
        }
      }
      if current > 0 { runs.append(current) }
      let real = runs.filter { $0 >= 3 }
      counts.append(real.count)
      lengths += real
    }
    let stackCount = counts.sorted()[counts.count / 2]
    let stackThickness = lengths.isEmpty ? 0 : Double(lengths.reduce(0, +)) / Double(lengths.count) / radius

    // Silhouette: close the gaps between stacks and fill holes.
    let silhouette = silhouette(mask, size: n)
    let foamArea = mask.reduce(0) { $0 + Int($1) }
    let silhouetteArea = silhouette.reduce(0) { $0 + Int($1) }
    let profile = widthProfile(silhouette, size: n, axis: axis)
    let tipBand = profile.prefix(max(1, Int(Double(profile.count) * 0.15)))
    let tipTaper = (profile.max() ?? 0) > 0 ? tipBand.reduce(0, +) / Double(tipBand.count) / profile.max()! : 1
    /// Intersection over union of a mask and its mirror image across the axis:
    /// with A foam pixels of which H land on foam when mirrored, IoU = H / (2A − H).
    func mirrorIoU(_ m: [UInt8]) -> Double {
      var area = 0, hits = 0
      for y in 0..<n {
        for x in 0..<n where m[y * n + x] == 1 {
          area += 1
          let f = frame(Double(x) + 0.5, Double(y) + 0.5)
          let q = point(t: f.t, s: -f.s)
          let ix = Int(q.x), iy = Int(q.y)
          if ix >= 0, iy >= 0, ix < n, iy < n, m[iy * n + ix] == 1 { hits += 1 }
        }
      }
      return area > 0 ? Double(hits) / Double(2 * area - hits) : 0
    }

    /// Silhouette symmetry about its own best mirror line near the axis, so a
    /// slightly mis-estimated axis doesn't count against the pour.
    func bestMirrorIoU(_ m: [UInt8]) -> Double {
      var pts: [(Double, Double)] = []
      for y in 0..<n { for x in 0..<n where m[y * n + x] == 1 { pts.append((Double(x) + 0.5, Double(y) + 0.5)) } }
      guard !pts.isEmpty else { return 0 }
      let base = atan2(dy, dx)
      var best = 0.0
      for dAngle in stride(from: -10.0, through: 10.0, by: 2) {
        let a = base + dAngle * .pi / 180
        let ux = cos(a), uy = sin(a)
        for offset in stride(from: -8.0, through: 8.0, by: 2) {
          let ox = axis.originX - uy * offset, oy = axis.originY + ux * offset
          var hits = 0
          for (px, py) in pts {
            let rx = px - ox, ry = py - oy
            let t = rx * ux + ry * uy, s = -rx * uy + ry * ux
            let qx = ox + t * ux + s * uy, qy = oy + t * uy - s * ux
            let ix = Int(qx), iy = Int(qy)
            if ix >= 0, iy >= 0, ix < n, iy < n, m[iy * n + ix] == 1 { hits += 1 }
          }
          best = max(best, Double(hits) / Double(2 * pts.count - hits))
        }
      }
      return best
    }

    // Stem: thin raw-foam line continuing past the base (cleanup erased it from the mask).
    var stem = 0.0
    var t = tMin
    while t > -radius {
      t -= 1
      let hit = stride(from: -3.0, through: 3.0, by: 1).contains { s in
        let p = point(t: t, s: s)
        return whiteAt(p.x, p.y) > foam.threshold
      }
      if !hit { break }
      stem += 1
    }

    // Roughness: crema pixels far from their 5×5 neighborhood mean.
    var rough = 0, cremaCount = 0
    for y in 2..<(n - 2) {
      for x in 2..<(n - 2) {
        let i = y * n + x
        guard surface.inside[i] == 1, mask[i] == 0 else { continue }
        var sum: Float = 0
        for oy in -2...2 { for ox in -2...2 { sum += surface.l[i + oy * n + ox] } }
        if abs(surface.l[i] - sum / 25) > 5 { rough += 1 }
        cremaCount += 1
      }
    }

    return PourMetrics(
      centerOffset: centerOffset,
      symmetry: bestMirrorIoU(silhouette),
      detailSymmetry: mirrorIoU(mask),
      length: (tMax - tMin) / (2 * radius),
      width: (sMax - sMin) / (2 * radius),
      coverage: foam.coverage,
      contrast: contrast,
      edgeSharpness: edgeSharpness,
      stackCount: stackCount,
      stackThickness: stackThickness,
      stemLength: stem / radius,
      fill: silhouetteArea > 0 ? min(1, Double(foamArea) / Double(silhouetteArea)) : 0,
      tipTaper: tipTaper,
      surfaceRoughness: cremaCount > 0 ? Double(rough) / Double(cremaCount) : 0
    )
  }

  static func median(_ values: [Float]) -> Float {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
  }
}
