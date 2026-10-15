// StatusFeed.swift — OWNER: UI (Documentation/REDESIGN-OWNERSHIP.md).
//
// Status banners: which simulation events and sensor changes deserve one, and the native glass card that shows it for
// 6.5 s at the top of the chamber's headspace (Metro: readable text on native glass, never over the readouts). Events
// come from the hub's `recentEvents`; sensor changes (microphone on or refused, slow motion, a magnet arriving, simulated
// motion) are watched at the 10 Hz telemetry rate by `ToothpasteStatusWatcher`, which is plain state so the tests can
// drive it.
// Also: the UI's launch arguments (`ToothpasteUIArgs`) and the `-logFrames` frame log used for layout checks.

import Foundation
import LabKitCore
import LabKitSensors
import LabKitUI
import SwiftUI

// MARK: - Events → banners

@MainActor enum ToothpasteEventBanners {
  /// The banner for the most important of `events`: an experiment beats a material change, which beats a dropped
  /// prop, which beats a resolution change. Touches, pokes and prop hits get none (they are felt and seen).
  static func banner(for events: [SimEvent], catalog: any ToothpasteCatalog) -> ToothpasteBanner? {
    var best: (rank: Int, banner: ToothpasteBanner)?
    func offer(_ rank: Int, _ b: ToothpasteBanner?) {
      guard let b else { return }
      if best == nil || rank > best!.rank { best = (rank, b) }
    }
    for e in events {
      switch e {
      case .experimentApplied(let id):
        offer(4, catalog.experiments.first { $0.id == id }.map(ToothpasteCopy.experimentBanner))
      case .materialChanged(let id):
        offer(3, ToothpasteCopy.materialBanner(catalog.material(id)))
      case .propDropped(let kind):
        offer(2, ToothpasteCopy.propBanner(catalog.prop(kind)))
      case .qualityChanged:
        offer(1, ToothpasteCopy.qualityChanged)
      default:
        break
      }
    }
    return best?.banner
  }
}

// MARK: - Sensors → banners

/// Watches the 10 Hz telemetry for sensor changes worth a banner. Each kind fires once per change: the microphone on
/// a state transition, slow motion after 1.5 s of lag (then at most every 90 s), a magnet when the field rises past
/// 150 µT (re-armed below 80 µT), simulated motion once, the first time it is seen.
@MainActor final class ToothpasteStatusWatcher {
  struct Input {
    var telemetry: ToothpasteTelemetry
    var mic: MicState
    var useMagnetometer: Bool
    var material: MaterialID
    /// The Drives knob's label ("Shake").
    var drives: String
    /// Seconds, any monotonic clock.
    var now: Double
  }

  static let magnetOn = 150.0
  static let magnetOff = 80.0
  static let lagDelay = 1.5
  static let slowRepeat = 90.0

  private var lastMic: MicState?
  private var laggingSince: Double?
  private var lastSlowBanner = -Double.infinity
  private var magnetArmed = true
  private var simulatedShown = false
  /// True while the solver has lagged for `lagDelay` (the stage's "Slow motion" tag).
  private(set) var slowMotion = false

  func update(_ i: Input) -> ToothpasteBanner? {
    var out: ToothpasteBanner?
    func offer(_ b: ToothpasteBanner) { if out == nil { out = b } }

    if let last = lastMic, last != i.mic {
      switch i.mic {
      case .on: offer(ToothpasteCopy.micOnBanner(drives: i.drives))
      case .denied: offer(ToothpasteCopy.micDenied)
      case .failed: offer(ToothpasteCopy.micFailed)
      case .off, .starting: break
      }
    }
    lastMic = i.mic

    if i.telemetry.lagging {
      let since = laggingSince ?? i.now
      laggingSince = since
      slowMotion = i.now - since >= Self.lagDelay
      if slowMotion, i.now - lastSlowBanner >= Self.slowRepeat {
        lastSlowBanner = i.now
        offer(ToothpasteCopy.slowMotion)
      }
    } else {
      laggingSince = nil
      slowMotion = false
    }

    if i.useMagnetometer {
      if magnetArmed, i.telemetry.fieldMicroTesla > Self.magnetOn {
        magnetArmed = false
        offer(ToothpasteCopy.magnetBanner(microTesla: i.telemetry.fieldMicroTesla, isMR: i.material == "mrFluid"))
      } else if i.telemetry.fieldMicroTesla < Self.magnetOff {
        magnetArmed = true
      }
    }

    if !simulatedShown, i.telemetry.simulatedMotion, i.telemetry.particles > 0 {
      simulatedShown = true
      offer(ToothpasteCopy.simulatedMotion)
    }
    return out
  }
}

// MARK: - The banner

/// A native glass card with the symbol in the banner's colour. Posts `spoken` (or the text) to VoiceOver when it appears
/// or changes. Capped at accessibility size 1 so it never covers the whole chamber.
struct ToothpasteBannerView: View {
  let banner: ToothpasteBanner

  var body: some View {
    Label {
      Text(banner.text)
        .foregroundStyle(Metro.Colour.displayInk.color)
    } icon: {
      Image(systemName: banner.icon).foregroundStyle(banner.tint.map { Color($0) } ?? Metro.Colour.actionCyan.color)
    }
    .font(.subheadline.weight(.medium))
    .multilineTextAlignment(.leading)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(.regular.tint(Metro.Colour.canvas.color.opacity(0.55)), in: .rect(cornerRadius: 18))
    .contentTransition(.opacity)
    .allowsHitTesting(false)
    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(banner.spoken ?? banner.text)
    .accessibilityAddTraits(.updatesFrequently)
    .accessibilityIdentifier("status-banner")
    .onAppear { AccessibilityNotification.Announcement(banner.spoken ?? banner.text).post() }
    .onChange(of: banner) { _, b in AccessibilityNotification.Announcement(b.spoken ?? b.text).post() }
  }
}

// MARK: - Launch arguments and the frame log

/// The UI's own launch arguments: `-pastes`, `-more`, `-rheometer`, `-info`, `-infoPanel <01…09>`, `-large`,
/// `-banner <kind>`, `-lensDemo`, `-squeezeDemo`, `-quietSensors`, `-logFrames`.
/// `override` lets the in-app screenshot tour (App/Snapshot.swift) re-create the screen with other arguments.
@MainActor enum ToothpasteUIArgs {
  static var override: [String]?
  static var all: [String] { override ?? LaunchOptions.arguments }
  static func has(_ flag: String) -> Bool { all.contains(flag) }
  static func value(_ flag: String) -> String? {
    guard let i = all.firstIndex(of: flag), i + 1 < all.count else { return nil }
    return all[i + 1]
  }
}

/// `-logFrames`: named global frames written to tmp/frames.txt as "FRAME name x y w h" (points), so layout can be
/// checked from the host without a screenshot (the header, the squeeze row, the chamber and its region, the rack, the
/// controls, the floating actions).
@MainActor enum ToothpasteFrameLog {
  static var enabled: Bool { ToothpasteUIArgs.has("-logFrames") }
  private static var frames: [String: CGRect] = [:]
  private static var pending = false

  static func record(_ name: String, _ rect: CGRect) {
    guard enabled, frames[name] != rect else { return }
    frames[name] = rect
    guard !pending else { return }
    pending = true
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(300))
      pending = false
      let lines = frames.keys.sorted().map { k -> String in
        let r = frames[k]!
        return String(format: "FRAME %@ %.1f %.1f %.1f %.1f", k, r.minX, r.minY, r.width, r.height)
      }
      let url = FileManager.default.temporaryDirectory.appending(path: "frames.txt")
      try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
  }
}

extension View {
  /// Records this view's global frame under `name` when `-logFrames` is set.
  func logFrame(_ name: String) -> some View {
    onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { ToothpasteFrameLog.record(name, $0) }
  }
}
