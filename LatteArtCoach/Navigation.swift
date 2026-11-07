import SwiftUI

/// Screens pushed inside a tab's navigation stack.
enum Route: Hashable {
  /// Rating and scoring the photo just taken.
  case score
  case pour(Pour)
  case bean(Bean)
}

/// Ends the scoring flow: back to the Pour tab's start screen.
struct GoHomeAction {
  let action: @MainActor () -> Void
  @MainActor func callAsFunction() { action() }
}

extension EnvironmentValues {
  @Entry var goHome = GoHomeAction(action: {})
}
