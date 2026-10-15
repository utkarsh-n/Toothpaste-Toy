// Interfaces.swift — OWNER: integrator (the skeleton architect). Frozen during the area waves; RHEO-FIX (8–9 October
// 2026) added `ToothpasteFeeling.deniedRaises`, the scoop tool (`ShelfMode.scoop`, `FingerState.Tool.scoop`) and
// `ToothpasteViewState.chromeBottom`. (The `-perfLog` counters are the hub's own: Model/PerfCounters.swift.)
//
// The contract between Toothpaste Toy's ownership areas (redesign: Documentation/REDESIGN-OWNERSHIP.md; the Rheo
// skeleton's four areas: Documentation/SKELETON.md):
//   UI     ToothpasteToy/App/*, UI/*, Resources/*, Design/Metro/*, Tools/make-icon.swift, the UI tests
//   HOLO   ToothpasteToy/Render/* (+ LabKitMPM's surface renderer), RenderTests  (protocol: ToothpasteTankRendering)
//   PLAY   ToothpasteToy/Model/* (except this file, ToothpasteModel.swift and PerfCounters.swift), Engine/*,
//          Feedback/* (+ LabKit's emitter/dye code), PhysTests, FeelTests  (protocols: ToothpasteSimulation,
//          ToothpasteFeeling, ToothpasteCatalog, ToothpasteSettingsStoring)
// Each area implements its protocols below with its own concrete types; `ToothpasteModel` (the hub) owns the
// shared resources and calls the areas in a fixed order every frame. Nothing here does any work.
//
// Units: SI in Double everywhere (metres, seconds, kilograms, pascals, kelvin, tesla); the one exception is
// `SqueezeState.rate` (mm/s) and `.nozzleDiameter` (mm), the crown's own units, with SI views `speed`/`nozzleRadius`.
// The tank frame has its origin at the inside bottom-left corner, x right, y up (the same frame as LabKitMPM and
// LabKitRigid).
//
// Changing anything in this file is an interface change: ask the integrator. Adding a *new* type or protocol
// that only your own area uses belongs in your own files, not here.
//
// v2 (FOUNDATION, 13 October 2026; Documentation/REDESIGN.md §8, REDESIGN-OWNERSHIP.md): the Toothpaste Toy contracts —
// `LensState`, `SqueezeState`, `NozzleState`, `SignalChannel`/`PasteChannels`, `PasteEvent`, `PasteLiveSnapshot` (end
// of this file) and the additive fields on `FrameStep` and `ToothpasteFrame`. During the redesign waves this file is
// frozen: additive changes only, announced in your report.

import CoreGraphics
import Foundation
import LabKitCore
import LabKitFeedback
import LabKitMPM
import LabKitRender
import LabKitRigid
import LabKitSensors
import LabKitShaderTypes
import Metal
import simd

// MARK: - Identifiers

/// A material's id: the `LabPalette.rheoFluids` data-hue id ("waterLike", "honey", "ketchup", "mayonnaise",
/// "toothpaste", "oobleck", "slime", "sillyPutty", "yogurt", "quicksand", "mrFluid", "paint", "lava").
typealias MaterialID = String

/// The hero and default material (REDESIGN.md §1): a fresh install, a `-noPersist` launch and an unknown saved id
/// start with toothpaste. The other twelve stay as "Other pastes".
let defaultMaterialID: MaterialID = "toothpaste"

/// Knob ids (labkit-from-orbitals-spectra.md §9.5). The raw strings match `LabPalette.rheo.parameterHues`.
extension ParamID {
  // Fluid page
  static let yield: ParamID = "yield"
  static let consistency: ParamID = "consistency"
  static let index: ParamID = "index"
  static let packing: ParamID = "packing"
  // World page
  static let gravity: ParamID = "gravity"
  static let heat: ParamID = "heat"
  static let magnet: ParamID = "magnet"
  static let time: ParamID = "time"
  // Touch page
  static let finger: ParamID = "finger"
  static let stir: ParamID = "stir"
  static let shake: ParamID = "shake"
  static let rate: ParamID = "rate"
  // Signals page
  static let listen: ParamID = "listen"
  static let drives: ParamID = "drives"
  static let gain: ParamID = "gain"
  static let band: ParamID = "band"
  // View page
  static let glow: ParamID = "glow"
  static let grain: ParamID = "grain"
  static let tracers: ParamID = "tracers"
  static let depth: ParamID = "depth"
  // Rheometer card knobs (large detent)
  static let memory: ParamID = "memory"
  static let rebuild: ParamID = "rebuild"
}

/// Positions of the Drives rotary switch (what the microphone modulates).
enum DriveTarget: Int, CaseIterable, Sendable {
  case shake = 0, gravity, stir, kicks, heat
}

/// What tapping a shelf tile does: Fill refills the tank; Pour makes the next drag pour that material in;
/// Drop shows prop tiles that drop a Box2D prop at the top centre (ARCHITECTURE.md §6); Scoop has no tiles: the next
/// drag takes fluid out under the finger (a drain in the solver).
enum ShelfMode: String, CaseIterable, Sendable, Codable {
  case fill, pour, drop, scoop
  var title: String {
    switch self {
    case .fill: "Fill"
    case .pour: "Pour"
    case .drop: "Drop"
    case .scoop: "Scoop"
    }
  }
}

/// The Drop-mode props.
enum PropKind: String, CaseIterable, Sendable, Codable {
  case steelBall, glassMarble, corkBlock, die
}

// MARK: - Catalog (PHYS provides the values; UI, RENDER and FEEL read them)

/// One shelf material. `slot` is the solver material id (index into `MPMSolver.materials` and
/// `MPMSurfaceRenderer.looks`), which equals the index in `ContinuumPresets.all`.
struct MaterialInfo: Sendable, Identifiable {
  let id: MaterialID
  let slot: Int
  /// Display name ("Oobleck", "MR fluid").
  let title: String
  /// Shelf subtitle and banner hint, ≤ 36 characters ("Thins when you shake it").
  let hint: String
  /// SF Symbol (checked against CoreGlyphs' name_availability.plist).
  let icon: String
  let material: ContinuumMaterial
  let look: FluidLook
  /// Fluid-page knobs that do something for this material; the console dims the others.
  let activeKnobs: Set<ParamID>
  /// Fraction of the tank height a Fill fills (0.45 by default).
  let fillFraction: Double
  /// Temperature of freshly filled fluid, K (lava starts at 1403.15 K).
  let fillTemperature: Double
  /// Honesty lines for the info sheet (rheology-models.md §8.2): what is real, what is tuned.
  let real: String
  let tuned: String
  let citations: [Citation]
}

/// One Drop-mode prop.
struct PropInfo: Sendable, Identifiable {
  let id: PropKind
  let title: String
  let hint: String
  let icon: String
  let shape: RigidShape
  /// Bulk density, kg/m³ (PHYS converts to areal density with the tank gap).
  let density: Double
  let friction: Double
  let restitution: Double
  /// Linear Display P3 body colour for the renderer.
  let colour: SIMD3<Float>
}

/// Static data every area reads: materials, props, knob specs and pages, experiments, flow curves.
@MainActor protocol ToothpasteCatalog: AnyObject {
  /// The 13 materials in shelf order (`ContinuumPresets.all` order).
  var materials: [MaterialInfo] { get }
  var props: [PropInfo] { get }
  /// Every knob: the 20 console knobs plus the Rheometer's card knobs.
  var specs: [ParamSpec] { get }
  /// The five console pages (Fluid, World, Touch, Signals, View), four knobs each.
  var pages: [ConsolePage] { get }
  /// Knobs on the Rheometer sheet's large detent (Memory, Rebuild).
  var cardKnobs: [ParamID] { get }
  var experiments: [Experiment] { get }
  /// Every citation the info sheet's panel 09 lists.
  var sources: [Citation] { get }
  func material(_ id: MaterialID) -> MaterialInfo
  func prop(_ kind: PropKind) -> PropInfo
  /// Modelled steady flow curve σ(γ̇) of a material at a temperature, Pa, one value per shear rate (1/s), NaN where
  /// undefined. Used by the Rheometer sheet and the info sheet.
  func flowCurve(_ id: MaterialID, shearRates: [Double], temperature: Double) -> [Double]
}

// MARK: - Launch arguments and persisted settings

/// What the process was launched with. PHYS parses it (`ToothpasteLaunch.parse` in Model/LaunchConfig.swift).
/// LabKit's own fakes (-simSway, -fakeMic, -startMic, -fakeMagnet, -fakeShake, -fakeThermal, -fakeLowPower) are
/// read by LabKitSensors directly. UI-only arguments (-page, -shelf, -rheometer, -info) are read by the UI.
struct ToothpasteLaunch: Sendable {
  /// `-material <id>`: start with this material (overrides the saved one).
  var material: MaterialID?
  /// `-experiment <id>`: apply this experiment at launch.
  var experiment: String?
  /// `-fakeTouch [poke|stir|punch]`: a scripted finger (nil = none).
  var fakeTouch: String?
  /// `-quality standard|high|bench`.
  var quality: MPMQuality
  /// Particle capacity of the solver (≥ 40 k).
  var capacity: Int
  /// `-ui-testing`: defaults, no persistence, deterministic fakes.
  var uiTesting: Bool
  /// `-noPersist` or `-ui-testing`: neither load nor save settings.
  var persist: Bool
}

/// UI state the other areas read every frame: the Layers menu's Show and Sensors sections, plus the View
/// diagnostic. (The Feel section lives in `LabFeedback`, which persists itself.)
struct ToothpasteLayers: Sendable, Equatable {
  /// Show › Stress light: light the fluid by how hard it is sheared.
  var stressLight = true
  /// Show › Dye lines.
  var dyeLines = true
  /// Show › Particles.
  var particles = false
  /// Show › Rheometer cursor (the probe ring).
  var rheometerCursor = true
  /// Sensors › Use tilt (off: gravity points straight down the screen).
  var useTilt = true
  /// Sensors › Use the magnetometer.
  var useMagnetometer = true
  /// View diagnostic colour map over the fluid (`.none` = the material's look).
  var diagnostic: FluidDiagnostic = .none
  /// v2 (HOLO, 13 October 2026): View › Solid: draw the paste as the glossy solid look instead of the quantum hologram
  /// (the default). Not persisted.
  var solid = false
}

/// What survives a relaunch (PHYS persists it; the hub loads it at init and saves it when the app goes inactive).
struct ToothpasteSettings: Sendable, Equatable {
  var material: MaterialID
  var shelfMode: ShelfMode
  var layers: ToothpasteLayers
}

@MainActor protocol ToothpasteSettingsStoring: AnyObject {
  func load() -> ToothpasteSettings?
  func save(_ settings: ToothpasteSettings)
}

// MARK: - Touch (UI → hub → PHYS)

/// One finger on the tank, already converted to tank metres by the hub.
struct TankTouch: Sendable, Equatable {
  enum Phase: Sendable, Equatable { case began, moved, ended }
  /// Stable while the finger is down (CanvasTouch.id).
  var id: Int
  var position: SIMD2<Double>
  var start: SIMD2<Double>
  var phase: Phase
  /// Seconds since boot (UITouch.timestamp).
  var timestamp: Double
}

/// A two-finger gesture on the tank: simulated tilt (Simulator) or pinch zoom.
struct TankTwoFinger: Sendable, Equatable {
  enum Phase: Sendable, Equatable { case began, changed, ended }
  var phase: Phase
  /// Centroid travel since the previous event and since the start, points (screen, y down).
  var delta: CGSize
  var translation: CGSize
  /// Finger spread relative to the start.
  var scale: Double
  /// Current centroid, tank metres.
  var anchor: SIMD2<Double>
}

/// Commands from the UI, accessibility actions and the keyboard to the simulation.
enum ToothpasteCommand: Sendable, Equatable {
  /// Refill the tank with the current material (the Refill button).
  case refill
  /// Fill-mode tile: switch to this material and refill.
  case fill(MaterialID)
  /// Pour-mode tile: the next one-finger drag pours this material in.
  case pourMaterial(MaterialID)
  /// Drop-mode tile: drop this prop at the top centre.
  case dropProp(PropKind)
  case clearProps
  /// Apply an experiment by id (`Experiment.id`): knob values, material, fill, props; restarts the clock.
  case experiment(String)
  /// A quick poke or a punch at a tank point (canvas actions, keyboard space).
  case poke(SIMD2<Double>)
  case punch(SIMD2<Double>)
  /// Simulated tilt by an angle in radians (+x tilts the bottom of the phone right), canvas actions and arrows.
  case tilt(dx: Double, dy: Double)
  /// One synthetic shake of the phone (canvas action "Shake").
  case shakeOnce
  case quality(MPMQuality)
  /// Back to defaults: material knobs, props cleared, refill.
  case resetAll
}

// MARK: - One frame (PHYS → RENDER, FEEL, UI)

/// Hub → PHYS, once per drawn frame.
struct FrameStep: Sendable {
  /// Real seconds since the last frame (FrameClock: first 1/120, then ≤ 1/15).
  var realDt: Double
  /// The ParamStore snapshot, unmodulated (PHYS applies the drives to its copy).
  var params: ParamValues
  /// Knobs the user is holding: drives skip them.
  var held: Set<ParamID>
  /// Freeze time.
  var paused: Bool
  var layers: ToothpasteLayers
  var shelfMode: ShelfMode
  /// v2: the glass lens and the tube as the UI left them (requested values; the engine acknowledges them in the frame).
  var lens: LensState = .resting
  var squeeze: SqueezeState = .idle
}

struct FingerState: Sendable, Equatable {
  enum Tool: Sendable, Equatable { case probe, pour, prop, scoop }
  /// Centre at the end of the frame, m; velocity, m/s; probe radius (the Finger knob), m.
  var position: SIMD2<Double>
  var velocity: SIMD2<Double>
  var radius: Double
  var tool: Tool
}

struct PaddleState: Sendable, Equatable {
  var position: SIMD2<Double>
  var angle: Double
  var halfLength: Double
  var radius: Double
  var angularVelocity: Double
}

struct PropState: Sendable, Equatable {
  /// `RigidBodyID.rawValue`.
  var id: Int
  var kind: PropKind
  var shape: RigidShape
  var position: SIMD2<Double>
  var angle: Double
  var velocity: SIMD2<Double>
}

struct MagnetState: Sendable, Equatable {
  /// Virtual magnet position (m), nil for a uniform field only.
  var position: SIMD2<Double>?
  /// |B| the fluid sees at its strongest, T.
  var fieldTesla: Double
}

/// The rheometer reading at the probe (finger, or the strongest-sheared region when no finger is down).
struct ProbeReading: Sendable, Equatable {
  var position: SIMD2<Double>?
  var shearRate: Double = 0
  var stress: Double = 0
  var viscosity: Double = 0
  var solidFraction: Double = 0
  /// A finger is in the fluid.
  var fingerDown = false
}

/// Discrete things that happened this frame (FEEL turns them into haptics and sound; UI may banner them).
enum SimEvent: Sendable, Equatable {
  case refilled(MaterialID)
  case materialChanged(MaterialID)
  case poke(SIMD2<Double>)
  case punch(SIMD2<Double>)
  case touchDown
  case touchUp
  case pourStarted(MaterialID)
  case propDropped(PropKind)
  /// A prop hit a wall or another prop at this approach speed (m/s).
  case propHit(speed: Double)
  case experimentApplied(String)
  case qualityChanged
}

/// Everything one simulated frame produced. Built by PHYS in `advance`, read by RENDER, FEEL and the hub.
struct ToothpasteFrame: Sendable {
  var realDt: Double
  /// Simulated seconds this frame (Time knob × real dt, ≤ 1/15; 0 while frozen).
  var simDt: Double
  /// Simulated seconds since launch or the last experiment.
  var simTime: Double
  /// The knob values after the drives (what the physics used).
  var params: ParamValues
  /// Conditioned sensor sources (shake, mic envelope and onset, field step, …).
  var sources: ModSources
  /// Tank inside size, m (the solver's actual domain).
  var tank: SIMD2<Double>
  /// Exactly what `encode(into:)` hands the solver this frame.
  var input: MPMFrameInput
  /// Latest completed solver statistics (1–2 frames old).
  var stats: MPMStats
  /// The material the tank was last filled with.
  var material: MaterialID
  var finger: FingerState?
  var paddle: PaddleState?
  var props: [PropState]
  var magnet: MagnetState?
  var probe: ProbeReading
  var events: [SimEvent]
  /// Motion comes from the simulated phone (Simulator, or a fake).
  var simulatedMotion: Bool
  /// Floor vibration actually applied: amplitude m/s², frequency Hz.
  var vibration: SIMD2<Double>

  // v2 (REDESIGN.md §8), all defaulted so older constructions still compile.
  /// The lens as the engine used it this frame (nil: inactive, no collider).
  var lens: LensState? = nil
  /// The tube's nozzle and what it did this frame (the engine fills it every frame; nil only before the first).
  var nozzle: NozzleState? = nil
  /// This frame's channels (the per-frame values the pills draw from; the hub republishes them at 10 Hz).
  var channels = PasteChannels()
  /// Paste events detected this frame (unstamped: the hub gives them ids and its clock time).
  var pasteEvents: [PasteEvent] = []

  /// A resting frame for before the first `advance`.
  static func idle(tank: SIMD2<Double>, material: MaterialID) -> ToothpasteFrame {
    ToothpasteFrame(
      realDt: 0, simDt: 0, simTime: 0, params: ParamValues(), sources: ModSources(), tank: tank,
      input: MPMFrameInput(dt: 0), stats: MPMStats(), material: material, finger: nil, paddle: nil, props: [],
      magnet: nil, probe: ProbeReading(), events: [], simulatedMotion: true, vibration: .zero)
  }
}

/// The 10 Hz readout for the top bar, the Rheometer and the canvas's accessibility value (PHYS → UI).
struct ToothpasteTelemetry: Sendable, Equatable {
  var material: MaterialID = defaultMaterialID
  /// η: the tank's mean secant viscosity of the flowing fluid, Pa·s (headline).
  var viscosity: Double = 0
  /// γ̇ and σ at the probe (subline, Rheometer cursor).
  var shearRate: Double = 0
  var stress: Double = 0
  var probeViscosity: Double = 0
  var solidFraction: Double = 0
  var fingerDown = false
  var timeScale: Double = 1
  /// Sensor rows: tilt from level (degrees), shake (g), |B| (µT), microphone level (dBFS, nil = off).
  var tiltDegrees: Double = 0
  var shakeG: Double = 0
  var fieldMicroTesla: Double = 0
  var micDBFS: Double?
  var simulatedMotion = true
  /// Solver health.
  var lagging = false
  var particles = 0
  var substeps = 0
  var gpuMilliseconds = 0.0
  var nanCount = 0
  var overflowCount = 0
  var framesPerSecond = 0.0
  /// Share of the tank height that holds fluid at rest, 0…1.
  var fillFraction = 0.0
}

// MARK: - View (hub → RENDER)

/// Maps between the canvas region (points, origin top-left, y down) and the tank (metres, origin bottom-left,
/// y up). Life-size when the device's millimetres-per-point are known and the tank fits; otherwise the tank is
/// fitted (contain). The tank floor sits on the region's bottom edge (the console's top edge); spare height is
/// headspace at the top. Zoom shrinks the world rectangle around `zoomCentre`.
struct TankView: Sendable, Equatable {
  var tankSize: SIMD2<Double>
  var regionSize: CGSize
  /// Metres per point of this display (nil: unknown device).
  var metresPerPoint: Double?
  /// 1…4.
  var zoom: Double = 1
  /// Tank metres the zoom closes in on.
  var zoomCentre: SIMD2<Double>?

  /// Metres per point at zoom 1: life-size when it fits, else the contain fit.
  var baseMetresPerPoint: Double {
    let w = max(Double(regionSize.width), 1), h = max(Double(regionSize.height), 1)
    let fit = max(tankSize.x / w, tankSize.y / h)
    if let m = metresPerPoint, tankSize.x <= w * m * 1.0005, tankSize.y <= h * m * 1.0005 { return m }
    return fit
  }

  /// Drawn size over real size: 1 = life-size (the "LIFE-SIZE" tag), else "×0.69" or "×2".
  var displayScale: Double {
    guard let m = metresPerPoint else { return zoom }
    return m / baseMetresPerPoint * zoom
  }
  var isLifeSize: Bool { metresPerPoint != nil && abs(displayScale - 1) < 0.005 }

  /// The tank-metre rectangle shown in the region (same aspect as the region).
  var worldRect: CGRect {
    let s = baseMetresPerPoint
    let w = Double(regionSize.width) * s, h = Double(regionSize.height) * s
    guard w > 0, h > 0 else { return CGRect(x: 0, y: 0, width: tankSize.x, height: tankSize.y) }
    // Zoom 1: centred horizontally on the tank, floor on the region's bottom edge.
    var rect = CGRect(x: (tankSize.x - w) / 2, y: 0, width: w, height: h)
    let z = min(max(zoom, 1), 4)
    if z > 1 {
      let c = zoomCentre ?? SIMD2(tankSize.x / 2, tankSize.y / 2)
      let zw = w / z, zh = h / z
      let x = min(max(c.x - zw / 2, rect.minX), rect.maxX - zw)
      let y = min(max(c.y - zh / 2, rect.minY), rect.maxY - zh)
      rect = CGRect(x: x, y: y, width: zw, height: zh)
    }
    return rect
  }

  /// Region-local point → tank metres.
  func tankPoint(_ p: CGPoint) -> SIMD2<Double> {
    let r = worldRect
    let w = max(Double(regionSize.width), 1), h = max(Double(regionSize.height), 1)
    return SIMD2(Double(r.minX) + Double(p.x) / w * Double(r.width), Double(r.maxY) - Double(p.y) / h * Double(r.height))
  }

  /// Tank metres → region-local point.
  func regionPoint(_ m: SIMD2<Double>) -> CGPoint {
    let r = worldRect
    guard r.width > 0, r.height > 0 else { return .zero }
    return CGPoint(
      x: (m.x - Double(r.minX)) / Double(r.width) * Double(regionSize.width),
      y: (Double(r.maxY) - m.y) / Double(r.height) * Double(regionSize.height))
  }

  /// Points per metre on screen (for sizing overlays in points).
  var pointsPerMetre: Double { 1 / max(baseMetresPerPoint / min(max(zoom, 1), 4), 1e-12) }
}

/// Everything the renderer needs that is not simulation state.
struct ToothpasteViewState: Sendable, Equatable {
  var tankView: TankView
  var layers: ToothpasteLayers
  var reduceMotion: Bool
  var paused: Bool
  /// How far down the canvas region (points from its top) the top chrome reaches (the top bar, or the shelf when it is
  /// open): drawn labels such as the ruler's numerals stay below it. 0 = nothing covers the stage.
  var chromeBottom: CGFloat = 0
}

// MARK: - The four areas

/// PHYS: sensors → drives → body forces, colliders, emitters → solver and Box2D → readings.
/// Owns no resources: the hub passes it the shared ones (`ToothpasteResources`) at init.
@MainActor protocol ToothpasteSimulation: AnyObject {
  /// Tank inside size, m (the solver's actual domain).
  var tankSize: SIMD2<Double> { get }
  /// The material the tank was last filled with.
  var currentMaterial: MaterialID { get }
  /// The material Pour mode pours.
  var pourMaterial: MaterialID { get }
  /// Lifecycle (scenePhase): sensors on and off. The mic belongs to FEEL's permission flow.
  func start()
  func stop()
  /// One frame. The only place simulated time moves.
  func advance(_ step: FrameStep) -> ToothpasteFrame
  /// Encodes the solver substeps for the frame `advance` just built (first thing in `encodeCompute`).
  func encode(into cmd: MTLCommandBuffer)
  func touches(_ touches: [TankTouch])
  func twoFinger(_ gesture: TankTwoFinger)
  func perform(_ command: ToothpasteCommand)
  /// The 10 Hz readout.
  func telemetry(frame: ToothpasteFrame, framesPerSecond: Double) -> ToothpasteTelemetry
}

/// RENDER: draws the tank. Called from the hub's `LabRenderScene` methods in LabKit's frame order.
@MainActor protocol ToothpasteTankRendering: AnyObject {
  /// Whether LabKit draws its own backdrop (Gyre's sky) before `encodeBehind`; false = RENDER draws the stage itself.
  var drawsBackdrop: Bool { get }
  /// App fields of the shared frame uniforms (LabRenderScene.fillUniforms), before any pass.
  func fillUniforms(_ u: inout LabFrameUniforms, frame: ToothpasteFrame, view: ToothpasteViewState)
  /// After `ToothpasteSimulation.encode`: the fluid's half-resolution prepass (and any other offscreen work).
  func encodeCompute(_ cmd: MTLCommandBuffer, context: LabFrameContext, frame: ToothpasteFrame, view: ToothpasteViewState)
  /// Opaque layer before the `behind` copy: tank back wall, props behind the fluid.
  func encodeBehind(
    _ enc: MTLRenderCommandEncoder, uniforms: inout LabFrameUniforms, context: LabFrameContext, frame: ToothpasteFrame,
    view: ToothpasteViewState)
  /// After the copy: fluid shade (samples `context.targets.behind`), props in front, glass, overlays.
  func encodeScene(
    _ enc: MTLRenderCommandEncoder, uniforms: inout LabFrameUniforms, context: LabFrameContext, frame: ToothpasteFrame,
    view: ToothpasteViewState)
  /// Glowing overlay lines (drawn additively after `encodeScene`).
  func buildLines(_ batch: inout LineBatch, context: LabFrameContext, frame: ToothpasteFrame, view: ToothpasteViewState)
  /// v2 (HOLO): whether LabKit copies the scene into `behind` before `encodeScene` (default true; see the extension).
  var wantsBehindCopy: Bool { get }
}

extension ToothpasteTankRendering {
  /// v2 (HOLO, 13 October 2026; REDESIGN.md §11): whether LabKit splits the scene pass around a mipmapped `behind` copy
  /// that `encodeScene` samples. The default keeps v1's behaviour (always); the hologram draws light over the chamber
  /// and needs none, so `TankRenderer` asks for it only for the Solid look. The hub reads it before each frame.
  var wantsBehindCopy: Bool { true }
}

/// FEEL: haptics (hum + transients), the gloop sound bed and cues, and the microphone permission flow.
@MainActor protocol ToothpasteFeeling: AnyObject {
  /// scenePhase == .active (starts/stops haptics, synth; LabFeedback.setActive).
  func setActive(_ active: Bool)
  func setPaused(_ paused: Bool)
  /// Once per frame after the simulation: hum, events, bed, mic just-in-time permission.
  func update(frame: ToothpasteFrame, dt: Double)
  /// The microphone's state for the info sheet's PermissionGate and the telemetry row.
  var micState: MicState { get }
  /// How many times the microphone was found refused with Listen up: a raise of Listen while it is refused, or a refusal
  /// at iOS's prompt while Listen is up (the UI shows the PermissionGate each time).
  var deniedRaises: Int { get }
  /// Ask for the microphone now (the first raise of Listen, or the mic toggle).
  func requestMicrophone()
}

/// The resources the hub owns and lends to the areas (ARCHITECTURE.md §6: ToothpasteModel owns ParamStore, the sensors,
/// the feedback, the MPM solver and surface renderer, and the Box2D world).
@MainActor final class ToothpasteResources {
  let device: MTLDevice?
  let params: ParamStore
  let motion: MotionSource
  let mic: MicListener
  let thermal: ThermalSource
  /// Haptics, the synth bed (FEEL's `GloopKernel`) and cues; persists Haptics, Strength, Feel and Sound.
  let feedback: LabFeedback
  let solver: MPMSolver?
  let surface: MPMSurfaceRenderer?
  let rigid: RigidWorld
  let catalog: any ToothpasteCatalog
  let launch: ToothpasteLaunch

  init(
    device: MTLDevice?, params: ParamStore, motion: MotionSource, mic: MicListener, thermal: ThermalSource,
    feedback: LabFeedback, solver: MPMSolver?, surface: MPMSurfaceRenderer?, rigid: RigidWorld,
    catalog: any ToothpasteCatalog, launch: ToothpasteLaunch
  ) {
    self.device = device
    self.params = params
    self.motion = motion
    self.mic = mic
    self.thermal = thermal
    self.feedback = feedback
    self.solver = solver
    self.surface = surface
    self.rigid = rigid
    self.catalog = catalog
    self.launch = launch
  }
}

// MARK: - v2: Toothpaste Toy (REDESIGN.md §8) — FOUNDATION, 13 October 2026

/// The glass lens (REDESIGN.md §3): Metro's isolated clear lens is the player's finger. The UI's lens control and canvas
/// drags write it to the hub (`ToothpasteModel.lens`, or `moveLens(to:active:timestamp:)` from region points); the
/// engine reads it every frame (`FrameStep.lens`) as a kinematic circular probe collider, in addition to a canvas finger,
/// and samples the rheometer at its leading edge; the renderer refracts the hologram under it (`ToothpasteFrame.lens`).
/// Tank metres, origin at the inside bottom-left, y up.
struct LensState: Sendable, Equatable {
  /// Centre, m.
  var centre: SIMD2<Double>
  /// Radius of the glass disc (collider and refraction), m.
  var radius: Double
  /// In the chamber and pushing paste. An inactive lens adds no collider (the UI may still draw it parked).
  var active: Bool
  /// m/s, written with the centre (the engine moves the collider through the frame with it and ends at `centre`).
  var velocity: SIMD2<Double>

  /// 6 mm: a fingertip-sized disc (12 mm across, 6 cells at Δx 2 mm).
  static let defaultRadius = 0.006
  /// Fastest lens the engine follows, m/s (a faster write is clamped: a jump, not a punch through the paste).
  static let maxSpeed = 2.0
  /// Parked, inactive, at the chamber's centre.
  static let resting = LensState(
    centre: SIMD2(MPMDomain.lifeSizeTank.x / 2, MPMDomain.lifeSizeTank.y / 2), radius: defaultRadius, active: false,
    velocity: .zero)
}

/// The tube (REDESIGN.md §4–§5): the Squeeze crown and the press-and-hold Squeeze button write it to the hub
/// (`ToothpasteModel.squeeze`, requested values). The engine turns a positive rate into an emitter at the nozzle (top
/// centre of the chamber, pointing down) with `stripes` dye bands, and tears the ribbon off at the nozzle when the rate
/// returns to 0 (a `PasteEvent.Kind.tearOff`). The hub keeps `material` in step with a Fill; the UI may change it.
struct SqueezeState: Sendable, Equatable {
  /// Extrusion speed of the paste leaving the nozzle, mm/s (≥ 0; 0 = not squeezing).
  var rate: Double
  /// Nozzle bore, mm.
  var nozzleDiameter: Double
  /// Dye bands across the nozzle: 0 = plain, 1…`maxStripes` (toothpaste's three stripes: 3).
  var stripes: Int
  /// The paste in the tube.
  var material: MaterialID

  var isSqueezing: Bool { rate > 0 }
  /// SI views for the engine: extrusion speed, m/s, and bore radius, m.
  var speed: Double { max(rate, 0) * 1e-3 }
  var nozzleRadius: Double { max(nozzleDiameter, 0) * 0.5e-3 }

  /// 8 mm: a toothpaste tube's bore (6–9 mm; 4 cells at Δx 2 mm).
  static let defaultNozzleDiameter = 8.0
  static let nozzleDiameterRange: ClosedRange<Double> = 4...12
  /// Fastest squeeze, mm/s.
  static let maxRate = 80.0
  static let maxStripes = MPMEmitter.maxStripes
  /// Not squeezing; a striped toothpaste tube.
  static let idle = SqueezeState(rate: 0, nozzleDiameter: defaultNozzleDiameter, stripes: 3, material: defaultMaterialID)
}

/// The nozzle as the engine placed and drove it this frame (engine → renderer and UI; `ToothpasteFrame.nozzle`).
struct NozzleState: Sendable, Equatable {
  /// Centre of the bore's mouth, m (top centre of the chamber).
  var position: SIMD2<Double>
  /// Bore radius, m.
  var radius: Double
  /// Paste left the nozzle this frame (squeezing and time running).
  var emitting: Bool
  /// Extrusion speed, m/s (along −y).
  var speed: Double
  var stripes: Int
  var material: MaterialID
  /// Ribbon length extruded since the squeeze began, m (0 when not squeezing).
  var extruded: Double
}

/// One signal channel for a vertical pill (REDESIGN.md §4; Metro §11): the SI value and a 0…1 level for drawing.
struct SignalChannel: Sendable, Equatable {
  /// SI value: 1/s (shear rate), Pa (stress), dimensionless 0…1 (structure).
  var value: Double = 0
  /// 0…1: the pill's interior energy (`PasteChannels` documents each mapping).
  var level: Double = 0
}

/// What the probe says the paste is doing (the lens readout's state word; the UI words it).
enum PasteStateWord: String, Sendable, Equatable, CaseIterable {
  /// Unyielded: holds its shape.
  case holding
  /// Partly yielded at the probe.
  case yielding
  /// Yielded: flows like a liquid.
  case flowing
  /// Shear-thickened solid (oobleck).
  case jammed
}

/// The three channels (REDESIGN.md §4, §8): cyan shear γ̇, amber stress σ, violet structure λ / jam. Measured at the
/// probe (the lens or finger's leading edge, else the strongest-sheared region), from the solver statistics.
struct PasteChannels: Sendable, Equatable {
  /// Shear rate γ̇ at the probe, 1/s; level = log-decades over `shearRange`.
  var shear = SignalChannel()
  /// Equivalent shear stress σ at the probe, Pa; level = log-decades over `stressRange`.
  var stress = SignalChannel()
  /// Structure: the mean thixotropic λ of the paste (0…1), or the jammed share for a shear-thickening paste; level =
  /// value.
  var structure = SignalChannel()
  /// Shares of the paste that are yielded (flowing) and jammed, 0…1.
  var yieldedFraction = 0.0
  var jammedFraction = 0.0
  var state: PasteStateWord = .holding
  /// Simulated seconds of the frame they describe.
  var simTime = 0.0

  /// The pills' log scales (SI).
  static let shearRange: ClosedRange<Double> = 0.01...1000
  static let stressRange: ClosedRange<Double> = 1...10_000

  /// log10(v) placed in `range` as 0…1 (0 at or below the floor, also for v ≤ 0 or NaN).
  static func logLevel(_ v: Double, in range: ClosedRange<Double>) -> Double {
    guard v.isFinite, v > range.lowerBound else { return 0 }
    let t = (log10(v) - log10(range.lowerBound)) / (log10(range.upperBound) - log10(range.lowerBound))
    return min(max(t, 0), 1)
  }
}

/// One discrete event for the event tiles, the lens bounce and feedback (REDESIGN.md §4, §8): amber attack/decay.
struct PasteEvent: Sendable, Equatable, Identifiable {
  enum Kind: String, Sendable, Equatable, CaseIterable {
    /// The paste at the probe gave way (holding → flowing).
    case yield
    /// The paste jammed solid (a shear-thickening paste under a fast push).
    case jam
    /// The ribbon tore off at the nozzle when the squeeze stopped.
    case tearOff
    /// Something struck the paste or the chamber (a prop, a punch).
    case impact
  }
  /// Increasing id the hub assigns (0 until stamped).
  var id: Int = 0
  var kind: Kind
  /// Simulated seconds when it happened (`ToothpasteFrame.simTime`).
  var simTime: Double
  /// Real seconds on the hub's clock (0 until stamped).
  var time: Double = 0
  /// Where, m (tank frame); nil when not local.
  var position: SIMD2<Double>?
  /// Size in the kind's SI unit: yield and jam — stress at the probe, Pa; tearOff — ribbon length extruded, m;
  /// impact — approach speed, m/s.
  var magnitude: Double
}

/// The per-frame drawing snapshot (REDESIGN.md §8): written once per frame by the hub on the main actor
/// (`ToothpasteModel.live`, not observed), read by the UI's TimelineView/Canvas drawing at its own cadence. No lock is
/// needed (one actor) and SwiftUI is not invalidated at 120 Hz; the observed 10 Hz values are `ToothpasteModel.channels`
/// and `.events`.
struct PasteLiveSnapshot: Sendable, Equatable {
  /// The hub's frame counter (increments every `advance`).
  var frameIndex = 0
  /// Real seconds on the hub's clock and simulated seconds of the frame.
  var time = 0.0
  var simTime = 0.0
  var channels = PasteChannels()
  /// The lens as the hub holds it now (requested) and the nozzle as the engine drove it.
  var lens = LensState.resting
  var squeeze = SqueezeState.idle
  var nozzle: NozzleState?
  /// The newest stamped events (≤ `recentLimit`), oldest first.
  var recentEvents: [PasteEvent] = []

  static let recentLimit = 8
}
