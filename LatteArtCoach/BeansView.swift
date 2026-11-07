import Charts
import LatteCore
import SwiftData
import SwiftUI

/// Every bag of beans, with what the user's ratings say they like.
struct BeansView: View {
  @Environment(\.modelContext) private var context
  @Query(sort: \Bean.addedAt, order: .reverse) private var beans: [Bean]
  @Query private var pours: [Pour]
  @State private var adding = false

  var body: some View {
    List {
      Section {
        let preferences = TastePreferences(records: pours.map(\.record))
        if preferences.findings.isEmpty {
          Text(preferences.ratedDrinks == 0
            ? "Rate how your drinks taste (the stars under “How it tasted”) and this fills in with what you like."
            : "\(preferences.ratedDrinks) rated drink\(preferences.ratedDrinks == 1 ? "" : "s") so far. Comparisons show up once there are \(TastePreferences.minimumDrinks)+ drinks of each kind.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        ForEach(preferences.findings) { finding in
          Label(finding.text, systemImage: icon(finding.kind)).font(.subheadline)
        }
      } header: {
        Text("What you like")
      }
      .accessibilityIdentifier("preferences")

      if beans.isEmpty {
        ContentUnavailableView {
          Label("No beans yet", systemImage: "bag")
        } description: {
          Text("Add a bag, or scan its label, and log it on your pours.")
        } actions: {
          Button("Add beans") { adding = true }.buttonStyle(.borderedProminent)
        }
      } else {
        Section("Bags") {
          ForEach(beans) { bean in
            NavigationLink(value: Route.bean(bean)) { BeanRow(bean: bean) }
          }
          .onDelete { offsets in
            for index in offsets { context.delete(beans[index]) }
            try? context.save()
          }
        }
      }
    }
    .scrollContentBackground(.hidden)
    .background(Color.milk)
    .navigationTitle("Beans")
    .toolbar {
      DoneButton()
      ToolbarItem(placement: .topBarTrailing) {
        Button { adding = true } label: { Label("Add beans", systemImage: "plus") }
          .accessibilityIdentifier("add-beans")
      }
    }
    .sheet(isPresented: $adding) {
      NewBeanForm { bean in
        context.insert(bean)
        try? context.save()
      }
    }
  }

  private func icon(_ kind: TastePreferences.Finding.Kind) -> String {
    switch kind {
    case .roast: "flame"
    case .origin: "globe.americas"
    case .process: "drop"
    case .flavor: "leaf"
    case .notes: "text.bubble"
    case .milk: "cup.and.saucer"
    }
  }
}

private struct BeanRow: View {
  let bean: Bean

  var body: some View {
    let summary = bean.summary
    VStack(alignment: .leading, spacing: 3) {
      HStack {
        Text(bean.name).font(.body.weight(.semibold))
        Spacer()
        if let rating = summary.averageRating {
          Text(String(format: "%.1f★", rating)).font(.subheadline.monospacedDigit()).foregroundStyle(Color.measure)
        }
      }
      Text(BeanFacts.line(bean)).font(.footnote).foregroundStyle(.secondary)
      Text(summary.pourCount == 0 ? "No pours yet"
        : "\(summary.pourCount) pour\(summary.pourCount == 1 ? "" : "s") · art avg \(Int((summary.averageScore ?? 0).rounded()))")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("bean-row")
  }
}

enum BeanFacts {
  /// "Onyx · Ethiopia · washed · light · 12 days off roast"
  static func line(_ bean: Bean, on date: Date = .now) -> String {
    var parts = [bean.roaster, bean.origin, bean.process?.lowercased(), bean.roastLevel?.displayName.lowercased()].compactMap { $0 }
    if let roast = bean.roastDate,
       let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: roast), to: Calendar.current.startOfDay(for: date)).day {
      parts.append("\(days) day\(days == 1 ? "" : "s") off roast")
    }
    return parts.isEmpty ? "No details yet" : parts.joined(separator: " · ")
  }
}

/// One bag over time: how its drinks tasted, how the art went, and the grind
/// that worked.
struct BeanDetailView: View {
  @Bindable var bean: Bean
  @Environment(\.modelContext) private var context
  @Query private var allPours: [Pour]
  @State private var editing = false

  private var pours: [Pour] { bean.pours.sorted { $0.date < $1.date } }

  var body: some View {
    let summary = bean.summary
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 6) {
          Text(bean.name).font(.display(.title))
          Text(BeanFacts.line(bean)).font(.subheadline).foregroundStyle(.secondary)
          if !bean.tastingNotes.isEmpty {
            Text("On the bag: " + bean.tastingNotes.joined(separator: ", ")).font(.subheadline)
          }
          if bean.roastLevelIsGuess, bean.roastLevel != nil {
            Text("Roast level guessed from the tasting notes.").font(.caption).foregroundStyle(.secondary)
          }
        }

        HStack(spacing: 10) {
          stat("\(summary.pourCount)", "pours")
          stat(summary.averageScore.map { "\(Int($0.rounded()))" } ?? "–", "art avg")
          stat(summary.averageRating.map { String(format: "%.1f★", $0) } ?? "–", "taste avg")
          stat(summary.usualBalance?.displayName ?? "–", "usually")
        }

        if pours.count >= 2 { chart.card() }

        if let best = DialIn.bestSettings(for: BrewDetails(beanName: bean.name, roaster: bean.roaster),
                                          in: allPours.map(\.record)) {
          VStack(alignment: .leading, spacing: 4) {
            Label(best.title, systemImage: "dial.medium").font(.subheadline.bold())
            Text(best.detail).font(.subheadline).foregroundStyle(.secondary)
          }
          .card()
        }

        if !noticed.isEmpty {
          VStack(alignment: .leading, spacing: 6) {
            Text("Flavors you noticed").font(.display(.title3))
            Text(noticed.map { "\($0.note) (\($0.count)×)" }.joined(separator: ", ")).font(.subheadline)
          }
          .card()
        }

        if let notes = bean.notes {
          VStack(alignment: .leading, spacing: 6) {
            Text("Your notes").font(.display(.title3))
            Text(notes).font(.subheadline)
          }
          .card()
        }

        if !pours.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text("Pours").font(.display(.title3))
            ForEach(pours.reversed()) { pour in
              NavigationLink(value: Route.pour(pour)) {
                HStack {
                  Text(pour.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
                  Spacer()
                  if let stars = pour.drinkRating { Text("\(stars)★").font(.subheadline).foregroundStyle(Color.measure) }
                  Text("\(pour.score)").font(.subheadline.bold().monospacedDigit())
                  Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
              }
              .buttonStyle(.plain)
            }
          }
          .card()
        }
      }
      .padding()
    }
    .background(Color.milk)
    .navigationTitle("Beans")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Edit") { editing = true }.accessibilityIdentifier("edit-beans")
      }
      DoneButton()
    }
    .sheet(isPresented: $editing) {
      NewBeanForm(editing: bean) { _ in try? context.save() }
    }
  }

  private var noticed: [(note: String, count: Int)] {
    Dictionary(grouping: pours.flatMap(\.tastedNotes)) { $0 }.map { ($0.key, $0.value.count) }
      .sorted { ($0.count, $1.note) > ($1.count, $0.note) }
  }

  private var chart: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Over time").font(.display(.title3))
      Chart {
        ForEach(pours) { pour in
          LineMark(x: .value("Date", pour.date), y: .value("Score", pour.score))
            .foregroundStyle(by: .value("Series", "Art score"))
          PointMark(x: .value("Date", pour.date), y: .value("Score", pour.score))
            .foregroundStyle(by: .value("Series", "Art score"))
          if let stars = pour.drinkRating {
            PointMark(x: .value("Date", pour.date), y: .value("Score", stars * 20))
              .foregroundStyle(by: .value("Series", "Taste ★×20"))
              .symbol(.diamond)
              .symbolSize(70)
          }
        }
      }
      .chartForegroundStyleScale(["Art score": Color.measure, "Taste ★×20": Color.espresso])
      .chartYScale(domain: 0...100)
      .frame(height: 150)
    }
  }

  private func stat(_ value: String, _ label: String) -> some View {
    VStack(spacing: 2) {
      Text(value).font(.number(20)).minimumScaleFactor(0.6).lineLimit(1)
      Text(label).font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 10)
    .background(Color.card, in: .rect(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.crema.opacity(0.15)))
  }
}
