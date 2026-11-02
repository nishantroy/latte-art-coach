import Foundation
@testable import LatteCore

enum Fixtures {
  static func pourURL(_ number: Int) -> URL {
    Bundle.module.url(forResource: String(format: "pour-%02d", number), withExtension: "jpg", subdirectory: "Fixtures/pours")!
  }

  static let pours = Array(1...6)

  /// Where tests write debug overlays (set LATTE_DEBUG_DIR to inspect them).
  static var debugDirectory: URL? {
    guard let path = ProcessInfo.processInfo.environment["LATTE_DEBUG_DIR"], !path.isEmpty else { return nil }
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
