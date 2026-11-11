import Charts
import LatteCore
import SwiftData
import SwiftUI

/// Saved pours for one pattern: progress over time, then the list.
struct HistoryView: View {
  @Environment(\.modelContext) private var context
  @Query(sort: \Pour.date, order: .reverse) private var pours: [Pour]
  /// Separate from the Pour tab's choice: browsing history shouldn't change what you're about to pour.
  @AppStorage("historyPattern") private var pattern: Pattern = .tulip
  @State private var export: ExportFiles?

  private var shown: [Pour] { pours.filter { $0.pattern == pattern } }

  var body: some View {
    List {
      Section {
        SlidingPicker(options: Pattern.allCases, selection: $pattern) { option, _ in
          HStack(spacing: 6) {
            PatternGlyph(pattern: option).frame(width: 14, height: 14)
            Text(option.displayName).font(.subheadline.weight(.semibold))
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel(option.displayName)
        }
        .accessibilityIdentifier("history-pattern")
      }
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets())

      if let summary = ProgressSummary(records: shown.map(\.record), pattern: pattern) {
        Section("Progress") { ProgressSection(pours: shown, summary: summary) }
        .listRowBackground(Color.card)
        Section("Pours") {
          ForEach(shown) { pour in
            NavigationLink(value: Route.pour(pour)) { PourRow(pour: pour).zoomSource(pour.persistentModelID) }
          }
          .onDelete { offsets in
            for index in offsets { context.delete(shown[index]) }
            try? context.save()
          }
        }
        .listRowBackground(Color.card)
      } else {
        ContentUnavailableView(
          "No \(pattern.noun)s yet", systemImage: "cup.and.saucer",
          description: Text("Score a \(pattern.noun) and it shows up here."))
      }
    }
    .scrollContentBackground(.hidden)
    .background(Color.milk)
    .navigationTitle("History")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          export = try? ExportFiles(pours: pours)
        } label: {
          Label("Export", systemImage: "square.and.arrow.up")
        }
        .disabled(pours.isEmpty)
      }
    }
    .sheet(item: $export) { files in
      ActivityView(items: files.urls).ignoresSafeArea()
    }
    .task { await PourAnalyzer.rescoreOutdated(pours, context: context) }
  }
}

private struct PourRow: View {
  let pour: Pour

  var body: some View {
    HStack(spacing: 12) {
      Group {
        if let data = pour.thumbnail, let image = UIImage(data: data) {
          Image(uiImage: image).resizable().scaledToFill()
        } else {
          Color.crema.opacity(0.2)
        }
      }
      .frame(width: 52, height: 52)
      .clipShape(.rect(cornerRadius: 12))
      VStack(alignment: .leading, spacing: 3) {
        Text(pour.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))).font(.subheadline.weight(.semibold))
        Text("\(pour.date.formatted(date: .omitted, time: .shortened)) · " + (pour.rating.map { "You: \($0)/10" } ?? "Not rated"))
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Text("\(pour.score)")
        .font(.number(24))
        .foregroundStyle(pour.score >= 65 ? Color.espresso : Color.weak)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("pour-row")
  }
}

private struct ProgressSection: View {
  let pours: [Pour]
  let summary: ProgressSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if pours.count >= 2 { chart }
      Text(headline).font(.display(.headline))
      VStack(spacing: 10) {
        ForEach(summary.trends, id: \.component) { trend in
          HStack(spacing: 10) {
            Text(trend.component.label(for: summary.pattern)).font(.subheadline).frame(width: 104, alignment: .leading)
            Meter(value: trend.recent)
            Text("\(Int((trend.recent * 100).rounded()))").font(.subheadline.monospacedDigit()).frame(width: 30, alignment: .trailing)
            Group {
              if let change = trend.change, abs(change) >= 0.05 {
                Image(systemName: change > 0 ? "arrow.up.right" : "arrow.down.right")
                  .foregroundStyle(change > 0 ? Color.measure : Color.weak)
                  .accessibilityLabel(change > 0 ? "up" : "down")
              }
            }
            .font(.caption.bold())
            .frame(width: 14)
          }
        }
      }
      if !summary.disagreements.isEmpty {
        Label("The score and your rating disagree on \(summary.disagreements.count) of \(summary.ratedCount) rated pours. Export them so the score can be tuned.", systemImage: "exclamationmark.bubble")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
  }

  private var chart: some View {
      Chart {
        ForEach(pours) { pour in
          AreaMark(x: .value("Date", pour.date), y: .value("Score", pour.score))
            .interpolationMethod(.monotone)
            .foregroundStyle(LinearGradient(colors: [Color.measure.opacity(0.25), Color.measure.opacity(0)], startPoint: .top, endPoint: .bottom))
          LineMark(x: .value("Date", pour.date), y: .value("Score", pour.score))
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .foregroundStyle(by: .value("Series", "App score"))
          PointMark(x: .value("Date", pour.date), y: .value("Score", pour.score))
            .symbolSize(30)
            .foregroundStyle(by: .value("Series", "App score"))
          if let rating = pour.rating {
            PointMark(x: .value("Date", pour.date), y: .value("Score", rating * 10))
              .foregroundStyle(by: .value("Series", "Your rating ×10"))
              .symbol(.diamond)
              .symbolSize(70)
          }
        }
      }
      // Amber for the app's measured score; espresso for your rating, so the
      // two read apart at a glance (crema and amber were too close).
      .chartForegroundStyleScale(["App score": Color.measure, "Your rating ×10": Color.espresso])
      .chartYScale(domain: 0...100)
      .chartYAxis { AxisMarks(values: [0, 50, 100]) { AxisGridLine(); AxisValueLabel() } }
      .chartLegend(position: .top, alignment: .leading)
      .chartXScale(range: .plotDimension(padding: 10))
      .frame(height: 170)
  }

  private var headline: String {
    let recent = Int(summary.recentAverageScore.rounded())
    guard let earlier = summary.earlierAverageScore else {
      return "\(summary.pourCount) \(summary.pattern.noun)\(summary.pourCount == 1 ? "" : "s") so far, averaging \(recent)."
    }
    return "Last \(summary.recentCount) average \(recent), up from \(Int(earlier.rounded())) before."
      .replacingOccurrences(of: "up from", with: recent >= Int(earlier.rounded()) ? "up from" : "down from")
  }
}

/// A saved pour, re-analyzed from its original photo.
struct PourDetailView: View {
  @Environment(\.modelContext) private var context
  @Bindable var pour: Pour
  @State private var shown: (UIImage, PourAnalysis)?
  @State private var failure: String?

  var body: some View {
    Group {
      if let (photo, analysis) = shown {
        ResultView(photo: photo, analysis: analysis, pour: pour, onRescore: { pattern in
          Task { await load(as: pattern) }
        }, onAdjustCup: { cup in
          pour.manualCup = cup
          Task { await load(as: pour.pattern) }
        }, onAgain: nil)
      } else if let failure {
        ContentUnavailableView("Couldn't score this one", systemImage: "cup.and.saucer", description: Text(failure))
      } else {
        ProgressView()
      }
    }
    .navigationTitle(pour.date.formatted(date: .abbreviated, time: .omitted))
    .navigationBarTitleDisplayMode(.inline)
    .task { await load(as: pour.pattern) }
  }

  private func load(as pattern: Pattern) async {
    let data = pour.photo
    let photo = await Task.detached { PhotoRendition(data: data) }.value
    switch await PourAnalyzer.analyze(data, as: pattern, cup: pour.manualCup) {
    case .success(let analysis):
      pour.update(from: analysis)
      try? context.save()
      if let photo { shown = (photo.image, analysis) }
    case .failure(let error):
      failure = CoachModel.message(for: error)
    }
  }
}

/// Original photos plus `pours.json`, written to a temporary folder for sharing.
struct ExportFiles: Identifiable {
  let id = UUID()
  let urls: [URL]

  init(pours: [Pour]) throws {
    let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
      .replacingOccurrences(of: ":", with: "")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LatteCoach-\(stamp)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var entries: [(photo: String, record: PourRecord, analysisVersion: Int)] = []
    var urls: [URL] = []
    let names = DateFormatter()
    names.dateFormat = "yyyyMMdd-HHmmss"
    for pour in pours.sorted(by: { $0.date < $1.date }) {
      let name = "\(names.string(from: pour.date))-\(pour.pattern.rawValue).\(Self.fileExtension(pour.photo))"
      let url = folder.appendingPathComponent(name)
      try pour.photo.write(to: url)
      urls.append(url)
      entries.append((name, pour.record, pour.analysisVersion))
    }
    let json = folder.appendingPathComponent("pours.json")
    try HistoryExport(exportedAt: .now, pours: entries).encoded().write(to: json)
    self.urls = [json] + urls
  }

  static func fileExtension(_ data: Data) -> String {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let type = CGImageSourceGetType(source) as String? else { return "jpg" }
    switch type {
    case "public.heic", "public.heif": return "heic"
    case "public.png": return "png"
    default: return "jpg"
    }
  }
}

/// The system share sheet.
struct ActivityView: UIViewControllerRepresentable {
  let items: [Any]
  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }
  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
