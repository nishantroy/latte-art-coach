import SwiftUI

/// Screens pushed on the main navigation stack.
enum Route: Hashable {
  case history
  case pour(Pour)
  case beans
  case bean(Bean)
}

/// Goes back to the start screen from anywhere.
struct GoHomeAction {
  let action: @MainActor () -> Void
  @MainActor func callAsFunction() { action() }
}

extension EnvironmentValues {
  @Entry var goHome = GoHomeAction(action: {})
}

/// "Done" at the top right: back to the start screen.
struct DoneButton: ToolbarContent {
  @Environment(\.goHome) private var goHome

  var body: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      Button("Done") { goHome() }
        .fontWeight(.semibold)
        .accessibilityIdentifier("done")
    }
  }
}
