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

extension EnvironmentValues {
  /// Shared by a tab's rows and the screens they open, so a screen zooms
  /// out of the row that opened it.
  @Entry var zoomSpace: Namespace.ID?
}

extension View {
  /// The row a screen zooms out of.
  func zoomSource(_ id: some Hashable) -> some View { modifier(ZoomSource(id: AnyHashable(id))) }
  /// A screen that zooms out of the row with the same id.
  func zoomDestination(_ id: some Hashable) -> some View { modifier(ZoomDestination(id: AnyHashable(id))) }
}

private struct ZoomSource: ViewModifier {
  let id: AnyHashable
  @Environment(\.zoomSpace) private var space

  func body(content: Content) -> some View {
    if let space { content.matchedTransitionSource(id: id, in: space) } else { content }
  }
}

private struct ZoomDestination: ViewModifier {
  let id: AnyHashable
  @Environment(\.zoomSpace) private var space

  func body(content: Content) -> some View {
    if let space { content.navigationTransition(.zoom(sourceID: id, in: space)) } else { content }
  }
}
