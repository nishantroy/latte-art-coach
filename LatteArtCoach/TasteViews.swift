import LatteCore
import SwiftData
import SwiftUI

/// How the drink tasted: balance, a 1–5 rating, and flavors noticed.
/// Separate from the art score; it drives the dial-in advice and bean ratings.
struct TasteFields: View {
  @Bindable var pour: Pour
  @Environment(\.modelContext) private var context
  @State private var newNote = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      SlidingPicker(options: DrinkTaste.Balance.allCases,
                    selection: Binding(get: { pour.taste.balance }, set: { b in update { $0.balance = b } }),
                    allowsNone: true) { balance, _ in
        Text(balance.displayName).font(.subheadline.weight(.semibold))
      }
      .accessibilityIdentifier("taste-balance")

      HStack(spacing: 4) {
        ForEach(1...5, id: \.self) { star in
          let on = star <= (pour.drinkRating ?? 0)
          Button {
            withAnimation(.glide) { update { $0.rating = $0.rating == star ? nil : star } }
          } label: {
            Image(systemName: on ? "star.fill" : "star")
              .font(.system(size: 26, weight: .medium))
              .foregroundStyle(on ? Color.measure : Color.secondary.opacity(0.5))
              .symbolEffect(.bounce, value: on)
              .frame(width: 44, height: 44)
              .contentShape(.rect)
          }
          .buttonStyle(PressStyle(scale: 0.85))
          .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
          .accessibilityIdentifier("drink-\(star)")
        }
        Spacer()
        Text(["", "Didn't like it", "Meh", "Fine", "Good", "Loved it"][pour.drinkRating ?? 0])
          .font(.subheadline)
          .lineLimit(1)
          .foregroundStyle(.secondary)
          .contentTransition(.opacity)
      }
      .sensoryFeedback(.selection, trigger: pour.drinkRating)

      VStack(alignment: .leading, spacing: 10) {
        Text("Flavors you noticed").eyebrow()
        FlowLayout {
          ForEach(noteChoices, id: \.self) { note in
            Chip(text: note, selected: pour.tastedNotes.contains(note)) {
              withAnimation(.settle) {
                update { taste in
                  if let i = taste.notes.firstIndex(of: note) { taste.notes.remove(at: i) } else { taste.notes.append(note) }
                }
              }
            }
          }
        }
        .sensoryFeedback(.selection, trigger: pour.tastedNotes)
        TextField("Add a flavor", text: $newNote)
          .font(.subheadline)
          .submitLabel(.done)
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .background(Color.well.opacity(0.6), in: .capsule)
          .onSubmit {
            let note = newNote.trimmingCharacters(in: .whitespaces).lowercased()
            newNote = ""
            guard !note.isEmpty, !pour.tastedNotes.contains(note) else { return }
            withAnimation(.settle) { update { $0.notes.append(note) } }
          }
      }
    }
  }

  /// The bag's notes first (to check against), then anything already picked.
  private var noteChoices: [String] {
    var choices = (pour.bean?.tastingNotes ?? []).map { $0.lowercased() }
    if choices.isEmpty { choices = ["chocolate", "caramel", "nutty", "fruity", "citrus", "floral"] }
    for note in pour.tastedNotes where !choices.contains(note) { choices.append(note) }
    return choices
  }

  private func update(_ change: (inout DrinkTaste) -> Void) {
    var taste = pour.taste
    change(&taste)
    pour.taste = taste
    try? context.save()
  }
}

/// Espresso advice from the shot numbers, the taste and earlier pours of the
/// same beans. Hidden when there's nothing to change.
struct DialInCard: View {
  let pour: Pour
  let contrast: Double
  @Query(sort: \Pour.date) private var pours: [Pour]

  var body: some View {
    let tips = Self.tips(for: pour, contrast: contrast, among: pours)
    if !tips.isEmpty || pour.shotSeconds != nil {
      VStack(alignment: .leading, spacing: 10) {
        Text("Dial in").font(.display(.title3))
        if tips.isEmpty {
          Label("Shot looks on target for \(roastName). Keep it there.", systemImage: "checkmark.circle")
            .font(.subheadline)
            .foregroundStyle(Color.espresso)
        }
        ForEach(tips) { tip in
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(tip.kind))
              .font(.footnote.weight(.semibold))
              .foregroundStyle(Color.crema)
              .frame(width: 28, height: 28)
              .background(Color.crema.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
              Text(tip.title).font(.subheadline.weight(.semibold))
              Text(tip.detail).font(.subheadline).foregroundStyle(.secondary)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        let target = DialIn.target(for: pour.bean?.roastLevel)
        Text("Usual target for \(roastName): 1:\(f(target.ratio.lowerBound))–\(f(target.ratio.upperBound)) in \(Int(target.seconds.lowerBound))–\(Int(target.seconds.upperBound)) s. Taste wins over the numbers.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .card()
      .accessibilityIdentifier("dial-in")
    }
  }

  static func tips(for pour: Pour, contrast: Double?, among pours: [Pour]) -> [DialInTip] {
    let earlier = pours.filter { $0.date < pour.date && $0.persistentModelID != pour.persistentModelID }.map(\.record)
    return DialIn.tips(brew: pour.brew, taste: pour.taste.balance, contrast: contrast, date: pour.date, history: earlier)
  }

  private var roastName: String { pour.bean?.roastLevel.map { "a \($0.displayName.lowercased()) roast" } ?? "espresso" }
  private func f(_ v: Double) -> String { String(format: "%.1f", v) }

  private func icon(_ kind: DialInTip.Kind) -> String {
    switch kind {
    case .grind: "dial.medium"
    case .ratio: "scalemass"
    case .freshness: "calendar"
    case .history: "clock.arrow.circlepath"
    }
  }
}
