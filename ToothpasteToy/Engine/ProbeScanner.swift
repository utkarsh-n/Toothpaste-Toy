// ProbeScanner.swift — OWNER: PLAY (was PHYS; Documentation/REDESIGN-OWNERSHIP.md).
//
// The rheometer probe. The solver samples one point per frame (MPMFrameInput.probe, averaged over 3 cells) and
// reports it 1–2 frames later (MPMStats.frameIndex says which frame). With a finger in the fluid the probe sits at
// the finger's leading edge every frame. Without one it looks for "the strongest-sheared region": every other frame
// it samples the next candidate (the stir paddle's tip, each prop's leading side, a lattice over the pool) and moves to
// a candidate that shears clearly harder (1.5×) than where it sits; the reading shown is always from the frames that
// sampled the chosen point, so the cursor does not jump with the scan.

import Foundation
import simd
import LabKitMPM

struct ProbeScanner {
  enum Role: Equatable { case main, candidate(Int) }

  /// Point sampled per encoded frame, by the solver's frame index (the engine is the only encoder).
  private var log: [Int: (point: SIMD2<Double>, role: Role)] = [:]
  private var encodes = 0
  private(set) var chosen: SIMD2<Double>?
  private var chosenRate = 0.0
  private var candidateRates: [Int: Double] = [:]
  private var nextCandidate = 0
  /// The latest reading at the chosen point.
  private(set) var reading = ProbeReading()
  private var lastSeenFrame = 0

  /// Picks the point the solver samples this frame. `finger` wins; else the scan.
  mutating func point(finger: SIMD2<Double>?, candidates: [SIMD2<Double>]) -> SIMD2<Double>? {
    let index = encodes + 1  // the solver's frameIndex for the encode that follows
    if let f = finger {
      chosen = f
      chosenRate = 0
      log[index] = (f, .main)
      return f
    }
    guard !candidates.isEmpty else { return chosen }
    if chosen == nil { chosen = candidates[0] }
    var p = chosen!
    var role = Role.main
    if index % 2 == 0 {
      let i = nextCandidate % candidates.count
      nextCandidate += 1
      p = candidates[i]
      role = .candidate(i)
    }
    log[index] = (p, role)
    return p
  }

  /// Call once per encode that used `point(…)`.
  mutating func didEncode() { encodes += 1 }

  /// Folds the latest solver statistics in; returns the reading at the chosen point.
  mutating func observe(_ stats: MPMStats, candidates: [SIMD2<Double>], fingerDown: Bool) -> ProbeReading {
    if stats.frameIndex != lastSeenFrame, let entry = log[stats.frameIndex] {
      lastSeenFrame = stats.frameIndex
      let rate = stats.probe.shearRate
      switch entry.role {
      case .main:
        chosenRate = rate
        reading = ProbeReading(
          position: entry.point, shearRate: rate, stress: stats.probe.stress, viscosity: stats.probe.viscosity,
          solidFraction: stats.probe.solidFraction, fingerDown: fingerDown)
      case .candidate(let i):
        candidateRates[i] = rate
        if !fingerDown, i < candidates.count, rate > max(1.5 * chosenRate, 0.05) {
          chosen = candidates[i]
          chosenRate = rate
        }
      }
      log = log.filter { $0.key > stats.frameIndex - 8 }
    }
    var r = reading
    r.fingerDown = fingerDown
    if let c = chosen { r.position = fingerDown ? reading.position : c }
    return r
  }

  mutating func reset() {
    log.removeAll()
    chosen = nil
    chosenRate = 0
    candidateRates.removeAll()
    reading = ProbeReading()
  }
}
