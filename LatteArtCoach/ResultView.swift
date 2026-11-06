import LatteCore
import SwiftUI

struct ResultView: View {
  let photo: UIImage
  let analysis: PourAnalysis
  let onRescore: (Pattern) -> Void
  let onAgain: () -> Void
  @State private var showOverlay = true

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        PatternPicker(selection: Binding(get: { analysis.pattern }, set: onRescore))
          .accessibilityLabel("Scored as")
        scoreHeader
        if let note = resemblanceNote {
          Label(note, systemImage: "info.circle")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("resemblance-note")
        }
        PourPhotoView(photo: photo, analysis: analysis, showOverlay: showOverlay)
          .onTapGesture { showOverlay.toggle() }
          .accessibilityLabel("Photo of your pour, tap to toggle the overlay")
        tips
        breakdown
        Text("Analyzed on device in \(analysis.duration.formatted(.units(allowed: [.milliseconds])))")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("analysis-duration")
        Button(action: onAgain) {
          Label("Score another pour", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.brown)
      }
      .padding()
    }
  }

  private var scoreHeader: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text("\(analysis.score.overall)")
        .font(.system(size: 64, weight: .bold, design: .rounded))
        .accessibilityIdentifier("overall-score")
      VStack(alignment: .leading) {
        Text(verdict).font(.title3.bold())
        Text("out of 100").foregroundStyle(.secondary)
      }
    }
  }

  private var verdict: String {
    switch analysis.score.overall {
    case 90...: "Excellent"
    case 80..<90: "Good \(analysis.pattern.noun)"
    case 65..<80: "Getting there"
    default: "Keep practicing"
    }
  }

  /// Shown when the foam clearly reads as a different pattern than the one
  /// being scored, e.g. tulip stacks that came out as rosetta leaves.
  private var resemblanceNote: String? {
    guard let looks = analysis.resembles, looks != analysis.pattern else { return nil }
    return "This reads more like a \(looks.noun). Tap \(looks.displayName) above to score it as one."
  }

  private var tips: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Next pour").font(.headline)
      ForEach(analysis.tips) { tip in
        VStack(alignment: .leading, spacing: 4) {
          Text(tip.title).font(.subheadline.bold())
          Text(tip.detail).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.brown.opacity(0.1), in: .rect(cornerRadius: 12))
      }
    }
  }

  private var breakdown: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Breakdown").font(.headline)
      ForEach(PourScore.Component.allCases, id: \.self) { component in
        let label = component.label(for: analysis.pattern)
        let value = analysis.score.components[component] ?? 0
        HStack {
          Text(label).font(.subheadline).frame(width: 110, alignment: .leading)
          ProgressView(value: value).tint(value >= 0.7 ? .green : value >= 0.4 ? .orange : .red)
          Text("\(Int((value * 100).rounded()))").font(.subheadline.monospacedDigit()).frame(width: 32, alignment: .trailing)
        }
      }
    }
  }
}

extension PourScore.Component {
  func label(for pattern: Pattern) -> String {
    switch self {
    case .centering: "Centering"
    case .symmetry: "Symmetry"
    case .contrast: "Contrast"
    case .proportion: "Size"
    case .texture: "Milk texture"
    case .definition:
      switch pattern {
      case .heart: "Heart shape"
      case .tulip: "Tulip stacks"
      case .rosetta: "Leaves"
      }
    }
  }
}

/// The photo cropped around the cup, with the foam mask, cup outline and
/// pattern axis drawn over it.
struct PourPhotoView: View {
  let photo: UIImage
  let analysis: PourAnalysis
  let showOverlay: Bool

  var body: some View {
    let crop = cropRect
    GeometryReader { proxy in
      let scale = proxy.size.width / crop.width
      ZStack(alignment: .topLeading) {
        imageLayer(Image(uiImage: photo), crop: crop, scale: scale)
        if showOverlay {
          if let overlay = analysis.foamOverlay.makeCGImage() {
            imageLayer(Image(decorative: overlay, scale: 1), crop: crop, scale: scale)
          }
          Canvas { context, _ in
            func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: (x - crop.minX) * scale, y: (y - crop.minY) * scale) }
            let e = analysis.cup
            var outline = Path()
            for step in 0...120 {
              let t = Double(step) / 120 * 2 * .pi
              let q = e.point(unitX: cos(t), unitY: sin(t))
              step == 0 ? outline.move(to: p(q.x, q.y)) : outline.addLine(to: p(q.x, q.y))
            }
            context.stroke(outline, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            var axis = Path()
            axis.move(to: p(analysis.stem.x, analysis.stem.y))
            axis.addLine(to: p(analysis.tip.x, analysis.tip.y))
            context.stroke(axis, with: .color(.yellow), lineWidth: 2)
            let tip = p(analysis.tip.x, analysis.tip.y)
            context.fill(Path(ellipseIn: CGRect(x: tip.x - 4, y: tip.y - 4, width: 8, height: 8)), with: .color(.yellow))
          }
        }
      }
      // The layers are larger than the view; pin them to the top-left so the
      // offsets above line the crop up exactly (the default would center them).
      .frame(width: proxy.size.width, height: proxy.size.width, alignment: .topLeading)
      .clipped()
    }
    .aspectRatio(1, contentMode: .fit)
    .clipShape(.rect(cornerRadius: 16))
  }

  /// A square around the cup, in analysis-image pixels.
  private var cropRect: CGRect {
    let e = analysis.cup
    let side = min(Double(min(analysis.imageWidth, analysis.imageHeight)), e.semiMajor * 2.3)
    let x = min(max(0, e.centerX - side / 2), Double(analysis.imageWidth) - side)
    let y = min(max(0, e.centerY - side / 2), Double(analysis.imageHeight) - side)
    return CGRect(x: x, y: y, width: side, height: side)
  }

  /// Draws an image that spans the analysis frame, shifted so `crop` fills the view.
  private func imageLayer(_ image: Image, crop: CGRect, scale: Double) -> some View {
    image
      .resizable()
      .frame(width: Double(analysis.imageWidth) * scale, height: Double(analysis.imageHeight) * scale)
      .offset(x: -crop.minX * scale, y: -crop.minY * scale)
  }
}
