import LatteCore
import PhotosUI
import SwiftUI

/// Pick or take a photo → analyze → results.
struct ContentView: View {
  @State private var model = CoachModel()
  @State private var pickerItem: PhotosPickerItem?
  @State private var showingCamera = false
  @AppStorage("pattern") private var pattern: Pattern = .tulip

  var body: some View {
    NavigationStack {
      Group {
        switch model.state {
        case .idle:
          start
        case .analyzing:
          ProgressView("Analyzing your pour…")
        case .result(let photo, let analysis):
          ResultView(
            photo: photo, analysis: analysis,
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
    }
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
    VStack(spacing: 20) {
      Spacer()
      Image(systemName: "cup.and.saucer.fill")
        .font(.system(size: 56))
        .foregroundStyle(.brown)
      Text("Latte Art Coach")
        .font(.largeTitle.bold())
      Text("Pour a heart, tulip or rosetta, take a photo from above, and get a score with tips for your next pour.")
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
      Spacer()
      VStack(alignment: .leading, spacing: 8) {
        Text("What did you pour?").font(.headline)
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
      .tint(.brown)
    }
    .padding(24)
  }

  private var resultTitle: String {
    if case .result(_, let analysis) = model.state { return "Your \(analysis.pattern.noun)" }
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
        .tint(.brown)
    }
  }
}

#Preview {
  ContentView()
}
