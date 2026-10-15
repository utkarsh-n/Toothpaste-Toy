// HoloMotion.swift — OWNER: HOLO (Documentation/REDESIGN-OWNERSHIP.md §3).
//
// The hologram's interface motion on Janum Trivedi's Wave springs (LabKit vendors Wave 0.3.4, MIT): every value the
// chamber animates — the grid's parallax against the hologram under tilt, the lens's refraction strength and its radius
// bounce on a yield or jam, the amber flash of each paste event, how strongly fast paste leaves echoes — is a spring
// with a target and a velocity, so it is interruptible and keeps its velocity when the target moves. Wave animates
// these interface values only: the paste itself is LabKitMPM's physics.
//
// The renderer steps the springs itself, once per drawn frame, with Wave's own integrator
// (`CGFloat.updateValue(spring:value:target:velocity:dt:)`, semi-implicit Euler) in substeps of at most 1/240 s, so a
// stiff spring stays stable at the render loop's longest frame (1/15 s). No allocations per frame.

import CoreGraphics
import LabKitMPM
import Wave

/// One spring-driven interface value.
struct HoloSpring {
  var value: CGFloat
  var velocity: CGFloat = 0
  var target: CGFloat

  init(_ value: CGFloat) {
    self.value = value
    target = value
  }

  /// Advances by `dt` seconds toward `target` (≤ 1/240 s substeps).
  mutating func step(_ spring: Spring, dt: Double) {
    guard dt > 0, spring.response > 0 else { return }
    let n = max(1, Int((dt * 240).rounded(.up)))
    let h = dt / Double(n)
    for _ in 0..<n {
      let s = CGFloat.updateValue(spring: spring, value: value, target: target, velocity: velocity, dt: h)
      value = s.value
      velocity = s.velocity
    }
    if !value.isFinite || !velocity.isFinite { value = target; velocity = 0 }
  }

  /// Jumps to `v` at rest (Reduce Motion, a reset).
  mutating func snap(_ v: CGFloat) {
    value = v
    target = v
    velocity = 0
  }

  var float: Float { Float(value) }
}

/// The springs the chamber uses (Wave `Spring(dampingRatio:response:)`; response = one undamped period, s).
struct HoloSprings {
  /// Grid parallax and the fringe hue follow the tilt: a little lag and a soft settle, like a world-anchored layer.
  let tilt = Spring(dampingRatio: 0.82, response: 0.32)
  /// The lens's refraction fades in as the glass touches the hologram, and out quickly on release.
  let lensIn = Spring(dampingRatio: 1.0, response: 0.14)
  let lensOut = Spring(dampingRatio: 1.0, response: 0.07)
  /// Radius bounce on a yield or jam: underdamped, settles in about half a second.
  let bounce = Spring(dampingRatio: 0.38, response: 0.30)
  /// Event flash energy: a critically damped spring kicked from rest gives an amber attack (peak after ~70 ms) and a
  /// decay over ~0.4 s.
  let flash = Spring(dampingRatio: 1.0, response: 0.42)
  /// How strongly fast-moving paste leaves echoes (follows the paste's speed; decays as it settles).
  let ghosts = Spring(dampingRatio: 1.0, response: 0.25)
  /// The nozzle's mouth light while the tube squeezes.
  let mouth = Spring(dampingRatio: 0.9, response: 0.18)
}

/// Up to four amber event flashes (REDESIGN.md §2, §4: amber attack and decay), each a spring kicked by its event.
struct HoloFlashBank {
  struct Slot {
    var centre = SIMD2<Float>.zero
    var radius: Float = 0
    var energy = HoloSpring(0)
    var gain: Float = 0
  }
  private(set) var slots = (Slot(), Slot(), Slot(), Slot())

  /// A kick of this velocity peaks at 1 with `HoloSprings.flash` (critically damped from rest: x(t) = v·t·e^(−ωt),
  /// peak v/(ω·e) at t = 1/ω, ω = 2π / 0.42 s).
  static let kickForUnitPeak: CGFloat = 40.6

  /// Lights a new flash: reuses the dimmest slot.
  mutating func fire(at centre: SIMD2<Float>, radius: Float, intensity: Float) {
    var best = 0
    var dimmest = Float.greatestFiniteMagnitude
    for i in 0..<4 {
      let s = slot(i)
      let v = abs(s.energy.float) * s.gain
      if v < dimmest { dimmest = v; best = i }
    }
    var s = Slot()
    s.centre = centre
    s.radius = radius
    s.gain = min(max(intensity, 0), 1.5)
    s.energy.velocity = Self.kickForUnitPeak
    setSlot(best, s)
  }

  mutating func step(_ spring: Spring, dt: Double) {
    for i in 0..<4 {
      var s = slot(i)
      guard s.gain > 0 else { continue }
      s.energy.step(spring, dt: dt)
      if abs(s.energy.value) < 1e-3 && abs(s.energy.velocity) < 1e-2 { s = Slot() }
      setSlot(i, s)
    }
  }

  mutating func clear() { slots = (Slot(), Slot(), Slot(), Slot()) }

  /// The four flashes for the renderer (the shader sums them).
  func flashes() -> (FluidHoloFlash, FluidHoloFlash, FluidHoloFlash, FluidHoloFlash) {
    func f(_ s: Slot) -> FluidHoloFlash {
      FluidHoloFlash(centre: s.centre, radius: s.radius, intensity: max(s.energy.float, 0) * s.gain)
    }
    return (f(slots.0), f(slots.1), f(slots.2), f(slots.3))
  }

  /// Brightest flash now (tests, the lens bounce).
  var peak: Float {
    var m: Float = 0
    for i in 0..<4 { let s = slot(i); m = max(m, max(s.energy.float, 0) * s.gain) }
    return m
  }

  private func slot(_ i: Int) -> Slot {
    switch i {
    case 0: slots.0
    case 1: slots.1
    case 2: slots.2
    default: slots.3
    }
  }

  private mutating func setSlot(_ i: Int, _ s: Slot) {
    switch i {
    case 0: slots.0 = s
    case 1: slots.1 = s
    case 2: slots.2 = s
    default: slots.3 = s
    }
  }
}
