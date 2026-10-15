# Rheo walking skeleton (now Toothpaste Toy)

> **Renamed 13 October 2026 (FOUNDATION, Toothpaste Toy redesign).** Rheo is now **Toothpaste Toy**: folder
> `AI Stuff/Toothpaste Toy`, sources `ToothpasteToy/`, tests `ToothpasteToyTests/` and `ToothpasteToyUITests/`, bundle
> `com.utkarsh.toothpastetoy`, build variables `TT_BUILD_DIR` / `TT_SIM` (the old `RHEO_*` names still work). Paths and
> `Rheo*` type names below were updated to the new names (`RheoModel` → `ToothpasteModel`, …); the narrative keeps the
> old brand where it describes history. Appendix A is the 9 October interface file with the new names; the current
> contract (v2) is `ToothpasteToy/Model/Interfaces.swift` plus `Documentation/REDESIGN-OWNERSHIP.md`.

Date: 8 October 2026. Work name `skel`, simulator `Rheo Skel 15 Pro Max` (iPhone 15 Pro Max, iOS 27.0).
Status (8 October): **the interfaces in `ToothpasteToy/Model/Interfaces.swift` and the hub in `ToothpasteToy/Model/ToothpasteModel.swift` are
frozen.** Four agents now fill in their areas in parallel; none of them edits another area's files.
Update (9 October 2026): the four areas are finished (`progress-{phys,render,ui,feel}.md`); RHEO-FIX, one integrator,
fixed their open issues and added `-perfLog`/`-autoTour` and the XCUITest target, with three small interface additions
(§3, §10, `progress-rfix.md`).

Status words: **built** (compiled), **run** (executed and checked), **written** (code exists, not exercised).

---

## 1. What the skeleton does

A compiling, running end-to-end slice of `ARCHITECTURE.md` §6:

- `ToothpasteModel` (`@MainActor @Observable`) is the `LabRenderScene`. It owns the `ParamStore`, `MotionSource`,
  `MicListener`, `ThermalSource`, `LabFeedback` (haptics + the `GloopKernel` bed), `MPMSolver`, `MPMSurfaceRenderer`
  and `RigidWorld`, lends them to the four areas through `ToothpasteResources`, and calls the areas in LabKit's frame order.
  The render loop owns time (`advance(dt:)`); telemetry is republished at 10 Hz.
- Oobleck fills the life-size tank (71.2 × 100.9 mm at Δx ≈ 1.98 mm) to 45 %; the shelf switches to any of the 13
  materials (Fill), picks a pour material (Pour) or drops props (Drop).
- Gravity is the screen-plane component of the (simulated, `-simSway`) device gravity × the Gravity knob; the Time knob
  scales simulated time; Freeze stops it.
- A one-finger drag moves a kinematic circle collider (radius = Finger knob) through the fluid; `-fakeTouch` scripts it.
- The fluid is drawn by `MPMSurfaceRenderer` (half-resolution prepass in `encodeCompute`, full-resolution shade in
  pass 2 sampling the mipmapped `behind` copy for refraction) over a gridded back wall.
- The console shows five pages of real knobs bound to the `ParamStore`; the top bar shows η (tank mean) and γ̇ · σ at the
  probe, live.

See §8 for what was built, run and seen, and §9 for known issues.

---

## 2. File layout and ownership

| Path | Area | What it is | Stub or done |
|---|---|---|---|
| `ToothpasteToy/Model/Interfaces.swift` | **integrator (frozen)** | every cross-area type and protocol (§3) | done |
| `ToothpasteToy/Model/ToothpasteModel.swift` | **integrator (frozen)** | the hub: resources, `LabRenderScene`, frame order, touch → tank metres | done |
| `ToothpasteToy/Model/Knobs.swift` | PHYS | 20 console specs + 2 card knobs, pages, per-material Fluid page, lava Heat | first pass |
| `ToothpasteToy/Model/Materials.swift` | PHYS | `ToothpasteCatalogData: ToothpasteCatalog` (13 materials, 4 props, flow curves `FlowCurve`), `ToothpasteSources` | first pass |
| `ToothpasteToy/Model/Experiments.swift` | PHYS | the 14 experiments + `ExperimentRecipe` (layers, props) | first pass |
| `ToothpasteToy/Model/LaunchConfig.swift` | PHYS | `ToothpasteLaunch.parse` / `.current` | done |
| `ToothpasteToy/Model/Persistence.swift` | PHYS | `ToothpastePersistence: ToothpasteSettingsStoring` (UserDefaults `ToothpasteToy.settings`) | done |
| `ToothpasteToy/Engine/ToothpasteEngine.swift` | PHYS | `ToothpasteEngine: ToothpasteSimulation`, `ToothpasteDrives` (mic routes) | working stub |
| `ToothpasteToy/Engine/TouchTools.swift` | PHYS | drag probe, pour, prop drag, poke/punch events, `FakeTouchScript` | working stub |
| `ToothpasteToy/Engine/Props.swift` | PHYS | `PropBay`: Box2D props, fluid ↔ body coupling | written |
| `ToothpasteToy/Render/TankRenderer.swift` | RENDER | `TankRenderer: ToothpasteTankRendering` | working stub |
| `ToothpasteToy/Render/TankShaders.metal` | RENDER | back wall and front glass fragments (with `labQuadVertex`) | stub art |
| `ToothpasteToy/App/ToothpasteToyApp.swift` | UI | `@main`; creates the model after the first frame, never under XCTest | done |
| `ToothpasteToy/UI/ToothpasteScreen.swift` | UI | §9 screen: canvas, stage tags, banner, console, lifecycle wiring | working |
| `ToothpasteToy/UI/TopBar.swift` | UI | `ToothpasteTopBar` (telemetry card, Material, Experiments) and `LayersMenu` | working |
| `ToothpasteToy/UI/MaterialShelf.swift` | UI | Fill · Pour · Drop picker + tile shelf | working |
| `ToothpasteToy/UI/RheometerSheet.swift` | UI | `RheometerSheet`, `FlowCurvePlot` (LabPlot) | working |
| `ToothpasteToy/UI/InfoSheetContent.swift` | UI | `ToothpasteInfoSheet`, panels 01–09 | first-pass copy |
| `ToothpasteToy/Resources/Assets.xcassets` | UI | AppIcon (from `Tools/make-icon.swift`), AccentColor, LaunchBackground | placeholder art |
| `Tools/make-icon.swift` | UI | draws the 1024 px icon | placeholder art |
| `ToothpasteToy/Feedback/ToothpasteFeel.swift` | FEEL | `ToothpasteFeel: ToothpasteFeeling`: hum map, events, bed, mic permission | written (untestable in the Simulator) |
| `ToothpasteToy/Feedback/GloopKernel.swift` | FEEL | `GloopKernel: SynthKernel` | stub voice |
| `ToothpasteToyTests/ToothpasteSmokeTests.swift` | integrator | catalog consistency, flow curves, `TankView`, 120-frame headless loop, material/experiment switching | done |
| `ToothpasteToyTests/SkeletonDiagTests.swift` | integrator | scripted-poke diagnostics at 120/60/15 fps, printed as `RHEO-DIAG` lines (not judged) | done |
| `ToothpasteToyTests/<Area>Tests.swift` | each area | add your own file (`PhysTests.swift`, `RenderTests.swift`, `UITests.swift`, `FeelTests.swift`) | — |
| `project.yml`, `Tools/build.sh` | integrator | targets Rheo, ToothpasteToyTests (unit), ToothpasteToyUITests (XCUITest, RHEO-FIX); §7.4 mic string | done |
| `ToothpasteToy/App/PerfLog.swift`, `ToothpasteToy/Model/PerfCounters.swift` | integrator (RHEO-FIX) | `-perfLog` recorder (CSV + os_log), `-autoTour`, `-tourShots`; per-frame counters the hub feeds | done |
| `ToothpasteToyUITests/ToothpasteToyUITests.swift` | integrator (RHEO-FIX) | real-input XCUITests: shelf, Gravity knob, tank drag, Experiments, Rheometer, info, Listen/mic flows, keyboard | done |

Since RHEO-FIX (9 October 2026) the areas are finished and one integrator owns every Rheo file; the rules below
applied during the area waves.

Rules:
1. Edit only your area's files. New files go in your area's folders.
2. Need a new cross-area type, a new `ToothpasteCommand` case, a new `SimEvent` or a field on `ToothpasteFrame`/`ToothpasteTelemetry`?
   Ask the integrator; do not edit `Interfaces.swift` or `ToothpasteModel.swift`. Area-private types stay in your files.
3. The hub constructs your concrete type by name with a fixed initialiser. These names and initialisers are part of
   the contract:
   - PHYS: `ToothpasteCatalogData()`, `ToothpasteEngine(resources:initialMaterial:)`, `ToothpastePersistence(enabled:)`,
     `ToothpasteLaunch.current`, `ToothpasteLaunch.parse(_:)`
   - RENDER: `TankRenderer(resources:)`
   - FEEL: `ToothpasteFeel(resources:)`, `GloopKernel()`
   - UI: `ToothpasteScreen(model:)` (from `ToothpasteToyApp`)
4. Cross-area reads that are allowed without going through a protocol: everyone may read `ToothpasteKnobs.yieldStress(_:)`
   and `ToothpasteKnobs.consistency(_:)` (FEEL uses them for the yield event and the bed pitch). Keep their signatures.

---

## 3. The interfaces

The full text is `ToothpasteToy/Model/Interfaces.swift` (appended verbatim in Appendix A). In short:

### 3.1 Identifiers and catalog

```swift
typealias MaterialID = String                 // LabPalette.rheoFluids ids: "oobleck", "honey", …
extension ParamID { static let yield, consistency, index, packing, gravity, heat, magnet, time, finger, stir, shake,
                    rate, listen, drives, gain, band, glow, grain, tracers, depth, memory, rebuild }
enum DriveTarget: Int { case shake = 0, gravity, stir, kicks, heat }
enum ShelfMode: String { case fill, pour, drop, scoop }   // scoop: RHEO-FIX (a drag drains fluid)
enum PropKind: String { case steelBall, glassMarble, corkBlock, die }
struct MaterialInfo { id, slot, title, hint, icon, material: ContinuumMaterial, look: FluidLook,
                      activeKnobs: Set<ParamID>, fillFraction, fillTemperature, real, tuned, citations }
struct PropInfo { id: PropKind, title, hint, icon, shape: RigidShape, density /* kg/m³ */, friction, restitution,
                  colour: SIMD3<Float> }
@MainActor protocol ToothpasteCatalog: AnyObject {
  var materials: [MaterialInfo] { get }; var props: [PropInfo] { get }; var specs: [ParamSpec] { get }
  var pages: [ConsolePage] { get }; var cardKnobs: [ParamID] { get }; var experiments: [Experiment] { get }
  var sources: [Citation] { get }
  func material(_ id: MaterialID) -> MaterialInfo; func prop(_ kind: PropKind) -> PropInfo
  func flowCurve(_ id: MaterialID, shearRates: [Double], temperature: Double) -> [Double]
}
```

### 3.2 Launch, settings, touch, commands

```swift
struct ToothpasteLaunch { var material: MaterialID?; var experiment: String?; var fakeTouch: String?; var quality: MPMQuality
                    var capacity: Int; var uiTesting: Bool; var persist: Bool }
struct ToothpasteLayers { stressLight, dyeLines, particles, rheometerCursor, useTilt, useMagnetometer: Bool
                    diagnostic: FluidDiagnostic }
struct ToothpasteSettings { material: MaterialID; shelfMode: ShelfMode; layers: ToothpasteLayers }
@MainActor protocol ToothpasteSettingsStoring: AnyObject { func load() -> ToothpasteSettings?; func save(_: ToothpasteSettings) }
struct TankTouch { id: Int; position, start: SIMD2<Double> /* tank m */; phase: began|moved|ended; timestamp }
struct TankTwoFinger { phase; delta, translation: CGSize /* pt */; scale: Double; anchor: SIMD2<Double> /* m */ }
enum ToothpasteCommand { refill, fill(MaterialID), pourMaterial(MaterialID), dropProp(PropKind), clearProps,
                   experiment(String), poke(SIMD2<Double>), punch(SIMD2<Double>), tilt(dx:dy:), shakeOnce,
                   quality(MPMQuality), resetAll }
```

### 3.3 One frame

```swift
struct FrameStep { realDt; params: ParamValues /* unmodulated snapshot */; held: Set<ParamID>; paused; layers; shelfMode }
struct ToothpasteFrame {
  realDt, simDt, simTime; params: ParamValues /* after drives */; sources: ModSources; tank: SIMD2<Double>
  input: MPMFrameInput /* exactly what the solver gets */; stats: MPMStats /* 1–2 frames old */; material: MaterialID
  finger: FingerState?; paddle: PaddleState?; props: [PropState]; magnet: MagnetState?; probe: ProbeReading
  events: [SimEvent]; simulatedMotion: Bool; vibration: SIMD2<Double> /* m/s², Hz */
}
enum SimEvent { refilled, materialChanged, poke, punch, touchDown, touchUp, pourStarted, propDropped, propHit(speed:),
                experimentApplied, qualityChanged }
struct ToothpasteTelemetry { material, viscosity, shearRate, stress, probeViscosity, solidFraction, fingerDown, timeScale,
                       tiltDegrees, shakeG, fieldMicroTesla, micDBFS?, simulatedMotion, lagging, particles, substeps,
                       gpuMilliseconds, nanCount, overflowCount, framesPerSecond, fillFraction }
struct TankView { tankSize; regionSize; metresPerPoint?; zoom; zoomCentre?
                  worldRect; tankPoint(_:) ; regionPoint(_:); displayScale; isLifeSize; pointsPerMetre }
struct ToothpasteViewState { tankView: TankView; layers: ToothpasteLayers; reduceMotion: Bool; paused: Bool
                       chromeBottom: CGFloat /* RHEO-FIX: top chrome's reach into the region, pt */ }
```

### 3.4 The four area protocols

```swift
@MainActor protocol ToothpasteSimulation: AnyObject {               // PHYS
  var tankSize: SIMD2<Double> { get }
  var currentMaterial: MaterialID { get }
  var pourMaterial: MaterialID { get }
  func start(); func stop()
  func advance(_ step: FrameStep) -> ToothpasteFrame
  func encode(into cmd: MTLCommandBuffer)
  func touches(_ touches: [TankTouch])
  func twoFinger(_ gesture: TankTwoFinger)
  func perform(_ command: ToothpasteCommand)
  func telemetry(frame: ToothpasteFrame, framesPerSecond: Double) -> ToothpasteTelemetry
}
@MainActor protocol ToothpasteTankRendering: AnyObject {            // RENDER
  var drawsBackdrop: Bool { get }                             // false = RENDER draws the stage itself
  func fillUniforms(_ u: inout LabFrameUniforms, frame: ToothpasteFrame, view: ToothpasteViewState)
  func encodeCompute(_ cmd: MTLCommandBuffer, context: LabFrameContext, frame: ToothpasteFrame, view: ToothpasteViewState)
  func encodeBehind(_ enc: MTLRenderCommandEncoder, uniforms: inout LabFrameUniforms, context: LabFrameContext,
                    frame: ToothpasteFrame, view: ToothpasteViewState)
  func encodeScene(_ enc: MTLRenderCommandEncoder, uniforms: inout LabFrameUniforms, context: LabFrameContext,
                   frame: ToothpasteFrame, view: ToothpasteViewState)
  func buildLines(_ batch: inout LineBatch, context: LabFrameContext, frame: ToothpasteFrame, view: ToothpasteViewState)
}
@MainActor protocol ToothpasteFeeling: AnyObject {                  // FEEL
  func setActive(_ active: Bool); func setPaused(_ paused: Bool)
  func update(frame: ToothpasteFrame, dt: Double)
  var micState: MicState { get }
  var deniedRaises: Int { get }        // RHEO-FIX: the UI opens the PermissionGate on each new count
  func requestMicrophone()
}
@MainActor final class ToothpasteResources {                        // owned by the hub, lent to every area
  let device: MTLDevice?; let params: ParamStore; let motion: MotionSource; let mic: MicListener
  let thermal: ThermalSource; let feedback: LabFeedback; let solver: MPMSolver?; let surface: MPMSurfaceRenderer?
  let rigid: RigidWorld; let catalog: any ToothpasteCatalog; let launch: ToothpasteLaunch
}
```

### 3.5 The hub's frame (ToothpasteModel)

```
advance(dt):  FrameStep(realDt, params.snapshot(), heldKnobs, paused, layers, shelfMode)
              → engine.advance → frame → feel.update(frame, dt) → 10 Hz: telemetry = engine.telemetry(frame, fps),
              mirror materialID / pourMaterialID, pass banner events to the UI (recentEvents)
encodeCompute: engine.encode(into: cmd)  →  tank.encodeCompute(cmd, context, frame, view)
encodeBehind / encodeScene / buildLines → tank.*
projection:   .orthographicRect(tankView.worldRect, fit: .stretch);  wantsBehindCopy: true
drawsBackdrop / fillUniforms → tank.drawsBackdrop / tank.fillUniforms
UI API:       params, feedback, catalog, engine, feel, telemetry, materialID, pourMaterialID, shelfMode, layers,
              paused, zoom, isRunning, tankView, setActive(_:), perform(_:), refill(), choose(material:), drop(_:),
              apply(_:), resetPage(_:), takeEvents(), touch(_ CanvasTouches), twoFinger(_ CanvasTwoFinger),
              canvasRegion, heldKnobs, reduceMotion, latestFrame
```

Tank frame: metres, origin at the inside bottom-left, y up (= LabKitMPM = LabKitRigid). `TankView` maps the canvas
region (points, y down) to it: life-size when `LabMetrics.millimetresPerPoint` is known and the tank fits (15 Pro Max:
0.16565 mm/pt, region 430 × 612.3 pt = 71.2 × 101.4 mm), the tank floor on the console's top edge, spare height as
headspace; otherwise a contain fit ("×0.69" at AX XXXL). MPM body indices: 0 finger, 1 stir paddle, 2…15 props.

---

## 4. What each stub must become

### PHYS (`Model/*` except the two frozen files, `Engine/*`)
- **Materials**: citations for every material (`rheology-models.md` §10), MR flow curve with the field branch,
  thixotropic curves at the current structure, a unit test of `FlowCurve` against LabKitMPMReference's `EVP` at steady
  shear (add `LabKitMPMReference` to the test target only).
- **Knobs**: CopyLint test of all copy; the Consistency range for Silly Putty (k = 2800 Pa·s > the spec's 1000; the
  range is widened per material now); Memory/Rebuild → G and t_build of the current material; Rebuild's detent source.
- **Experiments**: scripted stimuli (ketchup "tilt, then shake"), sources for each, "Two fluids" layer check.
- **Engine**: virtual magnet position (the `magnet:` input) and Kelvin force; magnetometer Δ|B| → field with the 100 µT
  dead zone; mic kicks as floor impulses (now a 60 ms vertical burst); lava cooling (`thermalTime`, `surfaceCooling`);
  quality auto-choice from measured device GPU time (`MPMStats.gpuMilliseconds`); `setQuality` on thermal pressure.
- **Touch tools**: a real poke impulse for quick taps (now a scripted 12 mm jab); punch tuning against the jamming
  front; probe placement (now the finger's leading edge: the collider pushes fluid out of its own disc, so the probe
  cannot sit at the finger centre); simulated-tilt signs (two-finger drag rolls the simulated phone; check on screen).
- **Props**: the |Δv| clamp from README-Rigid for light props in dense fluids; buoyancy per material; drag feel.
- **Persistence**: decide whether knob values persist.

### RENDER (`Render/*`)
- Stress light (Glow knob, Layers › Stress light) as a shear-rate emissive layer (now `FluidRenderOptions.glow` only
  drives lava's temperature glow and the knob is unused).
- Props drawn `colliderSkin · Δx` larger (the fluid keeps one cell away) and behind translucent fluids where right.
- Dye tracers look, magnet marker, vibrating-floor cue, finger ring and rheometer cursor art; zoom; diagnostics legend.
- Tilt-anchored key light (`FluidRenderOptions.keyLight`), stage vignette around the tank, Reduce Motion rules.
- GPU time on the iPhone 15 Pro Max (prepass + shade at 1290 × 2796).

### UI (`App/*`, `UI/*`, `Resources/*`, `Tools/make-icon.swift`)
- AX XXXL pass (top bar reflow, console growth, the tank refits via `TankView`), Large Content Viewer.
- Rheometer strip detent from the measured console top on hardware; σ/η readouts with provenance at the large detent.
- Info sheet copy: field notes per gesture, the §8.1 honesty list, generated UI names, CopyLint test.
- Banner copy for every `SimEvent` worth one; gesture-hint fade; zoom tag; the final app icon.
- The microphone usage string in `project.yml` differs from §7.4's copy (integrator change if UI wants it).

### FEEL (`Feedback/*`)
- Tune every constant of the §5.3 map on the iPhone 15 Pro Max (the Simulator has no haptics).
- MR crackle near the magnet, droplet pinch-off, `.ripple` per mic onset with Listen > 0, squelch bursts and grain
  clicks in `GloopKernel` (PolyBLEP saw, 2-pole filter at 4 f), speaker audibility, mic interruptions
  (`AudioRoute.observeInterruptions`), cue choices for UI events.

---

## 5. Launch arguments

| Argument | Read by | Effect |
|---|---|---|
| `-material <id>` | PHYS | start with this material (overrides the saved one) |
| `-experiment <id>` | PHYS | apply an experiment at launch (`punch`, `slowfast`, `monsters`, `ketchup`, `toothpaste`, `moon`, `honey`, `putty`, `slime`, `quicksand`, `magnet`, `paint`, `lava`, `twofluids`) |
| `-fakeTouch [poke\|stir\|punch\|slow]` | PHYS | a scripted finger, looping every 4 s after 1.5 s (`stir`: continuous circles) |
| `-quality standard\|high\|bench` | PHYS | Δx 2.0 / 1.6 / 1.1 mm |
| `-noPersist` | PHYS | neither load nor save settings |
| `-ui-testing` | PHYS | defaults, no persistence |
| `-thermalHeat` | PHYS | the phone's thermal state drives Heat (off by default) |
| `-page <id>`, `-shelf`, `-rheometer`, `-large`, `-info`, `-expanded` | UI | open that page, the shelf, a sheet, the expanded telemetry card. `-info` with `-rheometer`: the info sheet opens over the strip once the strip is up (1 s) |
| `-infoAfter <s>`, `-infoPanel <01…09>`, `-banner <kind>`, `-touched`, `-quietSensors`, `-logFrames` | UI | see `UI/ToothpasteScreen.swift` and `UI/StatusFeed.swift` |
| `-diagnostic <shearRate\|viscosity\|stress\|structure\|jam\|temperature\|speed>` | UI | Layers › Colour by at launch (the legend card shows among the stage tags) |
| `-snapshot`, `-uiTour`, `-ax` | UI | in-app pictures (`App/Snapshot.swift`) |
| `-simSway`, `-fakeMic`, `-startMic`, `-fakeMagnet`, `-fakeShake`, `-fakeThermal n`, `-fakeLowPower` | LabKitSensors / FEEL | LabKit's fakes (`-startMic` asks for the mic at launch; otherwise only the first raise of Listen does) |
| `-fakeMicDenied` | FEEL (Debug builds) | the microphone reads as refused without asking iOS (the PermissionGate flow in tests) |
| `-perfLog` | integrator (`App/PerfLog.swift`) | once a second: one CSV row in `Documents/perf.csv` (the previous run's file is kept as `perf-previous.csv`) and one `os_log` line (subsystem `com.utkarsh.toothpastetoy`, category `Perf`). Columns: `t_s, fps, frame_ms_mean, frame_ms_max, gpu_ms_mean, gpu_ms_max, gpu_frames, cpu_advance_ms_mean, substeps_mean, substeps_max, iterations, lagging_frames, cell_mm, max_substeps, thermal, low_power, particles, material, step`. GPU time is per solver frame and covers solver **and** render together (Rheo encodes the substeps and every render pass into the frame's one command buffer; LabKit has no split). `cell_mm`/`max_substeps`/`iterations` are the solver's current quality |
| `-autoTour` | integrator (`App/PerfLog.swift`) | cycles through every material (Fill, then two pokes) and then every experiment, 6 s each, forever; each step is logged (category `Perf`) and named in the CSV's `step` column. For unattended device measurement with `-perfLog`. Listen is kept at 0 (Oobleck monsters would otherwise bring up the microphone prompt and the app would pause behind it) unless `-fakeMic` or `-startMic` |
| `-tourShots` | integrator | with `-autoTour`: an in-app capture of the screen 5 s into each step, `Documents/tour-NN-<step>.png` (costs a frame or two: leave it off for timing runs) |

Reading the device log: `log stream --predicate 'subsystem == "com.utkarsh.toothpastetoy" && category == "Perf"'` (the
simulator, from the Mac) or Console.app with the phone attached. The CSV and pictures are in the app's Documents
(`UIFileSharingEnabled`: the Files app → On My iPhone → Rheo, or Finder with the phone attached), or
`xcrun devicectl device copy from --device <id> --domain-type appDataContainer --domain-identifier com.utkarsh.toothpastetoy
--source Documents/perf.csv --destination perf.csv`. A typical unattended run:
`xcrun devicectl device process launch --terminate-existing --device <id> com.utkarsh.toothpastetoy -- -perfLog -autoTour -noPersist`
(about 27 steps × 6 s = 2.7 min per lap).

---

## 6. Build, test, run, screenshot

Never build inside iCloud. Each agent uses its own build directory and simulator:

```zsh
cd "/path/to/developer/Documents/AI Stuff/Toothpaste Toy"
TT_BUILD_DIR=$TMPDIR/tt-<work> TT_SIM='<your simulator>' Tools/build.sh sim      # Debug, simulator
TT_BUILD_DIR=$TMPDIR/tt-<work> Tools/build.sh device                               # Release, generic iOS
TT_BUILD_DIR=$TMPDIR/tt-<work> TT_SIM='<your simulator>' Tools/build.sh test     # ToothpasteToyTests + ToothpasteToyUITests
```

The scheme has two test targets: `ToothpasteToyTests` (unit and headless-frame tests, hosted in the app) and `ToothpasteToyUITests`
(XCUITest: the app runs as itself and the runner synthesises taps, drags, knob turns and keys, reading the app's
accessibility tree from outside; nothing in the app turns on libAccessibility's automation flag). One of them, or
one test: `xcodebuild … test -only-testing:ToothpasteToyUITests` (or `-only-testing:ToothpasteToyTests/PhysTests/testPropsInOobleck`).
The UI tests take about 4 min on a loaded host; `testMicrophoneIsAskedForOnlyWhenListenIsRaised` resets the
simulator's microphone permission and answers the real iOS prompt (Don't Allow).

Your own simulator, then install, launch and screenshot (wrap every simctl call in a timeout):

```zsh
UDID=$(xcrun simctl create "Rheo <Work> 15 Pro Max" com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro-Max \
       com.apple.CoreSimulator.SimRuntime.iOS-27-0)
T() { perl -e 'alarm shift; exec @ARGV' "$@"; }
T 120 xcrun simctl boot $UDID
APP=$TMPDIR/tt-<work>/dd/Build/Products/Debug-iphonesimulator/ToothpasteToy.app
T 120 xcrun simctl install $UDID $APP
T 60 xcrun simctl launch --terminate-running-process $UDID com.utkarsh.toothpastetoy -simSway -noPersist -fakeTouch poke
sleep 6; T 60 xcrun simctl io $UDID screenshot shot.png
```

---

## 7. Known LabKit facts the areas must respect

- `MPMSurfaceRenderer.encodeShade` leaves its own pipeline and depth state on the encoder: set yours again after it.
- `MPMSolver.stats` is 1–2 frames old; apply `bodyImpulses` once per `stats.frameIndex` (PropBay does).
- Colliders keep the fluid one cell away (`colliderSkin = 1`).
- `MotionSource.simulatedTilt(dx:dy:)` changes yaw for dx, which does not tilt a screen-plane tank; the engine rolls
  `simRoll` instead.
- The frame loop never blocks on the GPU (two frames in flight; frames are skipped instead).
- **Time dilation.** When the substep rule wants more than `MPMQuality.maxSubsteps` (20 at standard), the solver
  simulates less than the requested `dt`. `ToothpasteEngine.plannedTime` predicts that with the public
  `MPMSubstepRule.plan` (same inputs as the solver) and advances the clock, the stir paddle, Box2D and the finger
  collider by the *simulated* time; `ToothpasteFrame.simDt`/`simTime` are the simulated values. Without this the collider
  jumped through the fluid every lagging frame (measured, §8). An oobleck pool needs about 14 substeps at 120 Hz,
  about 28 at 60 Hz (so 60 fps runs at about 0.7× speed) and about 110 at 15 Hz (0.18×).

---

## 8. Verification (8 October 2026)

Builds use `Tools/build.sh` with `TT_BUILD_DIR=$TMPDIR/tt-skel` (simulator, tests) and `$TMPDIR/tt-skel-dev`
(device). LabKit was **not** edited by the skeleton. Note: another work package edited LabKit (LabKitUI, LabKitCore
params/format, README) between 12:21 and 13:42 while the skeleton was being built; the final builds below (13:45–13:51)
compiled against LabKit as of 13:42.

| Claim | Status | Evidence |
|---|---|---|
| Rheo builds for the iOS Simulator (Debug) with 0 warnings | **built** | `Tools/build.sh sim`: `** BUILD SUCCEEDED **`, 0 `: warning:` lines (the only "warning" text is appintentsmetadataprocessor's "Metadata extraction skipped", a tool log line every Xcode build prints) |
| Rheo builds for device (Release, generic iOS, signed with team YOUR_TEAM_ID) with 0 warnings | **built** | `Tools/build.sh device`: `** BUILD SUCCEEDED **`, 0 warnings. Not installed on the iPhone (not asked; no device run) |
| ToothpasteToyTests pass in the `Rheo Skel 15 Pro Max` simulator | **run** | `Tools/build.sh test`: 7 tests, 0 failures: catalog consistency (13 materials ↔ ContinuumPresets ↔ data hues, 5 pages × 4 knobs with hues, copy lengths, CopyLint British spelling, 14 experiments with valid materials and knobs), modelled flow curves (honey σ(1 s⁻¹) = 15.4 Pa and halves per 6 K, ketchup yield, oobleck jams at 1000 s⁻¹), `TankView` life-size mapping and the AX XXXL fit (×0.69), material switching and experiments (Fluid page re-registered per material, lava's Heat range), the headless frame loop and pictures |
| The whole frame loop runs headlessly | **run** | `testModelAdvances240FramesHeadless`: `ToothpasteModel` through LabKit's `LabFrameEncoder` (solver substeps, surface prepass, split scene with the behind copy, lines, bloom, composite) for 240 frames at 120 Hz with `-fakeTouch poke`: simulated time 2.000 s, no lag (14 substeps), 3,312 particles, 0 NaN, 0 overflow, gravity down the screen, the scripted finger in the tank, and the oobleck pixel brighter than the back wall |
| The app runs in the Simulator with `-simSway`: life-size oobleck tank, live telemetry, five-page console | **run, screenshots inspected** | `screenshots/skeleton-idle.png`: oobleck at 45 % sloshing with the swaying phone; "η 105 mPa·s, γ̇ 0.698 s⁻¹ · σ 48.1 mPa"; THIN TANK · OOBLECK and LIFE-SIZE tags in the headspace; Yield and Flow index dimmed for oobleck; the console's top edge is the tank floor; nothing overlaps the fluid |
| One-finger drag moves the finger collider through the fluid (scripted with `-fakeTouch poke`) | **run, screenshots inspected** | `screenshots/skeleton-poke.png` (+ a 10-frame burst): the probe ring descends to the floor, the oobleck jams around it (η rises to about 0.5 kPa·s, σ about 0.4–1.4 kPa at the probe) and the rheometer cursor sits at the finger's leading edge; `RHEO-DIAG` shows volume ratio J 0.93–0.98 throughout. Real finger drags were **not** exercised (no touch injection in this run) |
| The shelf switches to Honey and Ketchup | **run, screenshots inspected** | `-material honey`: η 15.4 Pa·s (the preset), surface tilting with the phone, Consistency 15.4 Pa·sⁿ; `-material ketchup`: η 7.38 kPa·s at rest, Yield 25 Pa, K 8 Pa·sⁿ, n 0.30, a flatter surface (yield stress). `testMaterialSwitchAndExperiment` drives `choose(material:)` itself; the shelf tile tap was not driven by touch |
| Refraction through the `behind` copy | **run, pictures inspected** | `screenshots/skeleton-headless-water.png` (offscreen, 3×): the back-wall grid shows through water-like fluid, tinted teal and kinked at the free surface; `encoder.lastFrameSplit == true` |
| Gravity and Time knobs affect the simulation | **built, run in tests** | gravity = `env.screenGravityOnly` (× Gravity) is checked in the headless test; Time scales `simDt` (code path exercised by every frame; knob turns not driven by touch). `testMaterialSwitchAndExperiment` sets Gravity 0.166 via the Moon experiment |
| Shelf (Fill · Pour · Drop) and Rheometer strip lay out without covering fluid | **run, screenshots inspected** | `screenshots/skeleton-shelf.png` (World page), `screenshots/skeleton-rheometer-stir.png` (strip on the console's top edge, live cursor on the flow curve) |
| Honey and water respond normally to the finger | **run, screenshots inspected** | honey stirred with `-fakeTouch stir` stays a continuous viscous pool; water reads η 1.00 mPa·s |
| Haptics, the gloop bed, the mic permission flow, props, pour, experiments' recipes | **written** | compiled; the Simulator has no haptics; props, pour and Drop were not exercised on screen |

Simulator notes from this run: the host was saturated for long stretches (load average 600–980 from six other
agents' simulators rebooting), during which the simulator's display froze (the status-bar clock stopped) and
`simctl io screenshot` returned stale home-screen frames or timed out, although the app was alive (main thread idle,
no display-link callbacks). The offscreen PNGs in `testHeadlessPictures` were added as a display-independent check;
the on-screen screenshots above were taken once the display recovered.

## 9. Known issues

Status on 9 October 2026 (the list below is the skeleton's text of 8 October): **1** fixed in wave 2 (PHYS rest
melt, `DST.restMelt`/`plasticDrive`: a punch's jam halves in about 0.11 s and the surface is flat to 0.7 mm 3 s later);
**4–7** fixed in wave 2 (RENDER: stage, glass sheens, honey backlight, stress light); **9** in part (ProbeScanner finds
the strongest-sheared region without a finger, and the cursor now shows there dimmed while it flows); **11** fixed
(RHEO-FIX). Still open: **2** (particle foam; LabKit, LK-FIX), **3** (60 Hz policy; measure with `-perfLog` on the
phone), **8**, **10** (two-finger tilt sign on screen; the arrow keys are checked by XCUITest), **12** and **13**
(device). See §10 for RHEO-FIX's list.

1. **Jammed oobleck never relaxes at rest (PHYS, possibly LabKit).** With the shipped preset (φ 0.52, φ_m 0.452,
   σ* 5 Pa) any gravity-scale stress (≥ tens of Pa) drives f → 1, φ_J → φ_m < φ, so the suspension is jammed, and a
   jammed region carries its own weight. After one slow poke at 120 Hz the jammed fraction rises to 0.33 and stays
   there with the finger lifted (0.5 after a second poke); at rest the tank keeps open holes and towers for as long as
   watched (7 s headless, the 7 s on-screen burst). Stirring turns the pool into a self-supporting sponge that fills most
   of the tank (`skeleton-rheometer-stir.png`). Real oobleck flows back. Candidates: σ* (Han's density-matched fit is
   20.4 Pa with this form), the jam creep (`jamTime`, `jamFailureStress`), the rest-melt law, Packing default. This is
   the most visible physics problem for the "Punch the oobleck" experiment.
2. **Sparse particles render as bulk fluid (RENDER).** Where jammed oobleck fractures, particles separate but the
   splat (radius 1.2 cells, threshold 0.35) still draws continuous "foam", so the fluid looks larger than its volume
   (J stays 0.93–0.98).
3. **Time dilation below 120 Hz (PHYS).** At 60 fps the standard quality lags (needs about 28 substeps, cap 20) and the
   world runs at about 0.7×; on the loaded simulator it ran far slower. The engine now honours it (§7), but a real
   finger then moves faster *relative to the fluid*, so slow pokes behave like punches when the simulator is slow.
   Decide the 60 Hz policy (quality `.standard` with a higher cap, or `.high` only at 120 Hz) from a device run.
4. **Stage backdrop (RENDER).** LabKit's backdrop is Gyre's sky: faint radial and arc lines show above and below the
   tank. `TankRenderer.drawsBackdrop` is the switch.
5. **Front-glass streak (RENDER).** The placeholder sheen reads as a vertical light band on the left third.
6. **Honey looks muddy (RENDER).** The amber is dark and the back-wall grid (blue) is absorbed; the refraction is only
   obvious in clear fluids. Tune `FluidLook` per material or the wall colours.
7. **Glow knob unused (RENDER).** `FluidRenderOptions.glow` only drives lava's temperature glow; Stress light is not
   drawn yet.
8. **Grain** uses `Grain knob × 2` as the look-grain multiplier, so oobleck shows a mottled texture at the default 50 %.
9. **Probe placement (PHYS).** The finger collider pushes fluid out of its own disc, so the probe sits 3 mm ahead of the
   finger's edge along its motion (below it when still). The probe's σ and γ̇ are therefore *near* the finger, not under
   it; with no finger the probe is low in the pool, not at "the strongest-sheared region".
10. **Two-finger tilt** rolls `MotionSource.simRoll` (because `simulatedTilt(dx:)` changes yaw, which does not tilt a
    screen-plane tank); the sign was not checked on screen.
11. **The microphone usage string** in `project.yml` is shorter than §7.4's copy.
12. **Feel and sound are unverified**: written to LabKit's `StressFeel`/`FeelEventDetector`/`LabFeedback`; needs the
    iPhone 15 Pro Max.
13. **Not run on the device.** GPU time on the 15 Pro Max, the life-size claim on glass and the 902.4 pt sheet offset
    are unmeasured.

---

## 10. RHEO-FIX (9 October 2026)

One integrator (work name `rfix`, simulator `Rheo Fix 15 Pro Max`) fixed the areas' open issues (the four implementer
and four verifier reports) and added the device-measurement hooks and an XCUITest target. Log, numbers and file
paths: `progress-rfix.md`. LabKit was not edited here (LK-FIX was changing it in parallel; every result below is
against LabKit as it stood at the time of the run, noted where it mattered).

### 10.1 What changed

| Area | Change |
|---|---|
| FEEL | The hum keeps its harmonics outside the drives' keep-out band (only those inside are cancelled in the voice: a 120 Hz floor at Band 80 Hz loses only its fundamental). Rheo sets the voice's host gain itself (`ToothpasteBedMix`): the mic duck (× 0.3), Low Power Mode and Freeze scale only the continuous layers; squelches, cracks and splashes keep their level. With the mic live, background bubbles and grain clicks are spawned by the mapper, so each one opens the self-sound window (no plink → onset → kick → plink loop). `MicDenialWatch`: the PermissionGate opens on a raise of Listen while refused and on a refusal at iOS's prompt. `-fakeMicDenied`. |
| UI | Microphone state as a stage tag while Listen is up (Listening, Asking for the mic, Mic not allowed, Mic unavailable) and the PermissionGate card (§7.4 copy, Open Settings, close); the tank takes keyboard focus at launch; the Rheometer's η is "Probe viscosity" (the top bar's is the tank mean); `-info -rheometer` (info follows the strip); Layers › Colour by; the diagnostics legend is a SwiftUI card among the stage tags; Scoop shelf mode; §7.4 mic usage string in `project.yml`. |
| RENDER | Zoomed in, everything after the stage is scissored to the canvas region (no fluid under the console); a dimmed rheometer cursor at the strongest-sheared region while the fluid flows with no finger; ruler numerals under the top chrome are left out (`ToothpasteViewState.chromeBottom`); MR fluid's look retuned (`ToothpasteLooks`) plus an oily steel sheen pass (`rheoSheenFragment`), no spikes; lava crack pattern's honesty line in the catalog. |
| PHYS | Props in shear-thickening fluids feel the flow curve at the rate their own motion drives (`PropViscosity`): a dropped steel ball jams the oobleck surface, is held about 0.4 s, then sinks to the floor; props ride the vibrating floor's mean force (`EncodeLog`), so the quicksand marble reaches the floor during the shake; Scoop (a drain 0.75 × the finger along the drag); the punch test measures a settled surface; the toothpaste test measures a runaway topple. |
| Hooks | `-perfLog`, `-autoTour`, `-tourShots` (§5); `ToothpasteToyUITests` target (§6); `-uiTour -tourOnly fix-` picture steps. |

### 10.2 Verification

| Claim | Status | Evidence |
|---|---|---|
| Builds: simulator Debug and device Release, 0 warnings | **built** | build logs listed in `progress-rfix.md` (scratchpad `rfix/`) |
| ToothpasteToyTests on the simulator | **run** | final `Tools/build.sh test`: 87 run (FeelTests 23 incl. the real audio thread, PhysTests 38, RenderTests 3, ToothpasteSmokeTests 6, UITests 14, SkeletonDiag 1, 2 opt-in skips). Results moved with LK-FIX's in-progress solver during the day: toothpaste's lean (0.74–2.04 mm) and the honey pour pile (3.85–13.4 mm at 0.6 s) each failed once on an intermediate LabKit and passed on the next. Rerun on LabKit as of 17:38: PhysTests 38/38 and ToothpasteSmokeTests 6/6 (honey pile 13.4 mm, punch 0.72 mm, ball 35 mm deep at 4 s, marble at 6.0 mm) |
| ToothpasteToyUITests (real input) | **run** | 11/11: shelf tile → honey and the shelf closes; Gravity knob dragged 1.00 → 1.87 → 0.17 g; a drag in honey raises the probe's shear rate 0 → 1.16 s⁻¹; Experiments › Ketchup won't pour; Rheometer strip top 671.7 vs console 671.3 and "Probe viscosity"; info sheet; `-rheometer -info`; Listen raise with `-fakeMic` → "Listening"; with `-fakeMicDenied` → PermissionGate (closes); the real prompt: none at launch with `-noPersist`, "Allow “Rheo” to access your microphone?" on the first raise, Don't Allow → "Mic not allowed"; arrow keys tilt at launch |
| Fixed looks | **run, pictures inspected** | in-app captures (`-uiTour -tourOnly fix- -fakeMicDenied`, `screenshots/rfix-*.png`): ×2 zoom ends at the console; MR at rest a steel-grey body with sheen bands; legend under the tags with ×1.50 and ×0.25 up; dimmed cursor in sloshing water; mic tag and gate; Scoop; ruler numerals stop under the shelf / telemetry card |
| `-perfLog` / `-autoTour` | **run (simulator)** | one CSV row a second in `Documents/perf.csv` and os_log, all 13 materials and the experiments in turn, tour pictures. Simulator GPU times are not meaningful; **the device run is the point and has not been done** |
| Haptics, speaker, mic on the phone; A17 Pro GPU time | **written** | device only |

### 10.3 Still open

- Device run: `-perfLog -autoTour` on the iPhone 15 Pro Max (GPU ms at 120 Hz, substeps, thermal), the haptic map, speaker
  audibility, the mic prompt/denial/Settings/interruption flows on hardware.
- LabKit (LK-FIX's, in flux during this run): Rheo's physics tests track it. One intermediate solver made the
  toothpaste column creep 2.7 mm (base 22 → 28 mm) and another left the honey pour pile at 3.85 mm; the 17:38 one
  reads 0.3 mm and 13.4 mm. The punch re-expansion bump is gone with it (settled 0.7 mm). Rerun ToothpasteToyTests once LK-FIX
  is final. MR heaping, particle foam and the lava band are LK-FIX's.
- Vibrated oobleck (Merkt's holes and fingers), the ketchup demo's small slide, props' 8× added mass: unchanged, the
  copy says so.
- UIKit logs "Adding '_UIReparentingView' as a subview of UIHostingController.view is not supported" when the
  Experiments menu opens (SwiftUI `Menu` in LabKit's top bar); harmless in the tests.

---

## Appendix A. `ToothpasteToy/Model/Interfaces.swift` (verbatim)

```swift
// Interfaces.swift — OWNER: integrator (the skeleton architect). Frozen during the area waves; RHEO-FIX (8–9 October
// 2026) added `ToothpasteFeeling.deniedRaises`, the scoop tool (`ShelfMode.scoop`, `FingerState.Tool.scoop`) and
// `ToothpasteViewState.chromeBottom`. (The `-perfLog` counters are the hub's own: Model/PerfCounters.swift.)
//
// The contract between Rheo's four ownership areas (Documentation/SKELETON.md):
//   PHYS   ToothpasteToy/Model/* (except this file and ToothpasteModel.swift), ToothpasteToy/Engine/*
//   RENDER ToothpasteToy/Render/*
//   UI     ToothpasteToy/App/*, ToothpasteToy/UI/*, ToothpasteToy/Resources/*, Tools/make-icon.swift
//   FEEL   ToothpasteToy/Feedback/*
// Each area implements one protocol below with its own concrete type; `ToothpasteModel` (the hub) owns the
// shared resources and calls the areas in a fixed order every frame. Nothing here does any work.
//
// Units: SI in Double everywhere (metres, seconds, kilograms, pascals, kelvin, tesla). The tank frame has its
// origin at the inside bottom-left corner, x right, y up (the same frame as LabKitMPM and LabKitRigid).
//
// Changing anything in this file is an interface change: ask the integrator. Adding a *new* type or protocol
// that only your own area uses belongs in your own files, not here.

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
  var material: MaterialID = "oobleck"
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
```
