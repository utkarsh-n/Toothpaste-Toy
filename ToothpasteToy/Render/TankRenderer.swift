// TankRenderer.swift — OWNER: HOLO (Documentation/REDESIGN-OWNERSHIP.md §3).
//
// `ToothpasteTankRendering`: the holo chamber (REDESIGN.md §2–§3). Order inside LabKit's frame: `buildLines` (this frame's
// springs, options and uniforms, then the overlay lines) → `fillUniforms` (gentle bloom for highlights only) →
// `encodeCompute` (MPMSurfaceRenderer's prepass, after the solver's substeps) → `encodeBehind`: the chamber (projection
// volume with the technical grid at depth and the projector's light cone, refracted under the glass lens; the metal
// housing round it with the projector's slit under the floor), the magnet, props behind the hologram → `encodeScene`:
// the paste as a quantum hologram (LabKitMPM `FluidRenderStyle.hologram`: Fresnel rim, thin-film fringes that turn with
// the tilt, scanlines, the probability cloud, superposition echoes, Metro semantic light, the stripe dye as three
// bands, the lens), the tube nozzle, a canvas finger's ring → overlay lines → bloom and EDR.
//
// The hologram is light drawn over the chamber, so the frame is one scene pass with no `behind` copy (REDESIGN.md §11:
// the copy and its mip chain cost 1.1–2.3 ms on the iPhone 15 Pro Max and serialised the front pass behind it). Only
// View › Solid (the glossy material look, which refracts what lies behind clear pastes) asks LabKit for the copy.
//
// The MTKView is chamber-sized (UI's layout contract, progress-ui.md): the tank's inside fills the canvas region and a
// band of housing surrounds it (2.5 mm left and right, 3.5 mm above, 5.5 mm below the floor). The chamber quad reaches
// `housingReach` beyond the window on every side, so any band the UI chooses shows housing.
//
// Interface motion runs on Wave springs (HoloMotion.swift): the grid's parallax and the fringe hue follow the tilt, the
// lens's refraction fades in and bounces its radius on a yield or jam, every paste event lights an amber flash with a
// spring's attack and decay, the echoes follow the paste's speed, the nozzle's mouth lights while squeezing. Readouts
// and controls are SwiftUI (UI) and never move with any of this (Metro contract 1). World units are tank metres;
// `context.viewProj` is the tank→clip transform. No per-frame heap allocations after warm-up.

import CoreGraphics
import Foundation
import LabKitCore
import LabKitMPM
import LabKitRender
import LabKitShaderTypes
import Metal
import Wave
import simd

/// Mirrors `ToothpasteTankUniforms` in TankShaders.metal.
struct ToothpasteTankUniforms {
  var tank = SIMD4<Float>.zero
  var origin = SIMD4<Float>.zero
  var keyLight = SIMD4<Float>(0.25, 0.45, 0.86, 1.1)
  var fillLight = SIMD4<Float>(-0.7, 0.5, 0.2, 0.45)
  var up = SIMD4<Float>(0, 0.5, 0.866, 0)
  var fluid = SIMD4<Float>.zero
  var tilt = SIMD4<Float>.zero
  var stage = SIMD4<Float>.zero
  var projector = SIMD4<Float>(1, 1, 0, 1)
  var field = SIMD4<Float>.zero
  var misc = SIMD4<Float>.zero
  var lens = SIMD4<Float>.zero
  var lensOptics = SIMD4<Float>.zero
  var nozzle = SIMD4<Float>.zero
  var accent = SIMD4<Float>.zero
}

/// Overlay colours (linear Display P3), converted once: `LabColor.linearDisplayP3` builds its matrix from an array
/// literal, so calling it per frame would allocate on every frame.
private enum TankHues {
  static let stress = LabPalette.rheo.parameterHues[.glow]?.linearDisplayP3 ?? SIMD3(0.05, 0.85, 1.0)
  static let finger = LabPalette.rheo.parameterHues[.finger]?.linearDisplayP3 ?? SIMD3(0.3, 0.8, 1)
  static let value = LabSemantic.value.linearDisplayP3
  static let warning = LabSemantic.warning.linearDisplayP3
  static let forecast = LabSemantic.forecast.linearDisplayP3
}

@MainActor final class TankRenderer: ToothpasteTankRendering {
  /// The chamber quad reaches this far beyond the window (the tank's inside) on every side, m.
  static let housingReach = 0.03
  /// Parallax of the technical grid against the hologram at full tilt (|e| = 1), m; the dot lattice lies deeper.
  static let gridParallax: Float = 0.0018
  static let deepParallax: Float = 2.2
  /// The lens's optics (REDESIGN.md §3, Metro spec §14 scaled to a 6 mm disc): shift at the centre by the tilt (m),
  /// magnification k at the centre (1/(1−k)), red-to-blue split at its diagonal edges (m), and the bounce.
  static let lensShift: Float = 0.0004
  static let lensMagnification: Float = 0.16
  static let lensSplit: Float = 0.00012
  /// A yield or jam squeezes the lens's refraction radius inward by up to this share, then it springs back.
  static let lensBounceDepth: Float = 0.10
  /// Echoes appear once the paste moves faster than this, m/s (full at `ghostFullSpeed`).
  static let ghostOnsetSpeed = 0.08
  static let ghostFullSpeed = 0.55
  /// The rheometer cursor without a lens: drawn dimmed at the strongest-sheared region once the paste there flows
  /// faster than this (1/s), easing to new places over `cursorEase` seconds.
  static let idleCursorRate = 0.5
  static let cursorEase = 0.12
  static let idleCursorAlpha: Float = 0.4

  /// Tests and the Mac harness: a fixed bounded tilt e (|e| ≤ 1) instead of the phone's.
  var debugTilt: SIMD2<Float>?
  /// Tests and the Mac harness: leave out parts of the frame to time them (all drawn by default).
  struct DebugPasses: Sendable, Equatable {
    var chamber = true
    var hologram = true
    var cloud = true
  }
  var debugPasses = DebugPasses()
  /// The options the surface renderer got this frame (tests).
  private(set) var lastOptions = FluidRenderOptions()
  /// The chamber uniforms of this frame (tests).
  var uniforms: ToothpasteTankUniforms { tu }

  private let r: ToothpasteResources
  private var prepared = false
  private var chamber, nozzleQuad, propBehind, propFront, ring, magnet, sheen: QuadRenderer?
  private var blank: MTLTexture?
  /// Where the cursor is drawn (eased toward the probe), tank metres.
  private var cursor: SIMD2<Double>?
  private var cursorFade: Float = 0
  // This frame (set once in `beginFrame`).
  private var frameTime: Float = -1
  private var tu = ToothpasteTankUniforms()
  private var options = FluidRenderOptions()
  private var upSmooth = SIMD3<Float>(0, 0.5, 0.866)
  private var materialOpacity: Float = 1
  private var materialMetallic: Float = 0
  private var hologram = true
  private var quads: [LabQuadInstance] = []
  // Interface motion (Wave springs, HoloMotion.swift).
  private let springs = HoloSprings()
  private var tiltX = HoloSpring(0), tiltY = HoloSpring(0)
  private var tiltReference: SIMD2<Double>?
  private var lensStrength = HoloSpring(0)
  private var lensBounce = HoloSpring(0)
  private var lensLast = LensState.resting
  private var ghostAmount = HoloSpring(0)
  private var mouthLight = HoloSpring(0)
  private var flashBank = HoloFlashBank()

  init(resources: ToothpasteResources) {
    r = resources
    quads.reserveCapacity(32)
    // The catalog's looks drive the Solid view; HoloLooks gives every material its hologram (index = solver slot).
    let materials = resources.catalog.materials.sorted { $0.slot < $1.slot }
    let looks = materials.map(\.look)
    if let surface = resources.surface {
      if looks.count == surface.looks.count { surface.looks = looks }
      var holo = [FluidHoloLook](repeating: .standard, count: max((materials.map(\.slot).max() ?? 0) + 1, 1))
      for m in materials where m.slot >= 0 { holo[m.slot] = HoloLooks.look(m.id) }
      surface.holoLooks = holo
    }
  }

  /// Toothpaste Toy draws its own chamber (no Gyre sky).
  var drawsBackdrop: Bool { false }
  /// The hologram needs no `behind` copy (one scene pass); the Solid look refracts it (REDESIGN.md §11). Read by the hub
  /// before each frame's encode, so a switch takes effect on the next frame.
  var wantsBehindCopy: Bool { !hologram }

  func fillUniforms(_ u: inout LabFrameUniforms, frame: ToothpasteFrame, view: ToothpasteViewState) {
    // Bloom for highlights only (the slit, rim cores, flashes, the brightest cloud points): LabKit's prefilter starts at
    // 0.35 and every broad surface here stays well below it. No post scanlines (the hologram draws its own), no
    // chromatic aberration (Metro keeps colour separation to the lens's diagonal edges).
    u.post = F4(0.34, 0, 0, u.post.w)
  }

  private func prepare(_ device: MTLDevice) {
    guard !prepared else { return }
    prepared = true
    guard let lab = try? LabShaders.library(device: device), let app = device.makeDefaultLibrary() else { return }
    let factory = PipelineFactory(device: device, lab: lab)
    func quad(_ fragment: String, _ blend: LabBlend) -> QuadRenderer? {
      try? QuadRenderer(device: device, factory: factory, fragment: fragment, fragmentLibrary: app, blend: blend, label: "Toothpaste Toy \(fragment)")
    }
    chamber = quad("toothpasteChamberFragment", .none)
    nozzleQuad = quad("toothpasteNozzleFragment", .premultiplied)
    propBehind = quad("toothpastePropFragment", .premultiplied)
    propFront = quad("toothpastePropFrontFragment", .premultiplied)
    ring = quad("toothpasteRingFragment", .premultiplied)
    magnet = quad("toothpasteMagnetFragment", .premultiplied)
    sheen = quad("toothpasteSheenFragment", .premultiplied)
    let bd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 1, height: 1, mipmapped: false)
    bd.usage = .shaderRead
    blank = device.makeTexture(descriptor: bd)
    // A new texture's contents are undefined: make the stand-in transparent black.
    let zero = [UInt16](repeating: 0, count: 4)
    zero.withUnsafeBytes { blank?.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 8) }
  }

  // MARK: Per frame

  /// Springs, lights, fluid options and the shader uniforms for this frame (once per frame, from whichever call comes
  /// first).
  private func beginFrame(_ context: LabFrameContext, _ f: ToothpasteFrame, _ v: ToothpasteViewState) {
    guard context.time != frameTime else { return }
    frameTime = context.time
    prepare(context.device)
    let dt = max(min(context.dt, 1.0 / 15), 0)
    let reduce = v.reduceMotion

    // World up in the screen frame, from the phone's gravity, smoothed over ~0.15 s (lights of the Solid look, props).
    let rest = SIMD3<Float>(0, 0.5, 0.866)
    var upTarget = rest
    if !reduce && v.layers.useTilt {
      let g = r.motion.last.gravity
      let up = -SIMD3<Float>(Float(g.x), Float(g.y), Float(g.z))
      if simd_length(up) > 0.2 { upTarget = simd_normalize(up) }
    }
    upSmooth = simd_normalize(upSmooth + (upTarget - upSmooth) * Float(min(1, dt * 7)))
    let up = upSmooth
    let key = simd_normalize(0.62 * up + SIMD3(0.24, 0, 0.66))
    let fill = simd_normalize(0.18 * up + SIMD3(-0.62, 0, 0.75))

    // The material and which look draws it.
    let info = r.catalog.material(f.material)
    let look = info.look
    materialOpacity = look.opacity
    materialMetallic = look.metallic
    hologram = !v.layers.solid && v.layers.diagnostic == .none
    let holo = HoloLooks.look(f.material)

    // Tilt (Metro spec §13–14: bounded, enhanced), on a spring.
    let e0 = tiltTarget(v)
    tiltX.target = CGFloat(e0.x)
    tiltY.target = CGFloat(e0.y)
    if reduce {
      tiltX.snap(0)
      tiltY.snap(0)
    } else {
      tiltX.step(springs.tilt, dt: dt)
      tiltY.step(springs.tilt, dt: dt)
    }
    var e = SIMD2(tiltX.float, tiltY.float)
    if simd_length(e) > 1 { e = simd_normalize(e) }

    // The lens: refraction fades in while the glass is in the chamber; a yield or jam bounces its radius.
    if let l = f.lens, l.active {
      lensLast = l
      lensStrength.target = 1
      lensStrength.step(springs.lensIn, dt: dt)
    } else {
      lensStrength.target = 0
      lensStrength.step(springs.lensOut, dt: dt)
    }
    if lensStrength.value < 0.002 && lensStrength.target == 0 { lensStrength.snap(0) }

    // Paste events: amber flashes (attack/decay on a spring), the lens bounce on yield and jam.
    let nozzle = f.nozzle ?? Self.restingNozzle(tank: f.tank)
    for ev in f.pasteEvents {
      switch ev.kind {
      case .yield:
        let at = ev.position ?? (f.lens?.centre ?? f.tank * 0.5)
        flashBank.fire(at: SIMD2<Float>(at), radius: 0.007, intensity: 0.75)
        if !reduce { lensBounce.velocity -= 2.4 }
      case .jam:
        let at = ev.position ?? (f.lens?.centre ?? f.tank * 0.5)
        flashBank.fire(at: SIMD2<Float>(at), radius: ev.position == nil && f.lens == nil ? 0.03 : 0.011, intensity: 1)
        if !reduce { lensBounce.velocity -= 3.6 }
      case .impact:
        let at = ev.position ?? f.tank * 0.5
        flashBank.fire(at: SIMD2<Float>(at), radius: 0.008, intensity: Float(min(max(ev.magnitude / 0.8, 0.25), 1)))
      case .tearOff:
        flashBank.fire(at: SIMD2<Float>(nozzle.position - SIMD2(0, nozzle.radius)), radius: 0.005, intensity: 0.6)
      }
    }
    if reduce {
      // Reduce Motion: no animated flashes or bounce.
      flashBank.clear()
      lensBounce.snap(0)
    } else {
      flashBank.step(springs.flash, dt: dt)
      lensBounce.target = 0
      lensBounce.step(springs.bounce, dt: dt)
    }

    // Echoes follow how fast the paste moves; they die away as it settles.
    let speed = f.stats.maxSpeed.isFinite ? f.stats.maxSpeed : 0
    let lensSpeed = f.lens.map { simd_length($0.velocity) } ?? 0
    let moving = max(speed, lensSpeed * 0.6)
    ghostAmount.target = CGFloat(Self.smoothstep(Self.ghostOnsetSpeed, Self.ghostFullSpeed, moving))
    ghostAmount.step(springs.ghosts, dt: dt)

    // The nozzle's mouth lights while the tube squeezes.
    mouthLight.target = nozzle.emitting ? 1 : 0
    if reduce { mouthLight.snap(mouthLight.target) } else { mouthLight.step(springs.mouth, dt: dt) }

    // Fluid options (the Solid look keeps Rheo's tuning; the hologram reads `options.hologram`).
    let p = f.params
    var o = FluidRenderOptions(
      diagnostic: v.layers.diagnostic, glow: 1, grain: Float(p[.grain]) * 2,
      tracers: v.layers.dyeLines ? Float(p[.tracers]) : 0, depth: Float(0.4 + 1.2 * p[.depth]),
      showParticles: v.layers.particles, speedRange: 0.5, keyLight: SIMD4(key, 1.1), fillLight: SIMD4(fill, 0.45),
      stressGlow: v.layers.stressLight ? Float(p[.glow] * p[.glow]) * 0.9 : 0, stressColour: TankHues.stress,
      environmentUp: up, droplets: true)
    o.style = hologram ? .hologram : .surface
    var h = FluidHologram()
    h.tilt = e
    h.time = context.time
    h.reduceMotion = reduce
    h.bandColours = HoloLooks.stripeColours
    h.bandGain = HoloLooks.bandGain
    h.scanlinePeriod = HoloLooks.scanlinePeriod
    h.scanlineDepth = HoloLooks.scanlineDepth
    h.shearColour = HoloPalette.cyan
    h.stressColour = HoloPalette.amber
    h.structureColour = HoloPalette.violet
    h.shearAmount = v.layers.stressLight ? 1 : 0
    h.ghostNear = HoloPalette.violet
    h.ghostFar = HoloPalette.magenta
    h.ghosts = reduce ? 0 : max(Float(ghostAmount.value), 0)
    h.ghostLife = 0.2
    h.iris = HoloPalette.iris
    let bounce = min(max(Float(lensBounce.value), -1), 1)
    let lensOn = hologram ? lensStrength.float : 0
    h.lensCentre = SIMD2<Float>(lensLast.centre)
    h.lensRadius = Float(lensLast.radius) * (1 + Self.lensBounceDepth * min(bounce, 0))
    h.lens = lensOn
    h.lensMagnification = Self.lensMagnification * (1 + 0.8 * abs(bounce))
    h.lensShift = Self.lensShift
    h.lensSplit = Self.lensSplit
    h.flashes = flashBank.flashes()
    if let m = f.magnet {
      h.magnet = m.position.map { SIMD2<Float>($0) }
      h.field = Float(min(m.fieldTesla / 0.3, 1))
    }
    h.pixelsPerPoint = max(context.pxScale, 1)
    if !debugPasses.cloud { h.cloudGain = 0 }
    o.hologram = h
    options = o
    lastOptions = o

    // Uniforms for the app fragments.
    let W = Float(context.drawableSize.x), H = Float(context.drawableSize.y)
    let o0 = context.viewProj * SIMD4<Float>(0, 0, 0, 1), o1 = context.viewProj * SIMD4<Float>(1, 0, 0, 1)
    let n0 = SIMD2(o0.x, o0.y) / max(o0.w, 1e-6), n1 = SIMD2(o1.x, o1.y) / max(o1.w, 1e-6)
    let originPx = SIMD2((n0.x * 0.5 + 0.5) * W, (0.5 - n0.y * 0.5) * H)
    let ppm = (n1.x - n0.x) * 0.5 * W
    tu.tank = SIMD4(Float(f.tank.x), Float(f.tank.y), ppm, context.time)
    tu.origin = SIMD4(originPx.x, originPx.y, W, H)
    tu.keyLight = o.keyLight
    tu.fillLight = o.fillLight
    tu.up = SIMD4(up, reduce ? 1 : 0)
    // Props read `fluid`: the hologram is light, never an opaque bath (props stay behind it).
    tu.fluid = hologram ? SIMD4(holo.body, 0.2) : SIMD4(look.glowGain > 0 ? SIMD3<Float>(0.9, 0.28, 0.04) : look.baseColour, look.opacity)
    let parallax = SIMD2(e.x, -e.y) * Self.gridParallax
    tu.tilt = SIMD4(e.x, e.y, parallax.x, parallax.y)
    let shake = Float(min(max(f.vibration.x / (17 * Gravity.g0), 0), 1))
    let phase = reduce ? 0 : context.time * 2 * .pi * 2.5
    let field = Float(min((f.magnet?.fieldTesla ?? 0) / 0.3, 1))
    tu.stage = SIMD4(shake, phase, field, Float(f.magnet?.position?.x ?? f.tank.x / 2))
    // The projector: the slit brightens a little while the tube squeezes (the projection is busy).
    tu.projector = SIMD4(1 + 0.25 * mouthLight.float, hologram ? 1 : 0.6, context.time, hologram ? 1 : 0)
    let dx = r.solver?.cellSize ?? 0.002
    tu.misc = SIMD4(Float(dx), r.surface?.threshold ?? 0.5, max(context.pxScale, 1), Self.deepParallax)
    tu.lens = SIMD4(h.lensCentre.x, h.lensCentre.y, h.lensRadius, lensOn)
    let shift = (reduce ? SIMD2<Float>.zero : e) * Self.lensShift
    tu.lensOptics = SIMD4(shift.x, shift.y, h.lensMagnification, Self.lensSplit)
    tu.nozzle = SIMD4(Float(nozzle.position.x), Float(nozzle.position.y), Float(nozzle.radius), mouthLight.float)
    tu.accent = SIMD4(holo.rim, nozzle.emitting ? 1 : 0)
    tu.field = .zero
  }

  /// The bounded, enhanced tilt e of Metro spec §13–14: gravity x and z against the reference captured at the first
  /// reading (×1.7, clamped to the unit disc, then e = 2g / (1 + |g|²)). Zero with Use tilt off or Reduce Motion.
  private func tiltTarget(_ v: ToothpasteViewState) -> SIMD2<Float> {
    if let t = debugTilt { return simd_length(t) > 1 ? simd_normalize(t) : t }
    guard !v.reduceMotion, v.layers.useTilt else {
      tiltReference = nil
      return .zero
    }
    let g = r.motion.last.gravity
    guard simd_length(g) > 0.5, g.x.isFinite, g.z.isFinite else { return .zero }
    let ref = tiltReference ?? SIMD2(g.x, g.z)
    tiltReference = ref
    var q = SIMD2<Float>(Float(1.7 * (g.x - ref.x)), Float(1.7 * (g.z - ref.y)))
    q = simd_clamp(q, SIMD2(repeating: -1), SIMD2(repeating: 1))
    if simd_length(q) > 1 { q = simd_normalize(q) }
    return 2 * q / (1 + simd_length_squared(q))
  }

  /// Where the engine puts the nozzle before its first frame (top centre, default bore): ToothpasteEngine.squeezeNozzle.
  static func restingNozzle(tank: SIMD2<Double>) -> NozzleState {
    let radius = SqueezeState.defaultNozzleDiameter * 0.5e-3
    return NozzleState(
      position: SIMD2(tank.x / 2, tank.y - radius - 0.002), radius: radius, emitting: false, speed: 0, stripes: 3,
      material: defaultMaterialID, extruded: 0)
  }

  private static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = min(max((x - a) / max(b - a, 1e-9), 0), 1)
    return t * t * (3 - 2 * t)
  }

  /// Zoomed in, the canvas region in drawable pixels (the world rectangle through the tank→clip transform); nil at
  /// zoom 1.
  private func regionScissor(_ context: LabFrameContext, _ v: ToothpasteViewState) -> MTLScissorRect? {
    guard v.tankView.zoom > 1.001 else { return nil }
    let w = v.tankView.worldRect
    let W = Double(context.drawableSize.x), H = Double(context.drawableSize.y)
    guard W > 0, H > 0 else { return nil }
    func pixel(_ x: Double, _ y: Double) -> SIMD2<Double> {
      let c = context.viewProj * SIMD4<Float>(Float(x), Float(y), 0, 1)
      let n = SIMD2(Double(c.x), Double(c.y)) / Double(max(c.w, 1e-6))
      return SIMD2((n.x * 0.5 + 0.5) * W, (0.5 - n.y * 0.5) * H)
    }
    let a = pixel(Double(w.minX), Double(w.maxY)), b = pixel(Double(w.maxX), Double(w.minY))
    let x0 = Int(max(min(a.x, b.x), 0).rounded(.down)), y0 = Int(max(min(a.y, b.y), 0).rounded(.down))
    let x1 = Int(min(max(a.x, b.x), W).rounded(.up)), y1 = Int(min(max(a.y, b.y), H).rounded(.up))
    guard x1 > x0, y1 > y0 else { return nil }
    return MTLScissorRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
  }

  // MARK: Compute

  func encodeCompute(_ cmd: MTLCommandBuffer, context: LabFrameContext, frame: ToothpasteFrame, view: ToothpasteViewState) {
    beginFrame(context, frame, view)
    guard let solver = r.solver, let surface = r.surface else { return }
    surface.encodePrepass(
      cmd, solver: solver, tankToClip: context.viewProj, drawableSize: context.drawableSize, options: options)
    if let s = surface.surfaceField {
      tu.field = s.rect
      tu.misc.y = s.threshold
    }
  }

  // MARK: Pass 1

  func encodeBehind(
    _ enc: MTLRenderCommandEncoder, uniforms: inout LabFrameUniforms, context: LabFrameContext, frame: ToothpasteFrame,
    view: ToothpasteViewState
  ) {
    beginFrame(context, frame, view)
    let always = context.depth.always
    enc.setFragmentBytes(&tu, length: MemoryLayout<ToothpasteTankUniforms>.stride, index: Int(LabFragmentApp.rawValue))
    // The chamber: projection volume + housing, one opaque quad well beyond the drawable's band.
    let reach = Self.housingReach
    if debugPasses.chamber {
      draw(chamber, enc, &uniforms, always) {
        $0.append(LabQuadInstance(
          rect: CGRect(x: -reach, y: -reach, width: frame.tank.x + 2 * reach, height: frame.tank.y + 2 * reach),
          color: F4(1, 1, 1, 1), z: -0.99))
      }
    }
    if let clip = regionScissor(context, view) { enc.setScissorRect(clip) }
    // The magnet in the projector's band, under the floor.
    if let m = frame.magnet, let mp = m.position {
      draw(magnet, enc, &uniforms, always) {
        $0.append(LabQuadInstance(rect: CGRect(x: mp.x - 0.0095, y: -0.0054, width: 0.019, height: 0.0040), color: F4(1, 1, 1, 1), z: -0.8))
      }
    }
    // Props behind the hologram (it is light: they show through it) or behind a translucent Solid paste.
    if hologram || materialOpacity < 0.5 {
      enc.setFragmentTexture(blank, index: 0)
      enc.setFragmentTexture(blank, index: 1)
      draw(propBehind, enc, &uniforms, always) { self.appendProps(frame, into: &$0) }
    }
  }

  // MARK: Pass 2

  func encodeScene(
    _ enc: MTLRenderCommandEncoder, uniforms: inout LabFrameUniforms, context: LabFrameContext, frame: ToothpasteFrame,
    view: ToothpasteViewState
  ) {
    beginFrame(context, frame, view)
    let always = context.depth.always
    let behind = context.targets.behind
    if let clip = regionScissor(context, view) { enc.setScissorRect(clip) }
    // The paste: the hologram over the chamber (the chamber already refracted itself under the lens, and the hologram's
    // shade refracts the paste with the same numbers), or the Solid look from the `behind` copy.
    if let surface = r.surface {
      if hologram {
        if debugPasses.hologram { surface.encodeHologramShade(enc, tankToClip: context.viewProj, time: context.time, options: options) }
      } else if let behind {
        surface.encodeShade(enc, behind: behind, tankToClip: context.viewProj, time: context.time, options: options)
      }
    }
    // encodeShade leaves its own buffers bound: set ours again.
    enc.setFragmentBytes(&uniforms, length: MemoryLayout<LabFrameUniforms>.stride, index: Int(LabFragmentFrame.rawValue))
    enc.setFragmentBytes(&tu, length: MemoryLayout<ToothpasteTankUniforms>.stride, index: Int(LabFragmentApp.rawValue))
    enc.setFragmentTexture(behind ?? blank, index: 0)
    enc.setFragmentTexture(r.surface?.surfaceField?.texture ?? blank, index: 1)
    // Solid look: MR fluid's oily steel gloss over its flat face.
    if !hologram, materialMetallic > 0.5, tu.field.z > 0 {
      draw(sheen, enc, &uniforms, always) {
        $0.append(LabQuadInstance(rect: self.tankRect(frame), color: F4(1, 1, 1, 1), z: 0.35))
      }
    }
    // Props in front of an opaque Solid paste (wet where it covers them), and the stir rod.
    draw(propFront, enc, &uniforms, always) { q in
      if !self.hologram && self.materialOpacity >= 0.5 { self.appendProps(frame, into: &q) }
      if let pd = frame.paddle {
        let skin = (self.r.solver?.colliderSkin ?? 1) * (self.r.solver?.cellSize ?? 0.002) * 0.5
        let hl = pd.halfLength + pd.radius + skin, rad = pd.radius + skin
        q.append(
          LabQuadInstance(
            rect: CGRect(x: pd.position.x - hl, y: pd.position.y - rad, width: 2 * hl, height: 2 * rad),
            color: F4(1, 1, 1, 1), z: 0.4, rotation: Float(pd.angle), cornerRadius: Float(rad), app: 40))
      }
    }
    // The tube nozzle, from the housing's top band down to its mouth.
    let nz = frame.nozzle ?? Self.restingNozzle(tank: frame.tank)
    let half = max(nz.radius * 3.2, 0.0038)
    let bottom = nz.position.y - nz.radius * 3.6
    draw(nozzleQuad, enc, &uniforms, always) {
      $0.append(LabQuadInstance(
        rect: CGRect(x: nz.position.x - half, y: bottom, width: 2 * half, height: frame.tank.y + 0.0032 - bottom),
        color: F4(1, 1, 1, 1), z: 0.6))
    }
    // A canvas finger (scripted touches, tests): a thin glass ring tinted by the stress and jamming under it.
    if let fg = frame.finger {
      let mpp = 1 / max(view.tankView.pointsPerMetre, 1)
      let w = 1.5 * mpp
      let half = fg.radius + 2.5 * w
      let tint = ringTint(frame.probe, tool: fg.tool)
      draw(ring, enc, &uniforms, always) {
        $0.append(
          LabQuadInstance(
            rect: CGRect(x: fg.position.x - half, y: fg.position.y - half, width: 2 * half, height: 2 * half),
            color: tint, z: 0.9, cornerRadius: Float(w)))
      }
    }
  }

  // MARK: Lines

  func buildLines(_ batch: inout LineBatch, context: LabFrameContext, frame f: ToothpasteFrame, view v: ToothpasteViewState) {
    beginFrame(context, f, v)
    // Rheometer cursor: a small amber ring with four ticks where the probe samples — only without the lens (the lens
    // readout is the UI's, beside the glass). With a canvas finger or the stir rod it sits on the probe; otherwise it
    // shows the strongest-sheared region dimmed while the paste there flows (eased between places).
    let lensDown = f.lens?.active == true
    let held = f.probe.fingerDown || f.paddle != nil
    let flowing = f.probe.shearRate.isFinite && f.probe.shearRate > Self.idleCursorRate
    let target: SIMD2<Double>? = v.layers.rheometerCursor && !lensDown && (held || flowing) ? f.probe.position : nil
    let k = Float(min(1, max(context.dt, 0) / Self.cursorEase))
    if let q = target {
      if held || cursor == nil || v.reduceMotion {
        cursor = q
      } else if let c = cursor {
        cursor = c + (q - c) * Double(k)
      }
    }
    let fadeTarget: Float = target == nil ? 0 : (held ? 1 : Self.idleCursorAlpha)
    cursorFade = held || v.reduceMotion ? fadeTarget : cursorFade + (fadeTarget - cursorFade) * k
    if cursorFade < 0.01 { cursor = target == nil ? nil : cursor }
    if let q = cursor, cursorFade >= 0.01 {
      let c = F3(Float(q.x), Float(q.y), 0.6)
      let amber = HoloPalette.amber * 1.2
      batch.ring(c, F3(1, 0, 0), F3(0, 1, 0), radius: 0.0012, color: amber, width: 1.2, alpha: cursorFade, segments: 28)
      for k in 0..<4 {
        let a = Float(k) * .pi / 2
        let d = F3(cos(a), sin(a), 0)
        batch.seg(c + d * 0.0017, c + d * 0.0026, amber, amber, alpha: cursorFade, width: 1.2)
      }
    }
    // Magnet: a bar on the floor where the magnet sits beneath it (north red, south blue, a chevron at its centre) and
    // faint dashed field arcs rising from it; brighter with the field.
    if let m = f.magnet, let mp = m.position {
      let cx = Float(mp.x)
      let k = 0.35 + 0.65 * tu.stage.z
      let y = Float(0.00055), hw = Float(0.0095)
      let north = F3(0.95, 0.22, 0.18), south = F3(0.25, 0.45, 1.0)
      batch.seg(F3(cx - hw, y, 0.55), F3(cx - 0.0004, y, 0.55), north, north, alpha: k, width: 3)
      batch.seg(F3(cx + 0.0004, y, 0.55), F3(cx + hw, y, 0.55), south, south, alpha: k, width: 3)
      let chev = HoloPalette.violet
      batch.seg(F3(cx - 0.0016, y + 0.0004, 0.55), F3(cx, y + 0.0022, 0.55), chev, chev, alpha: k, width: 1.6)
      batch.seg(F3(cx, y + 0.0022, 0.55), F3(cx + 0.0016, y + 0.0004, 0.55), chev, chev, alpha: k, width: 1.6)
      if tu.stage.z > 0.01 {
        let c = F3(cx, Float(-0.004), 0.5)
        let colour = HoloPalette.violet * 0.8
        for i in 0..<3 {
          let radius = Float(0.007) + 0.0045 * Float(i)
          batch.ring(
            c, F3(1, 0, 0), F3(0, 1, 0), radius: radius, color: colour, width: 1, alpha: tu.stage.z * (0.35 - 0.08 * Float(i)),
            segments: 40, start: 0.15, sweep: .pi - 0.3, dashed: true)
        }
      }
    }
    // Pour spout: a dashed ring where the pour lands.
    if let fg = f.finger, fg.tool == .pour {
      let c = F3(Float(fg.position.x), Float(fg.position.y), 0.6)
      batch.ring(c, F3(1, 0, 0), F3(0, 1, 0), radius: 0.0035, color: TankHues.forecast, width: 1.4, segments: 36, dashed: true)
    }
  }

  // MARK: Helpers

  private func tankRect(_ f: ToothpasteFrame) -> CGRect { CGRect(x: 0, y: 0, width: f.tank.x, height: f.tank.y) }

  private func draw(
    _ renderer: QuadRenderer?, _ enc: MTLRenderCommandEncoder, _ uniforms: inout LabFrameUniforms,
    _ depth: MTLDepthStencilState, _ fill: (inout [LabQuadInstance]) -> Void
  ) {
    guard let renderer else { return }
    quads.removeAll(keepingCapacity: true)
    fill(&quads)
    renderer.draw(enc, quads: quads, uniforms: &uniforms, depth: depth)
  }

  /// Props drawn `colliderSkin · Δx` larger than their bodies (the paste keeps one cell away from a collider).
  private func appendProps(_ f: ToothpasteFrame, into q: inout [LabQuadInstance]) {
    let skin = (r.solver?.colliderSkin ?? 1) * (r.solver?.cellSize ?? 0.002)
    for p in f.props {
      let kind: Float
      switch p.kind {
      case .steelBall: kind = 0
      case .glassMarble: kind = 1
      case .corkBlock: kind = 2
      case .die: kind = 3
      }
      let code = kind * 10 + Float(p.id % 6 + 1)
      switch p.shape {
      case .circle(let radius):
        let R = radius + skin
        q.append(
          LabQuadInstance(
            rect: CGRect(x: p.position.x - R, y: p.position.y - R, width: 2 * R, height: 2 * R), color: F4(1, 1, 1, 1),
            z: 0.3, rotation: Float(p.angle), cornerRadius: Float(R), app: code))
      case .box(let hw, let hh):
        let x = hw + skin, y = hh + skin
        let corner = p.kind == .die ? min(hw, hh) * 0.22 + skin : 0.0005 + skin
        q.append(
          LabQuadInstance(
            rect: CGRect(x: p.position.x - x, y: p.position.y - y, width: 2 * x, height: 2 * y), color: F4(1, 1, 1, 1),
            z: 0.3, rotation: Float(p.angle), cornerRadius: Float(corner), app: code))
      case .capsule(let hl, let radius):
        let x = hl + radius + skin, y = radius + skin
        q.append(
          LabQuadInstance(
            rect: CGRect(x: p.position.x - x, y: p.position.y - y, width: 2 * x, height: 2 * y), color: F4(1, 1, 1, 1),
            z: 0.3, rotation: Float(p.angle), cornerRadius: Float(y), app: 40))
      case .polygon:
        continue
      }
    }
  }

  /// The ring's tint: finger blue at rest → amber as the stress under it rises (log, 1 Pa … 3 kPa) → coral as the
  /// paste jams. Alpha = how strongly it is tinted (and how much it glows).
  private func ringTint(_ probe: ProbeReading, tool: FingerState.Tool) -> F4 {
    switch tool {
    case .pour: return F4(TankHues.forecast, 0.35)
    case .scoop: return F4(TankHues.warning, 0.4)
    case .prop: return F4(1, 1, 1, 0.15)
    case .probe:
      let s = Float(min(max(log10(1 + max(probe.stress, 0)) / 3.5, 0), 1))
      let jam = Float(min(max(probe.solidFraction, 0), 1))
      let calm = TankHues.finger, tense = TankHues.value, jammed = TankHues.warning
      let c = simd_mix(simd_mix(calm, tense, F3(repeating: s)), jammed, F3(repeating: jam))
      return F4(c, 0.25 + 0.75 * max(s, jam))
    }
  }
}
