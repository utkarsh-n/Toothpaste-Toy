// TouchTools.swift — OWNER: PLAY (was PHYS; Documentation/REDESIGN-OWNERSHIP.md).
//
// One-finger tools in the tank and the scripted fingers:
//   Probe   a kinematic circle collider (radius = the Finger knob) that chases the touch. It is force-limited: a
//           fingertip pushes with at most `pushPressure` over its diameter × the tank gap, so the fluid's reaction
//           (MPMStats.bodyImpulses[0], 1–2 frames old) slows it down. Liquid barely notices; jammed oobleck, a
//           magnetised MR fluid, lava or Silly Putty stop it, and it sinks on as they creep or melt.
//           The disc grows from a quarter size over 40 ms where it lands, so a touch inside the fluid does not
//           project a whole fingertip of fluid out in one substep.
//   Tap     touch-up within 0.25 s and 3 mm: a poke impulse, a short jab straight down from the tap point.
//   Swipe   faster than 0.8 m/s: a punch event (the collider's speed is what jams oobleck).
//   Pour    Pour mode: the drag carries an emitter of the pour material.
//   Scoop   Scoop mode: the drag carries a drain (the solver deletes the particles inside it), 0.75 × the finger.
//   Prop    a touch that starts on a dynamic prop drags it (Box2D mouse joint).
//   Magnet  a touch that starts on the magnet marker (the floor under the virtual magnet) slides the magnet.
// Scripts (`-fakeTouch`, canvas actions, experiments, mic kicks) drive the same finger; real touches win.

import Foundation
import simd
import LabKitCore
import LabKitRigid

struct TouchTools {
  enum Mode: Equatable { case probe, pour, scoop, prop(RigidBodyID), magnet }

  struct Finger {
    var id: Int
    var mode: Mode
    /// Latest touch position (m).
    var position: SIMD2<Double>
    /// Collider centre at the start of the next frame (m): lags the touch when the fluid resists.
    var collider: SIMD2<Double>
    var start: SIMD2<Double>
    var downAt: Double
    var lastTimestamp: Double
    /// Real finger velocity from touch timestamps, m/s.
    var velocity: SIMD2<Double> = .zero
    var punched = false
    /// Seconds of simulated time since the collider appeared (radius ramp).
    var age = 0.0
    /// Smoothed resisting force along the motion, N; current speed limit, m/s.
    var resist = 0.0
    var speedLimit = TouchTools.maxSpeed
    /// Direction of the collider's last motion (for the probe), unit or zero.
    var heading: SIMD2<Double> = .zero
  }

  /// A scripted straight jab: down from `from` to `to` at `speed`, hold, then lift.
  struct Jab {
    var start: Double
    var from: SIMD2<Double>
    var to: SIMD2<Double>
    var speed: Double
    var hold: Double
    var duration: Double { simd_length(to - from) / max(speed, 0.01) }
  }

  /// A scripted path: positions at times (real seconds, relative to `start`); nil entries lift the finger.
  struct Path {
    var start: Double
    var points: [(t: Double, p: SIMD2<Double>)]
    func position(at now: Double) -> SIMD2<Double>?? {
      let t = now - start
      guard let first = points.first, let last = points.last else { return .some(nil) }
      if t < first.t { return .some(nil) }
      if t > last.t { return nil }  // finished
      for i in 1..<points.count where t <= points[i].t {
        let a = points[i - 1], b = points[i]
        let u = (t - a.t) / max(b.t - a.t, 1e-9)
        return .some(a.p + (b.p - a.p) * u)
      }
      return .some(last.p)
    }
  }

  var finger: Finger?
  var jab: Jab?
  var path: Path?
  let script: FakeTouchScript?
  /// Events since the last frame.
  var events: [SimEvent] = []
  /// Where a magnet drag wants the magnet (tank x, m), consumed by the engine.
  var magnetTarget: Double?
  /// The engine's real-time clock at the latest frame (s since the engine started). Jabs and paths run on this clock;
  /// touch timestamps are UITouch's seconds since boot, a different clock, and only ever compared with each other.
  private(set) var now = 0.0

  /// Real-finger thresholds.
  static let punchSpeed = 0.8  // m/s
  static let tapTime = 0.25  // s
  static let tapTravel = 0.003  // m
  /// The hardest a fingertip pushes, Pa, over its diameter × the tank gap (0.64 N for an 8 mm finger in a 10 mm gap).
  /// Measured on the GPU solver, a kinematic 8 mm finger meets: water 0.2 kPa, honey 0.9–1.7 kPa, toothpaste 1.4–1.6,
  /// slime 3.7–4.1, oobleck 0.2 kPa at 2 cm/s but 7 kPa at 0.5 m/s, lava 29–63 kPa, Silly Putty 36–40 kPa.
  static let pushPressure = 4_000.0
  /// The collider never moves faster than this (m/s of simulated time).
  static let maxSpeed = 3.0
  /// Slowest crawl when the fluid resists: a stopped finger still sinks this fast (m/s).
  static let minSpeed = 0.002
  /// Radius ramp when the collider appears, s.
  static let growTime = 0.04
  /// Smoothing of the measured resistance, s.
  static let resistTime = 0.01
  /// Recovery of the speed limit once the fluid gives way: e-folding time (s) and a steady ramp (m/s²).
  static let recoverTime = 0.08
  static let recoverAcceleration = 0.3

  init(script: FakeTouchScript?) { self.script = script }

  // MARK: Real touches

  mutating func handle(
    _ t: TankTouch, mode: ShelfMode, rigid: RigidWorld, pourMaterial: MaterialID, magnetMarker: SIMD2<Double>?
  ) {
    switch t.phase {
    case .began:
      guard finger == nil || finger?.id == FakeTouchScript.touchID else { return }
      jab = nil
      path = nil
      var m: Mode = mode == .pour ? .pour : (mode == .scoop ? .scoop : .probe)
      if let marker = magnetMarker, abs(t.position.x - marker.x) < 0.008, t.position.y < marker.y + 0.010 {
        m = .magnet
      } else if let body = rigid.query(point: t.position, radius: 0.002), rigid.kind(body) == .dynamic,
        rigid.beginDrag(body, at: t.position)
      {
        m = .prop(body)
      }
      finger = Finger(
        id: t.id, mode: m, position: t.position, collider: t.position, start: t.position, downAt: t.timestamp,
        lastTimestamp: t.timestamp)
      events.append(.touchDown)
      if m == .pour { events.append(.pourStarted(pourMaterial)) }
      if m == .magnet { magnetTarget = t.position.x }
    case .moved:
      guard var f = finger, f.id == t.id else { return }
      let dtTouch = t.timestamp - f.lastTimestamp
      if dtTouch > 1e-4 {
        let v = (t.position - f.position) / dtTouch
        f.velocity += (v - f.velocity) * 0.5
      }
      f.position = t.position
      f.lastTimestamp = t.timestamp
      switch f.mode {
      case .prop: rigid.updateDrag(to: t.position)
      case .magnet: magnetTarget = t.position.x
      case .probe:
        if !f.punched, simd_length(f.velocity) > Self.punchSpeed {
          f.punched = true
          events.append(.punch(t.position))
        }
      case .pour, .scoop: break
      }
      finger = f
    case .ended:
      guard let f = finger, f.id == t.id else { return }
      if case .prop = f.mode { rigid.endDrag() }
      let quick = t.timestamp - f.downAt < Self.tapTime && simd_length(t.position - f.start) < Self.tapTravel
      finger = nil
      events.append(.touchUp)
      if quick, f.mode == .probe {
        // A quick tap: a poke impulse, the fingertip jabbed 10 mm down from where it landed. On the engine's clock, not
        // the touch's: scheduled at the boot-clock timestamp, the jab started days "in the future" and drove the
        // scripted finger up out of the tank instead of down (the tests' touch clock happened to equal the engine's).
        scheduleJab(at: f.start, depth: 0.010, speed: 0.5, now: now, rise: 0.002, hold: 0.04)
        events.append(.poke(f.start))
      }
    }
  }

  /// Lifts any finger (a second finger arrived, the material changed, an experiment started).
  mutating func cancel(rigid: RigidWorld) {
    if let f = finger, case .prop = f.mode { rigid.endDrag() }
    if finger != nil { events.append(.touchUp) }
    finger = nil
    jab = nil
    path = nil
  }

  // MARK: Scripted fingers

  /// A jab straight down to `depth` below `point` (canvas actions "Poke centre", "Punch"; taps; mic kicks; scripts).
  /// It starts `rise` above the point.
  mutating func scheduleJab(
    at point: SIMD2<Double>, depth: Double, speed: Double, now: Double, rise: Double = 0.012, hold: Double = 0.2
  ) {
    jab = Jab(start: now, from: point + SIMD2(0, rise), to: point - SIMD2(0, depth), speed: speed, hold: hold)
  }

  /// A scripted path in real time from `now` (experiments: the slow finger).
  mutating func schedulePath(_ points: [(t: Double, p: SIMD2<Double>)], now: Double) {
    path = Path(start: now, points: points)
  }

  /// Drives `finger` from the jab, the path or the `-fakeTouch` script at real time `now`. Real touches win.
  mutating func runScripts(now: Double, tank: SIMD2<Double>, fillTop: Double) {
    self.now = now
    if let f = finger, f.id != FakeTouchScript.touchID { return }
    var target: SIMD2<Double>??
    if let j = jab {
      let t = now - j.start
      if t < j.duration {
        target = .some(j.from + (j.to - j.from) * (t / j.duration))
      } else if t < j.duration + j.hold {
        target = .some(j.to)
      } else {
        jab = nil
        target = .some(nil)
      }
    } else if let p = path {
      if let pos = p.position(at: now) {
        target = .some(pos)
      } else {
        path = nil
        target = .some(nil)
      }
    } else if let script {
      target = .some(script.position(at: now, tank: tank, fillTop: fillTop))
    }
    guard let wanted = target else { return }
    let id = FakeTouchScript.touchID
    if let p = wanted {
      if var f = finger {
        let dtTouch = max(now - f.lastTimestamp, 1e-3)
        f.velocity = (p - f.position) / dtTouch
        f.position = p
        f.lastTimestamp = now
        if !f.punched, simd_length(f.velocity) > Self.punchSpeed {
          f.punched = true
          events.append(.punch(p))
        }
        finger = f
      } else {
        finger = Finger(id: id, mode: .probe, position: p, collider: p, start: p, downAt: now, lastTimestamp: now)
        events.append(.touchDown)
      }
    } else if finger?.id == id {
      finger = nil
      events.append(.touchUp)
    }
  }

  // MARK: The frame

  /// The finger for this frame and the collider pose the solver gets (frame-start position, velocity, radius).
  /// `resistance` is the fluid's force on the finger collider from the latest solver frame (N, tank frame); `gap` the
  /// tank gap (m). The collider chases the touch at ≤ `maxSpeed` of simulated time and, along its motion, at no more
  /// than the speed the push budget allows.
  mutating func takeFrame(radius: Double, simDt: Double, resistance: SIMD2<Double>?, gap: Double)
    -> (state: FingerState, collider: (position: SIMD2<Double>, velocity: SIMD2<Double>, radius: Double))?
  {
    guard var f = finger else { return nil }
    let tool: FingerState.Tool
    switch f.mode {
    case .probe: tool = .probe
    case .pour: tool = .pour
    case .scoop: tool = .scoop
    case .prop, .magnet: tool = .prop
    }
    var v = simDt > 0 ? (f.position - f.collider) / simDt : .zero
    var speed = simd_length(v)
    if speed > Self.maxSpeed {
      v *= Self.maxSpeed / speed
      speed = Self.maxSpeed
    }
    if tool == .probe, simDt > 0 {
      let dir = speed > 1e-5 ? v / speed : f.heading
      let push = Self.pushPressure * 2 * radius * max(gap, 0.001)
      let along = max(0, -simd_dot(resistance ?? .zero, dir))
      f.resist += (along - f.resist) * min(1, simDt / Self.resistTime)
      if f.resist > push {
        // Over budget: slow down in proportion (from the speed actually reached, so a fast finger stops within a few
        // frames of meeting a jam).
        f.speedLimit = max(Self.minSpeed, min(f.speedLimit, max(speed, Self.minSpeed)) * push / f.resist)
      } else {
        // Under budget: speed back up over about a tenth of a second (a jam that has let go stays let go; one that
        // re-forms stops the finger again).
        f.speedLimit = min(Self.maxSpeed, f.speedLimit * exp(simDt / Self.recoverTime) + Self.recoverAcceleration * simDt)
      }
      if speed > f.speedLimit {
        v *= f.speedLimit / speed
        speed = f.speedLimit
      }
    }
    let grow = min(1, 0.25 + 0.75 * f.age / Self.growTime)
    let r = radius * grow
    let start = f.collider
    f.collider += v * simDt
    f.age += simDt
    if speed > 1e-4 { f.heading = v / speed }
    finger = f
    let state = FingerState(position: f.collider, velocity: v, radius: r, tool: tool)
    return (state, (start, v, r))
  }

  /// Where the rheometer samples next to the finger: the fluid at its leading edge, one collider skin (`skin`, m) out
  /// from the disc along the motion, or under it when it is still. (The collider keeps the fluid one cell away, so the
  /// centre of the finger has no fluid to sample.)
  func probePoint(radius: Double, skin: Double, gravity: SIMD2<Double>) -> SIMD2<Double>? {
    guard let f = finger, f.mode == .probe else { return nil }
    let down = simd_length(gravity) > 1e-6 ? simd_normalize(gravity) : SIMD2(0, -1)
    let moving = simd_length(f.velocity) > 0.005 && simd_length(f.heading) > 0.5
    let dir = moving ? f.heading : down
    return f.collider + dir * (radius + skin)
  }
}

/// `-fakeTouch poke|stir|punch|slow`: a looping scripted finger for the Simulator and screenshots.
struct FakeTouchScript: Sendable {
  enum Kind: String, Sendable { case poke, stir, punch, slow }
  static let touchID = 9_999
  let kind: Kind
  /// Seconds before the first touch (lets the fluid settle).
  var delay = 1.5

  init?(_ name: String?) {
    guard let name else { return nil }
    kind = Kind(rawValue: name) ?? .poke
  }

  /// Finger position (m) at real time `t`, or nil while lifted.
  func position(at t: Double, tank: SIMD2<Double>, fillTop: Double) -> SIMD2<Double>? {
    guard t >= delay else { return nil }
    let x = tank.x / 2
    let top = fillTop + 0.010
    let bottom = max(0.012, fillTop - 0.03)
    switch kind {
    case .stir:
      let c = SIMD2(x, fillTop * 0.5)
      let r = min(0.015, fillTop * 0.3)
      let a = 2 * Double.pi * 0.8 * (t - delay)
      return c + r * SIMD2(cos(a), sin(a))
    case .poke, .punch, .slow:
      let tau = (t - delay).truncatingRemainder(dividingBy: 4)
      let down: Double
      switch kind {
      case .punch: down = 0.03
      case .slow: down = 2.0
      default: down = 0.6
      }
      if tau < down { return SIMD2(x, top + (bottom - top) * tau / down) }
      if tau < min(down + 1.0, 3.4) { return SIMD2(x, bottom) }
      return nil
    }
  }
}
