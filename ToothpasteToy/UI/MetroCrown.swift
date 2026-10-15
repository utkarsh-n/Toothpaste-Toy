// MetroCrown.swift — OWNER: UI (Documentation/REDESIGN-OWNERSHIP.md).
//
// Metro's tactile crowns (spec §10, §15; the source app's `TempoCrownControl` and `CrownDetentTracker`): a knurled metal
// face (62 × 62, 40 knurls, concentric grooves, crown-base shadow resting 6/5, pressed 3/2) between native glass
// minus/plus buttons (44 × 44, 13 pt semibold, tint 0.08), with a steady caption row above and below.
//
// - Fine (8° detents, instrument cyan): Heat, one degree per accepted step.
// - Semantic (20° detents, instrument amber): Gravity, from one named world to the next (Zero-g · Moon · Mars · Earth ·
//   Jupiter).
// Relative angular travel accumulates across the ±180° seam; reversing needs 18 % extra travel; at most one step per
// update and 20 a second; a 7 pt centre exclusion. Every accepted step (face, button or VoiceOver) writes the domain
// once and plays its directional detent once; a step at a limit does neither. After release the face keeps a little of
// its spin (Wave spring, velocity hand-off) and settles onto the detent it is nearest: inertia that never adds a step.
//
// `SqueezeCrown` is the tube's cap at the nozzle (REDESIGN.md §4): no ± buttons (the floating Squeeze button is its
// accessible twin). Holding it squeezes; turning it faster squeezes faster; letting go tears the ribbon off.

import LabKitCore
import SwiftUI

// MARK: - Detent logic (pure)

/// Relative angular detents with direction hysteresis (Metro Station `CrownDetentTracker`, unchanged maths).
struct CrownDetentTracker: Equatable {
  let detentDegrees: Double
  let hysteresisDegrees: Double
  private(set) var residual = 0.0
  private(set) var lastDirection = 0
  private var previous: Double?

  init(detentDegrees: Double) {
    let spacing = detentDegrees.isFinite ? min(90, max(0.1, detentDegrees)) : Metro.Motion.fineDetentDegrees
    self.detentDegrees = spacing
    hysteresisDegrees = spacing * Metro.Motion.reversalHysteresisRatio
  }

  mutating func begin(angle: Double) {
    reset()
    if angle.isFinite { previous = Self.wrap(angle) }
  }

  mutating func reset() {
    previous = nil
    residual = 0
    lastDirection = 0
  }

  /// Accumulates relative motion; returns −1, 0 or +1.
  mutating func update(angle a: Double) -> Int {
    guard a.isFinite else { return 0 }
    let angle = Self.wrap(a)
    guard let p = previous else {
      previous = angle
      return 0
    }
    previous = angle
    residual += Self.wrap(angle - p)
    let direction = residual > 0 ? 1 : -1
    let reversing = lastDirection != 0 && direction != lastDirection
    let threshold = detentDegrees + (reversing ? hysteresisDegrees : 0)
    guard abs(residual) + 1e-9 >= threshold else { return 0 }
    residual -= Double(direction) * threshold
    residual = residual.truncatingRemainder(dividingBy: detentDegrees)
    if abs(residual) < 1e-9 { residual = 0 }
    lastDirection = direction
    return direction
  }

  static func wrap(_ angle: Double) -> Double {
    var r = angle.truncatingRemainder(dividingBy: 360)
    if r > 180 { r -= 360 }
    if r < -180 { r += 360 }
    return r
  }
}

/// At most one accepted step per 1/20 s; a pending notch waits rather than queueing a burst and is dropped on reversal.
struct DetentGate: Equatable {
  let minimumInterval = 1 / Metro.Motion.detentMaxHz
  private(set) var pending = 0
  private(set) var lastEmission = -Double.infinity

  mutating func begin() {
    pending = 0
    lastEmission = -.infinity
  }

  mutating func clearPending() { pending = 0 }

  mutating func update(visualDelta: Double?, detent: Int, now: Double, canStep: (Int) -> Bool) -> Int {
    if pending != 0, let d = visualDelta, d * Double(pending) < -0.5 { pending = 0 }
    if detent != 0 { pending = detent > 0 ? 1 : -1 }
    guard pending != 0, now - lastEmission >= minimumInterval else { return 0 }
    let direction = pending
    pending = 0
    guard canStep(direction) else { return 0 }
    lastEmission = now
    return direction
  }
}

/// The two crown roles and their detent feel (Metro §10, §15).
enum CrownRole: Equatable {
  case fine, semantic

  var detentDegrees: Double { self == .fine ? Metro.Motion.fineDetentDegrees : Metro.Motion.coarseDetentDegrees }
  var accent: Color { self == .fine ? Metro.Colour.instrumentCyan.color : Metro.Colour.instrumentAmber.color }

  func haptic(direction: Int) -> Metro.Haptic.Detent {
    switch (self, direction > 0) {
    case (.fine, true): Metro.Haptic.fineUp
    case (.fine, false): Metro.Haptic.fineDown
    case (.semantic, true): Metro.Haptic.semanticUp
    case (.semantic, false): Metro.Haptic.semanticDown
    }
  }
}

// MARK: - The metal face

/// The crown's metal (spec §6 metal recipe, §10). Decorative: the control speaks for it.
struct CrownFace: View {
  let accent: Color
  let rotation: Double
  var light: SIMD2<Double> = .zero
  var pressed = false
  var glyph: Glyph = .text("1")

  enum Glyph: Equatable {
    case text(String)
    case symbol(String)
    case none
  }

  var body: some View {
    ZStack {
      Circle()
        .fill(Metro.Colour.crownBase.color)
        .shadow(
          color: .black.opacity(Metro.Housing.crownShadowResting.opacity),
          radius: pressed ? Metro.Housing.crownShadowPressed.radius : Metro.Housing.crownShadowResting.radius,
          y: pressed ? Metro.Housing.crownShadowPressed.y : Metro.Housing.crownShadowResting.y)
      Canvas { context, size in draw(&context, d: min(size.width, size.height)) }
      switch glyph {
      case .text(let t):
        Text(t).font(.system(size: 17, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.9))
      case .symbol(let s):
        Image(systemName: s).font(.system(size: 16, weight: .medium)).foregroundStyle(.white.opacity(0.9))
      case .none:
        EmptyView()
      }
    }
    .accessibilityHidden(true)
  }

  private func draw(_ context: inout GraphicsContext, d: CGFloat) {
    let lx = light.x.isFinite ? min(1, max(-1, light.x)) : 0
    let ly = light.y.isFinite ? min(1, max(-1, light.y)) : 0
    let c = CGPoint(x: d / 2, y: d / 2)
    let k = d / 62
    context.fill(
      Path(ellipseIn: CGRect(x: 1.5 * k, y: 1.5 * k, width: d - 3 * k, height: d - 3 * k)),
      with: .linearGradient(
        Gradient(colors: [Metro.Colour.crownRimLight.color, Metro.Colour.crownRimDark.color, Metro.Colour.crownRimMid.color]),
        startPoint: CGPoint(x: (9 + lx * 8) * k, y: ly * 6 * k), endPoint: CGPoint(x: d - 8 * k, y: d)))
    for i in 0..<Metro.Housing.crownKnurls {
      let a = (Double(i) * 360 / Double(Metro.Housing.crownKnurls) + rotation) * .pi / 180
      var groove = Path()
      groove.move(to: CGPoint(x: c.x + cos(a) * d * 0.40, y: c.y + sin(a) * d * 0.40))
      groove.addLine(to: CGPoint(x: c.x + cos(a) * d * 0.475, y: c.y + sin(a) * d * 0.475))
      context.stroke(groove, with: .color(.black.opacity(0.65)), lineWidth: 1.5 * k)
      context.stroke(groove, with: .color(.white.opacity(0.2)), lineWidth: 0.45 * k)
    }
    let face = CGRect(x: 8 * k, y: 8 * k, width: d - 16 * k, height: d - 16 * k)
    context.fill(
      Path(ellipseIn: face),
      with: .linearGradient(
        Gradient(colors: [Metro.Colour.crownFaceLight.color, Metro.Colour.crownFaceDark.color]),
        startPoint: CGPoint(x: c.x - 12 * k + lx * 9 * k, y: (3 + ly * 8) * k), endPoint: CGPoint(x: d - 7 * k, y: d)))
    context.stroke(Path(ellipseIn: face), with: .color(.white.opacity(0.31)), lineWidth: 0.7)
    for inset in stride(from: 11.0, through: 16.0, by: 1.5) {
      let i = inset * k
      context.stroke(
        Path(ellipseIn: CGRect(x: i, y: i, width: d - 2 * i, height: d - 2 * i)), with: .color(.white.opacity(0.045)),
        lineWidth: 0.4)
    }
    let pa = (-90 + rotation) * .pi / 180
    var pointer = Path()
    pointer.move(to: CGPoint(x: c.x + cos(pa) * 16 * k, y: c.y + sin(pa) * 16 * k))
    pointer.addLine(to: CGPoint(x: c.x + cos(pa) * 21 * k, y: c.y + sin(pa) * 21 * k))
    context.stroke(pointer, with: .color(accent), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    var datum = Path()
    datum.move(to: CGPoint(x: c.x - 2.5 * k, y: 0.5))
    datum.addLine(to: CGPoint(x: c.x + 2.5 * k, y: 0.5))
    datum.addLine(to: CGPoint(x: c.x, y: 4 * k))
    datum.closeSubpath()
    context.fill(datum, with: .color(accent))
  }
}

// MARK: - A crown with ± buttons

/// One Metro crown control. `canStep` says whether a step would change the domain; `onStep` writes it (once per
/// accepted step) and `onDetent` plays the feedback for it.
struct InstrumentCrown: View {
  let role: CrownRole
  let caption: String
  let footer: String
  var glyph: CrownFace.Glyph = .text("1")
  var light: SIMD2<Double> = .zero
  let accessibilityLabel: String
  let accessibilityValue: String
  let accessibilityHint: String
  let increaseLabel: String
  let decreaseLabel: String
  let identifier: String
  let canStep: (Int) -> Bool
  let onStep: (Int) -> Void
  let onDetent: (Metro.Haptic.Detent) -> Void
  var onInteraction: (Bool) -> Void = { _ in }

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @ScaledMetric(relativeTo: .caption2) private var captionRow = Metro.Layout.crownCaptionRowHeight
  @State private var tracker = CrownDetentTracker(detentDegrees: 8)
  @State private var gate = DetentGate()
  @State private var dragging = false
  @State private var previousAngle: Double?
  @State private var rotation = SpringScalar(0)
  @State private var spin = 0.0
  @State private var lastSample = 0.0
  @State private var settleTask: Task<Void, Never>?

  var body: some View {
    VStack(spacing: 5) {
      Text(caption)
        .font(.system(.caption, design: .monospaced, weight: .medium))
        .tracking(1.2)
        .foregroundStyle(role.accent)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(minHeight: captionRow)
      GlassEffectContainer(spacing: 6) {
        HStack(spacing: 0) {
          stepButton(-1)
          face
          stepButton(1)
        }
      }
      Text(footer)
        .font(.system(.caption2, design: .monospaced))
        .foregroundStyle(.white.opacity(Metro.Opacity.supportingInk))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(minHeight: captionRow)
        .accessibilityHidden(true)
    }
    .frame(maxWidth: .infinity)
    .instrumentControlOwnsTouches(identifier: identifier)
    .onDisappear { finish(velocity: 0) }
    .onChange(of: scenePhase) { _, p in if p != .active { finish(velocity: 0) } }
  }

  private var face: some View {
    let d = Metro.Layout.crownDiameter
    return CrownFace(
      accent: role.accent, rotation: reduceMotion ? 0 : Double(rotation.value), light: reduceMotion ? .zero : light,
      pressed: dragging, glyph: glyph
    )
    .frame(width: d, height: d)
    .contentShape(Circle())
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { v in drag(v.location, d: d) }
        .onEnded { _ in finish(velocity: spin) })
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityValue(accessibilityValue)
    .accessibilityHint(accessibilityHint)
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment: tap(1)
      case .decrement: tap(-1)
      @unknown default: break
      }
    }
    .accessibilityIdentifier(identifier)
  }

  private func stepButton(_ direction: Int) -> some View {
    Button {
      tap(direction)
    } label: {
      Image(systemName: direction > 0 ? "plus" : "minus")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(role.accent)
        .frame(width: Metro.Layout.secondaryTargetMin, height: Metro.Layout.secondaryTargetMin)
        .glassEffect(.regular.tint(role.accent.opacity(Metro.Opacity.crownGlassTint)).interactive(), in: .circle)
    }
    .buttonStyle(.plain)
    .disabled(!canStep(direction))
    .accessibilityLabel(direction > 0 ? increaseLabel : decreaseLabel)
    .accessibilityIdentifier("\(identifier)-\(direction > 0 ? "plus" : "minus")")
  }

  private func drag(_ p: CGPoint, d: CGFloat) {
    let dx = Double(p.x - d / 2), dy = Double(p.y - d / 2)
    guard hypot(dx, dy) >= Double(Metro.Motion.crownCentreExclusion) else {
      tracker.reset()
      previousAngle = nil
      gate.clearPending()
      return
    }
    let angle = atan2(dy, dx) * 180 / .pi
    let now = ProcessInfo.processInfo.systemUptime
    if !dragging {
      dragging = true
      settleTask?.cancel()
      tracker = CrownDetentTracker(detentDegrees: role.detentDegrees)
      tracker.begin(angle: angle)
      previousAngle = angle
      gate.begin()
      lastSample = now
      spin = 0
      onInteraction(true)
      return
    }
    var delta: Double?
    if let a0 = previousAngle {
      let dd = CrownDetentTracker.wrap(angle - a0)
      delta = dd
      rotation.snap(rotation.value + CGFloat(dd))
      let dt = now - lastSample
      if dt > 0.001 { spin = dd / dt }
    }
    lastSample = now
    previousAngle = angle
    let detent = tracker.update(angle: angle)
    let accepted = gate.update(visualDelta: delta, detent: detent, now: now, canStep: canStep)
    if accepted != 0 { accept(accepted) }
  }

  private func tap(_ direction: Int) {
    guard canStep(direction) else { return }
    onInteraction(true)
    accept(direction)
    onInteraction(false)
    // The face turns one detent with the step, on a spring.
    settle(to: rotation.target + CGFloat(Double(direction) * role.detentDegrees), velocity: 0)
  }

  private func accept(_ direction: Int) {
    onStep(direction)
    onDetent(role.haptic(direction: direction))
  }

  /// Ends a drag: the face keeps a little of its spin and settles onto the nearest detent angle (no extra step).
  private func finish(velocity: Double) {
    guard dragging else { return }
    dragging = false
    tracker.reset()
    previousAngle = nil
    gate.clearPending()
    onInteraction(false)
    let carry = reduceMotion ? 0 : max(-180, min(180, velocity * 0.12))
    let target = ((Double(rotation.value) + carry) / role.detentDegrees).rounded() * role.detentDegrees
    settle(to: CGFloat(target), velocity: CGFloat(reduceMotion ? 0 : velocity * 0.4))
  }

  private func settle(to target: CGFloat, velocity: CGFloat) {
    settleTask?.cancel()
    guard !reduceMotion else {
      rotation.snap(target)
      return
    }
    rotation.target = target
    rotation.velocity = velocity
    settleTask = Task { @MainActor in
      var last = ContinuousClock.now
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(8))
        let now = ContinuousClock.now
        let dt = Double((now - last).components.attoseconds) / 1e18 + Double((now - last).components.seconds)
        last = now
        var r = rotation
        r.step(MetroSprings.detentSnap, dt: min(dt, 1.0 / 15))
        rotation = r
        if r.isSettled(0.02) {
          rotation.snap(target)
          break
        }
      }
    }
  }
}

// MARK: - Parameter crowns

/// Semantic stepping over a parameter's named detents (Gravity: Zero-g → Moon → Mars → Earth → Jupiter).
enum NamedDetents {
  /// The detents of `spec` at or above zero, in order.
  static func list(_ spec: ParamSpec) -> [Detent] { spec.detents.sorted { $0.value < $1.value } }

  /// The next named detent from `value` in `direction`, or nil at the end.
  static func next(_ spec: ParamSpec, from value: Double, direction: Int) -> Detent? {
    let all = list(spec)
    let eps = 1e-6 * max(1, abs(value))
    return direction > 0 ? all.first { $0.value > value + eps } : all.last { $0.value < value - eps }
  }

  /// The nearest named detent (by position along the sweep).
  static func nearest(_ spec: ParamSpec, to value: Double) -> Detent? {
    list(spec).min { abs(spec.position(of: $0.value) - spec.position(of: value)) < abs(spec.position(of: $1.value) - spec.position(of: value)) }
  }
}

/// Gravity on a semantic crown: amber, 20° detents, one named world per step.
struct GravityCrown: View {
  let store: ParamStore
  var light: SIMD2<Double> = .zero
  let onDetent: (Metro.Haptic.Detent) -> Void
  var onInteraction: (Bool) -> Void = { _ in }

  var body: some View {
    let spec = store.spec(.gravity)
    let value = store[.gravity]
    let here = spec.detent(at: value)?.label
    let previous = NamedDetents.next(spec, from: value, direction: -1)?.label ?? "—"
    let next = NamedDetents.next(spec, from: value, direction: 1)?.label ?? "—"
    InstrumentCrown(
      role: .semantic,
      caption: ToothpasteCopy.gravityCaption(here: here, value: spec.formatted(value)),
      footer: "\(previous) ⇄ \(next)",
      glyph: .symbol("globe.europe.africa.fill"),
      light: light,
      accessibilityLabel: ToothpasteCopy.gravityTitle,
      accessibilityValue: spec.accessibilityValue(value),
      accessibilityHint: ToothpasteCopy.gravityHint,
      increaseLabel: ToothpasteCopy.strongerGravity,
      decreaseLabel: ToothpasteCopy.weakerGravity,
      identifier: "crown-gravity",
      canStep: { NamedDetents.next(store.spec(.gravity), from: store[.gravity], direction: $0) != nil },
      onStep: { d in
        if let target = NamedDetents.next(store.spec(.gravity), from: store[.gravity], direction: d) {
          store[.gravity] = target.value
        }
      },
      onDetent: onDetent,
      onInteraction: onInteraction)
  }
}

/// Heat on a fine crown: cyan, 8° detents, one degree Celsius per step (lava's 1050–1200 °C range too).
struct HeatCrown: View {
  let store: ParamStore
  var light: SIMD2<Double> = .zero
  let onDetent: (Metro.Haptic.Detent) -> Void
  var onInteraction: (Bool) -> Void = { _ in }

  var body: some View {
    let spec = store.spec(.heat)
    let value = store[.heat]
    InstrumentCrown(
      role: .fine,
      caption: ToothpasteCopy.heatCaption(spec.formatted(value)),
      footer: ToothpasteCopy.heatFooter(named: spec.detent(at: value)?.label),
      glyph: .text("1"),
      light: light,
      accessibilityLabel: ToothpasteCopy.heatTitle,
      accessibilityValue: spec.accessibilityValue(value),
      accessibilityHint: ToothpasteCopy.heatHint,
      increaseLabel: ToothpasteCopy.warmer,
      decreaseLabel: ToothpasteCopy.cooler,
      identifier: "crown-heat",
      canStep: { d in
        let s = store.spec(.heat)
        return s.quantised(store[.heat] + Double(d) * max(s.step, 1)) != store[.heat]
      },
      onStep: { d in
        let s = store.spec(.heat)
        store[.heat] = s.quantised(store[.heat] + Double(d) * max(s.step, 1))
      },
      onDetent: onDetent,
      onInteraction: onInteraction)
  }
}

// MARK: - The Squeeze crown

/// The tube's knurled cap above the nozzle: hold it to squeeze, turn it (either way) to squeeze faster, let go to tear
/// the ribbon off. The face's angle and inertia live in `ChamberMotion`.
struct SqueezeCrown: View {
  let motion: ChamberMotion
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var previousAngle: Double?
  @State private var holding = false

  static let diameter: CGFloat = 62

  var body: some View {
    let d = Self.diameter
    CrownFace(
      accent: Metro.Colour.instrumentCyan.color, rotation: reduceMotion ? 0 : motion.squeezeAngle,
      light: reduceMotion ? .zero : motion.light, pressed: holding, glyph: .symbol("arrow.down.to.line.compact")
    )
    .frame(width: d, height: d)
    .contentShape(Circle())
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { v in drag(v.location, d: d) }
        .onEnded { _ in end() })
    .instrumentControlOwnsTouches(identifier: "crown-squeeze")
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(ToothpasteCopy.squeezeCrownLabel)
    .accessibilityValue(ToothpasteCopy.squeezeSpoken(rate: motion.model.squeeze.rate))
    .accessibilityHint(ToothpasteCopy.squeezeCrownHint)
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { squeezeBurst() }
    .accessibilityIdentifier("crown-squeeze")
    .onDisappear { end() }
  }

  private func drag(_ p: CGPoint, d: CGFloat) {
    let now = ProcessInfo.processInfo.systemUptime
    if !holding {
      holding = true
      motion.setSqueeze(.crown)
    }
    let dx = Double(p.x - d / 2), dy = Double(p.y - d / 2)
    guard hypot(dx, dy) >= Double(Metro.Motion.crownCentreExclusion) else {
      previousAngle = nil
      return
    }
    let angle = atan2(dy, dx) * 180 / .pi
    if let a0 = previousAngle { motion.crownTurned(by: CrownDetentTracker.wrap(angle - a0), at: now) }
    previousAngle = angle
  }

  private func end() {
    guard holding else { return }
    holding = false
    previousAngle = nil
    motion.crownReleased()
  }

  /// VoiceOver's activate: a 1.5 s squeeze, then the tear-off.
  private func squeezeBurst() {
    motion.setSqueeze(.button)
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(1.5))
      if motion.squeezeSource == .button { motion.setSqueeze(.none) }
    }
  }
}
