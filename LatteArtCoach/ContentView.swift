import LatteCore
import PhotosUI
import SwiftData
import SwiftUI

/// Pick or take a photo → analyze → results.
struct ContentView: View {
  @Environment(\.modelContext) private var context
  @State private var model = CoachModel()
  @State private var pickerItem: PhotosPickerItem?
  @State private var showingCamera = false
  @State private var path: [Route] = []
  @AppStorage("pattern") private var pattern: Pattern = .tulip
  @Query(sort: \Pour.date) private var pours: [Pour]

  var body: some View {
    NavigationStack(path: $path) {
      Group {
        switch model.state {
        case .idle:
          start
        case .analyzing:
          ProgressView("Analyzing your pour…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.milk)
        case .rating(let photo, let analysis, let pour):
          RateFirstView(photo: photo, analysis: analysis, pour: pour, onReveal: { model.reveal() })
        case .result(let photo, let analysis, let pour):
          ResultView(
            photo: photo, analysis: analysis, pour: pour,
            onRescore: { newPattern in
              pattern = newPattern
              Task { await model.rescore(as: newPattern) }
            },
            onAgain: { model.reset() })
        case .failed(let message):
          failure(message)
        }
      }
      .navigationTitle(resultTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if !isAnalyzing {
          ToolbarItem(placement: .topBarLeading) {
            NavigationLink(value: Route.history) {
              Label("History", systemImage: "clock.arrow.circlepath")
            }
            .accessibilityIdentifier("history")
          }
        }
        // Every screen past the start one can go straight home; the pour is
        // already saved, so nothing is lost.
        if showsDone { DoneButton() }
      }
      .navigationDestination(for: Route.self) { route in
        switch route {
        case .history: HistoryView()
        case .pour(let pour): PourDetailView(pour: pour)
        }
      }
    }
    .environment(\.goHome, GoHomeAction {
      path.removeAll()
      model.reset()
    })
    .onAppear { model.context = context }
    .onChange(of: pickerItem) { _, item in
      guard let item else { return }
      pickerItem = nil
      Task {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
          model.fail("Couldn't open that photo.")
          return
        }
        await model.analyze(data, as: pattern)
      }
    }
    .fullScreenCover(isPresented: $showingCamera) {
      CameraPicker { data in
        showingCamera = false
        if let data { Task { await model.analyze(data, as: pattern) } }
      }
      .ignoresSafeArea()
    }
  }

  private var start: some View {
    VStack(spacing: 22) {
      Spacer(minLength: 8)
      Image("IconArt")
        .resizable()
        .frame(width: 112, height: 112)
        .clipShape(.rect(cornerRadius: 26))
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
      Spacer(minLength: 8)
      VStack(alignment: .leading, spacing: 10) {
        Text("What did you pour?").font(.display(.title3))
        PatternPicker(selection: $pattern)
      }
      VStack(spacing: 12) {
        if CameraPicker.isAvailable {
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
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.milk)
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

  private var showsDone: Bool {
    switch model.state {
    case .rating, .result, .failed: true
    case .idle, .analyzing: false
    }
  }

  private var isAnalyzing: Bool {
    if case .analyzing = model.state { return true }
    return false
  }

  private var resultTitle: String {
    if case .result(_, let analysis, _) = model.state { return "Your \(analysis.pattern.noun)" }
    if case .rating(_, let analysis, _) = model.state { return "Your \(analysis.pattern.noun)" }
    return ""
  }

  private func failure(_ message: String) -> some View {
    ContentUnavailableView {
      Label("Couldn't score this one", systemImage: "cup.and.saucer")
    } description: {
      Text(message)
    } actions: {
      Button("Try another photo") { model.reset() }
        .buttonStyle(.borderedProminent)
    }
  }
}

#Preview {
  ContentView()
}
