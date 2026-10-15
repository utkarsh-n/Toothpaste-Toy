// RenderTests.swift — OWNER: HOLO (was RENDER; Documentation/REDESIGN-OWNERSHIP.md).
//
// Display-independent checks of the holo chamber, through the whole LabKit frame (ToothpasteModel → LabFrameEncoder:
// solver, the hologram's prepass, one scene pass — no `behind` copy — lines, bloom, EDR composite) at the iPhone 15 Pro
// Max's chamber-sized MTKView (UI's layout contract: the tank region at ×0.64 plus the housing band, 3 px per point):
//   1. a contact sheet of every paste as a hologram plus toothpaste squeezing, under the lens, tilted and in the Solid
//      view (PNG paths printed as TT-HOLO-PNG);
//   2. the hologram's edge is crisp (a 1 pt rim, not fog) and the drawn paste matches the particles' volume;
//   3. the hologram needs no `behind` copy and the Solid look asks for one (REDESIGN.md §11);
//   4. the interface springs (Wave): flashes peak and decay as specified, every spring settles, nothing goes NaN;
//   5. main-thread cost of advancing and encoding a frame (TT-HOLO-CPU). GPU time is measured on the Mac with HOLO's
//      harness and on the phone by the device lab: the Simulator's GPU timestamps are not meaningful.

import CoreGraphics
import ImageIO
import LabKitCore
import LabKitMPM
import LabKitRender
import LabKitShaderTypes
import Metal
import UniformTypeIdentifiers
import Wave
import XCTest
import simd

@testable import ToothpasteToy

@MainActor final class RenderTests: XCTestCase {
  /// The chamber-sized MTKView: the tank region at ×0.64 of life-size on a 460 ppi, 3× screen, plus the housing band
  /// (2.5 mm left and right, 3.5 mm above, 5.5 mm below the floor, in tank millimetres).
  static let mmPerPoint = 25.4 / (460.0 / 3.0)
  static func pts(_ mm: Double) -> Double { mm * 0.64 / mmPerPoint }
  static let region = CGRect(x: pts(2.5), y: pts(3.5), width: pts(71.2), height: pts(101.4))
  static let view = CGSize(width: pts(76.2), height: pts(110.4))

  /// Offscreen rig at 3 px per point with the hub's own projection.
  final class Rig {
    let device: MTLDevice
    let queue: MTLCommandQueue
    var targets: RenderTargets
    let encoder: LabFrameEncoder
    let output: MTLTexture
    let size: CGSize
    let scale: CGFloat = 3
    var camera = LayoutCamera()

    @MainActor init(device: MTLDevice) throws {
      self.device = device
      size = CGSize(width: (RenderTests.view.width * 3).rounded(), height: (RenderTests.view.height * 3).rounded())
      queue = try XCTUnwrap(device.makeCommandQueue())
      targets = try XCTUnwrap(RenderTargets(device: device, size: size, wantsBehind: false, behindMipLevels: 8))
      encoder = try LabFrameEncoder(device: device, drawableFormat: .rgba16Float)
      let od = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba16Float, width: Int(size.width), height: Int(size.height), mipmapped: false)
      od.usage = [.renderTarget, .shaderRead]
      od.storageMode = .private
      output = try XCTUnwrap(device.makeTexture(descriptor: od))
    }

    /// Frames as the app's LabRenderer draws them (behind copy only when the hub asks for it).
    @MainActor func run(_ model: ToothpasteModel, frames: Int, dt: Double = 1.0 / 60, setup: ((Int) -> Void)? = nil) throws {
      model.canvasRegion = RenderTests.region
      for frame in 0..<frames {
        setup?(frame)
        model.advance(dt: dt)
        if (targets.behind != nil) != model.wantsBehindCopy {
          targets = try XCTUnwrap(RenderTargets(device: device, size: size, wantsBehind: model.wantsBehindCopy, behindMipLevels: 8))
        }
        guard case .orthographicRect(let world, let fit) = model.projection else { throw XCTSkip("projection") }
        let s = camera.orthographic(
          world: world, fit: fit, region: RenderTests.region, viewBounds: CGRect(origin: .zero, size: RenderTests.view),
          drawableSize: size, scale: Float(scale), dt: dt)
        let cmd = try XCTUnwrap(queue.makeCommandBuffer())
        encoder.encode(
          cmd, scene: model, targets: targets, output: output,
          info: LabFrameInfo(setup: s, time: Float(Double(frame) * dt), dt: dt, frameIndex: frame % 3, pxScale: Float(scale)))
        cmd.commit()
        cmd.waitUntilCompleted()
        XCTAssertNil(cmd.error)
      }
    }

    /// The output as 8-bit sRGB-encoded RGBA and linear luminance (soft-clipped to SDR by the composite).
    @MainActor func pixels() throws -> (rgba: [UInt8], linear: [Float], w: Int, h: Int) {
      let w = output.width, h = output.height
      let bytes = try XCTUnwrap(device.makeBuffer(length: w * h * 8, options: .storageModeShared))
      let cmd = try XCTUnwrap(queue.makeCommandBuffer())
      let blit = try XCTUnwrap(cmd.makeBlitCommandEncoder())
      blit.copy(
        from: output, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: w, height: h, depth: 1),
        to: bytes, destinationOffset: 0, destinationBytesPerRow: w * 8, destinationBytesPerImage: w * h * 8)
      blit.endEncoding()
      cmd.commit()
      cmd.waitUntilCompleted()
      let src = bytes.contents().bindMemory(to: Float16.self, capacity: w * h * 4)
      var rgba = [UInt8](repeating: 255, count: w * h * 4)
      var lum = [Float](repeating: 0, count: w * h)
      let weights = SIMD3<Float>(0.2126, 0.7152, 0.0722)
      for i in 0..<(w * h) {
        var l: Float = 0
        for c in 0..<3 {
          let v = min(max(Float(src[i * 4 + c]), 0), 1)
          l += v * weights[c]
          let e = v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
          rgba[i * 4 + c] = UInt8(min(max(e * 255, 0), 255))
        }
        lum[i] = l
      }
      return (rgba, lum, w, h)
    }
  }

  private static func writePNG(_ rgba: [UInt8], w: Int, h: Int, name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tt-holo-\(name).png")
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
    let provider = try XCTUnwrap(CGDataProvider(data: Data(rgba) as CFData))
    let image = try XCTUnwrap(
      CGImage(
        width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: space,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil,
        shouldInterpolate: false, intent: .defaultIntent))
    let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(dest, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(dest))
    return url
  }

  private func model(_ args: [String], device: MTLDevice) -> ToothpasteModel {
    let m = ToothpasteModel(launch: ToothpasteLaunch.parse(["ToothpasteToy", "-noPersist"] + args), device: device)
    m.canvasRegion = Self.region
    return m
  }

  /// The glass lens swept from `a` to `b` (tank metres) over frames `f0..<f1`, parked after.
  private static func sweep(_ m: ToothpasteModel, _ f: Int, _ f0: Int, _ f1: Int, _ a: SIMD2<Double>, _ b: SIMD2<Double>) {
    guard f >= f0 else { return }
    guard f < f1 else {
      m.lens.active = false
      m.lens.velocity = .zero
      return
    }
    let t = Double(f - f0) / Double(max(f1 - f0 - 1, 1))
    m.lens = LensState(centre: a + (b - a) * t, radius: LensState.defaultRadius, active: true, velocity: (b - a) * 60 / Double(f1 - f0))
  }

  // MARK: 1. Contact sheet

  func testHologramContactSheet() throws {
    let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    let rig = try Rig(device: device)
    let catalog = ToothpasteCatalogData()
    struct Panel { var name: String; var args: [String]; var frames: Int; var setup: ((ToothpasteModel, Int) -> Void)? }
    var panels: [Panel] = [
      Panel(name: "toothpaste", args: [], frames: 150, setup: nil),
      Panel(name: "toothpaste-squeeze", args: [], frames: 110) { m, f in if f >= 20 { m.squeeze.rate = 40 } },
      Panel(name: "toothpaste-lens", args: [], frames: 140) { m, f in
        Self.sweep(m, f, 100, 140, SIMD2(0.012, 0.016), SIMD2(0.040, 0.012))
      },
      Panel(name: "toothpaste-tilt", args: [], frames: 140) { m, f in
        if f == 0 { (m.tank as? TankRenderer)?.debugTilt = SIMD2(0.75, 0.25) }
      },
      Panel(name: "toothpaste-solid", args: [], frames: 140) { m, f in if f == 0 { m.layers.solid = true } },
    ]
    for mat in catalog.materials where mat.id != "toothpaste" {
      panels.append(Panel(name: mat.id, args: mat.id == "lava" ? ["-experiment", "lava"] : ["-material", mat.id], frames: 150) { m, f in
        Self.sweep(m, f, 110, 150, SIMD2(0.014, 0.010), SIMD2(0.044, 0.018))
      })
    }
    panels.append(Panel(name: "mrFluid-magnet", args: ["-experiment", "magnet"], frames: 160, setup: nil))
    let cols = 5
    let pw = Int(rig.size.width) / 3, ph = Int(rig.size.height) / 3
    let rows = (panels.count + cols - 1) / cols
    var sheet = [UInt8](repeating: 0, count: pw * cols * ph * rows * 4)
    for (i, panel) in panels.enumerated() {
      let m = model(panel.args, device: device)
      try rig.run(m, frames: panel.frames) { f in panel.setup?(m, f) }
      let px = try rig.pixels()
      let url = try Self.writePNG(px.rgba, w: px.w, h: px.h, name: panel.name)
      print("TT-HOLO-PNG \(panel.name) \(url.path)")
      XCTAssertEqual(try XCTUnwrap(m.resources.solver).stats.nanCount, 0, panel.name)
      let ox = (i % cols) * pw, oy = (i / cols) * ph
      for y in 0..<ph {
        for x in 0..<pw {
          for c in 0..<3 {
            var s = 0
            for j in 0..<3 { for k in 0..<3 { s += Int(px.rgba[((y * 3 + j) * px.w + x * 3 + k) * 4 + c]) } }
            sheet[((oy + y) * pw * cols + ox + x) * 4 + c] = UInt8(s / 9)
          }
          sheet[((oy + y) * pw * cols + ox + x) * 4 + 3] = 255
        }
      }
    }
    let url = try Self.writePNG(sheet, w: pw * cols, h: ph * rows, name: "sheet")
    print("TT-HOLO-PNG sheet \(url.path)")
  }

  // MARK: 2. Crisp, honest edge

  /// Oobleck at rest after 1.5 s, as a hologram: the free surface's rim rises from the dark chamber to half its peak
  /// within a few pixels (a 1 pt rim, not fog), and the drawn paste (pixels the hologram changed against the chamber
  /// alone) matches the particles' area within 20 % (the rim's bloom adds a little).
  func testHologramEdgeIsCrispAndNotInflated() throws {
    let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    let rig = try Rig(device: device)
    let m = model(["-material", "oobleck"], device: device)
    try rig.run(m, frames: 90)
    let px = try rig.pixels()
    let tank = try XCTUnwrap(m.tank as? TankRenderer)
    tank.debugPasses.hologram = false
    try rig.run(m, frames: 1)
    let bare = try rig.pixels()
    tank.debugPasses.hologram = true
    let solver = try XCTUnwrap(m.resources.solver)
    let top = Int(Self.region.minY * 3), floor = Int(Self.region.maxY * 3)
    var widths: [Int] = []
    for x in stride(from: 300, to: Int(Self.region.maxX * 3) - 200, by: 120) {
      let column = (top..<floor).map { px.linear[$0 * px.w + x] }
      guard let lo = column.prefix(150).min(), let i0 = column.firstIndex(where: { $0 > lo + 0.12 }) else { continue }
      guard let peak = column[i0..<min(i0 + 12, column.count)].max(), peak - lo > 0.15 else { continue }
      let b = lo + 0.5 * (peak - lo), a = lo + 0.1 * (peak - lo)
      guard let i50 = column.firstIndex(where: { $0 >= b }) else { continue }
      let i10 = column[..<i50].lastIndex(where: { $0 <= a }) ?? 0
      widths.append(i50 - i10)
    }
    print("TT-HOLO-EDGE oobleck rim 10–50 % widths (px at 3x): \(widths)")
    XCTAssertFalse(widths.isEmpty)
    XCTAssertLessThanOrEqual(widths.sorted()[widths.count / 2], 6, "the hologram's edge is crisp, not foggy")
    let ppm = m.tankView.pointsPerMetre * Double(rig.scale)
    var drawn = 0
    for y in top..<floor {
      for x in Int(Self.region.minX * 3)..<Int(Self.region.maxX * 3) where px.linear[y * px.w + x] - bare.linear[y * px.w + x] > 0.012 {
        drawn += 1
      }
    }
    let drawnArea = Double(drawn) / (ppm * ppm)
    let particleArea = Double(solver.stats.liveParticles) * pow(solver.cellSize, 2) / 4
    let ratio = drawnArea / particleArea
    print(String(format: "TT-HOLO-AREA drawn %.1f mm², particles %.1f mm², ratio %.3f", drawnArea * 1e6, particleArea * 1e6, ratio))
    XCTAssertEqual(ratio, 1, accuracy: 0.2, "the drawn hologram matches the particles' volume (no foam, no inflation)")
  }

  // MARK: 3. One scene pass

  func testHologramNeedsNoBehindCopy() throws {
    let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    let rig = try Rig(device: device)
    let m = model([], device: device)
    try rig.run(m, frames: 3)
    XCTAssertFalse(m.wantsBehindCopy, "the hologram is light over the chamber: no behind copy")
    XCTAssertFalse(rig.encoder.lastFrameSplit)
    m.layers.solid = true
    try rig.run(m, frames: 3)
    XCTAssertTrue(m.wantsBehindCopy, "the Solid look refracts what lies behind clear pastes")
    XCTAssertTrue(rig.encoder.lastFrameSplit)
    XCTAssertEqual(try XCTUnwrap(m.tank as? TankRenderer).lastOptions.style, .surface)
    m.layers.solid = false
    try rig.run(m, frames: 3)
    XCTAssertEqual(try XCTUnwrap(m.tank as? TankRenderer).lastOptions.style, .hologram)
  }

  // MARK: 4. Interface springs

  func testHoloSpringsSettleAndFlashesPeak() {
    let springs = HoloSprings()
    // A flash kicked from rest peaks near 1 after about 1/ω = 67 ms and is nearly gone after 0.6 s.
    var bank = HoloFlashBank()
    bank.fire(at: .zero, radius: 0.01, intensity: 1)
    var peak: Float = 0
    var peakAt = 0.0
    var t = 0.0
    while t < 0.6 {
      bank.step(springs.flash, dt: 1.0 / 120)
      t += 1.0 / 120
      if bank.peak > peak { peak = bank.peak; peakAt = t }
    }
    XCTAssertEqual(Double(peak), 1, accuracy: 0.08)
    XCTAssertEqual(peakAt, 0.067, accuracy: 0.02)
    XCTAssertLessThan(bank.peak, 0.08)
    // Every spring settles on a new target from any frame rate, without overshooting into NaN.
    for spring in [springs.tilt, springs.lensIn, springs.lensOut, springs.bounce, springs.ghosts, springs.mouth] {
      for dt in [1.0 / 120, 1.0 / 60, 1.0 / 15] {
        var s = HoloSpring(0)
        s.target = 1
        var elapsed = 0.0
        while elapsed < 2 { s.step(spring, dt: dt); elapsed += dt }
        XCTAssertTrue(s.value.isFinite)
        XCTAssertEqual(Double(s.value), 1, accuracy: 0.01)
      }
    }
    // Interruptible: retargeting mid-flight keeps the velocity (no jump).
    var s = HoloSpring(0)
    s.target = 1
    for _ in 0..<6 { s.step(springs.tilt, dt: 1.0 / 120) }
    let before = s.value
    let v = s.velocity
    s.target = -1
    s.step(springs.tilt, dt: 1.0 / 120)
    XCTAssertGreaterThan(v, 0)
    XCTAssertEqual(Double(s.value), Double(before + v / 120), accuracy: 0.02)
  }

  // MARK: 5. Cost

  /// Main-thread cost of advancing the hub and encoding one whole frame (LabFrameEncoder with every HOLO call), frozen
  /// so the solver adds no substeps.
  func testFrameEncodeCost() throws {
    let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    let rig = try Rig(device: device)
    let m = model([], device: device)
    try rig.run(m, frames: 60, dt: 1.0 / 120) { f in
      if f >= 10 { m.squeeze.rate = 40 }
      Self.sweep(m, f, 20, 60, SIMD2(0.012, 0.016), SIMD2(0.040, 0.012))
    }
    m.paused = true
    var cpu: [Double] = []
    for frame in 0..<120 {
      let t0 = CFAbsoluteTimeGetCurrent()
      m.advance(dt: 1.0 / 120)
      guard case .orthographicRect(let world, let fit) = m.projection else { throw XCTSkip("projection") }
      let s = rig.camera.orthographic(
        world: world, fit: fit, region: Self.region, viewBounds: CGRect(origin: .zero, size: Self.view),
        drawableSize: rig.size, scale: 3, dt: 1.0 / 120)
      let cmd = try XCTUnwrap(rig.queue.makeCommandBuffer())
      rig.encoder.encode(
        cmd, scene: m, targets: rig.targets, output: rig.output,
        info: LabFrameInfo(setup: s, time: Float(frame) / 120, dt: 1.0 / 120, frameIndex: frame % 3, pxScale: 3))
      cpu.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
      cmd.commit()
      cmd.waitUntilCompleted()
    }
    let sorted = cpu.sorted()
    print(
      String(
        format: "TT-HOLO-CPU advance + encode per frame (frozen, Simulator on the Mac CPU): median %.3f ms, p90 %.3f ms",
        sorted[sorted.count / 2], sorted[Int(Double(sorted.count) * 0.9)]))
    XCTAssertLessThan(sorted[sorted.count / 2], 8, "encoding a frame stays well inside the 8.3 ms budget")
  }
}
