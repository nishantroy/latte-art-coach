import LatteCore
import SwiftUI

/// Heart / Tulip / Rosetta as cards with a drawing of each pattern.
struct PatternPicker: View {
  @Binding var selection: Pattern

  var body: some View {
    HStack(spacing: 10) {
      ForEach(Pattern.allCases) { pattern in
        let selected = pattern == selection
        Button {
          withAnimation(.settle) { selection = pattern }
        } label: {
          VStack(spacing: 6) {
            PatternGlyph(pattern: pattern).frame(width: 34, height: 34)
            Text(pattern.displayName).font(.subheadline.weight(.semibold))
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
          .foregroundStyle(selected ? Color.white : Color.espresso)
          .background(selected ? Color.crema : Color.card, in: .rect(cornerRadius: 14))
          .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.crema.opacity(selected ? 0 : 0.25)))
        }
        .buttonStyle(.press)
        .accessibilityLabel(pattern.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
      }
    }
    .sensoryFeedback(.selection, trigger: selection)
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
