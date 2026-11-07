import XCTest

/// Picks the newest photo in the library (scripts/test.sh adds fixture pour 3)
/// and checks that a score appears.
final class AnalyzeFlowUITests: XCTestCase {
  @MainActor
  func testScoresAPhotoFromTheLibrary() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-uitest"]  // empty, in-memory history
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
    // A tap while the picker is still settling can be dropped; tap again
    // while the picker is up and the rating step hasn't appeared.
    for _ in 1...3 {
      newest.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      if app.buttons["rating-7"].waitForExistence(timeout: 20) || !newest.exists { break }
    }

    // Rate first: the score stays hidden until the pour is rated.
    let seven = app.buttons["rating-7"]
    XCTAssertTrue(seven.waitForExistence(timeout: 30), "Rating step didn't appear")
    XCTAssertFalse(app.staticTexts["overall-score"].exists, "Score shown before rating")
    let reveal = app.buttons["reveal"]
    XCTAssertFalse(reveal.isEnabled, "Reveal should wait for a rating")
    capture("2-rate-first")
    seven.tap()
    let selected = expectation(for: NSPredicate(format: "selected == true"), evaluatedWith: seven)
    XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 3), .completed, "Rating didn't show as selected")
    reveal.tap()

    let score = app.staticTexts["overall-score"]
    XCTAssertTrue(score.waitForExistence(timeout: 10), "No score appeared")
    sleep(2)  // let the arc finish filling for the screenshot
    capture("3-result")
    let value = try XCTUnwrap(Int(score.label))
    XCTAssertTrue((70...95).contains(value), "Unexpected score \(value) for fixture pour 3")
    XCTAssertTrue(app.staticTexts["You rated it 7/10"].exists)
    XCTAssertTrue(app.navigationBars["Your tulip"].exists)

    // Re-score the same photo as a rosetta without picking it again
    // (under the folded "Score details").
    let details = app.buttons["score-details"].firstMatch
    for _ in 0..<6 where !details.isHittable { app.swipeUp() }
    details.tap()
    let rosetta = app.buttons["Rosetta"].firstMatch
    if !rosetta.waitForExistence(timeout: 3) {
      details.tap()
      XCTAssertTrue(rosetta.waitForExistence(timeout: 3), "Score details didn't open")
    }
    for _ in 0..<4 where !rosetta.isHittable { app.swipeUp() }
    capture("3a-result-scrolled")
    rosetta.tap()
    XCTAssertTrue(app.navigationBars["Your rosetta"].waitForExistence(timeout: 5), "Re-scoring didn't switch the pattern")
    XCTAssertTrue(score.exists)

    // Coaching: from the on-device model when Apple Intelligence is on,
    // otherwise the rule-based tips (the Simulator usually can't run the
    // model; pour 3 scored as a rosetta gets "Thinner leaves").
    // Re-scoring restarts the coaching, so wait for it (or the fallback).
    let anyCoaching = { (id: String) in app.descendants(matching: .any).matching(identifier: id).firstMatch.exists }
    let coachDeadline = Date().addingTimeInterval(40)
    var coached = false
    while !coached && Date() < coachDeadline {
      coached = anyCoaching("coach-focus") || anyCoaching("coach-thinking") || app.staticTexts["Thinner leaves"].exists
      if !coached { sleep(1) }
    }
    if !coached { print("COACHING TREE:\n\(app.debugDescription)") }
    XCTAssertTrue(coached, "No coaching or fallback tips shown")

    // The pour shows up in history with its rating.
    // It's the last thing on the page: scroll to the end, then tap.
    let again = app.buttons["pour-another"]
    for _ in 0..<5 { app.swipeUp() }
    XCTAssertTrue(again.waitForExistence(timeout: 5))
    again.tap()
    app.tabBars.buttons["History"].tap()
    XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
    let row = app.descendants(matching: .any).matching(identifier: "pour-row").firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5), "No pour in history")
    XCTAssertTrue(row.label.contains("You: 7/10"), "Row: \(row.label)")
    capture("4-history")
    row.tap()
    let opened = app.staticTexts["overall-score"].waitForExistence(timeout: 20)
    if !opened { capture("5-detail-missing"); print("DETAIL TREE:\n\(app.debugDescription)") }
    XCTAssertTrue(opened, "Saved pour didn't open")
    capture("5-history-detail")
  }

  private func capture(_ name: String) {
    let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
  }
}
