// HoloChamber.swift — OWNER: UI (Documentation/REDESIGN-OWNERSHIP.md).
//
// The holo chamber, the screen's one primary object (REDESIGN.md §2–§3; Metro spec §7–§8, §13–§14). SwiftUI owns the
// chamber's frame and everything in front of it; HOLO's Metal view draws the hologram and the housing detail inside it.
//
// Layout contract with HOLO (progress-ui.md, "Chamber layout contract"): the MTKView is chamber-sized — the tank's
// inside (the canvas region, exactly the tank's aspect, floor on its bottom edge) plus a housing band of 2.5 mm left and
// right, 3.5 mm above and 5.5 mm below the floor, in tank millimetres at the chamber's scale. `model.canvasRegion` is
// the region in the MTKView's own points, so the renderer's camera maps the tank onto it and draws the housing in the
// band (world coordinates outside the tank). The MTKView is clipped to a rounded rectangle and wrapped in a thin metal
// rim (Metro metal recipe: housing shadow 0.8/22/16, 1.4 pt rim through white 0.36, 0.025, black, white 0.15).
//
// In front of the Metal view, as separate siblings (Metro layer order, spec §7): the lens dock (engraved ring), the
// isolated glass lens — decorative reticle ink through Metro's one-pass `instrumentLensOptics` refraction, native clear
// Liquid Glass at a constant 0.48, a faint rim arc that follows the tilt — and the transparent touch surface. The lens
// IS the finger: one finger anywhere in the chamber drives it (`ChamberMotion`), and its readout lives outside, fixed
// and unfiltered (MetroSignals.swift). Two fingers tilt (the simulator's stand-in for the phone; no zoom).

import LabKitCore
import LabKitRender
import LabKitUI
import SwiftUI
import simd

// MARK: - Geometry

/// The chamber's layout in points: the tank region inside a housing band, all in tank millimetres × `scale`.
struct ChamberGeometry: Equatable {
  /// Points per millimetre of tank (0: not laid out yet).
  var scale: CGFloat
  /// The tank's inside, mm.
  var tank: CGSize

  /// The housing band around the tank region, mm (the contract with HOLO).
  static let bandLeft: CGFloat = 2.5
  static let bandRight: CGFloat = 2.5
  static let bandTop: CGFloat = 3.5
  static let bandBottom: CGFloat = 5.5
  static let zero = ChamberGeometry(scale: 0, tank: CGSize(width: 71.2, height: 101.4))

  var isValid: Bool { scale > 0 && tank.width > 0 && tank.height > 0 }

  /// The MTKView's size: the region plus the band.
  var size: CGSize {
    CGSize(
      width: (tank.width + Self.bandLeft + Self.bandRight) * scale,
      height: (tank.height + Self.bandTop + Self.bandBottom) * scale)
  }

  /// The tank's inside in the MTKView's points (floor = bottom edge).
  var region: CGRect {
    CGRect(x: Self.bandLeft * scale, y: Self.bandTop * scale, width: tank.width * scale, height: tank.height * scale)
  }

  var cornerRadius: CGFloat { max(6, 3.2 * scale) }

  /// Drawn size over the real tank (×0.66 on the 15 Pro Max), given the display's millimetres per point.
  func displayScale(millimetresPerPoint: Double?) -> Double? {
    millimetresPerPoint.map { Double(scale) * $0 }
  }

  /// The largest chamber that fits `width` × `height` points.
  static func fitting(tank: SIMD2<Double>, width: CGFloat, height: CGFloat) -> ChamberGeometry {
    let t = CGSize(width: tank.x * 1000, height: tank.y * 1000)
    guard width > 0, height > 0, t.width > 0, t.height > 0 else { return ChamberGeometry(scale: 0, tank: t) }
    let sx = width / (t.width + bandLeft + bandRight)
    let sy = height / (t.height + bandTop + bandBottom)
    // Quantised to 1/100 pt per mm so the region's size (and the hub's TankView) does not flicker with layout noise.
    let s = (min(sx, sy) * 100).rounded(.down) / 100
    return ChamberGeometry(scale: max(s, 0), tank: t)
  }

  /// Chamber points → canvas-region points (what `ToothpasteModel.moveLens` takes).
  func regionPoint(fromChamber p: CGPoint) -> CGPoint {
    CGPoint(x: p.x - region.minX, y: p.y - region.minY)
  }

  /// Tank metres (origin bottom-left, y up) → chamber points.
  func chamberPoint(tank m: SIMD2<Double>) -> CGPoint {
    let r = region
    return CGPoint(x: r.minX + m.x * 1000 * scale, y: r.maxY - m.y * 1000 * scale)
  }

  func points(metres: Double) -> CGFloat { metres * 1000 * scale }

  /// Where the lens rests when no finger holds it: the region's top-left corner of the headspace (the nozzle is at the
  /// top centre, the paste on the floor).
  func dock(lensRadius r: CGFloat) -> CGPoint {
    let inset = r + max(6, 1.6 * scale)
    return CGPoint(x: region.minX + inset, y: region.minY + inset)
  }
}

// MARK: - The chamber

struct HoloChamber: View {
  let model: ToothpasteModel
  let motion: ChamberMotion
  let geometry: ChamberGeometry
  let material: MaterialInfo
  let actions: [CanvasRegion.Action]
  let onTouched: () -> Void

  var body: some View {
    let g = geometry
    let shape = RoundedRectangle(cornerRadius: g.cornerRadius, style: .continuous)
    ZStack(alignment: .topLeading) {
      // The housing's body and its shadow (the Metal view is opaque, so this only shows as the shadow and rim).
      shape
        .fill(Metro.Colour.gaugeHousing.color)
        .shadow(
          color: .black.opacity(Metro.Housing.housingShadow.opacity), radius: Metro.Housing.housingShadow.radius,
          y: Metro.Housing.housingShadow.y)
        .accessibilityHidden(true)
      LabRenderHost(scene: model)
        .frame(width: g.size.width, height: g.size.height)
        .clipShape(shape)
        .accessibilityHidden(true)
      LensDock(radius: motion.lensRadius)
        .position(g.dock(lensRadius: motion.lensRadius))
      LensGlassLayer(motion: motion)
      LiveChamberSurface(
        model: model, motion: motion, material: material, actions: actions, onTouched: onTouched)
      ChamberRim(cornerRadius: g.cornerRadius, motion: motion)
    }
    .frame(width: g.size.width, height: g.size.height)
    .onChange(of: geometry, initial: true) { _, g in
      model.canvasRegion = g.region
      motion.geometry = g
      ToothpasteFrameLog.record("chamber-region", g.region)
    }
  }
}

/// The chamber's transparent multi-touch and accessibility surface (LabKit's CanvasRegion over the whole chamber, so
/// touch locations are chamber points). Its VoiceOver value is the live sentence, so only this small view follows the
/// 10 Hz telemetry.
private struct LiveChamberSurface: View {
  let model: ToothpasteModel
  let motion: ChamberMotion
  let material: MaterialInfo
  let actions: [CanvasRegion.Action]
  let onTouched: () -> Void

  var body: some View {
    CanvasRegion(
      label: ToothpasteCopy.chamberLabel(material),
      value: ToothpasteCopy.chamberValue(model.telemetry, channels: model.channels, material: material, paused: model.paused),
      hint: ToothpasteCopy.chamberHint,
      actions: actions,
      identifier: "holo-chamber",
      onFrame: { ToothpasteFrameLog.record("chamber", $0) },
      onTouch: { t in
        let active = t.active
        if active.count == 1, let f = active.first {
          motion.touch(at: f.location)
          onTouched()
        } else {
          motion.release()
        }
      },
      onTwoFinger: { gesture in
        // Two fingers tilt the simulated phone; the chamber never zooms (it would crop the housing).
        var g = gesture
        g.scale = 1
        model.twoFinger(g)
      })
    .instrumentControlOwnsTouches(identifier: "holo-chamber")
  }
}

// MARK: - The glass lens

/// The lens at its spring position (`ChamberMotion`), sized by the hub's lens radius and its bounce.
private struct LensGlassLayer: View {
  let motion: ChamberMotion
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    let r = motion.lensRadius
    if r > 1 {
      InstrumentGlassLens(
        radius: r, radiusScale: motion.lensScale, tilt: motion.light, active: motion.lensActive,
        opticsEnabled: !reduceMotion && !reduceTransparency, reduceTransparency: reduceTransparency)
      .position(motion.lensCentre)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }
}

/// Metro's isolated clear lens (spec §6–§7, §13–§14), at the size of the engine's probe: decorative reticle ink through
/// the one-pass refraction shader, then native clear glass at a constant 0.48, then the faint rim arc. Nothing in it is
/// text or a value; the readout is outside the chamber.
struct InstrumentGlassLens: View {
  let radius: CGFloat
  var radiusScale: CGFloat = 1
  var tilt: SIMD2<Double> = .zero
  var active = false
  var opticsEnabled = true
  var reduceTransparency = false

  /// The decorative canvas reaches past the rim so the refraction has ink to sample at the edge.
  private var pad: CGFloat { 4 }
  private var side: CGFloat { 2 * radius + 2 * pad }
  /// Metro's optics are tuned to the primary object's diameter D, of which the lens is 0.76.
  private var gaugeDiameter: Double { Double(2 * radius) / Double(Metro.Gauge.lensDiameterRatio) }
  private var enhanced: (x: Double, y: Double) {
    LensRefraction.enhancedTilt(x: tilt.x, y: tilt.y, enabled: opticsEnabled)
  }

  var body: some View {
    let scaled = radius * radiusScale
    ZStack {
      LensReticle(radius: radius, active: active)
        .frame(width: side, height: side)
        .layerEffect(shader(radius: scaled), maxSampleOffset: CGSize(width: samplingBound, height: samplingBound),
                     isEnabled: opticsEnabled)
      Color.clear
        .frame(width: 2 * radius, height: 2 * radius)
        .glassEffect(.clear, in: .circle)
        .scaleEffect(radiusScale)
        .opacity(reduceTransparency ? Metro.Opacity.lensCompositeReduceTransparency : Metro.Opacity.lensComposite)
      if opticsEnabled { rimArc(radius: scaled) }
    }
    .frame(width: side, height: side)
    .transaction { $0.animation = nil }
  }

  private var samplingBound: CGFloat {
    LensRefraction.maximumShift(diameter: gaugeDiameter)
      + LensRefraction.maximumChannelSplit(diameter: gaugeDiameter) * Metro.Optics.channelOffsetFractionOfTotal
  }

  private func shader(radius r: CGFloat) -> Shader {
    ShaderLibrary.instrumentLensOptics(
      .float2(Float(side / 2), Float(side / 2)),
      .float(Float(r)),
      .float2(Float(enhanced.x), Float(enhanced.y)),
      .float(Float(LensRefraction.maximumShift(diameter: gaugeDiameter))),
      .float(Float(LensRefraction.rimStart)),
      .float(Float(LensRefraction.curvature)),
      .float(Float(LensRefraction.maximumChannelSplit(diameter: gaugeDiameter))),
      .float(Float(LensRefraction.chromaticInnerStart)),
      .float(Float(LensRefraction.chromaticPeakRadius)))
  }

  private func rimArc(radius r: CGFloat) -> some View {
    Canvas { context, size in
      let c = CGPoint(x: size.width / 2, y: size.height / 2)
      let rim = r * Metro.Optics.rimRadiusRatio
      let angle = Metro.Optics.rimAngleBase + enhanced.x * Metro.Optics.rimAngleTiltX + enhanced.y * Metro.Optics.rimAngleTiltY
      let a0 = angle - Metro.Optics.rimArcDegrees / 2, a1 = angle + Metro.Optics.rimArcDegrees / 2
      let arc = Path { p in
        p.addArc(center: c, radius: rim, startAngle: .degrees(a0), endAngle: .degrees(a1), clockwise: false)
      }
      let pa = CGPoint(x: c.x + rim * cos(a0 * .pi / 180), y: c.y + rim * sin(a0 * .pi / 180))
      let pb = CGPoint(x: c.x + rim * cos(a1 * .pi / 180), y: c.y + rim * sin(a1 * .pi / 180))
      context.stroke(
        arc,
        with: .linearGradient(
          Gradient(stops: [
            .init(color: .clear, location: 0), .init(color: .white.opacity(Metro.Opacity.rimLightPeak * 2.2), location: 0.5),
            .init(color: .clear, location: 1),
          ]), startPoint: pa, endPoint: pb),
        style: StrokeStyle(lineWidth: Metro.Stroke.glassRimLight, lineCap: .round))
    }
    .frame(width: side, height: side)
  }
}

/// The lens's decorative ink: a calibrated ring of 24 ticks, a fine centre cross and a cyan contact ring while the
/// glass is in the paste (constant outline; it only appears or not).
private struct LensReticle: View {
  let radius: CGFloat
  let active: Bool

  var body: some View {
    Canvas { context, size in
      let c = CGPoint(x: size.width / 2, y: size.height / 2)
      let cyan = Metro.Colour.instrumentCyan.color
      for i in 0..<24 {
        let a = Double(i) / 24 * 2 * .pi
        let long = i % 6 == 0
        let r0 = radius * (long ? 0.72 : 0.79), r1 = radius * 0.86
        var tick = Path()
        tick.move(to: CGPoint(x: c.x + r0 * cos(a), y: c.y + r0 * sin(a)))
        tick.addLine(to: CGPoint(x: c.x + r1 * cos(a), y: c.y + r1 * sin(a)))
        context.stroke(tick, with: .color(cyan.opacity(long ? 0.55 : 0.28)), lineWidth: long ? 0.9 : 0.6)
      }
      var cross = Path()
      let k = radius * 0.16
      cross.move(to: CGPoint(x: c.x - k, y: c.y))
      cross.addLine(to: CGPoint(x: c.x + k, y: c.y))
      cross.move(to: CGPoint(x: c.x, y: c.y - k))
      cross.addLine(to: CGPoint(x: c.x, y: c.y + k))
      context.stroke(cross, with: .color(.white.opacity(0.45)), lineWidth: 0.6)
      let ring = Path(ellipseIn: CGRect(x: c.x - radius * 0.93, y: c.y - radius * 0.93, width: radius * 1.86, height: radius * 1.86))
      context.stroke(ring, with: .color(cyan.opacity(active ? 0.7 : 0.22)), lineWidth: active ? 1.1 : 0.6)
    }
  }
}

/// Where the lens rests: an engraved ring with twelve index marks in the headspace's corner.
private struct LensDock: View {
  let radius: CGFloat

  var body: some View {
    Canvas { context, size in
      let c = CGPoint(x: size.width / 2, y: size.height / 2)
      let r = radius + 3
      context.stroke(
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
        with: .color(.black.opacity(0.55)), lineWidth: 2.2)
      context.stroke(
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
        with: .color(.white.opacity(0.12)), lineWidth: 0.5)
      for i in 0..<12 {
        let a = Double(i) / 12 * 2 * .pi
        var tick = Path()
        tick.move(to: CGPoint(x: c.x + (r + 2) * cos(a), y: c.y + (r + 2) * sin(a)))
        tick.addLine(to: CGPoint(x: c.x + (r + 5) * cos(a), y: c.y + (r + 5) * sin(a)))
        context.stroke(tick, with: .color(.white.opacity(i % 3 == 0 ? 0.3 : 0.12)), lineWidth: 0.6)
      }
    }
    .frame(width: 2 * radius + 16, height: 2 * radius + 16)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

/// The chamber's metal rim (Metro housing rim, 1.4 pt) with a recessed inner line; its light turns with the tilt.
private struct ChamberRim: View {
  let cornerRadius: CGFloat
  let motion: ChamberMotion

  var body: some View {
    let l = motion.light
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    let stops = Metro.Housing.housingRimStops
    ZStack {
      shape.strokeBorder(
        LinearGradient(
          stops: [
            .init(color: .white.opacity(stops[0]), location: 0), .init(color: .white.opacity(stops[1]), location: 0.35),
            .init(color: .black.opacity(0.9), location: 0.7), .init(color: .white.opacity(stops[3]), location: 1),
          ],
          startPoint: UnitPoint(x: 0.2 + 0.25 * l.x, y: 0 + 0.15 * l.y),
          endPoint: UnitPoint(x: 0.8 - 0.25 * l.x, y: 1 - 0.15 * l.y)),
        lineWidth: Metro.Stroke.housingRim)
      shape
        .inset(by: Metro.Stroke.housingRim + 0.4)
        .strokeBorder(.white.opacity(Metro.Housing.recessedFaceStrokeOpacity), lineWidth: Metro.Housing.recessedFaceStroke)
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
