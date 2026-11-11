import Foundation

/// Raw measurements of a pour, for any pattern, all scale-free (fractions of the cup
/// radius or of the pattern) so photos of any size compare directly.
public struct PourMetrics: Sendable, Equatable, Codable {
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
  /// How far each lobe's outline strays from a circle, / the circle's
  /// radius. Round lobes are low; a flat top or squared corners are high.
  /// Only meaningful for hearts. Clean drawn hearts measure ~0.01, a
  /// flat-topped shield ~0.10.
  public var lobeRoundness: Double
  /// Fraction of crema pixels that differ sharply from their neighborhood
  /// (bubbles and coarse microfoam), away from the art's outline and from
  /// reflections.
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

  /// The axis of a heart: the line from its point (stem) to its notch (tip).
  ///
  /// A heart is a round blob, so a plain mirror-overlap search can settle on
  /// a diagonal that fits almost as well, especially when one lobe is bigger.
  /// Instead the axis comes from two landmarks: the notch between the lobes
  /// is the deepest dent in the outline, and the point is the part of the
  /// heart farthest from the notch. The line is then fine-tuned for mirror
  /// overlap. Hearts without a visible notch fall back to a search scored on
  /// mirror overlap plus a wide-lobes, narrow-point profile.
  public static func heartAxis(mask: [UInt8], size n: Int) -> PatternAxis? {
    if let axis = notchAxis(mask: mask, size: n) { return axis }
    return profileAxis(mask: mask, size: n)
  }

  /// The heart itself: the largest foam region, holes filled. The raw mask
  /// is used rather than the silhouette, whose closing would fill the notch.
  static func solidHeart(mask: [UInt8], size n: Int) -> [UInt8]? {
    guard let heart = CupDetector.components(mask, width: n, height: n, minSize: 50).max(by: { $0.size < $1.size }) else { return nil }
    return CupDetector.fillHoles(heart.mask, width: n, height: n)
  }

  /// See `PourMetrics.lobeRoundness`.
  ///
  /// Each lobe's outline, from the heart's widest row up to the top
  /// (including its side of the notch), gets a least-squares circle fit; the
  /// mean distance of the outline from that circle, / its radius, is low for
  /// round lobes and high for flat tops and corners.
  static func lobeRoundness(mask: [UInt8], size n: Int, axis: PatternAxis) -> Double {
    guard let solid = solidHeart(mask: mask, size: n) else { return 1 }
    let dx = axis.directionX, dy = axis.directionY
    func frame(_ x: Double, _ y: Double) -> (t: Double, s: Double) {
      let rx = x - axis.originX, ry = y - axis.originY
      return (rx * dx + ry * dy, -rx * dy + ry * dx)
    }
    var rows: [Int: (lo: Double, hi: Double)] = [:]
    var tMin = Double.infinity, tMax = -Double.infinity
    var outline: [(t: Double, s: Double)] = []
    for y in 1..<(n - 1) {
      for x in 1..<(n - 1) where solid[y * n + x] == 1 {
        let i = y * n + x
        let f = frame(Double(x) + 0.5, Double(y) + 0.5)
        tMin = min(tMin, f.t); tMax = max(tMax, f.t)
        let r = rows[Int(f.t)] ?? (f.s, f.s)
        rows[Int(f.t)] = (min(r.lo, f.s), max(r.hi, f.s))
        if solid[i - 1] == 0 || solid[i + 1] == 0 || solid[i - n] == 0 || solid[i + n] == 0 { outline.append(f) }
      }
    }
    // The lobes start at the widest row. Flat-sided shapes have several rows
    // tied for widest; take the one nearest the point. (Picking among ties in
    // dictionary order made the result vary from run to run.)
    guard tMax - tMin > 8, let maxWidth = rows.values.map({ $0.hi - $0.lo }).max() else { return 1 }
    let widestKey = rows.filter { $0.value.hi - $0.value.lo == maxWidth }.keys.min()!
    let widest = rows[widestKey]!
    let sMid = (widest.lo + widest.hi) / 2
    let tWide = Double(widestKey)

    func circleError(_ pts: [(t: Double, s: Double)]) -> Double {
      guard pts.count >= 8 else { return 1 }
      // Kåsa fit: minimize Σ(x² + y² + Dx + Ey + F)².
      var sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0, sz = 0.0, sxz = 0.0, syz = 0.0
      let m = Double(pts.count)
      for p in pts {
        let x = p.s, y = p.t, z = x * x + y * y
        sx += x; sy += y; sxx += x * x; syy += y * y; sxy += x * y; sz += z; sxz += x * z; syz += y * z
      }
      // Normal equations [sxx sxy sx; sxy syy sy; sx sy m]·[D E F] = −[sxz syz sz].
      let a = [[sxx, sxy, sx], [sxy, syy, sy], [sx, sy, m]], b = [-sxz, -syz, -sz]
      func det(_ q: [[Double]]) -> Double {
        q[0][0] * (q[1][1] * q[2][2] - q[1][2] * q[2][1]) - q[0][1] * (q[1][0] * q[2][2] - q[1][2] * q[2][0])
          + q[0][2] * (q[1][0] * q[2][1] - q[1][1] * q[2][0])
      }
      let d = det(a)
      guard abs(d) > 1e-9 else { return 1 }
      var sol = [0.0, 0.0, 0.0]
      for k in 0..<3 {
        var q = a
        for r in 0..<3 { q[r][k] = b[r] }
        sol[k] = det(q) / d
      }
      let cx = -sol[0] / 2, cy = -sol[1] / 2
      let radius = (cx * cx + cy * cy - sol[2]).squareRoot()
      guard radius.isFinite, radius > 0 else { return 1 }
      let mean = pts.reduce(0) { $0 + abs(hypot($1.s - cx, $1.t - cy) - radius) } / m
      return mean / radius
    }
    let upper = outline.filter { $0.t >= tWide }
    return (circleError(upper.filter { $0.s < sMid }) + circleError(upper.filter { $0.s > sMid })) / 2
  }

  static func notchAxis(mask: [UInt8], size n: Int) -> PatternAxis? {
    guard let solid = solidHeart(mask: mask, size: n) else { return nil }
    var points: [(x: Double, y: Double)] = []
    for y in 0..<n { for x in 0..<n where solid[y * n + x] == 1 { points.append((Double(x) + 0.5, Double(y) + 0.5)) } }
    let cx = points.reduce(0) { $0 + $1.x } / Double(points.count)
    let cy = points.reduce(0) { $0 + $1.y } / Double(points.count)
    let hull = ConvexHull.mask(points: points, size: n, shrink: 0)
    var dents = [UInt8](repeating: 0, count: n * n)
    for i in 0..<(n * n) where hull[i] == 1 && solid[i] == 0 { dents[i] = 1 }
    guard let notch = CupDetector.components(dents, width: n, height: n, minSize: max(4, points.count / 200))
      .max(by: { $0.size < $1.size }) else { return nil }
    // The bottom of the notch is its pixel nearest the heart's center.
    var notchPoint = (x: 0.0, y: 0.0), nearest = Double.infinity
    for y in 0..<n {
      for x in 0..<n where notch.mask[y * n + x] == 1 {
        let d = hypot(Double(x) + 0.5 - cx, Double(y) + 0.5 - cy)
        if d < nearest { nearest = d; notchPoint = (Double(x) + 0.5, Double(y) + 0.5) }
      }
    }
    guard let tipPoint = points.max(by: {
      hypot($0.x - notchPoint.x, $0.y - notchPoint.y) < hypot($1.x - notchPoint.x, $1.y - notchPoint.y)
    }) else { return nil }
    let base = atan2(notchPoint.y - tipPoint.y, notchPoint.x - tipPoint.x)
    let mx = (notchPoint.x + tipPoint.x) / 2, my = (notchPoint.y + tipPoint.y) / 2

    // Fine-tune: best mirror overlap within a few degrees and pixels.
    let sil = silhouette(mask, size: n)
    var silPoints: [(x: Double, y: Double)] = []
    for y in 0..<n { for x in 0..<n where sil[y * n + x] == 1 { silPoints.append((Double(x) + 0.5, Double(y) + 0.5)) } }
    var best = (iou: -1.0, theta: base, ox: mx, oy: my)
    for dAngle in stride(from: -8.0, through: 8.0, by: 1) {
      let theta = base + dAngle * .pi / 180
      let dx = cos(theta), dy = sin(theta)
      for offset in stride(from: -6.0, through: 6.0, by: 2) {
        let ox = mx - dy * offset, oy = my + dx * offset
        var hits = 0
        for p in silPoints {
          let rx = p.x - ox, ry = p.y - oy
          let t = rx * dx + ry * dy, s = -rx * dy + ry * dx
          let ix = Int(ox + t * dx + s * dy), iy = Int(oy + t * dy - s * dx)
          if ix >= 0, iy >= 0, ix < n, iy < n, sil[iy * n + ix] == 1 { hits += 1 }
        }
        let iou = Double(hits) / Double(2 * silPoints.count - hits)
        if iou > best.iou { best = (iou, theta, ox, oy) }
      }
    }
    return PatternAxis(originX: best.ox, originY: best.oy, directionX: cos(best.theta), directionY: sin(best.theta),
                       mirrorOverlap: best.iou, directionConfidence: 1)
  }

  static func profileAxis(mask: [UInt8], size n: Int) -> PatternAxis? {
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

    // Roughness: crema pixels far from their 5×5 neighborhood mean. Crema
    // next to the foam differs from its neighbors because of the art's own
    // outline, and reflections on wet crema are bright streaks, not bubbles;
    // both are skipped. Reflections: pixels well above the crema's median
    // lightness, and a little around them.
    var nearFoam = mask
    for _ in 0..<3 { nearFoam = Morphology.dilate(nearFoam, size: n) }
    var openCrema: [Float] = []
    for i in 0..<(n * n) where surface.inside[i] == 1 && nearFoam[i] == 0 { openCrema.append(surface.l[i]) }
    let cremaMedian = median(openCrema)
    var reflection = [UInt8](repeating: 0, count: n * n)
    for i in 0..<(n * n) where surface.inside[i] == 1 && nearFoam[i] == 0 && surface.l[i] > cremaMedian + 12 { reflection[i] = 1 }
    for _ in 0..<3 { reflection = Morphology.dilate(reflection, size: n) }
    var rough = 0, cremaCount = 0
    for y in 2..<(n - 2) {
      for x in 2..<(n - 2) {
        let i = y * n + x
        guard surface.inside[i] == 1, nearFoam[i] == 0, reflection[i] == 0 else { continue }
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
      lobeRoundness: lobeRoundness(mask: mask, size: n, axis: axis),
      surfaceRoughness: cremaCount > 0 ? Double(rough) / Double(cremaCount) : 0
    )
  }

  static func median(_ values: [Float]) -> Float {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
  }
}
