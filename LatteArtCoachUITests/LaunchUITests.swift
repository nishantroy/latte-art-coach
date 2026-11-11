import XCTest

final class LaunchUITests: XCTestCase {
  @MainActor
  func testLaunchShowsTitle() throws {
    let app = XCUIApplication()
    app.launch()
    XCTAssertTrue(app.staticTexts["Lattelier"].waitForExistence(timeout: 10))
    let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    shot.name = "launch"
    shot.lifetime = .keepAlways
    add(shot)
  }
}
