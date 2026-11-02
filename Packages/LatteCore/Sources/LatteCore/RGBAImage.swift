import CoreGraphics
import Foundation
import ImageIO

/// An 8-bit RGBA bitmap in display orientation (EXIF rotation already applied).
public struct RGBAImage: Sendable {
  public let width: Int
  public let height: Int
  /// Row-major RGBA bytes, `width * height * 4` long.
  public var pixels: [UInt8]

  public init(width: Int, height: Int, pixels: [UInt8]) {
    precondition(pixels.count == width * height * 4)
    self.width = width
    self.height = height
    self.pixels = pixels
  }

  public enum LoadError: Error { case unreadable, decodeFailed }

  /// Decodes an image file, applying EXIF orientation and downscaling so the
  /// longest side is at most `maxDimension`. ImageIO's thumbnailer decodes at
  /// reduced resolution, so this is fast even for 12 MP photos.
  public static func load(contentsOf url: URL, maxDimension: Int = 512) throws -> RGBAImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw LoadError.unreadable }
    return try load(source: source, maxDimension: maxDimension)
  }

  public static func load(data: Data, maxDimension: Int = 512) throws -> RGBAImage {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw LoadError.unreadable }
    return try load(source: source, maxDimension: maxDimension)
  }

  private static func load(source: CGImageSource, maxDimension: Int) throws -> RGBAImage {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxDimension,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      throw LoadError.decodeFailed
    }
    return try RGBAImage(cgImage: image)
  }

  public init(cgImage: CGImage) throws {
    let width = cgImage.width
    let height = cgImage.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard let context = CGContext(
        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else { return false }
      context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { throw LoadError.decodeFailed }
    self.init(width: width, height: height, pixels: pixels)
  }

  public func makeCGImage() -> CGImage? {
    let data = Data(pixels) as CFData
    guard let provider = CGDataProvider(data: data) else { return nil }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
    )
  }
}
