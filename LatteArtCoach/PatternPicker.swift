import LatteCore
import SwiftUI

/// Heart / Tulip / Rosetta segmented control.
struct PatternPicker: View {
  @Binding var selection: Pattern

  var body: some View {
    Picker("Pattern", selection: $selection) {
      ForEach(Pattern.allCases) { Text($0.displayName).tag($0) }
    }
    .pickerStyle(.segmented)
  }
}
