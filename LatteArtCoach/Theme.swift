import SwiftUI
import UIKit

/// The app's palette: quiet warm neutrals, one accent taken from the cup.
/// - crema: the brand color (selection, primary actions)
/// - measure: amber, for anything the app measured (score arc, axis, meters)
/// - milk / card: the page and the surfaces on it
/// - espresso: text and glyphs
extension Color {
  static let crema = Color(light: 0xB0692E, dark: 0xE2A46A)
  static let measure = Color(light: 0xE39A17, dark: 0xF2B33D)
  static let milk = Color(light: 0xF3F1EE, dark: 0x0B0A09)
  static let card = Color(light: 0xFFFFFF, dark: 0x1B1917)
  static let espresso = Color(light: 0x1C1917, dark: 0xF5F2EE)
  /// Terracotta, for weak scores: warm like the rest, never traffic-light red.
  static let weak = Color(light: 0xB5533A, dark: 0xE0846A)
  /// Recessed tracks behind controls and meters.
  static let well = Color(light: 0xE7E3DE, dark: 0x2A2724)
  /// A raised thumb on a well: lighter than the well in both modes.
  static let thumb = Color(light: 0xFFFFFF, dark: 0x4A4541)

  init(light: UInt32, dark: UInt32) {
    self.init(uiColor: UIColor { traits in UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light) })
  }
}

extension UIColor {
  convenience init(hex: UInt32) {
    self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
              blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
  }
}

extension Font {
  /// Headings: SF Pro, semibold. Plain and precise, like the system apps.
  static func display(_ style: Font.TextStyle) -> Font { .system(style, weight: .semibold) }
  /// Numbers in rows and stats: tabular, so they line up and don't jitter.
  static func number(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold).monospacedDigit() }
  /// Big instrument readouts (the score, a rating, a dose): light and large.
  static func readout(_ size: CGFloat) -> Font { .system(size: size, weight: .light).monospacedDigit() }
}

extension View {
  /// The standard surface for a section: borderless, softly lifted.
  func card() -> some View { modifier(CardSurface()) }

  /// A small uppercase label above a value or a group ("DOSE", "NEXT POUR").
  func eyebrow() -> some View {
    font(.caption.weight(.semibold)).textCase(.uppercase).tracking(0.8).foregroundStyle(.secondary)
  }
}

private struct CardSurface: ViewModifier {
  @Environment(\.colorScheme) private var scheme

  func body(content: Content) -> some View {
    content
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .fill(Color.card)
          .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.05), radius: 16, y: 6)
      }
      // Dark mode has no shadows to lift a surface; a faint edge does it.
      .overlay {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .strokeBorder(.white.opacity(scheme == .dark ? 0.06 : 0))
      }
  }
}

extension Animation {
  /// The app's one motion curve for state changes: quick, no bounce.
  static let settle = Animation.smooth(duration: 0.35)
  /// For a thumb sliding under a finger: fast, with a hint of follow-through.
  static let glide = Animation.snappy(duration: 0.28, extraBounce: 0.04)
}

/// Custom tappable surfaces (pattern cards, rating chips, cards that open a
/// sheet): they give under the finger, like a system button.
struct PressStyle: ButtonStyle {
  var scale: CGFloat = 0.96
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
      .opacity(configuration.isPressed ? 0.85 : 1)
      .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
  }
}

extension ButtonStyle where Self == PressStyle {
  static var press: PressStyle { PressStyle() }
  /// For large cards, where 0.96 would move the edges too far.
  static var pressCard: PressStyle { PressStyle(scale: 0.985) }
}

/// The app's main action: a full-width crema capsule in Liquid Glass.
struct PrimaryButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .foregroundStyle(isEnabled ? Color.white : Color.secondary)
      .frame(maxWidth: .infinity, minHeight: 54)
      .contentShape(.capsule)
      .glassEffect(isEnabled ? .regular.tint(.crema).interactive() : .regular, in: .capsule)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
  }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
  static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

/// A 0–1 bar for a measured part of the score: amber, or terracotta when
/// it's weak. Fills in when it appears.
struct Meter: View {
  let value: Double
  @State private var shown = 0.0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(Color.well)
        Capsule()
          .fill(value >= 0.5 ? Color.measure : Color.weak)
          .frame(width: max(4, proxy.size.width * min(max(shown, 0), 1)))
      }
    }
    .frame(height: 4)
    .onAppear {
      if reduceMotion { shown = value } else { withAnimation(.smooth(duration: 0.7).delay(0.1)) { shown = value } }
    }
    .onChange(of: value) { withAnimation(.settle) { shown = value } }
    .accessibilityHidden(true)
  }
}

/// A row of options with a thumb that glides to the chosen one. Tap an
/// option, or drag across the control to scrub; each change ticks.
struct SlidingPicker<Value: Hashable, Label: View>: View {
  let options: [Value]
  @Binding var selection: Value?
  /// Tapping the chosen option again clears it.
  var allowsNone = false
  @ViewBuilder let label: (Value, Bool) -> Label
  @Namespace private var thumb
  @State private var width: CGFloat = 0

  var body: some View {
    HStack(spacing: 0) {
      ForEach(options, id: \.self) { option in
        let on = option == selection
        Button {
          withAnimation(.glide) { selection = on && allowsNone ? nil : option }
        } label: {
          label(option, on)
            .frame(maxWidth: .infinity, minHeight: 36)
            .padding(.vertical, 4)
            .foregroundStyle(on ? Color.espresso : Color.secondary)
            .background {
              if on {
                Capsule()
                  .fill(Color.thumb)
                  .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
                  .matchedGeometryEffect(id: "thumb", in: thumb)
              }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.press)
        .accessibilityAddTraits(on ? .isSelected : [])
      }
    }
    .padding(3)
    .background(Color.well, in: .capsule)
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    .simultaneousGesture(
      DragGesture(minimumDistance: 8).onChanged { drag in
        guard width > 0, !options.isEmpty else { return }
        let index = Int((drag.location.x / width * CGFloat(options.count)).rounded(.down))
        let option = options[min(max(index, 0), options.count - 1)]
        if option != selection { withAnimation(.glide) { selection = option } }
      })
    .sensoryFeedback(.selection, trigger: selection)
  }
}

extension SlidingPicker {
  /// For a choice that always has a value.
  init(options: [Value], selection: Binding<Value>, @ViewBuilder label: @escaping (Value, Bool) -> Label) {
    self.options = options
    self._selection = Binding(get: { selection.wrappedValue }, set: { if let v = $0 { selection.wrappedValue = v } })
    self.label = label
  }
}
