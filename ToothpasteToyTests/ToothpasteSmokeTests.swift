// ToothpasteSmokeTests.swift — OWNER: integrator. Areas add their own test files (PhysTests.swift, RenderTests.swift,
// UITests.swift, FeelTests.swift) rather than editing this one.
//
// 1. The catalog, specs, pages and experiments are consistent with each other and with LabKit.
// 2. The whole frame loop runs headlessly: ToothpasteModel advances 120 frames through LabKit's LabFrameEncoder (solver,
//    surface prepass, two-phase scene with the behind copy, lines, bloom), with a scripted finger, and the fluid is
//    visible in the scene target.

import CoreGraphics
import ImageIO
import LabKitCore
import LabKitMPM
import LabKitRender
import LabKitShaderTypes
import Metal
import UniformTypeIdentifiers
import XCTest
import simd

@testable import ToothpasteToy

final class ToothpasteSmokeTests: XCTestCase {
  // MARK: Catalog

  @MainActor func testCatalogIsConsistent() throws {
    let c = ToothpasteCatalogData()
    XCTAssertEqual(c.materials.count, 13)
    XCTAssertEqual(Set(c.materials.map(\.id)), Set(LabPalette.rheoFluids.map(\.id)), "ids match the data hues")
    for (i, m) in c.materials.enumerated() {
      XCTAssertEqual(m.slot, i)
      XCTAssertEqual(m.title, ContinuumPresets.all[i].name)
      XCTAssertEqual(m.material, ContinuumPresets.all[i].material)
      XCTAssertLessThanOrEqual(m.hint.count, 36, m.id)
      XCTAssertFalse(m.activeKnobs.isEmpty, m.id)
      XCTAssertTrue(CopyLint.americanSpellings(in: m.hint + " " + m.real + " " + m.tuned).isEmpty, m.id)
    }
    XCTAssertEqual(c.pages.count, 5)
    let registered = Set(c.specs.map(\.id))
    for page in c.pages {
      XCTAssertEqual(page.knobs.count, 4, page.id)
      for id in page.knobs { XCTAssertTrue(registered.contains(id), "\(id) registered") }
      for id in page.knobs { XCTAssertNotNil(LabPalette.rheo.parameterHues[id], "\(id) has a hue") }
    }
    for id in c.cardKnobs { XCTAssertTrue(registered.contains(id)) }
    for s in c.specs {
      XCTAssertLessThanOrEqual(s.hint.count, 110, "\(s.id) hint")
      XCTAssertLessThanOrEqual(s.descriptor.count, 36, "\(s.id) descriptor")
      XCTAssertTrue(CopyLint.americanSpellings(in: s.title + " " + s.hint + " " + s.detail).isEmpty, "\(s.id)")
    }
    XCTAssertEqual(c.experiments.count, 14)
    XCTAssertEqual(Set(c.experiments.map(\.id)).count, 14, "unique experiment ids")
    let titles = Set(c.specs.map(\.title) + c.pages.map(\.title))
    for e in c.experiments {
      XCTAssertLessThanOrEqual(e.title.count, 22, e.id)
      XCTAssertLessThanOrEqual(e.subtitle.count, 48, e.id)
      if let m = e.material { XCTAssertNotNil(c.materials.first { $0.id == m }, "\(e.id) material") }
      for id in e.values.keys { XCTAssertTrue(registered.contains(id), "\(e.id) sets \(id)") }
      XCTAssertTrue(CopyLint.americanSpellings(in: e.title + " " + e.subtitle + " " + e.note).isEmpty, e.id)
      XCTAssertTrue(CopyLint.unknownUINames(in: e.note, known: titles).isEmpty, e.id)
    }
    XCTAssertEqual(c.props.count, PropKind.allCases.count)
  }

  @MainActor func testFlowCurvesAreModelled() {
    let c = ToothpasteCatalogData()
    let rates = [0.01, 0.1, 1, 10, 100]
    let honey = c.flowCurve("honey", shearRates: rates, temperature: 293.15)
    XCTAssertEqual(honey[2], 15.4, accuracy: 1e-9, "Newtonian honey: σ = η·γ̇")
    let warm = c.flowCurve("honey", shearRates: [1], temperature: 299.15)[0]
    XCTAssertEqual(warm / honey[2], 0.5, accuracy: 0.05, "honey halves per 6 K")
    let ketchup = c.flowCurve("ketchup", shearRates: rates, temperature: 293.15)
    XCTAssertGreaterThan(ketchup[0], 10, "ketchup keeps a yield stress")
    let oobleck = c.flowCurve("oobleck", shearRates: [0.1, 1000], temperature: 293.15)
    XCTAssertTrue(oobleck[0].isFinite && oobleck[0] > 0, "oobleck flows slowly")
    XCTAssertTrue(oobleck[1].isNaN || oobleck[1] > 100, "oobleck jams when sheared fast")
    // Lava follows the solver's 230 K band (LabKit V14e: τ̄ at 1 s⁻¹ rises × 22 from 1170 to 900 °C, flat below).
    let lava = c.flowCurve("lava", shearRates: [1], temperature: 1443.15)[0]
    let crust = c.flowCurve("lava", shearRates: [1], temperature: 1173.15)[0]
    let colder = c.flowCurve("lava", shearRates: [1], temperature: 1123.15)[0]
    print("RHEO-SMOKE lava σ(1 s⁻¹) 1170 °C \(lava) Pa, 900 °C \(crust) Pa (× \(crust / lava)), 850 °C \(colder) Pa")
    XCTAssertGreaterThan(crust / lava, 10, "lava stiffens down to 900 °C")
    XCTAssertEqual(colder, crust, accuracy: crust * 1e-9, "and no further")
    for m in c.materials {
      let s = c.flowCurve(m.id, shearRates: [1], temperature: m.fillTemperature)[0]
      XCTAssertTrue(s.isFinite && s > 0, "\(m.id) σ(1 s⁻¹) = \(s)")
    }
  }

  // MARK: Tank mapping

  func testTankViewMapsLifeSize() {
    let tank = SIMD2(0.0712, 0.10087)
    let v = TankView(tankSize: tank, regionSize: CGSize(width: 430, height: 612.3), metresPerPoint: 0.16565e-3)
    XCTAssertTrue(v.isLifeSize)
    XCTAssertEqual(Double(v.worldRect.minY), 0, accuracy: 1e-12, "the floor sits on the region's bottom edge")
    let floorCentre = v.tankPoint(CGPoint(x: 215, y: 612.3))
    XCTAssertEqual(floorCentre.x, tank.x / 2, accuracy: 1e-6)
    XCTAssertEqual(floorCentre.y, 0, accuracy: 1e-9)
    let p = SIMD2(0.02, 0.03)
    let back = v.tankPoint(v.regionPoint(p))
    XCTAssertEqual(back.x, p.x, accuracy: 1e-9)
    XCTAssertEqual(back.y, p.y, accuracy: 1e-9)
    let small = TankView(tankSize: tank, regionSize: CGSize(width: 430, height: 419.5), metresPerPoint: 0.16565e-3)
    XCTAssertFalse(small.isLifeSize, "AX XXXL: the tank is fitted")
    XCTAssertEqual(small.displayScale, 0.69, accuracy: 0.01)
  }

  /// REDESIGN.md §1: toothpaste is the hero and the default material (a plain launch, no saved settings). The other
  /// tests pin `-material oobleck` (the Rheo default they were written for).
  @MainActor func testToothpasteIsTheDefaultMaterial() {
    let model = ToothpasteModel(launch: ToothpasteLaunch.parse(["ToothpasteToy", "-noPersist"]), device: nil)
    XCTAssertEqual(model.materialID, "toothpaste")
    XCTAssertEqual(defaultMaterialID, "toothpaste")
    XCTAssertEqual(ToothpasteTelemetry().material, "toothpaste")
  }

  /// Metro starter adoption (FOUNDATION step 2): the lens optics shader is compiled into the app's default library
  /// (SwiftUI's `ShaderLibrary.instrumentLensOptics` looks it up there), and the starter reads the `Metro` tokens.
  @MainActor func testMetroStarterIsInstalled() throws {
    let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    let library = try device.makeDefaultLibrary(bundle: Bundle(for: ToothpasteModel.self))
    XCTAssertTrue(library.functionNames.contains("instrumentLensOptics"), "\(library.functionNames.sorted())")
    XCTAssertEqual(InstrumentMetrics.lensOpacity, Metro.Opacity.lensComposite)
    XCTAssertEqual(InstrumentMetrics.lensOpacity, 0.48)
    XCTAssertEqual(LensRefraction.maximumShift(diameter: 322), 8.05, accuracy: 1e-9, "spec §14: 8.05 pt at 322 pt")
    XCTAssertEqual(LensRefraction.maximumChannelSplit(diameter: 322), 1, accuracy: 1e-12)
    XCTAssertEqual(Metro.Layout.cluster(availableWidth: 430 - 2 * Metro.Spacing.screenInset).diameter, 322,
                   "spec §5: the 430 pt iPhone's dial")
    XCTAssertEqual(Metro.Colour.canvas.srgb, SIMD3<Float>(0.025, 0.042, 0.058))
    XCTAssertLessThan(Metro.Colour.canvas.linear.x, Metro.Colour.canvas.srgb.x, "linear light is darker")
  }

  // MARK: Headless frame loop

  /// 240 frames at 120 Hz (the device rate; 2 s), through the whole LabKit frame encoder.
  @MainActor func testModelAdvances240FramesHeadless() throws {
    let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    let launch = ToothpasteLaunch.parse(["ToothpasteToy", "-noPersist", "-material", "oobleck", "-fakeTouch", "poke"])
    let model = ToothpasteModel(launch: launch, device: device)
    XCTAssertNotNil(model.resources.solver, "MPMSolver initialised")
    XCTAssertNotNil(model.resources.surface, "MPMSurfaceRenderer initialised")
    XCTAssertEqual(model.materialID, "oobleck")

    let size = CGSize(width: 430, height: 932)  // 1 px per point keeps the test light
    let region = CGRect(x: 0, y: 59, width: 430, height: 612.3)
    model.canvasRegion = region
    let targets = try XCTUnwrap(RenderTargets(device: device, size: size, wantsBehind: true))
    let encoder = try LabFrameEncoder(device: device, drawableFormat: .rgba16Float)
    let od = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba16Float, width: Int(size.width), height: Int(size.height), mipmapped: false)
    od.usage = [.renderTarget, .shaderRead]
    od.storageMode = .private
    let output = try XCTUnwrap(device.makeTexture(descriptor: od))
    let queue = try XCTUnwrap(device.makeCommandQueue())
    var camera = LayoutCamera()
    let dt = 1.0 / 120
    var fingerFrames = 0
    for frame in 0..<240 {
      model.advance(dt: dt)
      if model.latestFrame.finger != nil { fingerFrames += 1 }
      guard case .orthographicRect(let world, let fit) = model.projection else { return XCTFail("projection") }
      let setup = camera.orthographic(
        world: world, fit: fit, region: region, viewBounds: CGRect(origin: .zero, size: size), drawableSize: size,
        scale: 1, dt: dt)
      let cmd = try XCTUnwrap(queue.makeCommandBuffer())
      encoder.encode(
        cmd, scene: model, targets: targets, output: output,
        info: LabFrameInfo(setup: setup, time: Float(Double(frame) * dt), dt: dt, frameIndex: frame % 3, pxScale: 1))
      cmd.commit()
      cmd.waitUntilCompleted()
      XCTAssertNil(cmd.error, "frame \(frame)")
    }
    XCTAssertTrue(encoder.lastFrameSplit, "two-phase scene with the behind copy")
    let f = model.latestFrame
    // Time ×1: 240 frames of 1/120 s = 2 s; at 120 Hz the pool needs about 14 substeps (cap 20), so no lag.
    XCTAssertEqual(f.simTime, 2, accuracy: 1e-6, "simulated time = real time")
    XCTAssertGreaterThan(fingerFrames, 10, "the -fakeTouch poke put a finger in the tank")
    let stats = try XCTUnwrap(model.resources.solver).stats
    XCTAssertGreaterThan(stats.liveParticles, 2_000, "fluid seeded")
    XCTAssertEqual(stats.nanCount, 0, "no NaN")
    XCTAssertEqual(stats.overflowCount, 0, "no fixed-point overflow")
    XCTAssertGreaterThan(stats.substeps, 0)
    XCTAssertFalse(stats.lagging, "no time dilation at 120 Hz")
    XCTAssertTrue(f.input.gravity.y < -5, "gravity points down the screen: \(f.input.gravity)")
    let t = model.engine.telemetry(frame: f, framesPerSecond: 60)
    XCTAssertTrue(t.viscosity.isFinite && t.stress.isFinite && t.shearRate.isFinite)

    // The fluid is drawn: a pixel low in the tank differs from one in the headspace.
    let w = Int(size.width), h = Int(size.height)
    let bytes = try XCTUnwrap(device.makeBuffer(length: w * h * 8, options: .storageModeShared))
    let cmd = try XCTUnwrap(queue.makeCommandBuffer())
    let blit = try XCTUnwrap(cmd.makeBlitCommandEncoder())
    blit.copy(
      from: targets.scene, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
      sourceSize: MTLSize(width: w, height: h, depth: 1), to: bytes, destinationOffset: 0,
      destinationBytesPerRow: w * 8, destinationBytesPerImage: w * h * 8)
    blit.endEncoding()
    cmd.commit()
    cmd.waitUntilCompleted()
    let px = bytes.contents().bindMemory(to: Float16.self, capacity: w * h * 4)
    func luminance(_ x: Int, _ y: Int) -> Float {
      let i = (y * w + x) * 4
      return 0.2126 * Float(px[i]) + 0.7152 * Float(px[i + 1]) + 0.0722 * Float(px[i + 2])
    }
    let fluid = luminance(60, 640)  // 31 pt above the floor, away from the finger
    let air = luminance(60, 200)
    XCTAssertGreaterThan(fluid, air + 0.05, "oobleck is lighter than the back wall (fluid \(fluid), air \(air))")
  }

  @MainActor func testMaterialSwitchAndExperiment() throws {
    let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    let model = ToothpasteModel(launch: ToothpasteLaunch.parse(["ToothpasteToy", "-noPersist", "-material", "honey"]), device: device)
    XCTAssertEqual(model.materialID, "honey")
    XCTAssertEqual(model.params[.consistency], 15.4, accuracy: 1e-9, "Fluid page re-registered for honey")
    model.choose(material: "ketchup")
    XCTAssertEqual(model.materialID, "ketchup")
    XCTAssertEqual(model.params[.yield], 25, accuracy: 1e-9, "ketchup rested yield 10 + 15")
    model.perform(.experiment("moon"))
    XCTAssertEqual(model.materialID, "mayonnaise")
    XCTAssertEqual(model.params[.gravity], 0.166, accuracy: 1e-9)
    XCTAssertEqual(
      model.params.matchingExperiment(model.catalog.experiments, material: model.materialID)?.id, "moon")
    model.perform(.experiment("lava"))
    XCTAssertEqual(model.params.spec(.heat).range, 1050...1200, "Heat re-registered for lava")
    model.choose(material: "oobleck")
    XCTAssertEqual(model.params.spec(.heat).range, 0...90)
  }

  // MARK: Headless pictures (display-independent visual check)

  /// Renders `frames` frames of `model` offscreen at iPhone 15 Pro Max size and returns the composited output.
  @MainActor private func render(_ model: ToothpasteModel, frames: Int, scale: CGFloat, device: MTLDevice) throws -> MTLTexture {
    let points = CGSize(width: 430, height: 932)
    let size = CGSize(width: points.width * scale, height: points.height * scale)
    let region = CGRect(x: 0, y: 59, width: 430, height: 612.3)
    model.canvasRegion = region
    let targets = try XCTUnwrap(RenderTargets(device: device, size: size, wantsBehind: true))
    let encoder = try LabFrameEncoder(device: device, drawableFormat: .rgba16Float)
    let od = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba16Float, width: Int(size.width), height: Int(size.height), mipmapped: false)
    od.usage = [.renderTarget, .shaderRead]
    od.storageMode = .private
    let output = try XCTUnwrap(device.makeTexture(descriptor: od))
    let queue = try XCTUnwrap(device.makeCommandQueue())
    var camera = LayoutCamera()
    let dt = 1.0 / 60
    for frame in 0..<frames {
      model.advance(dt: dt)
      guard case .orthographicRect(let world, let fit) = model.projection else { throw XCTSkip("projection") }
      let setup = camera.orthographic(
        world: world, fit: fit, region: region, viewBounds: CGRect(origin: .zero, size: points), drawableSize: size,
        scale: Float(scale), dt: dt)
      let cmd = try XCTUnwrap(queue.makeCommandBuffer())
      encoder.encode(
        cmd, scene: model, targets: targets, output: output,
        info: LabFrameInfo(setup: setup, time: Float(Double(frame) * dt), dt: dt, frameIndex: frame % 3, pxScale: Float(scale)))
      cmd.commit()
      cmd.waitUntilCompleted()
    }
    return output
  }

  /// Writes an rgba16Float texture (extended linear) as an 8-bit sRGB-encoded PNG in the test's temporary directory.
  @MainActor private func writePNG(_ texture: MTLTexture, name: String, device: MTLDevice) throws -> URL {
    let w = texture.width, h = texture.height
    let bytes = try XCTUnwrap(device.makeBuffer(length: w * h * 8, options: .storageModeShared))
    let queue = try XCTUnwrap(device.makeCommandQueue())
    let cmd = try XCTUnwrap(queue.makeCommandBuffer())
    let blit = try XCTUnwrap(cmd.makeBlitCommandEncoder())
    blit.copy(
      from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: w, height: h, depth: 1),
      to: bytes, destinationOffset: 0, destinationBytesPerRow: w * 8, destinationBytesPerImage: w * h * 8)
    blit.endEncoding()
    cmd.commit()
    cmd.waitUntilCompleted()
    let src = bytes.contents().bindMemory(to: Float16.self, capacity: w * h * 4)
    var rgba = [UInt8](repeating: 255, count: w * h * 4)
    for i in 0..<(w * h) {
      for c in 0..<3 {
        let v = min(max(Float(src[i * 4 + c]), 0), 1)
        let e = v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        rgba[i * 4 + c] = UInt8(min(max(e * 255, 0), 255))
      }
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tt-headless-\(name).png")
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
    print("RHEO-HEADLESS-PNG \(url.path)")
    return url
  }

  /// Oobleck with a scripted poke, honey and ketchup, rendered offscreen at 3× and written as PNGs.
  @MainActor func testHeadlessPictures() throws {
    let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    for (name, args, frames) in [
      ("oobleck-poke", ["-fakeTouch", "poke"], 150), ("honey", ["-material", "honey"], 90),
      ("ketchup", ["-material", "ketchup"], 90), ("water", ["-material", "waterLike"], 90),
    ] {
      let model = ToothpasteModel(launch: ToothpasteLaunch.parse(["ToothpasteToy", "-noPersist", "-material", "oobleck"] + args), device: device)
      let out = try render(model, frames: frames, scale: 3, device: device)
      _ = try writePNG(out, name: name, device: device)
      let stats = try XCTUnwrap(model.resources.solver).stats
      XCTAssertEqual(stats.nanCount, 0, name)
    }
  }
}
