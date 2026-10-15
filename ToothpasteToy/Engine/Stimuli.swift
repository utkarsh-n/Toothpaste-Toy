// Stimuli.swift — OWNER: PLAY (was PHYS; Documentation/REDESIGN-OWNERSHIP.md).
//
// Everything that turns the outside world into stimuli for the tank, apart from touch:
//   ToothpasteDrives       the microphone routes of the Signals page (Listen sets the depth, Drives picks the target, Band
//                    picks the pitches, Gain the sensitivity) and the device-thermal route (off by default).
//   MicBand          the level of the Band knob's pitches from LabKit's 48-band spectrum.
//   FieldBaseline    the magnetometer's |B| at rest, so a magnet near the phone reads as Δ|B| and the Earth's field
//                    (and its changes as the phone turns) reads as nothing.
//   SubstepBudget    the frame-rate policy: the solver's substep cap follows the frame time (2 400 substeps/s), so a
//                    60 Hz display still runs in real time; below 60 Hz the clock slows and telemetry flags it. Hot
//                    (Serious), a 60 Hz frame keeps up to 28 substeps while the GPU stays under 70 % of the frame.
// Every route has a manual override: a knob the user is holding wins over its drive (ModulationRouter `holding`),
// Listen at 0 silences the microphone routes, Layers › Use tilt and Use the magnetometer switch those sensors off.

import Foundation
import simd
import LabKitCore
import LabKitMPM

enum ToothpasteDrives {
  /// Channel targets (not registered knobs).
  static let shakeChannel: ParamID = "drive.shake"
  static let kickChannel: ParamID = "drive.kick"
  /// The Band knob's level, 0…1 × Gain (filled by the engine before the routes run).
  static let bandSource: ModSourceID = "mic.band"

  static let routes: [ModRoute] = [
    ModRoute(
      "listen.shake", source: bandSource, target: shakeChannel, depthParam: .listen,
      gate: ModGate(.drives, DriveTarget.shake.rawValue), mode: .add(20), attack: 0.01, release: 0.15),
    ModRoute(
      "listen.gravity", source: bandSource, target: .gravity, depthParam: .listen,
      gate: ModGate(.drives, DriveTarget.gravity.rawValue), mode: .add(2), attack: 0.03, release: 0.35),
    ModRoute(
      "listen.stir", source: bandSource, target: .stir, depthParam: .listen,
      gate: ModGate(.drives, DriveTarget.stir.rawValue), mode: .add(3), attack: 0.03, release: 0.35, clampToRange: true),
    ModRoute(
      "listen.kicks", source: .micOnset, target: kickChannel, depthParam: .listen,
      gate: ModGate(.drives, DriveTarget.kicks.rawValue), curve: .normalize(6), mode: .trigger(threshold: 1.5)),
    ModRoute(
      "listen.heat", source: bandSource, target: .heat, depthParam: .listen,
      gate: ModGate(.drives, DriveTarget.heat.rawValue), mode: .add(40), attack: 0.2, release: 1.0, clampToRange: true),
    // The phone's own warmth: thermal state nominal 0 … critical 1 adds up to 30 °C. Off unless launched with
    // -thermalHeat (a playful route, ARCHITECTURE.md §6).
    ModRoute(
      "device.heat", source: .thermal, target: .heat, mode: .add(30), attack: 2, release: 5, clampToRange: true,
      enabled: false),
  ]

  /// Route ids that move a registered knob, for `held` handling and tests.
  static let knobRoutes: Set<String> = ["listen.gravity", "listen.stir", "listen.heat", "device.heat"]
}

/// The level of the pitches around the Band knob (40–2000 Hz): the mean of LabKit's log bands within ±⅓ octave,
/// 0…1, already scaled by Gain inside `Spectrum.update`.
@MainActor final class MicBand {
  private let spectrum = Spectrum()
  private(set) var level = 0.0

  func update(_ snapshot: MicSnapshot?, gain: Double, centre: Double, dt: Double) -> Double {
    guard let s = snapshot, s.samples.count >= Spectrum.size else {
      level = 0
      return 0
    }
    spectrum.update(s.samples, gain: Float(gain), dt: Float(dt))
    let low = 45.0, high = 15_000.0
    let n = Double(Spectrum.bandCount)
    func band(_ f: Double) -> Int { Int((log(max(f, low) / low) / log(high / low) * n).rounded(.down)) }
    let lo = max(0, band(centre / 1.26)), hi = min(Spectrum.bandCount - 1, max(lo, band(centre * 1.26)))
    level = Double(spectrum.mean(lo..<(hi + 1)))
    return level
  }
}

/// |B| at rest for the magnetometer route. It follows slowly (τ 20 s) while the field is calm (within 30 µT), and
/// freezes while something magnetic is near, so a held magnet is not forgotten.
struct FieldBaseline {
  private(set) var baseline: Double?
  static let calm = 30.0  // µT
  static let tau = 20.0  // s

  /// Returns Δ|B| ≥ 0, µT.
  mutating func step(fieldMicroTesla b: Double, dt: Double) -> Double {
    guard b.isFinite, b > 0 else { return 0 }
    guard let base = baseline else {
      baseline = b
      return 0
    }
    let delta = b - base
    if abs(delta) < Self.calm { baseline = base + delta * min(1, dt / Self.tau) }
    return max(0, delta)
  }

  mutating func reset() { baseline = nil }
}

/// The frame-rate policy. The substep rule needs about 14 substeps per 1/120 s frame for a 45 % oobleck pool and
/// twice that per 1/60 s frame; `MPMQuality.standard` caps at 20. The cap here follows the frame time at the same
/// per-second budget (20 per 1/120 s), up to twice the quality's cap (a 60 Hz display), so dropped frames do not slow
/// the clock; below 60 Hz the solver simulates less than real time and `MPMStats.lagging` reports it (the telemetry's
/// `lagging` flag). A finer quality steps down to `.standard` once, after `stepDownAfter` seconds of lag or of GPU time
/// over 90 % of the frame (measured `MPMStats.gpuMilliseconds`), or at once when the phone is hot (thermal state
/// serious or critical). While it is hot the 60 Hz doubling is off too, so the GPU does half the work and the clock
/// slows instead.
struct SubstepBudget {
  private(set) var laggingFor = 0.0
  private(set) var steppedDown = false
  static let stepDownAfter = 3.0
  /// `ModSources[.thermal]` at and above which the phone counts as hot (0 nominal, 0.33 fair, 0.67 serious, 1 critical).
  static let hot = 0.6

  /// GPU milliseconds per frame, smoothed over about 0.5 s (`noteGPU`): the hot policy's gate.
  private(set) var gpuAverage = 0.0
  /// Hot, a 60 Hz frame may still take up to `hotCap` substeps while the smoothed GPU time stays under this share of
  /// the frame (PLAY, 14 October 2026; DEVICE-RUN-2 recommendation 3: at Serious the app runs at 60 Hz with the GPU at
  /// 10.5–11 ms of 16.7, and oobleck, putty, MR fluid and lava hit the 20-substep cap on every frame, so the user saw
  /// SLOW MOTION while the GPU had headroom).
  static let hotGPUShare = 0.7
  static let hotCap = 28

  /// Feeds the latest frame's GPU time (ms; 0 = unknown, ignored).
  mutating func noteGPU(_ milliseconds: Double, dt: Double) {
    guard milliseconds.isFinite, milliseconds > 0, dt > 0 else { return }
    gpuAverage = gpuAverage > 0 ? gpuAverage + (milliseconds - gpuAverage) * min(1, dt / 0.5) : milliseconds
  }

  func cap(for dt: Double, base: MPMQuality, thermal: Double = 0) -> Int {
    let perSecond = Double(base.maxSubsteps) * 120
    let scaled = max(Int((perSecond * dt).rounded(.up)), base.maxSubsteps)
    if thermal >= Self.hot {
      // Hot: no doubling at 120 Hz; at 60 Hz (or slower) up to `hotCap` while the GPU has headroom.
      guard dt > 1.0 / 90, gpuAverage > 0, gpuAverage < Self.hotGPUShare * dt * 1000 else { return base.maxSubsteps }
      return min(scaled, max(Self.hotCap, base.maxSubsteps))
    }
    return min(scaled, 2 * base.maxSubsteps)
  }

  /// Returns the quality to switch to, if any.
  mutating func observe(
    lagging: Bool, dt: Double, current: MPMQuality, gpuMilliseconds: Double = 0, thermal: Double = 0
  ) -> MPMQuality? {
    let overBudget = gpuMilliseconds > 0.9 * dt * 1000
    laggingFor = lagging || overBudget ? laggingFor + dt : 0
    guard !steppedDown, current.cellSize < MPMQuality.standard.cellSize,
      laggingFor > Self.stepDownAfter || thermal >= Self.hot
    else { return nil }
    steppedDown = true
    laggingFor = 0
    return .standard
  }
}

/// Where the mic's kicks land: a low-discrepancy walk across the surface.
struct KickPlacer {
  private var k = 0
  mutating func next() -> Double {
    k += 1
    let u = (0.5 + Double(k) * 0.618_033_988_75).truncatingRemainder(dividingBy: 1)
    return 0.15 + 0.7 * u
  }
}

// MARK: - Solver frames and the floor vibration

/// The last few solver frames (`MPMSolver.encode` calls): their start on the solver's clock, their length and the floor
/// vibration they ran under. `MPMStats.frameIndex` counts the same encodes, so a frame's statistics (1–2 frames late)
/// can be paired with the vibration that produced them.
struct EncodeLog: Sendable {
  struct Entry: Sendable, Equatable {
    var index: Int
    var start: Double
    var duration: Double
    var amplitude: Double
    var frequency: Double
  }

  private(set) var entries: [Entry] = []
  private(set) var count = 0

  mutating func record(start: Double, end: Double, vibration: (amplitude: Double, frequency: Double)) {
    count += 1
    if entries.count >= 8 { entries.removeFirst() }
    entries.append(Entry(index: count, start: start, duration: max(end - start, 0), amplitude: vibration.amplitude,
                         frequency: vibration.frequency))
  }

  /// The floor vibration's mean extra gravity over the frame `stats` describes, m/s² along the tank's y: the solver
  /// adds −A·sin(2πf·t) to gravity's y at each substep (LabKitMPM), so the mean over [t₀, t₀ + T] is
  /// A·(cos 2πf(t₀ + T) − cos 2πf·t₀)/(2πf·T). 0 when unknown or still.
  func meanVibration(for stats: MPMStats) -> Double {
    guard let e = entries.last(where: { $0.index == stats.frameIndex }), e.duration > 0, e.amplitude > 0, e.frequency > 0
    else { return 0 }
    let w = 2 * Double.pi * e.frequency
    let mean = e.amplitude * (cos(w * (e.start + e.duration)) - cos(w * e.start)) / (w * e.duration)
    return mean.isFinite ? mean : 0
  }
}
