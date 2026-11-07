import LatteCore
import SwiftUI

/// A 1–10 row. Tapping the current rating clears it.
struct RatingRow: View {
  @Binding var rating: Int?

  var body: some View {
    HStack(spacing: 4) {
      ForEach(1...10, id: \.self) { value in
        Button {
          rating = rating == value ? nil : value
        } label: {
          Text("\(value)")
            .font(.number(17))
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(value == rating ? Color.crema : Color.crema.opacity(0.12), in: .rect(cornerRadius: 10))
            .foregroundStyle(value == rating ? Color.white : Color.espresso)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rating-\(value)")
        .accessibilityAddTraits(value == rating ? .isSelected : [])
      }
    }
    .sensoryFeedback(.selection, trigger: rating)
  }
}

/// Before the score is shown: the photo and "How would you rate it?".
/// Rating first keeps the user's opinion independent of the app's number,
/// which is what makes ratings useful for tuning the score.
struct RateFirstView: View {
  let photo: UIImage
  let analysis: PourAnalysis
  @Bindable var pour: Pour
  let onReveal: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        PourPhotoView(photo: photo, analysis: analysis, showOverlay: false)
        VStack(alignment: .leading, spacing: 6) {
          Text("How would you rate it?").font(.display(.title2))
          Text("Give your \(analysis.pattern.noun) a score out of 10 before you see the app's. Your own take, given first, is what tunes the scoring.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        RatingRow(rating: $pour.rating)
        Button(action: onReveal) {
          Text(pour.rating == nil ? "Rate it to see the score" : "See the score").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(pour.rating == nil)
        .accessibilityIdentifier("reveal")
        Button("Skip rating", action: onReveal)
          .frame(maxWidth: .infinity)
          .foregroundStyle(.secondary)
      }
      .padding()
    }
    .background(Color.milk)
    .onChange(of: pour.rating) { try? pour.modelContext?.save() }
  }
}
