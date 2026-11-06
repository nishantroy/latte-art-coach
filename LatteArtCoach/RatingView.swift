import SwiftUI

/// "How would you rate it?" 1–10. Tapping the current rating clears it.
struct RatingView: View {
  @Binding var rating: Int?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Your rating").font(.headline)
      Text("How good does this pour look to you? Your ratings show where the score is off, and help tune it.")
        .font(.footnote)
        .foregroundStyle(.secondary)
      HStack(spacing: 4) {
        ForEach(1...10, id: \.self) { value in
          Button {
            rating = rating == value ? nil : value
          } label: {
            Text("\(value)")
              .font(.subheadline.monospacedDigit().bold())
              .frame(maxWidth: .infinity, minHeight: 36)
              .background(value == rating ? Color.brown : Color.brown.opacity(0.12), in: .rect(cornerRadius: 8))
              .foregroundStyle(value == rating ? Color.white : Color.primary)
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("rating-\(value)")
          .accessibilityAddTraits(value == rating ? .isSelected : [])
        }
      }
    }
  }
}
