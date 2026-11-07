import SwiftData
import SwiftUI

@main
struct LatteArtCoachApp: App {
  init() {
    Theme.configure()
    // UI tests start from a fresh install's state.
    if ProcessInfo.processInfo.arguments.contains("-uitest") {
      UserDefaults.standard.removeObject(forKey: "pattern")
    }
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    // UI tests start from an empty history that isn't saved.
    .modelContainer(for: [Pour.self, Bean.self], inMemory: ProcessInfo.processInfo.arguments.contains("-uitest"))
  }
}
