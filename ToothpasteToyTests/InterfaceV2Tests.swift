// InterfaceV2Tests.swift — OWNER: integrator (FOUNDATION, 13 October 2026). Frozen with Interfaces.swift: areas may add
// tests here only for additive interface changes they announce.
//
// The v2 contracts of REDESIGN.md §8 through the real hub and engine: the squeeze becomes a striped ribbon from the
// nozzle that tears off on release, the glass lens pushes paste and is the rheometer's probe, the hub maps canvas
// points to the lens, keeps the tube's material in step with a Fill, and publishes channels and stamped paste events.
// These check the stubs' wiring, not the toy's final feel (PLAY tunes that; PhysTests judge physics).

import CoreGraphics
import ImageIO
import LabKitMPM
import UniformTypeIdentifiers
import XCTest
import simd

@testable import ToothpasteToy

final class InterfaceV2Tests: XCTestCase {
  /// Squeezing extrudes paste from the top-centre nozzle carrying three dye bands, left to right across the bore; on
  /// release the nozzle stops and a tear-off event (ribbon length) reaches the hub's feed, stamped and in order.
  @MainActor func testSqueezeExtrudesAStripedRibbonAndTearsOff() throws {
    let rig = try PhysRig(["-material", "toothpaste"])
    rig.solver.clear()
    rig.model.squeeze = SqueezeState(rate: 40, nozzleDiameter: 8, stripes: 3, material: "toothpaste")
    rig.run(0.75)
    let nozzle = try XCTUnwrap(rig.frame.nozzle)
    XCTAssertTrue(nozzle.emitting)
    // Updated by PLAY (14 October 2026, written reason): the tube now rides down from its parked place at the top
    // centre to lay the ribbon in folds just above the paste (Engine/Tube.swift, REDESIGN.md §5.2), so the mouth is
    // near the floor and sweeps ±1.5 bores about the centre, and the pressure builds only once it has arrived (about
    // 0.2 s of travel, then the squeeze ramps up): 0.75 s at 40 mm/s extrudes about 21 mm, not 30. `NozzleState.position`
    // is still the mouth, wherever the tube is (HOLO draws the nozzle there; UI centres the crown on its x).
    XCTAssertEqual(nozzle.position.x, rig.tank.x / 2, accuracy: 1.5 * 2 * nozzle.radius + nozzle.radius, "about the centre")
    XCTAssertLessThan(nozzle.position.y, 0.5 * rig.tank.y, "the tube rode down to lay the ribbon")
    XCTAssertEqual(nozzle.extruded, 0.021, accuracy: 0.006, "0.75 s at 40 mm/s after the descent and the ramp")
    let ps = rig.particles
    XCTAssertGreaterThan(ps.count, 100, "a ribbon came out")
    XCTAssertEqual(Set(ps.map(\.band)), [1, 2, 3], "three stripes")
    let near = ps.filter { nozzle.position.y - $0.position.y < 0.012 }
    func meanX(_ b: Int) -> Double {
      let xs = near.filter { $0.band == b }.map(\.position.x)
      return xs.isEmpty ? .nan : xs.reduce(0, +) / Double(xs.count)
    }
    print(String(format: "TT-V2 squeeze: %d particles, %d near the nozzle; band mean x − centre %.2f / %.2f / %.2f mm",
                 ps.count, near.count, (meanX(1) - nozzle.position.x) * 1000, (meanX(2) - nozzle.position.x) * 1000,
                 (meanX(3) - nozzle.position.x) * 1000))
    XCTAssertLessThan(meanX(1), meanX(2))
    XCTAssertLessThan(meanX(2), meanX(3))

    rig.model.squeeze.rate = 0
    rig.run(0.25)
    XCTAssertFalse(try XCTUnwrap(rig.frame.nozzle).emitting)
    let emitted = rig.solver.stats.emitted
    rig.run(0.1)
    XCTAssertEqual(rig.solver.stats.emitted, emitted, "nothing leaves the nozzle after release")
    let tear = try XCTUnwrap(rig.model.events.last { $0.kind == .tearOff }, "the tear-off reached the 10 Hz feed")
    XCTAssertEqual(tear.magnitude, nozzle.extruded, accuracy: 0.005, "ribbon length (PLAY: as extruded, see above)")
    XCTAssertGreaterThan(tear.id, 0)
    XCTAssertGreaterThan(tear.time, 0)
    XCTAssertEqual(rig.model.events.map(\.id), rig.model.events.map(\.id).sorted(), "ids increase")
    XCTAssertTrue(rig.model.live.recentEvents.contains { $0.id == tear.id }, "and the per-frame snapshot")
    let url = try Self.bandPicture(rig.particles, tank: rig.tank, nozzle: nozzle, name: "tt-v2-squeeze-bands")
    print("TT-V2 picture \(url.path)")
  }

  /// A diagnostic picture of the particles coloured by dye band (not the app's rendering): band 1 cyan, 2 white,
  /// 3 violet, undyed grey; the nozzle as an amber bar. 8 px per mm, y up.
  private static func bandPicture(_ ps: [MPMParticleSnapshot], tank: SIMD2<Double>, nozzle: NozzleState, name: String)
    throws -> URL
  {
    let scale = 8000.0, w = Int(tank.x * scale), h = Int(tank.y * scale)
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    let ctx = try XCTUnwrap(CGContext(
      data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(red: 0.025, green: 0.042, blue: 0.058, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let colours: [(CGFloat, CGFloat, CGFloat)] = [(0.5, 0.5, 0.5), (0.32, 0.91, 0.96), (0.95, 0.97, 1), (0.76, 0.57, 1)]
    for p in ps {
      let c = colours[min(max(p.band, 0), 3)]
      ctx.setFillColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
      ctx.fillEllipse(in: CGRect(x: p.position.x * scale - 3, y: p.position.y * scale - 3, width: 6, height: 6))
    }
    ctx.setFillColor(red: 1, green: 0.72, blue: 0.31, alpha: 1)
    ctx.fill(CGRect(
      x: (nozzle.position.x - nozzle.radius) * scale, y: (nozzle.position.y + nozzle.radius) * scale, width: 2 * nozzle.radius * scale,
      height: 6))
    let image = try XCTUnwrap(ctx.makeImage())
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).png")
    let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(dest, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(dest))
    return url
  }

  /// The active lens is a probe collider: driven down through resting toothpaste it clears the paste from its disc,
  /// the rheometer reads at it (finger down), the channels carry its stress; lifted, it leaves the frame.
  @MainActor func testLensPushesThePasteAndIsTheProbe() throws {
    let rig = try PhysRig(["-material", "toothpaste"])
    rig.run(0.5)
    let x = rig.tank.x / 2, r = LensState.defaultRadius
    let frames = 60
    for i in 0..<frames {
      let y = 0.08 - 0.06 * Double(i) / Double(frames - 1)
      rig.model.lens = LensState(centre: SIMD2(x, y), radius: r, active: true, velocity: SIMD2(0, -0.06))
      rig.step()
    }
    rig.run(0.1)
    let centre = rig.model.lens.centre
    let inside = rig.particles.filter { simd_distance($0.position, centre) < r - rig.solver.cellSize }
    let used = try XCTUnwrap(rig.frame.lens, "the engine used the lens")
    print(String(format: "TT-V2 lens at %.1f mm: %d particles inside, probe σ %.1f Pa γ̇ %.3f 1/s, state %@",
                 centre.y * 1000, inside.count, rig.frame.probe.stress, rig.frame.probe.shearRate,
                 rig.model.channels.state.rawValue))
    XCTAssertEqual(used.centre, centre)
    XCTAssertLessThan(inside.count, 4, "the lens pushed the paste out of its disc")
    XCTAssertTrue(rig.frame.probe.fingerDown, "the rheometer reads at the lens")
    XCTAssertGreaterThan(rig.model.channels.stress.value, 1, "the paste presses on the lens")
    XCTAssertEqual(rig.model.channels.stress.level, PasteChannels.logLevel(rig.model.channels.stress.value,
                                                                              in: PasteChannels.stressRange), accuracy: 1e-12)
    rig.model.lens.active = false
    rig.run(0.05)
    XCTAssertNil(rig.frame.lens, "a parked lens pushes nothing")
  }

  /// `moveLens` maps canvas-region points to tank metres, estimates the velocity, parks the lens; a Fill puts the new
  /// paste in the tube. (No GPU needed.)
  @MainActor func testHubMapsTheLensAndKeepsTheTubeInStep() {
    let model = ToothpasteModel(launch: ToothpasteLaunch.parse(["ToothpasteToy", "-noPersist"]), device: nil)
    model.canvasRegion = CGRect(x: 0, y: 59, width: 430, height: 612.3)
    model.moveLens(to: CGPoint(x: 215, y: 300), active: true, timestamp: 10)
    let first = model.tankView.tankPoint(CGPoint(x: 215, y: 300))
    XCTAssertEqual(model.lens.centre.x, first.x, accuracy: 1e-12)
    XCTAssertEqual(model.lens.centre.y, first.y, accuracy: 1e-12)
    XCTAssertTrue(model.lens.active)
    XCTAssertEqual(model.lens.velocity, .zero, "no velocity from a single sample")
    model.moveLens(to: CGPoint(x: 215, y: 330), active: true, timestamp: 10.1)
    XCTAssertLessThan(model.lens.velocity.y, 0, "down the screen is −y in the tank")
    XCTAssertLessThanOrEqual(simd_length(model.lens.velocity), LensState.maxSpeed + 1e-9)
    model.moveLens(to: CGPoint(x: 215, y: 330), active: false, timestamp: 10.2)
    XCTAssertFalse(model.lens.active)
    XCTAssertEqual(model.lens.velocity, .zero)

    XCTAssertEqual(model.squeeze, .idle)
    XCTAssertEqual(model.squeeze.material, "toothpaste")
    model.perform(.fill("honey"))
    XCTAssertEqual(model.squeeze.material, "honey", "the tube holds the new paste")
  }

  /// Channel scales and the state word (pure).
  func testChannelScalesAndStateWords() {
    XCTAssertEqual(PasteChannels.logLevel(0.01, in: PasteChannels.shearRange), 0)
    XCTAssertEqual(PasteChannels.logLevel(1, in: PasteChannels.shearRange), 0.4, accuracy: 1e-12)
    XCTAssertEqual(PasteChannels.logLevel(1000, in: PasteChannels.shearRange), 1)
    XCTAssertEqual(PasteChannels.logLevel(1e6, in: PasteChannels.shearRange), 1)
    XCTAssertEqual(PasteChannels.logLevel(100, in: PasteChannels.stressRange), 0.5, accuracy: 1e-12)
    XCTAssertEqual(PasteChannels.logLevel(.nan, in: PasteChannels.stressRange), 0)
    XCTAssertEqual(PasteChannels.logLevel(-3, in: PasteChannels.stressRange), 0)
    XCTAssertEqual(ToothpasteEngine.stateWord(solid: 0.9, jammed: 0, jams: false), .holding)
    XCTAssertEqual(ToothpasteEngine.stateWord(solid: 0.9, jammed: 0.3, jams: true), .jammed)
    XCTAssertEqual(ToothpasteEngine.stateWord(solid: 0.3, jammed: 0, jams: false), .yielding)
    XCTAssertEqual(ToothpasteEngine.stateWord(solid: 0.05, jammed: 0, jams: false), .flowing)
    XCTAssertEqual(SqueezeState.idle.speed, 0)
    XCTAssertEqual(SqueezeState(rate: 25, nozzleDiameter: 8, stripes: 3, material: "toothpaste").speed, 0.025, accuracy: 1e-12)
    XCTAssertEqual(SqueezeState.idle.nozzleRadius, 0.004, accuracy: 1e-12)
    XCTAssertEqual(SqueezeState.maxStripes, 7)
  }
}
