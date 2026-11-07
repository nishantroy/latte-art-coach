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
      }
      Tab("Beans", systemImage: "bag", value: .beans) {
        NavigationStack(path: $beansPath) { BeansView().routes() }
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
      case .pour(let pour): PourDetailView(pour: pour)
      case .bean(let bean): BeanDetailView(bean: bean)
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
    VStack(spacing: 20) {
      Spacer(minLength: 0)
      Image("IconArt")
        .resizable()
        .frame(width: 96, height: 96)
        .clipShape(.rect(cornerRadius: 22))
        .shadow(color: Color.espresso.opacity(0.18), radius: 12, y: 6)
        .accessibilityHidden(true)
      VStack(spacing: 6) {
        Text("Latte Art Coach").font(.display(.largeTitle))
        Text("Pour, snap it from above, and see what to change next time.")
          .multilineTextAlignment(.center)
          .foregroundStyle(.secondary)
      }
      if let progress = progressLine {
        Label(progress, systemImage: "chart.line.uptrend.xyaxis")
          .font(.subheadline)
          .foregroundStyle(Color.espresso)
          .card()
          .accessibilityIdentifier("progress-line")
      }
      Spacer(minLength: 0)
      VStack(alignment: .leading, spacing: 10) {
        Text("What did you pour?").font(.display(.title3))
        PatternPicker(selection: $pattern)
      }
      VStack(spacing: 12) {
        if LiveCamera.isAvailable {
          Button {
            showingCamera = true
          } label: {
            Label("Take a photo", systemImage: "camera.fill").frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
        }
        PhotosPicker(selection: $pickerItem, matching: .images) {
          Label("Choose a photo", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
      }
      .controlSize(.large)
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 16)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.milk)
    .overlay {
      if case .analyzing = model.state {
        ZStack {
          Color.milk.opacity(0.85).ignoresSafeArea()
          ProgressView("Analyzing your pour…")
        }
      }
    }
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
        RateFirstView(photo: photo, analysis: analysis, pour: pour, onReveal: { model.reveal() })
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
