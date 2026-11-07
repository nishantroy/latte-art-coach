import LatteCore
import SwiftUI

struct ResultView: View {
  let photo: UIImage
  let analysis: PourAnalysis
  /// The saved pour, for the user's rating and drink log.
  let pour: Pour?
  let onRescore: (Pattern) -> Void
  /// Re-scores with a hand-placed cup outline; nil goes back to automatic.
  let onAdjustCup: (LatteCore.Ellipse?) -> Void
  /// Nil when showing a pour from history.
  let onAgain: (() -> Void)?
  @State private var showOverlay = true
  @State private var adjustingCup = false
  @State private var editingRating = false
  @State private var showingDetails = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        PourPhotoView(photo: photo, analysis: analysis, showOverlay: showOverlay)
          .onTapGesture { showOverlay.toggle() }
          .accessibilityLabel("Photo of your pour, tap to toggle the overlay")
        scoreHeader
        if let looks = resemblance {
          Button { onRescore(looks) } label: {
            Label("This reads more like a \(looks.noun). Score it as one", systemImage: "arrow.triangle.2.circlepath")
              .font(.subheadline)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.plain)
          .foregroundStyle(Color.crema)
          .card()
          .accessibilityIdentifier("resemblance-note")
        }
        CoachingSection(analysis: analysis, pour: pour).card()
        if let pour {
          DrinkLogCard(pour: pour).card()
          DialInCard(pour: pour, contrast: analysis.score.components[.contrast] ?? 1)
        }
        details.card()
        if let onAgain {
          Button(action: onAgain) {
            Label("Pour another", systemImage: "camera").frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .accessibilityIdentifier("pour-another")
        }
      }
      .padding()
    }
    .background(Color.milk)
    .sheet(isPresented: $adjustingCup) {
      CupAdjustView(photo: photo, analysis: analysis, isManual: pour?.manualCup != nil) { cup in onAdjustCup(cup) }
    }
    .sheet(isPresented: $editingRating) {
      if let pour {
        VStack(alignment: .leading, spacing: 14) {
          Text("Your rating").font(.display(.title3))
          RatingRow(rating: Binding(get: { pour.rating }, set: { pour.rating = $0; try? pour.modelContext?.save() }))
        }
        .padding(20)
        .presentationDetents([.height(170)])
        .presentationBackground(Color.milk)
      }
    }
  }

  private var scoreHeader: some View {
    HStack(spacing: 16) {
      ScoreGauge(score: analysis.score.overall).frame(width: 124, height: 124)
      VStack(alignment: .leading, spacing: 8) {
        Text(verdict).font(.display(.title2))
        if let pour {
          Button { editingRating = true } label: {
            Label(pour.rating.map { "You rated it \($0)/10" } ?? "Add your rating", systemImage: "pencil")
              .font(.subheadline)
          }
          .tint(.crema)
          .accessibilityIdentifier("your-rating")
        }
        Text(showOverlay ? "Tap the photo to hide what was measured" : "Tap the photo to show what was measured")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var verdict: String {
    switch analysis.score.overall {
    case 90...: "Excellent \(analysis.pattern.noun)"
    case 80..<90: "Good \(analysis.pattern.noun)"
    case 65..<80: "Getting there"
    default: "Keep practicing"
    }
  }

  /// A clearly different pattern than the one being scored, e.g. tulip
  /// stacks that came out as rosetta leaves.
  private var resemblance: Pattern? {
    guard let looks = analysis.resembles, looks != analysis.pattern else { return nil }
    return looks
  }

  /// The breakdown and the rarely used controls, folded away.
  private var details: some View {
    DisclosureGroup(isExpanded: $showingDetails) {
      VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(PourScore.Component.allCases, id: \.self) { component in
            let value = analysis.score.components[component] ?? 0
            HStack {
              Text(component.label(for: analysis.pattern)).font(.subheadline).frame(width: 116, alignment: .leading)
              ProgressView(value: value).tint(value >= 0.5 ? Color.measure : Color.weak)
              Text("\(Int((value * 100).rounded()))").font(.subheadline.monospacedDigit()).frame(width: 32, alignment: .trailing)
            }
          }
        }
        Divider()
        LabeledContent("Scored as") {
          Picker("Scored as", selection: Binding(get: { analysis.pattern }, set: { if $0 != analysis.pattern { onRescore($0) } })) {
            ForEach(Pattern.allCases) { Text($0.displayName).tag($0) }
          }
          .pickerStyle(.segmented)
          .frame(maxWidth: 230)
          .accessibilityIdentifier("scored-as")
        }
        .font(.subheadline)
        Button { adjustingCup = true } label: {
          Label("Cup outline wrong? Adjust it", systemImage: "circle.dashed").font(.subheadline)
        }
        .tint(.crema)
        .accessibilityIdentifier("adjust-cup")
        Text("Analyzed on this iPhone in \(analysis.duration.formatted(.units(allowed: [.milliseconds])))")
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("analysis-duration")
      }
      .padding(.top, 10)
    } label: {
      Text("Score details").font(.display(.title3)).foregroundStyle(Color.espresso)
    }
    .tint(.crema)
    .accessibilityIdentifier("score-details")
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
            context.stroke(axis, with: .color(.measure), lineWidth: 2.5)
            let tip = p(analysis.tip.x, analysis.tip.y)
            context.fill(Path(ellipseIn: CGRect(x: tip.x - 4, y: tip.y - 4, width: 8, height: 8)), with: .color(.measure))
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
