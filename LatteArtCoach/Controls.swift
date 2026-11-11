import SwiftUI

/// A number set by sliding a ruler under a fixed needle, like a scale's
/// dial: a tick (and a haptic tick) per step, whole units longer, and a
/// label about every 100 points. Empty until the user moves it.
struct RulerDial: View {
  let title: String
  let unit: String
  @Binding var value: Double?
  let range: ClosedRange<Double>
  let step: Double
  /// Where the ruler rests while the value is empty.
  let typical: Double

  @State private var position: Int?
  @State private var phase: ScrollPhase = .idle

  private var count: Int { Int(((range.upperBound - range.lowerBound) / step).rounded()) + 1 }
  private func index(of v: Double) -> Int { min(max(Int(((v - range.lowerBound) / step).rounded()), 0), count - 1) }
  private func value(at i: Int) -> Double { range.lowerBound + Double(i) * step }
  private var perUnit: Int { max(1, Int((1 / step).rounded())) }
  /// Ticks between labels: every unit when steps are fine (grams to 0.1),
  /// every five units otherwise.
  private var perLabel: Int { step < 0.5 ? perUnit : perUnit * 5 }

  var body: some View {
    VStack(spacing: 6) {
      readout
      // VoiceOver adjusts the readout instead (swipe up or down).
      ruler.accessibilityHidden(true)
    }
    .onAppear { position = index(of: value ?? typical) }
    .onChange(of: value) { _, new in
      // Cleared or set elsewhere: move the ruler without counting it as a turn.
      if phase == .idle, let new { position = index(of: new) }
    }
  }

  private var readout: some View {
    VStack(spacing: 6) {
      HStack {
        Text(title).eyebrow()
        Spacer()
        if value != nil {
          Button("Clear") { withAnimation(.settle) { value = nil } }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
      }
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(value.map { $0.formatted(.number.precision(.fractionLength(step < 1 ? 1 : 0))) } ?? "–")
          .font(.readout(40))
          .contentTransition(.numericText(value: value ?? 0))
          .foregroundStyle(value == nil ? Color.secondary : Color.espresso)
        Text(unit).font(.title3.weight(.medium)).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
      .animation(.snappy(duration: 0.15), value: value)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(value.map { "\($0.formatted()) \(unit)" } ?? "not set")
    .accessibilityAdjustableAction { direction in
      let current = value ?? typical
      value = min(max(current + (direction == .increment ? step : -step), range.lowerBound), range.upperBound)
      position = index(of: value!)
    }
  }

  private var ruler: some View {
    GeometryReader { proxy in
      ScrollView(.horizontal) {
        LazyHStack(spacing: 0) {
          ForEach(0..<count, id: \.self) { i in
            let major = i % perUnit == 0, label = i % perLabel == 0
            let half = perUnit >= 10 && i % (perUnit / 2) == 0
            VStack(spacing: 4) {
              Capsule()
                .fill(Color.espresso.opacity(major ? 0.45 : 0.2))
                .frame(width: major ? 1.5 : 1, height: label ? 22 : major ? 14 : half ? 11 : 7)
                .frame(height: 22, alignment: .bottom)
              Text(label ? value(at: i).formatted(.number.precision(.fractionLength(0))) : " ")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
                .frame(width: 10)
            }
            .frame(width: 10)
          }
        }
        .scrollTargetLayout()
      }
      .scrollIndicators(.hidden)
      .scrollTargetBehavior(.viewAligned)
      .scrollPosition(id: $position, anchor: .center)
      .contentMargins(.horizontal, proxy.size.width / 2 - 5, for: .scrollContent)
      .onScrollPhaseChange { _, new in phase = new }
      .onChange(of: position) { _, i in
        guard let i, phase != .idle else { return }
        value = value(at: i)
      }
      // Fade the ends, so the scale reads as a dial turning under the needle.
      .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.25),
                                   .init(color: .black, location: 0.75), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing))
      .overlay(alignment: .top) {
        Capsule().fill(Color.crema).frame(width: 3, height: 30).offset(y: -4)
      }
    }
    .frame(height: 44)
    .sensoryFeedback(.selection, trigger: position)
    .opacity(value == nil ? 0.6 : 1)
  }
}

/// A selectable capsule, for flavors, milk and other picks from a list.
struct Chip: View {
  let text: String
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(text)
        .font(.subheadline.weight(selected ? .semibold : .regular))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .foregroundStyle(selected ? Color.white : Color.espresso)
        .background(selected ? Color.crema : Color.well, in: .capsule)
    }
    .buttonStyle(.press)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// Lays children out in rows, wrapping like words.
struct FlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
    let height = rows.last.map { $0.y + $0.height } ?? 0
    return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for row in arrange(width: bounds.width, subviews: subviews) {
      var x = bounds.minX
      for i in row.indices {
        let size = subviews[i].sizeThatFits(.unspecified)
        subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
    }
  }

  private func arrange(width: CGFloat, subviews: Subviews) -> [(indices: [Int], y: CGFloat, height: CGFloat, width: CGFloat)] {
    var rows: [(indices: [Int], y: CGFloat, height: CGFloat, width: CGFloat)] = []
    var current: [Int] = [], x: CGFloat = 0, y: CGFloat = 0, height: CGFloat = 0
    for (i, view) in subviews.enumerated() {
      let size = view.sizeThatFits(.unspecified)
      if !current.isEmpty, x + size.width > width {
        rows.append((current, y, height, x - spacing))
        y += height + spacing
        current = []; x = 0; height = 0
      }
      current.append(i)
      x += size.width + spacing
      height = max(height, size.height)
    }
    if !current.isEmpty { rows.append((current, y, height, x - spacing)) }
    return rows
  }
}
