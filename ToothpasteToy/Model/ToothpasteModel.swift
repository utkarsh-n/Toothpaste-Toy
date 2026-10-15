// ToothpasteModel.swift — OWNER: integrator (the skeleton architect). Frozen during the area waves; RHEO-FIX (8 October
// 2026) added `chromeBottom` (the UI's measured top chrome, for the renderer) and the `-perfLog` recorder hook.
//
// The hub. It owns the shared resources (ParamStore, sensors, feedback, MPM solver and surface renderer, Box2D
// world), conforms to LabRenderScene, and calls the four areas in a fixed order. It holds no behaviour of its own:
// physics is PHYS's `ToothpasteEngine`, drawing is RENDER's `TankRenderer`, feel is FEEL's `ToothpasteFeel`, the screen is
// UI's `ToothpasteScreen`. The render loop owns time: LabRenderer calls `advance(dt:)` once per drawn frame.
//
// Frame order (LabKit): advance → buildLines → fillUniforms → encodeCompute → pass 1 (backdrop, encodeBehind) →
// behind copy + mipmaps → pass 2 (encodeScene, lines) → bloom → EDR composite.
//
// v2 (FOUNDATION, 13 October 2026; REDESIGN.md §8): the hub also carries the glass lens (`lens`, `moveLens`), the tube
// (`squeeze`), the three channels (`channels`, 10 Hz) and the paste-event feed (`events`, 10 Hz, stamped with the hub's
// clock), plus the unobserved per-frame drawing snapshot `live`. Frozen during the redesign waves: additive only.

import CoreGraphics
import Foundation
import QuartzCore
import LabKitCore
import LabKitFeedback
import LabKitMPM
import LabKitRender
import LabKitRigid
import LabKitSensors
import LabKitShaderTypes
import LabKitUI
import Metal
import Observation
import simd

@MainActor @Observable
final class ToothpasteModel: LabRenderScene {
  // MARK: Owned resources

  /// The knob values (the only parameter state SwiftUI observes).
  let params: ParamStore
  /// Haptics, sound bed and cues (FeedbackSettings and the Layers menu bind to it).
  let feedback: LabFeedback
  @ObservationIgnored let resources: ToothpasteResources
  @ObservationIgnored let catalog: any ToothpasteCatalog
  @ObservationIgnored let launch: ToothpasteLaunch

  // MARK: Areas

  @ObservationIgnored let engine: any ToothpasteSimulation
  @ObservationIgnored let tank: any ToothpasteTankRendering
  @ObservationIgnored let feel: any ToothpasteFeeling
  @ObservationIgnored private let settingsStore: any ToothpasteSettingsStoring

  // MARK: Observed state (UI)

  /// 10 Hz readout.
  private(set) var telemetry = ToothpasteTelemetry()
  /// The material in the tank (Fill target); mirrors `engine.currentMaterial`.
  private(set) var materialID: MaterialID
  /// The material Pour mode pours; mirrors `engine.pourMaterial`.
  private(set) var pourMaterialID: MaterialID
  var shelfMode: ShelfMode = .fill
  var layers = ToothpasteLayers()
  /// Freeze time (knobs, haptics transients and the UI keep working).
  var paused = false {
    didSet { feel.setPaused(paused) }
  }
  /// Pinch zoom, 1…4 (illustrative).
  var zoom = 1.0
  /// Events of the latest frames, for UI banners (cleared by the UI with `takeEvents()`).
  private(set) var recentEvents: [SimEvent] = []
  private(set) var isRunning = false

  // MARK: v2 state (REDESIGN.md §8)

  /// The glass lens, tank metres (written by the UI's lens control and canvas drags; read by the engine every frame).
  /// Not observed: it changes at the touch rate.
  @ObservationIgnored var lens = LensState.resting
  /// The tube (requested values, written by the Squeeze crown and button; the engine acknowledges them in
  /// `latestFrame.nozzle` and `live.nozzle`). A Fill puts the new material in the tube.
  var squeeze = SqueezeState.idle
  /// 10 Hz: shear, stress and structure for the pills and the telemetry row.
  private(set) var channels = PasteChannels()
  /// 10 Hz: the newest paste events (≤ `eventLimit`), oldest first, ids increasing.
  private(set) var events: [PasteEvent] = []
  /// Per frame, not observed: the drawing snapshot for TimelineView/Canvas readers.
  @ObservationIgnored private(set) var live = PasteLiveSnapshot()

  var shearChannel: SignalChannel { channels.shear }
  var stressChannel: SignalChannel { channels.stress }
  var structureChannel: SignalChannel { channels.structure }
  static let eventLimit = 32

  // MARK: LabRenderScene

  @ObservationIgnored var reduceMotion = false
  /// The tank region's global frame (CanvasRegion onFrame).
  @ObservationIgnored var canvasRegion: CGRect = .zero
  /// Knobs the user is holding (from the console's KnobFocus); drives skip them.
  @ObservationIgnored var heldKnobs: Set<ParamID> = []
  /// How far down the canvas region the top chrome reaches, points (the UI measures it; ToothpasteViewState.chromeBottom).
  @ObservationIgnored var chromeBottom: CGFloat = 0
  @ObservationIgnored private var frame: ToothpasteFrame
  @ObservationIgnored private var zoomCentre: SIMD2<Double>?
  @ObservationIgnored private var pinchStartZoom = 1.0
  @ObservationIgnored private var telemetryGate = Throttle(hz: 10)
  @ObservationIgnored private var clock = 0.0
  @ObservationIgnored private var fps = 0.0
  @ObservationIgnored private var pendingEvents: [SimEvent] = []
  @ObservationIgnored private var pendingPaste: [PasteEvent] = []
  @ObservationIgnored private var pasteSerial = 0
  @ObservationIgnored private var frameCounter = 0
  /// The last lens write from `moveLens` (position, timestamp) for its velocity estimate.
  @ObservationIgnored private var lensSample: (position: SIMD2<Double>, timestamp: Double)?
  /// Per-frame counters for `-perfLog` (App/PerfLog.swift reads and resets them once a second).
  @ObservationIgnored var perf = ToothpastePerfCounters()

  /// `device` nil: no GPU (the engine and renderer degrade to no-ops). Tests pass their own launch options.
  init(launch: ToothpasteLaunch = .current, device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
    self.launch = launch
    let catalog = ToothpasteCatalogData()
    self.catalog = catalog
    let params = ParamStore(catalog.specs)
    self.params = params
    let feedback = LabFeedback(appName: "ToothpasteToy", kernel: GloopKernel())
    self.feedback = feedback
    var solver: MPMSolver?
    var surface: MPMSurfaceRenderer?
    if let device {
      solver = try? MPMSolver(device: device, domain: MPMDomain(), quality: launch.quality, capacity: launch.capacity)
      surface = try? MPMSurfaceRenderer(device: device)
    }
    let tankSize = solver?.domain.size ?? MPMDomain.lifeSizeTank
    let rigid = RigidWorld(gravity: SIMD2(0, -Gravity.g0))
    rigid.addWalls(width: tankSize.x, height: tankSize.y, thickness: 0.01)
    let resources = ToothpasteResources(
      device: device, params: params, motion: MotionSource(), mic: MicListener(), thermal: ThermalSource(),
      feedback: feedback, solver: solver, surface: surface, rigid: rigid, catalog: catalog, launch: launch)
    self.resources = resources
    let store = ToothpastePersistence(enabled: launch.persist)
    settingsStore = store
    let saved = store.load()
    let engine = ToothpasteEngine(resources: resources, initialMaterial: launch.material ?? saved?.material)
    self.engine = engine
    tank = TankRenderer(resources: resources)
    feel = ToothpasteFeel(resources: resources)
    materialID = engine.currentMaterial
    pourMaterialID = engine.pourMaterial
    frame = .idle(tank: tankSize, material: engine.currentMaterial)
    if let saved {
      shelfMode = saved.shelfMode
      layers = saved.layers
    }
    if let id = launch.experiment { perform(.experiment(id)) }
  }

  // MARK: Lifecycle

  /// scenePhase: `.active` starts sensors, haptics and sound; anything else stops them and saves settings.
  func setActive(_ active: Bool) {
    if active {
      guard !isRunning else { return }
      engine.start()
      feel.setActive(true)
      isRunning = true
    } else {
      engine.stop()
      feel.setActive(false)
      isRunning = false
      settingsStore.save(ToothpasteSettings(material: materialID, shelfMode: shelfMode, layers: layers))
    }
  }

  // MARK: Commands (UI → PHYS)

  func perform(_ command: ToothpasteCommand) {
    let before = engine.currentMaterial
    engine.perform(command)
    materialID = engine.currentMaterial
    pourMaterialID = engine.pourMaterial
    if materialID != before { squeeze.material = materialID }
  }

  func refill() { perform(.refill) }

  /// A shelf tile: what it does depends on the shelf mode.
  func choose(material id: MaterialID) {
    switch shelfMode {
    case .fill, .drop, .scoop: perform(.fill(id))
    case .pour: perform(.pourMaterial(id))
    }
  }

  func drop(_ prop: PropKind) { perform(.dropProp(prop)) }

  func apply(_ experiment: Experiment) { perform(.experiment(experiment.id)) }

  /// Resets the knobs of one console page to the current material's defaults.
  func resetPage(_ page: ConsolePage) { params.reset(page.knobs) }

  /// The UI drains banner-worthy events (material changes, experiments) at its own pace.
  func takeEvents() -> [SimEvent] {
    defer { recentEvents = [] }
    return recentEvents
  }

  // MARK: Touch (UI → PHYS)

  var tankView: TankView {
    TankView(
      tankSize: engine.tankSize, regionSize: canvasRegion.size,
      metresPerPoint: LabDisplay.currentMillimetresPerPoint.map { $0 / 1000 }, zoom: zoom, zoomCentre: zoomCentre)
  }

  func touch(_ t: CanvasTouches) {
    let view = tankView
    let mapped = t.touches.compactMap { c -> TankTouch? in
      let phase: TankTouch.Phase
      switch c.phase {
      case .began: phase = .began
      case .moved, .stationary: phase = .moved
      case .ended, .cancelled: phase = .ended
      }
      return TankTouch(
        id: c.id, position: view.tankPoint(c.location), start: view.tankPoint(c.start), phase: phase,
        timestamp: c.timestamp)
    }
    // A second finger turns the gesture into a two-finger one: the probe lifts.
    if t.active.count >= 2 {
      engine.touches(mapped.map { var m = $0; m.phase = .ended; return m })
    } else {
      engine.touches(mapped)
    }
  }

  /// v2: moves the glass lens to a canvas-region point (points, origin top-left), as a drag on the canvas or the lens
  /// control does. `timestamp`: seconds since boot (UITouch.timestamp or CACurrentMediaTime); the velocity is estimated
  /// from successive calls and clamped to `LensState.maxSpeed`. `active: false` parks the lens (no collider) where it is.
  func moveLens(to regionPoint: CGPoint, active: Bool, timestamp: Double) {
    let p = tankView.tankPoint(regionPoint)
    let size = engine.tankSize
    let r = lens.radius
    let centre = SIMD2(min(max(p.x, r), size.x - r), min(max(p.y, r), size.y - r))
    var v = SIMD2<Double>.zero
    if active, let last = lensSample, timestamp > last.timestamp {
      v = (centre - last.position) / (timestamp - last.timestamp)
      let speed = simd_length(v)
      if speed > LensState.maxSpeed { v *= LensState.maxSpeed / speed }
      v = lens.active ? lens.velocity + (v - lens.velocity) * 0.5 : v
    }
    lensSample = active ? (centre, timestamp) : nil
    lens = LensState(centre: centre, radius: r, active: active, velocity: v)
  }

  func twoFinger(_ g: CanvasTwoFinger) {
    let view = tankView
    let anchor = view.tankPoint(g.anchor)
    let phase: TankTwoFinger.Phase
    switch g.phase {
    case .began:
      phase = .began
      pinchStartZoom = zoom
    case .changed: phase = .changed
    case .ended: phase = .ended
    }
    // Pinch: zoom 1…4 around the pinch (only once the spread clearly changed, so a two-finger tilt stays a tilt).
    if abs(g.scale - 1) > 0.08 {
      zoom = min(max(pinchStartZoom * g.scale, 1), 4)
      zoomCentre = zoom > 1 ? anchor : nil
    }
    engine.twoFinger(
      TankTwoFinger(phase: phase, delta: g.delta, translation: g.translation, scale: g.scale, anchor: anchor))
  }

  // MARK: LabRenderScene

  var projection: LabProjection { .orthographicRect(tankView.worldRect, fit: .stretch) }
  /// v2 (HOLO, REDESIGN.md §11): the renderer decides (the hologram needs no `behind` copy; the Solid look does).
  var wantsBehindCopy: Bool { tank.wantsBehindCopy }
  var drawsBackdrop: Bool { tank.drawsBackdrop }

  func fillUniforms(_ u: inout LabFrameUniforms) {
    tank.fillUniforms(&u, frame: frame, view: viewState)
  }

  private var viewState: ToothpasteViewState {
    ToothpasteViewState(
      tankView: tankView, layers: layers, reduceMotion: reduceMotion, paused: paused, chromeBottom: chromeBottom)
  }

  func advance(dt: Double) {
    clock += dt
    let started = perf.enabled ? CACurrentMediaTime() : 0
    let step = FrameStep(
      realDt: dt, params: params.snapshot(), held: heldKnobs, paused: paused, layers: layers, shelfMode: shelfMode,
      lens: lens, squeeze: squeeze)
    let f = engine.advance(step)
    frame = f
    publishLive(f)
    if perf.enabled { perf.frame(f, realDt: dt, cpuSeconds: CACurrentMediaTime() - started) }
    feel.update(frame: f, dt: dt)
    if dt > 0 { fps += (1 / dt - fps) * 0.1 }
    pendingEvents.append(contentsOf: f.events.filter(Self.isBannerEvent))
    if telemetryGate.ready(at: clock) {
      telemetry = engine.telemetry(frame: f, framesPerSecond: fps)
      if materialID != engine.currentMaterial { materialID = engine.currentMaterial }
      if pourMaterialID != engine.pourMaterial { pourMaterialID = engine.pourMaterial }
      if !pendingEvents.isEmpty {
        recentEvents.append(contentsOf: pendingEvents)
        pendingEvents.removeAll()
      }
      if channels != f.channels { channels = f.channels }
      if !pendingPaste.isEmpty {
        events = Array((events + pendingPaste).suffix(Self.eventLimit))
        pendingPaste.removeAll()
      }
    }
  }

  /// v2: stamps the frame's paste events (id, hub clock) and refreshes the per-frame drawing snapshot.
  private func publishLive(_ f: ToothpasteFrame) {
    frameCounter += 1
    var recent = live.recentEvents
    for var e in f.pasteEvents {
      pasteSerial += 1
      e.id = pasteSerial
      e.time = clock
      pendingPaste.append(e)
      recent.append(e)
    }
    live = PasteLiveSnapshot(
      frameIndex: frameCounter, time: clock, simTime: f.simTime, channels: f.channels, lens: lens, squeeze: squeeze,
      nozzle: f.nozzle, recentEvents: Array(recent.suffix(PasteLiveSnapshot.recentLimit)))
  }

  private static func isBannerEvent(_ e: SimEvent) -> Bool {
    switch e {
    case .materialChanged, .experimentApplied, .propDropped, .qualityChanged: true
    default: false
    }
  }

  func encodeCompute(_ cmd: MTLCommandBuffer, context: LabFrameContext) {
    engine.encode(into: cmd)
    tank.encodeCompute(cmd, context: context, frame: frame, view: viewState)
  }

  func encodeBehind(_ enc: MTLRenderCommandEncoder, uniforms: inout LabFrameUniforms, context: LabFrameContext) {
    tank.encodeBehind(enc, uniforms: &uniforms, context: context, frame: frame, view: viewState)
  }

  func encodeScene(_ enc: MTLRenderCommandEncoder, uniforms: inout LabFrameUniforms, context: LabFrameContext) {
    tank.encodeScene(enc, uniforms: &uniforms, context: context, frame: frame, view: viewState)
  }

  func buildLines(_ batch: inout LineBatch, context: LabFrameContext) {
    tank.buildLines(&batch, context: context, frame: frame, view: viewState)
  }

  // MARK: Read-only views for tests and the UI

  /// The latest frame (tests, diagnostics).
  var latestFrame: ToothpasteFrame { frame }
}
