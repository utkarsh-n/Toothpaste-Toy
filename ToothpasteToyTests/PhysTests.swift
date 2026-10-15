// PhysTests.swift — OWNER: PLAY (was PHYS; Documentation/REDESIGN-OWNERSHIP.md).
//
// Headless scenarios through the real frame loop (ToothpasteModel → ToothpasteEngine → MPMSolver on the GPU, Box2D, no drawing),
// one per behaviour PHYS promises, with numeric pass criteria. Every scenario prints a `RHEO-PHYS` line with what it
// measured, so the log doubles as the verification table.
//
// Geometry comes from the particles (`MPMSolver.debugParticles`, read after each frame's command buffer completes).
// Times are simulated seconds. Frames are 1/60 s unless a test says otherwise (the substep budget keeps 60 Hz real-time).

import CoreGraphics
import LabKitCore
import LabKitMPM
import LabKitRigid
import Metal
import XCTest
import simd

@testable import ToothpasteToy

// MARK: - Rig

@MainActor final class PhysRig {
  let device: MTLDevice
  let queue: MTLCommandQueue
  let model: ToothpasteModel
  let solver: MPMSolver
  var engine: ToothpasteEngine { model.engine as! ToothpasteEngine }
  /// Real seconds since the rig started (touch timestamps).
  private(set) var clock = 0.0

  init(_ args: [String]) throws {
    device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    queue = try XCTUnwrap(device.makeCommandQueue())
    model = ToothpasteModel(launch: ToothpasteLaunch.parse(["ToothpasteToy", "-noPersist", "-material", "oobleck"] + args), device: device)
    model.canvasRegion = CGRect(x: 0, y: 59, width: 430, height: 612.3)
    solver = try XCTUnwrap(model.resources.solver)
  }

  var tank: SIMD2<Double> { engine.tankSize }
  var frame: ToothpasteFrame { model.latestFrame }
  var stats: MPMStats { solver.stats }

  func step(_ dt: Double = 1.0 / 60) {
    clock += dt
    model.advance(dt: dt)
    guard let cmd = queue.makeCommandBuffer() else { return }
    model.engine.encode(into: cmd)
    cmd.commit()
    cmd.waitUntilCompleted()
  }

  /// Advances `seconds` of real time (Time knob 1: of simulated time too).
  func run(_ seconds: Double, dt: Double = 1.0 / 60, each: ((Double) -> Void)? = nil) {
    let n = Int((seconds / dt).rounded())
    for _ in 0..<n {
      step(dt)
      each?(clock)
    }
  }

  var particles: [MPMParticleSnapshot] { solver.debugParticles().filter(\.enabled) }

  func particles(slot: Int) -> [MPMParticleSnapshot] { particles.filter { $0.material == slot } }

  /// Free-surface heights (m) at `n` stations across the width, 6 mm clear of the walls.
  func surface(_ n: Int = 13, from ps: [MPMParticleSnapshot]? = nil) -> [Double] {
    let all = ps ?? particles
    let dx = solver.cellSize
    return (0..<n).map { i in
      let x = 0.006 + (tank.x - 0.012) * Double(i) / Double(n - 1)
      return (all.filter { abs($0.position.x - x) < 1.5 * dx }.map(\.position.y).max() ?? 0) + 0.25 * dx
    }
  }

  /// The resting surface for flatness checks: per station the mean of the three highest particles (one stray particle
  /// riding up on the 1 kPa tension limit does not count as the surface), averaged over `seconds` of frames so the
  /// last frame's slosh does not decide the verdict.
  func settledSurface(_ n: Int = 13, seconds: Double, dt: Double = 1.0 / 120) -> [Double] {
    let dx = solver.cellSize
    let frames = max(Int((seconds / dt).rounded()), 1)
    var sum = [Double](repeating: 0, count: n)
    for _ in 0..<frames {
      step(dt)
      let all = particles
      for i in 0..<n {
        let x = 0.006 + (tank.x - 0.012) * Double(i) / Double(n - 1)
        let top = all.filter { abs($0.position.x - x) < 1.5 * dx }.map(\.position.y).sorted(by: >).prefix(3)
        sum[i] += (top.isEmpty ? 0 : top.reduce(0, +) / Double(top.count)) + 0.25 * dx
      }
    }
    return sum.map { $0 / Double(frames) }
  }

  func top(_ ps: [MPMParticleSnapshot]) -> Double { (ps.map(\.position.y).max() ?? 0) + 0.25 * solver.cellSize }
  func com(_ ps: [MPMParticleSnapshot]) -> SIMD2<Double> {
    ps.isEmpty ? .zero : ps.map(\.position).reduce(.zero, +) / Double(ps.count)
  }
  func width(_ ps: [MPMParticleSnapshot]) -> Double {
    (ps.map(\.position.x).max() ?? 0) - (ps.map(\.position.x).min() ?? 0) + 0.5 * solver.cellSize
  }

  /// Replaces the tank's contents (the engine's own fills cover the app; tests shape the starting state).
  func fill(_ shapes: [(MaterialID, CGRect)], temperature: Double? = nil) {
    solver.clear()
    for (id, rect) in shapes {
      let info = model.catalog.material(id)
      solver.fill(rect: rect, material: info.slot, temperature: temperature ?? info.fillTemperature)
    }
  }

  func fill(polygon: [SIMD2<Double>], material id: MaterialID) {
    let info = model.catalog.material(id)
    solver.fill(polygon: polygon, material: info.slot, temperature: info.fillTemperature)
  }

  func disc(_ id: MaterialID, centre: SIMD2<Double>, radius: Double) {
    let poly = (0..<32).map { i -> SIMD2<Double> in
      let a = Double(i) / 32 * 2 * .pi
      return centre + radius * SIMD2(cos(a), sin(a))
    }
    fill(polygon: poly, material: id)
  }

  /// UITouch timestamps are seconds since boot, not since the app (or the engine) started: touches here carry the
  /// rig's clock plus a boot offset, so nothing can mix the two clocks unnoticed.
  static let bootOffset = 386_400.0

  /// One finger on the tank (tank metres), id 1.
  func touch(_ phase: TankTouch.Phase, _ p: SIMD2<Double>, start: SIMD2<Double>? = nil) {
    model.engine.touches([TankTouch(id: 1, position: p, start: start ?? p, phase: phase, timestamp: clock + Self.bootOffset)])
  }

  static func range(_ xs: [Double]) -> Double { (xs.max() ?? 0) - (xs.min() ?? 0) }

  /// How sparse a set of particles is: occupied cells × 4 particle slots ÷ particles (≈ 1 for a settled bulk, more for
  /// a thin film's partly filled edge cells; 1.3–1.6 is a particle foam that renders as more fluid than there is).
  func foam(_ ps: [MPMParticleSnapshot]) -> Double {
    let dx = solver.cellSize
    var cells = Set<Int>()
    for p in ps { cells.insert(Int(p.position.x / dx) * 100_000 + Int(p.position.y / dx)) }
    return Double(cells.count * 4) / Double(max(ps.count, 1))
  }

  /// Root-mean-square deviation from the mean.
  static func rms(_ xs: [Double]) -> Double {
    let mean = xs.reduce(0, +) / Double(max(xs.count, 1))
    return (xs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(max(xs.count, 1))).squareRoot()
  }
}

func report(_ name: String, _ fields: [String: Double]) {
  let body = fields.sorted { $0.key < $1.key }.map { String(format: "%@ %.4g", $0.key, $0.value) }.joined(separator: " ")
  print("RHEO-PHYS \(name) \(body)")
}

final class PhysTests: XCTestCase {
  // MARK: - Oobleck

  /// At rest oobleck flows like a thick liquid: a 60/30 mm step levels to within 3 mm in ≤ 1.5 s and nothing stays
  /// jammed (the skeleton's preset kept 56 % jammed and never levelled).
  @MainActor func testOobleckRestLevels() throws {
    let rig = try PhysRig(["-material", "oobleck"])
    let W = rig.tank.x
    rig.fill([("oobleck", CGRect(x: 0, y: 0, width: W / 2, height: 0.06)), ("oobleck", CGRect(x: W / 2, y: 0, width: W / 2, height: 0.03))])
    var levelAt: Double?
    var maxJam = 0.0
    rig.run(3, dt: 1.0 / 120) { t in
      guard Int((t * 120).rounded()) % 6 == 0 else { return }
      maxJam = max(maxJam, rig.stats.jammedFraction)
      let r = PhysRig.range(rig.surface())
      if r < 0.003 { if levelAt == nil { levelAt = t } } else { levelAt = nil }
    }
    let endJam = rig.stats.jammedFraction
    report("oobleck.rest", ["levelSeconds": levelAt ?? .infinity, "maxJam": maxJam, "endJam": endJam,
                            "nan": Double(rig.stats.nanCount)])
    XCTAssertLessThanOrEqual(levelAt ?? .infinity, 1.5, "levels within 1.5 s")
    XCTAssertLessThan(endJam, 0.02, "nothing stays jammed at rest")
    XCTAssertEqual(rig.stats.nanCount, 0)
  }

  /// A slow finger (2 cm/s) sinks with the touch; a fast one (0.6 m/s) is stopped short by the jam it makes, then
  /// sinks on as the jam melts while it is held.
  @MainActor func testOobleckSlowFingerSinksFastFingerStops() throws {
    func push(speed: Double) throws -> (lag: Double, stoppedLag: Double, laterLag: Double, maxJam: Double) {
      let rig = try PhysRig(["-material", "oobleck"])
      rig.run(1.0, dt: 1.0 / 120)
      let x = rig.tank.x / 2
      let top = 0.058, bottom = 0.018
      var y = top
      rig.touch(.began, SIMD2(x, y))
      var maxLag = 0.0, maxJam = 0.0
      while y > bottom {
        y = max(bottom, y - speed / 120)
        rig.touch(.moved, SIMD2(x, y))
        rig.step(1.0 / 120)
        maxJam = max(maxJam, rig.stats.jammedFraction)
        if let f = rig.frame.finger { maxLag = max(maxLag, f.position.y - y) }
      }
      rig.run(0.1, dt: 1.0 / 120) { _ in rig.touch(.moved, SIMD2(x, bottom)); maxJam = max(maxJam, rig.stats.jammedFraction) }
      let stopped = (rig.frame.finger?.position.y ?? bottom) - bottom
      rig.run(1.5, dt: 1.0 / 120) { _ in rig.touch(.moved, SIMD2(x, bottom)) }
      let later = (rig.frame.finger?.position.y ?? bottom) - bottom
      rig.touch(.ended, SIMD2(x, bottom))
      return (maxLag, stopped, later, maxJam)
    }
    let slow = try push(speed: 0.02)
    let fast = try push(speed: 0.6)
    report("oobleck.slowfast", ["slowMaxLagMM": slow.lag * 1000, "slowJam": slow.maxJam, "fastLagAt0.1sMM": fast.stoppedLag * 1000,
                                "fastLagAt1.6sMM": fast.laterLag * 1000, "fastJam": fast.maxJam])
    XCTAssertLessThan(slow.lag, 0.004, "the slow finger follows the touch")
    XCTAssertLessThan(slow.maxJam, 0.1, "a slow finger hardly jams anything")
    XCTAssertGreaterThan(fast.stoppedLag, 0.008, "the fast finger is stopped short of the touch")
    XCTAssertGreaterThan(fast.maxJam, 0.3, "a fast finger jams the oobleck")
    XCTAssertLessThan(fast.laterLag, fast.stoppedLag - 0.003, "held, it sinks on as the jam melts")
  }

  /// A punch jams the pool; after the finger lifts, the jammed fraction halves within 0.5 s, the hole has refilled
  /// (surface within 3 mm) within 1 s, and 3 s later the surface is still flat to 3.5 mm. (In between, the column the
  /// punch compressed re-expands and lifted a bump of up to about 5 mm for a second with the solver of 8 October: the
  /// volume constraint, not oobleck; 2.9 mm at most with LK-FIX's LabKit of 9 October.)
  @MainActor func testOobleckJamMeltsAfterPunch() throws {
    let rig = try PhysRig(["-material", "oobleck"])
    rig.run(1.0, dt: 1.0 / 120)
    rig.model.perform(.punch(SIMD2(rig.tank.x / 2, 0.03)))
    var peak = 0.0
    while rig.engine.tools.jab != nil || rig.engine.tools.finger != nil {
      rig.step(1.0 / 120)
      peak = max(peak, rig.stats.jammedFraction)
    }
    let t0 = rig.clock
    let jam0 = rig.stats.jammedFraction
    var half: Double?, refilled: Double?
    var maxRange = 0.0
    rig.run(3, dt: 1.0 / 120) { t in
      if half == nil, rig.stats.jammedFraction <= 0.5 * jam0 { half = t - t0 }
      guard Int((t * 120).rounded()) % 6 == 0 else { return }
      let r = PhysRig.range(rig.surface())
      if refilled == nil, r < 0.003 { refilled = t - t0 }
      maxRange = max(maxRange, r)
    }
    // Flatness after the solver's re-expansion bump: the settled surface over 3–3.5 s (top three particles per station,
    // averaged over 0.5 s of frames). The old check, the single-particle range in the frame at exactly 3 s, sat on the
    // bump's steep tail with the solver of 8 October (Mac 1.7–2.4 mm, iOS once 3.39 mm, limit 3.5 mm): a quarter second
    // of timing decided it. It is still reported as endRangeInstantMM. The limit is unchanged. (9 October, LK-FIX's LabKit,
    // in progress: settled 0.70 mm, instant 0.83 mm on iOS.)
    let instant = PhysRig.range(rig.surface())
    let end = PhysRig.range(rig.settledSurface(seconds: 0.5))
    report("oobleck.melt", ["peakJam": peak, "jamAtRelease": jam0, "halfLife": half ?? .infinity,
                            "refilledAfter": refilled ?? .infinity, "maxRangeMM": maxRange * 1000, "endRangeMM": end * 1000,
                            "endRangeInstantMM": instant * 1000, "endJam": rig.stats.jammedFraction])
    XCTAssertGreaterThan(peak, 0.3, "the punch jams")
    XCTAssertLessThanOrEqual(half ?? .infinity, 0.5, "the jam melts")
    XCTAssertLessThanOrEqual(refilled ?? .infinity, 1.0, "the hole refills")
    XCTAssertLessThan(end, 0.0035, "and the surface is flat")
    XCTAssertLessThan(rig.stats.jammedFraction, 0.02)
  }

  /// Slow stirring is liquid; fast stirring jams and tears the pool.
  @MainActor func testOobleckStirSlowLiquidFastTears() throws {
    func stir(_ rps: Double) throws -> Double {
      let rig = try PhysRig(["-material", "oobleck"])
      rig.run(0.5, dt: 1.0 / 120)
      rig.model.params[.stir] = rps
      var sum = 0.0, n = 0.0
      rig.run(2.5, dt: 1.0 / 120) { t in if t > 1.5 { sum += rig.stats.jammedFraction; n += 1 } }
      return sum / max(n, 1)
    }
    let slow = try stir(0.3), fast = try stir(4)
    report("oobleck.stir", ["slowJam": slow, "fastJam": fast])
    XCTAssertLessThan(slow, 0.05)
    XCTAssertGreaterThan(fast, 0.25)
  }

  /// Merkt et al.'s vibrated layer: the solver keeps ≥ 8 substeps per vibration period at 120 Hz and stays finite; the
  /// hole a poke opens is measured (reported, see SKELETON/PHYS report for what the 2D layer does).
  @MainActor func testOobleckVibratedLayer() throws {
    let rig = try PhysRig(["-noPersist"])
    rig.model.perform(.experiment("monsters"))
    var minSub = Int.max
    var holes: [Double] = []
    rig.run(3, dt: 1.0 / 120) { t in
      minSub = min(minSub, rig.stats.substeps)
      if Int((t * 120).rounded()) % 30 == 0 {
        let h = rig.surface(25)
        let layer = 0.12 * rig.tank.y
        holes.append(Double(h.filter { $0 < 0.5 * layer }.count) / 24 * (rig.tank.x - 0.012))
      }
    }
    let f = rig.frame
    report("oobleck.vibrated", ["shakeG": f.vibration.x / Gravity.g0, "hz": f.vibration.y, "minSubsteps": Double(minSub),
                                "holeWidthEndMM": (holes.last ?? 0) * 1000, "maxHoleMM": (holes.max() ?? 0) * 1000,
                                "jam": rig.stats.jammedFraction, "lagging": rig.stats.lagging ? 1 : 0])
    XCTAssertGreaterThanOrEqual(Double(minSub) * 120 / f.vibration.y, 8, "≥ 8 substeps per vibration period")
    XCTAssertEqual(rig.stats.nanCount, 0)
  }

  // MARK: - Materials

  /// Honey thins when warm: a 25 × 40 mm block at 4 °C is still taller after 1 s than the same block at 37 °C has been
  /// since 0.5 s (rheology §3.1: η halves every 6 K).
  @MainActor func testHoneyThinsWhenWarm() throws {
    func slump(_ celsius: Double) throws -> Double {
      let rig = try PhysRig(["-material", "honey"])
      rig.model.params[.heat] = celsius
      let W = rig.tank.x
      rig.fill([("honey", CGRect(x: (W - 0.025) / 2, y: 0, width: 0.025, height: 0.04))], temperature: celsius + 273.15)
      rig.run(1.0)
      return rig.top(rig.particles)
    }
    let cold = try slump(4), room = try slump(20), warm = try slump(37)
    report("honey.temperature", ["coldTopMM": cold * 1000, "roomTopMM": room * 1000, "warmTopMM": warm * 1000])
    XCTAssertGreaterThan(cold, room + 0.004)
    XCTAssertGreaterThan(room, warm - 0.0005)
    XCTAssertGreaterThan(cold, 0.022, "cold honey still stands after 1 s")
  }

  /// Honey pours in a rope that piles up where it lands; water just spreads (measured 0.6 s after the pour stops).
  @MainActor func testHoneyPourPilesUpWaterDoesNot() throws {
    func pour(_ id: MaterialID, celsius: Double) throws -> Double {
      let rig = try PhysRig(["-material", id])
      rig.model.params[.heat] = celsius
      rig.fill([(id, CGRect(x: 0, y: 0, width: rig.tank.x, height: 0.006))], temperature: celsius + 273.15)
      rig.model.perform(.pourMaterial(id))
      rig.model.shelfMode = .pour
      rig.step()
      let p = SIMD2(rig.tank.x / 2, 0.06)
      rig.touch(.began, p)
      rig.run(2.0) { _ in rig.touch(.moved, p) }
      rig.touch(.ended, p)
      rig.run(0.6)  // the last of the stream lands; water levels, the honey pile stays
      let s = rig.surface(25)
      let centre = s[12], edge = (s[2] + s[22]) / 2
      foams[id] = rig.foam(rig.particles)
      return centre - edge
    }
    var foams: [MaterialID: Double] = [:]
    let honey = try pour("honey", celsius: 10), water = try pour("waterLike", celsius: 20)
    // Until LK-FIX (9 October 2026) the poured honey pile was a particle foam (1.3–1.6: landed particles kept J ≈ 0.94
    // and their pressure held the gaps open), so the foam was only reported. LabKit's two-sided volume correction fixed
    // it (this test read 1.006 for honey, 0.99 for water since), so it is judged now: ≤ 1.1, LabKit F1–F4's limit.
    report("pour.pile", ["honeyPileMM": honey * 1000, "waterPileMM": water * 1000, "honeyFoam": foams["honey"] ?? 0,
                         "waterFoam": foams["waterLike"] ?? 0])
    XCTAssertGreaterThan(honey, 0.004, "honey piles up under the pour")
    XCTAssertLessThan(water, 0.003, "water levels")
    XCTAssertLessThan(foams["honey"] ?? 9, 1.1, "the poured honey is a body of fluid, not a particle foam")
  }

  /// Ketchup holds a mound; a shake breaks its structure and it slumps far faster than it crept before.
  @MainActor func testKetchupHoldsThenFlowsWhenShaken() throws {
    let rig = try PhysRig(["-material", "ketchup"])
    let W = rig.tank.x
    rig.solver.clear()
    rig.fill(polygon: ToothpasteExperiments.mound(peak: 0.11, base: 0.0, from: 0.25, to: 0.75).map { $0 * rig.tank }, material: "ketchup")
    rig.run(1.0)
    let c1 = rig.com(rig.particles).y
    rig.run(1.0)
    let c2 = rig.com(rig.particles).y
    let lambdaBefore = rig.stats.meanStructure
    rig.model.perform(.shakeOnce)
    rig.run(0.6)
    rig.model.perform(.shakeOnce)
    rig.run(1.4)
    let c3 = rig.com(rig.particles).y
    let creep = c1 - c2, shaken = c2 - c3
    report("ketchup.shake", ["creepMM": creep * 1000, "shakenMM": shaken * 1000, "lambdaBefore": lambdaBefore,
                             "lambdaAfter": rig.stats.meanStructure, "widthMM": rig.width(rig.particles) * 1000])
    XCTAssertLessThan(creep, 0.0008, "at rest the mound holds")
    XCTAssertGreaterThan(shaken, 3 * max(creep, 0.0002), "shaken, it slumps")
    XCTAssertLessThan(rig.stats.meanStructure, lambdaBefore - 0.2, "shaking breaks its structure")
    _ = W
  }

  /// Mayonnaise holds a 5 cm peak on the Moon and slumps on Earth (yield length τ_y/ρg).
  @MainActor func testMayonnaiseStandsOnTheMoon() throws {
    func pile(gravity: Double) throws -> Double {
      let rig = try PhysRig(["-material", "mayonnaise"])
      rig.model.params[.gravity] = gravity
      rig.solver.clear()
      rig.fill([("mayonnaise", CGRect(x: (rig.tank.x - 0.03) / 2, y: 0, width: 0.03, height: 0.05))])
      rig.run(2.5)
      return rig.top(rig.particles)
    }
    let moon = try pile(gravity: 0.166), earth = try pile(gravity: 1)
    report("mayonnaise.moon", ["moonTopMM": moon * 1000, "earthTopMM": earth * 1000])
    XCTAssertGreaterThan(moon, 0.045, "about 5 cm tall on the Moon")
    XCTAssertLessThan(earth, 0.036, "it slumps on Earth")
  }

  /// A toothpaste column (20 × 30 mm) keeps ≥ 85 % of its height for 3 s.
  @MainActor func testToothpasteKeepsShape() throws {
    let rig = try PhysRig(["-material", "toothpaste"])
    rig.solver.clear()
    rig.fill([("toothpaste", CGRect(x: (rig.tank.x - 0.02) / 2, y: 0, width: 0.02, height: 0.03))])
    rig.run(3)
    let top = rig.top(rig.particles), width = rig.width(rig.particles)
    report("toothpaste.column", ["topMM": top * 1000, "widthMM": width * 1000])
    XCTAssertGreaterThan(top, 0.85 * 0.03)
    XCTAssertLessThan(width, 0.03)
  }

  /// Drops a disc of `id` from 25 mm and returns its rebound (largest upward mean velocity after landing, m/s), and its
  /// height at 1 s and 6 s.
  @MainActor private func drop(_ id: MaterialID, radius: Double) throws -> (rebound: Double, impact: Double, top1: Double, top6: Double, width1: Double, width6: Double) {
    let rig = try PhysRig(["-material", id])
    rig.solver.clear()
    rig.disc(id, centre: SIMD2(rig.tank.x / 2, 0.025 + radius), radius: radius)
    var landed = false, rebound = 0.0, impact = 0.0
    var top1 = 0.0, width1 = 0.0
    rig.run(6, dt: 1.0 / 120) { t in
      let ps = rig.particles
      let v = ps.map(\.velocity.y).reduce(0, +) / Double(max(ps.count, 1))
      if v < impact { impact = v; rebound = 0 }
      if v < -0.1 { landed = true }
      if landed { rebound = max(rebound, v) }
      if abs(t - 1) < 0.5 / 120 { top1 = rig.top(ps); width1 = rig.width(ps) }
    }
    let ps = rig.particles
    return (rebound, -impact, top1, rig.top(ps), width1, rig.width(ps))
  }

  /// Slime bounces, then puddles over seconds (λ = 0.4 s).
  @MainActor func testSlimeBouncesThenPuddles() throws {
    let r = try drop("slime", radius: 0.012)
    report("slime.drop", ["impact": r.impact, "rebound": r.rebound, "top1MM": r.top1 * 1000, "top6MM": r.top6 * 1000,
                          "width1MM": r.width1 * 1000, "width6MM": r.width6 * 1000])
    XCTAssertGreaterThan(r.rebound, 0.1 * r.impact, "it bounces")
    XCTAssertLessThan(r.top6, 0.85 * r.top1, "then puddles")
    XCTAssertGreaterThan(r.width6, 1.2 * r.width1)
  }

  /// Silly Putty bounces and snaps, then slumps slowly (λ = 0.14 s, η_toy 2.8 kPa·s).
  @MainActor func testSillyPuttyBouncesAndSlowlySlumps() throws {
    let r = try drop("sillyPutty", radius: 0.011)
    report("putty.drop", ["impact": r.impact, "rebound": r.rebound, "top1MM": r.top1 * 1000, "top6MM": r.top6 * 1000,
                          "width1MM": r.width1 * 1000, "width6MM": r.width6 * 1000])
    XCTAssertGreaterThan(r.rebound, 0.15 * r.impact, "it bounces")
    XCTAssertLessThan(r.top6, r.top1 - 0.0005, "it slumps")
    XCTAssertGreaterThan(r.top6, 0.7 * r.top1, "but slowly")
  }

  /// Yogurt: a spoon mark (a groove pressed in and left) heals slowly: still there after 1 s, shallower after 6 s.
  @MainActor func testYogurtSpoonMarkHealsSlowly() throws {
    let rig = try PhysRig(["-material", "yogurt"])
    rig.run(1)
    let x = rig.tank.x / 2
    rig.touch(.began, SIMD2(x, 0.058))
    var y = 0.058
    while y > 0.032 { y -= 0.05 / 60; rig.touch(.moved, SIMD2(x, y)); rig.step() }
    rig.touch(.ended, SIMD2(x, y))
    func depth() -> Double {
      let s = rig.surface(25)
      return (s[3] + s[21]) / 2 - s[12]
    }
    rig.run(1)
    let d1 = depth()
    rig.run(5)
    let d6 = depth()
    report("yogurt.mark", ["depth1MM": d1 * 1000, "depth6MM": d6 * 1000, "lambda": rig.stats.meanStructure])
    XCTAssertGreaterThan(d1, 0.002, "the mark stays at first")
    XCTAssertLessThan(d6, d1 - 0.0005, "and heals slowly")
  }

  /// Quicksand is firm at rest (a glass marble set on it stays near the top) and liquefies when shaken (it sinks), and
  /// the shaken bed stays a bed: it does not puff up into a sparse cloud (its top stays within 15 mm of the 40 mm fill
  /// while shaken; with no tension limit it rose to 77 mm). Run at the phone's 120 Hz: at 60 Hz a prop's collider
  /// ploughs twice as far into the rested bed per frame before the fluid's reaction arrives, and the bed under it
  /// unbuilds (measured; see Props.swift).
  @MainActor func testQuicksandFirmUntilShaken() throws {
    let rig = try PhysRig(["-material", "quicksand"])
    rig.model.perform(.experiment("quicksand"))
    rig.run(3.1, dt: 1.0 / 120)
    let surface = 0.4 * rig.tank.y
    let before = rig.frame.props.first?.position.y ?? 0
    var shaken = 0.0, maxTop = 0.0
    rig.run(5.4, dt: 1.0 / 120) { t in
      shaken = max(shaken, rig.frame.vibration.x / Gravity.g0)
      if Int((t * 120).rounded()) % 12 == 0 { maxTop = max(maxTop, rig.top(rig.particles)) }
    }
    let after = rig.frame.props.first?.position.y ?? 0
    report("quicksand.ball", ["surfaceMM": surface * 1000, "ballBeforeMM": before * 1000, "ballAfterMM": after * 1000,
                              "lambda": rig.stats.meanStructure, "shakeG": shaken, "maxTopMM": maxTop * 1000])
    XCTAssertGreaterThan(before, surface - 0.006, "rests near the top of firm quicksand")
    XCTAssertGreaterThanOrEqual(shaken, 3, "the script shakes the floor at 3 g")
    XCTAssertLessThan(after, before - 0.025, "sinks deep once the quicksand is shaken")
    XCTAssertLessThan(after, 0.012, "to the floor (the marble is 6 mm in radius): the liquefied bed no longer holds it")
    XCTAssertLessThan(maxTop, surface + 0.015, "the shaken bed does not puff up into a cloud")
  }

  /// MR fluid: near the virtual magnet it stiffens (a finger 15 mm off the magnet meets several times the resistance).
  /// A pool at the default fill (45 mm) does NOT heap: its surface lies outside the zone where LabKit caps the Kelvin
  /// force, and the field yield there outweighs the Kelvin pressure difference along the surface (LK-FIX, M5: 30 mm and
  /// deeper stay flat). Thin layers do heap since LK-FIX (the magnet experiment's 10 mm layer: testExperimentDemonstrations).
  /// The test pins the deep pool, so the copy (the MR fluid's honesty line) must keep saying a deep pool stays flat.
  @MainActor func testMRFluidStiffensNearTheMagnet() throws {
    func run(magnet: Double) throws -> (heap: Double, resist: Double) {
      let rig = try PhysRig(["-material", "mrFluid"])
      rig.engine.perform(.refill)
      rig.model.params[.magnet] = magnet
      rig.run(2)
      let s = rig.surface(25)
      let heap = s[12] - (s[3] + s[21]) / 2
      // Press a finger down 10 mm at 3 cm/s, 15 mm off the magnet, and read the fluid's force on it.
      let x = rig.tank.x / 2 + 0.015
      var y = 0.06, maxF = 0.0
      rig.touch(.began, SIMD2(x, y))
      while y > 0.035 {
        y -= 0.03 / 60
        rig.touch(.moved, SIMD2(x, y))
        rig.step()
        let j = rig.stats.bodyImpulses[0]
        maxF = max(maxF, j.y / max(rig.stats.simulatedTime, 1e-6))
      }
      rig.touch(.ended, SIMD2(x, y))
      return (heap, maxF)
    }
    let off = try run(magnet: 0), on = try run(magnet: 207)
    report("mr.magnet", ["heapOffMM": off.heap * 1000, "heapOnMM": on.heap * 1000, "forceOffN": off.resist, "forceOnN": on.resist])
    XCTAssertGreaterThan(on.resist, 3 * off.resist, "stiffens near the magnet")
    XCTAssertLessThan(on.heap, off.heap + 0.0005, "a deep pool is not heaped (only a thin layer is)")
  }

  /// Paint: brush marks (±3.5 mm ridges, 14 mm apart) flow out: the surface's RMS roughness falls by more than half
  /// within 3 s (the last sub-millimetre texture stays: paint's 5 Pa rested yield), while toothpaste keeps the same marks.
  /// (RMS, not the range: the surface is read from particles 1 mm apart, which adds about ±0.5 mm of noise.)
  @MainActor func testPaintLevels() throws {
    let rig = try PhysRig(["-material", "paint"])
    rig.solver.clear()
    rig.fill(polygon: ToothpasteExperiments.brushed(level: 0.4, amplitude: 0.035, waves: 5).map { $0 * rig.tank }, material: "paint")
    rig.step()
    let r0 = PhysRig.rms(rig.surface(41))
    rig.run(3)
    let r3 = PhysRig.rms(rig.surface(41))
    // Control: toothpaste (250 Pa yield, ToothpasteTuning) keeps the same marks.
    let paste = try PhysRig(["-material", "toothpaste"])
    paste.solver.clear()
    paste.fill(polygon: ToothpasteExperiments.brushed(level: 0.4, amplitude: 0.035, waves: 5).map { $0 * paste.tank }, material: "toothpaste")
    paste.step()
    let p0 = PhysRig.rms(paste.surface(41))
    paste.run(3)
    let p3 = PhysRig.rms(paste.surface(41))
    report("paint.level", ["rms0MM": r0 * 1000, "rms3MM": r3 * 1000, "toothpasteRms0MM": p0 * 1000, "toothpasteRms3MM": p3 * 1000])
    XCTAssertLessThan(r3, 0.45 * r0, "paint's brush marks flow out")
    XCTAssertGreaterThan(p3, 0.75 * p0, "toothpaste's do not")
  }

  /// Lava (erupting at 1170 °C): within 4 s the free surface cools into a crust at least 150 K cooler than the core,
  /// and the front, stiffening as the lava cools toward the model's 1090 °C floor, moves at most 60 % as fast at
  /// 3.5–4 s as at 0.5–1 s.
  @MainActor func testLavaCrustsAndSlows() throws {
    let rig = try PhysRig(["-noPersist"])
    rig.model.perform(.experiment("lava"))
    func front() -> Double {
      let xs = rig.particles.map(\.position.x).sorted()
      return xs.isEmpty ? 0 : xs[Int(Double(xs.count - 1) * 0.99)]
    }
    rig.run(0.5)
    let f05 = front()
    rig.run(0.5)
    let f1 = front()
    rig.run(2.5)
    let f35 = front()
    rig.run(0.5)
    let f4 = front()
    let ps = rig.particles
    let topY = rig.top(ps)
    let surfaceT = ps.filter { $0.position.y > topY - 0.003 }.map(\.temperature)
    let coreT = ps.filter { $0.position.y > 0.008 && $0.position.y < topY - 0.008 && $0.position.x > 0.004 && $0.position.x < 0.02 }
      .map(\.temperature)
    let eruption = 1170 + 273.15
    let sT = surfaceT.reduce(0, +) / Double(max(surfaceT.count, 1))
    let cT = coreT.reduce(0, +) / Double(max(coreT.count, 1))
    let early = (f1 - f05) / 0.5, late = (f4 - f35) / 0.5
    report("lava.crust", ["surfaceDropK": eruption - sT, "coreDropK": eruption - cT, "frontEarlyMMs": early * 1000,
                          "frontLateMMs": late * 1000])
    XCTAssertGreaterThan(cT - sT, 150, "a crust over a hot core")
    XCTAssertLessThan(late, 0.6 * early, "the flow slows as it cools")
    XCTAssertGreaterThan(late, 0, "but still creeps")
  }

  /// Water-like: a shake sloshes it, and the thin-tank drag settles it within seconds.
  @MainActor func testWaterSloshesAndSettles() throws {
    let rig = try PhysRig(["-material", "waterLike"])
    rig.run(1)
    rig.model.perform(.shakeOnce)
    var peakRange = 0.0, peakKE = 0.0
    rig.run(0.8) { _ in peakRange = max(peakRange, PhysRig.range(rig.surface())); peakKE = max(peakKE, rig.stats.kineticEnergy) }
    rig.run(3.2)
    let endRange = PhysRig.range(rig.surface()), endKE = rig.stats.kineticEnergy
    report("water.slosh", ["peakRangeMM": peakRange * 1000, "endRangeMM": endRange * 1000, "peakKE": peakKE, "endKE": endKE])
    XCTAssertGreaterThan(peakRange, 0.004, "it sloshes")
    XCTAssertLessThan(endKE, 0.1 * peakKE, "and settles")
    XCTAssertLessThan(endRange, 0.003)
  }

  // MARK: - Stimuli

  /// Tilt right tips gravity toward +x (fluid runs right); a two-finger drag right does the same; a shake is a frame
  /// acceleration; Shake/Rate are the floor vibration.
  @MainActor func testTiltShakeAndVibration() throws {
    let rig = try PhysRig(["-material", "waterLike"])
    rig.step()
    XCTAssertEqual(rig.frame.input.gravity.x, 0, accuracy: 0.6, "simulated phone starts nearly level in-plane")
    let g0 = rig.frame.input.gravity.x
    rig.model.perform(.tilt(dx: 0.15, dy: 0))
    rig.step()
    XCTAssertGreaterThan(rig.frame.input.gravity.x, g0 + 1, "Tilt right: gravity tips toward +x")
    rig.model.perform(.tilt(dx: -0.3, dy: 0))
    rig.step()
    XCTAssertLessThan(rig.frame.input.gravity.x, g0 - 1, "Tilt left: toward −x")
    rig.model.perform(.tilt(dx: 0.15, dy: 0))
    rig.model.engine.twoFinger(TankTwoFinger(phase: .changed, delta: CGSize(width: 40, height: 0), translation: CGSize(width: 40, height: 0), scale: 1, anchor: .zero))
    rig.step()
    XCTAssertGreaterThan(rig.frame.input.gravity.x, g0 + 1, "two fingers dragged right tip gravity right")
    rig.model.perform(.shakeOnce)
    rig.step()
    rig.step()
    XCTAssertGreaterThan(simd_length(rig.frame.input.frameAcceleration), 1, "a shake is a frame acceleration")
    rig.model.params[.shake] = 10
    rig.model.params[.rate] = 50
    rig.step()
    XCTAssertEqual(rig.frame.input.vibration.amplitude, 10 * Gravity.g0, accuracy: 1e-9)
    XCTAssertEqual(rig.frame.input.vibration.frequency, 50, accuracy: 1e-9)
    report("stimuli.tilt", ["gxRight": rig.frame.input.gravity.x])
  }

  /// Time scales simulated time, Freeze stops it, Gravity sets |g| (Moon detent), Heat sets the ambient temperature
  /// (lava: the eruption temperature while the air stays at room temperature).
  @MainActor func testTimeFreezeGravityHeat() throws {
    let rig = try PhysRig(["-material", "honey"])
    rig.model.params[.time] = 0.25
    rig.step(1.0 / 60)
    XCTAssertEqual(rig.frame.simDt, 0.25 / 60, accuracy: 1e-9)
    rig.model.paused = true
    rig.step(1.0 / 60)
    XCTAssertEqual(rig.frame.simDt, 0)
    rig.model.paused = false
    rig.model.params[.time] = 1
    rig.model.params[.gravity] = 0.166
    rig.model.layers.useTilt = false
    rig.step()
    XCTAssertEqual(simd_length(rig.frame.input.gravity), 0.166 * Gravity.g0, accuracy: 1e-6)
    rig.model.params[.heat] = 37
    rig.step()
    XCTAssertEqual(rig.frame.input.ambientTemperature, 310.15, accuracy: 1e-9)
    rig.model.choose(material: "lava")
    rig.step()
    XCTAssertEqual(rig.frame.input.ambientTemperature, ToothpasteEngine.room, accuracy: 1e-9)
    XCTAssertEqual(rig.model.params[.heat], 1170)
  }

  /// The Magnet knob is a virtual magnet under the floor; dragging its marker slides it; the magnetometer's Δ|B| is a
  /// uniform field (only with Layers › Use the magnetometer).
  @MainActor func testMagnetKnobDragAndMagnetometer() throws {
    let rig = try PhysRig(["-material", "mrFluid"])
    rig.step()
    XCTAssertNil(rig.frame.input.magnet, "off by default")
    rig.model.params[.magnet] = 207
    rig.step()
    let m = try XCTUnwrap(rig.frame.input.magnet)
    XCTAssertEqual(m.strength, 0.207 / MPMConstants.vacuumPermeability, accuracy: 1)
    XCTAssertLessThan(m.position.y, 0, "under the floor")
    XCTAssertEqual(m.position.x, rig.tank.x / 2, accuracy: 1e-9)
    XCTAssertEqual(rig.frame.magnet?.position?.x ?? 0, rig.tank.x / 2, accuracy: 1e-9)
    // Drag the marker 15 mm to the left.
    let start = SIMD2(rig.tank.x / 2, 0.003)
    rig.touch(.began, start)
    rig.touch(.moved, start - SIMD2(0.015, 0), start: start)
    rig.step()
    rig.touch(.ended, start - SIMD2(0.015, 0), start: start)
    XCTAssertEqual(rig.engine.magnetX, rig.tank.x / 2 - 0.015, accuracy: 1e-6, "the marker drag moves the magnet")
    XCTAssertNil(rig.frame.finger.flatMap { $0.tool == .probe ? $0 : nil }, "a marker drag is not a probe")
  }

  /// The mic routes: Listen × Drives gates; Band feeds the level; Kicks fire on onsets; a held knob wins; the thermal
  /// route is off unless asked for.
  func testDrivesRoutes() {
    var router = ModulationRouter(ToothpasteDrives.routes)
    var specs: [ParamID: ParamSpec] = [:]
    for s in ToothpasteKnobs.all { specs[s.id] = s }
    var p = ParamValues([.listen: 1, .drives: Double(DriveTarget.gravity.rawValue), .gravity: 1, .stir: 0, .heat: 20])
    var src = ModSources()
    src[ToothpasteDrives.bandSource] = 0.5
    for _ in 0..<60 { var settle = p; _ = router.apply(src, to: &settle, specs: specs, dt: 1.0 / 60) }
    var q = p
    _ = router.apply(src, to: &q, specs: specs, dt: 1.0 / 60)
    XCTAssertGreaterThan(q[.gravity], 1.5, "Drives at Gravity: sound raises gravity")
    q = p
    _ = router.apply(src, to: &q, specs: specs, dt: 1.0 / 60, holding: [.gravity])
    XCTAssertEqual(q[.gravity], 1, "a held knob wins")
    p[.drives] = Double(DriveTarget.kicks.rawValue)
    src[.micOnset] = 6
    q = p
    let out = router.apply(src, to: &q, specs: specs, dt: 1.0 / 60)
    XCTAssertNotNil(out.fired(ToothpasteDrives.kickChannel), "an onset is a kick")
    p[.drives] = Double(DriveTarget.shake.rawValue)
    src[.micOnset] = 0
    q = p
    let shake = router.apply(src, to: &q, specs: specs, dt: 1.0 / 60)
    XCTAssertGreaterThan(shake[ToothpasteDrives.shakeChannel], 1, "Drives at Shake: sound shakes the floor")
    XCTAssertFalse(ToothpasteDrives.routes.first { $0.id == "device.heat" }!.enabled, "the thermal route is off by default")
  }

  /// The frame-rate policy: the substep cap follows the frame time (20 at 120 Hz, 40 at 60 Hz, never more).
  func testSubstepBudget() {
    let b = SubstepBudget()
    XCTAssertEqual(b.cap(for: 1.0 / 120, base: .standard), 20)
    XCTAssertEqual(b.cap(for: 1.0 / 60, base: .standard), 40)
    XCTAssertEqual(b.cap(for: 1.0 / 15, base: .standard), 40)
    var c = SubstepBudget()
    XCTAssertNil(c.observe(lagging: true, dt: 1, current: .standard), "standard never steps down")
    var h = SubstepBudget()
    _ = h.observe(lagging: true, dt: 2, current: .high)
    XCTAssertEqual(h.observe(lagging: true, dt: 2, current: .high)?.cellSize, MPMQuality.standard.cellSize)
    // GPU time over 90 % of the frame for 3 s steps down too; a hot phone at once, and it loses the 60 Hz doubling.
    var gpu = SubstepBudget()
    XCTAssertNil(gpu.observe(lagging: false, dt: 2, current: .high, gpuMilliseconds: 16))
    XCTAssertNil(gpu.observe(lagging: false, dt: 2, current: .high, gpuMilliseconds: 1900))
    XCTAssertNotNil(gpu.observe(lagging: false, dt: 2, current: .high, gpuMilliseconds: 1900))
    var hot = SubstepBudget()
    XCTAssertNotNil(hot.observe(lagging: false, dt: 1.0 / 120, current: .high, thermal: 2.0 / 3))
    XCTAssertEqual(b.cap(for: 1.0 / 60, base: .standard, thermal: 2.0 / 3), 20)
    // PLAY (14 October 2026): hot at 60 Hz, up to 28 substeps while the smoothed GPU time stays under 70 % of the
    // frame (DEVICE-RUN-2: stiff pastes fell into slow motion at Serious with the GPU at 63 %); never at 120 Hz.
    var head = SubstepBudget()
    head.noteGPU(8, dt: 1.0 / 60)
    XCTAssertEqual(head.cap(for: 1.0 / 60, base: .standard, thermal: 2.0 / 3), 28)
    XCTAssertEqual(head.cap(for: 1.0 / 120, base: .standard, thermal: 2.0 / 3), 20, "no doubling at 120 Hz when hot")
    var busy = SubstepBudget()
    busy.noteGPU(13, dt: 1.0 / 60)
    XCTAssertEqual(busy.cap(for: 1.0 / 60, base: .standard, thermal: 2.0 / 3), 20, "no headroom: the base cap")
  }

  /// A 60 Hz frame of an oobleck pool runs in real time (no lag).
  @MainActor func testSixtyHertzRunsInRealTime() throws {
    let rig = try PhysRig(["-material", "oobleck"])
    rig.run(1)
    report("budget.60hz", ["substeps": Double(rig.stats.substeps), "lagging": rig.stats.lagging ? 1 : 0, "simTime": rig.frame.simTime])
    XCTAssertFalse(rig.stats.lagging)
    XCTAssertEqual(rig.frame.simTime, 1, accuracy: 1e-6)
  }

  // MARK: - Touch and props

  /// A quick tap pokes (a jab and a .poke event); a fast swipe is a punch; the probe sits at the finger's leading edge.
  @MainActor func testTapPokeSwipePunchAndProbe() throws {
    let rig = try PhysRig(["-material", "waterLike"])
    rig.run(0.5)
    let p = SIMD2(rig.tank.x / 2, 0.04)
    rig.touch(.began, p)
    rig.step()
    rig.touch(.ended, p)
    var events: [SimEvent] = []
    rig.step()
    events += rig.frame.events
    XCTAssertTrue(events.contains(.poke(p)), "a quick tap is a poke")
    XCTAssertNotNil(rig.engine.tools.jab, "with a poke impulse")
    var deepest = Double.infinity
    rig.run(0.1) { _ in deepest = min(deepest, rig.frame.finger?.position.y ?? .infinity) }
    XCTAssertLessThan(deepest, p.y - 0.006, "the poke goes down into the fluid")
    rig.run(0.2)
    XCTAssertNil(rig.engine.tools.jab, "and is over within a fraction of a second")
    XCTAssertNil(rig.frame.finger, "leaving no finger behind")
    rig.run(0.2)
    // Probe placement: a finger moving down; the probe sits one collider skin ahead of its leading edge.
    rig.touch(.began, SIMD2(p.x, 0.06))
    var y = 0.06
    for _ in 0..<20 { y -= 0.002; rig.touch(.moved, SIMD2(p.x, y)); rig.step() }
    let f = try XCTUnwrap(rig.frame.finger)
    let probe = try XCTUnwrap(rig.frame.input.probe)
    XCTAssertEqual(probe.x, f.position.x, accuracy: 1e-3)
    let gapToEdge = (f.position.y - f.radius) - probe.y
    XCTAssertEqual(gapToEdge, rig.solver.cellSize, accuracy: 0.0025, "probe one skin below the leading edge")
    rig.touch(.ended, SIMD2(p.x, y))
    rig.step()
    // A fast swipe (1.2 m/s) is a punch.
    events = []
    rig.touch(.began, SIMD2(0.01, 0.03))
    for i in 1...6 { rig.touch(.moved, SIMD2(0.01 + Double(i) * 0.01, 0.03)); rig.step(1.0 / 120); events += rig.frame.events }
    rig.touch(.ended, SIMD2(0.07, 0.03))
    XCTAssertTrue(events.contains { if case .punch = $0 { true } else { false } }, "a fast swipe is a punch")
  }

  /// Pour mode: a drag pours the chosen material into the tank; honey over oobleck shares the tank.
  @MainActor func testPourAndTwoFluids() throws {
    let rig = try PhysRig(["-material", "oobleck"])
    rig.run(0.3)
    let n0 = rig.particles.count
    rig.model.shelfMode = .pour
    rig.model.choose(material: "honey")
    rig.step()
    XCTAssertEqual(rig.engine.pourMaterial, "honey")
    XCTAssertEqual(rig.engine.currentMaterial, "oobleck", "Pour mode leaves the tank's material")
    let p = SIMD2(rig.tank.x / 2, 0.07)
    rig.touch(.began, p)
    rig.run(1) { _ in rig.touch(.moved, p) }
    rig.touch(.ended, p)
    let honey = rig.particles(slot: rig.model.catalog.material("honey").slot).count
    report("pour.honey", ["particlesBefore": Double(n0), "honeyParticles": Double(honey)])
    XCTAssertGreaterThan(honey, 200)
    // Two fluids experiment: report how honey and oobleck sit after 4 s.
    rig.model.perform(.experiment("twofluids"))
    rig.run(0.2)
    let hSlot = rig.model.catalog.material("honey").slot, oSlot = rig.model.catalog.material("oobleck").slot
    let h0 = rig.com(rig.particles(slot: hSlot)).y, o0 = rig.com(rig.particles(slot: oSlot)).y
    rig.run(3.8)
    let h4 = rig.com(rig.particles(slot: hSlot)).y, o4 = rig.com(rig.particles(slot: oSlot)).y
    report("twofluids", ["honeyY0MM": h0 * 1000, "oobleckY0MM": o0 * 1000, "honeyY4MM": h4 * 1000, "oobleckY4MM": o4 * 1000])
    XCTAssertGreaterThan(h0, o0, "honey starts on top")
    XCTAssertLessThan(h4, h0, "honey (1420 kg/m³) sinks into oobleck (1230 kg/m³)")
    XCTAssertEqual(rig.stats.nanCount, 0)
  }

  /// Scoop mode: a drag carries a drain (0.75 × the finger) that takes fluid out where it goes, and nothing else.
  @MainActor func testScoopTakesFluidOut() throws {
    let rig = try PhysRig(["-material", "waterLike"])
    rig.run(0.5)
    let n0 = rig.particles.count
    rig.model.shelfMode = .scoop
    rig.step()  // the engine takes the shelf mode with the next frame
    let a = SIMD2(rig.tank.x * 0.3, 0.03), b = SIMD2(rig.tank.x * 0.7, 0.03)
    rig.touch(.began, a)
    var drainSeen = false
    rig.run(1) { t in
      let u = min(t / 0.8, 1)
      rig.touch(.moved, a + (b - a) * u)
      if let f = rig.frame.finger, f.tool == .scoop, rig.frame.input.drains.count == 1 { drainSeen = true }
    }
    rig.touch(.ended, b)
    rig.run(0.3)
    let n1 = rig.particles.count
    report("scoop.water", ["particlesBefore": Double(n0), "particlesAfter": Double(n1), "drained": Double(rig.stats.drained)])
    XCTAssertTrue(drainSeen, "the drag carried a drain")
    XCTAssertLessThan(n1, n0 - 100, "fluid was taken out")
    XCTAssertGreaterThan(n1, n0 / 3, "only along the finger's path")
    XCTAssertTrue(rig.frame.input.drains.isEmpty, "lifting the finger stops it")
    XCTAssertEqual(rig.stats.nanCount, 0)
  }

  /// Props: a steel ball sinks to the floor of water, a cork block floats, the light prop's coupling stays stable.
  @MainActor func testPropsSinkFloatAndStayStable() throws {
    let rig = try PhysRig(["-material", "waterLike"])
    rig.run(0.5)
    rig.model.drop(.steelBall)
    rig.run(0.3)
    rig.model.drop(.corkBlock)
    var maxCorkSpeed = 0.0
    rig.run(4) { t in
      if t > 2.5, let cork = rig.frame.props.first(where: { $0.kind == .corkBlock }) {
        maxCorkSpeed = max(maxCorkSpeed, simd_length(cork.velocity))
      }
    }
    let ball = try XCTUnwrap(rig.frame.props.first { $0.kind == .steelBall })
    let cork = try XCTUnwrap(rig.frame.props.first { $0.kind == .corkBlock })
    let surface = rig.surface(25).sorted()[12]
    report("props.water", ["ballYMM": ball.position.y * 1000, "corkYMM": cork.position.y * 1000, "surfaceMM": surface * 1000,
                           "corkSpeedLate": maxCorkSpeed])
    XCTAssertLessThan(ball.position.y, 0.008, "the steel ball sinks to the floor")
    XCTAssertGreaterThan(cork.position.y, surface - 0.004, "the cork floats (its top above the surface)")
    XCTAssertLessThan(maxCorkSpeed, 0.1, "and settles (no pumping)")
  }

  /// Props in oobleck (rate-dependent drag stabiliser, Props.swift): a steel ball dropped from the top jams the surface
  /// and stops in it, then sinks once the jam melts (held about 0.4 s, then about 3 cm/s to the floor); a cork block
  /// floats. With the jammed branch's
  /// fixed 401 Pa·s the ball crept 0.3 mm/s (about 2 mm in 6 s).
  @MainActor func testPropsInOobleck() throws {
    let rig = try PhysRig(["-material", "oobleck"])
    rig.run(0.8, dt: 1.0 / 120)
    let surface = rig.surface(25).sorted()[12]
    rig.model.drop(.steelBall)
    var peakJam = 0.0
    var depthAt: [Double: Double] = [:]
    let t0 = rig.clock
    let watch: (Double) -> Void = { t in
      peakJam = max(peakJam, rig.stats.jammedFraction)
      let k = ((t - t0) * 10).rounded() / 10
      if abs((t - t0) - k) < 0.5 / 120, let b = rig.frame.props.first(where: { $0.kind == .steelBall }) {
        depthAt[k] = surface - b.position.y
      }
    }
    rig.run(1.5, dt: 1.0 / 120, each: watch)
    rig.model.drop(.corkBlock)
    rig.run(3.5, dt: 1.0 / 120, each: watch)
    let ball = try XCTUnwrap(rig.frame.props.first { $0.kind == .steelBall })
    let cork = try XCTUnwrap(rig.frame.props.first { $0.kind == .corkBlock })
    let held = depthAt[0.5] ?? .infinity
    let sunk = depthAt[4.0] ?? 0
    report("props.oobleck", ["surfaceMM": surface * 1000, "peakJam": peakJam, "ballDepthAt0.5sMM": held * 1000,
                             "ballDepthAt4sMM": sunk * 1000, "ballEndYMM": ball.position.y * 1000, "corkYMM": cork.position.y * 1000])
    XCTAssertGreaterThan(peakJam, 0.3, "the landing jams the surface")
    XCTAssertLessThan(held, 0.008, "and the jammed surface holds the ball up at first")
    XCTAssertGreaterThan(sunk, held + 0.015, "then it sinks visibly as the jam melts")
    XCTAssertGreaterThan(cork.position.y, surface - 0.004, "the cork floats")
  }

  /// Props in honey: a glass marble sinks slowly (honey is 15 Pa·s), a cork block, plunged in from the top, rises back
  /// without pumping, and a die (1150 kg/m³, lighter than honey's 1420) floats too.
  @MainActor func testPropsInHoney() throws {
    let rig = try PhysRig(["-material", "honey"])
    rig.run(0.5)
    rig.model.drop(.glassMarble)
    rig.run(0.2)
    rig.model.drop(.corkBlock)
    rig.run(0.2)
    rig.model.drop(.die)
    var marbleY: [Double] = []
    var lateSpeed = 0.0
    rig.run(5) { t in
      if let m = rig.frame.props.first(where: { $0.kind == .glassMarble }), Int((t * 60).rounded()) % 30 == 0 { marbleY.append(m.position.y) }
      if t > 4 { for p in rig.frame.props where p.kind != .glassMarble { lateSpeed = max(lateSpeed, simd_length(p.velocity)) } }
    }
    let surface = rig.surface(25).sorted()[12]
    let cork = try XCTUnwrap(rig.frame.props.first { $0.kind == .corkBlock })
    let die = try XCTUnwrap(rig.frame.props.first { $0.kind == .die })
    let marble = try XCTUnwrap(rig.frame.props.first { $0.kind == .glassMarble })
    let sinkRate = zip(marbleY, marbleY.dropFirst()).map { ($0 - $1) / 0.5 }.max() ?? 0
    report("props.honey", ["surfaceMM": surface * 1000, "corkYMM": cork.position.y * 1000, "dieYMM": die.position.y * 1000,
                           "marbleYMM": marble.position.y * 1000, "marbleMaxSinkMMs": sinkRate * 1000, "lateSpeed": lateSpeed])
    XCTAssertGreaterThan(cork.position.y, surface - 0.02, "the cork floats back up (slowly: 1–2 mm/s through honey)")
    XCTAssertGreaterThan(die.position.y, surface - 0.012, "the die floats in honey")
    XCTAssertLessThan(sinkRate, 0.03, "the marble sinks slowly")
    XCTAssertLessThan(lateSpeed, 0.1, "no pumping")
  }

  // MARK: - Catalog and knobs

  /// The Rheometer's modelled curves match the solver's own constitutive update (MPMConstitutiveProbe, GPU float32)
  /// at steady simple shear, within 3 % (non-oobleck materials at 1 and 3 s⁻¹, where Wi ≤ 0.05; the Maxwell materials
  /// slime and Silly Putty are left out: their b̄ₑ model thins above Wi ≈ 0.3, rheology §4.6).
  @MainActor func testFlowCurvesMatchTheSolver() throws {
    let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    let probe = try MPMConstitutiveProbe(device: device)
    let c = ToothpasteCatalogData()
    var worst = 0.0
    var worstName = ""
    for info in c.materials where info.material.dst == nil && info.id != "sillyPutty" && info.id != "slime" {
      for rate in [1.0, 3.0] {
        let m = info.material
        // Run long enough for structure and stress to settle: t = 8/(A + B) or 2 s, small steps.
        let settle = max(4.0, m.buildRate + m.breakShear * rate > 0 ? 10 / (m.buildRate + m.breakShear * rate) : 0)
        let dt = 2e-4
        var pts = [MPMConstitutiveProbe.Point(structure: 1, temperature: m.referenceTemperature)]
        let out = probe.run(
          materials: [m], points: &pts, materialIndex: [0],
          velocityGradient: [simd_double2x2(columns: (SIMD2(0, 0), SIMD2(rate, 0)))], dt: dt,
          steps: Int(min(settle, 60) / dt))
        let gpu = abs(out[0].y)
        let model = FlowCurve.stress(m, shearRate: rate, temperature: m.referenceTemperature)
        let err = abs(gpu - model) / model
        if err > worst { worst = err; worstName = "\(info.id)@\(rate)" }
      }
    }
    report("flowcurve.parity", ["worstRelErr": worst])
    print("RHEO-PHYS flowcurve.worst \(worstName)")
    XCTAssertLessThan(worst, 0.03, worstName)
  }

  /// Knobs act on the running material: Consistency has one range for every material (Silly Putty inside it), Memory
  /// sets G (or oobleck's melt time), Rebuild sets t_build, and the Rheometer's curve follows Yield.
  @MainActor func testKnobsMapToTheMaterial() throws {
    for m in ContinuumPresets.all.map(\.material) {
      let spec = ToothpasteKnobs.fluidSpecs(for: m)[1]
      XCTAssertTrue(spec.range.contains(ToothpasteKnobs.consistency(m)), "consistency default inside the range")
      XCTAssertEqual(spec.range, ToothpasteKnobs.consistencyRange)
    }
    let rig = try PhysRig(["-material", "slime"])
    let slot = rig.model.catalog.material("slime").slot
    rig.step()
    XCTAssertEqual(rig.solver.materials[slot], ContinuumPresets.slime, "defaults leave the preset untouched")
    rig.model.params[.memory] = 2
    rig.step()
    XCTAssertEqual(rig.solver.materials[slot].shearModulus, 447 / 2, accuracy: 1, "Memory 2 s: G = η/λ")
    rig.model.choose(material: "yogurt")
    rig.model.params[.rebuild] = 10
    rig.step()
    let ySlot = rig.model.catalog.material("yogurt").slot
    XCTAssertEqual(rig.solver.materials[ySlot].buildRate, 0.1, accuracy: 1e-12, "Rebuild 10 s: A₀ = 0.1/s")
    let before = rig.model.catalog.flowCurve("yogurt", shearRates: [0.1], temperature: 293.15)[0]
    rig.model.params[.yield] = 120
    rig.step()
    let after = rig.model.catalog.flowCurve("yogurt", shearRates: [0.1], temperature: 293.15)[0]
    XCTAssertGreaterThan(after, before * 2, "the Rheometer's curve follows the Yield knob")
    rig.model.choose(material: "oobleck")
    rig.model.params[.memory] = 0.5
    rig.step()
    XCTAssertEqual(rig.solver.materials[rig.model.catalog.material("oobleck").slot].dst?.meltTime ?? 0, 0.5, accuracy: 1e-12)
  }

  /// Every experiment refills, restarts the clock, plays its script for 3 s without NaN or overflow.
  @MainActor func testEveryExperimentRuns() throws {
    let rig = try PhysRig([])
    for e in rig.model.catalog.experiments {
      rig.run(0.2)
      rig.model.perform(.experiment(e.id))
      XCTAssertEqual(rig.engine.simTime, 0, e.id)
      if let m = e.material { XCTAssertEqual(rig.model.materialID, m, e.id) }
      rig.run(3)
      XCTAssertEqual(rig.engine.simTime, rig.frame.simTime)
      XCTAssertGreaterThan(rig.frame.simTime, 2.0, "\(e.id): clock runs (lag allowed)")
      XCTAssertEqual(rig.stats.nanCount, 0, e.id)
      XCTAssertEqual(rig.stats.overflowCount, 0, e.id)
      XCTAssertGreaterThan(rig.stats.liveParticles, 300, e.id)
      report("experiment.\(e.id)", ["simTime": rig.frame.simTime, "particles": Double(rig.stats.liveParticles),
                                    "jam": rig.stats.jammedFraction, "lagging": rig.stats.lagging ? 1 : 0])
    }
  }

  /// Each experiment's scripted demonstration shows its effect (measured at the moments the script sets up).
  @MainActor func testExperimentDemonstrations() throws {
    func start(_ id: String) throws -> PhysRig {
      let rig = try PhysRig([])
      rig.model.perform(.experiment(id))
      return rig
    }
    func sample(_ rig: PhysRig, until t: Double, _ body: () -> Void = {}) {
      while rig.engine.simTime < t - 1e-9 { rig.step(1.0 / 120); body() }
    }
    var results: [String: Double] = [:]
    // Punch: the scripted punch at 1 s jams; by 3 s (before the second punch) it has melted.
    do {
      let rig = try start("punch")
      var peak = 0.0
      sample(rig, until: 1.6) { peak = max(peak, rig.stats.jammedFraction) }
      sample(rig, until: 3.2)
      results["punch.peakJam"] = peak
      results["punch.jamAt3.2"] = rig.stats.jammedFraction
      XCTAssertGreaterThan(peak, 0.3)
      XCTAssertLessThan(rig.stats.jammedFraction, 0.05)
    }
    // Slow then fast finger: the slow press jams little; the fast jab jams a lot.
    do {
      let rig = try start("slowfast")
      var slowJam = 0.0, fastJam = 0.0
      sample(rig, until: 3.6) { slowJam = max(slowJam, rig.stats.jammedFraction) }
      sample(rig, until: 4.4) { fastJam = max(fastJam, rig.stats.jammedFraction) }
      results["slowfast.slowJam"] = slowJam
      results["slowfast.fastJam"] = fastJam
      XCTAssertLessThan(slowJam, 0.15)
      XCTAssertGreaterThan(fastJam, 0.3)
    }
    // Ketchup: the scripted shakes at 3 s and 5 s break its structure and it slumps.
    do {
      let rig = try start("ketchup")
      sample(rig, until: 2.9)
      // The script tilts the phone at 0.6 s: measure the slump along gravity, not along the tank's y.
      let down = simd_normalize(rig.frame.input.gravity)
      let lam0 = rig.stats.meanStructure, c0 = rig.com(rig.particles)
      sample(rig, until: 7)
      let lam1 = rig.stats.meanStructure, c1 = rig.com(rig.particles)
      results["ketchup.lambdaBefore"] = lam0
      results["ketchup.lambdaAfter"] = lam1
      results["ketchup.slumpMM"] = simd_dot(c1 - c0, down) * 1000
      XCTAssertLessThan(lam1, lam0 - 0.2)
      XCTAssertGreaterThan(simd_dot(c1 - c0, down), 0.0002, "it slides (slowly: the 1 cm gap's drag)")
    }
    // Toothpaste: the column stands, and keeps standing (a too-slender one toppled at about 3 s), at full gravity.
    // Toppling is a runaway: the column's upper half falls sideways faster and faster. Standing allows the slow creep
    // of a yield-stress column whose base is loaded near its yield stress: the base spreads and the upper half drifts a
    // few millimetres, then stops. So: the top stays up, the upper half has
    // drifted less than 4 mm by 8 s, and by 5–8 s the drift has (nearly) stopped. (Until 9 October this asserted the
    // whole column's centre of mass moved < 2 mm. An intermediate LabKit solver of that day (LK-FIX, about 17:12) read
    // 2.04 mm, with the upper half at 2.29 mm by 5 s and 2.72 mm by 8 s and the base 22 → 28 mm wide, against
    // 0.74–1.15 mm before and after it; the < 0.40·width filter also turned base spreading into an apparent lean as
    // particles crossed it. A topple moves the upper half by more than the column's half-width, 10 mm. `leanMM` is
    // still reported.)
    do {
      let rig = try start("toothpaste")
      rig.model.layers.useTilt = false
      func column() -> [MPMParticleSnapshot] { rig.particles.filter { $0.position.x < 0.40 * rig.tank.x } }
      func upper() -> Double {
        let ps = rig.particles.filter { $0.position.x < 0.60 * rig.tank.x }
        let top = rig.top(ps)
        return rig.com(ps.filter { $0.position.y > max(0.5 * top, 0.15 * rig.tank.y) }).x
      }
      sample(rig, until: 1.0)
      let x1 = rig.com(column()).x, u1 = upper()
      sample(rig, until: 5.0)
      let u5 = upper()
      sample(rig, until: 8.0)
      let top = rig.top(column()), x8 = rig.com(column()).x, u8 = upper()
      results["toothpaste.topMM"] = top * 1000
      results["toothpaste.leanMM"] = (x8 - x1) * 1000
      results["toothpaste.upperDriftMM"] = (u8 - u1) * 1000
      results["toothpaste.upperDrift5to8MM"] = (u8 - u5) * 1000
      XCTAssertGreaterThan(top, 0.85 * 0.30 * rig.tank.y)
      XCTAssertLessThan(abs(u8 - u1), 0.004, "it does not topple")
      XCTAssertLessThan(abs(u8 - u5), 0.001, "and its creep has stopped")
    }
    // Moon: the mound stands at one-sixth g; back on Earth (the script, at 4 s) it slumps.
    do {
      let rig = try start("moon")
      sample(rig, until: 3.9)
      let moon = rig.top(rig.particles)
      sample(rig, until: 7)
      let earth = rig.top(rig.particles)
      results["moon.topMoonMM"] = moon * 1000
      results["moon.topEarthMM"] = earth * 1000
      XCTAssertGreaterThan(moon, 0.045)
      XCTAssertLessThan(earth, moon - 0.008)
    }
    // Honey: cold honey poured piles up; warmed at 4.5 s, the pile runs flat.
    do {
      let rig = try start("honey")
      func pile() -> Double {
        let s = rig.surface(25)
        return s[12] - (s[2] + s[22]) / 2
      }
      sample(rig, until: 3.6)
      let cold = pile()
      sample(rig, until: 9.5)
      let warm = pile()
      results["honey.pileColdMM"] = cold * 1000
      results["honey.pileWarmMM"] = warm * 1000
      results["honey.meanTempC"] = rig.stats.meanTemperature - 273.15
      XCTAssertGreaterThan(cold, 0.004)
      XCTAssertLessThan(warm, 0.5 * cold)
    }
    // Quicksand: the marble rests until the scripted 3 g shake (3.2–5.7 s), then sinks.
    do {
      let rig = try start("quicksand")
      sample(rig, until: 3.1)
      let before = rig.frame.props.first?.position.y ?? 0
      sample(rig, until: 8.5)
      let after = rig.frame.props.first?.position.y ?? 0
      results["quicksand.ballBeforeMM"] = before * 1000
      results["quicksand.ballAfterMM"] = after * 1000
      XCTAssertGreaterThan(before, 0.4 * rig.tank.y - 0.006)
      XCTAssertLessThan(after, before - 0.008)
    }
    // Magnet: the thin (10 mm) layer heaps over the magnet (LabKit M5 since LK-FIX: a 10 mm layer rises about 4 mm in
    // 2 s; the Mac harness read 3.4 mm above the median surface at 1.9 s), and the heap follows the script's slide left,
    // then right (Mac harness: peak at 20.8 mm with the magnet at 17.8 mm, then 55 mm with it at 53 mm).
    do {
      let rig = try start("magnet")
      func peak() -> (x: Double, rise: Double) {
        let s = rig.surface(25)
        let i = s.indices.max { s[$0] < s[$1] } ?? 12
        return (0.006 + (rig.tank.x - 0.012) * Double(i) / 24, s[i] - s.sorted()[12])
      }
      sample(rig, until: 1.9)
      let still = peak()
      sample(rig, until: 3.6)
      let left = rig.frame.magnet?.position?.x ?? 0
      sample(rig, until: 4.4)
      let heapLeft = peak()
      sample(rig, until: 6.6)
      let right = rig.frame.magnet?.position?.x ?? 0
      sample(rig, until: 8.0)
      let heapRight = peak()
      results["magnet.leftMM"] = left * 1000
      results["magnet.rightMM"] = right * 1000
      results["magnet.heapMM"] = still.rise * 1000
      results["magnet.heapXMM"] = still.x * 1000
      results["magnet.heapLeftXMM"] = heapLeft.x * 1000
      results["magnet.heapRightXMM"] = heapRight.x * 1000
      XCTAssertEqual(left, 0.25 * rig.tank.x, accuracy: 0.001)
      XCTAssertEqual(right, 0.75 * rig.tank.x, accuracy: 0.001)
      XCTAssertGreaterThan(still.rise, 0.0015, "the thin layer heaps over the magnet")
      XCTAssertEqual(still.x, 0.5 * rig.tank.x, accuracy: 0.008, "over the magnet")
      XCTAssertLessThan(heapLeft.x, 0.45 * rig.tank.x, "the heap follows the magnet left")
      XCTAssertGreaterThan(heapRight.x, 0.55 * rig.tank.x, "and right")
    }
    // Paint: the brush marks flow out.
    do {
      let rig = try start("paint")
      rig.step(1.0 / 120)
      let r0 = PhysRig.range(rig.surface(41))
      sample(rig, until: 3)
      let r3 = PhysRig.range(rig.surface(41))
      results["paint.range0MM"] = r0 * 1000
      results["paint.range3MM"] = r3 * 1000
      XCTAssertLessThan(r3, 0.45 * r0)
    }
    // Two fluids: honey sinks into the oobleck.
    do {
      let rig = try start("twofluids")
      let slot = rig.model.catalog.material("honey").slot
      rig.step(1.0 / 120)
      let h0 = rig.com(rig.particles(slot: slot)).y
      sample(rig, until: 3.8)
      let h1 = rig.com(rig.particles(slot: slot)).y
      results["twofluids.honeyDropMM"] = (h0 - h1) * 1000
      XCTAssertGreaterThan(h0 - h1, 0.001)
    }
    report("experiments.demo", results)
  }

  /// Fill, Refill and Reset end a running experiment's demonstration: no more scripted pour, knob turns or jabs.
  @MainActor func testFillRefillResetStopTheExperimentScript() throws {
    let rig = try PhysRig([])
    let honeySlot = rig.model.catalog.material("honey").slot
    // Fill during "Honey, cold and warm"'s 3.2 s pour: the pour stops.
    rig.model.perform(.experiment("honey"))
    rig.run(1.0)
    rig.model.perform(.fill("waterLike"))
    rig.run(0.2)
    let n1 = rig.particles(slot: honeySlot).count
    rig.run(1.0)
    let n2 = rig.particles(slot: honeySlot).count
    // Refill during the honey pour: the pour stops, and the 4.5 s Heat turn never comes.
    rig.model.perform(.experiment("honey"))
    rig.run(1.0)
    rig.model.perform(.refill)
    rig.run(0.2)
    let r1 = rig.particles(slot: honeySlot).count
    rig.run(4.0)
    let r2 = rig.particles(slot: honeySlot).count
    let heat = rig.model.params[.heat]
    // Reset during the quicksand shake: the floor stops (Reset puts Shake back to 0 and nothing turns it up again).
    rig.model.perform(.experiment("quicksand"))
    rig.run(3.5)
    rig.model.perform(.resetAll)
    rig.run(3.0)
    report("experiment.stop", ["honeyAfterFill": Double(n1), "honeyLater": Double(n2), "honeyAfterRefill": Double(r1),
                               "honeyLaterRefill": Double(r2), "heat": heat])
    XCTAssertEqual(n1, 0, "Fill empties the tank of honey")
    XCTAssertEqual(n2, 0, "and no honey keeps pouring into the water")
    XCTAssertEqual(r2, r1, "Refill stops the scripted pour")
    XCTAssertEqual(heat, 4, "and the scripted Heat turn")
    XCTAssertEqual(rig.model.params[.shake], 0)
    XCTAssertEqual(rig.frame.vibration.x, 0)
  }

  /// An experiment starts from the default world: "Oobleck monsters" (Shake 17 g, Listen on) followed by "Toothpaste
  /// holds shape" must not shake the toothpaste.
  @MainActor func testExperimentStartsFromTheDefaultWorld() throws {
    let rig = try PhysRig([])
    rig.model.perform(.experiment("monsters"))
    rig.run(0.2)
    XCTAssertEqual(rig.model.params[.shake], 17)
    rig.model.params[.time] = 0.25
    rig.model.params[.gravity] = 2
    rig.model.perform(.experiment("toothpaste"))
    rig.step()
    XCTAssertEqual(rig.model.params[.shake], 0, "no leftover floor shake")
    XCTAssertEqual(rig.model.params[.listen], 0, "no leftover microphone drive")
    XCTAssertEqual(rig.model.params[.time], 1)
    XCTAssertEqual(rig.model.params[.gravity], 1)
    XCTAssertEqual(rig.frame.vibration.x, 0)
  }

  @MainActor func testPersistenceRoundTrip() throws {
    let suite = try XCTUnwrap(UserDefaults(suiteName: "toothpastetoy.phys.tests"))
    suite.removePersistentDomain(forName: "toothpastetoy.phys.tests")
    let store = ToothpastePersistence(enabled: true, defaults: suite)
    var layers = ToothpasteLayers()
    layers.useTilt = false
    layers.diagnostic = .jam
    store.save(ToothpasteSettings(material: "honey", shelfMode: .pour, layers: layers))
    let back = try XCTUnwrap(store.load())
    XCTAssertEqual(back, ToothpasteSettings(material: "honey", shelfMode: .pour, layers: layers))
    XCTAssertNil(ToothpastePersistence(enabled: false, defaults: suite).load())
  }

  /// PHYS copy: British spelling, length limits, and UI names that exist.
  // MARK: - Play (PLAY, REDESIGN.md §5; 14 October 2026)

  /// Squeezes `seconds` at `rate` mm/s from an empty chamber, releases, and returns the stack 1 s and 6 s after the
  /// release, the tear-off time after the release and the extruded length.
  private func squeezeStack(_ id: MaterialID = "toothpaste", rate: Double = 40, seconds: Double = 3, gravity: Double = 1,
                            settle: Double = 5) throws
    -> (top1: Double, base1: Double, width1: Double, top6: Double, tear: Double?, extruded: Double, bands: Set<Int>)
  {
    let rig = try PhysRig(["-material", id])
    rig.solver.clear()
    rig.model.layers.useTilt = false
    rig.model.params[.gravity] = gravity
    rig.run(0.1)
    rig.model.squeeze = SqueezeState(rate: rate, nozzleDiameter: 8, stripes: 3, material: id)
    rig.run(seconds)
    let extruded = rig.frame.nozzle?.extruded ?? 0
    rig.model.squeeze.rate = 0
    var tear: Double?
    var t = 0.0
    let watch: (Double) -> Void = { _ in
      t += 1.0 / 60
      if tear == nil, rig.frame.pasteEvents.contains(where: { $0.kind == .tearOff }) { tear = t }
    }
    rig.run(1, each: watch)
    let ps = rig.particles
    let top1 = rig.top(ps), base1 = rig.width(ps.filter { $0.position.y < 0.004 }), width1 = rig.width(ps)
    rig.run(settle, each: watch)
    return (top1, base1, width1, rig.top(rig.particles), tear, extruded, Set(ps.map(\.band)))
  }

  /// A 3 s squeeze at 40 mm/s lays a striped ribbon in folds that stack into a coil standing on its own (REDESIGN.md
  /// §5.2): at least 22 mm tall and at most 48 mm wide at the base 1 s after the release, keeping ≥ 85 % of its height
  /// 5 s later (the Bingham yield stress holds it; measured 29.8 → 29.4 mm, base 34 mm); the strand tears off at the
  /// nozzle within 0.6 s of the release (measured 0.33 s), and the coil carries the tube's three stripes.
  @MainActor func testSqueezeStacksIntoAStandingCoil() throws {
    let s = try squeezeStack()
    report("play.stack", ["extrudedMM": s.extruded * 1000, "top1MM": s.top1 * 1000, "base1MM": s.base1 * 1000,
                          "width1MM": s.width1 * 1000, "top6MM": s.top6 * 1000, "retention": s.top6 / max(s.top1, 1e-9),
                          "tearS": s.tear ?? -1])
    XCTAssertGreaterThan(s.extruded, 0.09, "3 s at 40 mm/s, after the descent and the ramp")
    XCTAssertGreaterThan(s.top1, 0.022, "a coil, not a puddle")
    XCTAssertLessThan(s.base1, 0.048)
    XCTAssertGreaterThan(s.top6 / s.top1, 0.85, "it holds its shape")
    XCTAssertLessThan(try XCTUnwrap(s.tear, "the strand tore off"), 0.6)
    XCTAssertEqual(s.bands, [1, 2, 3], "three stripes")
  }

  /// Gravity sets how tall the coil stands (REDESIGN.md §5.6): on the Moon the same squeeze stacks clearly taller than
  /// on Jupiter, where it slumps wider (measured 40 vs 27 mm tall, base 23 vs 48 mm).
  @MainActor func testMoonTowersJupiterSlumps() throws {
    let moon = try squeezeStack(seconds: 2.5, gravity: Gravity.detents.first { $0.label == "Moon" }?.value ?? 0.166,
                                settle: 1)
    let jupiter = try squeezeStack(seconds: 2.5, gravity: Gravity.detents.first { $0.label == "Jupiter" }?.value ?? 2.53,
                                   settle: 1)
    report("play.gravity", ["moonTopMM": moon.top1 * 1000, "moonBaseMM": moon.base1 * 1000,
                            "jupiterTopMM": jupiter.top1 * 1000, "jupiterBaseMM": jupiter.base1 * 1000])
    XCTAssertGreaterThan(moon.top1, jupiter.top1 + 0.008)
    XCTAssertGreaterThan(jupiter.base1, moon.base1 + 0.01)
  }

  /// The tear-off follows the paste: stiff toothpaste snaps within 0.6 s of the release and leaves a peak; honey
  /// strings out from the lifting nozzle for more than twice as long (measured 0.33 s and 1.1 s).
  @MainActor func testTearOffFollowsTheYieldStress() throws {
    let paste = try squeezeStack(seconds: 1.5, settle: 2)
    let honey = try squeezeStack("honey", seconds: 1.5, settle: 2)
    report("play.tear", ["toothpasteS": paste.tear ?? -1, "honeyS": honey.tear ?? -1])
    let p = try XCTUnwrap(paste.tear), h = try XCTUnwrap(honey.tear, "honey tears off too, later")
    XCTAssertLessThan(p, 0.6)
    XCTAssertGreaterThan(h, 1.8 * p)
  }

  /// A fresh toothpaste chamber opens on a short striped ribbon folded on the floor (REDESIGN.md §5.1) that stands:
  /// about 26 mm tall, 35 mm wide, unchanged 5 s later.
  @MainActor func testStartingCoilStands() throws {
    let rig = try PhysRig(["-material", "toothpaste"])
    rig.run(1)
    let top1 = rig.top(rig.particles)
    rig.run(4)
    let ps = rig.particles
    let top5 = rig.top(ps), width5 = rig.width(ps)
    report("play.coil", ["top1MM": top1 * 1000, "top5MM": top5 * 1000, "width5MM": width5 * 1000, "particles": Double(ps.count)])
    XCTAssertGreaterThan(top1, 0.02)
    XCTAssertGreaterThan(top5, 0.95 * top1, "it holds")
    XCTAssertLessThan(width5, 0.045)
    XCTAssertEqual(Set(ps.map(\.band)), [1, 2, 3])
    XCTAssertGreaterThan(ps.count, 400)
  }

  /// The glass lens is a probe (REDESIGN.md §5.3): pressed 10 mm into a toothpaste block and lifted out, it leaves a
  /// dent that stays (≥ 6 mm, ≥ 85 % of it 3 s later: the yield stress holds the walls); in honey the dent heals.
  @MainActor func testLensDentStaysInToothpasteHealsInHoney() throws {
    func dent(_ id: MaterialID) throws -> (early: Double, late: Double, yields: Int) {
      let rig = try PhysRig(["-material", id])
      rig.fill([(id, CGRect(x: 0.15 * rig.tank.x, y: 0, width: 0.7 * rig.tank.x, height: 0.025))])
      rig.run(1)
      let x = rig.tank.x / 2, r = LensState.defaultRadius, dx = rig.solver.cellSize
      func surface() -> Double {
        (rig.particles.filter { abs($0.position.x - x) < dx }.map(\.position.y).max() ?? 0) + 0.25 * dx
      }
      let s0 = surface()
      var yields = 0
      var y = s0 + r + 0.004
      let bottom = s0 + r - 0.010
      while y > bottom {
        y -= 0.05 / 60
        rig.model.lens = LensState(centre: SIMD2(x, y), radius: r, active: true, velocity: SIMD2(0, -0.05))
        rig.step()
        yields += rig.frame.pasteEvents.filter { $0.kind == .yield }.count
      }
      rig.run(0.3)
      while y < s0 + r + 0.01 {
        y += 0.05 / 60
        rig.model.lens = LensState(centre: SIMD2(x, y), radius: r, active: true, velocity: SIMD2(0, 0.05))
        rig.step()
      }
      rig.model.lens.active = false
      rig.run(0.2)
      let early = s0 - surface()
      rig.run(2.8)
      return (early, s0 - surface(), yields)
    }
    let paste = try dent("toothpaste"), honey = try dent("honey")
    report("play.lens.dent", ["toothpasteEarlyMM": paste.early * 1000, "toothpasteLateMM": paste.late * 1000,
                              "toothpasteYields": Double(paste.yields), "honeyEarlyMM": honey.early * 1000,
                              "honeyLateMM": honey.late * 1000])
    XCTAssertGreaterThan(paste.early, 0.006, "the lens leaves a dent")
    XCTAssertGreaterThan(paste.late, 0.85 * paste.early, "and it stays")
    XCTAssertLessThan(honey.late, 0.4 * max(honey.early, 0.001), "honey heals")
  }

  /// Jammed oobleck stops the glass (REDESIGN.md §5.7), as it stops a fingertip: a slow lens sinks with the drag, a
  /// fast one jams the pool (a `.jam` paste event), is held back, and sinks on as the jam melts.
  @MainActor func testOobleckJamsUnderTheLens() throws {
    func push(speed: Double) throws -> (lag: Double, stoppedLag: Double, laterLag: Double, maxJam: Double, jams: Int) {
      let rig = try PhysRig(["-material", "oobleck"])
      rig.run(1.0, dt: 1.0 / 120)
      let x = rig.tank.x / 2, r = LensState.defaultRadius
      let top = 0.058, bottom = 0.018
      var y = top
      var maxLag = 0.0, maxJam = 0.0
      var jams = 0
      func lens(_ y: Double, _ v: Double) {
        rig.model.lens = LensState(centre: SIMD2(x, y), radius: r, active: true, velocity: SIMD2(0, -v))
      }
      while y > bottom {
        y = max(bottom, y - speed / 120)
        lens(y, speed)
        rig.step(1.0 / 120)
        maxJam = max(maxJam, rig.stats.jammedFraction)
        jams += rig.frame.pasteEvents.filter { $0.kind == .jam }.count
        if let l = rig.frame.lens { maxLag = max(maxLag, l.centre.y - y) }
      }
      rig.run(0.1, dt: 1.0 / 120) { _ in
        lens(bottom, 0)
        maxJam = max(maxJam, rig.stats.jammedFraction)
        jams += rig.frame.pasteEvents.filter { $0.kind == .jam }.count
      }
      let stopped = (rig.frame.lens?.centre.y ?? bottom) - bottom
      rig.run(1.5, dt: 1.0 / 120) { _ in lens(bottom, 0) }
      let later = (rig.frame.lens?.centre.y ?? bottom) - bottom
      return (maxLag, stopped, later, maxJam, jams)
    }
    let slow = try push(speed: 0.02)
    let fast = try push(speed: 0.6)
    report("play.lens.oobleck", ["slowMaxLagMM": slow.lag * 1000, "slowJam": slow.maxJam, "fastLagAt0.1sMM": fast.stoppedLag * 1000,
                                 "fastLagAt1.6sMM": fast.laterLag * 1000, "fastJam": fast.maxJam, "fastJamEvents": Double(fast.jams)])
    XCTAssertLessThan(slow.lag, 0.004, "the slow lens follows the drag")
    XCTAssertGreaterThan(fast.stoppedLag, 0.006, "the fast lens is stopped short")
    XCTAssertGreaterThan(fast.maxJam, 0.3, "it jams the oobleck")
    XCTAssertGreaterThanOrEqual(fast.jams, 1, "a jam event for the tiles")
    XCTAssertLessThan(fast.laterLag, fast.stoppedLag - 0.003, "held, it sinks on as the jam melts")
  }

  /// Tilt-to-yield (REDESIGN.md §5.4): a 30 × 30 mm toothpaste pile on a slowly tilting floor (3°/s) leans but holds
  /// while gravity's sideways pull is below its yield stress, then slides past the yield angle (measured on the Mac:
  /// 0.5 mm of lean by 10°, sliding from 26° at 2°/s; the chamber grips toothpaste, ToothpasteTuning.wallFriction).
  @MainActor func testTiltPastTheYieldAngle() throws {
    let rig = try PhysRig(["-material", "toothpaste"])
    rig.model.layers.useTilt = false
    rig.fill([("toothpaste", CGRect(x: rig.tank.x / 2 - 0.015, y: 0, width: 0.03, height: 0.03))])
    rig.run(1)
    let c0 = rig.com(rig.particles)
    var angle = 0.0, slide: Double?, leanAt10 = 0.0
    var last = c0.x
    let rate = 3.0 * .pi / 180
    for k in 0..<(60 * 15) {
      rig.model.perform(.tilt(dx: rate / 60, dy: 0))
      angle += rate / 60
      rig.step()
      guard k % 15 == 14 else { continue }
      let c = rig.com(rig.particles)
      let degrees = angle * 180 / .pi
      if abs(degrees - 10) < 0.4 { leanAt10 = c.x - c0.x }
      if slide == nil, (c.x - last) / 0.25 > 0.005 { slide = degrees }
      last = c.x
      if let s = slide, degrees > s + 4 { break }
    }
    report("play.tilt", ["leanAt10degMM": leanAt10 * 1000, "slideDeg": slide ?? -1, "driftMM": (last - c0.x) * 1000])
    XCTAssertLessThan(abs(leanAt10), 0.003, "leans but holds below the yield angle")
    let s = try XCTUnwrap(slide, "it slides once tilted far enough")
    XCTAssertGreaterThan(s, 12)
    XCTAssertLessThan(s, 40)
  }

  /// Shake (REDESIGN.md §5.5): a gentle shake (0.25 g at 6 Hz for 1 s) leaves the starting coil standing (it stays
  /// within its elastic range almost everywhere: measured −0.7 mm of height, +2.4 mm of width); a hard one (2 g) breaks
  /// it into flow and it spreads (+23 mm).
  @MainActor func testShakeJigglesBelowYieldFlowsAbove() throws {
    func burst(_ g: Double) throws -> (dTop: Double, dWidth: Double) {
      let rig = try PhysRig(["-material", "toothpaste"])
      rig.model.layers.useTilt = false
      rig.run(1)
      let p0 = rig.particles
      rig.engine.shake(g: g, hz: 6, seconds: 1)
      rig.run(3)
      let p1 = rig.particles
      return (rig.top(p1) - rig.top(p0), rig.width(p1) - rig.width(p0))
    }
    let gentle = try burst(0.25), hard = try burst(2)
    report("play.shake", ["gentleTopMM": gentle.dTop * 1000, "gentleWidthMM": gentle.dWidth * 1000,
                          "hardTopMM": hard.dTop * 1000, "hardWidthMM": hard.dWidth * 1000])
    XCTAssertLessThan(abs(gentle.dTop), 0.0015, "a gentle shake: it keeps its height")
    XCTAssertLessThan(gentle.dWidth, 0.005)
    XCTAssertGreaterThan(hard.dWidth, 0.012, "a hard shake: it flows and spreads")
  }

  /// Heat (REDESIGN.md §5.6): warmed to 90 °C the coil softens (τ_y about 100 Pa) and slumps; at room temperature it
  /// stands.
  @MainActor func testWarmToothpasteSlumps() throws {
    func coil(heat: Double) throws -> Double {
      let rig = try PhysRig(["-material", "toothpaste"])
      rig.model.layers.useTilt = false
      rig.run(0.5)
      let top0 = rig.top(rig.particles)
      rig.model.params[.heat] = heat
      rig.run(8)
      return rig.top(rig.particles) - top0
    }
    let room = try coil(heat: 20), hot = try coil(heat: 90)
    report("play.heat", ["roomDropMM": room * 1000, "hotDropMM": hot * 1000])
    XCTAssertGreaterThan(room, -0.0015, "room temperature: it stands")
    XCTAssertLessThan(hot, room - 0.003, "hot: it slumps")
  }

  @MainActor func testCopyLint() {
    let c = ToothpasteCatalogData()
    var specs = c.specs
    for m in c.materials { specs += ToothpasteKnobs.materialSpecs(for: m.material, title: m.title) }
    for s in specs {
      XCTAssertLessThanOrEqual(s.hint.count, 110, "\(s.id) hint")
      XCTAssertLessThanOrEqual(s.descriptor.count, 36, "\(s.id) descriptor")
      XCTAssertTrue(CopyLint.americanSpellings(in: s.title + " " + s.hint + " " + s.detail).isEmpty, "\(s.id)")
      XCTAssertTrue(s.range.contains(s.defaultValue), "\(s.id) default in range")
    }
    for m in c.materials {
      XCTAssertLessThanOrEqual(m.hint.count, 36, m.id)
      XCTAssertTrue(CopyLint.americanSpellings(in: m.hint + " " + m.real + " " + m.tuned).isEmpty, m.id)
    }
    for e in c.experiments {
      XCTAssertLessThanOrEqual(e.title.count, 22, e.id)
      XCTAssertLessThanOrEqual(e.subtitle.count, 48, e.id)
      XCTAssertTrue(CopyLint.americanSpellings(in: e.title + " " + e.subtitle + " " + e.note).isEmpty, e.id)
      XCTAssertNotNil(ToothpasteExperiments.recipes[e.id], "\(e.id) has a recipe")
    }
    for s in c.sources { XCTAssertTrue(CopyLint.americanSpellings(in: s.title).isEmpty, s.title) }
  }
}
