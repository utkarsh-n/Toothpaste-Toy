// MetroSignals.swift — OWNER: UI (Documentation/REDESIGN-OWNERSHIP.md).
//
// The chamber's channels and readouts (REDESIGN.md §4; Metro spec §11–§12):
// - three vertical signal pills — shear γ̇ (wave cyan), stress σ (amber), structure λ / jam (spectrum violet). The
//   capsule, its title and its end labels never change (constant outline, contract 5); the interior shows where the
//   level has been for three seconds (a fading trail), the level now (a bright meniscus over a filled column, on a Wave
//   spring) and the paste events as an attack/decay glow (a yield in σ, a jam in λ, a tear-off in γ̇). Levels are the
//   hub's log scales (γ̇ 0.01–1000 s⁻¹, σ 1–10 000 Pa) and λ 0…1; the accessible value says so.
// - the lens readout: γ̇, σ and the state word at the probe, fixed beside the chamber and never filtered or moved.
// - event tiles: yield, jam, tear-off, each with its count since the last refill and an amber attack/decay.
// - the telemetry row: yield stress τ_y, the paste's viscosity η and the tilt, rounded numerals with monospaced units.
// Drawing reads `ChamberMotion`'s unobserved springs and history in TimelineViews (60 Hz while running, still under
// Reduce Motion); the numbers come from the hub's 10 Hz values.

import LabKitCore
import QuartzCore
import SwiftUI

// MARK: - Families

extension PasteSignal {
  var title: String {
    switch self {
    case .shear: "γ̇"
    case .stress: "σ"
    case .structure: "λ"
    }
  }
  var primary: Color {
    switch self {
    case .shear: Metro.Colour.wave.color
    case .stress: Metro.Colour.instrumentAmber.color
    case .structure: Metro.Colour.spectrum.color
    }
  }
  var secondary: Color {
    switch self {
    case .shear: Metro.Colour.waveDepth.color
    case .stress: Metro.Colour.carrier.color
    case .structure: Metro.Colour.spectrumDepth.color
    }
  }
  /// The pill's end labels (top, bottom).
  var ends: (String, String) {
    switch self {
    case .shear: ("1k", "0.01")
    case .stress: ("10k", "1")
    case .structure: ("1", "0")
    }
  }
  /// The paste event whose attack/decay lights this pill's interior.
  var event: PasteEvent.Kind {
    switch self {
    case .shear: .tearOff
    case .stress: .yield
    case .structure: .jam
    }
  }
}

// MARK: - Pill

struct SignalPill: View {
  let signal: PasteSignal
  let motion: ChamberMotion
  let spoken: String

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.scenePhase) private var scenePhase
  @ScaledMetric(relativeTo: .caption2) private var titleSize = Metro.Typography.pillTitle.size
  @ScaledMetric(relativeTo: .caption2) private var axisSize = Metro.Typography.pillAxis.size

  var body: some View {
    VStack(spacing: Metro.Pill.gap) {
      Text(signal.title)
        .font(.system(size: titleSize, weight: .semibold, design: .monospaced))
        .foregroundStyle(signal.primary)
        .lineLimit(1)
        .frame(height: 14)
      axis(signal.ends.0)
      TimelineView(.animation(minimumInterval: reduceMotion ? 0.1 : 1.0 / 60, paused: scenePhase != .active)) { tl in
        Canvas { context, size in
          draw(&context, size: size, now: tl.date.timeIntervalSinceReferenceDate)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      axis(signal.ends.1)
    }
    .padding(.horizontal, Metro.Pill.horizontalPadding)
    .padding(.vertical, Metro.Pill.verticalPadding)
    .background {
      Capsule().fill(
        LinearGradient(
          colors: [Metro.Colour.pillLight.color, Metro.Colour.pillDark.color], startPoint: .leading, endPoint: .trailing))
    }
    .overlay {
      // Constant: never animated by events (Metro contract 5).
      Capsule().strokeBorder(
        LinearGradient(
          colors: [
            signal.primary.opacity(
              contrast == .increased ? Metro.Opacity.pillPrimaryBorderIncreasedContrast : Metro.Opacity.pillPrimaryBorder),
            .white.opacity(Metro.Opacity.pillMiddleBorder), signal.secondary.opacity(Metro.Opacity.pillSecondaryBorder),
          ], startPoint: .topLeading, endPoint: .bottomTrailing),
        lineWidth: Metro.Stroke.pill)
    }
    .clipShape(Capsule())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(ToothpasteCopy.pillLabel(signal))
    .accessibilityValue(spoken)
    .accessibilityIdentifier("pill-\(signal.rawValue)")
  }

  private func axis(_ text: String) -> some View {
    Text(text)
      .font(.system(size: axisSize, weight: .medium, design: .monospaced))
      .foregroundStyle(.white.opacity(Metro.Opacity.supportingInk))
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      .frame(height: 11)
  }

  private func draw(_ context: inout GraphicsContext, size: CGSize, now: Double) {
    let plot = CGRect(x: 1, y: 2, width: max(1, size.width - 2), height: max(1, size.height - 4))
    // Quiet calibration (decades for the log channels, quarters for λ).
    let lines = signal == .shear ? 5 : signal == .stress ? 4 : 4
    for i in 0...lines {
      let y = plot.minY + plot.height * CGFloat(i) / CGFloat(lines)
      var tick = Path()
      tick.move(to: CGPoint(x: plot.minX, y: y))
      tick.addLine(to: CGPoint(x: plot.maxX, y: y))
      context.stroke(tick, with: .color(.white.opacity(i == 0 || i == lines ? 0.17 : 0.07)), lineWidth: 0.5)
    }
    var spine = Path()
    spine.move(to: CGPoint(x: plot.minX + 0.5, y: plot.minY))
    spine.addLine(to: CGPoint(x: plot.minX + 0.5, y: plot.maxY))
    context.stroke(spine, with: .color(signal.primary.opacity(0.22)), lineWidth: 0.6)

    let media = CACurrentMediaTime()
    let energy = reduceMotion ? 0 : motion.pulses.energy(signal.event, at: media)
    let level = motion.level(signal)
    func y(_ l: Double) -> CGFloat { plot.maxY - plot.height * CGFloat(min(max(l, 0), 1)) }

    // Where the level has been: a fading trail of marks (newest brightest).
    let trail = motion.history.newestFirst(signal)
    for (age, l) in trail.enumerated() where age % 2 == 0 && l > 0.001 {
      let fade = 1 - Double(age) / Double(ChannelHistory.count)
      var mark = Path()
      let yy = y(l)
      mark.move(to: CGPoint(x: plot.minX + 2, y: yy))
      mark.addLine(to: CGPoint(x: plot.maxX - 2, y: yy))
      context.stroke(mark, with: .color(signal.secondary.opacity(0.10 * fade)), lineWidth: 1)
    }

    // Now: a filled column up to the level and a bright meniscus; event energy brightens both.
    if level > 0.001 {
      let top = y(level)
      let column = Path(CGRect(x: plot.minX + 1.5, y: top, width: plot.width - 3, height: plot.maxY - top))
      context.fill(
        column,
        with: .linearGradient(
          Gradient(colors: [signal.primary.opacity(0.30 + 0.35 * energy), signal.secondary.opacity(0.10 + 0.2 * energy)]),
          startPoint: CGPoint(x: plot.midX, y: top), endPoint: CGPoint(x: plot.midX, y: plot.maxY)))
      var meniscus = Path()
      meniscus.move(to: CGPoint(x: plot.minX + 1, y: top))
      meniscus.addLine(to: CGPoint(x: plot.maxX - 1, y: top))
      context.stroke(meniscus, with: .color(signal.primary.opacity(0.95)), lineWidth: 1.4 + 1.2 * energy)
    }
    if energy > 0.01 {
      let glow = Path(roundedRect: plot.insetBy(dx: 1, dy: 1), cornerRadius: plot.width / 2)
      context.fill(glow, with: .color(signal.primary.opacity(0.10 * energy)))
    }
  }
}

// MARK: - The signal rack (pills, lens readout, event tiles)

struct SignalRack: View {
  let model: ToothpasteModel
  let motion: ChamberMotion
  let height: CGFloat

  static let width: CGFloat = 104
  static let pillWidth: CGFloat = 32
  static let pillGap: CGFloat = 4

  var body: some View {
    VStack(spacing: 8) {
      LivePills(model: model, motion: motion)
        .frame(maxHeight: .infinity)
      LensReadout(model: model, lensActive: motion.lensActive)
      EventTiles(motion: motion)
    }
    .frame(width: Self.width, height: height)
  }
}

/// The three pills; their spoken values follow the 10 Hz channels.
private struct LivePills: View {
  let model: ToothpasteModel
  let motion: ChamberMotion

  var body: some View {
    let c = model.channels
    HStack(spacing: SignalRack.pillGap) {
      SignalPill(signal: .shear, motion: motion, spoken: ToothpasteCopy.pillSpoken(.shear, channels: c))
      SignalPill(signal: .stress, motion: motion, spoken: ToothpasteCopy.pillSpoken(.stress, channels: c))
      SignalPill(signal: .structure, motion: motion, spoken: ToothpasteCopy.pillSpoken(.structure, channels: c))
    }
    .frame(minHeight: 120)
  }
}

/// The lens's fixed readout: γ̇ and σ at the probe and the state word (Metro: unfiltered, never moves).
struct LensReadout: View {
  let model: ToothpasteModel
  let lensActive: Bool

  var body: some View {
    let c = model.channels
    let shear = ToothpasteCopy.quantity(c.shear.value, unit: "s⁻¹")
    let stress = ToothpasteCopy.quantity(c.stress.value, unit: "Pa")
    VStack(alignment: .leading, spacing: 4) {
      Text(lensActive ? ToothpasteCopy.lensTitle : ToothpasteCopy.probeTitle)
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .tracking(1.2)
        .foregroundStyle(Metro.Colour.secondaryInk.color)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      row(PasteSignal.shear, shear)
      row(PasteSignal.stress, stress)
      Text(ToothpasteCopy.stateWord(c.state))
        .font(.system(.subheadline, design: .serif, weight: .medium))
        .italic()
        .foregroundStyle(Metro.Colour.instrumentCyan.color)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .contentTransition(.opacity)
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Metro.Colour.content.color.opacity(Metro.Opacity.panelFill), in: .rect(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(Metro.Opacity.panelBorder), lineWidth: 1)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(lensActive ? ToothpasteCopy.lensSpokenTitle : ToothpasteCopy.probeSpokenTitle)
    .accessibilityValue(ToothpasteCopy.lensSpoken(c))
    .accessibilityIdentifier("lens-readout")
  }

  private func row(_ s: PasteSignal, _ q: (value: String, unit: String)) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 3) {
      Text(s.title)
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundStyle(s.primary)
        .frame(width: 13, alignment: .leading)
      Text(q.value)
        .font(.system(size: 17, weight: .medium, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(Metro.Colour.displayInk.color)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      Text(q.unit)
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(Metro.Opacity.dialMetadataInk))
        .lineLimit(1)
    }
  }
}

/// Yield, jam and tear-off: Metro's event tiles, stacked, with counts and an amber attack/decay.
struct EventTiles: View {
  let motion: ChamberMotion
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  static let kinds: [PasteEvent.Kind] = [.yield, .jam, .tearOff]
  static let tileHeight: CGFloat = 30

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: scenePhase != .active)) { _ in
      let now = CACurrentMediaTime()
      VStack(spacing: 5) {
        ForEach(Self.kinds, id: \.self) { kind in
          tile(kind, energy: reduceMotion ? 0 : motion.pulses.energy(kind, at: now), count: motion.pulses.count(kind))
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(ToothpasteCopy.eventsTitle)
    .accessibilityValue(ToothpasteCopy.eventsSpoken(Self.kinds.map { ($0, motion.pulses.count($0)) }))
    .accessibilityIdentifier("event-tiles")
  }

  private func tile(_ kind: PasteEvent.Kind, energy: Double, count: Int) -> some View {
    let amber = Metro.Colour.actionAmber.color
    let lit = energy > 0.02
    return HStack(spacing: 4) {
      Text(ToothpasteCopy.eventTile(kind))
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .tracking(0.8)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Spacer(minLength: 2)
      Text("\(count)")
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .monospacedDigit()
    }
    .foregroundStyle(lit ? amber : Metro.Colour.secondaryInk.color)
    .padding(.horizontal, 8)
    .frame(maxWidth: .infinity, minHeight: Self.tileHeight, maxHeight: Self.tileHeight)
    .background(
      lit ? amber.opacity(Metro.Tile.activeFillOpacity + 0.16 * energy) : .white.opacity(Metro.Tile.idleFillOpacity),
      in: .rect(cornerRadius: Metro.Radius.beatTile))
    .overlay(
      RoundedRectangle(cornerRadius: Metro.Radius.beatTile)
        .stroke(lit ? amber.opacity(Metro.Tile.activeBorderOpacity) : .white.opacity(Metro.Tile.idleBorderOpacity)))
  }
}

// MARK: - Telemetry row

/// τ_y · η · tilt (Metro §12): label, rounded numerals, monospaced unit on the first baseline, 1 × 30 pt dividers.
struct TelemetryStrip: View {
  let model: ToothpasteModel
  let motion: ChamberMotion
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    let yieldSpec = model.params.spec(.yield)
    let tauY = model.params[.yield]
    let yieldText = ToothpasteCopy.yieldReadout(tauY, spec: yieldSpec)
    TimelineView(.periodic(from: .now, by: scenePhase == .active ? 1.0 / 30 : 1)) { _ in
      let eta = pow(10, Double(motion.viscosityLog.value))
      let viscosity = ToothpasteCopy.quantity(eta, unit: "Pa·s")
      let tilt = Int(Double(motion.tiltDegrees.value).rounded())
      let cells: [(String, String, String, Color, String)] = [
        (ToothpasteCopy.yieldLabel, yieldText.value, yieldText.unit, Metro.Colour.actionAmber.color,
         ToothpasteCopy.yieldSpoken(tauY, spec: yieldSpec)),
        (ToothpasteCopy.viscosityLabel, viscosity.value, viscosity.unit, Metro.Colour.displayInk.color,
         ToothpasteCopy.viscositySpoken(model.telemetry.viscosity)),
        (ToothpasteCopy.tiltLabel, "\(tilt)", "°", Metro.Colour.actionCyan.color, ToothpasteCopy.tiltSpoken(tilt)),
      ]
      Group {
        if typeSize.isAccessibilitySize {
          VStack(spacing: 10) { ForEach(0..<3, id: \.self) { cell(cells[$0]) } }
        } else {
          HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
              if i > 0 {
                Rectangle()
                  .fill(.white.opacity(Metro.Opacity.divider))
                  .frame(width: Metro.Layout.telemetryDivider.width, height: Metro.Layout.telemetryDivider.height)
                  .accessibilityHidden(true)
              }
              cell(cells[i])
            }
          }
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("telemetry")
  }

  private func cell(_ c: (String, String, String, Color, String)) -> some View {
    VStack(spacing: 5) {
      Text(c.0)
        .font(.system(.caption2, design: .monospaced))
        .tracking(Metro.Typography.telemetryLabelTracking)
        .foregroundStyle(Metro.Colour.secondaryInk.color)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(c.1)
          .font(.system(.title2, design: .rounded, weight: .medium))
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.6)
        Text(c.2)
          .font(.system(.caption, design: .monospaced))
          .lineLimit(1)
      }
      .foregroundStyle(c.3)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(c.0.capitalized)
    .accessibilityValue(c.4)
  }
}
