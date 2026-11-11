import LatteCore
import PhotosUI
import SwiftData
import SwiftUI

/// Three tabs: Pour (score a new one), History and Beans. Each keeps its own
/// navigation, so back always goes where you came from.
struct ContentView: View {
  enum AppTab: Hashable { case pour, history, beans }

  @Environment(\.modelContext) private var context
  @State private var model = CoachModel()
  @State private var tab: AppTab = .pour
  @State private var pourPath: [Route] = []
  @State private var historyPath: [Route] = []
  @State private var beansPath: [Route] = []
  // One per tab: a pour can be a row in History and in a bag at once.
  @Namespace private var historyZoom
  @Namespace private var beansZoom

  var body: some View {
    TabView(selection: $tab) {
      Tab("Pour", systemImage: "cup.and.saucer.fill", value: .pour) {
        NavigationStack(path: $pourPath) {
          StartView { pourPath.append(.score) }
            .routes()
        }
        .environment(\.goHome, GoHomeAction { pourPath.removeAll() })
      }
      Tab("History", systemImage: "chart.line.uptrend.xyaxis", value: .history) {
        NavigationStack(path: $historyPath) { HistoryView().routes() }
          .environment(\.zoomSpace, historyZoom)
      }
      Tab("Beans", systemImage: "bag", value: .beans) {
        NavigationStack(path: $beansPath) { BeansView().routes() }
          .environment(\.zoomSpace, beansZoom)
      }
    }
    .tint(.crema)
    .environment(model)
    .onAppear { model.context = context }
    // Leaving the scoring flow (back, or "Pour another") starts fresh.
    .onChange(of: pourPath) { _, path in
      if !path.contains(.score) { model.reset() }
    }
  }
}

extension View {
  /// Every screen any tab can push.
  func routes() -> some View {
    navigationDestination(for: Route.self) { route in
      switch route {
      case .score: ScoreFlowView()
      case .pour(let pour): PourDetailView(pour: pour).zoomDestination(pour.persistentModelID)
      case .bean(let bean): BeanDetailView(bean: bean).zoomDestination(bean.persistentModelID)
      }
    }
  }
}

/// The Pour tab's first screen: pick the pattern, then take or choose a photo.
struct StartView: View {
  /// Called once a photo is scored and ready to rate.
  let onScored: () -> Void
  @Environment(CoachModel.self) private var model
  @State private var pickerItem: PhotosPickerItem?
  @State private var showingCamera = false
  @State private var failure: String?
  @AppStorage("pattern") private var pattern: Pattern = .tulip
  @AppStorage("historyPattern") private var historyPattern: Pattern = .tulip
  @Query(sort: \Pour.date) private var pours: [Pour]

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        Text("Lattelier").font(.system(.largeTitle, weight: .bold))
        Spacer()
        if let progress = progressLine {
          Label(progress, systemImage: "chart.line.uptrend.xyaxis")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityIdentifier("progress-line")
        }
      }
      Spacer(minLength: 12)
      CupHero(pattern: pattern)
        .frame(maxWidth: 280)
        .padding(.horizontal, 24)
        .contentShape(.circle)
        .gesture(DragGesture(minimumDistance: 20).onEnded { drag in
          let all = Pattern.allCases, i = all.firstIndex(of: pattern) ?? 0
          let step = drag.translation.width < -40 ? 1 : drag.translation.width > 40 ? -1 : 0
          let next = min(max(i + step, 0), all.count - 1)
          if next != i { withAnimation(.glide) { pattern = all[next] } }
        })
        .accessibilityLabel("\(pattern.displayName), swipe to change")
      Text("Pour, then snap it from straight above.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.top, 24)
      Spacer(minLength: 12)
      SlidingPicker(options: Pattern.allCases, selection: $pattern) { option, _ in
        HStack(spacing: 6) {
          PatternGlyph(pattern: option).frame(width: 16, height: 16)
          Text(option.displayName).font(.subheadline.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(option.displayName)
      }
      .padding(.bottom, 28)
      captureControls
    }
    .padding(.horizontal, 20)
    .padding(.top, 8)
    .padding(.bottom, 20)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.milk)
    .overlay {
      if isAnalyzing { AnalyzingView(pattern: pattern).transition(.opacity) }
    }
    .animation(.settle, value: isAnalyzing)
    .toolbar(.hidden, for: .navigationBar)
    .alert("Couldn't score this one", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(failure ?? "")
    }
    .onChange(of: pickerItem) { _, item in
      guard let item else { return }
      pickerItem = nil
      Task {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
          failure = "Couldn't open that photo."
          return
        }
        await score(data)
      }
    }
    .fullScreenCover(isPresented: $showingCamera) {
      LiveCameraView(pattern: pattern) { data in
        showingCamera = false
        if let data { Task { await score(data) } }
      }
    }
  }

  /// A shutter in the middle, the library to its left, like the Camera app.
  /// Without a camera (the Simulator), the shutter opens the library.
  private var captureControls: some View {
    HStack {
      if LiveCamera.isAvailable {
        PhotosPicker(selection: $pickerItem, matching: .images) {
          Image(systemName: "photo.on.rectangle")
            .font(.title3.weight(.medium))
            .frame(width: 56, height: 56)
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .accessibilityLabel("Choose a photo")
        Spacer()
        Button { showingCamera = true } label: { Shutter() }
          .buttonStyle(.press)
          .accessibilityLabel("Take a photo")
        Spacer()
        Color.clear.frame(width: 56, height: 56)
      } else {
        Spacer()
        PhotosPicker(selection: $pickerItem, matching: .images) { Shutter(symbol: "photo.on.rectangle") }
          .buttonStyle(.press)
          .accessibilityLabel("Choose a photo")
        Spacer()
      }
    }
    .foregroundStyle(Color.espresso)
    .sensoryFeedback(.impact(weight: .medium), trigger: showingCamera) { _, now in now }
  }

  private var isAnalyzing: Bool {
    if case .analyzing = model.state { true } else { false }
  }

  private func score(_ data: Data) async {
    await model.analyze(data, as: pattern)
    switch model.state {
    case .rating:
      // History opens on what you just poured.
      historyPattern = pattern
      onScored()
    case .failed(let message):
      failure = message
      model.reset()
    default: break
    }
  }

  /// How the chosen pattern is going, from history.
  private var progressLine: String? {
    guard let summary = ProgressSummary(records: pours.map(\.record), pattern: pattern) else { return nil }
    let name = summary.pourCount == 1 ? pattern.noun : "\(pattern.noun)s"
    let recent = Int(summary.recentAverageScore.rounded())
    guard let earlier = summary.earlierAverageScore.map({ Int($0.rounded()) }) else {
      return "\(summary.pourCount) \(name) so far, averaging \(recent)"
    }
    let direction = recent > earlier ? "up from" : recent < earlier ? "down from" : "same as"
    return "Last \(summary.recentCount) \(pattern.noun)s: \(recent), \(direction) \(earlier) before"
  }
}

/// While a photo is scored: the pattern's drawing breathing on a card.
private struct AnalyzingView: View {
  let pattern: Pattern
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var spin = false

  var body: some View {
    ZStack {
      Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
      VStack(spacing: 28) {
        ZStack {
          CupHero(pattern: pattern).frame(width: 150, height: 150)
          // A sweep round the cup, like a scanner.
          Circle()
            .trim(from: 0, to: 0.25)
            .stroke(AngularGradient(colors: [Color.measure.opacity(0), Color.measure], center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(90)),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: 178, height: 178)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .opacity(reduceMotion ? 0 : 1)
        }
        VStack(spacing: 6) {
          Text("Reading your \(pattern.noun)…").font(.headline)
          Text("Finding the cup, the foam and the shape").font(.footnote).foregroundStyle(.secondary)
        }
      }
    }
    .accessibilityElement(children: .combine)
    .onAppear {
      guard !reduceMotion else { return }
      withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = true }
    }
  }
}

/// Rate the new pour, then see its score. Back (or "Pour another") returns
/// to the start; the pour is already saved.
struct ScoreFlowView: View {
  @Environment(CoachModel.self) private var model
  @Environment(\.goHome) private var goHome
  @AppStorage("pattern") private var pattern: Pattern = .tulip
  @AppStorage("historyPattern") private var historyPattern: Pattern = .tulip

  var body: some View {
    Group {
      switch model.state {
      case .rating(let photo, let analysis, let pour):
        RateFirstView(photo: photo, analysis: analysis, pour: pour, onReveal: { withAnimation(.settle) { model.reveal() } })
      case .result(let photo, let analysis, let pour):
        ResultView(
          photo: photo, analysis: analysis, pour: pour,
          onRescore: { newPattern in
            pattern = newPattern
            historyPattern = newPattern
            Task { await model.rescore(as: newPattern) }
          },
          onAdjustCup: { cup in Task { await model.adjustCup(cup) } },
          onAgain: { goHome() })
      case .failed(let message):
        ContentUnavailableView("Couldn't score this one", systemImage: "cup.and.saucer", description: Text(message))
      case .idle, .analyzing:
        ProgressView()
      }
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
  }

  private var title: String {
    switch model.state {
    case .rating(_, let analysis, _), .result(_, let analysis, _): "Your \(analysis.pattern.noun)"
    default: ""
    }
  }
}
