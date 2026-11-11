import FoundationModels
import LatteCore
import SwiftData
import SwiftUI

/// What the language model writes. The score and the facts come from the
/// measurements (see `CoachingBrief`); the model only words the coaching.
@Generable
struct AICoaching {
  @Guide(description: "One sentence: the single most important thing to focus on in the next pour.")
  var focus: String
  @Guide(description: "Specific technique tips for the next pour, most important first.", .count(1...3))
  var tips: [AITip]
  @Guide(description: "One short sentence to the barista, addressed as you, about a recurring problem or an improvement across recent pours, based only on the history facts. Empty if there is nothing to say.")
  var progress: String
}

@Generable
struct AITip {
  @Guide(description: "A short title of 2 to 4 words.")
  var title: String
  @Guide(description: "One or two sentences of concrete pouring technique.")
  var detail: String
}

/// Coaching as saved with a pour, so reopening it doesn't run the model again.
struct SavedCoaching: Codable, Equatable {
  struct Tip: Codable, Equatable {
    var title: String
    var detail: String
  }
  var focus: String
  var tips: [Tip]
  var progress: String

  init(focus: String, tips: [Tip], progress: String) {
    self.focus = focus
    self.tips = tips
    self.progress = progress
  }

  init(_ partial: AICoaching.PartiallyGenerated) {
    focus = partial.focus ?? ""
    tips = (partial.tips ?? []).map { Tip(title: $0.title ?? "", detail: $0.detail ?? "") }
    progress = partial.progress ?? ""
  }

  /// As plain text, to remind the model what it said when answering a
  /// follow-up question later.
  var text: String {
    ([focus] + tips.map { "\($0.title): \($0.detail)" } + (progress.isEmpty ? [] : [progress])).joined(separator: "\n")
  }
}

/// Streams coaching for one pour from the on-device model (or shows the
/// saved coaching), and answers follow-up questions.
@MainActor @Observable
final class AICoach {
  enum Phase {
    /// The model can't run; the rule-based tips are shown, with this note.
    case unavailable(note: String?)
    case thinking
    case writing(SavedCoaching)
    case done(SavedCoaching)
    /// Generation failed; fall back to the rule-based tips.
    case failed
  }

  private(set) var phase: Phase = .thinking
  private(set) var answer: String?
  private(set) var isAnswering = false
  private var session: LanguageModelSession?
  private var prompt = ""

  /// Shows `saved` when it was written from this same prompt; otherwise
  /// asks the model and returns the new coaching for saving.
  func start(prompt: String, saved: SavedCoaching?) async -> SavedCoaching? {
    self.prompt = prompt
    session = nil
    answer = nil
    if let saved {
      phase = .done(saved)
      return nil
    }
    switch SystemLanguageModel.default.availability {
    case .available: break
    case .unavailable(.appleIntelligenceNotEnabled):
      phase = .unavailable(note: "Turn on Apple Intelligence in Settings for coaching written for your pours.")
      return nil
    case .unavailable(.modelNotReady):
      phase = .unavailable(note: "Apple Intelligence is still getting ready. Built-in tips for now.")
      return nil
    case .unavailable:
      phase = .unavailable(note: nil)
      return nil
    }
    let session = LanguageModelSession(instructions: CoachingBrief.instructions)
    self.session = session
    phase = .thinking
    let work = Task { @MainActor () -> SavedCoaching? in
      var latest: SavedCoaching?
      for try await snapshot in session.streamResponse(to: prompt, generating: AICoaching.self) {
        try Task.checkCancellation()
        latest = SavedCoaching(snapshot.content)
        phase = .writing(latest!)
      }
      return latest
    }
    // If the model hasn't started writing in time, show the built-in tips
    // rather than a spinner that never ends.
    let watchdog = Task { @MainActor in
      try await Task.sleep(for: Self.startTimeout)
      if case .thinking = phase {
        phase = .failed
        work.cancel()
      }
    }
    defer { watchdog.cancel() }
    do {
      guard let latest = try await work.value, !latest.focus.isEmpty else {
        phase = .failed
        return nil
      }
      phase = .done(latest)
      return latest
    } catch {
      phase = .failed
      return nil
    }
  }

  static let startTimeout: Duration = .seconds(20)

  func ask(_ question: String) async {
    var question = question
    if session == nil, case .done(let saved) = phase {
      // Saved coaching: start a conversation that knows the facts and what
      // was already said.
      session = LanguageModelSession(instructions: CoachingBrief.instructions)
      question = "\(prompt)\n\nYou already gave this coaching:\n\(saved.text)\n\nThe barista asks: \(question)"
    }
    guard let session, !session.isResponding else { return }
    isAnswering = true
    answer = ""
    do {
      for try await snapshot in session.streamResponse(to: question) { answer = snapshot.content }
    } catch {
      answer = "Couldn't answer that one. Try asking another way."
    }
    isAnswering = false
  }
}

/// "Next pour": coaching from the on-device model when it's available,
/// otherwise the rule-based tips.
struct CoachingSection: View {
  let analysis: PourAnalysis
  let pour: Pour?
  @Environment(\.modelContext) private var context
  @State private var coach = AICoach()
  @State private var question = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Next pour").font(.display(.title3))
        Spacer()
        if isAI {
          Label("Apple Intelligence", systemImage: "apple.intelligence")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      switch coach.phase {
      case .thinking:
        HStack(spacing: 8) {
          ProgressView()
          Text("Your coach is looking at this pour…").font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("coach-thinking")
      case .writing(let coaching), .done(let coaching):
        written(coaching)
      case .failed:
        ruleTips
      case .unavailable(let note):
        ruleTips
        if let note { Text(note).font(.footnote).foregroundStyle(.secondary) }
      }
    }
    .animation(.settle, value: phaseName)
    .task(id: taskKey) {
      let prompt = prompt()
      // Reuse saved coaching when it was written from exactly these facts.
      let saved = pour?.coachingPrompt == prompt ? pour?.savedCoaching : nil
      if let fresh = await coach.start(prompt: prompt, saved: saved), let pour {
        pour.savedCoaching = fresh
        pour.coachingPrompt = prompt
        try? context.save()
      }
    }
  }

  /// The phase without its payload: animates the switch from thinking to
  /// writing, but not every streamed word.
  private var phaseName: String {
    switch coach.phase {
    case .thinking: "thinking"
    case .writing: "writing"
    case .done: "done"
    case .failed: "failed"
    case .unavailable: "unavailable"
    }
  }

  private var isAI: Bool {
    switch coach.phase {
    case .thinking, .writing, .done: true
    case .failed, .unavailable: false
    }
  }

  /// Changes whenever the facts given to the model could change.
  private var taskKey: String {
    "\(analysis.pattern.rawValue)-\(analysis.score.overall)-\(pour?.rating ?? 0)-\(String(describing: pour?.brew))-\(String(describing: pour?.taste))"
  }

  @ViewBuilder
  private func written(_ coaching: SavedCoaching) -> some View {
    let focus = coaching.focus
    if !focus.isEmpty {
      Text(focus)
        .font(.body.weight(.semibold))
        .padding(.leading, 10)
        .overlay(alignment: .leading) { Capsule().fill(Color.measure).frame(width: 3) }
        .accessibilityIdentifier("coach-focus")
    }
    ForEach(Array(coaching.tips.enumerated()), id: \.offset) { index, tip in
      card(index + 1, title: tip.title, detail: tip.detail)
    }
    if !coaching.progress.isEmpty {
      let progress = coaching.progress
      Label(progress, systemImage: "chart.line.uptrend.xyaxis").font(.subheadline).foregroundStyle(.secondary)
    }
    if case .done = coach.phase { askBox }
  }

  private var ruleTips: some View {
    ForEach(Array(analysis.tips.enumerated()), id: \.offset) { index, tip in
      card(index + 1, title: tip.title, detail: tip.detail)
    }
  }

  /// One tip: a numbered step, no box.
  private func card(_ number: Int, title: String, detail: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text("\(number)")
        .font(.caption.weight(.bold).monospacedDigit())
        .foregroundStyle(Color.crema)
        .frame(width: 22, height: 22)
        .background(Color.crema.opacity(0.12), in: .circle)
        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 6 }
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.subheadline.weight(.semibold))
        Text(detail).font(.subheadline).foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 2)
  }

  private var askBox: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        TextField("Ask your coach about this pour", text: $question)
          .font(.subheadline)
          .submitLabel(.send)
          .onSubmit(send)
        Button(action: send) {
          Image(systemName: "arrow.up.circle.fill").font(.title2).symbolRenderingMode(.hierarchical)
        }
        .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || coach.isAnswering)
        .tint(.crema)
        .accessibilityLabel("Ask")
      }
      .padding(.leading, 14)
      .padding(.trailing, 6)
      .padding(.vertical, 6)
      .background(Color.milk, in: .capsule)
      .overlay(Capsule().strokeBorder(Color.crema.opacity(0.2)))
      if let answer = coach.answer {
        Text(answer.isEmpty ? "…" : answer).font(.subheadline)
      }
    }
  }

  private func send() {
    let text = question.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return }
    question = ""
    Task { await coach.ask(text) }
  }

  /// The facts for the model: this pour plus earlier pours of the same pattern.
  private func prompt() -> String {
    let pattern = analysis.pattern
    let all = (try? context.fetch(FetchDescriptor<Pour>())) ?? []
    let earlier = all
      .filter { $0.pattern == pattern && $0.persistentModelID != pour?.persistentModelID && $0.date < (pour?.date ?? .now) }
      .map(\.record)
    let dialIn = pour.map { DialInCard.tips(for: $0, contrast: analysis.score.components[.contrast], among: all) } ?? []
    return CoachingBrief.prompt(
      pattern: pattern, score: analysis.score, tips: analysis.tips,
      history: ProgressSummary(records: earlier, pattern: pattern), rating: pour?.rating,
      brew: pour?.brew, taste: pour?.taste, dialIn: dialIn, date: pour?.date ?? .now)
  }
}
