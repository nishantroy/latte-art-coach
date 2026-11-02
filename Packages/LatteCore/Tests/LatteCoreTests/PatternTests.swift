import Testing
@testable import LatteCore

@Test func heartIsTheOnlySupportedPattern() {
  #expect(Pattern.allCases == [.heart])
  #expect(Pattern.heart.displayName == "Heart")
}
