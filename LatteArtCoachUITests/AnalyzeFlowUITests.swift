import XCTest

/// Picks the newest photo in the library (scripts/test.sh adds fixture pour 3)
/// and checks that a score appears.
final class AnalyzeFlowUITests: XCTestCase {
  @MainActor
  func testScoresAPhotoFromTheLibrary() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    let choose = app.buttons["Choose a photo"]
    XCTAssertTrue(choose.waitForExistence(timeout: 15))
    // The chosen pattern persists between launches; score the fixture as a tulip.
    app.buttons["Tulip"].tap()
    capture("1-start")
    // An early tap can land before the button responds; retry until the picker covers it.
    for _ in 1...3 {
      choose.tap()
      let gone = expectation(for: NSPredicate(format: "hittable == false"), evaluatedWith: choose)
      if XCTWaiter.wait(for: [gone], timeout: 8) == .completed { break }
    }

    // The system picker runs out of process; its cells report isHittable == false,
    // and the newest photo is the top-left cell, so tap that one by coordinate.
    let photos = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo'"))
    let deadline = Date().addingTimeInterval(60)
    while photos.count == 0 && Date() < deadline { _ = photos.firstMatch.waitForExistence(timeout: 1) }
    XCTAssertGreaterThan(photos.count, 0, "No photos in the picker")
    let screen = app.windows.firstMatch.frame
    let visible = photos.allElementsBoundByIndex.filter {
      $0.frame.width > 20 && screen.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
    }
    let newest = try XCTUnwrap(visible.min { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) })
    newest.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

    let score = app.staticTexts["overall-score"]
    XCTAssertTrue(score.waitForExistence(timeout: 20), "No score appeared")
    capture("2-result")
    let value = try XCTUnwrap(Int(score.label))
    XCTAssertTrue((70...95).contains(value), "Unexpected score \(value) for fixture pour 3")
    print("ANALYSIS: \(app.staticTexts["analysis-duration"].label)")
    XCTAssertTrue(app.navigationBars["Your tulip"].exists)

    // Re-score the same photo as a rosetta without picking it again.
    app.buttons["Rosetta"].tap()
    XCTAssertTrue(app.navigationBars["Your rosetta"].waitForExistence(timeout: 5), "Re-scoring didn't switch the pattern")
    XCTAssertTrue(score.exists)
    print("AS ROSETTA: \(score.label)")
    capture("2b-rescored-rosetta")
    app.swipeUp()
    capture("3-result-scrolled")
  }

  private func capture(_ name: String) {
    let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
  }
}
