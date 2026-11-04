import Foundation

/// A point in analysis-image pixel coordinates.
public struct ImagePoint: Sendable, Equatable {
  public var x: Double
  public var y: Double
  public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// Everything the app shows for one analyzed photo.
public struct PourAnalysis: Sendable {
  /// Size of the downscaled image the analysis ran on. All geometry below is
  /// in this image's pixel coordinates; scale it to draw over any rendition.
  public let imageWidth: Int
  public let imageHeight: Int
  public let cup: Ellipse
  /// Same size as the analysis image: foam pixels tinted, everything else clear.
  public let foamOverlay: RGBAImage
  /// Ends of the pattern's axis.
  public let stem: ImagePoint
  public let tip: ImagePoint
  public let metrics: TulipMetrics
  public let score: TulipScore
  public let tips: [CoachingTip]
  public let duration: Duration

  public enum Failure: Error, Equatable, Sendable {
    case unreadableImage
    case noCoffeeFound
    case noPatternFound
  }

  public static let analysisDimension = 512

  public static func analyze(imageData: Data) throws(Failure) -> PourAnalysis {
    let start = ContinuousClock.now
    let image: RGBAImage
    do { image = try RGBAImage.load(data: imageData, maxDimension: analysisDimension) } catch { throw .unreadableImage }
    return try analyze(image: image, start: start)
  }

  public static func analyze(image: RGBAImage, start: ContinuousClock.Instant = .now) throws(Failure) -> PourAnalysis {
    let lab = LabImage(image)
    let cup: CupDetector.Result
    do { cup = try CupDetector.detect(lab) } catch { throw .noCoffeeFound }
    let surface = CupSurface(lab: lab, ellipse: cup.ellipse)
    let foam = FoamSegmenter.segment(surface)
    guard foam.coverage > 0.03, let axis = PatternAxis.find(surface: surface, mask: foam.mask) else {
      throw .noPatternFound
    }
    let metrics = TulipAnalyzer.measure(surface: surface, foam: foam, axis: axis)
    let score = TulipScore(metrics)
    let extent = TulipAnalyzer.extent(mask: foam.mask, size: surface.size, axis: axis)
    let stem = surface.imagePoint(gridX: extent.stem.x, gridY: extent.stem.y)
    let tip = surface.imagePoint(gridX: extent.tip.x, gridY: extent.tip.y)
    let tips = Coach.tips(metrics: metrics, score: score, offsetAlongAxis: extent.offsetAlongAxis)
    return PourAnalysis(
      imageWidth: image.width, imageHeight: image.height, cup: cup.ellipse,
      foamOverlay: foamOverlay(surface: surface, mask: foam.mask, width: image.width, height: image.height),
      stem: ImagePoint(x: stem.x, y: stem.y), tip: ImagePoint(x: tip.x, y: tip.y),
      metrics: metrics, score: score, tips: tips, duration: ContinuousClock.now - start
    )
  }

  /// Projects the grid foam mask back onto the photo.
  static func foamOverlay(surface: CupSurface, mask: [UInt8], width: Int, height: Int) -> RGBAImage {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let e = surface.ellipse
    let c = cos(e.angle), s = sin(e.angle)
    // Inverse of M = R·diag(a, b)·Rᵀ is R·diag(1/a, 1/b)·Rᵀ.
    let ia = 1 / e.semiMajor, ib = 1 / e.semiMinor
    let i00 = ia * c * c + ib * s * s, i01 = (ia - ib) * c * s, i11 = ia * s * s + ib * c * c
    let n = surface.size, half = Double(n) / 2
    let minY = max(0, Int(e.centerY - e.semiMajor)), maxY = min(height - 1, Int(e.centerY + e.semiMajor) + 1)
    let minX = max(0, Int(e.centerX - e.semiMajor)), maxX = min(width - 1, Int(e.centerX + e.semiMajor) + 1)
    guard minY <= maxY, minX <= maxX else { return RGBAImage(width: width, height: height, pixels: pixels) }
    for y in minY...maxY {
      for x in minX...maxX {
        let dx = Double(x) + 0.5 - e.centerX, dy = Double(y) + 0.5 - e.centerY
        let u = i00 * dx + i01 * dy, v = i01 * dx + i11 * dy
        let gx = Int(u * half + half), gy = Int(v * half + half)
        guard gx >= 0, gy >= 0, gx < n, gy < n, mask[gy * n + gx] == 1 else { continue }
        // Premultiplied mint at ~55% opacity.
        let o = (y * width + x) * 4
        pixels[o] = 48; pixels[o + 1] = 121; pixels[o + 2] = 102; pixels[o + 3] = 140
      }
    }
    return RGBAImage(width: width, height: height, pixels: pixels)
  }
}

extension TulipAnalyzer {
  /// Ends of the pattern along its axis (grid coordinates) and how far the
  /// pattern's center sits from the cup center along the axis, / cup radius
  /// (positive = pushed toward the tip).
  static func extent(mask: [UInt8], size n: Int, axis: PatternAxis)
    -> (stem: (x: Double, y: Double), tip: (x: Double, y: Double), offsetAlongAxis: Double)
  {
    let dx = axis.directionX, dy = axis.directionY
    var tMin = Double.infinity, tMax = -Double.infinity
    for y in 0..<n {
      for x in 0..<n where mask[y * n + x] == 1 {
        let t = (Double(x) + 0.5 - axis.originX) * dx + (Double(y) + 0.5 - axis.originY) * dy
        tMin = min(tMin, t); tMax = max(tMax, t)
      }
    }
    let half = Double(n) / 2
    let mid = (tMin + tMax) / 2
    let centerT = (half - axis.originX) * dx + (half - axis.originY) * dy
    return (
      (axis.originX + dx * tMin, axis.originY + dy * tMin),
      (axis.originX + dx * tMax, axis.originY + dy * tMax),
      (mid - centerT) / half
    )
  }
}
