// FeelTests.swift — OWNER: PLAY (was FEEL; Documentation/REDESIGN-OWNERSHIP.md).
//
// The Simulator has no haptics (`supportsHaptics == false`), so these tests check everything around them:
//   1. the stress → hum map against labkit-from-orbitals-spectra.md §5.3's table (water silent, honey ≈ 0.47,
//      oobleck punch ≈ 0.76 at sharpness 1.0), through FeelMapper and LabKit's HumGovernor;
//   2. event edges: yield and jam/unjam fire once per real crossing, never on chatter inside the hysteresis band;
//      simulation events map to the right transients and gloop triggers; rate limits hold; the hum is causal;
//   3. the microphone: the just-in-time gate and its release, PHYS's band filter hearing only the Band knob's pitches,
//      Toothpaste Toy's own sound kept out of that band, and LabFeedback's persisted toggles and bed policy as FEEL drives it;
//   4. the gloop voice: silent at rest, finite and bounded (|x| ≤ 1, no subnormals) for any control values, and a
//      3 s scripted session rendered offline to Documentation/screenshots/feel-gloop.wav (copied from the path the
//      test prints) whose levels and spectra are checked numerically;
//   5. the whole frame loop (ToothpasteModel, GPU solver) feeding ToothpasteFeel with real frames (honey stir, oobleck punch).
// Numbers are printed as RHEO-FEEL lines.

import AVFoundation
import Accelerate
import Foundation
import LabKitCore
import LabKitFeedback
import LabKitSensors
import Metal
import XCTest
import simd

@testable import ToothpasteToy

final class FeelTests: XCTestCase {
  // MARK: Helpers

  /// A finger in the fluid at the tank's centre, moving down at `speed`.
  private func fingerIn(
    _ material: MaterialID, stress: Double, solid: Double, speed: Double, yield: Double? = nil
  ) -> FeelSignals {
    var s = FeelSignals()
    s.material = material
    s.timbre = .of(material)
    s.jams = material == "oobleck"
    s.yieldStress = yield
    s.surface = 0.045
    s.sloshReference = 1e-4
    s.finger = .init(position: SIMD2(0.035, 0.02), velocity: SIMD2(0, -speed), radius: 0.008, tool: .probe)
    s.probeStress = stress
    s.probeSolid = solid
    s.sources[.touchDown] = 1
    return s
  }

  private func quiet(_ material: MaterialID) -> FeelSignals {
    var s = FeelSignals()
    s.material = material
    s.timbre = .of(material)
    s.jams = material == "oobleck"
    s.surface = 0.045
    s.sloshReference = 1e-4
    return s
  }

  private func count(_ out: FeelOutput, _ kind: GloopTrigger.Kind) -> Int { out.triggers.filter { $0.kind == kind }.count }

  // MARK: 1. The stress → hum map

  func testHumMapMatchesTheSpecTable() {
    // The formula itself (§5.3 table, finger at 0.1 m/s, r 8 mm).
    XCTAssertLessThan(StressFeel.intensity(stress: 0.0125), HumGovernor.stopLevel, "water is below the stop level")
    XCTAssertEqual(StressFeel.intensity(stress: 125), 0.47, accuracy: 0.01, "honey")
    XCTAssertEqual(StressFeel.sharpness(solidFraction: 0, fingerSpeed: 0.1), 0.18, accuracy: 1e-9, "honey is dull")
    XCTAssertEqual(StressFeel.intensity(stress: 11_400), 0.76, accuracy: 0.01, "oobleck punch")
    XCTAssertEqual(StressFeel.sharpness(solidFraction: 1, fingerSpeed: 1), 1, accuracy: 1e-9, "oobleck punch is crisp")

    // Through FeelMapper, after the 30 ms smoothing settles, then LabKit's HumGovernor at full Strength.
    let cases: [(MaterialID, Double, Double, Double, Double, Double)] = [
      ("waterLike", 0.0125, 0, 0.1, 0.0077, 0.18), ("honey", 125, 0, 0.1, 0.4646, 0.18),
      ("oobleck", 11_400, 1, 1, 0.7585, 1.0),
    ]
    for (material, stress, solid, speed, intensity, sharpness) in cases {
      var mapper = FeelMapper()
      var governor = HumGovernor()
      var out = FeelOutput()
      var level = 0.0
      for i in 0..<120 {
        out = mapper.step(fingerIn(material, stress: stress, solid: solid, speed: speed))
        let now = Double(i) / 120
        if out.cause { governor.noteCause(at: now) }
        level = governor.step(wish: out.hum.intensity, strength: 1, allowed: true, now: now, dt: 1.0 / 120)
      }
      XCTAssertTrue(out.cause, material)
      XCTAssertEqual(out.hum.intensity, intensity, accuracy: 0.002, material)
      XCTAssertEqual(out.hum.sharpness, sharpness, accuracy: 0.002, material)
      if material == "waterLike" { XCTAssertEqual(level, 0, "water: no hum (honest)") }
      print(String(format: "RHEO-FEEL hum %@ σ %.4g Pa → I %.3f S %.2f, played %.3f", material, stress,
        out.hum.intensity, out.hum.sharpness, level))
    }
  }

  // MARK: 2. Events

  func testYieldFiresOncePerCrossingWithHysteresis() {
    var mapper = FeelMapper()
    var yields = 0
    func run(_ stress: Double, _ frames: Int) {
      for _ in 0..<frames {
        let out = mapper.step(fingerIn("toothpaste", stress: stress, solid: 0.8, speed: 0.05, yield: 150))
        yields += out.haptics.filter { $0 == .event(.yield) }.count
      }
    }
    run(50, 30)
    XCTAssertEqual(yields, 0, "below τ_y")
    run(200, 30)
    XCTAssertEqual(yields, 1, "one detent on the way up")
    for i in 0..<120 { run(i % 2 == 0 ? 160 : 125, 1) }  // σ̃ ≈ 142: inside the band (0.8 τ_y = 120 … τ_y)
    XCTAssertEqual(yields, 1, "no chatter")
    run(60, 30)
    run(200, 30)
    XCTAssertEqual(yields, 2, "re-armed below 0.8 τ_y")
  }

  func testJamAndUnjamFireOnceAndMakeCracks() {
    var mapper = FeelMapper()
    var jams = 0, unjams = 0, cracks = 0, crumbles = 0, crackTaps = 0
    func run(_ solid: Double, _ frames: Int, wobble: Double = 0) {
      for i in 0..<frames {
        let f = solid + (i % 2 == 0 ? wobble : -wobble)
        let out = mapper.step(fingerIn("oobleck", stress: 2000, solid: f, speed: 0.3))
        for h in out.haptics {
          if case .event(.jam) = h { jams += 1 }
          if h == .event(.unjam) { unjams += 1 }
          if h == .transient(intensity: 0.6, sharpness: 1, minGap: 0.03) { crackTaps += 1 }
        }
        cracks += count(out, .crack)
        crumbles += count(out, .crumble)
      }
    }
    run(0.1, 30)
    run(0.7, 30)
    run(0.4, 120, wobble: 0.05)  // inside jamOff 0.3 … jamOn 0.5
    run(0.2, 30)
    XCTAssertEqual(jams, 1)
    XCTAssertEqual(unjams, 1, "it gives (.release)")
    XCTAssertEqual(crackTaps, 1, "after a dry crack")
    XCTAssertEqual(cracks, 1, "a knock when it holds")
    XCTAssertEqual(crumbles, 1, "a crumble when it fails")
    // A non-jamming material never reports a jam, however solid the probe reads (toothpaste at rest is unyielded).
    var paste = FeelMapper()
    for _ in 0..<60 {
      let out = paste.step(fingerIn("toothpaste", stress: 20, solid: 1, speed: 0.01, yield: 150))
      XCTAssertFalse(out.haptics.contains { if case .event(.jam) = $0 { true } else { false } })
    }
  }

  func testSimulationEventsMapToHapticsAndSound() {
    func one(_ material: MaterialID, _ event: SimEvent) -> FeelOutput {
      var mapper = FeelMapper()
      var s = quiet(material)
      s.events = [event]
      return mapper.step(s)
    }
    let poke = one("honey", .poke(SIMD2(0.03, 0.02)))
    XCTAssertEqual(poke.haptics, [.tap(.poke)])
    XCTAssertEqual(count(poke, .splash), 1)

    let punch = one("oobleck", .punch(SIMD2(0.03, 0.02)))
    XCTAssertEqual(punch.haptics, [.transient(intensity: 1, sharpness: 0.95, minGap: 0)], "oobleck: a hard knock")
    XCTAssertEqual(punch.triggers, [GloopTrigger(kind: .crack, strength: 0.9)])

    let splash = one("honey", .punch(SIMD2(0.03, 0.02)))
    XCTAssertEqual(splash.haptics, [.tap(.poke)])
    XCTAssertEqual(splash.triggers, [GloopTrigger(kind: .splash, strength: 0.9)])

    let hit = one("waterLike", .propHit(speed: 0.4))
    XCTAssertEqual(hit.haptics, [.transient(intensity: 0.5, sharpness: 0.7, minGap: FeelMapper.propHitGap)])
    XCTAssertEqual(count(hit, .crack), 1)

    let refill = one("ketchup", .refilled("ketchup"))
    XCTAssertEqual(refill.haptics, [.ramp(duration: 0.55)])
    XCTAssertEqual(count(refill, .splash), 1)

    XCTAssertEqual(one("ketchup", .propDropped(.steelBall)).haptics, [.tap(.place)])
    for e: SimEvent in [.materialChanged("honey"), .experimentApplied("punch"), .qualityChanged, .touchDown] {
      XCTAssertTrue(one("honey", e).haptics.isEmpty, "\(e): the UI answers it, or nothing should")
    }

    // A punch, then the jam onset it causes: one knock, not two.
    var mapper = FeelMapper()
    var s = fingerIn("oobleck", stress: 11_400, solid: 1, speed: 1)
    s.events = [.punch(SIMD2(0.03, 0.02))]
    let first = mapper.step(s)
    s.events = []
    let next = mapper.step(s)
    let knocks = (first.haptics + next.haptics).filter {
      if case .event(.jam) = $0 { return true }
      if case .transient(let i, _, _) = $0, i >= 0.9 { return true }
      return false
    }
    XCTAssertEqual(knocks.count, 1)
    XCTAssertEqual(first.triggers.filter { $0.kind == .crack }.count + count(next, .crack), 1)

    // A prop falling into the fluid splashes once.
    var props = FeelMapper()
    var p = quiet("waterLike")
    var hits = 0
    for y in stride(from: 0.08, through: 0.01, by: -0.004) {
      p.props = [.init(id: 7, position: SIMD2(0.035, y), velocity: SIMD2(0, -0.6), radius: 0.004)]
      hits += count(props.step(p), .splash)
    }
    XCTAssertEqual(hits, 1)

    // A clap with Listen up: a ripple; a splash only when the clap kicks the fluid (Drives on Kicks).
    var room = quiet("oobleck")
    room.listen = 0.5
    room.sources[.micOnset] = 3
    let felt = FeelMapper().stepped(room)
    XCTAssertEqual(felt.haptics, [.tap(.ripple)])
    XCTAssertTrue(felt.triggers.isEmpty)
    room.drives = .kicks
    XCTAssertEqual(count(FeelMapper().stepped(room), .splash), 1)
    room.listen = 0
    XCTAssertTrue(FeelMapper().stepped(room).haptics.isEmpty, "Listen off: the room is ignored")
  }

  func testPinchOffHeldHumPitchAndMaterialSnap() {
    // A finger pulled out of honey: suction and a strand pinching off; out of water: neither.
    for (material, expected) in [("honey", 1), ("waterLike", 0)] {
      var mapper = FeelMapper()
      var pinches = 0, squelches = 0
      for i in 0..<60 {
        let out = mapper.step(i < 30 ? fingerIn(material, stress: 50, solid: 0, speed: 0.1) : quiet(material))
        pinches += out.haptics.filter { $0 == .tap(.pinch) }.count
        if i >= 30 { squelches += count(out, .squelch) }
      }
      XCTAssertEqual(pinches, expected, material)
      XCTAssertEqual(squelches, expected, material)
    }

    // A pour stream ending: its last drop pinches off and lands.
    var pour = FeelMapper()
    var p = quiet("waterLike")
    var pinches = 0, splashes = 0
    for i in 0..<60 {
      p.finger = i < 30 ? .init(position: SIMD2(0.035, 0.08), velocity: .zero, radius: 0.008, tool: .pour) : nil
      let out = pour.step(p)
      pinches += out.haptics.filter { $0 == .tap(.pinch) }.count
      if i >= 30 { splashes += count(out, .splash) }
    }
    XCTAssertEqual(pinches, 1)
    XCTAssertEqual(splashes, 1)

    // The floor hum keeps its pitch while it fades (no falling buzz when the floor stops).
    var floor = FeelMapper()
    var v = quiet("oobleck")
    v.vibration = SIMD2(10 * Gravity.g0, 120)
    XCTAssertEqual(floor.step(v).gloop.humHz, 120)
    v.vibration = .zero
    let still = floor.step(v)
    XCTAssertEqual(still.gloop.hum, 0)
    XCTAssertEqual(still.gloop.humHz, 120, "a fading hum keeps its pitch")

    // A new material starts at its own pitch; within one material a viscosity change glides (τ 0.3 s).
    var voice = FeelMapper()
    var w = quiet("waterLike")
    w.meanViscosity = 1e-3
    for _ in 0..<60 { _ = voice.step(w) }
    var h = quiet("honey")
    h.meanViscosity = 15.4
    XCTAssertEqual(voice.step(h).gloop.pitch, FeelMapper.pitch(viscosity: 15.4), accuracy: 1e-6)
    h.meanViscosity = 1540
    XCTAssertGreaterThan(voice.step(h).gloop.pitch, 1.2 * FeelMapper.pitch(viscosity: 1540), "a thickening fluid glides down")
  }

  func testSkimmingTheSurfaceDoesNotChatter() {
    // A finger dragged along honey's surface with ±0.5 mm of jitter (its disc's bottom on the surface line): one
    // plunge, then no train of suction squelches and pinch-offs; lifted 3 mm clear, one pinch-off.
    var mapper = FeelMapper()
    var rng = XorShift32(seed: 3)
    var squelches = 0, pinches = 0
    func skim(_ lift: Double, _ frames: Int) {
      for i in 0..<frames {
        var s = quiet("honey")
        let y = s.surface + 0.008 + lift + 0.0005 * rng.bipolar()
        s.finger = .init(position: SIMD2(0.01 + 0.0002 * Double(i), y), velocity: SIMD2(0.024, 0), radius: 0.008, tool: .probe)
        s.sources[.touchDown] = 1
        let out = mapper.step(s)
        squelches += count(out, .squelch)
        pinches += out.haptics.filter { $0 == .tap(.pinch) }.count
      }
    }
    skim(0, 240)
    print("RHEO-FEEL skim 2 s at the surface: \(squelches) squelches, \(pinches) pinches")
    XCTAssertLessThanOrEqual(squelches, 1, "one plunge at most")
    XCTAssertEqual(pinches, 0, "no pinch-off while the finger stays on the surface")
    skim(0.003, 30)
    XCTAssertEqual(pinches, 1, "lifted clear: the strand pinches off once")

    // The surface lies across gravity: tilted 10° to the right, the fluid is about 6 mm higher at the right wall.
    var tilted = quiet("honey")
    tilted.surfaceCentreX = 0.0356
    tilted.surfaceSlope = tan(10 * Double.pi / 180)
    XCTAssertEqual(tilted.surfaceHeight(at: 0.0712) - tilted.surface, 0.0063, accuracy: 0.0001)
    // A finger 3 mm above the level line at the right wall is already in the tilted fluid; at the left wall it is not.
    var right = FeelMapper(), left = FeelMapper()
    tilted.finger = .init(position: SIMD2(0.068, tilted.surface + 0.011), velocity: .zero, radius: 0.008, tool: .probe)
    XCTAssertEqual(count(right.step(tilted), .squelch), 1, "right wall: plunged")
    tilted.finger?.position.x = 0.004
    XCTAssertEqual(count(left.step(tilted), .squelch), 0, "left wall: above the fluid")
  }

  @MainActor func testSurfaceEstimateFollowsGravityAndVolume() {
    // From a frame: the fill line before any stats; tilted gravity (pulling 10° to the right) tilts the surface up
    // to the right; the solver's mass sets the level (a pour raises it).
    let catalog = ToothpasteCatalogData()
    let tank = SIMD2(0.0712, 0.1009)
    var f = ToothpasteFrame.idle(tank: tank, material: "honey")
    let angle = 10 * Double.pi / 180
    f.input.gravity = SIMD2(Gravity.g0 * sin(angle), -Gravity.g0 * cos(angle))
    let info = catalog.material("honey")
    var s = FeelSignals.make(frame: f, dt: 1.0 / 120, catalog: catalog, gap: 0.01, micLive: false)
    XCTAssertEqual(s.surface, info.fillFraction * tank.y, accuracy: 1e-9, "no stats yet: the fill line")
    XCTAssertEqual(s.surfaceSlope, tan(angle), accuracy: 1e-9)
    XCTAssertGreaterThan(s.surfaceHeight(at: tank.x), s.surfaceHeight(at: 0), "higher on the side gravity pulls to")
    f.stats.particleMass = info.material.density * 0.01 * tank.x * 0.06  // 60 mm of fluid across the tank
    f.stats.volumeRatio = 1
    s = FeelSignals.make(frame: f, dt: 1.0 / 120, catalog: catalog, gap: 0.01, micLive: false)
    XCTAssertEqual(s.surface, 0.06, accuracy: 1e-9)
  }

  func testRateLimits() {
    // Yield crossings at 10 Hz for 2 s: every detent plays, squelches stay at or below 8 per second.
    var mapper = FeelMapper()
    var times: [Double] = []
    var detents = 0
    for i in 0..<240 {
      let high = (i / 6) % 2 == 1
      let out = mapper.step(fingerIn("toothpaste", stress: high ? 300 : 30, solid: 0.5, speed: 0.05, yield: 150))
      detents += out.haptics.filter { $0 == .event(.yield) }.count
      for _ in 0..<count(out, .squelch) { times.append(mapper.clock) }
    }
    XCTAssertGreaterThanOrEqual(detents, 18)
    for t in times { XCTAssertLessThanOrEqual(times.filter { $0 >= t && $0 < t + 1 }.count, 8) }
    for (a, b) in zip(times, times.dropFirst()) { XCTAssertGreaterThanOrEqual(b - a, FeelMapper.squelchGap - 1e-9) }

    // Wild jammed-fraction noise: grain haptics stay near 40 per second, the voice's click rate bounded.
    var noisy = FeelMapper()
    var rng = XorShift32(seed: 7)
    var grains = 0
    var maxRate = 0.0
    for _ in 0..<240 {
      var s = fingerIn("oobleck", stress: 500, solid: Double(rng.unit()), speed: 0.3)
      s.tankJammed = Double(rng.unit())
      let out = noisy.step(s)
      grains += out.haptics.filter { if case .event(.grain) = $0 { true } else { false } }.count
      maxRate = max(maxRate, out.gloop.grains)
    }
    XCTAssertLessThanOrEqual(grains, 100, "≤ 40 s⁻¹ Poisson over 2 s (one per frame at most)")
    XCTAssertLessThanOrEqual(maxRate, 120)
    print("RHEO-FEEL rate squelch \(times.count) in 2 s for \(detents) detents; grains \(grains) in 2 s; click rate ≤ \(Int(maxRate)) s⁻¹")
  }

  func testHumIsCausalAndPausedIsQuiet() {
    var mapper = FeelMapper()
    var s = quiet("oobleck")
    var out = mapper.step(s)
    XCTAssertFalse(out.cause, "nothing moves, nothing to feel")
    XCTAssertEqual(out.hum.intensity, 0)
    XCTAssertTrue(out.triggers.isEmpty)
    XCTAssertEqual(out.gloop.drone, 0)
    XCTAssertEqual(out.gloop.bubbles, 0)

    s.vibration = SIMD2(10 * Gravity.g0, 120)
    out = mapper.step(s)
    XCTAssertTrue(out.cause, "a vibrating floor is a visible cause")
    XCTAssertEqual(out.hum.intensity, 0.24, accuracy: 1e-6)
    XCTAssertEqual(out.hum.sharpness, 0.3 + 0.5 * log10(6), accuracy: 1e-6)
    XCTAssertEqual(out.gloop.humHz, 120)
    XCTAssertGreaterThan(out.gloop.hum, 0.8)

    // With the microphone live and Band at 80 Hz, the 120 Hz hum's fundamental would feed the shake drive: only that
    // harmonic is cancelled (the keep-out band is 31.7–201.6 Hz; 240, 360, 480 and 600 Hz still play).
    s.micLive = true
    s.band = 80
    var listening = mapper.step(s)
    XCTAssertGreaterThan(listening.gloop.hum, 0.8, "the hum still plays")
    XCTAssertEqual(listening.gloop.humMute, 0b1, "without its fundamental")
    s.band = 2000
    listening = mapper.step(s)
    XCTAssertGreaterThan(listening.gloop.hum, 0.8)
    XCTAssertEqual(listening.gloop.humMute, 0, "nothing of a 120 Hz hum lies near 2 kHz")

    var shaken = quiet("waterLike")
    shaken.sources[.shake] = 0.3
    XCTAssertTrue(FeelMapper().stepped(shaken).cause, "a shake of the phone")

    // The causal idle: a cause, then 9 s without one: the governor ends the hum.
    var governor = HumGovernor()
    var calm = FeelMapper()
    var slosh = quiet("waterLike")
    var level = 1.0
    for i in 0..<(120 * 10) {
      let now = Double(i) / 120
      slosh.kineticEnergy = 1e-4  // still sloshing: a wish, but no live cause after the first second
      slosh.sources[.shake] = now < 1 ? 0.3 : 0
      let o = calm.step(slosh)
      if o.cause { governor.noteCause(at: now) }
      level = governor.step(wish: o.hum.intensity, strength: 1, allowed: true, now: now, dt: 1.0 / 120)
    }
    XCTAssertEqual(level, 0, "no hum without a cause")

    // Frozen: no physical feel, no gloop events, the bed gated off; a refill still answers with its ramp.
    var frozen = FeelMapper()
    var f = fingerIn("oobleck", stress: 5000, solid: 1, speed: 1)
    f.running = false
    f.events = [.punch(SIMD2(0.03, 0.02)), .refilled("oobleck")]
    out = frozen.step(f)
    XCTAssertFalse(out.cause)
    XCTAssertEqual(out.hum, .silent)
    XCTAssertTrue(out.triggers.isEmpty)
    XCTAssertEqual(out.bedGate, 0)
    XCTAssertEqual(out.haptics, [.ramp(duration: 0.55)])
  }

  // MARK: 3. Microphone

  func testMicGateIsJustInTimeAndReleases() {
    var gate = MicGate()
    XCTAssertEqual(gate.step(listen: 0, state: .off, now: 0), .none, "never at launch")
    XCTAssertEqual(gate.step(listen: 0.3, state: .off, now: 1), .start, "the first raise of Listen asks")
    XCTAssertEqual(gate.step(listen: 0.3, state: .starting, now: 1.1), .none)
    XCTAssertEqual(gate.step(listen: 0.3, state: .off, now: 1.2), .none, "asked once (prompt pending or suspended)")
    XCTAssertEqual(gate.step(listen: 0.3, state: .on, now: 2), .none)
    XCTAssertEqual(gate.step(listen: 0, state: .on, now: 3), .none)
    XCTAssertEqual(gate.step(listen: 0, state: .on, now: 4.9), .none)
    XCTAssertEqual(gate.step(listen: 0, state: .on, now: 5.0), .stop, "released 2 s after Listen returns to 0")
    XCTAssertEqual(gate.step(listen: 0.2, state: .off, now: 6), .start, "asks again on the next raise")

    var denied = MicGate()
    XCTAssertEqual(denied.step(listen: 0.5, state: .denied, now: 0), .none, "a denial is not asked again")
    XCTAssertEqual(denied.step(listen: 0.5, state: .denied, now: 10), .none)
    // Allowed in Settings later (ToothpasteFeel reports a lifted denial as .off): the raised Listen starts it.
    XCTAssertEqual(denied.step(listen: 0.5, state: .off, now: 11), .start, "after Settings")

    var asked = MicGate()
    XCTAssertEqual(asked.step(listen: 0.5, state: .off, now: 0), .start)
    XCTAssertEqual(asked.step(listen: 0.5, state: .denied, now: 1), .none, "the user said no")
    XCTAssertEqual(asked.step(listen: 0, state: .denied, now: 2), .none)
    XCTAssertEqual(asked.step(listen: 0, state: .off, now: 30), .none, "allowed in Settings, Listen at 0: wait")
    XCTAssertEqual(asked.step(listen: 0.2, state: .off, now: 31), .start, "the next raise asks")

    var failed = MicGate()
    XCTAssertEqual(failed.step(listen: 0.5, state: .off, now: 0), .start)
    XCTAssertEqual(failed.step(listen: 0.5, state: .failed, now: 1), .none)
    XCTAssertEqual(failed.step(listen: 0.5, state: .failed, now: 5.9), .none)
    XCTAssertEqual(failed.step(listen: 0.5, state: .failed, now: 6.1), .start, "retried after 5 s")

    // A call took the session and iOS never recommended resuming: the microphone is off although the gate asked for
    // it. Lowering Listen to 0 and raising it again starts it.
    var call = MicGate()
    XCTAssertEqual(call.step(listen: 0.5, state: .off, now: 0), .start)
    XCTAssertEqual(call.step(listen: 0.5, state: .on, now: 1), .none)
    XCTAssertEqual(call.step(listen: 0.5, state: .off, now: 2), .none, "suspended: wait for the resumption")
    XCTAssertEqual(call.step(listen: 0, state: .off, now: 30), .none)
    XCTAssertEqual(call.step(listen: 0.5, state: .off, now: 31), .start, "the next raise starts it")
    var stillDenied = MicGate()
    XCTAssertEqual(stillDenied.step(listen: 0.5, state: .off, now: 0), .start)
    XCTAssertEqual(stillDenied.step(listen: 0, state: .denied, now: 1), .none)
    XCTAssertEqual(stillDenied.step(listen: 0.5, state: .denied, now: 2), .none, "a denial is still never re-asked")

    var kept = MicGate(keepAlive: true)
    XCTAssertEqual(kept.step(listen: 0, state: .on, now: 0), .none)
    XCTAssertEqual(kept.step(listen: 0, state: .on, now: 10), .none, "-startMic keeps it on")
    var toggle = MicGate()
    XCTAssertEqual(toggle.request(state: .off), .start)
    XCTAssertEqual(toggle.step(listen: 0, state: .on, now: 0), .none)
    XCTAssertEqual(toggle.step(listen: 0, state: .on, now: 10), .none, "an explicit request is not released")

    // The microphone's copy (the PermissionGate and banners) is the UI's: ToothpasteCopy.micDeniedText, linted with the rest.
  }

  /// When the UI opens the PermissionGate: each raise of Listen while the microphone is refused, and a refusal at
  /// iOS's prompt while Listen is up; never at launch, never with Listen down, not every frame.
  func testPermissionGateOpensOnRefusalsWithListenUp() {
    var w = MicDenialWatch()
    w.step(listen: 0, state: .off)
    w.step(listen: 0, state: .denied)
    XCTAssertEqual(w.count, 0, "refused but Listen down: nothing to show")
    w.step(listen: 0.4, state: .denied)
    XCTAssertEqual(w.count, 1, "a raise while refused")
    for _ in 0..<120 { w.step(listen: 0.5, state: .denied) }
    XCTAssertEqual(w.count, 1, "once per raise, not per frame")
    w.step(listen: 0, state: .denied)
    w.step(listen: 0.3, state: .denied)
    XCTAssertEqual(w.count, 2, "the next raise shows it again")

    var prompt = MicDenialWatch()
    prompt.step(listen: 0.3, state: .off)
    prompt.step(listen: 0.3, state: .starting)
    XCTAssertEqual(prompt.count, 0, "the first raise asks iOS (no card while the prompt is up)")
    prompt.step(listen: 0.3, state: .denied)
    XCTAssertEqual(prompt.count, 1, "refused at the prompt with Listen up")
    prompt.step(listen: 0.3, state: .denied)
    XCTAssertEqual(prompt.count, 1)

    var allowed = MicDenialWatch()
    allowed.step(listen: 0.3, state: .starting)
    allowed.step(listen: 0.3, state: .on)
    XCTAssertEqual(allowed.count, 0, "allowed: no card")
  }

  func testOwnSoundStaysOutOfTheDrivesBand() {
    // The drives listen ±⅓ octave around Band (PHYS's MicBand); FEEL keeps out of that band widened by an octave.
    let r = ToothpasteMicBand.range(80)
    XCTAssertEqual(r.lowerBound, 80 / 1.26, accuracy: 1e-9)
    XCTAssertEqual(r.upperBound, 80 * 1.26, accuracy: 1e-9)
    XCTAssertEqual(ToothpasteMicBand.keepOut(80).lowerBound, 80 / 2.52, accuracy: 1e-9)
    var policy = SoundPolicy()
    policy.micLive = true
    policy.micBand = ToothpasteMicBand.range(300)
    XCTAssertFalse(policy.allowsPartial(frequency: 300), "a cue at Band is dropped while listening")
    XCTAssertTrue(policy.allowsPartial(frequency: 1400), "the detent cue survives a voice-band setting")
    // The floor's hum at its rate and the body tone near Band are kept quiet with the microphone live.
    var mapper = FeelMapper()
    var s = quiet("oobleck")
    s.vibration = SIMD2(5 * Gravity.g0, 100)
    s.kineticEnergy = 1e-4
    s.restingViscosity = 15
    s.micLive = true
    s.band = 200
    let out = mapper.step(s)
    XCTAssertEqual(out.gloop.hum, 0, "every harmonic the hum's filter passes (100–500 Hz) is in the band: silent")
    XCTAssertTrue(ToothpasteMicBand.keepOut(200).contains(out.gloop.pitch), "\(out.gloop.pitch) Hz")
    XCTAssertEqual(out.gloop.drone, 0.3, accuracy: 1e-9, "ducked")

    // The mask itself.
    XCTAssertEqual(FeelMapper.humMute(humHz: 120, keepOut: ToothpasteMicBand.keepOut(80)), 0b1)
    XCTAssertEqual(FeelMapper.humMute(humHz: 50, keepOut: ToothpasteMicBand.keepOut(80)), 0b1111, "50, 100, 150, 200 Hz")
    XCTAssertEqual(FeelMapper.humMute(humHz: 100, keepOut: ToothpasteMicBand.keepOut(300)), 0b11110, "200–500 Hz; 100 Hz plays")
    XCTAssertNil(FeelMapper.humMute(humHz: 120, keepOut: ToothpasteMicBand.keepOut(300)), "120–600 Hz all in 119–756 Hz")
    XCTAssertNil(FeelMapper.humMute(humHz: 100, keepOut: ToothpasteMicBand.keepOut(200)), "nothing audible left")
    XCTAssertEqual(FeelMapper.humMute(humHz: 120, keepOut: ToothpasteMicBand.keepOut(2000)), 0)
  }

  /// The voice cancels exactly the harmonics it is told to: a 120 Hz hum with its fundamental muted loses the
  /// 120 Hz line (Goertzel) and keeps 240 Hz.
  func testHumCancelsOnlyTheMutedHarmonics() {
    func line(_ x: [Float], _ f: Double) -> Double {
      // Goertzel power at f over the steady second half.
      let n = x.count / 2
      let w = 2 * Double.pi * f / 48_000
      var s1 = 0.0, s2 = 0.0
      for v in x[n...] {
        let s0 = Double(v) + 2 * cos(w) * s1 - s2
        s2 = s1
        s1 = s0
      }
      return (s1 * s1 + s2 * s2 - 2 * cos(w) * s1 * s2).squareRoot() / Double(n)
    }
    func hum(mute: Int) -> [Float] {
      let kernel = GloopKernel()
      kernel.prepare(sampleRate: 48_000)
      let c = SynthControls()
      c.set(GloopKernel.Slot.hum, 0.8)
      c.set(GloopKernel.Slot.humHz, GloopKernel.Slot.packHum(hz: 120, mute: mute))
      return render(kernel, c, seconds: 1).left
    }
    let full = hum(mute: 0), muted = hum(mute: 0b1), second = hum(mute: 0b10)
    let f1 = line(full, 120), f2 = line(full, 240)
    let m1 = line(muted, 120), m2 = line(muted, 240)
    let s1 = line(second, 120), s2 = line(second, 240)
    print(String(format: "RHEO-FEEL hum lines: full 120 %.2e 240 %.2e; fundamental muted 120 %.2e 240 %.2e; 2nd muted 120 %.2e 240 %.2e",
      f1, f2, m1, m2, s1, s2))
    XCTAssertGreaterThan(f1, 1e-3, "the hum's fundamental is there to begin with")
    XCTAssertLessThan(m1, 0.03 * f1, "muted: the fundamental drops by more than 30 dB")
    XCTAssertEqual(m2, f2, accuracy: 0.1 * f2, "the second harmonic is untouched")
    XCTAssertEqual(s1, f1, accuracy: 0.1 * f1)
    XCTAssertLessThan(s2, 0.03 * f2, "and the second harmonic alone can be cancelled too")
    checkSamples(muted, "muted hum")
  }

  /// With the microphone live the continuous layers duck to × 0.3 and Low Power Mode silences them, but the one-shot
  /// gloop events keep their level (they answer the user, like cues): the host gain stays 1 and only the bed scale
  /// moves. A splash rendered with the bed ducked is as loud as one rendered without.
  @MainActor func testEventsKeepTheirLevelWhenTheBedIsDucked() {
    func settle(_ mix: inout ToothpasteBedMix, running: Bool = true, sound: Bool = true, paused: Bool = false,
                lowPower: Bool = false, mic: Bool = false) {
      for _ in 0..<240 {
        mix.step(running: running, sound: sound, active: true, paused: paused, lowPower: lowPower, micLive: mic,
                 dt: 1.0 / 120)
      }
    }
    var mix = ToothpasteBedMix()
    settle(&mix)
    XCTAssertEqual(mix.hostGain, 1)
    XCTAssertEqual(mix.bedScale, 1, accuracy: 0.001)
    settle(&mix, mic: true)
    XCTAssertEqual(mix.hostGain, 1, "listening: events at full level")
    XCTAssertEqual(mix.bedScale, SoundPolicy.micDuck, accuracy: 0.001, "the bed ducked to × 0.3")
    settle(&mix, lowPower: true)
    XCTAssertEqual(mix.hostGain, 1, "Low Power Mode: events still play")
    XCTAssertEqual(mix.bedScale, 0, "the bed is silent")
    settle(&mix, running: false)
    XCTAssertEqual(mix.bedScale, 0, accuracy: 0.001, "frozen: the bed is silent")
    settle(&mix, sound: false)
    XCTAssertEqual(mix.hostGain, 0, "Sound off: nothing")

    // The driver scales the continuous layers by the bed scale and passes the events on untouched.
    var mapper = FeelMapper()
    var s = fingerIn("waterLike", stress: 1, solid: 0, speed: 0.3)
    s.kineticEnergy = 1e-4
    s.events = [.poke(SIMD2(0.03, 0.04))]
    let out = mapper.step(s)
    XCTAssertGreaterThan(out.gloop.drone, 0)
    XCTAssertGreaterThan(out.gloop.bubbles, 0)
    XCTAssertEqual(count(out, .splash), 1, "the poke splashes")
    var driver = GloopDriver()
    let c = SynthControls()
    driver.write(out, to: c, bedScale: 0)
    XCTAssertEqual(c[GloopKernel.Slot.drone], 0, "Low Power Mode: the bed is silent")
    XCTAssertEqual(c[GloopKernel.Slot.drag], 0)
    XCTAssertEqual(c[GloopKernel.Slot.bubbles], 0)
    XCTAssertEqual(c[GloopKernel.Slot.splash], 1, "the splash still goes to the voice")
    XCTAssertEqual(c[GloopKernel.Slot.splashStrength], out.triggers.first?.strength ?? -1, accuracy: 1e-12)
    driver.write(out, to: c, bedScale: SoundPolicy.micDuck)
    XCTAssertEqual(c[GloopKernel.Slot.drone], out.gloop.drone * SoundPolicy.micDuck, accuracy: 1e-12, "ducked × 0.3")

    // In the voice: a splash alone, with and without the continuous layers.
    func splashPeak(bed: Double) -> Float {
      let kernel = GloopKernel()
      kernel.prepare(sampleRate: 48_000)
      let c = SynthControls()
      c.set(GloopKernel.Slot.thick, GloopKernel.Slot.packTimbre(thick: 0.2, grit: 0))
      c.set(GloopKernel.Slot.drone, 0.5 * bed)
      _ = render(kernel, c, seconds: 0.2)
      c.set(GloopKernel.Slot.splashStrength, 0.8)
      c.set(GloopKernel.Slot.splash, 1)
      let x = render(kernel, c, seconds: 0.05).left
      return x.map(abs).max() ?? 0
    }
    let loud = splashPeak(bed: 1), ducked = splashPeak(bed: SoundPolicy.micDuck)
    print(String(format: "RHEO-FEEL splash peak with the bed at 1: %.3f, at × 0.3: %.3f", loud, ducked))
    XCTAssertGreaterThan(ducked, 0.6 * loud, "the event is not ducked with the bed")
  }

  /// With the microphone live, background bubbles and grain clicks are drawn by the mapper (Poisson, at the bed's
  /// rates), not by the voice: each frame that spawns one is a self-sound, which opens the onset window, so Toothpaste Toy's
  /// own plinks cannot kick the fluid (Drives on Kicks) into plinking again.
  func testMicLiveTextureIsDrawnHereAndOpensTheOnsetWindow() {
    var mapper = FeelMapper()
    var s = quiet("waterLike")
    s.kineticEnergy = 1e-4  // full slosh: about 45 bubbles a second in water
    s.micLive = true
    s.band = 80
    var spawned = 0, frames = 0, windows = 0
    for _ in 0..<240 {
      let out = mapper.step(s)
      XCTAssertEqual(out.gloop.bubbles, 0, "the voice draws none of its own")
      XCTAssertEqual(out.gloop.grains, 0)
      spawned += out.gloop.bubbleSpawns
      if out.gloop.bubbleSpawns > 0 {
        frames += 1
        if out.selfSound { windows += 1 }
      }
    }
    print("RHEO-FEEL mic-live texture: \(spawned) bubbles in 2 s over \(frames) frames, \(windows) onset windows")
    XCTAssertGreaterThan(spawned, 20)
    XCTAssertLessThan(spawned, 200)
    XCTAssertEqual(windows, frames, "every spawn opens the window")
    s.micLive = false
    let off = mapper.step(s)
    XCTAssertGreaterThan(off.gloop.bubbles, 1, "mic off: the voice draws them itself")
    XCTAssertEqual(off.gloop.bubbleSpawns, 0)

    // The voice plays what the counters ask for, and resynchronises on a reset or a jump.
    let kernel = GloopKernel()
    kernel.prepare(sampleRate: 48_000)
    let c = SynthControls()
    c.set(GloopKernel.Slot.texture, GloopKernel.Slot.packTexture(bubbles: 0, clicks: 0))
    _ = render(kernel, c, seconds: 0.01)
    c.set(GloopKernel.Slot.texture, GloopKernel.Slot.packTexture(bubbles: 3, clicks: 2))
    let x = render(kernel, c, seconds: 0.05).left
    XCTAssertGreaterThan(x.map(abs).max() ?? 0, 0.001, "three bubbles and two clicks sound")
    c.set(GloopKernel.Slot.texture, GloopKernel.Slot.packTexture(bubbles: 3000, clicks: 0))
    let tail = render(kernel, c, seconds: 1.5).left
    XCTAssertEqual(tail.suffix(4800).map(abs).max() ?? 1, 0, "a jump only resynchronises: silence")
  }

  @MainActor func testDrivesHearOnlyTheBand() {
    // PHYS's MicBand (Engine/Stimuli.swift) is the filter between the microphone and the drives: the Band knob's
    // pitches ±⅓ octave, from LabKit's 48-band spectrum. A tone in the band drives; the same tone elsewhere does not.
    func level(tone f: Double, band: Double, amplitude: Double = 0.3) -> Double {
      let samples = (0..<Spectrum.size).map { Float(amplitude * sin(2 * Double.pi * f * Double($0) / 48_000)) }
      let snapshot = MicSnapshot(samples: samples, level: Float(amplitude / Double(2).squareRoot()), bass: 0, onset: 0)
      return MicBand().update(snapshot, gain: 1, centre: band, dt: 1.0 / 60)
    }
    let hum300 = level(tone: 300, band: 300)
    let hum300at2k = level(tone: 300, band: 2000)
    let hum300at80 = level(tone: 300, band: 80)
    let whistle = level(tone: 2000, band: 2000)
    let whistleAt80 = level(tone: 2000, band: 80)
    XCTAssertGreaterThan(hum300, 0.3, "a tone at Band drives")
    XCTAssertLessThan(hum300at2k, 0.1 * hum300, "2.7 octaves away it does not")
    XCTAssertLessThan(hum300at80, 0.1 * hum300)
    XCTAssertGreaterThan(whistle, 0.1)
    XCTAssertLessThan(whistleAt80, 0.1 * whistle)
    let quieter = level(tone: 300, band: 300, amplitude: 0.1)
    XCTAssertGreaterThan(quieter, 0.1, "−10 dB still registers")
    XCTAssertLessThan(quieter, hum300, "and drives less")
    XCTAssertEqual(MicBand().update(nil, gain: 1, centre: 300, dt: 1.0 / 60), 0, "mic off: no drive")
    print(String(format: "RHEO-FEEL band 300 Hz tone: Band 300 %.3f, Band 2000 %.3f, Band 80 %.3f; 2 kHz tone: Band 2000 %.3f, Band 80 %.3f",
      hum300, hum300at2k, hum300at80, whistle, whistleAt80))
  }

  @MainActor func testFeedbackTogglesPersistAndTheBedFollowsThePolicy() throws {
    // The hub builds `LabFeedback(appName: "ToothpasteToy", kernel: GloopKernel())`: Sound, Haptics, Feel the fluid and
    // Strength persist under "ToothpasteToy.*" (labkit-from-orbitals-spectra.md §5.2 rule 7, §6.3 rule 2).
    let suite = "ToothpasteFeelTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = LabFeedback(appName: "ToothpasteToy", kernel: nil, defaults: defaults)
    XCTAssertTrue(first.sound, "Sound is on by default")
    XCTAssertTrue(first.haptics.enabled)
    XCTAssertTrue(first.haptics.humEnabled)
    XCTAssertEqual(first.haptics.strength, 0.85, accuracy: 1e-6)
    first.sound = false
    first.haptics.enabled = false
    first.haptics.humEnabled = false
    first.haptics.strength = 0.4
    let second = LabFeedback(appName: "ToothpasteToy", kernel: nil, defaults: defaults)
    XCTAssertFalse(second.sound)
    XCTAssertFalse(second.haptics.enabled)
    XCTAssertFalse(second.haptics.humEnabled)
    XCTAssertEqual(second.haptics.strength, 0.4, accuracy: 1e-6)
    XCTAssertEqual(defaults.object(forKey: "ToothpasteToy.sound") as? Bool, false)
    XCTAssertEqual(defaults.object(forKey: "ToothpasteToy.feel") as? Bool, false)

    // The bed as ToothpasteFeel drives it: FeelMapper's gate is 1 while the simulation runs; LabFeedback ducks it to × 0.3
    // with the microphone live, and silences it when paused or with Sound off.
    let bed = LabFeedback(appName: nil, kernel: nil)
    var mapper = FeelMapper()
    let gate = mapper.step(quiet("honey")).bedGate
    XCTAssertEqual(gate, 1)
    func settle() -> Double {
      for _ in 0..<240 { bed.updateBed(activity: gate, dt: 1.0 / 120) }
      return bed.bedLevel
    }
    XCTAssertEqual(settle(), 1, accuracy: 0.001)
    bed.micLive = true
    XCTAssertEqual(settle(), SoundPolicy.micDuck, accuracy: 0.001, "listening: ducked")
    bed.paused = true
    XCTAssertEqual(settle(), 0, "frozen: silent")
    bed.paused = false
    bed.micLive = false
    bed.sound = false
    XCTAssertEqual(settle(), 0, "Sound off: silent")
  }

  // MARK: 4. The gloop voice

  /// Renders `seconds` in blocks of `block` frames; `each` runs before every block.
  private func render(
    _ kernel: GloopKernel, _ controls: SynthControls, seconds: Double, block: Int = 512, fs: Double = 48_000,
    each: (Int) -> Void = { _ in }
  ) -> (left: [Float], right: [Float]) {
    let total = Int(seconds * fs)
    var left = [Float](), right = [Float]()
    left.reserveCapacity(total)
    right.reserveCapacity(total)
    let l = UnsafeMutablePointer<Float>.allocate(capacity: 4096)
    let r = UnsafeMutablePointer<Float>.allocate(capacity: 4096)
    defer {
      l.deallocate()
      r.deallocate()
    }
    var done = 0
    var index = 0
    while done < total {
      each(index)
      let n = min(block, total - done, 4096)
      kernel.render(frames: n, left: l, right: r, controls: controls)
      left.append(contentsOf: UnsafeBufferPointer(start: l, count: n))
      right.append(contentsOf: UnsafeBufferPointer(start: r, count: n))
      done += n
      index += 1
    }
    return (left, right)
  }

  private func checkSamples(_ x: [Float], _ label: String, file: StaticString = #filePath, line: UInt = #line) {
    var bad = 0, loud = 0, subnormal = 0
    for v in x {
      if !v.isFinite { bad += 1 } else if abs(v) > 1 { loud += 1 } else if v.isSubnormal { subnormal += 1 }
    }
    XCTAssertEqual(bad, 0, "\(label): non-finite samples", file: file, line: line)
    XCTAssertEqual(loud, 0, "\(label): samples beyond ±1", file: file, line: line)
    XCTAssertEqual(subnormal, 0, "\(label): subnormal samples", file: file, line: line)
  }

  func testVoiceIsSilentAtRest() {
    let kernel = GloopKernel()
    kernel.prepare(sampleRate: 48_000)
    let (l, r) = render(kernel, SynthControls(), seconds: 0.5)
    XCTAssertTrue(l.allSatisfy { $0 == 0 } && r.allSatisfy { $0 == 0 }, "nothing moves: exact silence")
  }

  func testPitchesJumpFromSilenceAndGlideWhileSounding() {
    let kernel = GloopKernel()
    kernel.prepare(sampleRate: 48_000)
    let c = SynthControls()
    let l = UnsafeMutablePointer<Float>.allocate(capacity: 4096)
    let r = UnsafeMutablePointer<Float>.allocate(capacity: 4096)
    defer {
      l.deallocate()
      r.deallocate()
    }
    func run(_ frames: Int) { kernel.render(frames: frames, left: l, right: r, controls: c) }
    c.set(GloopKernel.Slot.pitch, 880)
    c.set(GloopKernel.Slot.humHz, 120)
    run(4096)
    // Silent voices take a new pitch at once: no swoop from water's 880 Hz down to honey's.
    c.set(GloopKernel.Slot.pitch, 296)
    c.set(GloopKernel.Slot.drone, 0.5)
    c.set(GloopKernel.Slot.humHz, 60)
    c.set(GloopKernel.Slot.hum, 0.5)
    run(32)
    XCTAssertEqual(kernel.pitches.body, 296, accuracy: 1e-9)
    XCTAssertEqual(kernel.pitches.hum, 60, accuracy: 1e-9)
    // Sounding voices glide (τ 30 ms): 10 ms after a change they are about a quarter of the way.
    run(4096)
    c.set(GloopKernel.Slot.pitch, 592)
    c.set(GloopKernel.Slot.humHz, 120)
    run(480)
    XCTAssertGreaterThan(kernel.pitches.body, 296 + 0.15 * 296)
    XCTAssertLessThan(kernel.pitches.body, 296 + 0.45 * 296)
    XCTAssertGreaterThan(kernel.pitches.hum, 60 + 0.15 * 60)
    XCTAssertLessThan(kernel.pitches.hum, 60 + 0.45 * 60)
  }

  func testVoiceIsFiniteAndBoundedForAnyControls() {
    let kernel = GloopKernel()
    kernel.prepare(sampleRate: 48_000)
    let controls = SynthControls()
    var rng = XorShift32(seed: 99)
    let garbage: [Double] = [.nan, .infinity, -.infinity, 1e300, -1e300, -5, 0, 1e-320]
    var counters = [0.0, 0.0, 0.0]
    let (l, r) = render(kernel, controls, seconds: 8, block: 333) { block in
      for slot in 0..<SynthControls.capacity {
        let u = Double(rng.unit())
        let v: Double
        if block % 7 == 3 {
          v = garbage[Int(rng.next() % UInt32(garbage.count))]
        } else {
          switch slot {
          case GloopKernel.Slot.pitch: v = 40 + 2000 * u
          case GloopKernel.Slot.humHz: v = GloopKernel.Slot.packHum(hz: 15 + 400 * u, mute: Int(rng.next() % 256))
          case GloopKernel.Slot.thick: v = GloopKernel.Slot.packTimbre(thick: u, grit: Double(rng.unit()))
          case GloopKernel.Slot.texture: v = GloopKernel.Slot.packTexture(bubbles: block, clicks: block / 2)
          case GloopKernel.Slot.grains, GloopKernel.Slot.bubbles: v = 300 * u
          case GloopKernel.Slot.crackStrength: v = 2 * u - 1
          default: v = u
          }
        }
        controls.set(slot, v)
      }
      // Event counters: bursts, resets and huge jumps.
      for (i, slot) in [GloopKernel.Slot.squelch, GloopKernel.Slot.crack, GloopKernel.Slot.splash].enumerated() {
        switch block % 11 {
        case 5: counters[i] = 0
        case 9: counters[i] += 1000
        default: counters[i] += Double(rng.next() % 3)
        }
        controls.set(slot, block % 7 == 3 ? .nan : counters[i])
      }
    }
    checkSamples(l, "left")
    checkSamples(r, "right")
    let peak = l.map { abs($0) }.max() ?? 0
    XCTAssertGreaterThan(peak, 0.05, "the fuzz is actually audible")

    // Then everything off: it decays to silence and frees every voice.
    for slot in 0..<SynthControls.capacity where ![3, 7, 11].contains(slot) { controls.set(slot, 0) }
    let (tail, _) = render(kernel, controls, seconds: 3)
    checkSamples(tail, "tail")
    let last = tail.suffix(24_000)
    let rms = (last.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(last.count)).squareRoot()
    XCTAssertLessThan(rms, 1e-6, "silent within 2.5 s")
    XCTAssertEqual(kernel.activeVoices, 0)
    print(String(format: "RHEO-FEEL fuzz 8 s: peak %.3f; tail RMS %.2e", peak, rms))
  }

  // MARK: Offline session → WAV

  private struct Segment {
    let name: String
    let from: Double
    let to: Double
  }

  /// One scripted frame of the 3 s session (120 Hz).
  private func sessionSignals(at t: Double) -> FeelSignals {
    var s = FeelSignals()
    s.dt = 1.0 / 120
    s.surface = 0.045
    s.sloshReference = 1e-4
    func finger(_ x: Double, _ y: Double, _ v: SIMD2<Double>, _ tool: FingerState.Tool = .probe) {
      s.finger = .init(position: SIMD2(x, y), velocity: v, radius: 0.008, tool: tool)
      s.sources[.touchDown] = 1
    }
    func material(_ id: MaterialID, eta: Double) {
      s.material = id
      s.timbre = .of(id)
      s.jams = id == "oobleck"
      s.meanViscosity = eta
      s.restingViscosity = eta
    }
    switch t {
    case ..<0.55:
      // Water: a finger sweeps through at 0.3 m/s, a poke at 0.30 s.
      material("waterLike", eta: 1e-3)
      s.kineticEnergy = 0.36e-4
      if t >= 0.05, t < 0.5 { finger(0.02 + 0.3 * (t - 0.05), 0.03, SIMD2(0.3, 0)) }
      s.probeStress = 0.01
      if abs(t - 0.30) < 0.004 { s.events = [.poke(SIMD2(0.03, 0.03))] }
    case ..<1.2:
      // Honey: a slow drag at 0.08 m/s (σ 125 Pa), lifted at 1.1 s (suction).
      material("honey", eta: 15.4)
      s.kineticEnergy = 0.04e-4
      if t >= 0.6, t < 1.1 { finger(0.02 + 0.08 * (t - 0.6), 0.025, SIMD2(0.08, 0)) }
      s.probeStress = 125
    case ..<1.95:
      // Oobleck: a punch at 1.30 s jams it (σ 11.4 kPa, solid 1); it fails from 1.6 s and flows by 1.7 s.
      material("oobleck", eta: t < 1.3 ? 0.002 : 60)
      s.kineticEnergy = 0.1e-4
      if t >= 1.25, t < 1.85 { finger(0.035, 0.03 - 0.02 * min(1, (t - 1.25) / 0.1), SIMD2(0, t < 1.35 ? -1 : -0.02)) }
      if abs(t - 1.30) < 0.004 { s.events = [.punch(SIMD2(0.035, 0.03))] }
      let solid = t < 1.3 ? 0.1 : t < 1.6 ? 1 : max(0.1, 1 - (t - 1.6) / 0.1)
      s.probeSolid = solid
      s.probeStress = t < 1.3 ? 20 : t < 1.6 ? 11_400 : 200
      s.tankJammed = 0.3 * solid
    case ..<2.35:
      // Pouring water from above the surface.
      material("waterLike", eta: 1e-3)
      s.kineticEnergy = 0.09e-4
      finger(0.035, 0.08, .zero, .pour)
      if abs(t - 1.95) < 0.004 { s.events = [.pourStarted("waterLike")] }
    case ..<2.6:
      // Oobleck on a vibrating floor: 10 g at 120 Hz, then rest from 2.6 s.
      material("oobleck", eta: 5)
      s.vibration = SIMD2(10 * Gravity.g0, 120)
      s.kineticEnergy = 0.25e-4
      s.tankJammed = 0.25 + 0.1 * sin(2 * Double.pi * (t - 2.35) / 0.25)
    default:
      // At rest (the jammed share holds).
      material("oobleck", eta: 5)
      s.tankJammed = 0.25
    }
    return s
  }

  private func spectrum(_ x: ArraySlice<Float>, n: Int = 4096) -> [Double] {
    let log2n = vDSP_Length(log2(Double(n)))
    guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
    defer { vDSP_destroy_fftsetup(setup) }
    var window = [Float](repeating: 0, count: n)
    vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
    var power = [Double](repeating: 0, count: n / 2)
    var real = [Float](repeating: 0, count: n / 2)
    var imag = [Float](repeating: 0, count: n / 2)
    var start = x.startIndex
    while start + n <= x.endIndex {
      var seg = [Float](x[start..<(start + n)])
      for i in 0..<n { seg[i] *= window[i] }
      real.withUnsafeMutableBufferPointer { rp in
        imag.withUnsafeMutableBufferPointer { ip in
          var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
          seg.withUnsafeBytes { raw in
            vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(n / 2))
          }
          vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
        }
      }
      for k in 1..<(n / 2) { power[k] += Double(real[k] * real[k] + imag[k] * imag[k]) }
      start += n / 2
    }
    return power
  }

  private func writeWAV(left: [Float], right: [Float], sampleRate: Int, to url: URL) throws {
    var data = Data()
    func bytes<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    let payload = left.count * 4
    data.append(contentsOf: Array("RIFF".utf8))
    bytes(UInt32(36 + payload))
    data.append(contentsOf: Array("WAVEfmt ".utf8))
    bytes(UInt32(16))
    bytes(UInt16(1))  // PCM
    bytes(UInt16(2))
    bytes(UInt32(sampleRate))
    bytes(UInt32(sampleRate * 4))
    bytes(UInt16(4))
    bytes(UInt16(16))
    data.append(contentsOf: Array("data".utf8))
    bytes(UInt32(payload))
    for i in 0..<left.count {
      bytes(Int16((max(-1, min(1, left[i])) * 32_767).rounded()))
      bytes(Int16((max(-1, min(1, right[i])) * 32_767).rounded()))
    }
    try data.write(to: url)
  }

  func testOfflineSessionSoundsLikeGoo() throws {
    let fs = 48_000.0
    let fps = 120.0
    let kernel = GloopKernel()
    kernel.prepare(sampleRate: fs)
    let controls = SynthControls()
    var mapper = FeelMapper()
    var driver = GloopDriver()
    // 3 s of session (the WAV), then 0.5 s more at rest: every tail must have ended by 3.3 s.
    let frames = Int(3.5 * fps)
    let started = Date()
    let (left, right) = render(kernel, controls, seconds: 3.5, block: Int(fs / fps)) { frame in
      guard frame < frames else { return }
      driver.write(mapper.step(sessionSignals(at: Double(frame) / fps)), to: controls)
    }
    let elapsed = Date().timeIntervalSince(started)
    checkSamples(left, "left")
    checkSamples(right, "right")
    XCTAssertEqual(driver.cracks, 2, "the punch's knock and the failure's crumble; the jam between them is the same knock")

    let url = FileManager.default.temporaryDirectory.appendingPathComponent("feel-gloop.wav")
    try writeWAV(left: Array(left.prefix(Int(3 * fs))), right: Array(right.prefix(Int(3 * fs))), sampleRate: Int(fs), to: url)
    print("RHEO-FEEL-WAV \(url.path)")

    let mono = zip(left, right).map { ($0 + $1) / 2 }
    let segments = [
      Segment(name: "water", from: 0.10, to: 0.55), Segment(name: "honey", from: 0.65, to: 1.20),
      Segment(name: "oobleck", from: 1.25, to: 1.95), Segment(name: "pour", from: 2.00, to: 2.35),
      Segment(name: "shake", from: 2.38, to: 2.60), Segment(name: "rest", from: 3.30, to: 3.50),
    ]
    var metrics: [String: (rms: Double, peak: Double, centroid: Double, above300: Double, dominant: Double)] = [:]
    for seg in segments {
      let x = mono[Int(seg.from * fs)..<Int(seg.to * fs)]
      let rms = (x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(x.count)).squareRoot()
      let peak = Double(x.map { abs($0) }.max() ?? 0)
      let p = spectrum(x)
      let binHz = fs / 4096
      let total = p.reduce(0, +)
      var weighted = 0.0, high = 0.0, best = 0.0, dominant = 0.0
      for (k, v) in p.enumerated() {
        let f = Double(k) * binHz
        weighted += f * v
        if f > 300 { high += v }
        if f < 1000, v > best {
          best = v
          dominant = f
        }
      }
      let m = (
        rms: 20 * log10(max(rms, 1e-12)), peak: peak, centroid: total > 0 ? weighted / total : 0,
        above300: total > 0 ? high / total : 0, dominant: dominant
      )
      metrics[seg.name] = m
      print(String(format: "RHEO-FEEL seg %-7@ RMS %6.1f dBFS  peak %.3f  crest %5.1f  centroid %6.0f Hz  >300 Hz %3.0f%%  dominant<1k %4.0f Hz",
        seg.name, m.rms, m.peak, m.peak / max(rms, 1e-12), m.centroid, 100 * m.above300, m.dominant))
    }
    print(String(format: "RHEO-FEEL render 3.5 s of audio in %.3f s (%.1f%% of real time, this build)", elapsed, 100 * elapsed / 3.5))

    let water = try XCTUnwrap(metrics["water"]), honey = try XCTUnwrap(metrics["honey"])
    let oobleck = try XCTUnwrap(metrics["oobleck"]), pour = try XCTUnwrap(metrics["pour"])
    let shake = try XCTUnwrap(metrics["shake"]), rest = try XCTUnwrap(metrics["rest"])
    for (name, m) in [("water", water), ("honey", honey), ("oobleck", oobleck), ("pour", pour), ("shake", shake)] {
      XCTAssertTrue((-45 ... -10).contains(m.rms), "\(name) is audible but not loud: \(m.rms) dBFS")
      XCTAssertLessThanOrEqual(m.peak, 1, name)
    }
    XCTAssertGreaterThan(water.centroid, 1.5 * honey.centroid, "water splashes bright, honey glorps low")
    XCTAssertGreaterThan(honey.above300, 0.2, "honey's low voice carries harmonics the speaker can play")
    XCTAssertGreaterThan(oobleck.peak / pow(10, oobleck.rms / 20), 4, "oobleck cracks are sharp transients")
    XCTAssertGreaterThan(pour.centroid, 1500, "pouring hisses")
    XCTAssertEqual(shake.dominant, 120, accuracy: 12, "the floor hums at its rate")
    XCTAssertGreaterThan(shake.above300, 0.15, "and its harmonics reach the speaker")
    XCTAssertLessThan(rest.rms, -80, "silent at rest: every tail has ended")
    XCTAssertEqual(kernel.activeVoices, 0)
  }

  // MARK: 4b. The tube and the lens (v2, PLAY 14 October 2026)

  /// The squeeze (REDESIGN.md §5): a soft continuous pressure in the hum that tracks the extrusion speed, a squish and a
  /// creak in the voice (toothpaste creaks, honey hardly), a soft squelch at the first push, one crisp tick and a
  /// squelch per tear-off event, and silence again once the squeeze stops. The glass lens is felt as the probe.
  func testSqueezeFeelsAndSoundsLikeASqueeze() {
    func squeezing(_ id: MaterialID, mmPerSecond v: Double) -> FeelSignals {
      var s = quiet(id)
      s.squeeze = .init(emitting: v > 0, speed: v * 1e-3, material: id)
      return s
    }
    var m = FeelMapper()
    _ = m.step(quiet("toothpaste"))
    let first = m.step(squeezing("toothpaste", mmPerSecond: 40))
    XCTAssertEqual(count(first, .squelch), 1, "the first push squelches")
    XCTAssertTrue(first.cause, "squeezing is a cause for the hum")
    var slow = FeelOutput(), fast = FeelOutput()
    for _ in 0..<30 { slow = m.step(squeezing("toothpaste", mmPerSecond: 20)) }
    for _ in 0..<30 { fast = m.step(squeezing("toothpaste", mmPerSecond: 80)) }
    XCTAssertEqual(count(fast, .squelch), 0, "no squelch while it keeps flowing")
    XCTAssertGreaterThan(slow.hum.intensity, 0.15)
    XCTAssertGreaterThan(fast.hum.intensity, slow.hum.intensity + 0.1, "the pressure tracks the rate")
    XCTAssertLessThan(fast.hum.sharpness, 0.4, "a soft pressure, not a buzz")
    XCTAssertGreaterThan(fast.gloop.squish, slow.gloop.squish + 0.2)
    XCTAssertGreaterThan(fast.gloop.creak, 0.8, "toothpaste creaks")
    var honey = FeelMapper()
    var h = FeelOutput()
    for _ in 0..<30 { h = honey.step(squeezing("honey", mmPerSecond: 80)) }
    XCTAssertLessThan(h.gloop.creak, 0.15, "honey glides")
    XCTAssertGreaterThan(h.gloop.squish, 0.8)

    // Release: the tube's speed falls; the tear-off event comes a few frames later, once.
    var stop = quiet("toothpaste")
    stop.squeeze = .init(emitting: false, speed: 0, material: "toothpaste")
    var after = FeelOutput()
    for _ in 0..<12 { after = m.step(stop) }
    var torn = stop
    torn.pasteEvents = [PasteEvent(kind: .tearOff, simTime: 1, position: SIMD2(0.035, 0.02), magnitude: 0.05)]
    let tick = m.step(torn)
    let ticks = tick.haptics.filter {
      if case .transient(_, let sharpness, _) = $0 { return sharpness >= 0.75 }
      return false
    }
    XCTAssertEqual(ticks.count, 1, "one crisp tick at the tear-off")
    XCTAssertEqual(count(tick, .squelch), 1, "and a squelch")
    for _ in 0..<60 { after = m.step(stop) }
    XCTAssertEqual(after.gloop.squish, 0, "silent once the squeeze stops")
    XCTAssertEqual(after.gloop.creak, 0)
    XCTAssertEqual(after.hum.intensity, 0)

    // The lens is the probe when no canvas finger is down: plunging it into honey squelches and hums.
    var lens = FeelMapper()
    var ls = quiet("honey")
    ls.lens = .init(position: SIMD2(0.035, 0.02), velocity: SIMD2(0, -0.2), radius: 0.006, tool: .probe)
    ls.probeStress = 40
    ls.probeSolid = 0
    let plunge = lens.step(ls)
    XCTAssertEqual(count(plunge, .squelch), 1, "the lens plunges in")
    XCTAssertGreaterThan(plunge.gloop.drag + lens.step(ls).hum.intensity, 0.05, "and is felt moving")
    print(String(format: "RHEO-FEEL squeeze hum %.2f/%.2f sharp %.2f squish %.2f/%.2f creak %.2f honey creak %.2f",
                 slow.hum.intensity, fast.hum.intensity, fast.hum.sharpness, slow.gloop.squish, fast.gloop.squish,
                 fast.gloop.creak, h.gloop.creak))
  }

  /// The squeeze voice: packed controls round-trip (a plain hiss value is hiss alone), the squish and creak play at a
  /// bed's level, the creak clicks faster as the squeeze speeds up, and the voice falls silent when they return to 0.
  func testSqueezeVoiceCreaksFasterWhenSqueezedHarder() {
    typealias S = GloopKernel.Slot
    let packed = S.packFlow(hiss: 0.4, squish: 0.6, creak: 0.9)
    let (hh, sq, cr) = GloopEngine.unpackFlow(packed)
    XCTAssertEqual(hh, 0.4, accuracy: 0.005)
    XCTAssertEqual(sq, 0.6, accuracy: 0.005)
    XCTAssertEqual(cr, 0.9, accuracy: 0.005)
    XCTAssertEqual(GloopEngine.unpackFlow(0.7).hiss, 0.7, accuracy: 1e-12, "a plain value is hiss alone")
    XCTAssertEqual(GloopEngine.unpackFlow(0.7).squish, 0)
    XCTAssertEqual(GloopEngine.unpackFlow(.nan).hiss, 0)

    func clicks(squish: Double) -> (rate: Double, rms: Double, peak: Double, samples: [Float]) {
      let kernel = GloopKernel()
      kernel.prepare(sampleRate: 48_000)
      let c = SynthControls()
      c.set(S.thick, S.packTimbre(thick: 0.9, grit: 0))
      c.set(S.hiss, S.packFlow(hiss: 0, squish: squish, creak: 1))
      _ = render(kernel, c, seconds: 0.3)
      let (l, _) = render(kernel, c, seconds: 2)
      let rms = (l.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(l.count)).squareRoot()
      let peak = Double(l.map { abs($0) }.max() ?? 0)
      // Clicks: envelope peaks above a quarter of the peak, at least 6 ms apart.
      var n = 0, last = -10_000
      for (i, v) in l.enumerated() where abs(v) > Float(0.25 * peak) && i - last > 288 {
        n += 1
        last = i
      }
      return (Double(n) / 2, 20 * log10(max(rms, 1e-12)), peak, l)
    }
    let gentle = clicks(squish: 0.35), hard = clicks(squish: 1)
    checkSamples(gentle.samples, "gentle squeeze")
    checkSamples(hard.samples, "hard squeeze")
    XCTAssertGreaterThan(hard.rate, 1.6 * gentle.rate, "the creak clicks faster when squeezed harder")
    XCTAssertTrue((-45 ... -12).contains(hard.rms), "a bed's level: \(hard.rms) dBFS")
    XCTAssertLessThan(hard.peak, 0.9)
    print(String(format: "RHEO-FEEL squeeze voice: creak %.0f/%.0f clicks/s, RMS %.1f/%.1f dBFS, peak %.2f",
                 gentle.rate, hard.rate, gentle.rms, hard.rms, hard.peak))

    let kernel = GloopKernel()
    kernel.prepare(sampleRate: 48_000)
    let c = SynthControls()
    c.set(S.hiss, S.packFlow(hiss: 0, squish: 1, creak: 1))
    _ = render(kernel, c, seconds: 0.5)
    c.set(S.hiss, 0)
    _ = render(kernel, c, seconds: 0.5)
    let (rest, _) = render(kernel, c, seconds: 0.2)
    XCTAssertLessThan(Double(rest.map { abs($0) }.max() ?? 0), 1e-4, "silent once the squeeze stops")
  }

  // MARK: 5. Real frames

  @MainActor func testRealFramesDriveTheFeel() throws {
    let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    let queue = try XCTUnwrap(device.makeCommandQueue())
    for (name, args) in [("honey-stir", ["-material", "honey", "-fakeTouch", "stir"]), ("oobleck-punch", ["-fakeTouch", "punch"])] {
      let model = ToothpasteModel(launch: ToothpasteLaunch.parse(["ToothpasteToy", "-noPersist", "-material", "oobleck"] + args), device: device)
      model.canvasRegion = CGRect(x: 0, y: 59, width: 430, height: 612.3)
      let feel = try XCTUnwrap(model.feel as? ToothpasteFeel)
      var maxI = 0.0, maxS = 0.0, maxDrag = 0.0, causes = 0
      var kinds: [GloopTrigger.Kind: Int] = [:]
      var taps: [String: Int] = [:]
      var pitches: [Double] = []
      for _ in 0..<(120 * 3) {
        model.advance(dt: 1.0 / 120)
        let cmd = try XCTUnwrap(queue.makeCommandBuffer())
        model.engine.encode(into: cmd)
        cmd.commit()
        cmd.waitUntilCompleted()
        let out = feel.lastOutput
        if out.cause { causes += 1 }
        maxI = max(maxI, out.hum.intensity)
        maxS = max(maxS, out.hum.sharpness)
        maxDrag = max(maxDrag, out.gloop.drag)
        pitches.append(out.gloop.pitch)
        for t in out.triggers { kinds[t.kind, default: 0] += 1 }
        for h in out.haptics { taps[String(describing: h).components(separatedBy: "(").first ?? "?", default: 0] += 1 }
      }
      // The resting-surface estimate from the solver's mass agrees with the fill line (no pour in these runs).
      let frame = model.latestFrame
      let signals = FeelSignals.make(
        frame: frame, dt: 1.0 / 120, catalog: model.catalog, gap: model.resources.solver?.domain.heleShawGap ?? 0.01,
        micLive: false)
      let fillLine = model.catalog.material(frame.material).fillFraction * frame.tank.y
      print(String(format: "RHEO-FEEL surface %@: %.2f mm from mass %.4g kg (J %.3f) vs fill line %.2f mm, slope %.3f",
        name, 1000 * signals.surface, frame.stats.particleMass, frame.stats.volumeRatio, 1000 * fillLine,
        signals.surfaceSlope))
      XCTAssertEqual(signals.surface, fillLine, accuracy: 0.15 * fillLine, name)
      XCTAssertTrue(pitches.allSatisfy { $0.isFinite && $0 >= 110 && $0 <= 880 }, name)
      XCTAssertGreaterThan(causes, 0, "\(name): the finger is a cause")
      XCTAssertGreaterThan(maxI, 0.1, "\(name): the fluid pushes back")
      XCTAssertLessThanOrEqual(maxI, 1)
      if name == "oobleck-punch" { XCTAssertGreaterThan(kinds[.crack, default: 0], 0, "the punch knocks") }
      if name == "honey-stir" { XCTAssertGreaterThan(maxDrag, 0.1, "stirring honey drags") }
      print(String(format: "RHEO-FEEL frames %@: hum max I %.2f S %.2f, drag %.2f, causes %d/360, pitch %.0f–%.0f Hz, triggers %@, haptics %@",
        name, maxI, maxS, maxDrag, causes, pitches.min() ?? 0, pitches.max() ?? 0,
        String(describing: kinds), String(describing: taps)))
    }
  }
}

extension FeelTests {
  /// The voice inside LabKit's real SynthHost: AVAudioEngine calls `GloopKernel.render` on Core Audio's I/O thread.
  /// A main-actor-isolated closure or method there would trap (the Swift 6 audio-thread rule); this would crash.
  /// (It plays about 2 s of gloop through the Mac's speakers.)
  @MainActor func testVoiceRunsOnTheRealAudioThread() throws {
    let model = ToothpasteModel(launch: ToothpasteLaunch.parse(["ToothpasteToy", "-noPersist", "-material", "oobleck", "-fakeTouch", "punch"]), device: nil)
    let synth = try XCTUnwrap(model.feedback.synth)
    let kernel = try XCTUnwrap(synth.kernel as? GloopKernel)
    guard model.feedback.sound else { throw XCTSkip("Sound is off in this simulator's settings") }
    model.setActive(true)
    defer { model.setActive(false) }
    guard synth.running else { throw XCTSkip("AVAudioEngine did not start (no audio output)") }
    #if os(iOS)
    XCTAssertEqual(
      AVAudioSession.sharedInstance().category, .ambient, "microphone off: .ambient, so the ring/silent switch mutes Toothpaste Toy")
    #endif
    let before = kernel.renderCount
    let feel = try XCTUnwrap(model.feel as? ToothpasteFeel)
    var triggers = 0
    let end = Date().addingTimeInterval(2.2)
    while Date() < end {
      model.advance(dt: 1.0 / 120)
      triggers += feel.lastOutput.triggers.count
      RunLoop.main.run(until: Date().addingTimeInterval(1.0 / 120))
    }
    let calls = kernel.renderCount - before
    XCTAssertGreaterThan(calls, 20, "the audio thread rendered the voice")
    XCTAssertEqual(feel.bedMix.hostGain, 1, "the voice's gain is open while Sound is on")
    XCTAssertGreaterThan(feel.bedMix.bedScale, 0.5, "and the bed follows the running simulation")
    XCTAssertEqual(synth.bedGain, 1)
    print("RHEO-FEEL audio thread: \(calls) render calls in 2.2 s, \(triggers) triggers, bed scale \(feel.bedMix.bedScale)")
  }
}

extension FeelMapper {
  /// One step from a fresh copy (tests).
  fileprivate func stepped(_ s: FeelSignals) -> FeelOutput {
    var m = self
    return m.step(s)
  }
}
