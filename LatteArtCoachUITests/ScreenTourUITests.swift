import XCTest

/// Walks every main screen and saves a screenshot of each, for design
/// review. Asserts little: it's a camera, not a test of behavior.
/// Run alone: UI=1 ONLY=LatteArtCoachUITests/ScreenTourUITests scripts/test.sh
@MainActor
final class ScreenTourUITests: XCTestCase {
  let app = XCUIApplication()

  func testTourEveryScreen() throws {
    continueAfterFailure = true
    app.launchArguments = ["-uitest"]
    app.launch()
    let choose = app.buttons["Choose a photo"]
    XCTAssertTrue(choose.waitForExistence(timeout: 15))
    app.buttons["Tulip"].tap()
    capture("01-home")

    try scoreNewestPhoto(choose)

    let seven = app.buttons["rating-7"]
    XCTAssertTrue(seven.waitForExistence(timeout: 30))
    capture("02-rate-first")
    seven.tap()
    app.buttons["reveal"].tap()
    XCTAssertTrue(app.staticTexts["overall-score"].waitForExistence(timeout: 10))
    sleep(2)
    capture("03-result-top")
    app.swipeUp()
    capture("03-result-scroll-01")
    let details = app.buttons["score-details"].firstMatch
    for _ in 0..<4 where !details.isHittable { app.swipeUp() }
    if details.isHittable { details.tap() }
    sleep(1)
    capture("03-result-scroll-02")
    app.swipeUp()
    capture("03-result-scroll-03")

    // The drink sheet and the bean form on top of it.
    let brew = app.buttons["drink-card"]
    for _ in 0..<8 where !brew.isHittable { app.swipeDown() }
    if brew.isHittable {
      brew.tap()
      sleep(1)
      capture("04-brew-editor")
      let add = app.buttons["Add new beans…"]
      if add.waitForExistence(timeout: 3) {
        add.tap()
        sleep(1)
        capture("05-new-beans")
        let name = app.textFields["Name, e.g. Guji Hambela"]
        if name.waitForExistence(timeout: 3) {
          name.tap()
          name.typeText("Hambela")
          app.textFields["Roaster"].tap()
          app.textFields["Roaster"].typeText("Onyx")
          app.buttons["Save"].tap()
        }
      }
      sleep(1)
      // Close the drink sheet. The keyboard has a Done key too, so tap the
      // one in the sheet's navigation bar until the sheet is gone.
      let sheet = app.navigationBars["Your drink"]
      for _ in 1...3 where sheet.exists {
        sheet.buttons["Done"].tap()
        sleep(1)
      }
    }

    goHome()
    XCTAssertTrue(choose.waitForExistence(timeout: 5))
    // A second tulip, so History has a trend to chart.
    try scoreNewestPhoto(choose)
    app.buttons["rating-8"].tap()
    app.buttons["reveal"].tap()
    _ = app.staticTexts["overall-score"].waitForExistence(timeout: 10)
    goHome()
    XCTAssertTrue(choose.waitForExistence(timeout: 5))
    capture("06-home-with-history")
    app.tabBars.buttons["History"].tap()
    sleep(1)
    capture("07-history")
    let row = app.descendants(matching: .any).matching(identifier: "pour-row").firstMatch
    if row.waitForExistence(timeout: 5) {
      row.tap()
      _ = app.staticTexts["overall-score"].waitForExistence(timeout: 20)
      sleep(1)
      capture("08-history-detail")
    }
    app.tabBars.buttons["Beans"].tap()
    sleep(1)
    capture("09-beans")
    let bean = app.descendants(matching: .any).matching(identifier: "bean-row").firstMatch
    if bean.waitForExistence(timeout: 3) {
      bean.tap()
      sleep(1)
      capture("10-bean-detail")
    }
  }

  /// Opens the photo picker and picks the newest photo; returns once the
  /// rating step is up.
  private func scoreNewestPhoto(_ choose: XCUIElement) throws {
    for _ in 1...3 {
      choose.tap()
      let gone = expectation(for: NSPredicate(format: "hittable == false"), evaluatedWith: choose)
      if XCTWaiter.wait(for: [gone], timeout: 8) == .completed { break }
    }
    let photos = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo'"))
    let deadline = Date().addingTimeInterval(60)
    while photos.count == 0 && Date() < deadline { _ = photos.firstMatch.waitForExistence(timeout: 1) }
    let screen = app.windows.firstMatch.frame
    let visible = photos.allElementsBoundByIndex.filter {
      $0.frame.width > 20 && screen.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
    }
    let newest = try XCTUnwrap(visible.min { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) })
    // A tap while the picker is still settling can be dropped; tap again
    // while the picker is up and the rating step hasn't appeared.
    for _ in 1...3 {
      newest.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      if app.buttons["rating-7"].waitForExistence(timeout: 20) || !newest.exists { break }
    }
    XCTAssertTrue(app.buttons["rating-7"].waitForExistence(timeout: 30))
  }

  /// "Pour another", at the end of the result. A tap while the scroll is
  /// still moving only stops it, so let it settle and retry.
  private func goHome() {
    let again = app.buttons["pour-another"]
    for _ in 0..<8 where !again.isHittable { app.swipeUp() }
    for _ in 1...3 {
      sleep(1)
      again.tap()
      if app.buttons["Choose a photo"].waitForExistence(timeout: 3) { return }
    }
  }

  private func capture(_ name: String) {
    let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
  }
}
