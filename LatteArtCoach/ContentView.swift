import LatteCore
import SwiftUI

struct ContentView: View {
  var body: some View {
    NavigationStack {
      VStack(spacing: 16) {
        Image(systemName: "cup.and.saucer.fill")
          .font(.system(size: 56))
          .foregroundStyle(.brown)
        Text("Latte Art Coach")
          .font(.largeTitle.bold())
        Text("Pour a \(Pattern.heart.displayName.lowercased()), snap a photo, and get a score with tips for your next pour.")
          .multilineTextAlignment(.center)
          .foregroundStyle(.secondary)
      }
      .padding(24)
    }
  }
}

#Preview {
  ContentView()
}
