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
  @Guide(description: "One short sentence about a recurring problem or an improvement across recent pours, based only on the history facts. Empty if there is nothing to say.")
  var progress: String
}

@Generable
struct AITip {
  @Guide(description: "A short title of 2 to 4 words.")
  var title: String
  @Guide(description: "One or two sentences of concrete pouring technique.")
  var detail: String
}

/// Streams coaching for one pour from the on-device model, and answers
/// follow-up questions in the same conversation.
@MainActor @Observable
final class AICoach {
  enum Phase {
    /// The model can't run; the rule-based tips are shown, with this note.
    case unavailable(note: String?)
    case thinking
    case writing(AICoaching.PartiallyGenerated)
    case done(AICoaching.PartiallyGenerated)
    /// Generation failed; fall back to the rule-based tips.
    case failed
  }

  private(set) var phase: Phase = .thinking
  private(set) var answer: String?
  private(set) var isAnswering = false
  private var session: LanguageModelSession?

  func start(prompt: String) async {
    switch SystemLanguageModel.default.availability {
    case .available: break
    case .unavailable(.appleIntelligenceNotEnabled):
      phase = .unavailable(note: "Turn on Apple Intelligence in Settings for coaching written for your pours.")
      return
    case .unavailable(.modelNotReady):
      phase = .unavailable(note: "Apple Intelligence is still getting ready. Built-in tips for now.")
      return
    case .unavailable:
      phase = .unavailable(note: nil)
      return
    }
    let session = LanguageModelSession(instructions: CoachingBrief.instructions)
    self.session = session
    answer = nil
    phase = .thinking
    do {
      var latest: AICoaching.PartiallyGenerated?
      for try await snapshot in session.streamResponse(to: prompt, generating: AICoaching.self) {
        latest = snapshot.content
        phase = .writing(snapshot.content)
      }
      phase = latest.map { .done($0) } ?? .failed
    } catch {
      phase = .failed
    }
  }

  func ask(_ question: String) async {
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
    .task(id: "\(analysis.pattern.rawValue)-\(analysis.score.overall)") {
      await coach.start(prompt: prompt())
    }
  }

  private var isAI: Bool {
    switch coach.phase {
    case .thinking, .writing, .done: true
    case .failed, .unavailable: false
    }
  }

  @ViewBuilder
  private func written(_ coaching: AICoaching.PartiallyGenerated) -> some View {
    if let focus = coaching.focus, !focus.isEmpty {
      Text(focus)
        .font(.body.weight(.semibold))
        .padding(.leading, 10)
        .overlay(alignment: .leading) { Capsule().fill(Color.measure).frame(width: 3) }
        .accessibilityIdentifier("coach-focus")
    }
    if let tips = coaching.tips {
      ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
        card(title: tip.title ?? "", detail: tip.detail ?? "")
      }
    }
    if let progress = coaching.progress, !progress.isEmpty {
      Label(progress, systemImage: "chart.line.uptrend.xyaxis").font(.subheadline).foregroundStyle(.secondary)
    }
    if case .done = coach.phase { askBox }
  }

  private var ruleTips: some View {
    ForEach(analysis.tips) { tip in card(title: tip.title, detail: tip.detail) }
  }

  private func card(title: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.subheadline.bold())
      Text(detail).font(.subheadline).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Color.crema.opacity(0.08), in: .rect(cornerRadius: 12))
  }

  private var askBox: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        TextField("Ask your coach about this pour", text: $question)
          .textFieldStyle(.roundedBorder)
          .submitLabel(.send)
          .onSubmit(send)
        Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
          .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || coach.isAnswering)
          .tint(.crema)
      }
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
    let earlier = ((try? context.fetch(FetchDescriptor<Pour>())) ?? [])
      .filter { $0.pattern == pattern && $0.persistentModelID != pour?.persistentModelID && $0.date < (pour?.date ?? .now) }
      .map(\.record)
    return CoachingBrief.prompt(
      pattern: pattern, score: analysis.score, tips: analysis.tips,
      history: ProgressSummary(records: earlier, pattern: pattern), rating: pour?.rating)
  }
}
