import SwiftUI

/// The score as the app icon's amber arc: a ring with a gap at the bottom
/// that fills to the score and ends in the tip dot, with the number inside.
struct ScoreGauge: View {
  let score: Int
  var lineWidth: CGFloat = 11
  @State private var fill: Double = 0

  /// The same sweep and start as the icon: 78% of the circle, gap at lower left.
  nonisolated static let span = 0.78
  nonisolated static let startDegrees = 111.6

  var body: some View {
    ZStack {
      Circle()
        .trim(from: 0, to: Self.span)
        .stroke(Color.crema.opacity(0.18), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.degrees(Self.startDegrees))
      Circle()
        .trim(from: 0, to: Self.span * fill)
        .stroke(Color.measure, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.degrees(Self.startDegrees))
      ArcDot(fraction: fill, lineWidth: lineWidth).fill(Color.measure)
      VStack(spacing: 0) {
        Text("\(score)")
          .font(.number(44))
          .contentTransition(.numericText(value: Double(score)))
          .accessibilityIdentifier("overall-score")
        Text("of 100").font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(lineWidth)
    .onAppear { reveal() }
    .onChange(of: score) { reveal() }
    .sensoryFeedback(.success, trigger: score)
    .accessibilityElement(children: .contain)
  }

  private func reveal() {
    fill = 0
    withAnimation(.spring(duration: 1.1, bounce: 0.15)) { fill = Double(score) / 100 }
  }
}

/// The dot at the end of the filled arc; animatable so it travels with it.
private struct ArcDot: Shape {
  var fraction: Double
  let lineWidth: CGFloat
  var animatableData: Double {
    get { fraction }
    set { fraction = newValue }
  }

  func path(in rect: CGRect) -> Path {
    let radius = min(rect.width, rect.height) / 2
    let angle = (ScoreGauge.startDegrees + 360 * ScoreGauge.span * fraction) * .pi / 180
    let center = CGPoint(x: rect.midX + radius * cos(angle), y: rect.midY + radius * sin(angle))
    let size = lineWidth * 2.1
    return Path(ellipseIn: CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size))
  }
}
