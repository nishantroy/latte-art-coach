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
