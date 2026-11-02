import Foundation

/// CIE L*a*b* (D65) planes for an image, computed with lookup tables.
public struct LabImage: Sendable {
  public let width: Int
  public let height: Int
  public var l: [Float]
  public var a: [Float]
  public var b: [Float]

  public init(_ image: RGBAImage) {
    width = image.width
    height = image.height
    let count = width * height
    var l = [Float](repeating: 0, count: count)
    var a = [Float](repeating: 0, count: count)
    var b = [Float](repeating: 0, count: count)
    let linear = LabImage.linearTable
    image.pixels.withUnsafeBufferPointer { px in
      for i in 0..<count {
        let r = linear[Int(px[i * 4])], g = linear[Int(px[i * 4 + 1])], bl = linear[Int(px[i * 4 + 2])]
        let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * bl) / 0.95047
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * bl
        let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * bl) / 1.08883
        let fx = LabImage.f(x), fy = LabImage.f(y), fz = LabImage.f(z)
        l[i] = 116 * fy - 16
        a[i] = 500 * (fx - fy)
        b[i] = 200 * (fy - fz)
      }
    }
    self.l = l
    self.a = a
    self.b = b
  }

  private static let linearTable: [Float] = (0..<256).map { value in
    let c = Float(value) / 255
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
  }

  @inline(__always) private static func f(_ t: Float) -> Float {
    t > 0.008856 ? cbrtf(t) : 7.787 * t + 16.0 / 116.0
  }
}
