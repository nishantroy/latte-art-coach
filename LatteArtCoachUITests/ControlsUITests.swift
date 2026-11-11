import XCTest

/// The tactile controls do what they show: dragging a ruler dial sets
/// its value.
@MainActor
final class ControlsUITests: XCTestCase {
  func testDraggingTheDoseDialSetsTheDose() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-uitest"]
    app.launch()
    let choose = app.buttons["Choose a photo"]
    XCTAssertTrue(choose.waitForExistence(timeout: 15))
    choose.tap()
    let photos = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo'"))
    XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 60))
    sleep(1)
    let screen = app.windows.firstMatch.frame
    let newest = try XCTUnwrap(photos.allElementsBoundByIndex
      .filter { $0.frame.width > 20 && screen.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
      .min { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) })
    newest.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    XCTAssertTrue(app.buttons["rating-7"].waitForExistence(timeout: 30))
    app.buttons["reveal"].tap()  // "Skip" isn't needed: reveal is enabled once rated
    if !app.staticTexts["overall-score"].waitForExistence(timeout: 3) {
      app.buttons["rating-7"].tap()
      app.buttons["reveal"].tap()
    }
    let card = app.buttons["drink-card"]
    for _ in 0..<8 where !card.isHittable { app.swipeUp() }
    card.tap()

    let dose = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Dose'")).firstMatch
    XCTAssertTrue(dose.waitForExistence(timeout: 5))
    print("DOSE frame \(dose.frame) value \(String(describing: dose.value))")
    XCTAssertEqual(dose.value as? String, "not set")
    // The ruler sits under the readout (the element) and runs off
    // screen both ways; drag across its visible middle.
    let origin = app.coordinate(withNormalizedOffset: .zero)
    let y = dose.frame.maxY + 28, mid = app.windows.firstMatch.frame.midX
    origin.withOffset(CGVector(dx: mid + 60, dy: y))
      .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: mid - 40, dy: y)))
    sleep(1)
    print("DOSE after drag \(String(describing: dose.value))")
    let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    shot.lifetime = .keepAlways
    add(shot)
    let value = try XCTUnwrap(dose.value as? String)
    XCTAssertNotEqual(value, "not set", "Dragging the ruler didn't set the dose")
    let grams = Double(value.split(separator: " ").first ?? "") ?? 0
    XCTAssertGreaterThan(grams, 18, "Dragging left should raise the dose from 18 g; got \(value)")
  }
}
