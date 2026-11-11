import LatteCore
import SwiftUI

/// A cup from straight above with the pattern poured in it: white rim,
/// crema, milk. The home screen's hero, and the scoring screen's.
struct CupHero: View {
  let pattern: Pattern

  var body: some View {
    GeometryReader { proxy in
      let s = min(proxy.size.width, proxy.size.height)
      ZStack {
        // The cup's rim, lit from above.
        Circle()
          .fill(LinearGradient(colors: [Color(light: 0xFFFFFF, dark: 0x3A3532), Color(light: 0xE9E5E0, dark: 0x24201D)],
                               startPoint: .top, endPoint: .bottom))
          .shadow(color: .black.opacity(0.14), radius: s * 0.06, y: s * 0.04)
        // The coffee: darker toward the edge, as crema is.
        Circle()
          .fill(RadialGradient(colors: [Color(light: 0xC68A52, dark: 0xB27A45), Color(light: 0x9A5A2B, dark: 0x82491F),
                                        Color(light: 0x4E2C16, dark: 0x3C2111)],
                               center: .center, startRadius: 0, endRadius: s * 0.43))
          .padding(s * 0.075)
          .overlay {
            // The rim's inner edge throws a thin shadow onto the coffee.
            Circle().strokeBorder(.black.opacity(0.25), lineWidth: s * 0.012).blur(radius: s * 0.01).padding(s * 0.075)
          }
        PatternGlyph(pattern: pattern)
          .foregroundStyle(Color(light: 0xFBF6EE, dark: 0xF4ECE0))
          .frame(width: s * 0.4, height: s * 0.4)
          .shadow(color: .black.opacity(0.15), radius: s * 0.01)
          .id(pattern)
          .transition(.asymmetric(insertion: .scale(scale: 0.6).combined(with: .opacity),
                                  removal: .scale(scale: 1.2).combined(with: .opacity)))
      }
      .frame(width: s, height: s)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .aspectRatio(1, contentMode: .fit)
    .accessibilityHidden(true)
  }
}

/// The capture button: a white disc in a ring, like the Camera app's.
struct Shutter: View {
  var symbol = "camera.fill"

  var body: some View {
    ZStack {
      Circle().strokeBorder(Color.espresso.opacity(0.85), lineWidth: 3).frame(width: 82, height: 82)
      Circle().fill(Color.crema).frame(width: 68, height: 68)
      Image(systemName: symbol).font(.title2.weight(.semibold)).foregroundStyle(.white)
    }
    .contentShape(.circle)
  }
}

/// A simple drawing of each pattern, in the current foreground style.
struct PatternGlyph: View {
  let pattern: Pattern

  var body: some View {
    Canvas { context, size in
      let s = min(size.width, size.height)
      let r = CGRect(x: (size.width - s) / 2, y: (size.height - s) / 2, width: s, height: s)
      func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * s, y: r.minY + y * s) }
      /// The lower part of a circle round the stem: a crescent with its tips
      /// pointing up, from `start` degrees to 180 − `start` through the bottom.
      /// Traced point by point as its own subpath, so nothing joins crescents.
      func crescent(_ p: inout Path, centerY: CGFloat, radius: CGFloat, from start: Double) {
        let steps = 24
        for i in 0...steps {
          let a = (start + (180 - 2 * start) * Double(i) / Double(steps)) * .pi / 180
          let q = pt(0.5 + radius * cos(a), centerY + radius * sin(a))
          i == 0 ? p.move(to: q) : p.addLine(to: q)
        }
      }
      switch pattern {
      case .heart:
        // The icon's heart, with its pull-through tail.
        var p = Path()
        p.move(to: pt(0.5, 0.80))
        p.addCurve(to: pt(0.08, 0.34), control1: pt(0.26, 0.64), control2: pt(0.08, 0.52))
        p.addCurve(to: pt(0.31, 0.12), control1: pt(0.08, 0.20), control2: pt(0.18, 0.12))
        p.addCurve(to: pt(0.5, 0.25), control1: pt(0.40, 0.12), control2: pt(0.47, 0.17))
        p.addCurve(to: pt(0.69, 0.12), control1: pt(0.53, 0.17), control2: pt(0.60, 0.12))
        p.addCurve(to: pt(0.92, 0.34), control1: pt(0.82, 0.12), control2: pt(0.92, 0.20))
        p.addCurve(to: pt(0.5, 0.80), control1: pt(0.92, 0.52), control2: pt(0.74, 0.64))
        p.closeSubpath()
        context.fill(p, with: .foreground)
        context.fill(Path(CGRect(x: r.minX + s * 0.485, y: r.minY + s * 0.76, width: s * 0.03, height: s * 0.18)), with: .foreground)
      case .tulip:
        // A round head with two crescents wrapped under it, on a short stem.
        context.fill(Path(ellipseIn: CGRect(x: r.minX + s * 0.32, y: r.minY + s * 0.08, width: s * 0.36, height: s * 0.28)), with: .foreground)
        var p = Path()
        crescent(&p, centerY: 0.18, radius: 0.30, from: 22)
        crescent(&p, centerY: 0.20, radius: 0.43, from: 28)
        context.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: s * 0.085, lineCap: .round))
        context.fill(Path(roundedRect: CGRect(x: r.minX + s * 0.47, y: r.minY + s * 0.66, width: s * 0.06, height: s * 0.28), cornerRadius: s * 0.03), with: .foreground)
      case .rosetta:
        // Many thin crescents up a stem, smallest at the top.
        var p = Path()
        p.move(to: pt(0.5, 0.06))
        p.addLine(to: pt(0.5, 0.96))
        for i in 0..<5 {
          crescent(&p, centerY: 0.02 + CGFloat(i) * 0.115, radius: 0.08 + CGFloat(i) * 0.06, from: 28)
        }
        context.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: s * 0.065, lineCap: .round, lineJoin: .round))
      }
    }
    .accessibilityHidden(true)
  }
}
