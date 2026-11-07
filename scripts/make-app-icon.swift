// Draws the app icon (light, dark and tinted) into the asset catalog.
//   swift scripts/make-app-icon.swift
//
// A top-down view into the cup: crema with a poured heart (with its
// pull-through tail), ringed by the amber score arc. The arc ends in the dot
// the app draws at the tip of a pattern's axis.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func rgb(_ hex: UInt32) -> CGColor {
  CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

enum Appearance { case light, dark, tinted }

func heartPath(in r: CGRect) -> CGPath {
  // 100×100 box, y down, point at the bottom.
  let p = CGMutablePath()
  func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x / 100 * r.width, y: r.minY + y / 100 * r.height) }
  p.move(to: pt(50, 90))
  p.addCurve(to: pt(5, 34), control1: pt(24, 72), control2: pt(5, 55))
  p.addCurve(to: pt(30, 8), control1: pt(5, 18), control2: pt(16, 8))
  p.addCurve(to: pt(50, 22), control1: pt(40, 8), control2: pt(47, 14))
  p.addCurve(to: pt(70, 8), control1: pt(53, 14), control2: pt(60, 8))
  p.addCurve(to: pt(95, 34), control1: pt(84, 8), control2: pt(95, 18))
  p.addCurve(to: pt(50, 90), control1: pt(95, 55), control2: pt(76, 72))
  p.closeSubpath()
  return p
}

func icon(_ appearance: Appearance, size: Int = 1024) -> CGImage {
  let s = CGFloat(size)
  let gray = appearance == .tinted
  let space = gray ? CGColorSpaceCreateDeviceGray() : CGColorSpace(name: CGColorSpace.sRGB)!
  // No alpha channel: the App Store rejects icons with one.
  let info = gray ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
  let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)!
  ctx.translateBy(x: 0, y: s)
  ctx.scaleBy(x: 1, y: -1)  // y down
  func color(_ light: UInt32, dark: UInt32? = nil, gray level: CGFloat) -> CGColor {
    gray ? CGColor(gray: level, alpha: 1) : rgb(appearance == .dark ? (dark ?? light) : light)
  }
  let center = CGPoint(x: s / 2, y: s / 2)

  // Crema, lighter in the middle, darker toward the rim.
  let crema = CGGradient(
    colorsSpace: space,
    colors: [color(0xC98A4B, dark: 0x9A5E2C, gray: 0.32), color(0x7E4A22, dark: 0x3E2312, gray: 0.08)] as CFArray,
    locations: [0, 1])!
  ctx.drawRadialGradient(crema, startCenter: CGPoint(x: center.x, y: center.y - s * 0.04), startRadius: 0,
                         endCenter: center, endRadius: s * 0.62, options: [.drawsAfterEndLocation])

  // The heart, with a soft microfoam edge and its pull-through tail.
  let foam = color(0xFBF7F0, gray: 1)
  let markSize = s * 0.50
  let mark = CGRect(x: center.x - markSize / 2, y: center.y - markSize / 2 - s * 0.02, width: markSize, height: markSize)
  ctx.saveGState()
  ctx.setShadow(offset: .zero, blur: s * 0.012, color: foam)
  ctx.setFillColor(foam)
  ctx.addPath(heartPath(in: mark))
  ctx.fillPath()
  let tip = CGPoint(x: mark.midX, y: mark.minY + mark.height * 0.88)
  let tail = CGMutablePath()
  tail.move(to: CGPoint(x: tip.x - s * 0.012, y: tip.y - s * 0.02))
  tail.addLine(to: CGPoint(x: tip.x + s * 0.012, y: tip.y - s * 0.02))
  tail.addLine(to: CGPoint(x: tip.x + s * 0.0035, y: tip.y + s * 0.10))
  tail.addLine(to: CGPoint(x: tip.x - s * 0.0035, y: tip.y + s * 0.10))
  tail.closeSubpath()
  ctx.addPath(tail)
  ctx.fillPath()
  ctx.restoreGState()

  // The amber score arc, about 78% of the way round, ending in the tip dot.
  let amber = color(0xF2B33D, gray: 0.85)
  let radius = s * 0.355
  let start = CGFloat.pi * 0.62, end = start + CGFloat.pi * 2 * 0.78
  ctx.setStrokeColor(amber)
  ctx.setLineWidth(s * 0.035)
  ctx.setLineCap(.round)
  ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
  ctx.strokePath()
  let dot = s * 0.075
  let q = CGPoint(x: center.x + radius * cos(end), y: center.y + radius * sin(end))
  ctx.setFillColor(amber)
  ctx.fillEllipse(in: CGRect(x: q.x - dot / 2, y: q.y - dot / 2, width: dot, height: dot))
  return ctx.makeImage()!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let folder = root.appendingPathComponent("LatteArtCoach/Assets.xcassets/AppIcon.appiconset")
for (name, appearance) in [("AppIcon.png", Appearance.light), ("AppIcon-dark.png", .dark), ("AppIcon-tinted.png", .tinted)] {
  let url = folder.appendingPathComponent(name)
  let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(dest, icon(appearance), nil)
  guard CGImageDestinationFinalize(dest) else { fatalError("Couldn't write \(url.path)") }
  print("Wrote \(url.path)")
}
