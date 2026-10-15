// FeelMap.swift — OWNER: PLAY (was FEEL; Documentation/REDESIGN-OWNERSHIP.md).
//
// The pure half of Toothpaste Toy's feel: one frame of simulation numbers in (`FeelSignals`), haptic commands, the gloop voice's
// controls and its event triggers out (`FeelOutput`). Nothing here touches Core Haptics, AVAudio or the main actor
// (except `FeelSignals.make`, which reads the catalog), so every rule is testable in the Simulator, which has no
// haptics. `ToothpasteFeel` applies the output to `LabFeedback`; `GloopDriver` writes it to the voice's control slots.
//
// Haptics (labkit-from-orbitals-spectra.md §5.3, constants are LabKit's proposals, to tune on the iPhone 15 Pro Max):
//   hum   finger in the fluid: StressFeel (I = 0.15·log₁₀(1 + σ̃/0.1 Pa), S = 0.15 + 0.7·s_f + 0.15·min(1, v/0.5 m/s);
//         held at S ≥ 0.95 while jammed); no finger: the slosh law; a vibrating floor (Shake ≥ 0.5 g) adds a modest
//         buzz whose sharpness rises with its rate. Causal: FeelCauses or the vibrating floor must be live.
//   taps  yield crossing → .detent; jam onset → transient(0.9 + 0.1·f, 0.85); grains → Poisson
//         transients (FeelEventDetector, hysteresis); poke → .poke; punch → transient(1, 0.95) on a jamming fluid
//         (the jam onset that follows within 0.2 s is not doubled), else .poke; the jammed solid failing (unjam) →
//         a dry crack transient(0.6, 1.0), then .release 40 ms later as it gives; prop impact → transient(v/0.8 m/s, 0.7,
//         minGap 0.04 s); a prop falling into the fluid → a dull transient; refill → ramp(0.55 s); MR fluid with a
//         field → Gyre's crackle law while something moves; a mic onset with Listen up → .ripple; a strand or a drop
//         pinching off → .pinch (0.4, 0.3), inferred from the gesture, not detected in the particles: a finger
//         leaving a thick fluid, or the end of a pour stream (PHYS reports no topology events).
//         Material and experiment choices are answered by the UI (.select, success()), not here.
// Sound triggers are rate-limited: squelch ≤ 8 per second (one per 0.125 s, §6.3), cracks one per 0.15 s (a punch
// and the jam it causes are one knock), splashes one per 0.05 s.
//
// v2 (PLAY, 14 October 2026; REDESIGN.md §3–§5): the glass lens is felt as the fingertip probe is (hum, plunge and
// suction, yield/jam/unjam transients) whenever no canvas finger probes. The tube: while paste leaves the nozzle the hum
// is a soft continuous pressure that tracks the extrusion speed (`squeezeHum`, low sharpness), and the voice plays the
// squeeze — a wet squish whose level follows the speed and the creak of the paste slipping along the nozzle wall (a
// click train whose rate rises with the speed; stiff pastes creak, honey and water do not: `GloopTimbre.creak`); the
// first push is a soft squelch; the tear-off (`PasteEvent.Kind.tearOff`, once per event) is a crisp haptic tick and a
// squelch. Illustrative, like the rest of the voice.

import Foundation
import simd
import LabKitCore
import LabKitFeedback
import LabKitRigid

// MARK: - Material character

/// How a material's gloop voice sounds (illustrative choices, not measurements): `thick` 0 (water: small, bright,
/// short bubbles) … 1 (toothpaste: big, low, slow glorps); `grit` 0 (smooth) … 1 (sand: crunchy clicks).
struct GloopTimbre: Sendable, Equatable {
  var thick: Double
  var grit: Double

  /// v2: how much the paste creaks as it is squeezed through the nozzle, 0…1 (stick–slip of a stiff paste along the
  /// nozzle wall; an illustrative choice: yield-stress pastes creak, Newtonian liquids glide).
  static func creak(_ id: MaterialID) -> Double {
    switch id {
    case "toothpaste": 1
    case "mayonnaise": 0.6
    case "ketchup": 0.55
    case "yogurt", "sillyPutty", "slime": 0.4
    case "oobleck", "quicksand": 0.5
    case "mrFluid", "paint", "lava": 0.3
    case "honey": 0.1
    default: 0
    }
  }

  static func of(_ id: MaterialID) -> GloopTimbre {
    switch id {
    case "waterLike": GloopTimbre(thick: 0, grit: 0)
    case "honey": GloopTimbre(thick: 0.85, grit: 0)
    case "ketchup": GloopTimbre(thick: 0.6, grit: 0)
    case "mayonnaise": GloopTimbre(thick: 0.7, grit: 0)
    case "toothpaste": GloopTimbre(thick: 0.9, grit: 0)
    case "oobleck": GloopTimbre(thick: 0.45, grit: 0.6)
    case "slime": GloopTimbre(thick: 0.55, grit: 0)
    case "sillyPutty": GloopTimbre(thick: 0.8, grit: 0.1)
    case "yogurt": GloopTimbre(thick: 0.55, grit: 0)
    case "quicksand": GloopTimbre(thick: 0.5, grit: 0.85)
    case "mrFluid": GloopTimbre(thick: 0.5, grit: 0.35)
    case "paint": GloopTimbre(thick: 0.4, grit: 0)
    case "lava": GloopTimbre(thick: 0.9, grit: 0.45)
    default: GloopTimbre(thick: 0.5, grit: 0)
    }
  }
}

// MARK: - In

/// What FEEL reads from one frame, as plain values (tests script these directly).
struct FeelSignals: Sendable {
  struct Finger: Sendable, Equatable {
    var position: SIMD2<Double>
    var velocity: SIMD2<Double>
    var radius: Double
    var tool: FingerState.Tool
  }

  /// The tube (`ToothpasteFrame.nozzle`): paste leaving the nozzle at `speed` (m/s, the tube's ramped extrusion speed).
  struct Squeeze: Sendable, Equatable {
    var emitting = false
    var speed = 0.0
    /// The paste in the tube (nil: the tank's).
    var material: MaterialID?
  }

  struct Prop: Sendable, Equatable {
    var id: Int
    var position: SIMD2<Double>
    var velocity: SIMD2<Double>
    /// Bounding radius, m.
    var radius: Double
  }

  /// Real seconds since the last frame.
  var dt = 1.0 / 120
  /// Simulated time moved this frame (false while frozen).
  var running = true
  var material: MaterialID = "oobleck"
  var timbre = GloopTimbre(thick: 0.5, grit: 0)
  /// The material can jam (a Wyart–Cates block): only then is the probe's solid fraction a *jammed* fraction.
  var jams = false
  /// τ_y from the Yield knob, Pa (nil: none).
  var yieldStress: Double?
  /// The material's consistency (Pa·sⁿ) when nothing flows yet.
  var restingViscosity = 1e-3
  var finger: Finger?
  /// v2: the glass lens while it is in the chamber (tool `.probe`): felt as the probe whenever no canvas finger probes.
  var lens: Finger?
  /// v2: the tube this frame (REDESIGN.md §5).
  var squeeze = Squeeze()
  /// v2: this frame's paste events (the tear-off's tick; yield and jam are felt at the probe, impacts through props).
  var pasteEvents: [PasteEvent] = []
  /// Probe: equivalent shear stress (Pa) and unyielded-or-jammed share.
  var probeStress = 0.0
  var probeSolid = 0.0
  /// Tank: mean secant viscosity of the flowing fluid (Pa·s), kinetic energy (J) and its slosh reference (J).
  var meanViscosity = 0.0
  var kineticEnergy = 0.0
  var sloshReference = 0.0
  var tankJammed = 0.0
  /// Floor vibration: amplitude m/s², frequency Hz.
  var vibration = SIMD2<Double>.zero
  var fieldTesla = 0.0
  /// Estimated free-surface height at rest at x = `surfaceCentreX`, m, and the surface's slope dy/dx (a tilted phone
  /// tilts it: the surface lies across the gravity the fluid feels).
  var surface = 0.0
  var surfaceSlope = 0.0
  var surfaceCentreX = 0.0
  var props: [Prop] = []
  var events: [SimEvent] = []
  var sources = ModSources()
  var listen = 0.0
  var drives = DriveTarget.shake
  var micLive = false
  /// Band knob, Hz.
  var band = 80.0
  /// Level of the continuous layers (body, drag, hiss, floor hum, background bubbles and grains): × 0.3 with the
  /// microphone live, 0 in Low Power Mode, 0 while frozen (`ToothpasteBedMix`). `GloopDriver.write` applies it to the
  /// voice's controls; the mapper uses it only for the bubbles and clicks it spawns itself with the microphone live.
  /// One-shot events are never scaled.
  var bedScale = 1.0

  /// The resting surface's height at `x`, m.
  func surfaceHeight(at x: Double) -> Double {
    let h = surface + surfaceSlope * (x - surfaceCentreX)
    return h.isFinite ? h : surface
  }
}

// MARK: - Out

/// A haptic command for `LabFeedback` / `HapticEngine`.
enum FeelHaptic: Sendable, Equatable {
  case tap(HapticTap)
  case event(FeelEvent)
  case transient(intensity: Double, sharpness: Double, minGap: Double)
  case ramp(duration: Double)
  case crackle(fieldMicroTesla: Double, depth: Double)
}

/// The gloop voice's continuous controls (see `GloopKernel.Slot`).
struct GloopControls: Sendable, Equatable {
  var pitch = 220.0
  var drone = 0.0
  var thick = 0.5
  var grains = 0.0
  var drag = 0.0
  var bubbles = 0.0
  var hiss = 0.0
  var hum = 0.0
  var humHz = 60.0
  /// Harmonics of the hum cancelled in the voice (bit k−1: harmonic k): those inside the drives' keep-out band.
  var humMute = 0
  var grit = 0.0
  /// Background bubbles and grain clicks spawned this frame by the mapper itself (microphone live; their rates are then
  /// 0 and the voice draws none of its own), so the app knows when it plinks.
  var bubbleSpawns = 0
  var clickSpawns = 0
  /// v2: the squeeze's wet squish (0…1, follows the extrusion speed; the voice's creak clicks faster as it rises) and
  /// the nozzle's creak (0…1: the squish × the paste's `GloopTimbre.creak`).
  var squish = 0.0
  var creak = 0.0
}

/// One gloop event.
struct GloopTrigger: Sendable, Equatable {
  enum Kind: Sendable, Equatable { case squelch, crack, crumble, splash }
  var kind: Kind
  var strength: Double
}

struct FeelOutput: Sendable {
  /// A cause for the causal hum is live this frame.
  var cause = false
  var hum = HumWish.silent
  var haptics: [FeelHaptic] = []
  var gloop = GloopControls()
  var triggers: [GloopTrigger] = []
  /// For `LabFeedback.updateBed(activity:)`: the policy gate (1 while the simulation runs). The voice's own levels
  /// carry the dynamics and are silent when nothing moves.
  var bedGate = 0.0

  /// The app made a transient sound or haptic itself (a background bubble or grain click included): open the
  /// microphone's onset-ignore window.
  var selfSound: Bool { !haptics.isEmpty || !triggers.isEmpty || gloop.bubbleSpawns > 0 || gloop.clickSpawns > 0 }
}

// MARK: - The map

struct FeelMapper: Sendable {
  /// Squelch bursts at most 8 per second (§6.3 item 8).
  static let squelchGap = 0.125
  /// A punch and the jam onset it causes are one knock.
  static let crackGap = 0.15
  static let splashGap = 0.05
  static let propHitGap = 0.04
  /// Shake knob level from which the floor's buzz is felt and keeps the hum causal.
  static let vibrationFeel = 0.5  // g
  /// How far (m) the finger's disc must rise clear of the surface before it counts as out of the fluid.
  static let surfaceHysteresis = 0.002
  /// v2: the tear-off's tick (a crisp transient) and its rate limit (s).
  static let tearTick = (intensity: 0.6, sharpness: 0.8)
  static let tearGap = 0.08

  /// v2: the hum while squeezing: a soft, low-sharpness pressure that tracks the extrusion speed (0 → nothing;
  /// `SqueezeState.maxRate` → 0.5).
  static func squeezeHum(speed: Double) -> HumWish {
    let u = clamped(speed / (SqueezeState.maxRate * 1e-3), 0, 1)
    guard u > 0.005 else { return .silent }
    return HumWish(intensity: 0.14 + 0.36 * pow(u, 0.6), sharpness: 0.18 + 0.12 * u)
  }

  private(set) var stressFeel = StressFeel()
  private(set) var detector = FeelEventDetector()
  /// Background bubbles and grain clicks while the microphone is live (Poisson arrivals drawn here, not in the voice).
  private var textureRNG = XorShift32(seed: 0x6B1B_B1E5)
  private(set) var clock = 0.0
  private var lastSquelch = -Double.infinity
  private var lastCrack = -Double.infinity
  private var lastSplash = -Double.infinity
  private var lastPunch = -Double.infinity
  /// When the `.release` after a crack is due (clock seconds).
  private var releaseAt: Double?
  private var etaLog: Double?
  private var drag = 0.0
  private var hiss = 0.0
  private var refill = 0.0
  private var grains = 0.0
  private var lastSolid: Double?
  private var lastTankJam: Double?
  private var material: MaterialID?
  /// The floor hum's pitch, held while the floor is still so a fading hum does not glide.
  private var humHz = 60.0
  private var pouring = false
  private var inFluid = false
  private var lastSpeed = 0.0
  private var propsInFluid: [Int: Bool] = [:]
  /// v2: the squeeze's smoothed level and whether paste was leaving the nozzle last frame; the last tear-off tick.
  private var squish = 0.0
  private var emitting = false
  private var lastTear = -Double.infinity

  init() {}

  /// Forget the touch and the smoothing (the app went inactive). The clock keeps running.
  mutating func reset() {
    let t = clock
    self = FeelMapper()
    clock = t
  }

  /// Bed pitch for a viscosity: f = 880·2^(−3p), p = (log₁₀ η + 3)/8 on 1 mPa·s…100 kPa·s (§6.3 item 8).
  static func pitch(viscosity eta: Double) -> Double {
    let p = clamped((log10(max(eta, 1e-6)) + 3) / 8, 0, 1)
    return 880 * pow(2, -3 * p)
  }

  mutating func step(_ s: FeelSignals) -> FeelOutput {
    var out = FeelOutput()
    let dt = s.dt.isFinite ? min(max(s.dt, 0), 0.1) : 0
    clock += dt

    // Live viscosity, log-smoothed: the bed's pitch and the timbre follow it (heated honey brightens).
    let eta = s.meanViscosity.isFinite && s.meanViscosity > 0 ? s.meanViscosity : max(s.restingViscosity, 1e-4)
    // A new material is a new tank: its voice starts at its own pitch instead of gliding from the last one.
    if material != s.material { etaLog = nil }
    material = s.material
    var e = etaLog ?? log10(eta)
    approach(&e, log10(eta), dt: dt, tau: 0.3)
    etaLog = e
    let p = clamped((e + 3) / 8, 0, 1)
    let thick = clamped(0.7 * s.timbre.thick + 0.3 * p, 0, 1)
    let pitch = 880 * pow(2, -3 * p)
    out.gloop.pitch = pitch
    out.gloop.thick = thick
    out.gloop.grit = s.timbre.grit

    // Discrete events that answer a button even while frozen.
    for e in s.events {
      switch e {
      case .refilled: out.haptics.append(.ramp(duration: 0.55))
      case .propDropped: out.haptics.append(.tap(.place))
      default: break
      }
    }

    guard s.running else {
      // Frozen: no physical feel, and the bed is gated off (LabFeedback also silences it while paused).
      stressFeel.reset()
      detector.reset()
      inFluid = false
      drag = 0
      hiss = 0
      grains = 0
      lastSolid = nil
      lastTankJam = nil
      releaseAt = nil
      self.pouring = false
      squish = 0
      emitting = false
      out.bedGate = 0
      return out
    }
    out.bedGate = 1

    // Finger: in the fluid when its disc reaches below the resting surface, or the probe already reads stress. It
    // leaves only once its disc is `surfaceHysteresis` clear of the surface, so a finger skimming the surface does not
    // chatter (plunge, suction and pinch-off on every frame).
    let probe = (s.finger?.tool == .probe ? s.finger : nil) ?? s.lens
    let speed = probe.map { simd_length($0.velocity) } ?? 0
    var nowIn = false
    if let f = probe {
      let clearance = f.position.y - f.radius - s.surfaceHeight(at: f.position.x)
      nowIn = clearance < (inFluid ? Self.surfaceHysteresis : 0) || s.probeStress > 0.05
    }
    if nowIn, !inFluid {
      // Plunge: a splash in thin fluids, a squelch in thick ones.
      let st = min(1, max(speed, 0.05) / 0.8)
      if thick < 0.35 { trigger(.splash, 0.3 + 0.6 * st, &out) } else { trigger(.squelch, 0.3 + 0.5 * st, &out) }
    } else if !nowIn, inFluid, thick > 0.35 {
      // Pulled out of something thick: suction, and the strand that follows the finger pinches off.
      trigger(.squelch, min(1, 0.25 + 0.6 * thick * min(1, lastSpeed / 0.3 + 0.3)), &out)
      out.haptics.append(.tap(.pinch))
    }
    inFluid = nowIn
    lastSpeed = speed

    // Hum.
    var wish = HumWish.silent
    if nowIn {
      wish = stressFeel.step(stress: s.probeStress.isFinite ? s.probeStress : 0, solidFraction: s.probeSolid,
        fingerSpeed: speed, dt: dt)
      if detector.jammed { wish.sharpness = max(wish.sharpness, 0.95) }
    } else {
      stressFeel.reset()
      wish = StressFeel.slosh(kineticEnergy: s.kineticEnergy, reference: s.sloshReference)
    }
    let vibG = s.vibration.x.isFinite ? max(s.vibration.x, 0) / Gravity.g0 : 0
    if vibG >= Self.vibrationFeel {
      let rate = s.vibration.y.isFinite ? max(s.vibration.y, 20) : 20
      let buzz = HumWish(
        intensity: 0.12 + 0.18 * min(1, vibG / 15), sharpness: clamped(0.3 + 0.5 * log10(rate / 20), 0, 1))
      if buzz.intensity > wish.intensity { wish = buzz }
    }
    // The tube: a soft pressure while the paste leaves the nozzle (the squeeze is the cause).
    let squeezing = s.squeeze.emitting && s.squeeze.speed > 0
    if squeezing {
      let press = Self.squeezeHum(speed: s.squeeze.speed)
      if press.intensity > wish.intensity { wish = press }
    }
    out.hum = wish
    out.cause = FeelCauses().isLive(s.sources, listen: s.listen, fingerDown: nowIn) || vibG >= Self.vibrationFeel
      || squeezing

    // Simulation events (before the detector, so a punch and the jam it causes are one knock).
    for e in s.events {
      switch e {
      case .refilled:
        refill = 1
        trigger(.splash, 0.4, &out)
      case .poke:
        out.haptics.append(.tap(.poke))
        trigger(.splash, 0.5, &out)
      case .punch:
        if s.jams {
          out.haptics.append(.transient(intensity: 1, sharpness: 0.95, minGap: 0))
          trigger(.crack, 0.9, &out)
          lastPunch = clock
        } else {
          out.haptics.append(.tap(.poke))
          trigger(.splash, 0.9, &out)
        }
      case .pourStarted:
        hiss = max(hiss, 0.3)
      case .propHit(let v):
        let st = v.isFinite ? min(1, max(v, 0) / 0.8) : 0
        out.haptics.append(.transient(intensity: st, sharpness: 0.7, minGap: Self.propHitGap))
        trigger(.crack, min(0.6, st * 0.6), &out)
      case .propDropped, .materialChanged, .experimentApplied, .touchDown, .touchUp, .qualityChanged:
        break
      }
    }

    // The tube: the first push is a soft squelch; each tear-off a crisp tick and a squelch (once per event).
    if squeezing, !emitting { trigger(.squelch, 0.25 + 0.2 * thick, &out) }
    emitting = squeezing
    for e in s.pasteEvents where e.kind == .tearOff {
      guard clock - lastTear >= Self.tearGap else { continue }
      lastTear = clock
      out.haptics.append(.transient(intensity: Self.tearTick.intensity, sharpness: Self.tearTick.sharpness, minGap: 0))
      trigger(.squelch, 0.35 + 0.35 * thick, &out)
    }

    // Transients at the finger: yield, jam, unjam, grains (hysteresis in FeelEventDetector).
    if nowIn {
      let found = detector.step(
        stress: stressFeel.stress, yieldStress: s.yieldStress, jammedFraction: s.jams ? s.probeSolid : 0, dt: dt)
      for e in found {
        switch e {
        case .yield:
          out.haptics.append(.event(e))
          trigger(.squelch, 0.55, &out)
        case .jam(let fraction):
          if clock - lastPunch > 0.2 { out.haptics.append(.event(e)) }
          trigger(.crack, 0.55 + 0.45 * clamped(fraction, 0, 1), &out)
        case .unjam:
          // The jammed solid cracks, then gives (.release, 40 ms later).
          out.haptics.append(.transient(intensity: 0.6, sharpness: 1, minGap: 0.03))
          releaseAt = clock + 0.04
          trigger(.crumble, 0.6, &out)
          trigger(.squelch, 0.35, &out)
        case .grain:
          out.haptics.append(.event(e))
        }
      }
    } else {
      detector.reset()
    }

    if let t = releaseAt, clock >= t - 1e-9 {
      out.haptics.append(.event(.unjam))
      releaseAt = nil
    }

    // Props falling into the fluid.
    for prop in s.props {
      let inside = prop.position.y - 0.5 * prop.radius < s.surfaceHeight(at: prop.position.x)
      let was = propsInFluid[prop.id] ?? inside
      if inside, !was, prop.velocity.y < -0.1 {
        let st = min(1, -prop.velocity.y / 1.2)
        trigger(.splash, st, &out)
        out.haptics.append(.transient(intensity: 0.25 + 0.5 * st, sharpness: 0.25, minGap: Self.splashGap))
      }
      propsInFluid[prop.id] = inside
    }
    // Every current prop is in the table now, so a larger table holds props that have gone (no per-frame set).
    if propsInFluid.count > s.props.count {
      let current = s.props
      propsInFluid = propsInFluid.filter { entry in current.contains { $0.id == entry.key } }
    }

    // A clap or a shout with Listen up: a ripple (§5.3 "oobleck monster" burst), and a splash when it kicks the
    // fluid (Drives on Kicks). The analyser's onsets already skip Toothpaste Toy's own sounds (the 0.2 s self-trigger window).
    if s.listen > 0.005, s.sources[.micOnset] >= 1.5 {
      out.haptics.append(.tap(.ripple))
      if s.drives == .kicks { trigger(.splash, 0.35, &out) }
    }

    // Continuous layers.
    let activity = s.sloshReference > 0 && s.kineticEnergy.isFinite
      ? min(1, max(s.kineticEnergy, 0) / s.sloshReference).squareRoot() : 0
    let act = max(0, activity - 0.04) / 0.96
    let intensity = StressFeel.intensity(stress: stressFeel.stress)
    let dragTarget = nowIn ? min(1, pow(speed / 0.25, 0.8)) * (0.35 + 0.65 * intensity) : 0
    approach(&drag, dragTarget, dt: dt, tau: dragTarget > drag ? 0.02 : 0.15)
    let pouring = s.finger?.tool == .pour
    if self.pouring, !pouring {
      // The stream ends: its last drop pinches off and lands (a plink in a thin fluid; a thick one takes it quietly).
      out.haptics.append(.tap(.pinch))
      if thick < 0.35 { trigger(.splash, 0.25, &out) }
    }
    self.pouring = pouring
    approach(&hiss, pouring ? 0.7 : 0, dt: dt, tau: pouring ? 0.05 : 0.06)
    approach(&refill, 0, dt: dt, tau: 0.45)

    var grainTarget = s.timbre.grit * (30 * drag + 10 * act)
    if s.jams {
      if nowIn, let last = lastSolid, dt > 0 { grainTarget += min(40, 200 * abs(s.probeSolid - last) / dt) }
      if let last = lastTankJam, dt > 0 { grainTarget += min(40, 400 * abs(s.tankJammed - last) / dt) }
    }
    lastSolid = nowIn ? s.probeSolid : nil
    lastTankJam = s.tankJammed

    // MR fluid in a field: Gyre's crackle while something moves it (a finger, a shake, the magnet itself).
    if s.material == "mrFluid", s.fieldTesla > 1e-4,
      nowIn || vibG >= Self.vibrationFeel || s.sources[.shake] > 0.15 || s.sources[.fieldStep] > 5
    {
      let depth = min(1, s.fieldTesla / 0.207)
      out.haptics.append(.crackle(fieldMicroTesla: s.fieldTesla * 1e6, depth: depth))
      grainTarget += 30 * depth
    }
    approach(&grains, min(grainTarget, 120), dt: dt, tau: grainTarget > grains ? 0.01 : 0.06)
    // Exponential tails end: below these the layers are silent, so a tank at rest is exactly quiet.
    if grainTarget == 0, grains < 0.5 { grains = 0 }
    if dragTarget == 0, drag < 0.002 { drag = 0 }
    if !pouring, hiss < 0.005 { hiss = 0 }
    if refill < 0.005 { refill = 0 }

    let thin = (1 - thick) * (1 - thick)
    let bubbles = thin * (45 * act + 50 * drag) + 18 * hiss * (1 - thick) + 30 * refill + thick * (2.5 * act + 6 * drag)

    var hum = vibG > 0.05 ? min(1, (vibG / 12).squareRoot()) : 0
    if hum > 0, s.vibration.y.isFinite, s.vibration.y > 0 { humHz = clamped(s.vibration.y, 15, 400) }
    var drone = act
    var mute = 0
    if s.micLive {
      // Keep our own sound out of the pitches the microphone drives listen to: the hum's harmonics inside the band
      // are cancelled (its other harmonics still play), the body tone near Band is ducked.
      let keepOut = ToothpasteMicBand.keepOut(s.band)
      if let m = Self.humMute(humHz: humHz, keepOut: keepOut) { mute = m } else { hum = 0 }
      if keepOut.contains(pitch) { drone *= 0.3 }
    }
    out.gloop.drone = drone
    out.gloop.drag = drag
    out.gloop.hiss = max(hiss, 0.6 * refill)
    var grainRate = grains
    var bubbleRate = bubbles < 0.05 ? 0 : min(bubbles, 150)
    if s.micLive {
      // The voice's own Poisson texture is invisible to the main actor, so a plink could reach the microphone as an
      // onset and kick the fluid (Drives on Kicks), which plinks again. Drawn here instead (at the bed's level), each
      // one opens the onset window (`selfSound`).
      let scale = s.bedScale.isFinite ? clamped(s.bedScale, 0, 1) : 0
      out.gloop.bubbleSpawns = Self.poisson(bubbleRate * scale * max(s.dt, 0), &textureRNG)
      out.gloop.clickSpawns = Self.poisson(grainRate * scale * max(s.dt, 0), &textureRNG)
      grainRate = 0
      bubbleRate = 0
    }
    // The squeeze: squish and creak follow the extrusion speed (fast attack, a short tail when it stops).
    let u = squeezing ? clamped(s.squeeze.speed / (SqueezeState.maxRate * 1e-3), 0, 1) : 0
    let squishTarget = u > 0 ? 0.25 + 0.75 * pow(u, 0.7) : 0
    approach(&squish, squishTarget, dt: dt, tau: squishTarget > squish ? 0.03 : 0.08)
    if squishTarget == 0, squish < 0.005 { squish = 0 }
    out.gloop.squish = squish
    out.gloop.creak = squish * GloopTimbre.creak(s.squeeze.material ?? s.material)
    out.gloop.grains = grainRate
    out.gloop.bubbles = bubbleRate
    out.gloop.hum = hum
    out.gloop.humHz = humHz
    out.gloop.humMute = mute
    return out
  }

  /// The hum's harmonics inside `keepOut` as a mask (bit k−1: harmonic k, up to the 8th), or nil when nothing the
  /// hum's filter passes (harmonics up to max(5f, 520 Hz)) lies outside it, or a harmonic past the 8th is inside it
  /// (only a floor slower than about 25 Hz): then the whole hum is muted.
  static func humMute(humHz f: Double, keepOut: ClosedRange<Double>) -> Int? {
    guard f.isFinite, f > 0 else { return nil }
    let cutoff = max(5 * f, 520)
    var mask = 0
    var audible = false
    var k = 1
    while Double(k) * f <= cutoff {
      if keepOut.contains(Double(k) * f) {
        guard k <= 8 else { return nil }
        mask |= 1 << (k - 1)
      } else {
        audible = true
      }
      k += 1
    }
    return audible ? mask : nil
  }

  /// A Poisson count with mean `mean` (inversion; `mean` is at most about 10 here).
  static func poisson(_ mean: Double, _ rng: inout XorShift32) -> Int {
    guard mean.isFinite, mean > 0 else { return 0 }
    let limit = exp(-min(mean, 30))
    var p = Double(rng.unit())
    var n = 0
    while p > limit, n < 64 {
      p *= Double(rng.unit())
      n += 1
    }
    return n
  }

  /// Appends a trigger unless its kind fired too recently.
  private mutating func trigger(_ kind: GloopTrigger.Kind, _ strength: Double, _ out: inout FeelOutput) {
    switch kind {
    case .squelch:
      guard clock - lastSquelch >= Self.squelchGap else { return }
      lastSquelch = clock
    case .crack, .crumble:
      guard clock - lastCrack >= Self.crackGap else { return }
      lastCrack = clock
    case .splash:
      guard clock - lastSplash >= Self.splashGap else { return }
      lastSplash = clock
    }
    out.triggers.append(GloopTrigger(kind: kind, strength: clamped(strength, 0, 1)))
  }
}

// MARK: - The voice's two gains

/// How loud the gloop voice plays (`labkit-from-orbitals-spectra.md` §6.3 rules 3–4, applied per layer). LabKit's
/// `LabFeedback.updateBed` scales the whole voice: with the microphone live it ducked squelches, cracks and splashes to
/// × 0.3 too, and Low Power Mode silenced them, although they answer what the user does, like cues (which stay). So
/// Toothpaste Toy sets the host gain itself and scales only the continuous layers:
/// - `hostGain` (`SynthHost.bedGain`): 1 while Sound is on and the app active, else 0;
/// - `bedScale` (`FeelSignals.bedScale`): the continuous layers follow the simulation's run state with the policy's
///   0.25 s lag, × 0.3 with the microphone live, 0 in Low Power Mode or while frozen.
struct ToothpasteBedMix: Sendable, Equatable {
  private(set) var hostGain = 0.0
  private(set) var bedScale = 0.0

  mutating func step(
    running: Bool, sound: Bool, active: Bool, paused: Bool, lowPower: Bool, micLive: Bool, dt: Double
  ) {
    let allowed = sound && active
    hostGain = allowed ? 1 : 0
    guard allowed, !paused, !lowPower else {
      bedScale = 0
      return
    }
    let target = running ? (micLive ? SoundPolicy.micDuck : 1) : 0
    approach(&bedScale, target, dt: max(dt.isFinite ? dt : 0, 0), tau: SoundPolicy.lag)
  }
}

// MARK: - Controls → the voice

/// Writes a `FeelOutput` to the voice's control slots. Event slots are monotone counters: the strength is written
/// first, then the counter is bumped (one increment per event).
struct GloopDriver: Sendable {
  private(set) var squelches = 0.0
  private(set) var cracks = 0.0
  private(set) var splashes = 0.0
  private(set) var bubbleSpawns = 0
  private(set) var clickSpawns = 0

  /// `triggers` false while the voice is not rendering (Sound off, inactive): events are dropped instead of piling
  /// up for the next start. `bedScale` (`ToothpasteBedMix`) scales the continuous layers only: levels and texture rates.
  mutating func write(_ out: FeelOutput, to c: SynthControls, triggers: Bool = true, bedScale: Double = 1) {
    typealias S = GloopKernel.Slot
    let g = out.gloop
    let k = bedScale.isFinite ? clamped(bedScale, 0, 1) : 0
    c.set(S.pitch, g.pitch)
    c.set(S.drone, g.drone * k)
    c.set(S.thick, S.packTimbre(thick: g.thick, grit: g.grit))
    c.set(S.grains, g.grains * k)
    c.set(S.drag, g.drag * k)
    c.set(S.bubbles, g.bubbles * k)
    c.set(S.hiss, S.packFlow(hiss: g.hiss * k, squish: g.squish * k, creak: g.creak * k))
    c.set(S.hum, g.hum * k)
    c.set(S.humHz, S.packHum(hz: g.humHz, mute: g.humMute))
    guard triggers else { return }
    if g.bubbleSpawns > 0 || g.clickSpawns > 0 {
      bubbleSpawns = (bubbleSpawns + min(g.bubbleSpawns, 8)) & 0xFFFF
      clickSpawns = (clickSpawns + min(g.clickSpawns, 8)) & 0xFFFF
    }
    c.set(S.texture, S.packTexture(bubbles: bubbleSpawns, clicks: clickSpawns))
    for t in out.triggers {
      switch t.kind {
      case .squelch:
        c.set(S.squelchStrength, t.strength)
        squelches += 1
        c.set(S.squelch, squelches)
      case .crack, .crumble:
        c.set(S.crackStrength, t.kind == .crumble ? -t.strength : t.strength)
        cracks += 1
        c.set(S.crack, cracks)
      case .splash:
        c.set(S.splashStrength, t.strength)
        splashes += 1
        c.set(S.splash, splashes)
      }
    }
  }
}

// MARK: - Frame → signals

extension FeelSignals {
  /// Reads one `ToothpasteFrame` (main actor: the catalog is main-actor isolated).
  @MainActor static func make(
    frame f: ToothpasteFrame, dt: Double, catalog: any ToothpasteCatalog, gap: Double, micLive: Bool
  ) -> FeelSignals {
    let info = catalog.material(f.material)
    var s = FeelSignals()
    s.dt = dt
    s.running = f.simDt > 0
    s.material = f.material
    s.timbre = .of(f.material)
    s.jams = info.material.dst != nil
    let ty = f.params[.yield]
    s.yieldStress = ty.isFinite && ty > 0.1 ? ty : nil
    s.restingViscosity = ToothpasteKnobs.consistency(info.material)
    if let finger = f.finger {
      s.finger = Finger(position: finger.position, velocity: finger.velocity, radius: finger.radius, tool: finger.tool)
    }
    if let l = f.lens, l.active {
      s.lens = Finger(position: l.centre, velocity: l.velocity, radius: l.radius, tool: .probe)
    }
    if let n = f.nozzle {
      s.squeeze = Squeeze(emitting: n.emitting, speed: n.speed.isFinite ? max(n.speed, 0) : 0, material: n.material)
    }
    s.pasteEvents = f.pasteEvents
    s.probeStress = f.probe.stress.isFinite ? max(f.probe.stress, 0) : 0
    s.probeSolid = f.probe.solidFraction.isFinite ? clamped(f.probe.solidFraction, 0, 1) : 0
    s.meanViscosity = f.stats.meanViscosity
    s.kineticEnergy = f.stats.kineticEnergy
    let area = f.tank.x * f.tank.y * info.fillFraction
    s.sloshReference = StressFeel.sloshReference(density: info.material.density, fillArea: area) * max(gap, 1e-4)
    s.tankJammed = f.stats.jammedFraction.isFinite ? f.stats.jammedFraction : 0
    s.vibration = f.vibration
    s.fieldTesla = f.magnet?.fieldTesla ?? 0
    // The resting surface: the fluid's area (its mass over ρ·gap, times the mean J, so a pour raises it) spread across
    // the tank, falling back to the fill line before the first stats arrive; it lies across the gravity the fluid feels.
    s.surfaceCentreX = 0.5 * f.tank.x
    var level = info.fillFraction * f.tank.y
    let rho = info.material.density
    let mass = f.stats.particleMass
    if mass.isFinite, mass > 0, rho > 0, gap > 0, f.tank.x > 0 {
      let j = f.stats.volumeRatio.isFinite && f.stats.volumeRatio > 0 ? f.stats.volumeRatio : 1
      level = mass * j / (rho * gap * f.tank.x)
    }
    s.surface = clamped(level, 0, f.tank.y)
    let g = f.input.gravity
    if g.y.isFinite, g.x.isFinite, g.y < -0.5 { s.surfaceSlope = clamped(-g.x / g.y, -1.5, 1.5) }
    s.props = f.props.map { Prop(id: $0.id, position: $0.position, velocity: $0.velocity, radius: boundingRadius($0.shape)) }
    s.events = f.events
    s.sources = f.sources
    s.listen = f.params[.listen]
    let d = f.params[.drives]
    s.drives = d.isFinite ? DriveTarget(rawValue: Int(min(max(d, 0), 4).rounded())) ?? .shake : .shake
    s.micLive = micLive
    s.band = f.params[.band].isFinite ? max(f.params[.band], 1) : 80
    return s
  }

  /// The radius of the smallest circle about the body origin that holds the shape, m.
  static func boundingRadius(_ shape: RigidShape) -> Double {
    switch shape {
    case .circle(let r): r
    case .box(let hw, let hh): (hw * hw + hh * hh).squareRoot()
    case .capsule(let hl, let r): hl + r
    case .polygon(let points): points.map { simd_length($0) }.max() ?? 0
    }
  }
}
