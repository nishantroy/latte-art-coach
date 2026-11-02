import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import LatteCore

/// Draws analysis results over a photo for eyeballing during development.
enum DebugRender {
  static func write(_ image: RGBAImage, ellipse: Ellipse, tint: [UInt8]? = nil, name: String) {
    guard let dir = Fixtures.debugDirectory else { return }
    var pixels = image.pixels
    if let tint {
      for i in 0..<(image.width * image.height) where tint[i] == 0 {
        pixels[i * 4] /= 3; pixels[i * 4 + 1] /= 3; pixels[i * 4 + 2] /= 3
      }
    }
    for t in stride(from: 0.0, to: 2 * Double.pi, by: 0.002) {
      let p = ellipse.point(unitX: cos(t), unitY: sin(t))
      plot(&pixels, image, Int(p.x), Int(p.y), [255, 0, 255])
    }
    for s in stride(from: -1.0, through: 1.0, by: 0.002) {
      let p = ellipse.point(unitX: s, unitY: 0)
      plot(&pixels, image, Int(p.x), Int(p.y), [0, 255, 255])
    }
    let out = RGBAImage(width: image.width, height: image.height, pixels: pixels)
    guard let cg = out.makeCGImage(),
          let dest = CGImageDestinationCreateWithURL(dir.appendingPathComponent("\(name).png") as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(dest, cg, nil)
    CGImageDestinationFinalize(dest)
  }

  private static func plot(_ pixels: inout [UInt8], _ image: RGBAImage, _ x: Int, _ y: Int, _ color: [UInt8]) {
    for dy in -1...1 {
      for dx in -1...1 {
        let px = x + dx, py = y + dy
        guard px >= 0, py >= 0, px < image.width, py < image.height else { continue }
        let i = (py * image.width + px) * 4
        pixels[i] = color[0]; pixels[i + 1] = color[1]; pixels[i + 2] = color[2]
      }
    }
  }
}

extension DebugRender {
  /// Renders the normalized cup surface with the foam mask tinted and the
  /// pattern axis drawn from stem (red) to tip (green).
  static func write(surface: CupSurface, foam: [UInt8], axis: PatternAxis?, name: String) {
    guard let dir = Fixtures.debugDirectory else { return }
    let n = surface.size
    var pixels = [UInt8](repeating: 0, count: n * n * 4)
    for i in 0..<(n * n) {
      let v = UInt8(max(0, min(255, surface.l[i] * 2.55)))
      let o = i * 4
      if surface.inside[i] == 0 { pixels[o] = v / 4; pixels[o + 1] = v / 4; pixels[o + 2] = v / 4 }
      else if foam[i] == 1 { pixels[o] = v / 2; pixels[o + 1] = v; pixels[o + 2] = v / 2 }
      else { pixels[o] = v; pixels[o + 1] = UInt8(Int(v) * 3 / 4); pixels[o + 2] = v / 2 }
      pixels[o + 3] = 255
    }
    var image = RGBAImage(width: n, height: n, pixels: pixels)
    if let axis {
      for step in stride(from: -0.45, through: 0.45, by: 0.002) {
        let x = Int(axis.originX + axis.directionX * step * Double(n))
        let y = Int(axis.originY + axis.directionY * step * Double(n))
        let color: [UInt8] = step < 0 ? [255, 40, 40] : [40, 255, 40]
        for dy in -1...1 { for dx in -1...1 {
          let px = x + dx, py = y + dy
          guard px >= 0, py >= 0, px < n, py < n else { continue }
          let o = (py * n + px) * 4
          image.pixels[o] = color[0]; image.pixels[o + 1] = color[1]; image.pixels[o + 2] = color[2]
        } }
      }
    }
    guard let cg = image.makeCGImage(),
          let dest = CGImageDestinationCreateWithURL(dir.appendingPathComponent("\(name).png") as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(dest, cg, nil)
    CGImageDestinationFinalize(dest)
  }
}
