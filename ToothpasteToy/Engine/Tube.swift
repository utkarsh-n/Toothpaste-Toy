// Tube.swift — OWNER: PLAY (REDESIGN.md §4–§5; Documentation/REDESIGN-OWNERSHIP.md).
//
// The tube of toothpaste: what `SqueezeState` (the Squeeze crown and button) does in the chamber.
//
//   Parked    the nozzle's mouth waits at the top centre (`NozzleState.position`). It holds nothing: the dab left in
//             the bore at the last tear-off went back into the tube (a one-frame drain over the bore), so nothing hangs
//             from a parked nozzle and paste or water that sloshes up to it falls back.
//   Laying    while squeezed, the tube rides down to just above the paste under it and lays the ribbon in folds: the
//             nozzle sweeps from side to side at the extrusion speed (at most `layRate`, so a faster squeeze bunches the
//             ribbon thicker) and
//             climbs as the stack grows. The bore is a positive-displacement nozzle: a grip (`MPMGrip`) that moves the
//             paste in it at the extrusion speed, fed by a striped emitter (`MPMEmitter.stripes`), so the ribbon is
//             pushed out as a real tube pushes it, folds where it meets the stack, and is the paste's own business from
//             the mouth on (LabKitMPM's elasto-viscoplastic solver: the folds hold by the yield stress or slump without).
//   Lifting   on release the extrusion stops and the tube lifts back to the top, still gripping the paste in its bore.
//             The strand between the nozzle and the stack stretches, necks and tears where the paste gives: a stiff
//             paste snaps early and leaves a peak; honey strings out. The tear-off (`PasteEvent.Kind.tearOff`, with the
//             ribbon's length) fires when the grip stops feeling the strand's pull, and the nozzle recoils.
//
// Motion: the tube's path, the squeeze-rate ramp (pressure building in the tube) and the recoil are interface motion,
// stepped with Wave's springs (`Spring`, `CGFloat.updateValue`: velocity carries over when the target changes, so a
// re-squeeze mid-lift is seamless). They place the nozzle; they do not move paste except through the grip, and the paste
// physics stays in LabKitMPM.

import CoreGraphics
import Foundation
import simd
import LabKitMPM
import Wave

/// What the tube hands the solver this frame.
struct TubeFrame {
  var nozzle: NozzleState
  /// Paste leaves the nozzle this frame (the engine adds the striped emitter at the mouth).
  var flowing: Bool
  /// The bore's grip while the tube lays or lifts a ribbon (nil while parked: a parked tube holds nothing, so paste or
  /// water sloshing up to the mouth is not caught and hung there).
  var grip: MPMGrip?
  /// At the tear-off, the dab left in the bore goes back into the tube: a drain over the bore for that one frame.
  var retract: (position: SIMD2<Double>, radius: Double)?
  /// Tear-offs detected this frame (unstamped).
  var events: [PasteEvent] = []
}

@MainActor struct Tube {
  enum Phase: Equatable { case parked, laying, lifting }

  /// Body index of the bore's grip (props use 2…13, the lens 14).
  static let gripBody = 15
  /// The mouth stays this far above the paste under it (between the mouth's lower edge and the stack top), as a share
  /// of the bore: the ribbon is laid, as from a piping bag, not dropped (at 1.5 bores a toothpaste ribbon stood on the
  /// floor as a pillar 12 mm tall before it buckled, and the heap spread 57 mm wide).
  static let dropShare = 0.75
  /// Half-width of the folds, as a share of the bore diameter.
  static let foldShare = 1.5
  /// The fastest the nozzle lays the ribbon sideways, m/s: a squeeze faster than this bunches the ribbon thicker.
  static let layRate = 0.06
  /// Fastest tube travel, m/s (down to the stack, back to the top).
  static let travelSpeed = 0.5
  static let liftSpeed = 0.06
  /// Laying, the tube climbs at most this share of the extrusion speed.
  static let climbShare = 0.5
  /// The pressure builds once the mouth is within this many bore radii above where it lays.
  static let arrivalShare = 1.0
  /// How the tube follows its path (Wave springs, interface motion).
  let travel = Spring(dampingRatio: 1, response: 0.2)
  /// Laying: snappier, so the nozzle keeps up with the fold path (a slow spring cut the folds short).
  let laying = Spring(dampingRatio: 1, response: 0.1)
  let lift = Spring(dampingRatio: 1, response: 0.45)
  /// The pressure in the tube: the extrusion speed follows the squeeze with this spring (a squeeze ramps up; a release
  /// stops it quickly).
  let pressure = Spring(dampingRatio: 0.9, response: 0.22)
  let release = Spring(dampingRatio: 1, response: 0.08)
  /// The nozzle's recoil when the strand snaps.
  let recoil = Spring(dampingRatio: 0.42, response: 0.2)
  static let recoilKick = 0.12
  /// The tear-off's drain radius as a share of the bore radius (the bore is a 2r × 2r box: 1.3 r reaches most of its
  /// corners and at most 0.3 r below the mouth).
  static let retractShare = 1.3

  private(set) var phase = Phase.parked
  /// Centre of the bore's mouth and its velocity (m, m/s).
  private(set) var mouth: SIMD2<Double>
  private(set) var velocity = SIMD2<Double>.zero
  /// The actual extrusion speed (m/s) and its rate of change.
  private(set) var speed = 0.0
  private var speedRate = 0.0
  /// Sideways lay phase (rad) and the recoil offset (m) and its velocity.
  /// Distance the nozzle has swept along its fold path (m): across and back, at the lay speed.
  private var sway = 0.0
  private var recoilOffset = 0.0
  private var recoilVelocity = 0.0
  /// Ribbon extruded since the squeeze began (m) and the length the next tear-off reports.
  private(set) var extruded = 0.0
  private var ribbon = 0.0
  /// The stack top under the mouth (m), measured every few frames.
  private(set) var stackTop: Double?
  private var measureCountdown = 0
  /// The strand's pull on the grip beyond the dab's own weight (N), smoothed; whether it has been felt this lift; how
  /// long it has been gone (s). `force`: the grip's raw vertical force (N, + up on the paste), diagnostics.
  private(set) var pull = 0.0
  private(set) var force = 0.0
  private var felt = false
  /// The tube has come down to where it lays (the pressure builds only then).
  private var arrived = false
  private var slack = 0.0
  private var lifted = 0.0
  private var homeTime = 0.0

  init(tank: SIMD2<Double>, bore: Double, cell: Double) {
    mouth = Self.park(tank: tank, radius: bore / 2, cell: cell)
  }

  /// The mouth's parked position: top centre, one cell below the chamber's top.
  static func park(tank: SIMD2<Double>, radius: Double, cell: Double) -> SIMD2<Double> {
    SIMD2(tank.x / 2, tank.y - radius - cell)
  }

  /// A triangle wave of period 1 and amplitude 1, 0 at u = 0 and rising there (slope 4).
  static func triangle(_ u: Double) -> Double {
    let f = (u - 0.25) - (u - 0.25).rounded(.down)
    return 4 * abs(f - 0.5) - 1
  }

  /// Whether `triangle` is rising at `u`.
  static func triangleRising(_ u: Double) -> Bool {
    let f = (u - 0.25) - (u - 0.25).rounded(.down)
    return f > 0.5
  }

  /// A fresh chamber (Fill, Refill): park at once, forget the stack and the ribbon.
  mutating func reset(tank: SIMD2<Double>, radius: Double, cell: Double) {
    phase = .parked
    mouth = Self.park(tank: tank, radius: radius, cell: cell)
    velocity = .zero
    speed = 0
    speedRate = 0
    sway = 0
    recoilOffset = 0
    recoilVelocity = 0
    extruded = 0
    ribbon = 0
    stackTop = nil
    pull = 0
    felt = false
  }

  /// One frame. `simulated`: the seconds the solver will simulate (0 while frozen); `solver` for the stack top;
  /// `grip`: the grip's impulse from the latest completed solver frame and the time it covered.
  mutating func step(
    _ s: SqueezeState, tank: SIMD2<Double>, cell: Double, simulated dt: Double, solver: MPMSolver?,
    gripImpulse: SIMD2<Double>?, impulseTime: Double, density: Double, gap: Double, gravity: Double, simTime: Double
  ) -> TubeFrame {
    let r = min(max(s.nozzleRadius, cell), tank.x / 4)
    let home = Self.park(tank: tank, radius: r, cell: cell)
    var events: [PasteEvent] = []
    let requested = min(max(s.speed, 0), SqueezeState.maxRate * 1e-3)

    // Phase changes.
    if s.isSqueezing, phase != .laying {
      if phase == .parked { extruded = 0 }
      phase = .laying
      felt = false
      arrived = false
      measureCountdown = 0
    } else if !s.isSqueezing, phase == .laying {
      phase = .lifting
      ribbon = extruded
      felt = false
      slack = 0
      lifted = 0
      homeTime = 0
    }

    // Where the tube is heading.
    var target = home
    var spring = travel
    var maxSpeed = Self.travelSpeed
    switch phase {
    case .parked:
      break
    case .laying:
      // The nozzle sweeps at the extrusion speed (up to `layRate`), so each fold is one ribbon thick; a triangle path
      // (constant speed, a turn at each end) rather than a sine, which dwelt at the ends and piled them up.
      let fold = Self.foldShare * 2 * r
      let lay = min(speed, Self.layRate)
      if dt > 0 { sway += lay * dt }
      let u = sway / max(4 * fold, 1e-9)
      let x = tank.x / 2 + fold * Self.triangle(u)
      let heading: Double = Self.triangleRising(u) ? 1 : -1
      // Its height: the paste just ahead of the nozzle (the next 1.5 bores of its path, up to well above the mouth).
      // That is what it is about to lay over, so it never ploughs into it, and after each turn the fold just laid is
      // ahead: the tube rises one layer per fold, as a hand piping a ribbon does. The strand under and behind the
      // mouth is not counted (a stiff ribbon stands on the stack as a short pillar before it buckles; counting it made
      // the tube climb on its own strand), nor are bits still flying (faster than the extrusion). The whole far side
      // of the sweep was too much: the tube rode over the highest fold and dropped the ribbon from 12 mm, where it tore.
      measureCountdown -= 1
      if measureCountdown <= 0, let solver {
        measureCountdown = 2
        let near = mouth.x + heading * (r + cell)
        let end = tank.x / 2 + heading * (fold + r + 2 * cell)
        let far = heading > 0 ? min(near + 3 * r, end) : max(near - 3 * r, end)
        if heading * (far - near) > cell {
          let top = solver.columnTop(
            x: (near + far) / 2, halfWidth: abs(far - near) / 2, below: mouth.y + 3 * r,
            maxSpeed: max(speed, 0.02))
          stackTop = top ?? stackTop ?? 0
        }
        if stackTop == nil { stackTop = 0 }
      }
      spring = laying
      let top = stackTop ?? 0
      let y = top + Self.dropShare * 2 * r + r
      target = SIMD2(min(max(x, r + cell), tank.x - r - cell), min(max(y, r + cell), home.y))
    case .lifting:
      spring = lift
      maxSpeed = Self.liftSpeed
    }

    // The squeeze-rate ramp (pressure). The tube first comes down to the paste (or the floor); the pressure builds as it
    // arrives, so the ribbon is not flung from a nozzle still travelling (it fell from high up and splashed).
    if phase == .laying, !arrived {
      arrived = mouth.y - target.y < Self.arrivalShare * r
    }
    let pushing = s.isSqueezing && (phase != .laying || arrived)
    if dt > 0 {
      let spring = requested > speed || s.isSqueezing ? pressure : release
      let next = CGFloat.updateValue(
        spring: spring, value: CGFloat(speed), target: CGFloat(pushing ? requested : 0),
        velocity: CGFloat(speedRate), dt: dt)
      speed = max(Double(next.value), 0)
      speedRate = speed > 0 ? Double(next.velocity) : 0
      if !pushing, speed < 2e-4 { speed = 0 }
    }
    let flowing = speed > 1e-4 && dt > 0 && phase == .laying
    if flowing { extruded += speed * dt }

    // Follow it (two springs, speed-limited).
    if dt > 0 {
      let nx = CGFloat.updateValue(
        spring: spring, value: CGFloat(mouth.x), target: CGFloat(target.x), velocity: CGFloat(velocity.x), dt: dt)
      let ny = CGFloat.updateValue(
        spring: spring, value: CGFloat(mouth.y), target: CGFloat(target.y), velocity: CGFloat(velocity.y), dt: dt)
      var v = SIMD2(Double(nx.velocity), Double(ny.velocity))
      let sp = simd_length(v)
      if sp > maxSpeed { v *= maxSpeed / sp }
      // Laying, the tube climbs slower than the paste leaves it (half the extrusion speed): the bore carries the paste
      // in it with the tube, so a faster climb pulled the ribbon up out of the stack and tore it.
      if phase == .laying, arrived { v.y = min(v.y, Self.climbShare * speed) }
      let moved = mouth + v * dt
      velocity = v
      mouth = SIMD2(min(max(moved.x, r + cell), tank.x - r - cell), min(max(moved.y, r + cell), home.y))
      if phase == .lifting { lifted += max(v.y, 0) * dt }
    }

    // The strand's pull: the grip's holding impulse beyond the dab's weight, felt while lifting.
    if let j = gripImpulse, impulseTime > 0 {
      let dab = density * Double.pi * r * r * max(gap, 1e-3) * max(gravity, 0)
      force = -j.y / impulseTime
      let f = max(-j.y / impulseTime - dab, 0)
      pull += (f - pull) * 0.5
    }
    if phase == .lifting, dt > 0 {
      let atHome = simd_distance(mouth, home) < 1e-4
      if atHome { homeTime += dt }
      // The strand: paste in the three cells under the bore's exit. Torn once that gap has been empty for 50 ms (or a
      // thread still hangs 3 s after the tube got home).
      if let solver, lifted > cell {
        let exit = mouth.y - r
        let under = solver.columnTop(x: mouth.x, halfWidth: r, below: exit - 0.25 * cell)
        let attached = (under ?? -1) > exit - 3 * cell
        slack = attached ? 0 : slack + dt
        if attached { felt = true }
      }
      let torn = slack > 0.05 || homeTime > 3
      if torn {
        events.append(PasteEvent(kind: .tearOff, simTime: simTime, position: mouth, magnitude: ribbon))
        recoilVelocity += Self.recoilKick
        phase = .parked
        felt = false
        ribbon = 0
        extruded = 0
      }
    }

    // Recoil (a spring on top of the path).
    if dt > 0 {
      let rc = CGFloat.updateValue(
        spring: recoil, value: CGFloat(recoilOffset), target: 0, velocity: CGFloat(recoilVelocity), dt: dt)
      recoilOffset = Double(rc.value)
      recoilVelocity = Double(rc.velocity)
      if abs(recoilOffset) < 1e-6, abs(recoilVelocity) < 1e-5 { recoilOffset = 0; recoilVelocity = 0 }
    }
    let shown = SIMD2(mouth.x, min(mouth.y + recoilOffset, home.y + 0.5 * r))

    let stripes = min(max(s.stripes, 0), SqueezeState.maxStripes)
    let nozzle = NozzleState(
      position: shown, radius: r, emitting: flowing, speed: phase == .laying ? speed : 0, stripes: stripes,
      material: s.material, extruded: phase == .laying ? extruded : 0)
    // The bore: the paste in it moves with the tube, plus the extrusion speed while laying (a piston). Parked: no grip;
    // the frame of the tear-off drains the bore (the dab goes back into the tube).
    var grip: MPMGrip?
    if phase != .parked {
      let gripVelocity = velocity + SIMD2(0, recoilVelocity) + SIMD2(0, flowing ? -speed : 0)
      grip = MPMGrip(shape: .box(halfSize: SIMD2(r, r)), position: shown, velocity: gripVelocity, bodyIndex: Self.gripBody)
    }
    let retract: (position: SIMD2<Double>, radius: Double)? = events.isEmpty ? nil : (shown, Self.retractShare * r)
    return TubeFrame(nozzle: nozzle, flowing: flowing, grip: grip, retract: retract, events: events)
  }
}
