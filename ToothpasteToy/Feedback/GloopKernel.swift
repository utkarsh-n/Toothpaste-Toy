// GloopKernel.swift — OWNER: PLAY (was FEEL; Documentation/REDESIGN-OWNERSHIP.md).
//
// Toothpaste Toy's sound voice: the fluid "gloops" (labkit-from-orbitals-spectra.md §6.3 item 8, extended for the FEEL area).
// Every layer is synthesised, none is sampled, and the sound is illustrative: it follows the simulation's numbers
// (viscosity, finger stress and speed, jamming, pouring, the vibrating floor) but is not a model of how fluids sound.
//
// Layers (all mixed to one stereo pair, soft-clipped to ±1):
//   • body     a PolyBLEP sawtooth at f = 880·2^(−3p) Hz (p = where the tank's mean viscosity sits on 1 mPa·s…100 kPa·s)
//              through a resonant 2-pole low-pass at 4 f, level ∝ the tank's kinetic activity: thick fluids hum low;
//   • drag     band-passed noise with a wandering centre and a squish flutter while a finger moves through the fluid
//              (low and narrow for honey and toothpaste, bright and broad for water);
//   • bubbles  pitch-gliding sinusoids with exponential decay, after van den Doel's bubble model (2005): small, high and
//              short "plinks" for thin fluids, big low "glorps" for thick ones; voices below 420 Hz carry their 2nd and
//              3rd harmonics so the phone's speaker (little output below about 300 Hz) can still play them;
//   • squelch  resonant band-passed noise bursts whose centre sweeps upward (the "squ-elch" formant);
//   • crack    a cluster of dry clicks plus a low knock when jammed oobleck holds, or a softer crumble when it fails;
//   • grains   Poisson clicks for granular jamming texture, MR crackle and lava crust;
//   • splash   a noise burst plus a spray of small bubbles (thin fluids) or one glorp and a squelch (thick ones);
//   • hiss     soft trickling noise while pouring;
//   • squish   (v2, the tube) band-passed noise with a slow wet "glug" while paste is squeezed from the nozzle, its
//              level following the extrusion speed;
//   • creak    (v2) the paste slipping along the nozzle wall: a jittered click train (18 Hz at a slow squeeze … 70 Hz at
//              the fastest) ringing two small resonances, for stiff pastes (toothpaste creaks, honey hardly);
//   • hum      a band-limited sawtooth at the vibrating floor's frequency (harmonics up to about 5 f, at least 520 Hz);
//              with the microphone live, the harmonics inside the drives' keep-out band are cancelled one by one (the
//              rest still play), so the floor's buzz stays audible without feeding the shake drive.
//
// Real-time rules: `render` runs on the audio thread. It allocates nothing, takes no locks and calls no Objective-C:
// every voice pool is allocated once in `init`, all state lives behind one pointer (no exclusivity checks per sample),
// controls arrive through `SynthControls`' relaxed atomics, recursive filter states are flushed to zero below 1e-18
// (no denormals) and any non-finite state resets the voice. The kernel class is `nonisolated`, so nothing in it is
// main-actor isolated even if the module's default isolation changes (the Swift 6 audio-thread trap).
//
// Controls (`Slot`): continuous values are smoothed here (τ 30 ms; a pitch jumps while its voice is silent); the three
// event slots are monotone counters (each increment is one event) with a strength slot written just before the
// counter. LabKit's `SynthControls` has 16 slots, all in use, so three carry two values each (`Slot.packTimbre`,
// `packHum`, `packTexture`): timbre and grit; the hum's pitch and its muted harmonics; and the counters of background
// bubbles and grain clicks that the main actor spawns itself while the microphone is live (so it knows when Toothpaste Toy
// plinks and can keep those onsets away from the kicks drive).

import Foundation
import LabKitCore
import LabKitFeedback
import Synchronization

/// The audio-thread voice (`SynthKernel`). Created by the hub as `GloopKernel()`; driven by `ToothpasteFeel`.
nonisolated final class GloopKernel: SynthKernel, @unchecked Sendable {
  /// Control slots (written on the main actor by `GloopDriver`).
  enum Slot {
    /// Body pitch, Hz (40…2000).
    static let pitch = 0
    /// Body level 0…1 (the tank's activity).
    static let drone = 1
    /// Timbre 0 (water: bright, short) … 1 (paste: low, long), packed with grit (`packTimbre`).
    static let thick = 2
    /// Counter: each increment is one squelch burst at `squelchStrength`.
    static let squelch = 3
    /// Grain clicks per second (0…200).
    static let grains = 4
    /// Viscous drag noise 0…1 (finger moving through the fluid).
    static let drag = 5
    /// Background bubbles per second (0…200).
    static let bubbles = 6
    /// Counter: each increment is one crack at `crackStrength` (> 0: a jam's knock; < 0: a crumble).
    static let crack = 7
    /// Pouring hiss 0…1, packed with the squeeze's squish and creak (`packFlow`; a plain 0…1 value is hiss alone).
    static let hiss = 8
    /// Vibrating-floor hum 0…1 at `humHz`.
    static let hum = 9
    /// The hum's pitch, Hz (15…400), packed with the harmonics to cancel (`packHum`).
    static let humHz = 10
    /// Counter: each increment is one splash at `splashStrength`.
    static let splash = 11
    static let splashStrength = 12
    /// Two monotone counters (`packTexture`): background bubbles and grain clicks spawned by the main actor (with the
    /// microphone live; otherwise the voice draws them itself from the `bubbles` and `grains` rates).
    static let texture = 13
    static let crackStrength = 14
    static let squelchStrength = 15

    /// Timbre and grit (each 0…1) in one slot: ⌊4095·thick⌉·4096 + ⌊4095·grit⌉ (exact in a Double).
    static func packTimbre(thick: Double, grit: Double) -> Double {
      func q(_ v: Double) -> Double { (min(max(v.isFinite ? v : 0, 0), 1) * 4095).rounded() }
      return q(thick) * 4096 + q(grit)
    }

    /// The hum's pitch (Hz) and a mask of harmonics to cancel (bit k−1: harmonic k, k ≤ 8): pitch + 1000·mask.
    static func packHum(hz: Double, mute: Int) -> Double {
      min(max(hz.isFinite ? hz : 60, 15), 400) + 1000 * Double(min(max(mute, 0), 255))
    }

    /// Hiss, squish and creak (each 0…1, 255 steps) in one slot: hiss/255-quantised in [0, 1] + 2·(⌊255·squish⌉ +
    /// 256·⌊255·creak⌉) (exact in a Double; a plain 0…1 value decodes as hiss alone).
    static func packFlow(hiss: Double, squish: Double, creak: Double) -> Double {
      func q(_ v: Double) -> Double { (min(max(v.isFinite ? v : 0, 0), 1) * 255).rounded() }
      return q(hiss) / 255 + 2 * (q(squish) + 256 * q(creak))
    }

    /// The background-bubble and grain-click counters (each kept modulo 65 536): bubbles + 65 536·clicks.
    static func packTexture(bubbles: Int, clicks: Int) -> Double {
      Double(bubbles & 0xFFFF) + 65_536 * Double(clicks & 0xFFFF)
    }
  }

  private let core: UnsafeMutablePointer<GloopEngine>
  /// Render calls so far (a relaxed atomic: tests check the voice really runs on the audio thread).
  private let renders = Atomic<Int>(0)

  init() {
    core = .allocate(capacity: 1)
    core.initialize(to: GloopEngine())
  }

  deinit {
    core.pointee.releasePools()
    core.deinitialize(count: 1)
    core.deallocate()
  }

  func prepare(sampleRate: Double) { core.pointee.prepare(sampleRate: sampleRate) }

  func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, controls c: SynthControls) {
    _ = renders.wrappingAdd(1, ordering: .relaxed)
    core.pointee.render(frames: frames, left: left, right: right, controls: c)
  }

  /// How many times the host has called `render`.
  var renderCount: Int { renders.load(ordering: .relaxed) }

  /// Voices currently sounding (tests and diagnostics; not for the audio thread's callers).
  var activeVoices: Int { core.pointee.activeVoices }

  /// The smoothed body and floor-hum pitches, Hz (tests; read only while nothing renders).
  var pitches: (body: Double, hum: Double) { (core.pointee.pitch, core.pointee.humHz) }
}

// MARK: - DSP building blocks

/// A TPT state-variable filter (Zavalishin; Simper's trapezoidal form): stable when retuned every block.
nonisolated struct GloopSVF {
  var ic1 = 0.0, ic2 = 0.0
  var a1 = 1.0, a2 = 0.0, a3 = 0.0, k = 1.0

  mutating func tune(_ cutoff: Double, q: Double, sampleRate fs: Double) {
    let f = min(max(cutoff.isFinite ? cutoff : 1000, 10), 0.45 * fs)
    let g = tan(Double.pi * f / fs)
    k = 1 / max(q, 0.05)
    a1 = 1 / (1 + g * (g + k))
    a2 = g * a1
    a3 = g * a2
  }

  /// Low-pass, unity-peak band-pass and high-pass outputs for one input sample.
  @inline(__always) mutating func run(_ v0: Double) -> (low: Double, band: Double, high: Double) {
    let v3 = v0 - ic2
    let v1 = a1 * ic1 + a2 * v3
    let v2 = ic2 + a2 * ic1 + a3 * v3
    ic1 = 2 * v1 - ic1
    ic2 = 2 * v2 - ic2
    return (v2, k * v1, v0 - k * v1 - v2)
  }

  /// Flushes tiny states to zero (no denormals) and clears non-finite ones.
  @inline(__always) mutating func flush() {
    if !(abs(ic1) > 1e-18) || !ic1.isFinite { ic1 = 0 }
    if !(abs(ic2) > 1e-18) || !ic2.isFinite { ic2 = 0 }
  }
}

/// PolyBLEP correction for a sawtooth at phase t (0…1) with phase increment dt.
@inline(__always) nonisolated func gloopPolyBLEP(_ t: Double, _ dt: Double) -> Double {
  if t < dt {
    let x = t / dt
    return x + x - x * x - 1
  }
  if t > 1 - dt {
    let x = (t - 1) / dt
    return x * x + x + x + 1
  }
  return 0
}

/// exp(lerp(log a, log b, t)).
@inline(__always) nonisolated func gloopLogLerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
  a * pow(b / a, min(max(t, 0), 1))
}

/// Unity below 0.6, then a tanh knee to ±1.
@inline(__always) nonisolated func gloopSoftClip(_ x: Double) -> Double {
  let a = abs(x)
  guard a > 0.6 else { return x }
  let y = 0.6 + 0.4 * tanh((a - 0.6) / 0.4)
  return x < 0 ? -y : y
}

// MARK: - Voices

nonisolated struct GloopBubble {
  var active = false
  /// Unit phasor (cos, sin) rotated each sample.
  var c = 1.0, s = 0.0
  /// Cycles per sample, and its growth per chunk (the upward glide).
  var inc = 0.0, incGrowth = 1.0
  var amp = 0.0, decay = 1.0
  var attack = 0.0, rise = 1.0
  var h2 = 0.0, h3 = 0.0
  var gl = 1.0, gr = 1.0
}

nonisolated struct GloopSquelch {
  var active = false
  var filter = GloopSVF()
  var centre = 500.0, centreGrowth = 1.0, q = 3.0
  var age = 0, attackSamples = 1
  var env = 0.0, decay = 1.0, amp = 0.0
  var flutterPhase = 0.0, flutterInc = 0.0, flutterDepth = 0.0
  var gl = 1.0, gr = 1.0
}

nonisolated struct GloopCrack {
  var active = false
  var impulsesLeft = 0
  var countdown = 0
  var meanGap = 240.0
  var env = 0.0, envDecay = 1.0, impulseAmp = 0.0, ampDecay = 0.8
  var highPass = GloopSVF(), body = GloopSVF()
  var knockC = 1.0, knockS = 0.0, knockCr = 1.0, knockSr = 0.0, knockAmp = 0.0, knockDecay = 1.0
  var gl = 1.0, gr = 1.0
}

// MARK: - The engine (all audio-thread state behind one pointer)

nonisolated struct GloopEngine {
  static let chunk = 32
  static let bubbleCount = 24
  static let squelchCount = 4
  static let crackCount = 3

  // Mix levels (calibrated with FeelTests' offline session: events peak near −6 dBFS, beds sit at −30…−20 dBFS).
  static let droneGain = 0.10
  static let dragGain = 0.16
  static let hissGain = 0.07
  static let humGain = 0.13
  static let splashGain = 0.22
  static let squelchGain = 0.30
  static let crackGain = 0.75
  static let knockGain = 0.42
  static let clickGain = 0.22
  static let bubbleGain = 0.30
  static let squishGain = 0.13
  static let creakGain = 0.5

  var fs = 48_000.0
  var rng = XorShift32(seed: 0x6100_D1E5)

  // Smoothed continuous controls.
  var pitch = 220.0, drone = 0.0, thick = 0.5, grainRate = 0.0, drag = 0.0, bubbleRate = 0.0
  var hiss = 0.0, hum = 0.0, humHz = 60.0, grit = 0.0
  /// v2: the squeeze's squish and creak levels (smoothed).
  var squish = 0.0, creak = 0.0
  /// Harmonics of the hum to cancel (bit k−1: harmonic k), not smoothed.
  var humMute = 0
  var smooth = 0.1

  // Event counters last seen.
  var lastSquelch = 0.0, lastCrack = 0.0, lastSplash = 0.0
  var lastTextureBubbles = -1, lastTextureClicks = -1
  /// Grain clicks spawned by the main actor, waiting for the click voice (one per chunk).
  var pendingClicks = 0

  // Continuous voices.
  var dronePhase = 0.0, droneFilter = GloopSVF(), droneLFO = 0.0
  var dragFilter = GloopSVF(), dragWander = 0.0, dragSquish = 0.0
  var hissFilter = GloopSVF(), hissTrickle = 0.0
  var squishFilter = GloopSVF(), squishGlug = 0.0, squishWander = 0.0
  var creakLow = GloopSVF(), creakHigh = GloopSVF(), creakCountdown = 0, creakEnv = 0.0, creakDecay = 0.9
  var humPhase = 0.0, humFilter = GloopSVF()
  var splashEnv = 0.0, splashDecay = 0.999, splashFilter = GloopSVF()
  var pendingBubbles = 0, pendingStrength = 0.0
  var clickEnv = 0.0, clickDecay = 0.95, clickDelay = -1, clickAmp = 0.0, clickFilter = GloopSVF()
  var dcInL = 0.0, dcOutL = 0.0, dcInR = 0.0, dcOutR = 0.0

  // Pools, allocated once.
  let bubbles: UnsafeMutablePointer<GloopBubble>
  let squelches: UnsafeMutablePointer<GloopSquelch>
  let cracks: UnsafeMutablePointer<GloopCrack>
  let mixL: UnsafeMutablePointer<Double>
  let mixR: UnsafeMutablePointer<Double>

  init() {
    bubbles = .allocate(capacity: Self.bubbleCount)
    bubbles.initialize(repeating: GloopBubble(), count: Self.bubbleCount)
    squelches = .allocate(capacity: Self.squelchCount)
    squelches.initialize(repeating: GloopSquelch(), count: Self.squelchCount)
    cracks = .allocate(capacity: Self.crackCount)
    cracks.initialize(repeating: GloopCrack(), count: Self.crackCount)
    mixL = .allocate(capacity: Self.chunk)
    mixL.initialize(repeating: 0, count: Self.chunk)
    mixR = .allocate(capacity: Self.chunk)
    mixR.initialize(repeating: 0, count: Self.chunk)
    prepare(sampleRate: 48_000)
  }

  func releasePools() {
    bubbles.deinitialize(count: Self.bubbleCount)
    bubbles.deallocate()
    squelches.deinitialize(count: Self.squelchCount)
    squelches.deallocate()
    cracks.deinitialize(count: Self.crackCount)
    cracks.deallocate()
    mixL.deallocate()
    mixR.deallocate()
  }

  mutating func prepare(sampleRate: Double) {
    fs = sampleRate.isFinite && sampleRate > 8000 ? sampleRate : 48_000
    let n = Double(Self.chunk)
    smooth = 1 - exp(-n / (0.03 * fs))
    clickDecay = exp(-1 / (0.0004 * fs))
    creakDecay = exp(-1 / (0.0007 * fs))
  }

  var activeVoices: Int {
    var n = 0
    for i in 0..<Self.bubbleCount where bubbles[i].active { n += 1 }
    for i in 0..<Self.squelchCount where squelches[i].active { n += 1 }
    for i in 0..<Self.crackCount where cracks[i].active { n += 1 }
    return n
  }

  // MARK: Render

  mutating func render(
    frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, controls c: SynthControls
  ) {
    var offset = 0
    while offset < frames {
      let n = min(Self.chunk, frames - offset)
      readControls(c, chunk: n)
      for i in 0..<n {
        mixL[i] = 0
        mixR[i] = 0
      }
      renderBeds(n)
      renderBubbles(n)
      renderSquelches(n)
      renderCracks(n)
      for i in 0..<n {
        // DC blocker (about 11 Hz), then the soft clip.
        let l = mixL[i], r = mixR[i]
        dcOutL = l - dcInL + 0.9985 * dcOutL
        dcInL = l
        dcOutR = r - dcInR + 0.9985 * dcOutR
        dcInR = r
        left[offset + i] = Float(gloopSoftClip(dcOutL))
        right[offset + i] = Float(gloopSoftClip(dcOutR))
      }
      flushStates()
      offset += n
    }
  }

  // MARK: Controls and triggers

  @inline(__always) private func value(_ c: SynthControls, _ slot: Int, _ lo: Double, _ hi: Double) -> Double {
    let v = c[slot]
    return v.isFinite ? min(max(v, lo), hi) : lo
  }

  /// How many events a counter slot holds since last read (0 when unchanged, reset or resynchronised; at most 4).
  @inline(__always) private func newEvents(_ c: SynthControls, _ slot: Int, last: inout Double) -> Int {
    let v = c[slot]
    guard v.isFinite, v != last else { return 0 }
    let delta = v - last
    last = v
    // A reset or a jump of more than 8 (events dropped while the voice was stopped) only resynchronises.
    guard delta > 0, delta <= 8 else { return 0 }
    return delta >= 4 ? 4 : max(1, Int(delta))
  }

  private mutating func readControls(_ c: SynthControls, chunk n: Int) {
    // Pitches glide only while their voice sounds: from silence they start where they are told (no swoops).
    let pitchTarget = value(c, GloopKernel.Slot.pitch, 40, 2000)
    pitch += (pitchTarget - pitch) * (drone < 1e-3 ? 1 : smooth)
    let (humTarget, mute) = Self.unpackHum(c[GloopKernel.Slot.humHz])
    humHz += (humTarget - humHz) * (hum < 1e-3 ? 1 : smooth)
    humMute = mute
    let (thickTarget, gritTarget) = Self.unpackTimbre(c[GloopKernel.Slot.thick])
    drone += (value(c, GloopKernel.Slot.drone, 0, 1) - drone) * smooth
    thick += (thickTarget - thick) * smooth
    grainRate += (value(c, GloopKernel.Slot.grains, 0, 200) - grainRate) * smooth
    drag += (value(c, GloopKernel.Slot.drag, 0, 1) - drag) * smooth
    bubbleRate += (value(c, GloopKernel.Slot.bubbles, 0, 200) - bubbleRate) * smooth
    grit += (gritTarget - grit) * smooth
    let (hissTarget, squishTarget, creakTarget) = Self.unpackFlow(c[GloopKernel.Slot.hiss])
    hiss += (hissTarget - hiss) * smooth
    squish += (squishTarget - squish) * smooth
    creak += (creakTarget - creak) * smooth
    hum += (value(c, GloopKernel.Slot.hum, 0, 1) - hum) * smooth

    // Background bubbles and grain clicks the main actor spawned (microphone live).
    let (bubbleSpawns, clickSpawns) = newTexture(c[GloopKernel.Slot.texture])
    for _ in 0..<bubbleSpawns { spawnBubble(strength: 0.45 + 0.55 * min(1, drag + hiss + drone), big: false) }
    pendingClicks = min(pendingClicks + clickSpawns, 8)

    let squelchN = newEvents(c, GloopKernel.Slot.squelch, last: &lastSquelch)
    if squelchN > 0 {
      let s = value(c, GloopKernel.Slot.squelchStrength, 0, 1)
      for _ in 0..<squelchN { spawnSquelch(s) }
    }
    let crackN = newEvents(c, GloopKernel.Slot.crack, last: &lastCrack)
    if crackN > 0 {
      let s = value(c, GloopKernel.Slot.crackStrength, -1, 1)
      for _ in 0..<crackN { spawnCrack(abs(s), crumble: s < 0) }
    }
    let splashN = newEvents(c, GloopKernel.Slot.splash, last: &lastSplash)
    if splashN > 0 {
      let s = value(c, GloopKernel.Slot.splashStrength, 0, 1)
      for _ in 0..<splashN { splash(s) }
    }

    // Poisson arrivals this chunk: background bubbles, the splash spray, grain clicks.
    let dt = Double(n) / fs
    if bubbleRate > 0.01, Double(rng.unit()) < bubbleRate * dt {
      spawnBubble(strength: 0.45 + 0.55 * min(1, drag + hiss + drone), big: false)
    }
    if pendingBubbles > 0, Double(rng.unit()) < 150 * dt {
      pendingBubbles -= 1
      spawnBubble(strength: pendingStrength * (0.5 + 0.5 * Double(rng.unit())), big: false)
    }
    if clickDelay < 0, pendingClicks > 0 || (grainRate > 0.01 && Double(rng.unit()) < grainRate * dt) {
      if pendingClicks > 0 { pendingClicks -= 1 }
      clickDelay = Int(Double(rng.unit()) * Double(n))
      clickAmp = 0.25 + 0.75 * Double(rng.unit())
    }

    // Filters of the continuous voices, retuned once per chunk.
    droneLFO += 2 * Double.pi * 0.55 * dt
    if droneLFO > 2 * Double.pi { droneLFO -= 2 * Double.pi }
    droneFilter.tune(4 * pitch * (1 + 0.25 * sin(droneLFO)), q: 2.2, sampleRate: fs)
    dragWander += (rng.bipolar() - dragWander) * 0.012
    dragFilter.tune(
      gloopLogLerp(2300, 420, thick) * max(0.5, 1 + 6 * dragWander), q: 1.2 + 3.5 * thick, sampleRate: fs)
    hissTrickle += (2 * abs(rng.bipolar()) - hissTrickle) * 0.08
    hissFilter.tune(gloopLogLerp(3900, 1000, thick), q: 0.9, sampleRate: fs)
    squishGlug += 2 * Double.pi * (3.5 + 4 * squish) * dt
    if squishGlug > 2 * Double.pi { squishGlug -= 2 * Double.pi }
    squishWander += (rng.bipolar() - squishWander) * 0.02
    squishFilter.tune(
      gloopLogLerp(1400, 300, thick) * (1 + 0.3 * sin(squishGlug) + 0.25 * squishWander), q: 1.6 + 2.5 * thick,
      sampleRate: fs)
    creakLow.tune(820, q: 9, sampleRate: fs)
    creakHigh.tune(2150, q: 7, sampleRate: fs)
    humFilter.tune(max(5 * humHz, 520), q: 1.4, sampleRate: fs)
    splashFilter.tune(gloopLogLerp(3000, 700, thick), q: 0.7, sampleRate: fs)
    clickFilter.tune(gloopLogLerp(4800, 2600, grit), q: 1.3, sampleRate: fs)
  }

  /// (thick, grit) from `Slot.packTimbre`; nonsense decodes to a mid timbre without grit.
  static func unpackTimbre(_ v: Double) -> (thick: Double, grit: Double) {
    guard v.isFinite, v >= 0, v < 4096 * 4096 else { return (0.5, 0) }
    let hi = (v / 4096).rounded(.down)
    return (min(hi / 4095, 1), min(max(v - hi * 4096, 0) / 4095, 1))
  }

  /// (hiss, squish, creak) from `Slot.packFlow`; a plain 0…1 value is hiss alone; nonsense decodes to silence.
  static func unpackFlow(_ v: Double) -> (hiss: Double, squish: Double, creak: Double) {
    guard v.isFinite, v >= 0, v < 2 * 65_536 + 2 else { return (0, 0, 0) }
    let k = (v / 2).rounded(.down)
    let hiss = min(max(v - 2 * k, 0), 1)
    let hi = (k / 256).rounded(.down)
    return (hiss, min(max(k - 256 * hi, 0) / 255, 1), min(hi / 255, 1))
  }

  /// (pitch, mute mask) from `Slot.packHum`; nonsense decodes to 60 Hz with nothing cancelled.
  static func unpackHum(_ v: Double) -> (hz: Double, mute: Int) {
    guard v.isFinite, v >= 0, v < 256_000 else { return (min(max(v.isFinite ? v : 60, 15), 400), 0) }
    let k = (v / 1000).rounded(.down)
    return (min(max(v - 1000 * k, 15), 400), Int(k) & 0xFF)
  }

  /// New background bubbles and clicks since the texture counters were last read (0 when unchanged, reset, garbled or
  /// jumping by more than 8, which only resynchronises).
  private mutating func newTexture(_ v: Double) -> (bubbles: Int, clicks: Int) {
    guard v.isFinite, v >= 0, v < 65_536 * 65_536 else { return (0, 0) }
    let clicks = Int((v / 65_536).rounded(.down)), bubbles = Int(v - 65_536 * Double(clicks))
    defer {
      lastTextureBubbles = bubbles
      lastTextureClicks = clicks
    }
    guard lastTextureBubbles >= 0, lastTextureClicks >= 0 else { return (0, 0) }
    let db = (bubbles - lastTextureBubbles) & 0xFFFF, dc = (clicks - lastTextureClicks) & 0xFFFF
    return (db <= 8 ? db : 0, dc <= 8 ? dc : 0)
  }

  // MARK: Continuous voices

  @inline(__always) private func bandNorm(_ centre: Double, q: Double) -> Double {
    min((0.5 * fs * q / max(centre, 20)).squareRoot(), 40)
  }

  private mutating func renderBeds(_ n: Int) {
    let droneOn = drone > 1e-4
    let dragOn = drag > 1e-4
    let hissOn = hiss > 1e-4
    let humOn = hum > 1e-4
    let splashOn = splashEnv > 1e-5
    let clickOn = clickEnv > 1e-5 || clickDelay >= 0 || pendingClicks > 0
    let squishOn = squish > 1e-4
    let creakOn = creak > 1e-4 || creakEnv > 1e-5
    guard droneOn || dragOn || hissOn || humOn || splashOn || clickOn || squishOn || creakOn else { return }
    let droneInc = pitch / fs
    let humInc = humHz / fs
    let dragNorm = bandNorm(gloopLogLerp(2300, 420, thick), q: 1.2 + 3.5 * thick)
    let hissNorm = bandNorm(gloopLogLerp(3900, 1000, thick), q: 0.9)
    let splashNorm = bandNorm(gloopLogLerp(3000, 700, thick), q: 0.7)
    let clickNorm = bandNorm(gloopLogLerp(4800, 2600, grit), q: 1.3)
    let squishInc = 2 * Double.pi * (6 + 8 * (1 - thick)) / fs
    let squishDepth = 0.3 + 0.4 * thick
    let droneAmp = drone * Self.droneGain * (0.4 + 0.6 * thick)  // water's 880 Hz sings softly, honey hums
    let dragAmp = drag * Self.dragGain * dragNorm
    let hissAmp = hiss * Self.hissGain * hissNorm * (0.45 + 0.55 * hissTrickle)
    let humAmp = hum * Self.humGain
    let squishNorm = bandNorm(gloopLogLerp(1400, 300, thick), q: 1.6 + 2.5 * thick)
    let squishAmp = squish * Self.squishGain * squishNorm * (0.55 + 0.45 * (0.5 + 0.5 * sin(squishGlug)))
    // The creak: one click every 1/f s (f = 18 Hz … 70 Hz with the squish), jittered ±35 %, ringing two resonances.
    let creakHz = 18 + 52 * min(max((squish - 0.25) / 0.75, 0), 1)
    let creakAmp = creak * Self.creakGain
    let creakNorm = 0.5 * bandNorm(820, q: 9)
    for i in 0..<n {
      var x = 0.0
      if droneOn {
        dronePhase += droneInc
        if dronePhase >= 1 { dronePhase -= 1 }
        let saw = 2 * dronePhase - 1 - gloopPolyBLEP(dronePhase, droneInc)
        x += droneFilter.run(saw).low * droneAmp
      }
      if dragOn {
        dragSquish += squishInc
        if dragSquish > 2 * Double.pi { dragSquish -= 2 * Double.pi }
        let squish = 1 - squishDepth * (0.5 + 0.5 * sin(dragSquish))
        x += dragFilter.run(rng.bipolar()).band * dragAmp * squish
      }
      if hissOn { x += hissFilter.run(rng.bipolar()).band * hissAmp }
      if squishOn { x += squishFilter.run(rng.bipolar()).band * squishAmp }
      if creakOn {
        if creak > 1e-4 {
          creakCountdown -= 1
          if creakCountdown <= 0 {
            creakEnv = creakAmp * (0.55 + 0.45 * Double(rng.unit()))
            creakCountdown = max(1, Int(fs / creakHz * (0.65 + 0.7 * Double(rng.unit()))))
          }
        }
        let e = rng.bipolar() * creakEnv
        x += (creakLow.run(e).band + 0.7 * creakHigh.run(e).band) * creakNorm
        creakEnv *= creakDecay
      }
      if humOn {
        humPhase += humInc
        if humPhase >= 1 { humPhase -= 1 }
        var saw = 2 * humPhase - 1 - gloopPolyBLEP(humPhase, humInc)
        if humMute != 0 {
          // 2φ − 1 = −(2/π)·Σ sin(2πkφ)/k: adding (2/πk)·sin(2πkφ) cancels harmonic k (sines by the Chebyshev
          // recurrence sin((k+1)θ) = 2·cos θ·sin kθ − sin((k−1)θ), one sin and one cos per sample).
          let theta = 2 * Double.pi * humPhase
          let c1 = cos(theta)
          var previous = 0.0, current = sin(theta)
          var k = 1
          var mask = humMute
          while mask != 0 {
            if mask & 1 != 0 { saw += 2 / (Double.pi * Double(k)) * current }
            let next = 2 * c1 * current - previous
            previous = current
            current = next
            mask >>= 1
            k += 1
          }
        }
        x += humFilter.run(saw).low * humAmp
      }
      if splashOn {
        x += splashFilter.run(rng.bipolar()).band * splashEnv * Self.splashGain * splashNorm
        splashEnv *= splashDecay
      }
      if clickOn {
        if clickDelay == 0 {
          clickEnv = clickAmp
          clickDelay = -1
        } else if clickDelay > 0 {
          clickDelay -= 1
        }
        x += clickFilter.run(rng.bipolar() * clickEnv).band * Self.clickGain * clickNorm
        clickEnv *= clickDecay
      }
      mixL[i] += x
      mixR[i] += x
    }
  }

  // MARK: Bubbles

  private mutating func freeBubble() -> Int {
    var quietest = 0
    var quietAmp = Double.infinity
    for i in 0..<Self.bubbleCount {
      if !bubbles[i].active { return i }
      if bubbles[i].amp < quietAmp {
        quietAmp = bubbles[i].amp
        quietest = i
      }
    }
    return quietest
  }

  /// One bubble. `big`: a low "glorp" from the bottom of the size range.
  mutating func spawnBubble(strength: Double, big: Bool) {
    let t = thick
    let lo = gloopLogLerp(650, 75, t), hi = gloopLogLerp(3400, 260, t)
    let u = Double(rng.unit())
    let f0 = big ? lo * (0.8 + 0.3 * u) : lo * pow(hi / lo, u)
    let tau = (0.005 + 0.11 * pow(t, 0.8)) * (0.7 + 0.6 * Double(rng.unit())) * (big ? 1.6 : 1)
    let glide = (0.2 + 0.9 * t) * (big ? 1.3 : 1)
    let w = min(max((420 - f0) / 320, 0), 1)
    let pan = (Double(rng.unit()) * 2 - 1) * 0.4
    let (gl, gr) = SynthDSP.pan(pan)
    let inc = f0 / fs
    var b = GloopBubble()
    b.active = true
    b.c = 1
    b.s = 0
    b.inc = inc
    b.incGrowth = pow(1 + glide, Double(Self.chunk) / (3 * tau * fs))
    b.decay = exp(-1 / (tau * fs))
    b.rise = 1 / max(1, (0.0008 + 0.004 * t) * fs)
    b.attack = 0
    b.h2 = 0.6 * w
    b.h3 = 0.35 * w
    b.amp = min(max(strength, 0), 1) * (0.35 + 0.65 * Double(rng.unit())) * Self.bubbleGain * (0.7 + 0.5 * t)
      / (1 + 0.6 * w)
    b.gl = gl
    b.gr = gr
    bubbles[freeBubble()] = b
  }

  private mutating func renderBubbles(_ n: Int) {
    for v in 0..<Self.bubbleCount where bubbles[v].active {
      var b = bubbles[v]
      let angle = 2 * Double.pi * min(b.inc, 0.45)
      let cr = cos(angle), sr = sin(angle)
      for i in 0..<n {
        let x = b.s, y = b.c
        let tone = x + b.h2 * 2 * x * y + b.h3 * x * (3 - 4 * x * x)
        let out = tone * b.amp * b.attack
        mixL[i] += out * b.gl
        mixR[i] += out * b.gr
        let c = b.c * cr - b.s * sr
        b.s = b.s * cr + b.c * sr
        b.c = c
        b.amp *= b.decay
        b.attack = min(1, b.attack + b.rise)
      }
      let m = (b.c * b.c + b.s * b.s).squareRoot()
      if m > 0, m.isFinite {
        b.c /= m
        b.s /= m
      } else {
        b.active = false
      }
      b.inc *= b.incGrowth
      if b.amp < 1e-5 || b.inc >= 0.45 || !b.amp.isFinite { b.active = false }
      bubbles[v] = b
    }
  }

  // MARK: Squelch

  mutating func spawnSquelch(_ strength: Double) {
    guard strength > 0 else { return }
    var slot = 0
    var quiet = Double.infinity
    for i in 0..<Self.squelchCount {
      if !squelches[i].active {
        slot = i
        quiet = -1
        break
      }
      if squelches[i].env < quiet {
        quiet = squelches[i].env
        slot = i
      }
    }
    let t = thick
    let u = Double(rng.unit())
    let c0 = gloopLogLerp(2600, 330, t) * (0.85 + 0.3 * u)
    let c1 = c0 * (1.6 + 0.8 * t)
    let duration = (0.04 + 0.09 * t) * (0.8 + 0.4 * Double(rng.unit()))
    var s = GloopSquelch()
    s.active = true
    s.centre = c0
    s.centreGrowth = pow(c1 / c0, Double(Self.chunk) / (duration * fs))
    s.q = 1.2 + 4.5 * t
    s.attackSamples = max(1, Int(0.003 * fs))
    s.env = 1
    s.decay = exp(-3 / (duration * fs))
    s.amp = min(strength, 1) * Self.squelchGain
    s.flutterInc = 2 * Double.pi * (22 + 25 * Double(rng.unit())) / fs
    s.flutterDepth = 0.15 + 0.5 * t
    let (gl, gr) = SynthDSP.pan((Double(rng.unit()) * 2 - 1) * 0.3)
    s.gl = gl
    s.gr = gr
    squelches[slot] = s
  }

  private mutating func renderSquelches(_ n: Int) {
    for v in 0..<Self.squelchCount where squelches[v].active {
      var s = squelches[v]
      s.filter.tune(s.centre, q: s.q, sampleRate: fs)
      let norm = bandNorm(s.centre, q: s.q)
      for i in 0..<n {
        let gain: Double
        if s.age < s.attackSamples {
          gain = Double(s.age) / Double(s.attackSamples)
        } else {
          s.env *= s.decay
          gain = s.env
        }
        s.age += 1
        s.flutterPhase += s.flutterInc
        if s.flutterPhase > 2 * Double.pi { s.flutterPhase -= 2 * Double.pi }
        let flutter = 1 - s.flutterDepth * (0.5 + 0.5 * sin(s.flutterPhase))
        let out = s.filter.run(rng.bipolar()).band * norm * s.amp * gain * flutter
        mixL[i] += out * s.gl
        mixR[i] += out * s.gr
      }
      s.centre = min(s.centre * s.centreGrowth, 0.4 * fs)
      s.filter.flush()
      if s.age > s.attackSamples, s.env < 1e-4 { s.active = false }
      squelches[v] = s
    }
  }

  // MARK: Crack

  mutating func spawnCrack(_ strength: Double, crumble: Bool) {
    guard strength > 0 else { return }
    var slot = 0
    var quiet = Double.infinity
    for i in 0..<Self.crackCount {
      if !cracks[i].active {
        slot = i
        quiet = -1
        break
      }
      if cracks[i].impulseAmp < quiet {
        quiet = cracks[i].impulseAmp
        slot = i
      }
    }
    let s = min(strength, 1)
    let g = grit
    var k = GloopCrack()
    k.active = true
    k.impulsesLeft = crumble ? 6 + Int(10 * s * (0.5 + g)) : 3 + Int(5 * s + 4 * g * s)
    k.meanGap = (crumble ? 0.009 : 0.005) * fs
    k.countdown = 0
    k.impulseAmp = (crumble ? 0.45 : 0.9) * s * Self.crackGain
    k.ampDecay = crumble ? 0.9 : 0.75
    k.envDecay = exp(-1 / ((crumble ? 0.0012 : 0.0006) * fs))
    k.highPass.tune(1600, q: 0.7, sampleRate: fs)
    k.body.tune((crumble ? 2400 : 3600) * (0.85 + 0.3 * Double(rng.unit())), q: 2, sampleRate: fs)
    if !crumble {
      let f = (140 + 60 * Double(rng.unit())) / fs
      k.knockCr = cos(2 * Double.pi * f)
      k.knockSr = sin(2 * Double.pi * f)
      k.knockAmp = s * Self.knockGain
      k.knockDecay = exp(-1 / (0.018 * fs))
    }
    let (gl, gr) = SynthDSP.pan((Double(rng.unit()) * 2 - 1) * 0.25)
    k.gl = gl
    k.gr = gr
    cracks[slot] = k
  }

  private mutating func renderCracks(_ n: Int) {
    for v in 0..<Self.crackCount where cracks[v].active {
      var k = cracks[v]
      for i in 0..<n {
        if k.impulsesLeft > 0 {
          if k.countdown <= 0 {
            k.env = k.impulseAmp * (0.5 + 0.5 * Double(rng.unit()))
            k.impulseAmp *= k.ampDecay
            k.impulsesLeft -= 1
            // Exponentially distributed gaps (a crackle, not a buzz).
            let u = max(Double(rng.unit()), 1e-4)
            k.countdown = max(8, Int(-log(u) * k.meanGap))
          } else {
            k.countdown -= 1
          }
        }
        let hp = k.highPass.run(rng.bipolar() * k.env).high
        var out = 0.45 * hp + 0.9 * k.body.run(hp).band
        k.env *= k.envDecay
        if k.knockAmp > 1e-6 {
          let x = k.knockS, y = k.knockC
          out += (x + 0.6 * 2 * x * y + 0.35 * x * (3 - 4 * x * x)) / 1.6 * k.knockAmp
          let c = k.knockC * k.knockCr - k.knockS * k.knockSr
          k.knockS = k.knockS * k.knockCr + k.knockC * k.knockSr
          k.knockC = c
          k.knockAmp *= k.knockDecay
        }
        mixL[i] += out * k.gl
        mixR[i] += out * k.gr
      }
      let m = (k.knockC * k.knockC + k.knockS * k.knockS).squareRoot()
      if m > 0, m.isFinite {
        k.knockC /= m
        k.knockS /= m
      }
      k.highPass.flush()
      k.body.flush()
      if k.impulsesLeft == 0, k.env < 1e-5, k.knockAmp < 1e-5 { k.active = false }
      cracks[v] = k
    }
  }

  // MARK: Splash

  private mutating func splash(_ strength: Double) {
    guard strength > 0 else { return }
    let s = min(strength, 1)
    let t = thick
    splashEnv = max(splashEnv, s * (1 - 0.6 * t))
    splashDecay = exp(-1 / ((0.025 + 0.05 * t) * fs))
    pendingBubbles = min(pendingBubbles + Int((3 + 9 * s) * (1 - t) + 0.5), 32)
    pendingStrength = s
    if t > 0.35 {
      spawnBubble(strength: s, big: true)
      spawnSquelch(s * t * 0.8)
    }
  }

  // MARK: Hygiene

  private mutating func flushStates() {
    droneFilter.flush()
    dragFilter.flush()
    hissFilter.flush()
    humFilter.flush()
    splashFilter.flush()
    clickFilter.flush()
    squishFilter.flush()
    creakLow.flush()
    creakHigh.flush()
    if !(creakEnv > 1e-9) { creakEnv = 0 }
    if !squish.isFinite || !(squish > 1e-12) { squish = 0 }
    if !creak.isFinite || !(creak > 1e-12) { creak = 0 }
    if !(splashEnv > 1e-9) { splashEnv = 0 }
    if !(clickEnv > 1e-9) { clickEnv = 0 }
    if !(abs(dcOutL) > 1e-18) || !dcOutL.isFinite { dcOutL = 0 }
    if !(abs(dcOutR) > 1e-18) || !dcOutR.isFinite { dcOutR = 0 }
    if !(abs(dcInL) > 1e-18) || !dcInL.isFinite { dcInL = 0 }
    if !(abs(dcInR) > 1e-18) || !dcInR.isFinite { dcInR = 0 }
    if !drone.isFinite || !(drone > 1e-12) { drone = 0 }
    if !drag.isFinite || !(drag > 1e-12) { drag = 0 }
    if !hiss.isFinite || !(hiss > 1e-12) { hiss = 0 }
    if !hum.isFinite || !(hum > 1e-12) { hum = 0 }
    if !grainRate.isFinite || !(grainRate > 1e-9) { grainRate = 0 }
    if !bubbleRate.isFinite || !(bubbleRate > 1e-9) { bubbleRate = 0 }
  }
}
