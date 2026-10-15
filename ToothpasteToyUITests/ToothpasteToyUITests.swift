// ToothpasteToyUITests.swift — OWNER: UI (Documentation/REDESIGN-OWNERSHIP.md).
//
// Real-input checks of the Metro Station screen through XCUITest (the app runs as itself; taps, holds and drags are
// synthesised by the test runner, which reads the app's accessibility tree from outside): the press-and-hold Squeeze
// extrudes a ribbon and tears it off on release, the crowns' ± buttons and face drags step Gravity through named worlds
// and Heat by single degrees, a drag in the chamber drives the glass lens, the pastes sheet fills another paste, and
// More, the Rheometer and "How Toothpaste Toy works" open (the last with the honesty sentence). Nothing in the app
// switches on libAccessibility's automation flag (that froze the simulator for every later launch; progress-ui.md).
//
// Timeouts are generous: the host is shared and often heavily loaded.

import XCTest

final class ToothpasteToyUITests: XCTestCase {
  // MARK: Helpers

  @MainActor private func launch(_ extra: [String] = []) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-noPersist", "-quietSensors"] + extra
    app.launch()
    XCTAssertTrue(element(app, "holo-chamber").waitForExistence(timeout: 120), "the chamber appears")
    return app
  }

  @MainActor private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: id).firstMatch
  }

  @MainActor private func value(_ e: XCUIElement) -> String { (e.value as? String) ?? "" }

  /// Waits until `condition` holds (re-evaluated every 0.25 s).
  @MainActor private func wait(_ seconds: Double, _ condition: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
      if condition() { return true }
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    return condition()
  }

  // MARK: Tests

  /// The Metro screen's parts are all there: chamber, three pills, lens readout, event tiles, telemetry, both crowns,
  /// the Squeeze cap and the five floating actions.
  @MainActor func testTheScreenHasEveryPart() {
    let app = launch()
    for id in [
      "pill-shear", "pill-stress", "pill-structure", "lens-readout", "event-tiles", "crown-gravity", "crown-heat",
      "crown-squeeze", "action-refill", "action-freeze", "action-squeeze", "action-rheometer", "action-info",
      "header-pastes", "header-more", "squeeze-requested", "ribbon-readout",
    ] {
      XCTAssertTrue(element(app, id).waitForExistence(timeout: 20), id)
    }
  }

  /// Holding Squeeze extrudes paste (the ribbon readout grows); letting go stops it (the requested rate returns to 0).
  @MainActor func testHoldingSqueezeExtrudesARibbon() {
    let app = launch()
    let squeeze = element(app, "action-squeeze")
    XCTAssertTrue(squeeze.waitForExistence(timeout: 20))
    squeeze.press(forDuration: 2.5)
    let requested = element(app, "squeeze-requested")
    XCTAssertTrue(wait(10) { self.value(requested) == "Not squeezing" }, "released: \(value(requested))")
    let ribbon = element(app, "ribbon-readout")
    XCTAssertTrue(
      wait(10) { (Int(self.value(ribbon).split(separator: " ").first ?? "") ?? 0) > 0 }, "ribbon: \(value(ribbon))")
  }

  /// Gravity's minus button steps from Earth to Mars; plus goes back; a face drag moves it again.
  @MainActor func testGravityCrownStepsThroughNamedWorlds() {
    let app = launch()
    let crown = element(app, "crown-gravity")
    XCTAssertTrue(crown.waitForExistence(timeout: 20))
    XCTAssertTrue(value(crown).contains("Earth"), value(crown))
    element(app, "crown-gravity-minus").tap()
    XCTAssertTrue(wait(5) { self.value(crown).contains("Mars") }, value(crown))
    element(app, "crown-gravity-plus").tap()
    XCTAssertTrue(wait(5) { self.value(crown).contains("Earth") }, value(crown))
    // A quarter turn clockwise on the knurled face, top to right edge.
    let top = crown.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
    let right = crown.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5))
    top.press(forDuration: 0.1, thenDragTo: right, withVelocity: 120, thenHoldForDuration: 0.2)
    XCTAssertTrue(wait(5) { !self.value(crown).contains("Earth") }, "the face turned gravity: \(value(crown))")
  }

  /// Heat's plus and minus move one degree each.
  @MainActor func testHeatCrownMovesOneDegree() {
    let app = launch()
    let crown = element(app, "crown-heat")
    XCTAssertTrue(crown.waitForExistence(timeout: 20))
    let before = value(crown)
    element(app, "crown-heat-plus").tap()
    XCTAssertTrue(wait(5) { self.value(crown) != before }, value(crown))
    XCTAssertTrue(value(crown).contains("21"), value(crown))
    element(app, "crown-heat-minus").tap()
    XCTAssertTrue(wait(5) { self.value(crown).contains("20") }, value(crown))
  }

  /// A drag in the chamber puts the lens in the paste (the readout's title says so while the finger is down is not
  /// observable from outside, so this checks the chamber survives the drag and the probe reads a stress).
  @MainActor func testDraggingInTheChamberPokesThePaste() {
    let app = launch()
    let chamber = element(app, "holo-chamber")
    let start = chamber.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.75))
    let end = chamber.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.85))
    start.press(forDuration: 0.1, thenDragTo: end, withVelocity: 300, thenHoldForDuration: 0.3)
    XCTAssertTrue(chamber.exists)
    XCTAssertTrue(value(chamber).contains("Stress"), value(chamber))
  }

  /// Other pastes: honey fills the chamber and the sheet closes.
  @MainActor func testPastesSheetFillsAnotherPaste() {
    let app = launch()
    element(app, "header-pastes").tap()
    let honey = element(app, "paste-honey")
    XCTAssertTrue(honey.waitForExistence(timeout: 20))
    honey.tap()
    XCTAssertTrue(wait(10) { !self.element(app, "pastes").exists }, "the sheet closes")
    let chamber = element(app, "holo-chamber")
    XCTAssertTrue(wait(10) { (chamber.label).contains("honey") }, chamber.label)
  }

  @MainActor func testMoreSheetOpensAndCloses() {
    let app = launch()
    element(app, "header-more").tap()
    XCTAssertTrue(element(app, "more-stripes").waitForExistence(timeout: 20))
    element(app, "more-done").tap()
    XCTAssertTrue(wait(10) { !self.element(app, "more-stripes").exists })
  }

  @MainActor func testInfoSheetSaysTheHologramIsALook() {
    let app = launch()
    element(app, "action-info").tap()
    let honesty = element(app, "info-honesty")
    XCTAssertTrue(honesty.waitForExistence(timeout: 20))
    XCTAssertTrue(honesty.label.contains("not quantum mechanics"), honesty.label)
  }

  @MainActor func testRheometerOpens() {
    let app = launch()
    element(app, "action-rheometer").tap()
    XCTAssertTrue(element(app, "rheometer-curve").waitForExistence(timeout: 20))
  }

  /// Freeze toggles to Resume and back.
  @MainActor func testFreezeToggles() {
    let app = launch()
    let freeze = element(app, "action-freeze")
    XCTAssertTrue(freeze.waitForExistence(timeout: 20))
    XCTAssertEqual(freeze.label, "Freeze time")
    freeze.tap()
    XCTAssertTrue(wait(5) { freeze.label == "Resume time" }, freeze.label)
    freeze.tap()
    XCTAssertTrue(wait(5) { freeze.label == "Freeze time" }, freeze.label)
  }
}
