// Microphone.swift — OWNER: PLAY (was FEEL; Documentation/REDESIGN-OWNERSHIP.md).
//
// The microphone's pure pieces:
//   • `MicGate`: when to ask for, and when to release, the microphone. Just in time: the first time Listen is turned
//     above 0 (labkit-from-orbitals-spectra.md §7.4); released 2 s after Listen returns to 0, so the audio session
//     drops back to `.ambient` and Toothpaste Toy follows the ring/silent switch again (with the mic live, `.playAndRecord`
//     ignores it). `-startMic` and an explicit request keep it on. A denied microphone is never asked again (iOS
//     would not show the prompt); the info sheet's PermissionGate says why. If the user then allows it in Settings
//     (the state reads `.off` again), the next raise of Listen asks once more. A failed start is retried after 5 s.
//     If the microphone went off without the gate's say (an interruption that never recommended resuming), lowering
//     Listen to 0 and raising it again starts it.
//   • `MicDenialWatch`: when the UI opens the PermissionGate (a raise while refused, or a refusal at the prompt).
//   • `ToothpasteMicBand`: the pitches the drives listen to. The drives' own Band filter is PHYS's (`MicBand` in
//     Engine/Stimuli.swift: ±⅓ octave around the Band knob, from LabKit's 48-band spectrum); FEEL uses the same band
//     to keep Toothpaste Toy's own sound out of it (LabFeedback drops cue partials within it, widened by an octave each side;
//     the gloop hum is muted and the body tone ducked in that widened band), so the speaker cannot drive the tank.

import Foundation
import LabKitSensors

// MARK: - Just-in-time permission and release

struct MicGate: Sendable {
  enum Action: Sendable, Equatable { case none, start, stop }

  /// Listen above this asks for the microphone (the knob shows "Off" at or below it).
  static let listenOn = 0.005
  /// Seconds at Listen 0 before the microphone is released.
  static let releaseAfter = 2.0
  /// Seconds before a failed start may be tried again.
  static let retryAfter = 5.0

  /// `-startMic` or an explicit request (a mic toggle): never released by the gate.
  var keepAlive = false
  private(set) var requested = false
  private var quietSince: Double?
  private var failedAt: Double?
  private var denied = false

  init(keepAlive: Bool = false) { self.keepAlive = keepAlive }

  /// One frame. `state` is the listener's state with a denial the user has since lifted reported as `.off`.
  mutating func step(listen: Double, state: MicState, now: Double) -> Action {
    if state == .denied {
      denied = true
    } else if denied, state == .off {
      // Allowed in Settings since: the next raise may start it.
      denied = false
      requested = false
    }
    if state == .failed {
      if failedAt == nil { failedAt = now }
      if let t = failedAt, now - t >= Self.retryAfter {
        requested = false
        failedAt = nil
      }
    } else {
      failedAt = nil
    }
    if listen.isFinite, listen > Self.listenOn {
      quietSince = nil
      guard !requested, state == .off || state == .failed else { return .none }
      requested = true
      return .start
    }
    guard state == .on, !keepAlive else {
      quietSince = nil
      // Listen is down and the microphone is not on (an interruption that never recommended resuming, or a stop
      // from outside): the next raise asks again. A denial stays denied (the guard above checks the state).
      if state == .off || state == .failed { requested = false }
      return .none
    }
    let since = quietSince ?? now
    quietSince = since
    guard now - since >= Self.releaseAfter else { return .none }
    quietSince = nil
    requested = false
    return .stop
  }

  /// An explicit request (the mic toggle, `-startMic`).
  mutating func request(state: MicState) -> Action {
    keepAlive = true
    guard state == .off || state == .failed else { return .none }
    requested = true
    return .start
  }

  /// The microphone was stopped from outside (the app went inactive).
  mutating func stopped() {
    requested = false
    quietSince = nil
  }
}

// MARK: - When the UI shows the PermissionGate

/// Counts the moments the microphone is found refused with Listen up: a raise of Listen while it is refused, or a
/// refusal at iOS's prompt while Listen is up (the state turns `.denied`). The UI opens the PermissionGate card (§7.4:
/// "Allow the microphone in Settings", Open Settings) on each new count; a refused microphone with Listen down shows
/// nothing.
struct MicDenialWatch: Sendable, Equatable {
  private(set) var count = 0
  private var listenWasUp = false
  private var last = MicState.off

  mutating func step(listen: Double, state: MicState) {
    let up = listen.isFinite && listen > MicGate.listenOn
    if up, state == .denied, !listenWasUp || last != .denied { count += 1 }
    listenWasUp = up
    last = state
  }
}

// MARK: - The Band knob's filter

enum ToothpasteMicBand {
  /// ⅓ octave, as PHYS's `MicBand` (2^(1/3) ≈ 1.26).
  static let halfWidth = 1.26

  /// The band the Band knob selects, Hz.
  static func range(_ band: Double) -> ClosedRange<Double> {
    let b = band.isFinite ? min(max(band, 20), 8000) : 80
    return (b / halfWidth)...(b * halfWidth)
  }

  /// The band widened by one octave each side (SoundPolicy's rule for cues), Hz: Toothpaste Toy's own continuous sound stays
  /// out of it while the microphone is live.
  static func keepOut(_ band: Double) -> ClosedRange<Double> {
    let r = range(band)
    return (r.lowerBound / 2)...(r.upperBound * 2)
  }
}
