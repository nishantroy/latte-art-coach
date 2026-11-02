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
