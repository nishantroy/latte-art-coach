import SwiftUI
import UIKit

/// The app's palette, taken from the cup:
/// - crema: the brand color (buttons, selection, accents)
/// - measure: amber, for anything the app measured (score arc, axis, trends)
/// - milk / card: warm page and card backgrounds
extension Color {
  static let crema = Color(light: 0xB8763A, dark: 0xD99A5B)
  static let measure = Color(light: 0xE9A21F, dark: 0xF2B33D)
  static let milk = Color(light: 0xF6EEE3, dark: 0x15100C)
  static let card = Color(light: 0xFFFBF5, dark: 0x241A14)
  static let espresso = Color(light: 0x2A1C14, dark: 0xF6EEE3)
  /// Terracotta, for weak scores: warm like the rest, never traffic-light red.
  static let weak = Color(light: 0xB5533A, dark: 0xD9785E)

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
  /// New York, for titles: a café menu rather than a settings screen.
  static func display(_ style: Font.TextStyle) -> Font { .system(style, design: .serif).weight(.semibold) }
  /// Rounded numerals for scores.
  static func number(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
}

extension View {
  /// A warm card: the standard container for sections.
  func card() -> some View {
    padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.card, in: .rect(cornerRadius: 16))
      .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.crema.opacity(0.15)))
  }
}

extension Animation {
  /// The app's one motion curve for state changes: quick, no bounce.
  static let settle = Animation.smooth(duration: 0.35)
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

/// A 0–1 bar for a measured part of the score: amber, or terracotta when
/// it's weak. Fills in when it appears.
struct Meter: View {
  let value: Double
  @State private var shown = 0.0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(Color.crema.opacity(0.15))
        Capsule()
          .fill(value >= 0.5 ? Color.measure : Color.weak)
          .frame(width: max(6, proxy.size.width * min(max(shown, 0), 1)))
      }
    }
    .frame(height: 6)
    .onAppear {
      if reduceMotion { shown = value } else { withAnimation(.smooth(duration: 0.7).delay(0.1)) { shown = value } }
    }
    .onChange(of: value) { withAnimation(.settle) { shown = value } }
    .accessibilityHidden(true)
  }
}

enum Theme {
  /// Serif navigation titles everywhere.
  @MainActor static func configure() {
    func serif(_ style: UIFont.TextStyle) -> UIFont {
      let base = UIFont.preferredFont(forTextStyle: style)
      let descriptor = base.fontDescriptor.withDesign(.serif)?.withSymbolicTraits(.traitBold) ?? base.fontDescriptor
      return UIFont(descriptor: descriptor, size: 0)
    }
    UINavigationBar.appearance().titleTextAttributes = [.font: serif(.headline)]
    UINavigationBar.appearance().largeTitleTextAttributes = [.font: serif(.largeTitle)]
  }
}
