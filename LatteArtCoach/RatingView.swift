import LatteCore
import SwiftUI

/// A 1–10 dial: tap a number or drag along it; each step ticks. Tapping the
/// current rating clears it.
struct RatingRow: View {
  @Binding var rating: Int?

  var body: some View {
    SlidingPicker(options: Array(1...10), selection: $rating, allowsNone: true, accent: true,
                  identifier: { "rating-\($0)" }) { value, on in
      Text("\(value)").font(on ? .number(17) : .system(size: 16, weight: .medium).monospacedDigit())
    }
  }
}

/// The big number above a rating dial, with a word for it.
struct RatingReadout: View {
  let rating: Int?

  var body: some View {
    VStack(spacing: 2) {
      Text(rating.map(String.init) ?? "–")
        .font(.readout(64))
        .contentTransition(.numericText(value: Double(rating ?? 0)))
        .foregroundStyle(rating == nil ? Color.secondary : Color.espresso)
      Text(Self.word(rating)).eyebrow()
    }
    .frame(maxWidth: .infinity)
    .animation(.glide, value: rating)
    .accessibilityHidden(true)
  }

  static func word(_ rating: Int?) -> String {
    guard let rating else { return "Slide to rate" }
    switch rating {
    case ...3: return "Needs work"
    case 4...5: return "Okay"
    case 6...7: return "Good"
    case 8...9: return "Great"
    default: return "Perfect"
    }
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
      VStack(spacing: 24) {
        PourPhotoView(photo: photo, analysis: analysis, showOverlay: false)
          .frame(maxWidth: 280)
          .shadow(color: .black.opacity(0.12), radius: 20, y: 10)
        VStack(spacing: 6) {
          Text("How would you rate it?").font(.display(.title2))
          Text("Your take first, before the app's. It's what tunes the scoring.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        RatingReadout(rating: pour.rating)
        RatingRow(rating: $pour.rating)
        VStack(spacing: 4) {
          Button(action: onReveal) {
            Text(pour.rating == nil ? "Rate it to see the score" : "See the score")
          }
          .buttonStyle(.primary)
          .disabled(pour.rating == nil)
          .accessibilityIdentifier("reveal")
          Button("Skip rating", action: onReveal)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
        }
      }
      .padding(20)
    }
    .background(Color.milk)
    .onChange(of: pour.rating) { try? pour.modelContext?.save() }
  }
}
