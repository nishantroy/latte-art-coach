import SwiftUI

/// The score as an instrument: the app icon's open ring (gap at the bottom)
/// with a scale of ticks round it, an amber arc that sweeps to the score
/// and ends in a bright tip, and the number inside.
struct ScoreGauge: View {
  let score: Int
  var lineWidth: CGFloat = 10
  @State private var fill: Double = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// The same sweep and start as the icon: 78% of the circle, gap at lower left.
  nonisolated static let span = 0.78
  nonisolated static let startDegrees = 111.6

  var body: some View {
    GeometryReader { proxy in
      let size = min(proxy.size.width, proxy.size.height)
      ZStack {
        Ticks(lineWidth: lineWidth)
          .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        Group {
          Circle()
            .trim(from: 0, to: Self.span)
            .stroke(Color.well, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
          Circle()
            .trim(from: 0, to: Self.span * fill)
            .stroke(AngularGradient(colors: [Color.measure.opacity(0.55), Color.measure], center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(360 * Self.span)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        .rotationEffect(.degrees(Self.startDegrees))
        .padding(lineWidth * 1.9)
        ArcDot(fraction: fill, lineWidth: lineWidth)
          .fill(Color.measure)
          .shadow(color: Color.measure.opacity(0.7), radius: lineWidth * 0.8)
          .padding(lineWidth * 1.9)
        VStack(spacing: 0) {
          Text("\(score)")
            .font(.readout(size * 0.34))
            .contentTransition(.numericText(value: Double(score)))
            .accessibilityIdentifier("overall-score")
          Text("of 100").eyebrow()
        }
      }
      .frame(width: size, height: size)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .aspectRatio(1, contentMode: .fit)
    .onAppear { reveal() }
    .onChange(of: score) { reveal() }
    .sensoryFeedback(.success, trigger: score)
    .accessibilityElement(children: .contain)
  }

  private func reveal() {
    guard !reduceMotion else { fill = Double(score) / 100; return }
    fill = 0
    withAnimation(.spring(duration: 1.1, bounce: 0.12)) { fill = Double(score) / 100 }
  }
}

/// The gauge's scale: a tick every 5 points, longer every 25, just outside the arc.
private struct Ticks: Shape {
  let lineWidth: CGFloat

  func path(in rect: CGRect) -> Path {
    let radius = min(rect.width, rect.height) / 2
    let center = CGPoint(x: rect.midX, y: rect.midY)
    var path = Path()
    for step in 0...20 {
      let angle = (ScoreGauge.startDegrees + 360 * ScoreGauge.span * Double(step) / 20) * .pi / 180
      let outer = radius - lineWidth * 0.2
      let inner = outer - (step % 5 == 0 ? lineWidth * 0.9 : lineWidth * 0.5)
      path.move(to: CGPoint(x: center.x + inner * cos(angle), y: center.y + inner * sin(angle)))
      path.addLine(to: CGPoint(x: center.x + outer * cos(angle), y: center.y + outer * sin(angle)))
    }
    return path
  }
}

/// The bright tip at the end of the filled arc; animatable so it travels with it.
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
    let size = lineWidth * 0.55
    return Path(ellipseIn: CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size))
  }
}
