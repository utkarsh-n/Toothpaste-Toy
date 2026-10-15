// MetroMotion.swift — OWNER: UI (Documentation/REDESIGN-OWNERSHIP.md).
//
// Every interface motion on the Metro Station screen runs on Janum Trivedi's Wave springs (LabKit vendors Wave 0.3.4,
// MIT): `Spring(dampingRatio:response:)` with Wave's own integrator (`CGFloat.updateValue`), stepped here once per
// display frame in substeps of at most 1/240 s, so every motion is interruptible and keeps its velocity when its target
// moves (the velocity hand-off). Wave animates interface values only; the paste itself is LabKitMPM's physics.
//
// `ChamberMotion` is the screen's one motion clock (a CADisplayLink: 120 Hz while something moves, 30 Hz at rest):
// - the glass lens: it catches the finger, follows it on a stiff spring, and on release glides home to its dock with
//   the release velocity; every frame it writes the hub's lens (`moveLens`), so the engine's probe collider is exactly
//   the glass you see. A yield or jam bounces its radius (spring kick, 0.92…1.09, centre fixed: Metro §13).
// - the Squeeze crown: the face's angle, the turning speed (spring-smoothed) that sets the requested extrusion rate,
//   its inertia after release and the snap to a 20° detent; one detent tap per 20° of accepted travel.
// - the metal light: Metro's bounded screen tilt (spec §13: gain 1.7 about a reference captured at start) through a
//   critically damped spring; it moves only light on metal and the lens rim, never a readout or a control frame.
// - the channel history the pills draw (30 Hz) and the paste events' attack/decay for the tiles and pills.
// Views read the observed `lensCentre`, `lensScale`, `light` and `squeezeAngle`; TimelineViews read the rest
// (unobserved) at their own cadence.

import CoreGraphics
import Foundation
import LabKitCore
import QuartzCore
import UIKit
import Wave
import simd

// MARK: - Spring values

/// One spring-driven scalar, stepped with Wave's integrator.
struct SpringScalar: Equatable {
  var value: CGFloat
  var velocity: CGFloat = 0
  var target: CGFloat

  init(_ value: CGFloat) {
    self.value = value
    target = value
  }

  /// Advances by `dt` seconds toward `target` in substeps of at most 1/240 s (stable at the loop's 1/15 s cap).
  mutating func step(_ spring: WaveSpring, dt: Double) {
    guard dt > 0 else { return }
    guard spring.response > 0 else {
      snap(target)
      return
    }
    let n = max(1, Int((dt * 240).rounded(.up)))
    let h = dt / Double(n)
    for _ in 0..<n {
      let s = CGFloat.updateValue(spring: spring, value: value, target: target, velocity: velocity, dt: h)
      value = s.value
      velocity = s.velocity
    }
    if !value.isFinite || !velocity.isFinite { snap(target) }
  }

  mutating func snap(_ v: CGFloat) {
    value = v
    target = v
    velocity = 0
  }

  func isSettled(_ tolerance: CGFloat) -> Bool { abs(value - target) < tolerance && abs(velocity) < tolerance * 8 }
}

/// One spring-driven point (the lens), stepped with Wave's integrator.
struct SpringPoint: Equatable {
  var value: CGPoint
  var velocity: CGPoint = .zero
  var target: CGPoint

  init(_ value: CGPoint) {
    self.value = value
    target = value
  }

  mutating func step(_ spring: WaveSpring, dt: Double) {
    guard dt > 0 else { return }
    guard spring.response > 0 else {
      snap(target)
      return
    }
    let n = max(1, Int((dt * 240).rounded(.up)))
    let h = dt / Double(n)
    for _ in 0..<n {
      let s = CGPoint.updateValue(spring: spring, value: value, target: target, velocity: velocity, dt: h)
      value = s.value
      velocity = s.velocity
    }
    if !value.x.isFinite || !value.y.isFinite || !velocity.x.isFinite || !velocity.y.isFinite { snap(target) }
  }

  mutating func snap(_ p: CGPoint) {
    value = p
    target = p
    velocity = .zero
  }

  var distanceToTarget: CGFloat { hypot(value.x - target.x, value.y - target.y) }
  var speed: CGFloat { hypot(velocity.x, velocity.y) }
}

/// The screen's springs (Wave `Spring(dampingRatio:response:)`; response = one undamped period, s).
@MainActor enum MetroSprings {
  /// The lens follows the finger: stiff and nearly critical, so it stays under the fingertip with a glassy lag.
  static let lensFollow = WaveSpring(dampingRatio: 0.86, response: 0.055)
  /// The lens catching a finger that landed near it while it was in flight.
  static let lensCatch = WaveSpring(dampingRatio: 0.8, response: 0.12)
  /// Released: the lens glides home to its dock carrying the release velocity, with one soft overshoot.
  static let lensDock = WaveSpring(dampingRatio: 0.74, response: 0.42)
  /// The radius bounce on a yield or jam (underdamped, about half a second).
  static let lensBounce = WaveSpring(dampingRatio: 0.38, response: 0.3)
  /// Metal light and the lens rim arc follow the tilt.
  static let light = WaveSpring(dampingRatio: 1, response: 0.3)
  /// The Squeeze crown's turning speed (deg/s) as the extrusion rate reads it.
  static let crownSpeed = WaveSpring(dampingRatio: 1, response: 0.12)
  /// A crown face settling onto its nearest detent after release.
  static let detentSnap = WaveSpring(dampingRatio: 0.68, response: 0.32)
  /// Telemetry numerals and pill levels gliding to a new 10 Hz value.
  static let numerals = WaveSpring(dampingRatio: 1, response: 0.22)
}

// MARK: - Channel history and event pulses

/// The last three seconds of the three channels' levels (0…1), sampled at 30 Hz, for the pills' traces.
struct ChannelHistory {
  static let count = 90
  static let rate = 30.0
  private(set) var shear = [Double](repeating: 0, count: count)
  private(set) var stress = [Double](repeating: 0, count: count)
  private(set) var structure = [Double](repeating: 0, count: count)
  /// Index of the newest sample.
  private(set) var head = 0
  private(set) var filled = 0

  mutating func append(_ c: PasteChannels) {
    head = (head + 1) % Self.count
    shear[head] = c.shear.level
    stress[head] = c.stress.level
    structure[head] = c.structure.level
    filled = min(filled + 1, Self.count)
  }

  /// The channel's samples, newest first.
  func newestFirst(_ kind: PasteSignal) -> [Double] {
    let ring: [Double]
    switch kind {
    case .shear: ring = shear
    case .stress: ring = stress
    case .structure: ring = structure
    }
    return (0..<filled).map { ring[(head - $0 + Self.count) % Self.count] }
  }
}

/// The three signal channels (REDESIGN.md §4): shear γ̇ cyan, stress σ amber, structure λ / jam violet.
enum PasteSignal: String, CaseIterable, Sendable {
  case shear, stress, structure
}

/// When each kind of paste event last fired (media time) and how many have fired since the last refill.
struct EventPulses {
  private(set) var last: [PasteEvent.Kind: Double] = [:]
  private(set) var counts: [PasteEvent.Kind: Int] = [:]

  /// Amber attack/decay of an event tile or pill interior (Metro §11, retuned for paste events: a 30 ms attack and a
  /// 0.7 s smoothstep release, long enough to read).
  static let support = 0.7
  static let attack = 0.03

  mutating func fire(_ kind: PasteEvent.Kind, at time: Double) {
    last[kind] = time
    counts[kind, default: 0] += 1
  }

  mutating func resetCounts() { counts = [:] }

  func count(_ kind: PasteEvent.Kind) -> Int { counts[kind] ?? 0 }

  /// 0…1 energy of the kind's newest event at `time`.
  func energy(_ kind: PasteEvent.Kind, at time: Double) -> Double {
    guard let t0 = last[kind] else { return 0 }
    return Self.envelope(elapsed: time - t0)
  }

  static func envelope(elapsed: Double) -> Double {
    guard elapsed.isFinite, elapsed > 0, elapsed < support else { return 0 }
    func smooth(_ x: Double) -> Double {
      let t = min(1, max(0, x))
      return t * t * (3 - 2 * t)
    }
    if elapsed <= attack { return smooth(elapsed / attack) }
    return 1 - smooth((elapsed - attack) / (support - attack))
  }
}

// MARK: - The motion clock

/// A CADisplayLink target (the link retains it; it holds the clock weakly and retires the link once the clock is gone).
@MainActor private final class DisplayLinkProxy: NSObject {
  var onTick: ((CADisplayLink) -> Bool)?
  @objc func tick(_ link: CADisplayLink) {
    if onTick?(link) != true { link.invalidate() }
  }
}

@MainActor @Observable final class ChamberMotion {
  // MARK: Observed by the views

  /// The glass lens's centre in chamber coordinates (the MTKView's own points), and its radius scale (bounce).
  private(set) var lensCentre: CGPoint = .zero
  private(set) var lensScale: CGFloat = 1
  /// The lens is in the paste (the engine's collider is on).
  private(set) var lensActive = false
  /// Metro's bounded screen tilt for light on metal (each axis −1…1; zero under Reduce Motion).
  private(set) var light: SIMD2<Double> = .zero
  /// The Squeeze crown face's angle, degrees (visual).
  private(set) var squeezeAngle: Double = 0
  /// Who is squeezing (the crown, the floating Squeeze button, a screenshot script) or nobody.
  private(set) var squeezeSource: SqueezeSource = .none

  enum SqueezeSource: Equatable { case none, crown, button, script }

  // MARK: Configuration

  @ObservationIgnored let model: ToothpasteModel
  @ObservationIgnored var geometry: ChamberGeometry = .zero {
    didSet {
      guard geometry != oldValue, geometry.isValid else { return }
      // The dock moved (first layout, larger text): a resting lens goes with it.
      if finger == nil, !oldValue.isValid || lens.distanceToTarget < 0.5 {
        lens.snap(dock)
        lensCentre = dock
      }
    }
  }
  @ObservationIgnored var reduceMotion = false
  /// Called once per accepted 20° of Squeeze crown travel (the screen plays the detent).
  @ObservationIgnored var onSqueezeDetent: (() -> Void)?

  // MARK: Internal state

  @ObservationIgnored private var lens = SpringPoint(.zero)
  @ObservationIgnored private var finger: CGPoint?
  @ObservationIgnored private var caught = false
  @ObservationIgnored private var wroteActive = false
  @ObservationIgnored private var bounce = SpringScalar(1)
  @ObservationIgnored private var lastEventID = 0
  @ObservationIgnored private var lightX = SpringScalar(0)
  @ObservationIgnored private var lightY = SpringScalar(0)
  @ObservationIgnored private var tiltReference: SIMD2<Double>?
  @ObservationIgnored private var crownSpeed = SpringScalar(0)
  @ObservationIgnored private var lastCrownSample = -Double.infinity
  @ObservationIgnored private var crownTravel = 0.0
  @ObservationIgnored private var lastDetentTime = -Double.infinity
  @ObservationIgnored private var spinVelocity = 0.0
  @ObservationIgnored private var spinSnap: SpringScalar?
  @ObservationIgnored private var historyClock = 0.0
  @ObservationIgnored private var link: CADisplayLink?
  @ObservationIgnored private var lastTime: CFTimeInterval?
  @ObservationIgnored private var busyRate = true
  @ObservationIgnored private var demo: Task<Void, Never>?

  /// Unobserved, read by TimelineViews: the channel history and the paste events' pulses.
  @ObservationIgnored private(set) var history = ChannelHistory()
  @ObservationIgnored private(set) var pulses = EventPulses()
  /// Unobserved, read by TimelineViews: the pills' levels and the telemetry numerals, each gliding on a Wave spring to
  /// the newest value (per frame for the levels, 10 Hz for the numerals).
  @ObservationIgnored private(set) var levels = [SpringScalar(0), SpringScalar(0), SpringScalar(0)]
  @ObservationIgnored private(set) var viscosityLog = SpringScalar(-3)
  @ObservationIgnored private(set) var tiltDegrees = SpringScalar(0)
  @ObservationIgnored private var numeralsPrimed = false

  /// Squeeze tuning: holding the crown still squeezes at `holdRate`; turning adds `rateGain` mm/s per °/s.
  static let holdRate = 10.0
  static let rateGain = 40.0 / 360.0
  /// The press-and-hold Squeeze button's rate, mm/s.
  static let buttonRate = 40.0
  /// One detent of the Squeeze crown, degrees (Metro's semantic spacing).
  static let squeezeDetent = 20.0

  init(model: ToothpasteModel) {
    self.model = model
  }

  // MARK: Lifecycle

  func start() {
    guard link == nil else { return }
    let proxy = DisplayLinkProxy()
    proxy.onTick = { [weak self] link in
      guard let self else { return false }
      self.tick(link)
      return true
    }
    let l = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:)))
    l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
    l.add(to: .main, forMode: .common)
    link = l
    lastTime = nil
    tiltReference = nil
  }

  func stop() {
    link?.invalidate()
    link = nil
    demo?.cancel()
    demo = nil
    release()
    setSqueeze(.none)
    lightX.snap(0)
    lightY.snap(0)
    light = .zero
  }

  // MARK: Lens input (chamber coordinates)

  var dock: CGPoint { geometry.dock(lensRadius: lensRadius) }
  var lensRadius: CGFloat { geometry.points(metres: model.lens.radius) }

  /// A finger landed or moved in the chamber.
  func touch(at p: CGPoint) {
    guard geometry.isValid else { return }
    if finger == nil {
      // Landing near the glass (it may be gliding home): catch it, keeping its velocity. Elsewhere: the glass appears
      // under the fingertip at once, so a quick tap still pokes, with a small pop of its radius.
      if hypot(lens.value.x - p.x, lens.value.y - p.y) < lensRadius * 2.5 {
        caught = false
      } else {
        lens.snap(p)
        caught = true
        if !reduceMotion { bounce.velocity -= 1.2 }
      }
    }
    finger = p
    wake()
  }

  /// The finger lifted (or a second finger arrived): the glass leaves the paste and glides home.
  func release() {
    finger = nil
    caught = false
    wake()
  }

  // MARK: Squeeze input

  /// Starts or stops squeezing from one source (the crown and the button never fight: the newest wins).
  func setSqueeze(_ source: SqueezeSource) {
    squeezeSource = source
    if source == .none {
      crownSpeed.snap(0)
      writeRate(0)
    } else if source == .button || source == .script {
      writeRate(Self.buttonRate)
    } else {
      writeRate(Self.holdRate)
    }
    wake()
  }

  /// The crown turned by `delta` degrees at media time `time` (while held).
  func crownTurned(by delta: Double, at time: Double) {
    guard delta.isFinite else { return }
    squeezeAngle += delta
    spinSnap = nil
    let dt = time - lastCrownSample
    if dt > 0.001, dt < 0.2 {
      crownSpeed.target = min(abs(delta) / dt, 1440)
      spinVelocity = delta / dt
    }
    lastCrownSample = time
    crownTravel += abs(delta)
    if crownTravel >= Self.squeezeDetent {
      crownTravel = crownTravel.truncatingRemainder(dividingBy: Self.squeezeDetent)
      // At most 20 detents a second (Metro §15), no catch-up burst.
      if time - lastDetentTime >= 1 / Metro.Motion.detentMaxHz {
        lastDetentTime = time
        onSqueezeDetent?()
      }
    }
    wake()
  }

  /// The crown was let go: squeezing stops (the ribbon tears off) and the face spins down onto a detent.
  func crownReleased() {
    if squeezeSource == .crown { setSqueeze(.none) }
    crownTravel = 0
    if reduceMotion { spinVelocity = 0 }
  }

  // MARK: Events

  func resetEventCounts() { pulses.resetCounts() }

  // MARK: Screenshot scripts

  /// `-lensDemo`: a scripted finger sweeps the lens through the lower chamber in a slow figure-eight, forever.
  func runLensDemo() {
    demo?.cancel()
    demo = Task { @MainActor [weak self] in
      let t0 = CACurrentMediaTime()
      while !Task.isCancelled, let self {
        let g = self.geometry
        if g.isValid {
          let t = CACurrentMediaTime() - t0
          let r = g.region
          let x = r.midX + r.width * 0.3 * sin(t * 0.9)
          let y = r.maxY - r.height * (0.16 + 0.07 * sin(t * 1.8))
          self.touch(at: CGPoint(x: x, y: y))
        }
        try? await Task.sleep(for: .milliseconds(16))
      }
    }
  }

  /// `-squeezeDemo`: squeezes continuously with the crown turning, for pictures.
  func runSqueezeDemo() {
    setSqueeze(.script)
    demo?.cancel()
    demo = Task { @MainActor [weak self] in
      while !Task.isCancelled, let self {
        self.squeezeAngle += 3
        try? await Task.sleep(for: .milliseconds(16))
      }
    }
  }

  // MARK: The frame

  private func wake() {
    if !busyRate, let link {
      busyRate = true
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
    }
  }

  private func tick(_ link: CADisplayLink) {
    let now = link.timestamp
    let dt = min(max(now - (lastTime ?? now), 0), 1.0 / 15)
    lastTime = now
    stepLens(dt)
    stepSqueeze(dt, now: now)
    stepLight(dt)
    scanEvents(now: now)
    stepNumerals(dt)
    historyClock += dt
    if historyClock >= 1 / ChannelHistory.rate {
      historyClock = historyClock.truncatingRemainder(dividingBy: 1 / ChannelHistory.rate)
      history.append(model.live.channels)
    }
    let busy = finger != nil || !lens.value.equalTo(lens.target) || lens.speed > 0.5 || !bounce.isSettled(0.002)
      || squeezeSource != .none || abs(spinVelocity) > 0.5 || spinSnap != nil
    if busy != busyRate {
      busyRate = busy
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: busy ? 120 : 30)
    }
  }

  private func stepLens(_ dt: Double) {
    guard geometry.isValid else { return }
    if let f = finger {
      lens.target = f
      if reduceMotion {
        lens.snap(f)
        caught = true
      } else {
        lens.step(caught ? MetroSprings.lensFollow : MetroSprings.lensCatch, dt: dt)
        if !caught, lens.distanceToTarget < lensRadius * 0.9 { caught = true }
      }
    } else {
      lens.target = dock
      if reduceMotion { lens.snap(dock) } else { lens.step(MetroSprings.lensDock, dt: dt) }
      if lens.distanceToTarget < 0.05, lens.speed < 0.5 { lens.snap(dock) }
    }
    let active = finger != nil && caught
    if active || wroteActive {
      model.moveLens(to: geometry.regionPoint(fromChamber: lens.value), active: active, timestamp: CACurrentMediaTime())
    }
    wroteActive = active
    if lensActive != active { lensActive = active }
    if hypot(lensCentre.x - lens.value.x, lensCentre.y - lens.value.y) > 0.05 { lensCentre = lens.value }
    if reduceMotion {
      bounce.snap(1)
    } else {
      bounce.target = 1
      bounce.step(MetroSprings.lensBounce, dt: dt)
    }
    let scale = min(max(bounce.value, CGFloat(Metro.Gauge.radiusScaleRange.lowerBound)),
                    CGFloat(Metro.Gauge.radiusScaleRange.upperBound))
    if abs(scale - lensScale) > 0.0005 { lensScale = scale }
  }

  private func stepSqueeze(_ dt: Double, now: Double) {
    if squeezeSource == .crown {
      if now - lastCrownSample > 0.07 { crownSpeed.target = 0 }
      crownSpeed.step(MetroSprings.crownSpeed, dt: dt)
      writeRate(min(Self.holdRate + Self.rateGain * Double(max(crownSpeed.value, 0)), SqueezeState.maxRate))
    } else if squeezeSource == .none, !reduceMotion {
      // Inertia: the face keeps turning a little after release, then settles onto the nearest detent.
      if abs(spinVelocity) > 25 {
        squeezeAngle += spinVelocity * dt
        spinVelocity *= exp(-dt / 0.28)
      } else if spinVelocity != 0 {
        spinVelocity = 0
        var s = SpringScalar(CGFloat(squeezeAngle))
        s.target = CGFloat((squeezeAngle / Self.squeezeDetent).rounded() * Self.squeezeDetent)
        spinSnap = s
      }
      if var s = spinSnap {
        s.step(MetroSprings.detentSnap, dt: dt)
        squeezeAngle = Double(s.value)
        spinSnap = s.isSettled(0.01) ? nil : s
      }
    }
  }

  private func writeRate(_ rate: Double) {
    let r = max(0, rate)
    let current = model.squeeze.rate
    if (r == 0 && current != 0) || abs(r - current) >= 0.4 { model.squeeze.rate = r }
  }

  private func stepLight(_ dt: Double) {
    guard !reduceMotion else {
      if light != .zero { light = .zero }
      return
    }
    let g = model.resources.motion.last.gravity
    let sample = SIMD2(g.x, g.z)
    guard sample.x.isFinite, sample.y.isFinite else { return }
    if tiltReference == nil { tiltReference = sample }
    let target = simd_clamp((sample - tiltReference!) * Metro.Motion.gravityGain, SIMD2(repeating: -1), SIMD2(repeating: 1))
    lightX.target = CGFloat(target.x)
    lightY.target = CGFloat(target.y)
    lightX.step(MetroSprings.light, dt: dt)
    lightY.step(MetroSprings.light, dt: dt)
    let v = SIMD2(Double(lightX.value), Double(lightY.value))
    if simd_length(v - light) > 0.01 { light = v }
  }

  private func stepNumerals(_ dt: Double) {
    let c = model.live.channels
    let targets = [c.shear.level, c.stress.level, c.structure.level]
    for i in 0..<3 {
      levels[i].target = CGFloat(targets[i].isFinite ? targets[i] : 0)
      if reduceMotion { levels[i].snap(levels[i].target) } else { levels[i].step(MetroSprings.numerals, dt: dt) }
    }
    let t = model.telemetry
    let eta = t.viscosity > 0 && t.viscosity.isFinite ? log10(t.viscosity) : -3
    viscosityLog.target = CGFloat(eta)
    tiltDegrees.target = CGFloat(t.tiltDegrees.isFinite ? t.tiltDegrees : 0)
    if !numeralsPrimed || reduceMotion {
      numeralsPrimed = t.particles > 0
      viscosityLog.snap(viscosityLog.target)
      tiltDegrees.snap(tiltDegrees.target)
    } else {
      viscosityLog.step(MetroSprings.numerals, dt: dt)
      tiltDegrees.step(MetroSprings.numerals, dt: dt)
    }
  }

  /// A channel's spring-smoothed level, 0…1.
  func level(_ s: PasteSignal) -> Double {
    let i = s == .shear ? 0 : s == .stress ? 1 : 2
    return min(max(Double(levels[i].value), 0), 1)
  }

  private func scanEvents(now: Double) {
    for e in model.live.recentEvents where e.id > lastEventID {
      lastEventID = e.id
      pulses.fire(e.kind, at: now)
      guard !reduceMotion else { continue }
      switch e.kind {
      case .yield: bounce.velocity += 1.4
      case .jam: bounce.velocity += 2.2
      case .tearOff, .impact: break
      }
    }
  }
}
