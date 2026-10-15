// ToothpasteScreen.swift — OWNER: UI (Documentation/REDESIGN-OWNERSHIP.md).
//
// Toothpaste Toy's one screen, in Metro Station's language (REDESIGN.md §2–§5; Metro spec §1–§12):
//
//   header        holo glyph · "Toothpaste Toy" · HOLO CHAMBER · <PASTE>          [Other pastes] [More]
//   squeeze row   SQUEEZE <requested mm/s>   (the knurled Squeeze crown = the tube's cap)   RIBBON <extruded mm>
//   cluster       the holo chamber (primary object)  |  signal rack: γ̇ σ λ pills · lens readout · event tiles
//   telemetry     YIELD τ_y │ VISCOSITY η │ TILT
//   crowns        GRAVITY (semantic, named worlds)          HEAT (fine, 1 °C)
//   floating      Refill · Freeze · SQUEEZE (hold) · Rheometer · Info        (native glass, no backing strip)
//
// The chamber takes all the height the rest leaves (measured, not guessed), at the tank's own aspect, so the tank is
// drawn as large as the Metro controls allow (×0.66 of life-size on the 15 Pro Max). At accessibility text sizes the
// controls grow, the chamber keeps a minimum size and the page scrolls; every control owns the touch that begins on it.
// Readouts and controls never move with the tilt (Metro contract 1): only light on metal and the hologram do.
//
// Every gesture has an accessible route: the chamber's named actions (poke, punch, tilt, shake, squeeze, refill), the
// crowns' ± buttons and VoiceOver adjustable actions, the press-and-hold Squeeze button (VoiceOver: a 1.5 s squeeze)
// and a hardware keyboard (arrows tilt, space pokes, S squeezes for as long as it is held… once per press, R refills,
// F freezes).
//
// UI launch arguments (pictures and layout checks): -pastes, -more, -rheometer, -info, -infoPanel <01…09>, -large,
// -banner <kind>, -lensDemo, -squeezeDemo, -quietSensors, -logFrames (see StatusFeed.swift); -snapshot, -uiTour, -ax
// (App/Snapshot.swift).

import LabKitCore
import LabKitRender
import LabKitSensors
import LabKitUI
import SwiftUI

/// The screen's sheets.
enum ScreenSheet: String, Identifiable {
  case pastes, more, rheometer, info
  var id: String { rawValue }
}

struct ToothpasteScreen: View {
  @Bindable var model: ToothpasteModel
  @State private var motion: ChamberMotion
  @State private var sheet: ScreenSheet?
  @State private var banner: ToothpasteBanner?
  @State private var bannerToken = 0
  @State private var watcher = ToothpasteStatusWatcher()
  @State private var slowMotion = false
  @State private var deniedRaisesSeen = 0
  /// Measured heights of everything but the chamber (initial values: the 15 Pro Max at the default text size).
  @State private var headerHeight: CGFloat = 66
  @State private var squeezeRowHeight: CGFloat = 74
  @State private var lowerHeight: CGFloat = 176
  @FocusState private var focused: Bool
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var typeSize

  init(model: ToothpasteModel) {
    self.model = model
    _motion = State(initialValue: ChamberMotion(model: model))
    _sheet = State(initialValue: Self.launchSheet)
  }

  private static var launchSheet: ScreenSheet? {
    if ToothpasteUIArgs.has("-pastes") { return .pastes }
    if ToothpasteUIArgs.has("-more") { return .more }
    if ToothpasteUIArgs.has("-rheometer") { return .rheometer }
    if ToothpasteUIArgs.has("-info") { return .info }
    return nil
  }

  private var material: MaterialInfo { model.catalog.material(model.materialID) }

  /// Spacing between the screen's rows.
  static let rowGap: CGFloat = 10
  static let inset: CGFloat = Metro.Spacing.screenInset
  /// The smallest chamber height before the page scrolls instead (accessibility text sizes).
  static let minimumChamberHeight: CGFloat = 300

  var body: some View {
    GeometryReader { proxy in
      let width = min(proxy.size.width, Metro.Layout.portraitContentMax)
      let chamberRoom = proxy.size.height - headerHeight - squeezeRowHeight - lowerHeight - FloatingActions.reserve
        - 3 * Self.rowGap
      let geometry = ChamberGeometry.fitting(
        tank: model.engine.tankSize, width: width - 2 * Self.inset - SignalRack.width - 6,
        height: max(chamberRoom, Self.minimumChamberHeight))
      let fits = chamberRoom >= Self.minimumChamberHeight - 0.5
      ScrollView(.vertical) {
        VStack(spacing: 0) {
          header
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
          squeezeRow(geometry)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { squeezeRowHeight = $0 }
          HStack(alignment: .top, spacing: 6) {
            chamber(geometry)
            SignalRack(model: model, motion: motion, height: geometry.size.height)
          }
          .padding(.top, Self.rowGap)
          .logFrame("cluster")
          lower
            .padding(.top, Self.rowGap)
            .padding(.bottom, Self.rowGap)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { lowerHeight = $0 }
          Color.clear.frame(height: FloatingActions.reserve)
        }
        .padding(.horizontal, Self.inset)
        .frame(width: width)
        .frame(maxWidth: .infinity)
      }
      .scrollDisabled(fits)
      .scrollBounceBehavior(.basedOnSize)
      .scrollIndicators(fits ? .hidden : .automatic)
      .overlay(alignment: .bottom) {
        FloatingActions(
          motion: motion, paused: model.paused, refill: refill, toggleFreeze: { model.paused.toggle() },
          rheometer: { sheet = .rheometer }, info: { sheet = .info }
        )
        .padding(.horizontal, 16)
        .padding(.bottom, Metro.Spacing.transportBottom)
        .frame(maxWidth: Metro.Layout.portraitContentMax)
        .logFrame("actions")
      }
    }
    .background { InstrumentDesignBackground() }
    .tint(Metro.Colour.actionCyan.color)
    .labHaptics(model.feedback.haptics)
    .focusable()
    .focused($focused)
    .focusEffectDisabled()
    .onKeyPress { key($0) ? .handled : .ignored }
    .sheet(item: $sheet) { s in sheetContent(s) }
    .onAppear {
      motion.reduceMotion = reduceMotion
      motion.onSqueezeDetent = { [model] in
        model.feedback.haptics.transient(
          intensity: Float(Metro.Haptic.fineDown.intensity), sharpness: Float(Metro.Haptic.fineDown.sharpness))
      }
      motion.start()
      if ToothpasteUIArgs.has("-lensDemo") { motion.runLensDemo() }
      if ToothpasteUIArgs.has("-squeezeDemo") { motion.runSqueezeDemo() }
    }
    .onDisappear { motion.stop() }
    .onChange(of: scenePhase, initial: true) { _, phase in
      model.setActive(phase == .active)
      if phase == .active { motion.start() } else if phase == .background { motion.stop() }
    }
    .onChange(of: reduceMotion, initial: true) { _, on in
      model.reduceMotion = on
      motion.reduceMotion = on
    }
    .onChange(of: model.recentEvents) { _, events in
      guard !events.isEmpty else { return }
      let taken = model.takeEvents()
      if taken.contains(where: Self.resetsCounts) { motion.resetEventCounts() }
      show(ToothpasteEventBanners.banner(for: taken, catalog: model.catalog))
    }
    .background { TelemetryTap(model: model) { watch($0) }.allowsHitTesting(false) }
    .task(id: bannerToken) {
      guard banner != nil else { return }
      try? await Task.sleep(for: .seconds(6.5))
      if !Task.isCancelled { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { banner = nil } }
    }
    .task {
      model.chromeBottom = 0
      if let kind = ToothpasteUIArgs.value("-banner") { show(demoBanner(kind)) }
      try? await Task.sleep(for: .milliseconds(300))
      focused = true
    }
  }

  private static func resetsCounts(_ e: SimEvent) -> Bool {
    switch e {
    case .refilled, .materialChanged, .experimentApplied: true
    default: false
    }
  }

  // MARK: Header

  private var header: some View {
    HStack(alignment: .center, spacing: 10) {
      HoloGlyph()
        .frame(width: 30, height: 24)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(ToothpasteCopy.appTitle)
          .font(.system(size: Metro.Typography.appTitle.size, weight: .semibold, design: .rounded))
          .foregroundStyle(Metro.Colour.displayInk.color)
          .lineLimit(1)
          .minimumScaleFactor(Metro.Typography.appTitleMinScale)
          .accessibilityAddTraits(.isHeader)
        Text(ToothpasteCopy.subtitle(material))
          .font(.system(size: 11, weight: .medium, design: .monospaced))
          .tracking(2.2)
          .foregroundStyle(Metro.Colour.secondaryInk.color)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .accessibilityLabel(ToothpasteCopy.subtitleSpoken(material))
      }
      .dynamicTypeSize(...DynamicTypeSize.accessibility1)
      Spacer(minLength: 4)
      GlassEffectContainer(spacing: 10) {
        HStack(spacing: 10) {
          InstrumentGlassIconButton("square.stack.3d.down.right.fill", label: ToothpasteCopy.otherPastes) {
            sheet = .pastes
          }
          .accessibilityIdentifier("header-pastes")
          InstrumentGlassIconButton("slider.horizontal.3", label: ToothpasteCopy.more) { sheet = .more }
            .accessibilityIdentifier("header-more")
        }
      }
    }
    .padding(.top, Metro.Spacing.headerTop)
    .padding(.bottom, 10)
    .padding(.horizontal, 4)
    .logFrame("header")
  }

  // MARK: Squeeze row

  private func squeezeRow(_ g: ChamberGeometry) -> some View {
    HStack(alignment: .bottom, spacing: 6) {
      ZStack(alignment: .bottom) {
        HStack(alignment: .center) {
          SqueezeRequested(model: model)
          Spacer(minLength: SqueezeCrown.diameter + 12)
          RibbonReadout(model: model)
        }
        .frame(maxHeight: .infinity)
        VStack(spacing: 0) {
          SqueezeCrown(motion: motion)
          // The tube's neck down to the chamber's housing.
          TubeNeck().frame(width: 18, height: 10)
        }
      }
      .frame(width: g.size.width)
      StatusTag(model: model, slowMotion: slowMotion)
        .frame(width: SignalRack.width, alignment: .leading)
    }
    .frame(height: SqueezeCrown.diameter + 10)
    .logFrame("squeeze-row")
  }

  // MARK: Chamber

  private func chamber(_ g: ChamberGeometry) -> some View {
    HoloChamber(
      model: model, motion: motion, geometry: g, material: material, actions: chamberActions, onTouched: {}
    )
    .overlay(alignment: .top) {
      if let banner {
        ToothpasteBannerView(banner: banner)
          .padding(.horizontal, g.region.minX + 6)
          .padding(.top, g.region.minY + 6)
          .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
          .id(bannerToken)
      }
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: bannerToken)
  }

  /// A point in the middle of the paste (for "Poke centre" and the space bar).
  private var centre: SIMD2<Double> {
    let tank = model.engine.tankSize
    return SIMD2(tank.x / 2, tank.y * max(model.telemetry.fillFraction, 0.15) * 0.6)
  }

  private var chamberActions: [CanvasRegion.Action] {
    [
      .init(ToothpasteCopy.actionPoke) { model.perform(.poke(centre)) },
      .init(ToothpasteCopy.actionSqueeze) { squeezeBurst() },
      .init(ToothpasteCopy.actionPunch) { model.perform(.punch(centre)) },
      .init(ToothpasteCopy.actionTiltLeft) { model.perform(.tilt(dx: -0.15, dy: 0)) },
      .init(ToothpasteCopy.actionTiltRight) { model.perform(.tilt(dx: 0.15, dy: 0)) },
      .init(ToothpasteCopy.actionShake) { model.perform(.shakeOnce) },
      .init(ToothpasteCopy.actionRefill) { refill() },
    ]
  }

  private func squeezeBurst() {
    motion.setSqueeze(.button)
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(1.5))
      if motion.squeezeSource == .button { motion.setSqueeze(.none) }
    }
  }

  private func refill() {
    model.refill()
    motion.resetEventCounts()
  }

  private func key(_ press: KeyPress) -> Bool {
    switch press.key {
    case .space: model.perform(.poke(centre))
    case .leftArrow: model.perform(.tilt(dx: -0.1, dy: 0))
    case .rightArrow: model.perform(.tilt(dx: 0.1, dy: 0))
    case .upArrow: model.perform(.tilt(dx: 0, dy: -0.1))
    case .downArrow: model.perform(.tilt(dx: 0, dy: 0.1))
    default:
      switch press.characters.lowercased() {
      case "r": refill()
      case "f": model.paused.toggle()
      case "s": squeezeBurst()
      default: return false
      }
    }
    return true
  }

  // MARK: Lower controls

  private var lower: some View {
    VStack(spacing: 12) {
      TelemetryStrip(model: model, motion: motion)
        .padding(.horizontal, 4)
      Group {
        if typeSize.isAccessibilitySize {
          VStack(spacing: 14) { gravityCrown; heatCrown }
        } else {
          HStack(alignment: .top, spacing: 12) { gravityCrown; heatCrown }
        }
      }
      .frame(maxWidth: Metro.Layout.controlRowMax)
      .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
    .frame(maxWidth: .infinity)
    .logFrame("lower")
  }

  private var gravityCrown: some View {
    GravityCrown(store: model.params, light: motion.light, onDetent: play) { held in
      model.heldKnobs = held ? [.gravity] : []
    }
  }

  private var heatCrown: some View {
    HeatCrown(store: model.params, light: motion.light, onDetent: play) { held in
      model.heldKnobs = held ? [.heat] : []
    }
  }

  private func play(_ d: Metro.Haptic.Detent) {
    model.feedback.haptics.transient(intensity: Float(d.intensity), sharpness: Float(d.sharpness))
  }

  // MARK: Sheets

  @ViewBuilder private func sheetContent(_ s: ScreenSheet) -> some View {
    Group {
      switch s {
      case .pastes:
        PastePicker(model: model) { id in
          model.shelfMode = .fill
          model.choose(material: id)
          motion.resetEventCounts()
          sheet = nil
        }
      case .more:
        MoreSheet(model: model) { next in sheet = next }
      case .rheometer:
        RheometerSheet(model: model)
      case .info:
        ToothpasteInfoSheet(model: model)
      }
    }
    .environment(\.dynamicTypeSize, typeSize)
    .tint(Metro.Colour.actionCyan.color)
    .preferredColorScheme(.dark)
  }

  // MARK: Banners

  private func show(_ b: ToothpasteBanner?) {
    guard let b else { return }
    if banner?.text == b.text { return }
    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
      banner = b
      bannerToken &+= 1
    }
  }

  private func watch(_ t: ToothpasteTelemetry) {
    let raises = model.feel.deniedRaises
    if raises > deniedRaisesSeen {
      deniedRaisesSeen = raises
      show(ToothpasteCopy.micDenied)
    }
    if ToothpasteUIArgs.has("-quietSensors") { return }
    let drives = model.params.spec(.drives).formatted(model.params[.drives])
    let input = ToothpasteStatusWatcher.Input(
      telemetry: t, mic: model.feel.micState, useMagnetometer: model.layers.useMagnetometer,
      material: model.materialID, drives: drives, now: ProcessInfo.processInfo.systemUptime)
    let b = watcher.update(input)
    if slowMotion != watcher.slowMotion { slowMotion = watcher.slowMotion }
    show(b)
  }

  /// `-banner <kind>`: a banner for screenshots.
  private func demoBanner(_ kind: String) -> ToothpasteBanner? {
    switch kind {
    case "simulated": ToothpasteCopy.simulatedMotion
    case "material": ToothpasteCopy.materialBanner(material)
    case "experiment": model.catalog.experiments.first.map(ToothpasteCopy.experimentBanner)
    case "micOn": ToothpasteCopy.micOnBanner(drives: model.params.spec(.drives).formatted(model.params[.drives]))
    case "micDenied": ToothpasteCopy.micDenied
    case "slowMotion": ToothpasteCopy.slowMotion
    case "magnet": ToothpasteCopy.magnetBanner(microTesla: 312, isMR: model.materialID == "mrFluid")
    default: nil
    }
  }
}

// MARK: - Small live views

/// Calls `action` with every new telemetry value (the sensor banners), without the screen observing it.
private struct TelemetryTap: View {
  let model: ToothpasteModel
  let action: (ToothpasteTelemetry) -> Void

  var body: some View {
    Color.clear
      .accessibilityHidden(true)
      .onChange(of: model.telemetry) { _, t in action(t) }
  }
}

/// The requested squeeze (Metro: the requested value shows at once).
private struct SqueezeRequested: View {
  let model: ToothpasteModel

  var body: some View {
    let rate = model.squeeze.rate
    VStack(alignment: .leading, spacing: 2) {
      Text(ToothpasteCopy.squeezeCaption)
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .tracking(1.6)
        .foregroundStyle(Metro.Colour.instrumentCyan.color)
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text("\(Int(rate.rounded()))")
          .font(.system(size: 22, weight: .medium, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(rate > 0 ? Metro.Colour.displayInk.color : Metro.Colour.secondaryInk.color)
        Text("mm/s")
          .font(.system(size: 10, weight: .medium, design: .monospaced))
          .foregroundStyle(.white.opacity(Metro.Opacity.dialMetadataInk))
      }
    }
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(ToothpasteCopy.squeezeRequestedLabel)
    .accessibilityValue(ToothpasteCopy.squeezeSpoken(rate: rate))
    .accessibilityIdentifier("squeeze-requested")
  }
}

/// What the nozzle actually did (acknowledged output, per frame snapshot, read at 10 Hz).
private struct RibbonReadout: View {
  let model: ToothpasteModel
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    TimelineView(.periodic(from: .now, by: scenePhase == .active ? 0.1 : 1)) { _ in
      let nozzle = model.live.nozzle
      let mm = Int(((nozzle?.extruded ?? 0) * 1000).rounded())
      let emitting = nozzle?.emitting ?? false
      VStack(alignment: .trailing, spacing: 2) {
        Text(ToothpasteCopy.ribbonCaption)
          .font(.system(size: 10, weight: .medium, design: .monospaced))
          .tracking(1.6)
          .foregroundStyle(emitting ? Metro.Colour.actionAmber.color : Metro.Colour.secondaryInk.color)
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text("\(mm)")
            .font(.system(size: 22, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(emitting ? Metro.Colour.displayInk.color : Metro.Colour.secondaryInk.color)
          Text("mm")
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(Metro.Opacity.dialMetadataInk))
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(ToothpasteCopy.ribbonLabel)
      .accessibilityValue(ToothpasteCopy.ribbonSpoken(millimetres: mm, emitting: emitting))
    }
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    .accessibilityIdentifier("ribbon-readout")
  }
}

/// The clock's state above the rack (Metro's status row: a dot and a word, constant height).
private struct StatusTag: View {
  let model: ToothpasteModel
  let slowMotion: Bool

  var body: some View {
    let (word, colour) = ToothpasteCopy.clockState(paused: model.paused, slowMotion: slowMotion)
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 5) {
        Circle().fill(colour).frame(width: 5, height: 5)
        Text(word)
          .font(.system(size: 10, weight: .medium, design: .monospaced))
          .tracking(1.4)
          .foregroundStyle(Metro.Colour.secondaryInk.color)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      Text(ToothpasteCopy.timeTag(model.params[.time]))
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .tracking(1.4)
        .foregroundStyle(Metro.Colour.secondaryInk.color.opacity(0.8))
        .lineLimit(1)
    }
    .padding(.bottom, 12)
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("status-tag")
  }
}

/// The tube's metal neck from the Squeeze crown down to the chamber housing.
private struct TubeNeck: View {
  var body: some View {
    LinearGradient(
      colors: [Metro.Colour.crownRimDark.color, Metro.Colour.crownRimLight.color.opacity(0.7), Metro.Colour.crownRimDark.color],
      startPoint: .leading, endPoint: .trailing)
    .clipShape(.rect(topLeadingRadius: 2, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 2))
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }
}

/// The header's mark: a striped holographic ribbon (white core, cyan and violet bands) in one squiggle.
struct HoloGlyph: View {
  var body: some View {
    Canvas { context, size in
      func ribbon(_ offset: CGFloat) -> Path {
        var p = Path()
        let w = size.width, h = size.height
        for i in 0...24 {
          let t = CGFloat(i) / 24
          let x = 2 + t * (w - 4)
          let y = h / 2 + sin(t * .pi * 2.2) * h * 0.28 + offset
          if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
      }
      context.stroke(ribbon(-3), with: .color(Metro.Colour.instrumentCyan.color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
      context.stroke(ribbon(0), with: .color(Metro.Colour.displayInk.color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
      context.stroke(ribbon(3), with: .color(Metro.Colour.spectrum.color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }
  }
}
