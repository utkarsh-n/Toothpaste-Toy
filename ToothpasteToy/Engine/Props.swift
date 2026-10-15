// Props.swift — OWNER: PLAY (was PHYS; Documentation/REDESIGN-OWNERSHIP.md).
//
// Drop-mode props in Box2D (LabKitRigid) and their two-way coupling with the fluid: each prop is an MPMCollider
// with its own `bodyIndex`; the solver's `bodyImpulses` (1–2 frames old, applied once per completed solver frame) push
// the Box2D body; Box2D's pose and velocity drive the collider next frame. Buoyancy and drag come out of the fluid
// impulses (LabKit measured buoyancy within 6 % of ρgA); nothing here fakes them.
//
// Stability (measured in the Toothpaste Toy tank on the GPU, 8 October 2026): the impulses lag the bodies by a solver frame or
// two and hold the fluid's added-mass reaction, which exceeds a light body's own inertia; a cork's 2 mm draft is thinner
// than the one-cell collider skin, so it touches the fluid only every other frame (|J| jumps between 0 and 4× its
// buoyancy); and in honey the lagged viscous reaction alone has a gain of about 5 per frame. Applied explicitly, a cork
// shot to the lid at 2 m/s and kept the water splashing, and props in honey were thrown out of it. Each prop's velocity
// change is therefore solved implicitly,
//   (m + m_a + c·h)·Δv = J·h/h_J + m·g·h − c·v·h,
// with an added mass m_a = 8·s·ρ_f·(A + P·Δx)·gap (the fluid in the prop's footprint and its one-cell skin, generously:
// 2× pumped a cork in water, 8× settles it to 0.03 m/s; s = how submerged it is, from its share of full buoyancy, rising
// at once and fading over 0.25 s so it does not vanish between touches) and a damping c = s·(3·ρ_f·g·(2·r_bound)·gap·h
// + 1.5·12·η·(A + P·Δx)/gap): the first cancels the negative damping a one-to-two-frame lag puts into bobbing
// (≈ k_hydrostatic·lag), the second is the thin-tank drag of the fluid the prop carries (η from the flow curve at
// 10 s⁻¹), which the lagged reaction cannot damp stably in honey or ketchup. The result is applied as a force over the
// Box2D step (an impulse that cancels gravity up front lifts a resting prop by g·h²/3 every frame). Equilibria (floating,
// resting) stay exact; transients are slower than real (a steel ball accelerates at about a third of its rate in water).
// Frames without fresh statistics reuse the last fluid force. A collider also sinks a whole frame into a stiff bed
// before the lagged reaction arrives, which launched a gently placed steel ball off quicksand at 5× its landing speed,
// so a prop denser than the fluid may be stopped by it but its upward speed may not grow (a light prop's upward push is
// capped at its weight plus twice its buoyancy). A loose |Δv| cap stays as a guard. Props are 2–15 in the solver's body table (0 finger,
// 1 paddle): at most 14 at once; dropping a 15th removes the oldest.
//
// Shear-thickening fluids (oobleck) get a rate-dependent η in that drag (`PropViscosity`): the flow curve at the shear
// rate the prop's own motion drives across the gap (2|v|/gap), held over the fluid's melt time. A fixed η from the
// jammed branch (401 Pa·s at 10 s⁻¹) glued a steel ball into the surface (0.3 mm/s), and the resting branch (0.07 Pa·s)
// let light props pump; with the rate, a steel ball dropped from the top jams the surface (jammed fraction 0.96) and is
// held about 1.5 mm deep for about 0.4 s, then sinks at about 3 cm/s as the jam melts and slows to the floor (on it by
// about 4 s; measured on 9 October 2026: PhysTests.testPropsInOobleck, trace in progress-rfix.md). A sphere in real
// cornflour also settles in stop-go oscillations (von Kann et al. 2011); this model shows the landing jam, not those.

import Foundation
import simd
import LabKitCore
import LabKitMPM
import LabKitRigid

/// The viscosity in a prop's implicit thin-tank drag, Pa·s. For most fluids the steady flow curve at 10 s⁻¹ (`fixed`);
/// for a shear-thickening one the flow curve at the rate the prop's motion imposes (`at(_:)`, a log-spaced table).
struct PropViscosity: Sendable, Equatable {
  /// η at 10 s⁻¹, Pa·s.
  var fixed = 0.0
  /// η at `rates` (shear-thickening materials only), Pa·s.
  var table: [Double] = []
  /// How long a jam the prop drove holds its viscosity, s (the material's melt time).
  var memory = 0.15
  /// 10⁻² … 10³ s⁻¹ in quarter decades.
  static let rates: [Double] = (0...20).map { pow(10, -2 + 0.25 * Double($0)) }

  var rateDependent: Bool { table.count == Self.rates.count }

  /// η at shear rate `rate` (1/s): log-log interpolation in the table, `fixed` without one.
  func at(_ rate: Double) -> Double {
    guard rateDependent else { return fixed }
    let x = (log10(max(rate, 1e-9)) + 2) / 0.25
    if !(x > 0) { return table[0] }
    if x >= Double(table.count - 1) { return table[table.count - 1] }
    let i = Int(x), u = x - Double(i)
    let a = log10(max(table[i], 1e-9)), b = log10(max(table[i + 1], 1e-9))
    return pow(10, a + (b - a) * u)
  }

  /// From a flow curve σ(γ̇) (Pa). `thickening`: the material jams under shear (a DST block).
  static func of(thickening: Bool, memory: Double, stress: (Double) -> Double) -> PropViscosity {
    func eta(_ r: Double) -> Double {
      let e = stress(r) / r
      return e.isFinite ? min(max(e, 0), 1e4) : 0
    }
    var v = PropViscosity(fixed: eta(10))
    if thickening {
      v.table = rates.map(eta)
      v.memory = memory.isFinite && memory > 0 ? memory : 0.15
    }
    return v
  }
}

struct PropBay {
  struct Prop {
    let id: RigidBodyID
    let kind: PropKind
    /// MPM body index (2…15; 0 is the finger, 1 the stir paddle).
    let bodyIndex: Int
  }

  private(set) var props: [Prop] = []
  private var lastImpulseFrame = 0
  /// The floor vibration's mean extra gravity over the solver frame the held fluid force came from, m/s² (y).
  private var heldVibration = 0.0
  /// The latest fluid force on each prop with its added-mass reaction removed, N (held between fresh statistics).
  private var force: [RigidBodyID: SIMD2<Double>] = [:]
  private var torque: [RigidBodyID: Double] = [:]
  /// How submerged each prop is, 0…1: rises at once with the fluid's push, decays over `submersionMemory` (a light prop
  /// floating on the one-cell collider skin touches the fluid only every other frame; its added mass must not vanish
  /// in between).
  private var submersion: [RigidBodyID: Double] = [:]
  /// The shear rate each prop's motion drove recently, 1/s (decays over `PropViscosity.memory`).
  private var drivenRate: [RigidBodyID: Double] = [:]
  static let submersionMemory = 0.25
  static let firstBodyIndex = 2
  /// Props use bodies 2…13: 14 is the glass lens (LensProbe), 15 the tube's grip (Tube).
  static let endBodyIndex = 14
  /// Added-mass multiple of ρ_f·(A + P·Δx)·gap, and the lag damping in units of ρ_f·g·width·gap·h (see the header).
  static let addedMassFactor = 8.0
  static let lagDamping = 3.0
  /// The implicit share of the thin-tank (Hele-Shaw) drag on the fluid a prop carries, 12·η·(A + P·Δx)/gap: the solver
  /// applies that drag to the fluid, whose lagged reaction alone made a cork in honey pump (gain ≈ 5 per frame).
  static let dragFactor = 1.5
  /// The most the fluid may push a lighter-than-fluid prop up: its weight plus this many times its full buoyancy.
  static let lightLift = 2.0
  /// Clamped impulses (diagnostics).
  private(set) var clampCount = 0

  /// Drops a prop at `point` (the oldest goes when every body index is taken).
  mutating func drop(_ info: PropInfo, at point: SIMD2<Double>, gap: Double, rigid: RigidWorld) {
    var used = Set(props.map(\.bodyIndex))
    if used.count >= Self.endBodyIndex - Self.firstBodyIndex, let oldest = props.first {
      rigid.remove(oldest.id)
      props.removeFirst()
      used.remove(oldest.bodyIndex)
    }
    guard let index = (Self.firstBodyIndex..<Self.endBodyIndex).first(where: { !used.contains($0) }) else { return }
    let light = info.density < 1000
    let id = rigid.add(
      RigidBodySpec(
        shape: info.shape, position: point, density: info.density * max(gap, 0.001), friction: info.friction,
        restitution: info.restitution, linearDamping: light ? 0.6 : 0.05, angularDamping: light ? 0.6 : 0.1,
        enableSleep: false, userTag: index))
    props.append(Prop(id: id, kind: info.id, bodyIndex: index))
  }

  mutating func clear(rigid: RigidWorld) {
    for p in props { rigid.remove(p.id) }
    props.removeAll()
    force.removeAll()
    torque.removeAll()
    submersion.removeAll()
    drivenRate.removeAll()
  }

  /// Fluid → bodies (once per completed solver frame), then one Box2D step of the simulated time. `fluidDensity` is
  /// the density of the fluid around the props (kg/m³), `gap` the tank gap (m). Returns hit events.
  mutating func step(
    rigid: RigidWorld, gravity: SIMD2<Double>, stats: MPMStats, dt: Double, fluidDensity: Double,
    fluidViscosity: PropViscosity, gap: Double, cell: Double, vibration: (MPMStats) -> Double = { _ in 0 }
  ) -> [SimEvent] {
    guard dt > 0 else { return [] }
    let fresh = stats.frameIndex != lastImpulseFrame
    if fresh {
      lastImpulseFrame = stats.frameIndex
      heldVibration = vibration(stats)
    }
    let hn = max(stats.simulatedTime, 1e-6)
    for p in props {
      let m = rigid.mass(p.id)
      guard m > 0 else { continue }
      let pose = rigid.pose(p.id)
      let shape = rigid.shape(p.id)
      let depth = max(gap, 0.001)
      var pushed = 0.0
      if fresh, p.bodyIndex < stats.bodyImpulses.count {
        let j = stats.bodyImpulses[p.bodyIndex]
        if j.x.isFinite, j.y.isFinite, j.z.isFinite {
          let fullBuoyancy = fluidDensity * shape.area * depth * simd_length(gravity) * hn
          pushed = fullBuoyancy > 0 ? min(simd_length(SIMD2(j.x, j.y)) / fullBuoyancy, 1) : 0
          force[p.id] = SIMD2(j.x, j.y) / hn
          torque[p.id] = j.z / hn
        }
      }
      guard var f = force[p.id] else { continue }
      let g = simd_length(gravity)
      let up = g > 1e-6 ? -gravity / g : SIMD2(0, 1)
      let displaced = fluidDensity * shape.area * depth
      let dense = m >= displaced
      // A light prop may be pushed up by at most its weight plus twice its full buoyancy (a tighter cap clips its
      // upward kicks but not the downward ones, and pumps a cork to the floor).
      if !dense {
        let lift = simd_dot(f, up), most = (m + Self.lightLift * displaced) * g
        if lift > most { f -= (lift - most) * up }
      }
      let s = max(pushed, (submersion[p.id] ?? 0) * exp(-dt / Self.submersionMemory))
      submersion[p.id] = s
      let dragged = shape.area + Self.perimeter(shape) * cell
      let ma = Self.addedMassFactor * s * fluidDensity * dragged * depth
      // The drag's viscosity: fixed, or (shear-thickening fluids) the flow curve at the rate this prop has driven across
      // the gap lately, so a fast prop meets the jammed branch and a slow one the liquid one.
      var eta = fluidViscosity.fixed
      if fluidViscosity.rateDependent {
        let rate = max(2 * simd_length(pose.velocity) / depth, (drivenRate[p.id] ?? 0) * exp(-dt / fluidViscosity.memory))
        drivenRate[p.id] = rate
        eta = fluidViscosity.at(rate)
      }
      let c = s * (Self.lagDamping * fluidDensity * g * 2 * shape.boundingRadius * depth * dt
        + Self.dragFactor * 12 * eta * dragged / depth)
      // The vibrating floor shakes the prop with the fluid around it (the solver applies the vibration as an oscillating
      // gravity, far faster than a frame): that frame's mean, paired with that frame's fluid force, on the prop and the
      // fluid it carries (m + m_a), so the prop rides the shaken bed as the fluid does. On m alone, the generous added
      // mass kept it nearly still while the bed shook past it, and the fluid's oscillating push rectified into support:
      // a glass marble stayed up on liquefied quicksand (λ 0.07) for the whole shake and sank 11 mm only once the floor
      // stopped. Now it sinks to the floor during the shake (PhysTests.testQuicksandFirmUntilShaken).
      f.y += (m + ma) * heldVibration
      var dv = (f * dt + m * gravity * dt - c * pose.velocity * dt) / (m + ma + c * dt)
      // A prop denser than the fluid may be stopped and held up by it (a bed it cannot sink into), never thrown up: a
      // kinematic collider sinks a whole frame into a stiff bed (quicksand at rest, jammed oobleck, putty) before the
      // lagged reaction arrives, which launched a gently placed steel ball off quicksand at 5× its landing speed and
      // kept it hopping, and a vibrating floor's support aliases against the frame rate. So its upward speed may not
      // grow (beyond a 0.05 g allowance).
      if dense {
        let vn0 = simd_dot(pose.velocity, up), vn1 = simd_dot(pose.velocity + dv, up)
        let limit = max(vn0, 0) + 0.05 * g * dt
        if vn1 > limit { dv -= (vn1 - limit) * up }
      }
      let cap = 3 * g * dt + 0.5 * simd_length(pose.velocity) + 0.1
      if simd_length(dv) > cap {
        dv *= cap / simd_length(dv)
        clampCount += 1
      }
      // As a force over the step, not an impulse at its start: Box2D adds gravity substep by substep, so an impulse that
      // cancels it up front lifts a resting prop by about g·h²/3 every frame (a marble levitated out of honey).
      rigid.applyForce(p.id, m * (dv / dt - gravity))
      // Rotation, implicit in the same way: (I + I_a + c_r·h)·Δω = T·h − c_r·ω·h, with the added inertia and the
      // rotational drag of the same fluid, I_a = m_a·k² and c_r = c·k² (k² = I/m). Applied explicitly (the torque only
      // scaled by m/(m + m_a)), the lagged torque spun a cork submerged in honey by up to 20 rad/s in one frame (its own
      // inertia is tiny), which threw it sideways at 5–11 cm/s for a frame every second or so (measured).
      let inertia = rigid.rotationalInertia(p.id)
      if inertia > 0 {
        let k2 = inertia / m
        let ia = ma * k2, cr = c * k2
        let dw = ((torque[p.id] ?? 0) * dt - cr * pose.angularVelocity * dt) / (inertia + ia + cr * dt)
        rigid.applyTorque(p.id, inertia * dw / dt)
      }
    }
    rigid.gravity = gravity
    rigid.step(dt: dt, subSteps: 4)
    return rigid.drainHits().filter { $0.approachSpeed > 0.15 }.map { .propHit(speed: $0.approachSpeed) }
  }

  static func perimeter(_ shape: RigidShape) -> Double {
    switch shape {
    case .circle(let r): 2 * Double.pi * r
    case .box(let hw, let hh): 4 * (hw + hh)
    case .capsule(let hl, let r): 4 * hl + 2 * Double.pi * r
    case .polygon: 2 * Double.pi * shape.boundingRadius
    }
  }

  func colliders(rigid: RigidWorld) -> [MPMCollider] {
    props.compactMap { p in
      let pose = rigid.pose(p.id)
      let shape: MPMCollider.Shape
      switch rigid.shape(p.id) {
      case .circle(let r): shape = .circle(radius: r)
      case .box(let hw, let hh): shape = .box(halfSize: SIMD2(hw, hh))
      case .capsule(let hl, let r): shape = .capsule(halfLength: hl, radius: r)
      case .polygon: return nil
      }
      return MPMCollider(
        shape: shape, position: pose.position, angle: pose.angle, velocity: pose.velocity,
        angularVelocity: pose.angularVelocity, friction: rigid.spec(p.id)?.friction ?? 0.5, bodyIndex: p.bodyIndex)
    }
  }

  func states(rigid: RigidWorld) -> [PropState] {
    props.map { p in
      let pose = rigid.pose(p.id)
      return PropState(
        id: p.id.rawValue, kind: p.kind, shape: rigid.shape(p.id), position: pose.position, angle: pose.angle,
        velocity: pose.velocity)
    }
  }
}
