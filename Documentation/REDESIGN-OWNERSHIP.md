# Toothpaste Toy: redesign ownership (v2)

Date: 13 October 2026. Written by FOUNDATION (the integrator for this stage). Status: **binding for the next stage**,
in which three areas (UI, HOLO, PLAY) work in parallel on the redesign of `REDESIGN.md`. Read `REDESIGN.md` first; this
file says who owns which file, what is frozen and what the v2 contracts are, in exact Swift.

The tree after FOUNDATION: the app is renamed (`ToothpasteToy/`, `ToothpasteToyTests/`, `ToothpasteToyUITests/`,
bundle `com.utkarsh.toothpastetoy`, display name "Toothpaste Toy", toothpaste is the default material), the Metro
Station starter is installed in `ToothpasteToy/Design/Metro/` with the token namespace `Metro`, and the v2 interfaces
below exist as compiling, working stubs (the lens pushes paste, the squeeze extrudes a striped ribbon that tears off,
channels and events are published). Nothing visual was redesigned yet: the screen is still Rheo's.

## 1. Rules

1. **Edit only your area's files** (§3). New files go in your area's folders (a new file in `ToothpasteToy/UI/` is
   UI's, in `ToothpasteToy/Render/` HOLO's, in `ToothpasteToy/Engine/` PLAY's, and so on).
2. **Frozen files** (§4) take *additive* changes only — a new field with a default, a new case nobody switches on
   exhaustively, a new type — and every such change is announced in your final report (file, exact Swift, why).
   Never rename, remove or change the meaning of a frozen declaration.
3. The hub constructs each area's concrete types by name with a fixed initialiser (contract):
   - PLAY: `ToothpasteCatalogData()`, `ToothpasteEngine(resources:initialMaterial:)`, `ToothpastePersistence(enabled:)`,
     `ToothpasteLaunch.current`, `ToothpasteLaunch.parse(_:)`, `ToothpasteFeel(resources:)`, `GloopKernel()`
   - HOLO: `TankRenderer(resources:)`
   - UI: `ToothpasteScreen(model:)` (from `ToothpasteToyApp`)
4. Cross-area reads allowed without a protocol: everyone may read `ToothpasteKnobs.yieldStress(_:)`,
   `ToothpasteKnobs.consistency(_:)`, `ToothpasteEngine.stateWord(solid:jammed:jams:)`, the `Metro` tokens and the
   starter's `Instrument*` types.
5. **LabKit is shared by other apps.** Touch only the LabKit files §3 lists for your area, keep the public API
   source-compatible (add parameters with defaults), and keep the LabKit checks green when you touch it:
   `LabKit/Tools/lk.sh <work> env TOOLCHAINS=metal swift test --no-parallel`,
   `LabKit/Tools/lk.sh <work> swift run -c release labkit-physcheck`,
   `LabKit/Tools/lk.sh <work> env TOOLCHAINS=metal swift run -c release labkit-gpucheck all`.
6. Build rules (unchanged): never build inside iCloud; `TT_BUILD_DIR=$TMPDIR/tt-<work> TT_SIM='<your sim>'
   Tools/build.sh sim|device|test|build-for-testing|test-without-building [xcodebuild args]`; one simulator of your own
   (`xcrun simctl create '<Name>' com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro-Max
   com.apple.CoreSimulator.SimRuntime.iOS-27-0`), every simctl call wrapped in `perl -e 'alarm 120; exec @ARGV'`,
   headless offscreen PNGs preferred, delete your simulator when done. Swift 6 strict concurrency, 0 warnings, XCTest
   only, British spelling, SI units, honest copy (the quantum hologram is a visual style; the physics is classical).
7. Keep a progress log `Documentation/progress-<area>.md` after each completed step.

## 2. What each area delivers (from REDESIGN.md)

| REDESIGN.md | UI | HOLO | PLAY |
|---|---|---|---|
| §1 identity | name, icon (`Tools/make-icon.swift`), "Other pastes" lineup, copy | — | toothpaste hero values, the other 12 kept |
| §2 holo chamber | the SwiftUI frame around the stage (housing chrome only if drawn in SwiftUI) | **the chamber**: metal housing, projector emitter + light cone, nozzle art, technical grid at depth, holographic paste (rim, fringes, scanlines, probability-cloud grain, superposition ghosts, Metro semantic colour, stripe bands from `(flags >> 8) & 0xF`), other pastes' identities, tilt parallax, bloom/EDR | the starting ribbon (`fill(…stripes:across:)`), nozzle position (`NozzleState`) |
| §3 lens | the native glass lens control (Metro `InstrumentLensSurface` recipe), its drag → `ToothpasteModel.lens` / `moveLens`, the fixed readout (γ̇, σ, state word) | refraction of the hologram under `frame.lens` (decorative, in Metal or the Metro shader), optional radius bounce on events | the lens as probe collider (stub in place), force feel, state word and yield/jam detection |
| §4 controls & channels | Squeeze crown + hold button → `ToothpasteModel.squeeze`; Gravity/Heat/Time crowns, steppers, material tiles; vertical pills from `live.channels`/`channels`; telemetry row; event tiles from `events`; floating action group; the "More" sheet | — | values behind the controls (gravity detents, heat, time), channel definitions, event detection |
| §5 play loop | the first-run flow and gestures | looks of each step | the physics of each step: squeeze → stack → coil that holds; lens cuts/dents; tilt past yield; shake; Moon/Jupiter; heat; other pastes |
| §6 honesty | info sheet copy (the hologram line), provenance | — | material provenance (catalog) |
| §7 performance | `-autoTour` disables the idle timer (App/PerfLog.swift) | hologram passes ≤ 1.5 ms, total GPU ≤ ~7 ms at 120 Hz for toothpaste | the oobleck substep budget, the 66 ms material-switch hitch |
| §8 contracts | consume | consume | own the stubs' behaviour behind the frozen types |

## 3. Every file and its owner

Paths are relative to `AI Stuff/Toothpaste Toy/` unless they start with `LabKit/` (`AI Stuff/LabKit/`).

### UI

| File | Notes |
|---|---|
| `ToothpasteToy/App/ToothpasteToyApp.swift` | `@main`; creates the hub after the first frame |
| `ToothpasteToy/App/PerfLog.swift` | `-perfLog`, `-autoTour`, `-tourShots`; set `UIApplication.shared.isIdleTimerDisabled` during `-autoTour` (REDESIGN §7) |
| `ToothpasteToy/App/QATour.swift`, `ToothpasteToy/App/Snapshot.swift` | in-app picture tours (`-uiTour`, `-snapshot`) |
| `ToothpasteToy/UI/*.swift` (ToothpasteScreen, TopBar, MaterialShelf, RheometerSheet, StatusFeed, InfoSheetContent, ToothpasteCopy, Licences, LiteraturePoints) | the screen; the 5-page console is retired by REDESIGN §4; keep a "More" sheet |
| `ToothpasteToy/Resources/Assets.xcassets/**` | app icon, accent, launch colour |
| `ToothpasteToy/Design/Metro/MetroTokens.swift` | the `Metro` token namespace (single source of Metro values) |
| `ToothpasteToy/Design/Metro/InstrumentDesignSystem.swift`, `InstrumentControlTouchBoundary.swift`, `LensRefraction.swift`, `InstrumentLensOptics.metal` | Metro Station starter (adapt, don't fork blindly; HOLO may *read* `LensRefraction` and `Metro`) |
| `ToothpasteToy/Design/Metro/UsageExample.swift` | reference only, excluded from the target in `project.yml` |
| `Tools/make-icon.swift` | the icon |
| `ToothpasteToyTests/UITests.swift` | headless SwiftUI checks |
| `ToothpasteToyUITests/ToothpasteToyUITests.swift` | XCUITests (real input) |
| `README.md` | the user-facing description (still Rheo's text below the rename note) |

### HOLO

| File | Notes |
|---|---|
| `ToothpasteToy/Render/TankRenderer.swift` | `TankRenderer: ToothpasteTankRendering`; the chamber, hologram, lens refraction, nozzle, projector |
| `ToothpasteToy/Render/TankShaders.metal` | app shaders (functions are `toothpaste*`) |
| `ToothpasteToy/Render/TankLabels.swift` | text textures |
| `ToothpasteToyTests/RenderTests.swift` | headless pictures and render checks |
| `LabKit/Sources/LabKitMPM/MPMSurfaceRenderer.swift` | the fluid surface renderer (shared with other apps: keep its API compatible) |
| `LabKit/Sources/LabKitMPM/FluidLook.swift`, `LabKit/Sources/LabKitMPM/MPMColourMaps.swift` | looks and diagnostic maps |
| `LabKit/Sources/LabKitMPM/Shaders/MPMRender.metal`, `LabKit/Sources/LabKitMPMTypes/include/MPMRender.h` | render shaders and their shared structs; read the dye band as `(p.flags >> PB_DYE_SHIFT) & PB_DYE_MASK` |
| `LabKit/Tests/LabKitMPMTests/MPMSurfaceRendererTests.swift` | keep green |

Hologram looks per material belong in `ToothpasteToy/Render/` keyed by `MaterialID` (`MaterialInfo.look` in PLAY's
catalog stays as LabKit's base look). HOLO reads `frame.lens`, `frame.nozzle`, `frame.channels`, `frame.pasteEvents`,
`frame.stats`, `frame.input` and the hub's `live` snapshot; it writes nothing outside its files.

### PLAY

| File | Notes |
|---|---|
| `ToothpasteToy/Engine/ToothpasteEngine.swift` | `ToothpasteEngine: ToothpasteSimulation`; owns the v2 stubs (lens collider, squeeze nozzle, channels, paste events) |
| `ToothpasteToy/Engine/TouchTools.swift`, `ProbeScanner.swift`, `Props.swift`, `Stimuli.swift` | canvas finger, rheometer probe, Box2D props, sensors → stimuli |
| `ToothpasteToy/Model/Materials.swift`, `Knobs.swift`, `Experiments.swift`, `LaunchConfig.swift`, `Persistence.swift` | catalog, knob specs, experiments, launch flags, settings (`ToothpasteToy.settings`) |
| `ToothpasteToy/Feedback/ToothpasteFeel.swift`, `FeelMap.swift`, `GloopKernel.swift`, `Microphone.swift` | haptics, sound, microphone flow (feedback once per accepted event: drive it from `PasteEvent`s and accepted control changes) |
| `ToothpasteToyTests/PhysTests.swift` (incl. the shared `PhysRig`), `ToothpasteToyTests/FeelTests.swift` | physics and feel tests |
| `LabKit/Sources/LabKitMPM/MPMTypes.swift` (`MPMEmitter`), `MPMSolver.swift` (`fill`, `seed`, `PendingParticle`, `MPMParticleSnapshot.band`), `MPMSolver+Encode.swift` (emitter encoding, `makeParticle`, resample) | emitter and dye code; other solver changes only with labkit-gpucheck parity green |
| `LabKit/Sources/LabKitMPM/Shaders/MPMSolver.metal` | `pbEmit` (the dye band); constitutive changes only with gpucheck + physcheck green and `LabKitMPMReference` kept in step |
| `LabKit/Sources/LabKitCore/ContinuumPresets.swift` | material values (provenance comments; physcheck green) |
| `LabKit/Tests/LabKitMPMTests/MPMDyeTests.swift` | the dye contract tests (keep green; add, don't weaken) |

### Integrator (shared; ask in your report)

| File | Notes |
|---|---|
| `project.yml`, `Tools/build.sh`, `.gitignore` | targets, settings, build mirror |
| `ToothpasteToyTests/ToothpasteSmokeTests.swift`, `ToothpasteToyTests/SkeletonDiagTests.swift`, `ToothpasteToyTests/InterfaceV2Tests.swift` | catalog/consistency smoke, diagnostics, the v2 contract tests (areas may add a test here for an additive interface change they announce) |
| `LabKit/Package.swift`, every other LabKit file | not touched in this stage unless your report asks first |
| `Documentation/REDESIGN.md`, `REDESIGN-OWNERSHIP.md`, `SKELETON.md`, `ARCHITECTURE.md` | read-only for the areas; each area writes its own `progress-<area>.md` |
| `Documentation/screenshots/` | anyone may add pictures, named `<area>-…` (never overwrite another area's) |

## 4. Frozen files (additive only, announced)

| File | What is frozen |
|---|---|
| `ToothpasteToy/Model/Interfaces.swift` | every declaration (v1 and v2 below) |
| `ToothpasteToy/Model/ToothpasteModel.swift` | the hub: resources, frame order, the UI API, the v2 state and methods |
| `ToothpasteToy/Model/PerfCounters.swift` | the hub's `-perfLog` counters |
| `LabKit/Sources/LabKitMPMTypes/include/MPMShared.h` | struct layouts (PBParticle 112 B, PBShape 64 B, …) and the dye bits: `flags` bit 0 enabled, bits 8–11 dye band (0 none, 1–7), `PBShape.emitMaterial` bits 0–7 slot / 8–11 stripes |
| `MPMEmitter.stripes`, `MPMSolver.fill(rect:…stripes:across:)`, `fill(polygon:…stripes:across:)`, `MPMParticleSnapshot.band` | LabKit's public dye API (PLAY may change the implementation, not the meaning) |

## 5. One frame (unchanged order, v2 additions marked)

```
UI writes:   model.lens (or model.moveLens(to:active:timestamp:)) ·v2   model.squeeze ·v2   knobs (ParamStore)
advance(dt): FrameStep(realDt, params, held, paused, layers, shelfMode, lens ·v2, squeeze ·v2)
             → engine.advance → frame (… + lens, nozzle, channels, pasteEvents ·v2)
             → publishLive(frame) ·v2: stamp pasteEvents (id, hub clock), refresh `live` (every frame, not observed)
             → feel.update(frame, dt)
             → 10 Hz: telemetry, materialID, banner events, channels ·v2, events (≤ 32) ·v2
encodeCompute: engine.encode(into:) → tank.encodeCompute(…)   encodeBehind / encodeScene / buildLines → tank.*
```

The engine turns `FrameStep.lens` (active) into a circle collider swept from where it ended the last frame to its
centre (speed ≤ 2 m/s; body 0 unless a canvas finger probe holds it) and samples the rheometer at its leading edge; it
turns `FrameStep.squeeze` (rate > 0) into an `MPMEmitter` at `NozzleState.position` (top centre, radius = bore,
velocity −speed, `stripes`), accumulates `extruded`, and on release appends a `.tearOff` event with the ribbon length.
`PasteChannels` come from the probe reading and the solver statistics; `.yield` fires when the probe's solid share
falls below 0.3 after holding at ≥ 0.6 (lens or finger down), `.jam` when the jammed share reaches 0.05 after being
below 0.01, `.impact` for every Box2D prop hit. These are stubs: PLAY tunes them.

## 6. The v2 interfaces (exact Swift)

### 6.1 `ToothpasteToy/Model/Interfaces.swift`, additions to existing types

```swift
/// The hero and default material (REDESIGN.md §1).
let defaultMaterialID: MaterialID = "toothpaste"

struct FrameStep: Sendable {
  // … v1 fields unchanged …
  /// v2: the glass lens and the tube as the UI left them (requested values; the engine acknowledges them in the frame).
  var lens: LensState = .resting
  var squeeze: SqueezeState = .idle
}

struct ToothpasteFrame: Sendable {
  // … v1 fields unchanged …
  /// The lens as the engine used it this frame (nil: inactive, no collider).
  var lens: LensState? = nil
  /// The tube's nozzle and what it did this frame (the engine fills it every frame; nil only before the first).
  var nozzle: NozzleState? = nil
  /// This frame's channels (the per-frame values the pills draw from; the hub republishes them at 10 Hz).
  var channels = PasteChannels()
  /// Paste events detected this frame (unstamped: the hub gives them ids and its clock time).
  var pasteEvents: [PasteEvent] = []
}
```

`ToothpasteTelemetry.material` now defaults to `defaultMaterialID`.

### 6.2 `ToothpasteToy/Model/Interfaces.swift`, new types (verbatim)

```swift
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
```

### 6.3 The hub, `ToothpasteToy/Model/ToothpasteModel.swift` (`@MainActor @Observable final class ToothpasteModel`)

```swift
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

  /// v2: moves the glass lens to a canvas-region point (points, origin top-left), as a drag on the canvas or the lens
  /// control does. `timestamp`: seconds since boot (UITouch.timestamp or CACurrentMediaTime); the velocity is estimated
  /// from successive calls and clamped to `LensState.maxSpeed`. `active: false` parks the lens (no collider) where it is.
  func moveLens(to regionPoint: CGPoint, active: Bool, timestamp: Double)
```

`perform(_:)` now also sets `squeeze.material` to the new material whenever a command changes the tank's material
(Fill, experiment). Everything else in the hub's v1 UI API is unchanged (`params`, `feedback`, `catalog`, `engine`,
`feel`, `telemetry`, `materialID`, `pourMaterialID`, `shelfMode`, `layers`, `paused`, `zoom`, `isRunning`, `tankView`,
`setActive(_:)`, `perform(_:)`, `refill()`, `choose(material:)`, `drop(_:)`, `apply(_:)`, `resetPage(_:)`,
`takeEvents()`, `touch(_:)`, `twoFinger(_:)`, `canvasRegion`, `heldKnobs`, `chromeBottom`, `reduceMotion`,
`latestFrame`, `perf`).

How to read what:
- **Pills, telemetry row, lens readout:** SwiftUI views observe `channels` (10 Hz: stable numerals); a TimelineView or
  Canvas that animates interior energy reads `live.channels` every frame (no observation, no lock: the hub writes it on
  the main actor in `advance`).
- **Event tiles, lens bounce, feedback:** `events` (10 Hz, ≤ 32, ids increase: remember the last id you handled) or
  `live.recentEvents` (≤ 8, per frame). Each event is delivered once per id: use the id to fire feedback once.
- **Squeeze readout:** show the requested `squeeze.rate`; show acknowledged output (`live.nozzle?.emitting`,
  `.extruded`) separately (Metro: requested vs acknowledged).
- **Renderer:** `frame.lens`, `frame.nozzle`, `frame.channels`, `frame.pasteEvents` (this frame's, unstamped).

### 6.4 LabKit (stripe dye), `LabKit/Sources/LabKitMPMTypes/include/MPMShared.h` and `LabKitMPM`

```c
// MPMShared.h
#define PB_FLAG_ENABLED   1u
#define PB_DYE_SHIFT      8u      // PBParticle.flags bits 8-11: dye band, 0 = none, 1-7 = band index
#define PB_DYE_MASK       0xFu
#define PB_MAX_STRIPES    7u
#define PB_EMIT_MATERIAL_MASK 0xFFu  // PBShape.emitMaterial bits 0-7 slot; bits 8-11 stripes across the nozzle
```

```swift
public struct MPMEmitter: Sendable, Equatable {
  // position, radius, velocity, material, rate, temperature as before
  /// Dye bands across the nozzle: 0 = plain (no dye), 1…`maxStripes` (larger values are clamped).
  public var stripes: Int
  /// The most dye bands a particle can carry (flags bits 8–11 hold 1…7).
  public static let maxStripes = Int(PB_MAX_STRIPES)
  public init(position: SIMD2<Double>, radius: Double, velocity: SIMD2<Double> = .zero, material: Int, rate: Double,
              temperature: Double? = nil, stripes: Int = 0)
}

extension MPMSolver {
  @discardableResult
  public func fill(rect: CGRect, material: Int, temperature: Double, structure: Double = 1, stripes: Int = 0,
                   across: SIMD2<Double> = SIMD2(1, 0)) -> Int
  @discardableResult
  public func fill(polygon: [SIMD2<Double>], material: Int, temperature: Double, structure: Double = 1,
                   stripes: Int = 0, across: SIMD2<Double> = SIMD2(1, 0)) -> Int
}

public struct MPMParticleSnapshot: Sendable {
  // … as before …
  /// Stripe dye band: 0 = none, 1…7 (`PBParticle.flags` bits 8–11; `MPMEmitter.stripes`, `fill(…stripes:)`).
  public var band: Int = 0
}
```

Semantics. The emit kernel (`pbEmit`) gives each new particle the band
`min(Int(t · stripes), stripes − 1) + 1`, `t = clamp(½ + ½ · dot(p − centre, across) / radius, 0, 1)`, where `across`
is the emitter's velocity turned by +90° (−vy, vx) normalised (x when the velocity is zero): equal-width bands across
the bore, band 1 on the −x side of a downward nozzle. A fill cuts its shape's extent along `across` into `stripes` equal
bands numbered from the low end (a ribbon lying along x: `across: SIMD2(0, 1)`). The band rides with the particle; a
quality-switch resample keeps it; drains and disables leave it on dead slots, which a new emission overwrites. Nothing
in the solver reads it (physics unchanged). The renderer reads `(p.flags >> PB_DYE_SHIFT) & PB_DYE_MASK`.

## 7. Stub limits PLAY inherits (honest list)

- The lens is a kinematic circle with no force limit (the canvas finger has one): it cuts any paste, even jammed
  oobleck. REDESIGN §5 wants jammed oobleck to stop it.
- The nozzle is only an emitter: no collider holds the ribbon, so "tear-off" is the emitter stopping (the ribbon then
  falls free) plus the event. The nozzle sits at the top inside the chamber (bore ≥ 1 cell, ≤ ¼ of the width).
- Emission rate = speed × bore ÷ particle area; the emit kernel refuses compressed cells, so a ribbon backed up
  against the nozzle stops emitting until it moves away.
- Channels: γ̇ and σ are the rheometer probe's (lens/finger leading edge, else the strongest-sheared region); structure is
  the tank's mean λ (or the jammed share for oobleck), not local. Log scales: γ̇ 0.01–1000 s⁻¹, σ 1–10⁴ Pa.
- Yield fires only with the lens or finger down; jam from the tank's jammed share; impacts only from Box2D props.
- No starting ribbon yet (REDESIGN §5.1): `fill(polygon:…stripes:across:)` exists for it.
- Not done by FOUNDATION (REDESIGN §7): the oobleck GPU budget, the 66 ms Fill hitch, the `-autoTour` idle timer.

## 8. Verification at hand-over

See `Documentation/progress-foundation.md` for the build and test logs (simulator Debug and device Release builds with
0 warnings, ToothpasteToyTests and ToothpasteToyUITests on `TT Found 15 Pro Max`, LabKit tests, physcheck and
gpucheck, one launch screenshot). Status words there: built, run, looked-at, written-only.
