// ToothpasteEngine.swift — OWNER: PLAY (was PHYS; Documentation/REDESIGN-OWNERSHIP.md).
//
// `ToothpasteSimulation`: one frame = experiment script → scripted fingers → sensors → conditioned sources (+ the mic Band
// level) → drives (ModulationRouter; a held knob wins) → time scale → body forces (gravity from tilt × Gravity, the
// phone's shake as frame acceleration, a synthetic shake, floor vibration from Shake/Rate + mic, temperature, the
// magnetometer's Δ|B| as a uniform field and the virtual magnet under the floor) → material knobs → colliders
// (force-limited finger, stir paddle, props) and emitters (pour) → `MPMFrameInput`; Box2D steps with the previous
// solver frame's body impulses; the solver itself is encoded in `encode(into:)`.
//
// Time: `simDt` = Time knob × real dt (≤ 1/15 s, 0 while frozen). The solver's substep cap follows the frame time
// (SubstepBudget, Stimuli.swift), and `plannedTime` predicts what the solver will really simulate when it still has to
// slow down, so the finger, the paddle, Box2D and the clock all advance by the *simulated* time (SKELETON.md §7).
//
// Temperature: the Heat knob is the room (the ambient the fluid relaxes to, thermal time 4 s). For lava it is the
// eruption temperature of fresh lava instead; the air stays at 20 °C, the core cools over about 60 s and the free
// surface about 16× faster (MPMSolver.surfaceCooling), so a crust forms over a hot core and the flow slows.
//
// v2 stubs (FOUNDATION, 13 October 2026; REDESIGN.md §8; PLAY owns and refines them): the glass lens
// (`FrameStep.lens`) is a kinematic circular probe collider swept from where it ended the last frame to its centre, and
// the rheometer samples its leading edge; the tube (`FrameStep.squeeze`) is a striped emitter at the nozzle (top centre,
// pointing down) that stops on release and reports a tear-off; the frame carries the three channels and paste events
// (yield and jam at the lens or finger, tear-off, prop impacts).

import CoreGraphics
import Foundation
import simd
import LabKitCore
import LabKitMPM
import LabKitRigid
import LabKitSensors
import Metal

@MainActor final class ToothpasteEngine: ToothpasteSimulation {
  private let r: ToothpasteResources
  private(set) var currentMaterial: MaterialID
  private(set) var pourMaterial: MaterialID

  private var conditioner = SourceConditioner()
  private var router = ModulationRouter(ToothpasteDrives.routes)
  private let band = MicBand()
  private var fieldBaseline = FieldBaseline()
  private var budget = SubstepBudget()
  private var kicks = KickPlacer()
  private var scanner = ProbeScanner()
  private(set) var tools: TouchTools
  private(set) var bay = PropBay()
  private var shelfMode: ShelfMode = .fill
  private var realTime = 0.0
  private(set) var simTime = 0.0
  private var pending: MPMFrameInput?
  private var events: [SimEvent] = []
  private var fillFraction = 0.45
  private var stirAngle = 0.0
  private var stirOmega = 0.0
  private var paddleGrowth = 0.0
  /// A synthetic shake of the tank (canvas action, experiment script): seconds left, peak acceleration (m/s²), Hz.
  private var burst: (left: Double, peak: SIMD2<Double>, hz: Double, phase: Double) = (0, .zero, 0, 0)
  /// In-plane tilt offset (rad, + tips gravity toward +x): two-finger drags and Tilt actions on a simulated phone,
  /// a nudge that eases back on a real one.
  private(set) var tiltOffset = 0.0
  /// Virtual magnet x (m) and a scripted slide toward a target.
  private(set) var magnetX: Double
  private var magnetSlide: (target: Double, speed: Double)?
  /// Experiment script and scripted pour.
  private var script: [ScriptStep] = []
  private var scriptIndex = 0
  private var scriptedPour: (material: MaterialID, x: Double, until: Double)?
  private var appliedKey: [Double] = []
  private var baseQuality: MPMQuality
  private var lastStats = MPMStats()
  // v2 state
  /// The glass lens as a force-limited probe: where its collider ended the last frame (m), how long it has been in the
  /// chamber (s, the radius ramp), the smoothed resistance along its motion (N), the speed the paste lets it move (m/s)
  /// and its last heading.
  private var lensAt: SIMD2<Double>?
  private var lensAge = 0.0
  private var lensResist = 0.0
  private var lensLimit = LensState.maxSpeed
  private var lensHeading = SIMD2<Double>.zero
  /// The tube (Tube.swift): parked, laying a ribbon, or lifting off it.
  private(set) var tube: Tube
  /// Event detectors: a yield fires once the probe's solid share falls below 0.3 after it held at ≥ 0.6; a jam once the
  /// jammed share reaches 0.05 after it was below 0.01.
  private var yieldArmed = false
  private var jamArmed = true
  private var pasteEvents: [PasteEvent] = []

  /// How deep the virtual magnet sits under the floor (m): the tank's glass floor.
  static let magnetDepth = 0.004
  /// Room temperature for lava's air, K.
  static let room = 293.15
  /// Lava's thermal times: the core cools toward the air over 60 s (real: hours), the free surface (half-filled cells)
  /// 16× faster, about 4 s. Fresh lava erupts at 1170 °C (the Heat knob), runnier than the 1130 °C of the preset's
  /// lava-lake data; as it cools toward the model's 1090 °C floor its viscosity and yield stress rise 2.3×, so the
  /// flow slows (measured: the front's speed halves between 0.5 s and 4 s) under a crust about 600 K cooler than the
  /// core.
  static let lavaCoreTime = 60.0
  static let lavaSurfaceCooling = 30.0
  /// Scoop mode's drain radius as a share of the Finger knob's radius.
  static let scoopShare = 0.75
  /// The World, Touch and Signals knobs an experiment puts back to their defaults before applying its own values.
  static let experimentResets: [ParamID] = [.gravity, .magnet, .time, .stir, .shake, .rate, .listen, .drives]

  init(resources: ToothpasteResources, initialMaterial: MaterialID?) {
    r = resources
    let known = Set(resources.catalog.materials.map(\.id))
    let id = initialMaterial.flatMap { known.contains($0) ? $0 : nil } ?? defaultMaterialID
    currentMaterial = id
    pourMaterial = id
    tools = TouchTools(script: FakeTouchScript(resources.launch.fakeTouch))
    tube = Tube(
      tank: resources.solver?.domain.size ?? MPMDomain.lifeSizeTank, bore: SqueezeState.defaultNozzleDiameter * 1e-3,
      cell: resources.solver?.cellSize ?? 0.002)
    baseQuality = resources.solver?.quality ?? .standard
    magnetX = (resources.solver?.domain.size.x ?? MPMDomain.lifeSizeTank.x) / 2
    if let solver = r.solver {
      solver.materials = resources.catalog.materials.map(\.material)
    }
    if ToothpasteLaunch.thermalHeatRequested, let i = router.routes.firstIndex(where: { $0.id == "device.heat" }) {
      router.routes[i].enabled = true
    }
    select(id)
    freshChamber(id)
    events.removeAll()
  }

  var tankSize: SIMD2<Double> { r.solver?.domain.size ?? MPMDomain.lifeSizeTank }
  private var gap: Double { r.solver?.domain.heleShawGap ?? 0.01 }
  private var cell: Double { r.solver?.cellSize ?? 0.002 }

  // MARK: Lifecycle

  func start() {
    r.motion.start()
    r.thermal.start()
  }

  func stop() {
    r.motion.stop()
    r.thermal.stop()
  }

  // MARK: Materials

  /// Re-registers the material's knobs (Fluid page, Memory, Rebuild, Heat) at its defaults and its thermal setting.
  private func select(_ id: MaterialID) {
    let info = r.catalog.material(id)
    currentMaterial = id
    r.params.register(ToothpasteKnobs.materialSpecs(for: info.material, title: info.title), adoptDefaults: true)
    appliedKey = []
    scanner.reset()
    if let solver = r.solver {
      solver.materials = r.catalog.materials.map(\.material)
      let lava = id == "lava"
      solver.thermalTime = lava ? Self.lavaCoreTime : 4
      solver.surfaceCooling = lava ? Self.lavaSurfaceCooling : 0
      solver.wallFriction = ToothpasteTuning.wallFriction(id)
    }
  }

  /// The temperature fresh fluid of `id` starts at, K: lava erupts at the Heat knob, everything else is at the room.
  private func fillTemperature(_ id: MaterialID) -> Double {
    r.params[.heat] + 273.15
  }

  /// A fresh chamber of `id` (launch, Fill, Refill, Reset): the starting coil for toothpaste, a pool for the others
  /// (Scenes.swift).
  private func freshChamber(_ id: MaterialID) {
    switch ToothpasteScenes.start(for: id) {
    case .pool:
      refill(layers: [(id, r.catalog.material(id).fillFraction)])
    case .coil:
      refill(layers: [], coil: id)
    }
  }

  private func refill(layers: [(material: MaterialID, fraction: Double)], shapes: [FillShape] = [], coil: MaterialID? = nil) {
    let size = tankSize
    var y = 0.0
    r.solver?.clear()
    tools.cancel(rigid: r.rigid)
    tube.reset(tank: size, radius: SqueezeState.defaultNozzleDiameter * 0.5e-3, cell: cell)
    lensAt = nil
    for layer in layers {
      let info = r.catalog.material(layer.material)
      let h = max(0, min(layer.fraction, 0.95)) * size.y
      r.solver?.fill(
        rect: CGRect(x: 0, y: y, width: size.x, height: h), material: info.slot,
        temperature: fillTemperature(info.id))
      y += h
    }
    var top = y
    for shape in shapes {
      let info = r.catalog.material(shape.material)
      let t = fillTemperature(info.id)
      switch shape {
      case .rect(_, let x0, let y0, let x1, let y1):
        r.solver?.fill(
          rect: CGRect(x: x0 * size.x, y: y0 * size.y, width: (x1 - x0) * size.x, height: (y1 - y0) * size.y),
          material: info.slot, temperature: t)
        top = max(top, y1 * size.y)
      case .polygon(_, let pts):
        let poly = pts.map { $0 * size }
        r.solver?.fill(polygon: poly, material: info.slot, temperature: t)
        top = max(top, poly.map(\.y).max() ?? 0)
      case .disc(_, let c, let radius):
        let centre = c * size, rad = radius * size.x
        let poly = (0..<32).map { i -> SIMD2<Double> in
          let a = Double(i) / 32 * 2 * .pi
          return centre + rad * SIMD2(cos(a), sin(a))
        }
        r.solver?.fill(polygon: poly, material: info.slot, temperature: t)
        top = max(top, (centre.y + rad))
      }
    }
    if let id = coil {
      // The starting ribbon, folded on the floor under the nozzle (Scenes.swift), dyed in the tube's three stripes.
      let info = r.catalog.material(id)
      let w = ToothpasteScenes.ribbonWidth
      let path = ToothpasteScenes.coilPath(centreX: size.x / 2)
      var area = 0.0
      for q in ToothpasteScenes.ribbon(path, width: w, taper: 1.2 * w) {
        r.solver?.fill(polygon: q.polygon, material: info.slot, temperature: fillTemperature(id), stripes: 3, across: q.across)
        area += Self.polygonArea(q.polygon)
      }
      top = max(top, (path.map(\.y).max() ?? 0) + w / 2)
      fillFraction = area / max(size.x * size.y, 1e-12)
    } else {
      fillFraction = layers.isEmpty && !shapes.isEmpty ? estimateFill(shapes) : y / max(size.y, 1e-9)
    }
    scriptTop = top
    stirOmega = 0
    paddleGrowth = 0
    scanner.reset()
    events.append(.refilled(currentMaterial))
  }

  static func polygonArea(_ p: [SIMD2<Double>]) -> Double {
    var a = 0.0
    for i in 0..<p.count {
      let j = (i + 1) % p.count
      a += p[i].x * p[j].y - p[j].x * p[i].y
    }
    return abs(a) / 2
  }

  /// The mean fill height of shape-only fills, as a fraction of the tank height (for scripts and the probe lattice).
  private func estimateFill(_ shapes: [FillShape]) -> Double {
    var area = 0.0
    for s in shapes {
      switch s {
      case .rect(_, let x0, let y0, let x1, let y1): area += (x1 - x0) * (y1 - y0)
      case .polygon(_, let p):
        var a = 0.0
        for i in 0..<p.count {
          let j = (i + 1) % p.count
          a += p[i].x * p[j].y - p[j].x * p[i].y
        }
        area += abs(a) / 2
      case .disc(_, _, let rad):
        let aspect = tankSize.x / max(tankSize.y, 1e-9)
        area += Double.pi * rad * rad * aspect
      }
    }
    return min(area, 0.95)
  }

  // MARK: Frame

  func advance(_ step: FrameStep) -> ToothpasteFrame {
    let dt = step.realDt
    realTime += dt
    shelfMode = step.shelfMode
    let size = tankSize
    let fillTop = fillFraction * size.y
    runScript(fillTop: fillTop)
    tools.runScripts(now: realTime, tank: size, fillTop: fillTop)

    // Sensors → sources → drives.
    let sample = r.motion.sample(dt: dt)
    var p = step.params
    let snapshot = r.mic.isLive ? r.mic.snapshot(count: 2048, dt: dt) : nil
    let touch = TouchSample(
      down: tools.finger != nil,
      position: tools.finger.map { SIMD2($0.position.x / size.x, $0.position.y / size.y) } ?? SIMD2(0.5, 0.5),
      speed: simd_length(tools.finger?.velocity ?? .zero) * 1000 / 0.16565)
    var sources = conditioner.step(
      motion: sample, mic: snapshot, micGain: p[.gain], pressureKPa: nil, thermal: r.thermal.sample(dt: dt),
      touch: touch, dt: dt)
    sources[ToothpasteDrives.bandSource] = band.update(snapshot, gain: p[.gain], centre: p[.band], dt: dt)
    let fieldDelta = fieldBaseline.step(fieldMicroTesla: sources[.field], dt: dt)
    sources[.fieldDelta] = fieldDelta
    let drive = router.apply(sources, to: &p, specs: r.params.specs, dt: dt, holding: step.held)
    if let kick = drive.fired(ToothpasteDrives.kickChannel), tools.finger == nil || tools.finger?.id == FakeTouchScript.touchID {
      // A beat: a poke at the surface, harder for louder onsets (a strong kick jams oobleck).
      let x = kicks.next() * size.x
      let speed = 0.3 + 0.9 * min(max(kick.strength, 0), 1)
      tools.scheduleJab(at: SIMD2(x, fillTop), depth: 0.008, speed: speed, now: realTime, rise: 0.006, hold: 0.03)
      events.append(.poke(SIMD2(x, fillTop)))
    }

    // Time.
    let timeScale = min(max(p[.time], 0.05), 2)
    let simDt = step.paused ? 0 : min(dt * timeScale, 1.0 / 15)

    // Body forces.
    let env = LabEnvironment.from(sample, gravityScale: p[.gravity])
    var gravity = step.layers.useTilt ? env.screenGravityOnly : SIMD2(0, -Gravity.g0 * p[.gravity])
    if !r.motion.isSimulated, abs(tiltOffset) > 1e-4 { tiltOffset *= exp(-dt / 1.5) }
    if abs(tiltOffset) > 1e-6 {
      let c = cos(tiltOffset), s = sin(tiltOffset)
      gravity = SIMD2(c * gravity.x - s * gravity.y, s * gravity.x + c * gravity.y)
    }
    if !(gravity.x.isFinite && gravity.y.isFinite) { gravity = SIMD2(0, -Gravity.g0) }
    var accel = env.screenAcceleration
    if !(accel.x.isFinite && accel.y.isFinite) { accel = .zero }
    if burst.left > 0 {
      burst.phase += 2 * .pi * burst.hz * simDt
      accel += burst.peak * (burst.hz > 0 ? sin(burst.phase) : 1)
      burst.left -= simDt
    }
    let vibration = SIMD2(max(0, p[.shake] + drive[ToothpasteDrives.shakeChannel]) * Gravity.g0, p[.rate])

    // Magnet: the knob is a virtual magnet under the floor (field at 1 cm); the magnetometer's Δ|B| a uniform field.
    stepMagnet(simDt, size: size)
    let magnetTesla = p[.magnet] * 1e-3
    let uniformTesla = step.layers.useMagnetometer ? fieldDelta * 1e-6 : 0
    let magnetPos = SIMD2(magnetX, -Self.magnetDepth)
    let magnetInput: (position: SIMD2<Double>, strength: Double)? =
      magnetTesla > 1e-4 ? (magnetPos, magnetTesla / MPMConstants.vacuumPermeability) : nil

    // Temperature.
    let lava = currentMaterial == "lava"
    let ambient = lava ? Self.room : p[.heat] + 273.15
    applyMaterialKnobs(p, field: max(magnetTesla, uniformTesla) / MPMConstants.vacuumPermeability)

    // Substep budget and the time the solver will really simulate.
    if let solver = r.solver, simDt > 0 {
      var q = solver.quality
      budget.noteGPU(solver.stats.gpuMilliseconds, dt: dt)
      let cap = budget.cap(for: simDt / timeScale, base: baseQuality, thermal: sources[.thermal])
      if q.maxSubsteps != cap {
        q.maxSubsteps = cap
        solver.setQuality(q)
      }
    }
    let simulated = plannedTime(simDt, gravity: gravity, accel: accel, vibration: vibration)
    simTime += simulated

    // Colliders: finger (body 0), stir paddle (body 1), props (2…).
    let stats = r.solver?.stats ?? MPMStats()
    lastStats = stats
    var colliders: [MPMCollider] = []
    var emitters: [MPMEmitter] = []
    var drains: [(position: SIMD2<Double>, radius: Double)] = []
    let fingerRadius = p[.finger] * 1e-3
    let resistance =
      stats.bodyImpulses.isEmpty || stats.simulatedTime <= 0
      ? nil : SIMD2(stats.bodyImpulses[0].x, stats.bodyImpulses[0].y) / stats.simulatedTime
    let toolRadius = tools.finger?.mode == .scoop ? Self.scoopShare * fingerRadius : fingerRadius
    let taken = tools.takeFrame(radius: toolRadius, simDt: simulated, resistance: resistance, gap: gap)
    if let magnetDrag = tools.magnetTarget {
      magnetX = min(max(magnetDrag, 0), size.x)
      magnetSlide = nil
      tools.magnetTarget = nil
    }
    let finger = taken?.state
    if let f = finger, let c = taken?.collider {
      switch f.tool {
      case .probe:
        colliders.append(
          MPMCollider(shape: .circle(radius: c.radius), position: c.position, velocity: c.velocity, bodyIndex: 0))
      case .pour:
        emitters.append(pourEmitter(at: f.position, material: pourMaterial))
      case .scoop:
        drains.append((f.position, f.radius))
      case .prop:
        break
      }
    }
    if let sp = scriptedPour {
      if simTime < sp.until {
        emitters.append(pourEmitter(at: SIMD2(sp.x * size.x, size.y - 0.006), material: sp.material))
      } else {
        scriptedPour = nil
      }
    }
    let paddle = stepPaddle(p[.stir], simulated: simulated, fillTop: fillTop, size: size)
    if let pd = paddle {
      let omega = pd.angularVelocity
      colliders.append(
        MPMCollider(
          shape: .capsule(halfLength: pd.halfLength, radius: pd.radius), position: pd.position,
          angle: pd.angle - omega * simulated, angularVelocity: omega, bodyIndex: 1))
    }
    colliders.append(contentsOf: bay.colliders(rigid: r.rigid))

    // v2: the glass lens (a force-limited probe collider of its own, body 14) and the tube (Tube.swift: the nozzle's
    // path, the striped emitter and the bore's grip, body 15).
    let lensResistance = Self.bodyForce(stats, LensProbe.body)
    let lens = lensCollider(step.lens, simulated: simulated, resistance: lensResistance)
    if let c = lens.collider { colliders.append(c) }
    let squeezed = r.catalog.material(step.squeeze.material)
    let tubeFrame = tube.step(
      step.squeeze, tank: size, cell: cell, simulated: simulated, solver: r.solver,
      gripImpulse: stats.bodyImpulses.count > Tube.gripBody
        ? SIMD2(stats.bodyImpulses[Tube.gripBody].x, stats.bodyImpulses[Tube.gripBody].y) : nil,
      impulseTime: stats.simulatedTime, density: squeezed.material.density, gap: gap,
      gravity: simd_length(gravity - accel), simTime: simTime)
    let nozzle = tubeFrame.nozzle
    if tubeFrame.flowing { emitters.append(squeezeEmitter(nozzle, speed: tube.speed)) }
    if let d = tubeFrame.retract { drains.append(d) }
    pasteEvents.append(contentsOf: tubeFrame.events)

    // Probe: the finger's leading edge, else the lens's, else the strongest-sheared candidate.
    let candidates = probeCandidates(paddle: paddle, fillTop: fillTop, size: size)
    let fingerProbe = tools.probePoint(radius: finger?.radius ?? fingerRadius, skin: cell, gravity: gravity)
    let lensProbe = lens.used.map { l -> SIMD2<Double> in
      let down = simd_length(gravity) > 1e-6 ? simd_normalize(gravity) : SIMD2(0, -1)
      let dir = simd_length(l.velocity) > 0.005 ? simd_normalize(l.velocity) : down
      return l.centre + dir * (l.radius + cell)
    }
    let probePoint = scanner.point(finger: fingerProbe ?? lensProbe, candidates: candidates)

    let input = MPMFrameInput(
      dt: simDt, gravity: gravity, frameAcceleration: accel, vibration: (vibration.x, vibration.y),
      ambientTemperature: ambient, magneticField: SIMD2(0, uniformTesla / MPMConstants.vacuumPermeability),
      magnet: magnetInput, colliders: Array(colliders.prefix(MPMSolver.maxColliders)), emitters: emitters,
      drains: drains, probe: probePoint, grips: tubeFrame.grip.map { [$0] } ?? [])
    pending = simDt > 0 ? input : nil

    // Box2D, with last frame's fluid impulses, in the same accelerating tank frame as the fluid (gravity minus the
    // phone's shake; the floor vibration is too fast for Box2D's frame step and is left to the fluid).
    let fluidDensity = (r.catalog as? ToothpasteCatalogData)?.running(currentMaterial).density
      ?? r.catalog.material(currentMaterial).material.density
    events.append(
      contentsOf: bay.step(
        rigid: r.rigid, gravity: gravity - accel, stats: stats, dt: simulated, fluidDensity: fluidDensity,
        fluidViscosity: propViscosity, gap: gap, cell: cell, vibration: { [encodes] in encodes.meanVibration(for: $0) }))
    events.append(contentsOf: tools.events)
    tools.events.removeAll()

    // Quality policy (a finer quality steps down to standard after 3 s of lag or GPU overrun, or when the phone is hot).
    if let solver = r.solver, simDt > 0,
      let q = budget.observe(
        lagging: stats.lagging, dt: dt, current: solver.quality, gpuMilliseconds: stats.gpuMilliseconds,
        thermal: sources[.thermal])
    {
      baseQuality = q
      solver.setQuality(q)
      events.append(.qualityChanged)
    }

    let probe = scanner.observe(stats, candidates: candidates, fingerDown: finger?.tool == .probe || lens.used != nil)
    let channels = pasteChannels(probe: probe, stats: stats)
    detectPasteEvents(channels, probe: probe, stats: stats)
    for case .propHit(let speed) in events {
      pasteEvents.append(PasteEvent(kind: .impact, simTime: simTime, position: nil, magnitude: speed))
    }
    let magnetState: MagnetState? =
      magnetTesla > 1e-4 || uniformTesla > 1e-4
      ? MagnetState(position: magnetTesla > 1e-4 ? magnetPos : nil, fieldTesla: magnetTesla + uniformTesla) : nil
    let frame = ToothpasteFrame(
      realDt: dt, simDt: simulated, simTime: simTime, params: p, sources: sources, tank: size, input: input, stats: stats,
      material: currentMaterial, finger: finger, paddle: paddle, props: bay.states(rigid: r.rigid),
      magnet: magnetState, probe: probe, events: events, simulatedMotion: r.motion.isSimulated, vibration: vibration,
      lens: lens.used, nozzle: nozzle, channels: channels, pasteEvents: pasteEvents)
    events.removeAll()
    pasteEvents.removeAll()
    return frame
  }

  // MARK: v2 — lens, squeeze, channels, paste events (stubs for PLAY)

  /// The fluid's force on body `index` over the latest completed solver frame, N (nil before the first).
  static func bodyForce(_ stats: MPMStats, _ index: Int) -> SIMD2<Double>? {
    guard index < stats.bodyImpulses.count, stats.simulatedTime > 0 else { return nil }
    let j = stats.bodyImpulses[index]
    return SIMD2(j.x, j.y) / stats.simulatedTime
  }

  /// The lens as a kinematic circle swept from where its collider ended the last frame toward the requested centre.
  /// Like a fingertip it is force-limited (`LensProbe`): the paste's push back on it (body 14) slows it, so jammed
  /// oobleck, lava or Silly Putty stop the glass while toothpaste lets it through. The disc grows from a quarter of its
  /// radius over 40 ms where it lands, so dropping it into paste does not fling a disc of paste out in one substep.
  private func lensCollider(_ l: LensState, simulated: Double, resistance: SIMD2<Double>?)
    -> (collider: MPMCollider?, used: LensState?)
  {
    guard l.active, l.radius > 0, l.centre.x.isFinite, l.centre.y.isFinite else {
      lensAt = nil
      lensAge = 0
      lensResist = 0
      lensLimit = LensState.maxSpeed
      return (nil, nil)
    }
    let start = lensAt ?? l.centre
    var v = simulated > 0 ? (l.centre - start) / simulated : SIMD2<Double>.zero
    var speed = simd_length(v)
    if speed > LensState.maxSpeed {
      v *= LensState.maxSpeed / speed
      speed = LensState.maxSpeed
    }
    if simulated > 0 {
      let dir = speed > 1e-5 ? v / speed : lensHeading
      let push = LensProbe.pushPressure * 2 * l.radius * max(gap, 0.001)
      let along = max(0, -simd_dot(resistance ?? .zero, dir))
      lensResist += (along - lensResist) * min(1, simulated / TouchTools.resistTime)
      if lensResist > push {
        lensLimit = max(TouchTools.minSpeed, min(lensLimit, max(speed, TouchTools.minSpeed)) * push / lensResist)
      } else {
        lensLimit = min(
          LensState.maxSpeed,
          lensLimit * exp(simulated / TouchTools.recoverTime) + TouchTools.recoverAcceleration * simulated)
      }
      if speed > lensLimit {
        v *= lensLimit / speed
        speed = lensLimit
      }
      if speed > 1e-4 { lensHeading = v / speed }
    }
    let end = start + v * simulated
    if simulated > 0 {
      lensAt = end
      lensAge += simulated
    }
    let grow = min(1, 0.25 + 0.75 * lensAge / TouchTools.growTime)
    var used = l
    used.centre = end
    used.velocity = v
    let collider = MPMCollider(
      shape: .circle(radius: l.radius * grow), position: start, velocity: v, bodyIndex: LensProbe.body)
    return (collider, used)
  }

  /// Paste at `speed` through the bore: a one-cell slot across the top of the bore (the piston's face), fed at speed ×
  /// bore width ÷ the area of one particle (2 × 2 per cell), so the ribbon leaves at rest density; the grip over the
  /// bore pushes it out at that speed (Tube.swift).
  private func squeezeEmitter(_ n: NozzleState, speed: Double) -> MPMEmitter {
    let info = r.catalog.material(n.material)
    let rate = speed * 2 * n.radius / (cell * cell / 4)
    return MPMEmitter(
      position: n.position + SIMD2(0, n.radius - cell / 2), radius: n.radius, velocity: SIMD2(0, -speed),
      material: info.slot, rate: rate, temperature: fillTemperature(n.material), stripes: n.stripes, slotLength: cell)
  }

  /// The channels at the probe: γ̇ and σ (log levels), structure λ (or the jammed share for a shear-thickening paste).
  private func pasteChannels(probe: ProbeReading, stats: MPMStats) -> PasteChannels {
    let jams = r.catalog.material(currentMaterial).material.dst != nil
    let structure = min(max(jams ? stats.jammedFraction : stats.meanStructure, 0), 1)
    var c = PasteChannels()
    c.shear = SignalChannel(value: probe.shearRate, level: PasteChannels.logLevel(probe.shearRate, in: PasteChannels.shearRange))
    c.stress = SignalChannel(value: probe.stress, level: PasteChannels.logLevel(probe.stress, in: PasteChannels.stressRange))
    c.structure = SignalChannel(value: structure, level: structure)
    c.yieldedFraction = stats.yieldedFraction
    c.jammedFraction = stats.jammedFraction
    c.state = Self.stateWord(solid: probe.solidFraction, jammed: stats.jammedFraction, jams: jams)
    c.simTime = simTime
    return c
  }

  /// The lens readout's state word from the probe's solid share (unyielded or jammed material near it).
  nonisolated static func stateWord(solid: Double, jammed: Double, jams: Bool) -> PasteStateWord {
    if solid >= 0.5 { return jams && jammed > 0.02 ? .jammed : .holding }
    return solid > 0.1 ? .yielding : .flowing
  }

  private func detectPasteEvents(_ c: PasteChannels, probe: ProbeReading, stats: MPMStats) {
    if probe.fingerDown {
      if probe.solidFraction >= 0.6 { yieldArmed = true }
      if yieldArmed, probe.solidFraction < 0.3 {
        yieldArmed = false
        pasteEvents.append(PasteEvent(kind: .yield, simTime: simTime, position: probe.position, magnitude: probe.stress))
      }
    } else {
      yieldArmed = false
    }
    if stats.jammedFraction < 0.01 { jamArmed = true }
    if jamArmed, stats.jammedFraction >= 0.05 {
      jamArmed = false
      pasteEvents.append(PasteEvent(kind: .jam, simTime: simTime, position: probe.position, magnitude: probe.stress))
    }
  }

  private func pourEmitter(at point: SIMD2<Double>, material: MaterialID) -> MPMEmitter {
    let info = r.catalog.material(material)
    let radius = 0.003, speed = 0.15
    let rate = speed * 2 * radius / (cell * cell / 4)
    return MPMEmitter(
      position: point, radius: radius, velocity: SIMD2(0, -speed), material: info.slot, rate: rate,
      temperature: fillTemperature(material))
  }

  /// The stir paddle: spins up and down over about 0.3 s, and grows from nothing over 0.2 s where it appears.
  private func stepPaddle(_ revPerSecond: Double, simulated: Double, fillTop: Double, size: SIMD2<Double>) -> PaddleState? {
    let target = revPerSecond > 0.02 ? 2 * Double.pi * revPerSecond : 0
    stirOmega += (target - stirOmega) * min(1, simulated / 0.3)
    if target > 0 { paddleGrowth = min(1, paddleGrowth + simulated / 0.2) } else if abs(stirOmega) < 0.3 {
      paddleGrowth = 0
    }
    guard paddleGrowth > 0 else { return nil }
    stirAngle += stirOmega * simulated
    return PaddleState(
      position: SIMD2(size.x / 2, max(fillTop * 0.5, 0.012)), angle: stirAngle, halfLength: 0.012 * paddleGrowth,
      radius: 0.002, angularVelocity: stirOmega)
  }

  private func probeCandidates(paddle: PaddleState?, fillTop: Double, size: SIMD2<Double>) -> [SIMD2<Double>] {
    var c: [SIMD2<Double>] = []
    if let pd = paddle { c.append(pd.position + SIMD2(cos(pd.angle), sin(pd.angle)) * (pd.halfLength + 0.003)) }
    for s in bay.states(rigid: r.rigid) where simd_length(s.velocity) > 0.005 {
      c.append(s.position + simd_normalize(s.velocity) * 0.007)
    }
    let h = max(fillTop, 0.01)
    for fy in [0.3, 0.75] {
      for fx in [0.2, 0.5, 0.8] { c.append(SIMD2(fx * size.x, fy * h)) }
    }
    return c
  }

  private func stepMagnet(_ dt: Double, size: SIMD2<Double>) {
    guard let s = magnetSlide else { return }
    let d = s.target - magnetX
    let stepLen = s.speed * dt
    if abs(d) <= stepLen {
      magnetX = s.target
      magnetSlide = nil
    } else {
      magnetX += stepLen * (d > 0 ? 1 : -1)
    }
    magnetX = min(max(magnetX, 0), size.x)
  }

  /// The simulated seconds the solver will really advance for a request of `requested` (MPMSubstepRule, the same
  /// inputs the solver uses; its depth and speed come from the latest stats, so this can differ by a substep).
  private func plannedTime(
    _ requested: Double, gravity: SIMD2<Double>, accel: SIMD2<Double>, vibration: SIMD2<Double>
  ) -> Double {
    guard requested > 0, let solver = r.solver else { return requested }
    let stats = solver.stats
    let size = solver.domain.size
    let dx = solver.cellSize
    let g = gravity - accel
    let gl = simd_length(g)
    let chord = gl > 1e-6 ? size.x * abs(g.y / gl) + size.y * abs(g.x / gl) : size.x
    let area = Double(max(stats.liveParticles, 1)) * 0.25 * dx * dx
    let depth = min(area / max(chord, dx), simd_length(size))
    let shearWave = solver.materialsInUse.compactMap { $0 < solver.materials.count ? solver.materials[$0] : nil }
      .map { ($0.shearModulus / max($0.density, 1)).squareRoot() }.max() ?? 0
    let plan = MPMSubstepRule.plan(
      frameTime: requested, cellSize: dx, peakAcceleration: simd_length(gravity) + simd_length(accel) + abs(vibration.x),
      depth: depth, maxSpeed: stats.maxSpeed, vibrationFrequency: vibration.x > 0 ? vibration.y : 0,
      shearWaveSpeed: shearWave, quality: solver.quality)
    return plan.simulatedTime
  }

  func encode(into cmd: MTLCommandBuffer) {
    guard let solver = r.solver, let input = pending else { return }
    let start = solver.simulatedTime
    solver.encode(into: cmd, input: input)
    encodes.record(start: start, end: solver.simulatedTime, vibration: input.vibration)
    scanner.didEncode()
    pending = nil
  }

  /// The solver frames encoded lately (their start on the solver's clock, length and floor vibration), so a frame's
  /// statistics can be paired with the vibration it ran under.
  private(set) var encodes = EncodeLog()

  // MARK: Knobs → material

  /// The current material's row of the solver's table from the Fluid page and the card knobs (only when they change).
  /// At the material's defaults the row is the preset, bit for bit.
  private func applyMaterialKnobs(_ p: ParamValues, field: Double) {
    guard let solver = r.solver else { return }
    let key = [p[.yield], p[.consistency], p[.index], p[.packing], p[.memory], p[.rebuild], field]
    guard key != appliedKey else { return }
    let materialKeyChanged = appliedKey.count != key.count || Array(appliedKey.prefix(6)) != Array(key.prefix(6))
    appliedKey = key
    let info = r.catalog.material(currentMaterial)
    let m = materialKeyChanged ? Self.material(info.material, knobs: p, specs: r.params.specs) : running
    running = m
    // The viscosity props feel (their implicit thin-tank drag): the steady flow curve at 10 s⁻¹, at the reference
    // temperature; for shear-thickening oobleck, the curve at the rate the prop drives (Props.swift).
    if materialKeyChanged {
      propViscosity = PropViscosity.of(thickening: m.dst != nil, memory: m.dst?.meltTime ?? 0.15) {
        FlowCurve.stress(m, shearRate: $0, temperature: m.referenceTemperature)
      }
    }
    (r.catalog as? ToothpasteCatalogData)?.setLive(currentMaterial, material: m, field: field)
    guard materialKeyChanged else { return }
    var table = solver.materials
    if info.slot < table.count, table[info.slot] != m {
      table[info.slot] = m
      solver.materials = table
    }
  }
  private var running: ContinuumMaterial = ContinuumPresets.oobleck
  private var propViscosity = PropViscosity()

  /// The preset `base` with the material knobs applied. A knob at its default leaves its parameters untouched.
  static func material(_ base: ContinuumMaterial, knobs p: ParamValues, specs: [ParamID: ParamSpec]) -> ContinuumMaterial {
    var m = base
    func moved(_ id: ParamID) -> Bool {
      guard let s = specs[id] else { return false }
      return abs(p[id] - s.defaultValue) > 1e-9 * max(1, abs(s.defaultValue))
    }
    if moved(.yield) {
      let baseYield = ToothpasteKnobs.yieldStress(base)
      let y = p[.yield] <= 0.1 ? 0 : p[.yield]
      if baseYield > 0 {
        m.yieldBroken *= y / baseYield
        m.yieldStructure *= y / baseYield
      } else {
        m.yieldBroken = y
      }
    }
    if moved(.consistency) {
      let k = max(p[.consistency], 1e-4)
      if base.consistency > 0 {
        m.consistency = k
      } else if base.fluidity > 0 {
        m.fluidity = 1 / k
      } else if base.dst != nil {
        m.dst?.solventViscosity = k
      } else {
        m.consistency = k
      }
    }
    if moved(.index) { m.flowIndex = min(max(p[.index], 0.2), 1) }
    if moved(.packing), m.dst != nil { m.dst?.phi = p[.packing] }
    if moved(.memory) {
      let lambda = max(p[.memory], 1e-4)
      if m.dst != nil {
        m.dst?.meltTime = lambda
      } else {
        // λ = η/G → G, kept between the yield-strain floor (τ_y/G ≤ 5 %) and the substep budget (G ≤ 30 kPa, or the
        // preset's own G if that is higher).
        let gFloor = max(20 * ToothpasteKnobs.yieldStress(m), 50)
        let gCeiling = max(3.0e4, base.shearModulus)
        m.shearModulus = min(max(ToothpasteKnobs.memoryViscosity(m) / lambda, gFloor), gCeiling)
        m.bulkModulus = max(m.bulkModulus, 2 * m.shearModulus)
      }
    }
    if moved(.rebuild), base.buildRate > 0 { m.buildRate = 1 / max(p[.rebuild], 0.01) }
    // Keep the yield strain within 5 % when Yield is raised past what G holds.
    if m.dst == nil { m.shearModulus = min(max(m.shearModulus, 20 * ToothpasteKnobs.yieldStress(m)), max(3.0e4, base.shearModulus)) }
    m.bulkModulus = max(m.bulkModulus, 2 * m.shearModulus)
    return m
  }

  // MARK: Experiment scripts

  private func runScript(fillTop: Double) {
    let size = tankSize
    while scriptIndex < script.count, script[scriptIndex].at <= simTime {
      let s = script[scriptIndex]
      scriptIndex += 1
      let top = maxFillTop(fillTop: fillTop) + 0.012
      switch s.action {
      case .jab(let fx, let fb, let speed):
        let x = fx * size.x, bottom = max(fb * size.y, 0.004)
        tools.scheduleJab(at: SIMD2(x, bottom), depth: 0, speed: speed, now: realTime, rise: max(top - bottom, 0.004), hold: 0.25)
      case .press(let fx, let fb, let speed, let hold):
        let x = fx * size.x, bottom = max(fb * size.y, 0.004)
        let travel = (top - bottom) / max(speed, 0.001)
        tools.schedulePath([(0, SIMD2(x, top)), (travel, SIMD2(x, bottom)), (travel + hold, SIMD2(x, bottom))], now: realTime)
      case .knob(let id, let v):
        r.params[id] = v
      case .tilt(let angle):
        if r.motion.isSimulated { tiltOffset = angle }
      case .shake(let g, let hz, let seconds):
        burst = (seconds, SIMD2(g * Gravity.g0, 0), hz, 0)
      case .pour(let m, let fx, let seconds):
        scriptedPour = (m, fx, simTime + seconds)
      case .drop(let kind, let fx, let gently):
        let info = r.catalog.prop(kind)
        // Gently: touching the fluid's surface under it (plus the one-cell collider skin). A collider that lands even at
        // 0.2 m/s ploughs a whole frame (3 mm at 60 Hz) into a stiff bed before the fluid's reaction arrives, which
        // unbuilds rested quicksand around it.
        let radius = info.shape.boundingRadius
        let surface = gently ? surfaceHeight(at: fx * size.x, halfWidth: radius) ?? 0.95 * maxFillTop(fillTop: fillTop) : 0
        let y = gently ? min(surface + radius + cell + 0.0002, size.y - 0.012) : size.y - 0.012
        bay.drop(info, at: SIMD2(fx * size.x, y), gap: gap, rigid: r.rigid)
        events.append(.propDropped(kind))
      case .magnet(let fx, let seconds):
        magnetSlide = (fx * size.x, abs(fx * size.x - magnetX) / max(seconds, 0.05))
      }
    }
  }

  /// The top of the fluid within `halfWidth` of x, m (one read of the particle buffer, for placing a prop gently; it
  /// may be a frame old while the GPU works, which is close enough).
  private func surfaceHeight(at x: Double, halfWidth: Double) -> Double? {
    guard let solver = r.solver else { return nil }
    let top = solver.debugParticles().lazy.filter { $0.enabled && abs($0.position.x - x) < halfWidth }.map(\.position.y)
      .max()
    return top.map { $0 + 0.25 * solver.cellSize }
  }

  /// The highest fluid the scripts must start above, m: the fill top, or the tallest shape of the experiment.
  private func maxFillTop(fillTop: Double) -> Double { max(fillTop, scriptTop) }
  private var scriptTop = 0.0

  // MARK: Input

  func touches(_ touches: [TankTouch]) {
    let marker = r.params[.magnet] > 0.5 ? SIMD2(magnetX, 0) : nil
    for t in touches {
      tools.handle(t, mode: shelfMode, rigid: r.rigid, pourMaterial: pourMaterial, magnetMarker: marker)
    }
  }

  func twoFinger(_ g: TankTwoFinger) {
    // Simulated tilt (Simulator only): drag sideways tips the phone (gravity follows the drag), drag up/down pitches it.
    guard r.motion.isSimulated, !r.motion.isLive, abs(g.scale - 1) < 0.08 else { return }
    tiltOffset = min(max(tiltOffset + Double(g.delta.width) * 0.008, -1.2), 1.2)
    r.motion.simulatedTilt(dx: 0, dy: Double(g.delta.height))
  }

  /// Ends a running experiment's demonstration: its remaining script steps, a scripted pour, a synthetic shake and a
  /// magnet slide (Fill, Refill and Reset start a plain tank; without this a "Honey, cold and warm" pour kept pouring
  /// honey into a fresh tank of water for the rest of its 3.2 s).
  private func stopScript() {
    script = []
    scriptIndex = 0
    scriptedPour = nil
    burst.left = 0
    magnetSlide = nil
  }

  func perform(_ command: ToothpasteCommand) {
    let size = tankSize
    switch command {
    case .refill:
      stopScript()
      freshChamber(currentMaterial)
    case .fill(let id):
      stopScript()
      select(id)
      pourMaterial = id
      freshChamber(id)
      events.append(.materialChanged(id))
    case .pourMaterial(let id):
      pourMaterial = id
    case .dropProp(let kind):
      bay.drop(r.catalog.prop(kind), at: SIMD2(size.x / 2, size.y - 0.012), gap: gap, rigid: r.rigid)
      events.append(.propDropped(kind))
    case .clearProps:
      bay.clear(rigid: r.rigid)
    case .experiment(let id):
      guard let e = r.catalog.experiments.first(where: { $0.id == id }) else { return }
      let recipe = ToothpasteExperiments.recipes[id] ?? ExperimentRecipe()
      let material = e.material ?? currentMaterial
      select(material)
      pourMaterial = material
      // Each experiment starts from the default world (select() already reset the Fluid page, the card knobs and Heat):
      // otherwise "Oobleck monsters" left Shake at 17 g and Listen on, and "Toothpaste holds shape" ran on a floor
      // shaking at 17 g.
      for id in Self.experimentResets {
        if let spec = r.params.specs[id] { r.params[id] = spec.defaultValue }
      }
      r.params.apply(e.values)
      bay.clear(rigid: r.rigid)
      burst.left = 0
      tiltOffset = 0
      scriptedPour = nil
      magnetX = recipe.magnetX * size.x
      magnetSlide = nil
      let layers =
        recipe.layers.isEmpty && recipe.shapes.isEmpty
        ? [(material, r.catalog.material(material).fillFraction)] : recipe.layers
      refill(layers: layers, shapes: recipe.shapes)
      for kind in recipe.props { perform(.dropProp(kind)) }
      router.reset()
      simTime = 0
      script = recipe.script
      scriptIndex = 0
      events.append(.experimentApplied(id))
    case .poke(let point):
      tools.scheduleJab(at: point, depth: 0.012, speed: 0.4, now: realTime, rise: 0.008, hold: 0.15)
      events.append(.poke(point))
    case .punch(let point):
      tools.scheduleJab(at: point, depth: 0.02, speed: 1.2, now: realTime, rise: 0.012, hold: 0.25)
      events.append(.punch(point))
    case .tilt(let dx, let dy):
      tiltOffset = min(max(tiltOffset + dx, -1.2), 1.2)
      if r.motion.isSimulated, dy != 0 { r.motion.simPitch = min(max(r.motion.simPitch - dy, -0.2), .pi - 0.2) }
    case .shakeOnce:
      burst = (0.5, SIMD2(1.2 * Gravity.g0, 0), 12, 0)
    case .quality(let q):
      baseQuality = q
      r.solver?.setQuality(q)
      events.append(.qualityChanged)
    case .resetAll:
      stopScript()
      r.params.resetAll()
      bay.clear(rigid: r.rigid)
      tiltOffset = 0
      select(currentMaterial)
      freshChamber(currentMaterial)
    }
  }

  /// A synthetic shake of the chamber (tests and lab scenarios; the `shake` script step does the same): `g` peak
  /// acceleration along x in g, at `hz`, for `seconds` of simulated time.
  func shake(g: Double, hz: Double, seconds: Double) {
    burst = (max(seconds, 0), SIMD2(g * Gravity.g0, 0), max(hz, 0), 0)
  }

  // MARK: Telemetry

  func telemetry(frame f: ToothpasteFrame, framesPerSecond: Double) -> ToothpasteTelemetry {
    var t = ToothpasteTelemetry()
    t.material = f.material
    t.viscosity = f.stats.meanViscosity
    t.shearRate = f.probe.shearRate
    t.stress = f.probe.stress
    t.probeViscosity = f.probe.viscosity
    t.solidFraction = f.probe.solidFraction
    t.fingerDown = f.probe.fingerDown
    t.timeScale = f.params[.time]
    let g = f.input.gravity
    t.tiltDegrees = simd_length(g) > 1e-6 ? abs(atan2(g.x, -g.y)) * 180 / .pi : 0
    t.shakeG = f.sources[.shake]
    t.fieldMicroTesla = f.sources[.field]
    t.micDBFS = r.mic.isLive ? f.sources[.micLevel] * 45 - 55 : nil
    t.simulatedMotion = f.simulatedMotion
    t.lagging = f.stats.lagging
    t.particles = f.stats.liveParticles
    t.substeps = f.stats.substeps
    t.gpuMilliseconds = f.stats.gpuMilliseconds
    t.nanCount = f.stats.nanCount
    t.overflowCount = f.stats.overflowCount
    t.framesPerSecond = framesPerSecond
    t.fillFraction = fillFraction
    return t
  }
}

/// The glass lens as a probe (REDESIGN.md §3, §5.3): its own body index for the paste's push back, and the hardest the
/// glass pushes (as a fingertip, TouchTools.pushPressure, over the disc's diameter × the tank gap).
enum LensProbe {
  static let body = 14
  static let pushPressure = TouchTools.pushPressure
}
