// UITests.swift — OWNER: UI (Documentation/REDESIGN-OWNERSHIP.md).
//
// Unit tests of the Metro Station screen's copy and logic (XCTest, no UI automation):
// 1. CopyLint over every user-facing string the UI owns or shows: British spelling, UI named by its live labels, the
//    house voice, the honesty sentence (REDESIGN.md §6) verbatim, "oobleck" rather than its recipe.
// 2. Numbers: quantities with whole digits where whole, prefixes, the spoken values.
// 3. The chamber's geometry (the contract with HOLO: region + housing band, tank aspect, dock).
// 4. Metro behaviour: crown detents (spacing, hysteresis, seam, one step per update, the 20 Hz gate), named detents
//    for Gravity, the event attack/decay envelope, constant pill semantics, the lens motion writing the hub's lens.
// 5. Licences (Box2D, PB-MPM, Wave) complete and verbatim; published points against the modelled curves.
// Plus an opt-in screenshot tour (`TEST_RUNNER_TT_UI_SHOTS=1`) that renders the real screen in the test host.

import LabKitCore
import LabKitMPM
import LabKitSensors
import LabKitUI
import Metal
import SwiftUI
import UIKit
import XCTest

@testable import ToothpasteToy

final class UITests: XCTestCase {
  // MARK: Copy

  @MainActor func testCopyLintOverEveryUIString() {
    let catalog = ToothpasteCatalogData()
    let store = ParamStore(catalog.specs)
    let known = Set(
      catalog.specs.map(\.title) + catalog.pages.map(\.title)
        + [ToothpasteCopy.rheometer, ToothpasteCopy.squeezeTitle, ToothpasteCopy.more])
    let strings = ToothpasteCopy.allStrings(catalog: catalog, store: store)
    XCTAssertGreaterThan(strings.count, 250, "the lint sees the whole UI")
    for s in strings {
      XCTAssertFalse(s.isEmpty)
      XCTAssertEqual(CopyLint.americanSpellings(in: s), [], "American spelling in “\(s)”")
      XCTAssertEqual(CopyLint.unknownUINames(in: s, known: known), [], "unknown UI name in “\(s)”")
      var lower = " " + s.lowercased() + " "
      for barely in ["just denser", "just above", "just below", "just over", "just under"] {
        lower = lower.replacingOccurrences(of: barely, with: "barely")
      }
      for banned in [" simply ", " just ", " we ", " we're ", " our ", "magic"] {
        XCTAssertFalse(lower.contains(banned), "“\(banned.trimmingCharacters(in: .whitespaces))” in “\(s)”")
      }
      XCTAssertFalse(s.contains("!"), "exclamation mark in “\(s)”")
      XCTAssertFalse(s.contains("~"), "write “about”, not “~”: “\(s)”")
      let recipeFree = lower.replacingOccurrences(of: ToothpasteCopy.oobleckRecipe.lowercased(), with: "")
      XCTAssertFalse(recipeFree.contains("cornstarch") || recipeFree.contains("cornflour"), "say oobleck: “\(s)”")
      XCTAssertFalse(s.contains("  "), "double space in “\(s)”")
    }
  }

  /// REDESIGN.md §6: the info sheet says plainly that the hologram is a look, verbatim; every mention of "quantum" sits
  /// next to that honesty.
  @MainActor func testHonestySentenceIsVerbatim() {
    XCTAssertEqual(
      ToothpasteCopy.honestySentence,
      "The paste obeys real yield-stress physics. The quantum shimmer, ghosts and fringes are a hologram look, not quantum mechanics.")
    let honesty = ToothpasteCopy.honesty(
      tank: MPMDomain.lifeSizeTank, gap: 0.01, cell: 0.002, lifeSize: false, scale: 0.66, honeyRatio: 200)
    XCTAssertTrue(honesty.contains { $0.contains("nothing quantum is computed") })
    XCTAssertTrue(honesty.contains("The tank is 71 × 101 mm, drawn at ×0.66 on this phone."))
    XCTAssertTrue(ToothpasteCopy.lookFootnote.contains("is a look"))
    XCTAssertTrue(ToothpasteCopy.method(particles: 3000, cell: 0.002).contains("Wave springs"))
  }

  @MainActor func testHonestyClaimsNoScaleOnAnUnknownPhone() {
    let lines = ToothpasteCopy.honesty(
      tank: SIMD2(0.0712, 0.1009), gap: 0.003, cell: 0.002, lifeSize: false, scale: nil, honeyRatio: 230)
    XCTAssertTrue(lines.contains("The tank is 71 × 101 mm, drawn to fit this screen."))
    XCTAssertFalse(lines.contains { $0.contains("drawn at ×") })
  }

  @MainActor func testNamesAndNumbers() {
    XCTAssertEqual(ToothpasteCopy.inSentence("Oobleck"), "oobleck")
    XCTAssertEqual(ToothpasteCopy.inSentence("MR fluid"), "MR fluid")
    XCTAssertEqual(ToothpasteCopy.inSentence("Silly Putty"), "Silly Putty")
    XCTAssertEqual(ToothpasteCopy.millimetres(0.01), "10")
    XCTAssertEqual(ToothpasteCopy.millimetres(0.00198), "2.0")
    XCTAssertEqual(ToothpasteCopy.twoFigures(225.6), "230")
    XCTAssertEqual(ToothpasteCopy.multiplier(0.66), "×0.66")
    XCTAssertEqual(ToothpasteCopy.multiplier(2), "×2")
    // Whole digits where the quantity is whole (Metro contract 6), three figures elsewhere, k and m prefixes.
    XCTAssertTrue(ToothpasteCopy.quantity(250, unit: "Pa") == ("250", "Pa"))
    XCTAssertTrue(ToothpasteCopy.quantity(12.44, unit: "Pa·s") == ("12.4", "Pa·s"))
    XCTAssertTrue(ToothpasteCopy.quantity(1200, unit: "Pa") == ("1.20", "kPa"))
    XCTAssertTrue(ToothpasteCopy.quantity(0.001, unit: "Pa·s") == ("1.00", "mPa·s"))
    XCTAssertTrue(ToothpasteCopy.quantity(1200, unit: "s⁻¹") == ("1.20k", "s⁻¹"))
    XCTAssertTrue(ToothpasteCopy.quantity(0.042, unit: "s⁻¹") == ("0.042", "s⁻¹"))
    XCTAssertTrue(ToothpasteCopy.quantity(.nan, unit: "Pa") == ("0", "Pa"))
    XCTAssertEqual(ToothpasteCopy.squeezeSpoken(rate: 0), "Not squeezing")
    XCTAssertEqual(ToothpasteCopy.squeezeSpoken(rate: 23.6), "24 millimetres per second")
    XCTAssertEqual(ToothpasteCopy.heatFooter(named: "Room"), "Room · ±1 °C")
    XCTAssertEqual(ToothpasteCopy.gravityCaption(here: "Moon", value: "0.17 g"), "GRAVITY · Moon")
    XCTAssertEqual(ToothpasteCopy.gravityCaption(here: nil, value: "0.50 g"), "GRAVITY · 0.50 g")
    XCTAssertEqual(
      ToothpasteCopy.actionNames,
      ["Poke the paste", "Squeeze a ribbon", "Punch", "Tilt left", "Tilt right", "Shake", "Refill"])
  }

  @MainActor func testChamberValueIsAParseableSentence() {
    let c = ToothpasteCatalogData()
    var t = ToothpasteTelemetry()
    t.tiltDegrees = 12.4
    t.fillFraction = 0.31
    var ch = PasteChannels()
    ch.shear = SignalChannel(value: 12.4, level: 0.6)
    ch.stress = SignalChannel(value: 250, level: 0.6)
    ch.state = .yielding
    let s = ToothpasteCopy.chamberValue(t, channels: ch, material: c.material("toothpaste"), paused: false)
    XCTAssertTrue(s.hasPrefix("Toothpaste. Yielding. Shear rate 12.4"), s)
    XCTAssertTrue(s.contains("Tilt 12 degrees"), s)
    XCTAssertTrue(s.contains("31 percent full"), s)
    XCTAssertTrue(ToothpasteCopy.chamberValue(t, channels: ch, material: c.material("honey"), paused: true).contains("Time frozen"))
  }

  @MainActor func testPillsSayTheirScales() {
    var ch = PasteChannels()
    ch.shear = SignalChannel(value: 10, level: 0.6)
    ch.structure = SignalChannel(value: 0.42, level: 0.42)
    XCTAssertTrue(ToothpasteCopy.pillSpoken(.shear, channels: ch).contains("60 percent up the scale"))
    XCTAssertTrue(ToothpasteCopy.pillSpoken(.shear, channels: ch).contains("logarithmic from 0.01 to 1000 per second"))
    XCTAssertTrue(ToothpasteCopy.pillSpoken(.structure, channels: ch).hasPrefix("42 percent structure"))
    // Titles and ends are constants (Metro contract 5): the same whatever the value.
    XCTAssertEqual(PasteSignal.allCases.map(\.title), ["γ̇", "σ", "λ"])
    XCTAssertEqual(PasteSignal.shear.ends.0, "1k")
    XCTAssertEqual(PasteSignal.stress.ends.1, "1")
  }

  // MARK: Chamber geometry (the contract with HOLO)

  func testChamberGeometryKeepsTheTankAspectAndTheBand() {
    let tank = MPMDomain.lifeSizeTank
    let g = ChamberGeometry.fitting(tank: tank, width: 302, height: 437)
    XCTAssertTrue(g.isValid)
    // Band: 2.5 mm left/right, 3.5 mm above, 5.5 mm below the floor, in tank millimetres × scale.
    XCTAssertEqual(g.region.minX, 2.5 * g.scale, accuracy: 1e-9)
    XCTAssertEqual(g.region.minY, 3.5 * g.scale, accuracy: 1e-9)
    XCTAssertEqual(g.size.width - g.region.maxX, 2.5 * g.scale, accuracy: 1e-9)
    XCTAssertEqual(g.size.height - g.region.maxY, 5.5 * g.scale, accuracy: 1e-9)
    // The region has exactly the tank's aspect, so TankView maps the tank onto it with no headspace.
    XCTAssertEqual(g.region.width / g.region.height, tank.x / tank.y, accuracy: 1e-9)
    XCTAssertLessThanOrEqual(g.size.width, 302 + 1e-9)
    XCTAssertLessThanOrEqual(g.size.height, 437 + 1e-9)
    var view = TankView(tankSize: tank, regionSize: g.region.size, metresPerPoint: 0.16565e-3)
    view.zoom = 1
    XCTAssertEqual(Double(view.worldRect.width), tank.x, accuracy: 1e-9)
    XCTAssertEqual(Double(view.worldRect.height), tank.y, accuracy: 1e-9)
    // Tank metres ↔ chamber points round trip through the hub's region mapping.
    let p = g.chamberPoint(tank: SIMD2(0.02, 0.03))
    let back = view.tankPoint(g.regionPoint(fromChamber: p))
    XCTAssertEqual(back.x, 0.02, accuracy: 1e-6)
    XCTAssertEqual(back.y, 0.03, accuracy: 1e-6)
    // The dock sits in the headspace's top-left corner, the lens wholly inside the region.
    let r = g.points(metres: LensState.defaultRadius)
    let dock = g.dock(lensRadius: r)
    XCTAssertGreaterThan(dock.x - r, g.region.minX)
    XCTAssertGreaterThan(dock.y - r, g.region.minY)
    XCTAssertLessThan(dock.x, g.region.midX)
    // Degenerate input lays nothing out.
    XCTAssertFalse(ChamberGeometry.fitting(tank: tank, width: 0, height: 400).isValid)
  }

  // MARK: Metro behaviour

  func testCrownDetentTracker() {
    var t = CrownDetentTracker(detentDegrees: 8)
    t.begin(angle: 0)
    XCTAssertEqual(t.update(angle: 7.9), 0, "below one detent")
    XCTAssertEqual(t.update(angle: 8.1), 1, "one detent clockwise")
    // A large jump gives one step, not a burst.
    XCTAssertEqual(t.update(angle: 60), 1)
    XCTAssertEqual(t.update(angle: 61), 0)
    // Reversal needs the detent plus 18 % hysteresis (1.44° at 8°).
    var r = CrownDetentTracker(detentDegrees: 8)
    r.begin(angle: 0)
    XCTAssertEqual(r.update(angle: 8), 1)
    XCTAssertEqual(r.update(angle: 0.5), 0, "7.5° back is not enough")
    XCTAssertEqual(r.update(angle: -1.5), -1, "9.5° back crosses 8 + 1.44")
    // The ±180° seam: 175° → −175° is +10°, one step.
    var s = CrownDetentTracker(detentDegrees: 8)
    s.begin(angle: 175)
    XCTAssertEqual(s.update(angle: -175), 1)
    XCTAssertEqual(CrownDetentTracker(detentDegrees: 20).hysteresisDegrees, 3.6, accuracy: 1e-9)
  }

  func testDetentGateCapsTheRateAndDropsReversals() {
    var g = DetentGate()
    g.begin()
    XCTAssertEqual(g.update(visualDelta: nil, detent: 1, now: 1.0, canStep: { _ in true }), 1)
    XCTAssertEqual(g.update(visualDelta: 8, detent: 1, now: 1.01, canStep: { _ in true }), 0, "inside 1/20 s")
    XCTAssertEqual(g.pending, 1, "a notch waits rather than queueing")
    XCTAssertEqual(g.update(visualDelta: -2, detent: 0, now: 1.02, canStep: { _ in true }), 0)
    XCTAssertEqual(g.pending, 0, "moving back clears it")
    XCTAssertEqual(g.update(visualDelta: 8, detent: 1, now: 1.2, canStep: { _ in false }), 0, "a refused step")
    XCTAssertEqual(g.update(visualDelta: 8, detent: 1, now: 1.21, canStep: { _ in true }), 1, "refusals use no interval")
  }

  @MainActor func testGravityStepsBetweenNamedWorlds() {
    let catalog = ToothpasteCatalogData()
    let store = ParamStore(catalog.specs)
    let spec = store.spec(.gravity)
    XCTAssertEqual(NamedDetents.list(spec).map(\.label), ["Zero-g", "Moon", "Mars", "Earth", "Jupiter"])
    XCTAssertEqual(NamedDetents.next(spec, from: 1, direction: -1)?.label, "Mars")
    XCTAssertEqual(NamedDetents.next(spec, from: 1, direction: 1)?.label, "Jupiter")
    XCTAssertNil(NamedDetents.next(spec, from: 2.53, direction: 1), "Jupiter is the end")
    XCTAssertEqual(NamedDetents.next(spec, from: 0.5, direction: 1)?.label, "Earth", "between worlds: the next one")
    XCTAssertEqual(NamedDetents.nearest(spec, to: 0.17)?.label, "Moon")
  }

  func testEventEnvelopeAttacksAndDecays() {
    XCTAssertEqual(EventPulses.envelope(elapsed: 0), 0)
    XCTAssertEqual(EventPulses.envelope(elapsed: EventPulses.attack), 1, accuracy: 1e-9)
    XCTAssertGreaterThan(EventPulses.envelope(elapsed: 0.2), EventPulses.envelope(elapsed: 0.5))
    XCTAssertEqual(EventPulses.envelope(elapsed: EventPulses.support), 0)
    XCTAssertEqual(EventPulses.envelope(elapsed: .nan), 0)
    var p = EventPulses()
    p.fire(.yield, at: 10)
    p.fire(.yield, at: 11)
    p.fire(.jam, at: 11)
    XCTAssertEqual(p.count(.yield), 2)
    XCTAssertEqual(p.energy(.jam, at: 11 + EventPulses.attack), 1, accuracy: 1e-9)
    XCTAssertEqual(p.energy(.tearOff, at: 11), 0)
    p.resetCounts()
    XCTAssertEqual(p.count(.yield), 0)
  }

  func testSpringValuesSettleAndKeepVelocity() {
    let spring = WaveSpring(dampingRatio: 1, response: 0.2)
    var s = SpringScalar(0)
    s.target = 10
    s.step(spring, dt: 1.0 / 15)
    XCTAssertGreaterThan(s.value, 0)
    XCTAssertGreaterThan(s.velocity, 0)
    for _ in 0..<60 { s.step(spring, dt: 1.0 / 60) }
    XCTAssertEqual(s.value, 10, accuracy: 0.01)
    // Retargeting mid-flight keeps the velocity (the hand-off).
    var p = SpringPoint(.zero)
    p.target = CGPoint(x: 100, y: 0)
    p.step(spring, dt: 0.05)
    let v = p.velocity.x
    p.target = CGPoint(x: -100, y: 0)
    XCTAssertEqual(p.velocity.x, v)
    XCTAssertGreaterThan(v, 0)
  }

  /// The lens motion writes the hub's lens every frame it is in the paste, and parks it inactive on release.
  @MainActor func testLensMotionDrivesTheHubLens() async throws {
    let model = ToothpasteModel(launch: ToothpasteLaunch.parse(["ToothpasteToy", "-noPersist"]), device: nil)
    let motion = ChamberMotion(model: model)
    let g = ChamberGeometry.fitting(tank: model.engine.tankSize, width: 302, height: 437)
    model.canvasRegion = g.region
    motion.geometry = g
    XCTAssertEqual(motion.lensCentre, g.dock(lensRadius: motion.lensRadius), "rests in its dock")
    motion.start()
    defer { motion.stop() }
    let target = g.chamberPoint(tank: SIMD2(0.03, 0.01))
    motion.touch(at: target)
    try await Task.sleep(for: .milliseconds(400))
    XCTAssertTrue(model.lens.active, "in the paste")
    XCTAssertEqual(model.lens.centre.x, 0.03, accuracy: 0.002)
    XCTAssertEqual(model.lens.centre.y, 0.01, accuracy: 0.002)
    motion.release()
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertFalse(model.lens.active, "parked on release")
  }

  /// The Squeeze sources write the hub's requested rate (and only one squeezes at a time).
  @MainActor func testSqueezeSourcesWriteTheRequestedRate() {
    let model = ToothpasteModel(launch: ToothpasteLaunch.parse(["ToothpasteToy", "-noPersist"]), device: nil)
    let motion = ChamberMotion(model: model)
    motion.setSqueeze(.button)
    XCTAssertEqual(model.squeeze.rate, ChamberMotion.buttonRate)
    motion.setSqueeze(.crown)
    XCTAssertEqual(model.squeeze.rate, ChamberMotion.holdRate)
    motion.crownReleased()
    XCTAssertEqual(model.squeeze.rate, 0, "letting go tears the ribbon off")
    XCTAssertEqual(motion.squeezeSource, .none)
    XCTAssertLessThanOrEqual(ChamberMotion.buttonRate, SqueezeState.maxRate)
  }

  // MARK: Plot, published points, licences

  @MainActor func testCurvesAreDrawnAtSensibleTemperatures() {
    let c = ToothpasteCatalogData()
    let honey = c.material("honey"), lava = c.material("lava")
    XCTAssertEqual(FlowCurvePlot.curveTemperature(honey, heatCelsius: 37), 310.15, accuracy: 1e-9)
    XCTAssertEqual(FlowCurvePlot.curveTemperature(lava, heatCelsius: 37), lava.fillTemperature, accuracy: 1e-9)
    XCTAssertEqual(FlowCurvePlot.curveTemperature(lava, heatCelsius: 1170), 1443.15, accuracy: 1e-9)
    XCTAssertEqual(FlowCurvePlot.curveTemperature(honey, heatCelsius: 1170), 293.15, accuracy: 1e-9)
  }

  @MainActor func testPlotSummaries() {
    let c = ToothpasteCatalogData()
    for m in c.materials {
      let s = ToothpasteCopy.plotSummary(m, catalog: c, temperature: m.fillTemperature)
      XCTAssertTrue(s.hasPrefix(m.title), s)
      XCTAssertTrue(s.hasSuffix("The pink ring is the probe in the chamber."), s)
    }
    XCTAssertTrue(ToothpasteCopy.plotSummary(c.material("toothpaste"), catalog: c, temperature: 293.15).contains("yield stress"))
  }

  @MainActor func testPublishedPointsAgreeWithTheModel() {
    let c = ToothpasteCatalogData()
    for temperature in [293.15, 310.15] {
      for id in ["honey", "waterLike"] {
        for p in LiteraturePoints.forMaterial(id).flatMap({ $0.points(temperature) }) {
          let model = c.flowCurve(id, shearRates: [p.x], temperature: temperature)[0]
          XCTAssertEqual(model / p.y, 1, accuracy: id == "honey" ? 0.10 : 0.15, "\(id) at \(p.x) s⁻¹, \(temperature) K")
        }
      }
    }
    for p in LiteraturePoints.all {
      for q in p.points(293.15) {
        XCTAssertNotNil(FlowCurvePlot.x.position(q.x), p.id)
        XCTAssertNotNil(FlowCurvePlot.stressAxis.position(q.y), p.id)
      }
    }
  }

  func testLicencesAreCompleteAndVerbatim() {
    XCTAssertTrue(ToothpasteLicences.box2d.text.contains("Copyright (c) 2022 Erin Catto"))
    XCTAssertEqual(ToothpasteLicences.box2d.citation.licence, "MIT")
    XCTAssertTrue(ToothpasteLicences.pbmpm.text.contains("Neither the name of Electronic Arts"))
    XCTAssertEqual(ToothpasteLicences.pbmpm.citation.licence, "BSD-3-Clause")
    XCTAssertTrue(ToothpasteLicences.wave.text.contains("Copyright (c) 2022 Janum Trivedi"))
    XCTAssertTrue(ToothpasteLicences.wave.text.contains("THE SOFTWARE IS PROVIDED \"AS IS\""))
    XCTAssertEqual(ToothpasteLicences.wave.citation.licence, "MIT")
    XCTAssertEqual(ToothpasteLicences.all.map(\.licence).sorted(), ["BSD-3-Clause", "MIT", "MIT"])
  }

  /// Metro tokens the screen relies on are the manifest's (spot checks against design-tokens.json).
  @MainActor func testMetroTokens() {
    XCTAssertEqual(Metro.Colour.canvas, Metro.RGB(0.025, 0.042, 0.058))
    XCTAssertEqual(Metro.Opacity.lensComposite, 0.48)
    XCTAssertEqual(Metro.Layout.crownDiameter, 62)
    XCTAssertEqual(Metro.Motion.fineDetentDegrees, 8)
    XCTAssertEqual(Metro.Motion.coarseDetentDegrees, 20)
    XCTAssertEqual(FloatingActions.reserve, 80)
  }
}

// MARK: - Screenshot tour (opt-in)

/// Renders the tour's states of the real screen inside the test host app, with the live Metal chamber, and writes
/// `tt-ui-<step>.png` plus `frames.txt` to the host app's temporary directory (paths printed as TT-UI-PNG). The route
/// for a host too loaded for `simctl launch`: `xcodebuild test` starts the host app another way. Opt in with
/// `TEST_RUNNER_TT_UI_SHOTS=1` (and `TEST_RUNNER_TT_UI_ONLY=<prefix,prefix>`).
final class UIScreenshotTour: XCTestCase {
  @MainActor func testScreenshotTour() async throws {
    let env = ProcessInfo.processInfo.environment
    guard env["TT_UI_SHOTS"] != nil else { throw XCTSkip("set TEST_RUNNER_TT_UI_SHOTS=1 to take the screenshots") }
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    let model = ToothpasteModel(launch: ToothpasteLaunch.parse(["ToothpasteToy", "-noPersist"]), device: device)
    let soundWas = model.feedback.sound
    model.feedback.sound = false
    defer {
      model.setActive(false)
      model.feedback.sound = soundWas
    }
    let window = UIWindow(windowScene: scene)
    window.frame = scene.effectiveGeometry.coordinateSpace.bounds
    var prefix = "tt-ui-"
    if let size = env["TT_UI_SIZE"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
      window.frame = CGRect(x: 0, y: 0, width: size[0], height: size[1])
      prefix = "tt-ui-\(Int(size[0]))x\(Int(size[1]))-"
    }
    window.windowLevel = .normal + 1
    let tmp = FileManager.default.temporaryDirectory
    try? FileManager.default.removeItem(at: tmp.appending(path: "frames.txt"))
    let prefixes = env["TT_UI_ONLY"].map { $0.split(separator: ",").map(String.init) }
    func wanted(_ name: String) -> Bool { prefixes.map { $0.contains { name.hasPrefix($0) } } ?? true }
    var shots = 0
    for step in ToothpasteTour.steps where wanted(step.name) {
      step.setup(model)
      ToothpasteUIArgs.override = ["ToothpasteToy", "-noPersist", "-logFrames", "-quietSensors"] + step.args
      let ax = step.args.contains("-ax")
      let root = ToothpasteScreen(model: model)
        .modifier(ToothpasteAXOverride(on: ax))
        .metroChrome()
      window.rootViewController = UIHostingController(rootView: root)
      window.makeKeyAndVisible()
      try await Task.sleep(for: .milliseconds(500))
      model.setActive(true)  // the test host's scene is never `.active`
      try await Task.sleep(for: .seconds(step.dwell + (shots == 0 ? 6 : 0)))
      print(
        "TT-UI-DIAG \(step.name) running \(model.isRunning) particles \(model.telemetry.particles) "
          + "region \(model.canvasRegion) lens \(model.lens) squeeze \(model.squeeze.rate)")
      let format = UIGraphicsImageRendererFormat()
      format.scale = window.screen.scale
      let windows = scene.windows.filter { !$0.isHidden }.sorted { $0.windowLevel.rawValue < $1.windowLevel.rawValue }
      let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
        for w in windows { _ = w.drawHierarchy(in: w.frame, afterScreenUpdates: true) }
      }
      let url = tmp.appending(path: "\(prefix)\(step.name).png")
      try XCTUnwrap(image.pngData()).write(to: url)
      print("TT-UI-PNG \(url.path)")
      if let frames = try? String(contentsOf: tmp.appending(path: "frames.txt"), encoding: .utf8) {
        print("TT-UI-FRAMES \(step.name)\n\(frames)")
      }
      if let presented = window.rootViewController?.presentedViewController {
        presented.dismiss(animated: false)
        try await Task.sleep(for: .milliseconds(400))
      }
      shots += 1
    }
    window.rootViewController = nil
    window.isHidden = true
    ToothpasteUIArgs.override = nil
    XCTAssertGreaterThan(shots, 0)
  }
}
