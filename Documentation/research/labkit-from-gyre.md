# LabKit extraction spec from Gyre

**Purpose.** This spec defines **LabKit**: one consistent UI, UX and physics kit for Utkarsh's iOS 27 toy apps. Its first consumer is **Rheo** ("Non-Newtonian Toy"). It covers each proposed module:

- the exact Gyre sources to lift, with `file:line`;
- the generalised public API, as Swift signatures that **compile under Swift 6**;
- verbatim design tokens;
- the frame and time architecture;
- the fake-sensor scheme for the Simulator;
- the strict-concurrency verdict per module;
- iOS 27 and SF Symbol gotchas;
- how shared Metal shaders ship in a SwiftPM package.

**Checked on:** 3 October 2026. Toolchain: Xcode 27.0 (27A5194q), Swift 6.4 (swiftlang-6.4.0.20.104), `iPhoneOS27.0.sdk` / `iPhoneSimulator27.0.sdk`, XcodeGen 2.46.

**Read in full:**
- every Swift and Metal file under `/path/to/developer/Documents/AI Stuff/Gyre/Gyre`;
- `README.md`, `project.yml` and `Info.plist`;
- `Tools/build.sh`, `Tools/physcheck/{run.sh,main.swift}` and `Tools/make-icon.swift`;
- the asset catalog JSON;
- `Spectra/Docs/research/design-gyre.md` (the starting point);
- the relevant parts of `design-orbitals.md`, `design-house-rules.md` and `sdk-sensors.md`.

**Nothing in Gyre, Orbitals, Spectra or the other projects was modified.** All experiments live under `/private/tmp/claude-501/-Users-utkarsh-Documents-AI-Stuff/b53a2b83-9308-4477-a9dd-fedd258cad75/scratchpad/labkit-from-gyre/`. That folder is called `$SCRATCH` below.

| Scratch artefact | What it is |
|---|---|
| `$SCRATCH/LabKitProto/` | A working **prototype of the LabKit package**: 6 library targets, a C shader-types target, a Mac harness, and XCTest. About 4,100 lines. Swift 6 language mode, iOS 27 + macOS 27. |
| `$SCRATCH/SmokeApp/` | An XcodeGen app with a Swift 6 target and `SWIFT_STRICT_CONCURRENCY: complete`. It consumes LabKit as a local package, the way Rheo will. |
| `$SCRATCH/smoke2.png` | Simulator screenshot of the smoke app running: sky backdrop, an app shader mixed with LabKit's library, lines, bloom, glass chrome, and the mic modulating gravity. |
| `$SCRATCH/isolation/iso.swift, iso2.swift` | SIL experiments proving the Swift 6 audio-thread isolation hazard (section 8). |
| `$SCRATCH/gyre-copy/` + `swift6-sil.log` | Gyre compiled as-is in Swift 6 mode, to list what breaks (section 8.3). |

---

## 0. TL;DR (decisions)

1. **One SwiftPM package `LabKit`** at `/path/to/developer/Documents/AI Stuff/LabKit`.
   - `// swift-tools-version: 6.4`. This is required for `.iOS(.v27)`; PackageDescription gates `v27` behind `_PackageDescription 6.4`.
   - `swiftLanguageModes: [.v6]`.
   - Products: `LabKitCore`, `LabKitSensors`, `LabKitFeedback`, `LabKitUI`, `LabKitRender`, `LabKitShaderTypes` (a C target), and the executable `labkit-physcheck`.
   - Optional later products: `LabKitAR` and `LabKitRadio`. Keep them separate so an app that links them is not dragged into camera or Bluetooth purpose strings.
   - **The prototype of exactly this layout builds for the iOS Simulator with 0 warnings, its XCTests pass on the iPhone 17 Pro simulator, and a Swift 6 app runs on it** (verified).
2. **Nothing has to stay in Swift 5 mode.** Every Gyre subsystem has a Swift 6-clean form, prototyped and compiled:
   - The ring buffer becomes `Mutex<State>`.
   - Synth controls become `InlineArray<16, Atomic<UInt64>>`.
   - The mic tap uses iOS 27's `installAudioTap`, whose provider is `@Sendable`.
   - Render blocks and Core Haptics handlers are built in `nonisolated static` factories.
   - The **one real trap** (verified in SIL): a closure handed to `AVAudioSourceNode` or the old `installTap`, if it is *formed inside a `@MainActor` method*, is inferred MainActor-isolated. It then carries a `swift_task_isCurrentExecutor` check, which will crash on the audio thread.
3. **Parameters are keyed by `ParamID`**, a string-backed `RawRepresentable` and `ExpressibleByStringLiteral` type. They are not keyed by `ReferenceWritableKeyPath<GyroModel, Double>`.
   - `ParamSpec` is Gyre's `KnobSpec` with the same mapping, detent and switch maths and the same tolerances.
   - `ParamStore` (`@MainActor @Observable`) holds the user values, and is the only parameter state SwiftUI observes.
   - The engine takes a `ParamValues` snapshot each frame and **modulates the copy**, exactly as Gyre does (`var p = params`, `GyroModel.swift:377`).
4. **Modulation ("Drives")** generalises Gyre's Listen depth knob plus Drives rotary switch (`GyroModel.swift:376-405`) into a declarative router:
   - `ModRoute(source, target, depth, depthParam, gate, curve, mode, attack, release)`.
   - Sources are conditioned sensor signals: mic envelope, level, bass, onset and spectrum thirds; motion shake, jerk, turn and tilt; magnetometer |B|, ΔB and EMF; barometer; thermal state; two LFOs; touch.
   - Targets are parameters, or named channels and triggers that the app's engine reads.
   - All five Gyre drives are expressible as five gated routes. The Mac harness verifies Gravity and Kicks against Gyre's formulas.
5. **The render loop owns time**, carried over unchanged:
   - `LabRenderer.draw(in:)` calls `scene.advance(dt:)` once per display frame. dt is 1/120 s on the first frame, then `min(now − last, 1/15)`.
   - Per-frame state is `@ObservationIgnored`.
   - Telemetry is republished at 10 Hz.
   - The MTKView delegate methods are `NS_SWIFT_UI_ACTOR` in the iOS 27 SDK (`MTKView.h:260/267`), so the whole loop is legitimately MainActor.
   - Rheo's MPM compute goes in the new `encodeCompute(_:context:)` hook, on the same command buffer, before the scene pass.
6. **Shaders ship inside the package.** Xcode compiles any `.metal` in a SwiftPM target into `LabKit_LabKitRender.bundle/default.metallib`, with no `resources:` entry needed. Load it with `device.makeDefaultLibrary(bundle: .module)` (verified at runtime).
   - The package's Metal compile **does not** receive the C target's include path. Use a relative `#include "../../LabKitShaderTypes/include/LabKitShaderTypes.h"`.
   - App shaders reach LabKit's header-only MSL library through `MTL_HEADER_SEARCH_PATHS` (verified).
   - One pipeline may take its vertex function from LabKit's library and its fragment function from the app's (verified on screen).
   - `swift build` on the command line **cannot** build `LabKitRender`. Keep the Mac harness Core-only.
7. **Corrections to `design-gyre.md`** (Gyre moved on after it was written; section 1):
   - Gyre now has an FFT (`Sensors/Spectrum.swift`) and radios (`Sensors/RadioSense.swift`).
   - The console pages are Physics, Signals and Object.
   - `carryOffset` is `(0, 0.035, −0.45)`.
   - **Most important for LabKit:** the Swift replacement for the deprecated tap *does* exist (`installAudioTap`). Gyre's comment at `MicListener.swift:97-98` and the memory note are wrong.

---

## 1. Corrections and additions to `design-gyre.md` (verified against source and SDK)

| design-gyre.md / memory said | Actual state (Gyre at 15:11, 3 October 2026) |
|---|---|
| "Gyre has no FFT and touches no radios" (§0, §6) | `Sensors/Spectrum.swift` (73 lines) is a Hann-windowed 2048-point `vDSP_fft_zrip` FFT, 48 log bands from 45 Hz to 15 kHz. `Sensors/RadioSense.swift` (164 lines) uses CoreBluetooth scanning, `NWPathMonitor` and `CTTelephonyNetworkInfo`, plus `-fakeRadio`. `project.yml:27` adds `NSBluetoothAlwaysUsageDescription`. |
| Console pages Physics / Sound / Object | `ConsolePage` is `physics = "Physics"`, `signals = "Signals"`, `object = "Object"` (`Console.swift:3-8`). Signals carries Listen, Drives, Gain, Scope, **Visual** and **Radio** (`Knobs.swift:189-249`). |
| `KnobID` has 15 cases | It has 17: `motor, inertia, gravity, balance, friction, air, magnet, time, listen, drives, gain, scope, visual, radio, frost, dispersion, refraction` (`Knobs.swift:3-8`). |
| `HumSynth.Controls` has 7 fields | It has 8: `vibrato` was added (radio waves wobble the pitch at 5.5 Hz), `HumSynth.swift:19-20, 95-98`. |
| `carryOffset = (0, −0.015, −0.45)` | `SIMD3<Float>(0, 0.035, -0.45)` (`ARController.swift:60`). |
| "`installTapOnBus:…error:block:` is `NS_REFINED_FOR_SWIFT` and the SDK has no AVFAudio Swift overlay that re-exposes it" (design-gyre §5; also the memory gotcha) | **Wrong.** The overlay lives inside the framework's own module: `AVFAudio.framework/Modules/AVFAudio.swiftmodule/arm64e-apple-ios.swiftinterface:63`, `@available(iOS 27.0) public func installAudioTap(onBus:bufferSize:format:tapProvider: @escaping @Sendable (AVReadOnlyAudioPCMBuffer, AVAudioTime) -> Void) throws`. design-gyre looked under `usr/lib/swift`. `sdk-sensors.md §4.9` had it right. I compiled it with `.float(let span)` channel data, with no warning (section 9). |
| Physcheck step cost 0.023 ms | I re-ran it: 8/8 PASS. Step cost was 0.164 ms per frame, with the machine loaded by parallel builds; it is load-dependent. |
| Info.plist gotcha | Still true. The checked-in `Gyre/Info.plist` (50 lines) has only `NSMotionUsageDescription`. It lacks Camera, Microphone **and** Bluetooth, although `project.yml:26-29` declares all four. |
| `UIScreen.mainScreen` deprecated in 27 | It was deprecated in **26.0**: `API_DEPRECATED(…, ios(2.0, 26.0))` (`UIScreen.h:57`). |

---

## 2. Package layout (prototype, verified)

```swift
// swift-tools-version: 6.4
// `.iOS(.v27)` / `.macOS(.v27)` need tools-version 6.4 (PackageDescription marks v27 `@available(_PackageDescription 6.4)`).
import PackageDescription

let package = Package(
  name: "LabKit",
  platforms: [.iOS(.v27), .macOS(.v27)],
  products: [
    .library(name: "LabKitCore", targets: ["LabKitCore"]),
    .library(name: "LabKitSensors", targets: ["LabKitSensors"]),
    .library(name: "LabKitFeedback", targets: ["LabKitFeedback"]),
    .library(name: "LabKitUI", targets: ["LabKitUI"]),
    .library(name: "LabKitRender", targets: ["LabKitRender"]),
    .library(name: "LabKitShaderTypes", targets: ["LabKitShaderTypes"]),
    .executable(name: "labkit-physcheck", targets: ["LabKitPhyscheck"]),
  ],
  targets: [
    .target(name: "LabKitCore"),                                   // nonisolated by default
    .target(name: "LabKitSensors", dependencies: ["LabKitCore", "LabKitFeedback"]), // AudioRoute lives in Feedback
    .target(name: "LabKitFeedback", dependencies: ["LabKitCore"]),
    .target(name: "LabKitUI", dependencies: ["LabKitCore", "LabKitFeedback"],
            swiftSettings: [.defaultIsolation(MainActor.self)]),   // SE-0466
    .target(name: "LabKitShaderTypes"),                            // C: include/LabKitShaderTypes.h + shim.c
    .target(name: "LabKitRender", dependencies: ["LabKitCore", "LabKitShaderTypes"]),
    .executableTarget(name: "LabKitPhyscheck", dependencies: ["LabKitCore"]),
    .testTarget(name: "LabKitCoreTests", dependencies: ["LabKitCore"]),
    .testTarget(name: "LabKitRenderTests", dependencies: ["LabKitRender"]),
  ],
  swiftLanguageModes: [.v6]
)
```

**Dependency graph.**
- Core is the base for everything.
- Feedback depends on Core.
- Sensors depends on Core and on Feedback (for `AudioRoute`; the one shared `AVAudioSession` owner).
- UI depends on Core and Feedback (knobs play haptics through `HapticEngine`).
- Render depends on Core and ShaderTypes.
- Sensors, Feedback, UI and `RenderHost` wrap their files in `#if os(iOS)`. Core builds for macOS too, so `swift run labkit-physcheck` works on the Mac in seconds (incremental build 10.6 s, then all checks PASS).

**Build facts verified on this machine:**
- `xcodebuild -scheme LabKit-Package -destination 'generic/platform=iOS Simulator'` gives **BUILD SUCCEEDED, 0 warnings**. Note that `xcodebuild -list` names the aggregate scheme `LabKit-Package`.
- `xcodebuild test -scheme LabKit-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` gives **TEST SUCCEEDED** (3 tests, including the metallib load).
- The first cold `swift build` of the Mac harness took 341 s (module-cache warm-up while other sessions were compiling). Incremental builds take about 10 s.
- `swift build --target LabKitRender` **fails**. SwiftPM calls `XcodeDefault.xctoolchain/usr/bin/metal` directly, which errors with `missing Metal Toolchain; use: xcodebuild -downloadComponent MetalToolchain`, while `xcrun metal` and xcodebuild work. Rule: only `LabKitCore` and the harness go through the SwiftPM command line; everything else builds through xcodebuild.
- Gyre's `xcodebuild` iCloud hang applies to the package too. Keep LabKit and the app under the same mirrored root (section 11).

---

## 3. Modules: what to lift, and the generalised API

Notation: `G/x.swift:N` means `/path/to/developer/Documents/AI Stuff/Gyre/Gyre/x.swift` at line N. `P/…` means `$SCRATCH/LabKitProto/Sources/…`, where the compiled prototype of the API lives.

### 3.1 LabKitCore: maths, parameters, modulation, integrators, environment, DSP, harness

UI-free: Foundation, simd, Accelerate and Observation only. Nonisolated by default. Everything is a `Sendable` value type except `ParamStore` (`@MainActor`) and `Spectrum` (a class owning an `FFTSetup`, confined to the engine's actor).

**Lift table**

| LabKit type / function | From Gyre | Change |
|---|---|---|
| `V3`, `F3`, `F4` (+ new `F2`), `.length`, `.unit`, `.f`, `.d`, `simd_quatd.identity`, `.float`, `.double`, `clamped`, `smoothstep(Float)` (+ `Double` overload), `perpendicular(to:)`, `wrapAngle` | `G/Physics/MathUtil.swift:1-56` (whole file) | `public`, `@inlinable` |
| `simd_float4x4(translation:)`, `(scale:)`, `(basis:_:_:origin:)` | `G/Render/GyroMeshes.swift:264-278` | moved to Core |
| `XorShift32` (`unit()`, `bipolar()`) | `G/Physics/BubbleWorld.swift:24-29`, `G/Feedback/HumSynth.swift:107-110`, `G/Sensors/MicListener.swift:199-202` | three copies merged |
| `approachFactor(dt:tau:)`, `approach(_:_:dt:tau:)` | the law `x += (target − x)(1 − e^(−dt/τ))`, used at `GyroModel.swift:374, 411, 469, 472`, `GyroSim.swift:107-109, 160`, `HoloRenderer.swift:439`, `ARController.swift:246` | named |
| `AttackRelease` | `GyroModel.swift:471-472` (envelope τ 0.03 up, 0.35 down) | generic |
| `Throttle(interval:)` / `Throttle(hz:)`, `.ready(at:)` | `GyroModel.swift:434` (trail 1/60), `:442` (telemetry 0.1), `:525` (spectrum history 0.05); `Haptics.swift:84` (1/40); `RadioSense.swift:77` (0.5) | named |
| `FrameClock` (first frame 1/120, cap 1/15) | `HoloRenderer.swift:263-265` | named |
| `SimClock` (timeScale ≥ 0.02, paused) | `GyroSim.swift:113, 126-130`, `GyroModel.swift:421` | named |
| `ParamID`, `LabColor`, `Detent`, `ParamScale`, `ParamSpec`, `ParamValues`, `ParamStore` | `G/Model/Knobs.swift:54-104, 184-187` | key path becomes `id`; `tint` is `LabColor` (UI adds `.color`); adds `glyph` |
| `RK4.step(_:h:project:_:)`, `IntegrableState` | `GyroSim.swift:198-207` (per-stage axis normalisation becomes `project`) | generic |
| `substepCount(dt:fastestRate:phasePerStep:cap:)` | `GyroSim.swift:132-141`: `n = clamp(⌈dt·ω_max/0.1⌉, 1, 2000)` | generic |
| `symplecticEuler` | `BubbleWorld.swift:63-64` | |
| `DampedSpring` (f 3.2 Hz, ζ 0.14, drive 14, limit 0.07, ×0.9 decay when disabled) | `Jiggle`, `BubbleWorld.swift:92-110` | parameters exposed |
| `RingBuffer<Element>` | `TrailBuffer`, `BubbleWorld.swift:113-133` | generic |
| `MotionSample` (+ `timestamp`), `.pose`, `.at`, `.resting`, `.simulatedField` | `G/Sensors/MotionSource.swift:6-35` | moved to Core (framework-free) |
| `Gravity.g0`, `Gravity.detents`, `Atmosphere.seaLevelKPa`, `Atmosphere.detents` | `GyroSim.swift:37`; `Knobs.swift:125-128, 158`; `GyroModel.swift:417` | named |
| `LabEnvironment` (+ `.from(_:gravityScale:air:pressureKPa:useBarometer:temperatureK:timeScale:)`, `gravityDevice`, `screenGravity`) | `GyroEnvironment` `GyroSim.swift:17-23`, `effectiveGravity` `GyroSim.swift:110`, assembly `GyroModel.swift:414-418` | adds temperature and a 2D in-plane gravity accessor for Rheo |
| `MicSnapshot` (+ `sampleRate`), `OnsetAnalyser` | `MicListener.swift:22-31, 147-171` | analyser split out of the listener |
| `EnvelopeFollower` | `GyroModel.swift:465-474` | |
| `ScopeData.update(_:gain:window:points:lag:)` | `GyroModel.swift:127-135, 478-510` | |
| `Spectrum` (+ `mean(_:)`, configurable band limits) | `G/Sensors/Spectrum.swift:6-73` | moved to Core (Accelerate works on macOS, so it is testable in the harness) |
| `EMFMeter` | `GyroModel.swift:627-646` | |
| `ModSourceID`, `ModSources`, `ModCurve`, `ModMode`, `ModGate`, `ModRoute`, `ModTrigger`, `ModOutputs`, `ModulationRouter`, `LFO` | new; replaces `GyroModel.swift:376-412` | section 6 |
| `SourceConditioner` | new; gathers envelope, EMF, jerk, ΔB baseline and LFOs | |
| `PhysCheck` | `Tools/physcheck/main.swift:6-10, 198-199` | reusable harness |

**Public API (compiled in `P/LabKitCore/*.swift`)**

```swift
public struct ParamID: Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral, CustomStringConvertible {
  public let rawValue: String
  public init(rawValue: String); public init(_ raw: String); public init(stringLiteral: String)
}
// Apps: extension ParamID { static let gravity: ParamID = "gravity" }

public struct LabColor: Sendable, Hashable { public var r, g, b: Double; public init(_ r: Double, _ g: Double, _ b: Double) }
public struct Detent: Sendable, Hashable { public let value: Double; public let label: String; public init(_ value: Double, _ label: String) }
public enum ParamScale: Sendable, Hashable { case linear, logarithmic }

public struct ParamSpec: Identifiable, Sendable {
  public let id: ParamID
  public var title: String, symbol: String, tint: LabColor
  public var range: ClosedRange<Double>, defaultValue: Double, scale: ParamScale
  public var origin: Double?          // bipolar knobs light up from here
  public var detents: [Detent]
  public var step: Double             // ≥ 1 ⇒ rotary switch
  public var hint: String, detail: String, glyph: String?
  public var format: @Sendable (Double) -> String
  public init(_ id: ParamID, title:symbol:tint:range:defaultValue:scale: = .linear, origin: = nil, detents: = [],
              step: = 0, hint:detail:glyph: = nil, format:)
  public var isSwitch: Bool                       // step >= 1
  public func position(of: Double) -> Double      // log: log(v/lo)/log(hi/lo)
  public func value(at: Double) -> Double         // step rounding, clamp
  public var originPosition: Double
  public func detent(at: Double) -> Detent?       // |Δposition| < 0.004
  public func clamp(_: Double) -> Double
  public static func labels(_ names: [String]) -> @Sendable (Double) -> String
  public static let percentOrOff, percent: @Sendable (Double) -> String
}

public struct ParamValues: Sendable, Equatable {
  public var storage: [ParamID: Double]
  public subscript(id: ParamID) -> Double { get set }
  public func choice<E: RawRepresentable>(_ id: ParamID, as: E.Type, default: E) -> E where E.RawValue == Int
}

@MainActor @Observable public final class ParamStore {
  public private(set) var specs: [ParamID: ParamSpec]; public private(set) var order: [ParamID]
  public init(_ specs: [ParamSpec] = [])
  public func register(_ list: [ParamSpec]); public func spec(_ id: ParamID) -> ParamSpec
  public subscript(id: ParamID) -> Double { get set }   // set clamps to range
  public func reset(_ ids: [ParamID]); public func apply(_ preset: [ParamID: Double])
  public func snapshot() -> ParamValues                // engine reads this once per frame
}

public protocol IntegrableState { static func + (Self, Self) -> Self; static func * (Double, Self) -> Self }
public enum RK4 { public static func step<S: IntegrableState>(_ y: S, h: Double, project: (S) -> S = { $0 }, _ f: (S) -> S) -> S }
public func substepCount(dt: Double, fastestRate: Double, phasePerStep: Double = 0.1, cap: Int = 2000) -> Int
public struct DampedSpring: Sendable { d, v: F3; frequency 3.2; damping 0.14; driveGain 14; limit 0.07
  mutating func step(dt: Float, accel: F3, enabled: Bool); mutating func kick(_ impulse: F3) }
public struct RingBuffer<Element: Sendable>: Sendable { init(capacity:fill:); append; clear; forEach((Int, Element) -> Void) }

public struct LabEnvironment: Sendable {
  public var attitude: simd_quatd, gravityWorld: V3 /* m/s², incl. −linear accel */, deviceRate: V3, linearAccel: V3
  public var magneticField: V3 /* T */, pressureKPa: Double?, airDensity: Double, temperatureK: Double, timeScale: Double
  public var gravityDevice: V3 { get }           // phone frame
  public var screenGravity: SIMD2<Double> { get } // in-plane (x right, y up): Rheo's tank gravity
  public static func from(_ s: MotionSample, gravityScale: Double, air: Double = 1, pressureKPa: Double? = nil,
                          useBarometer: Bool = false, temperatureK: Double = 293.15, timeScale: Double = 1) -> LabEnvironment
}

public struct PhysCheck { mutating func check(_ name: String, _ ok: Bool, _ detail: String)
  mutating func near(_ name: String, measured: Double, theory: Double, tolerance: Double, unit: String = "")
  static func cost(iterations: Int, _ body: () -> Void) -> Double; func finish() -> Never }
```

**Verified by `labkit-physcheck` on the Mac** (all PASS):
- RK4 SHO energy over 100 periods: err 0.000%.
- Substep rule: n = 210 at ω = 2513 rad/s, 120 Hz.
- Log knob round-trip: position(1) = 0.8121, back to 1.0 exactly.
- Detent lookup: 0.2501 gives "Slow motion".
- Gravity drive: g = 1 + 0.6·0.5·2 = 1.6, and air is untouched by the gate.
- Kick trigger: strength 0.6.
- Envelope: a steady hum settles to 0.000; a clap peaks at 0.811.
- Spectrum: a 1 kHz tone lands in band 25 (927–1047 Hz).
- `screenGravity` at the resting pose is (0, −8.493) m/s², which is −g·sin 60°.

### 3.2 LabKitSensors: motion, microphone, launch options

| LabKit | From Gyre | Change |
|---|---|---|
| `MotionSource` (`@MainActor`) | `G/Sensors/MotionSource.swift:40-140` | Pull mode is unchanged: `deviceMotionUpdateInterval = 1/120`, `.xArbitraryCorrectedZVertical`, falling back to `.xArbitraryZVertical`. The quaternion-convention latch (`:102-109`) is kept. New: `measuredRate` (Hz from `CMLogItem.timestamp`, per sdk-sensors §4.7, "measure fs"), `simulatedTilt(dx:dy:)` (`GyroModel.swift:753-755`), `-fakeMagnet` and `-fakeShake` |
| `MicState` | `MicListener.State` (`:37`) | |
| `MicListener` (`@MainActor`) + internal `MicRing: Sendable` | `G/Sensors/MicListener.swift:36-212` | `NSLock` fields become `Mutex<State>` (Synchronization). The deprecated `installTap` becomes `installAudioTap`. The permission callback becomes `async`. |
| `LaunchOptions` | ad hoc `ProcessInfo` reads at `MotionSource.swift:53`, `MicListener.swift:40`, `ARController.swift:65-66`, `RadioSense.swift:31`, `GyroModel.swift:254-256` | centralised, with a gating policy (section 7) |
| *(optional product `LabKitRadio`)* `RadioSense` | `G/Sensors/RadioSense.swift:12-164` | **Not prototyped.** Its Swift 6 error is at `:45`. Keep it out of Rheo. |
| *(optional product `LabKitAR`)* `ARController`, `ARFrameState`, `CoachingOverlay`, `ARBanner` | `G/Sensors/ARController.swift:10-379`, `G/UI/ARViews.swift:6-39` | **Not prototyped.** Note that Gyre's ARController produced no Swift 6 diagnostics in my compile. |

```swift
@MainActor public final class MotionSource {
  public private(set) var isLive: Bool, pressureKPa: Double?, last: MotionSample, measuredRate: Double
  public let barometerAvailable: Bool
  public var simYaw: Double, simPitch: Double /* 60° */, simRoll: Double, simSway: Bool, simMagnet: Bool, simShake: Bool
  public init()
  public func start(rateHz: Double = 120); public func stop()
  public func startBarometer(); public func stopBarometer()   // opt-in; prompts NSMotionUsageDescription
  public func sample(dt: Double) -> MotionSample              // call once per frame from advance(dt:)
  public func simulatedTilt(dx: Double, dy: Double)           // 0.008 rad/pt, pitch clamp −0.2…π−0.2
}

public enum MicState: Sendable, Equatable { case off, starting, on, denied, failed }
@MainActor public final class MicListener {
  public private(set) var state: MicState; public let fake: Bool
  public func start() async -> MicState          // just-in-time permission
  public func stop()
  public func ignoreOnsets(for seconds: Double)  // 0.2 s after own haptic pokes (GyroModel.swift:653, 812)
  public func snapshot(count: Int = 2048, dt: Double) -> MicSnapshot
}
```

The tap, verbatim from the prototype. It compiles in Swift 6 with no deprecation warning:

```swift
private nonisolated static func installTap(on input: AVAudioInputNode, ring: MicRing, sampleRate: Double, format: AVAudioFormat) throws {
  try input.installAudioTap(onBus: 0, bufferSize: 512, format: format) { buffer, _ in
    guard case .float(let span) = buffer.channelData(0) else { return }   // ChannelData is ~Escapable: use inside
    span.withUnsafeBufferPointer { ring.write($0, sampleRate: sampleRate) }
  }
}
final class MicRing: Sendable {                    // Mutex makes it Sendable without @unchecked
  struct State { var ring = [Float](repeating: 0, count: 16384); var head = 0; var analyser = OnsetAnalyser() }
  let state = Mutex(State())
}
```

Fake room, verbatim (`MicListener.swift:188-211`):
- a 0.22 × swell(0.18 Hz) chord of 196 Hz, + 0.6 × 294 Hz (phase 0.4) and + 0.25 × 392 Hz;
- plus white noise × 0.7 × e^(−70t) for 50 ms every 1.6 s;
- at 48 kHz, capped at 4096 samples per frame;
- written through the **same ring and analyser** as the real microphone.

### 3.3 LabKitFeedback: haptics, synth, audio route

| LabKit | From Gyre | Change |
|---|---|---|
| `HapticEngine` (`@MainActor`) | `G/Feedback/Haptics.swift:7-143` | Merged with Orbitals' `strength` (default 0.85, multiplies every intensity, per `design-orbitals.md §(e)`). Handlers are wired in a `nonisolated static func wire` with `@Sendable` closures. `spinUp()` is generalised to `ramp(duration:from:to:click:)`. Gyre's magnetometer crackle (`GyroModel.swift:705-711`) becomes `crackle(fieldMicroTesla:depth:clock:)`. |
| `HapticTap` + vocabulary constants | every `haptics.transient(…)` call site (table in §4.6) | named tokens |
| `SynthHost` (`@MainActor`), `SynthControls: Sendable`, `protocol SynthKernel: AnyObject, Sendable`, `SynthDSP`, `RotorHumKernel` | `G/Feedback/HumSynth.swift:8-135` | The engine is split from the voice. Controls become atomics. The render block comes from a `nonisolated static` factory. |
| `AudioRoute` (`@MainActor enum`) + `observeInterruptions(inactive:resume:)` | `G/Sensors/MicListener.swift:7-20` | Adds the iOS 27 session notifications. Gyre handles none. |

```swift
public struct HapticTap: Sendable, Hashable { public var intensity: Float, sharpness: Float, minGap: Double }
@MainActor public final class HapticEngine {
  public static let parameterRate = 40.0
  public let supported: Bool; public var enabled: Bool; public var strength: Float = 0.85
  public func start(); public func stop()
  public func updateHum(intensity: Float, sharpness: Float)   // per frame; < 0.02 stops; ≤ 40 Hz sends; sharpness − 0.5 offset
  public func play(_ tap: HapticTap)
  public func transient(intensity: Float, sharpness: Float, minGap: CFTimeInterval = 0)
  public func ramp(duration: Double = 0.55, from: Float = 0.1, to: Float = 1, click: Bool = true)
  public func crackle(fieldMicroTesla: Double, depth: Double, clock: Double)
}
// Swift 6-safe handler wiring (verified nonisolated in SIL):
private nonisolated static func wire(_ e: CHHapticEngine, to owner: HapticEngine) {
  e.resetHandler = { @Sendable [weak owner] in Task { @MainActor in owner?.recover() } }
  e.stoppedHandler = { @Sendable [weak owner] _ in Task { @MainActor in owner?.dropHum() } }
}

public final class SynthControls: Sendable {        // 16 slots, Double bit patterns, .relaxed
  private let slots: InlineArray<16, Atomic<UInt64>>
  public subscript(slot: Int) -> Double { get }; public func set(_ slot: Int, _ value: Double)
}
public protocol SynthKernel: AnyObject, Sendable {   // conformers: final class …: SynthKernel, @unchecked Sendable (render-thread confined)
  func prepare(sampleRate: Double)
  func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, controls: SynthControls)
}
@MainActor public final class SynthHost {
  public let controls: SynthControls; public let kernel: any SynthKernel; public private(set) var running: Bool
  public var masterVolume: Float = 0.9
  public init(kernel: any SynthKernel); public func start(); public func stop()
}
public enum SynthDSP { static func smoothing(tau: Double, sampleRate: Double) -> Double   // 1 − e^(−1/(τ·fs)), τ = 0.03
                       static func pan(_ p: Double) -> (Double, Double) }                     // (cos, sin)((p+1)π/4)·1.414
@MainActor public enum AudioRoute { public static var recording: Bool; public static func apply()
  public static func observeInterruptions(inactive: @escaping @MainActor () -> Void, resume: @escaping @MainActor () -> Void) -> [NSObjectProtocol] }
```

Constants for `RotorHumKernel` (verbatim, `HumSynth.swift:85-122`):
- Every control uses one-pole smoothing with τ = 30 ms.
- Vibrato runs at 5.5 Hz.
- The blade tone is 6× the rotor phase: `sin(b)·0.55 + sin(2b+0.3)·0.17 + sin(3b+1.1)·0.06`, plus the fundamental `sin(φ)·0.3 + sin(2φ)·0.12`.
- AM is `1 + wobble·sin(φw)`.
- Rumble is a one-pole low-pass with k = 0.02.
- The air band is a difference of two one-poles with `k = min(0.5, 0.01 + rotorHz·0.0009)`.
- Mix: `(tone·level·am + low·hiss·2.5 + air·whoosh·1.6)·0.2`.
- The mixer `outputVolume` is 0.9.
- The format is `AVAudioFormat(standardFormatWithSampleRate: output rate or 48 000, channels: 2)` (deinterleaved Float32).

Rheo writes its own kernel against the same host: squelch, gloop and granular crackle driven by shear rate.

### 3.4 LabKitUI: knob, console, top bar, info sheet, readout, banners, canvas region

`defaultIsolation(MainActor)`. Haptics are injected with `@Environment(\.labHaptics)`, an `@Entry` of type `HapticEngine?`.

| LabKit view | From Gyre | Change |
|---|---|---|
| `GlassKnob(spec:value:onActive:)`, `KnobArc` | `G/UI/GlassKnob.swift:6-188` | `ParamSpec` + `Binding<Double>` replace the key path. Orbitals' `.focusable()`, `@FocusState` and `onKeyPress(↑→ / ↓←)` are added. Haptics now use named taps. **`KnobArc` must be declared `nonisolated public struct`** (a compile error otherwise; section 8). |
| `KnobConsole<Page, Controls>(pages:page:open:store:activeKnob:content:controls:)`, `ConsolePage` | `G/UI/Console.swift:13-74, 173-260` | Pages are data. The page picker hides when there is a single page. The controls row is wrapped in `HStack(spacing: 10)`; the smoke run showed the controls stacking vertically without it. |
| `KnobGrid(_ ids:store:activeKnob:columns: = 4, dimmed:)` | `Console.swift:31-34, 114` (rows of 4; dimmed knobs at 0.55 opacity) | generic |
| `KnobReadout(spec:value:)` | `Console.swift:320-353` | |
| `LevelMeter(level:active:label:)` | `Console.swift:296-317` | |
| `GlassTile(title:symbol:subtitle:selected:tint:action:)` | `ObjectTile`, `Console.swift:264-293` | Rheo's material shelf |
| `ProminentGlassButton`, `CircleGlassButton` | `Console.swift:203-245` | |
| `LabTopBar(card:actions:)`, `ToolbarGlyph(_:)` | `G/UI/TopBar.swift:5-41`, icons 42×44 | |
| `TelemetryCard(expanded:rows:simulatedNote:headline:)`, `TelemetryRow` | `TopBar.swift:97-184` | rows are data |
| `StatusBanner(_:symbol:)` | `ARBanner`, `G/UI/ARViews.swift:22-39` | |
| `LabInfoSheet(title:content:)`, `InfoRow`, `LegendRow`, `SensorRow`, `KnobDetailRows` | `G/UI/InfoSheet.swift:3-125` | |
| `CanvasRegion(label:value:hint:actions:onFrame:onTouch:onMagnify:)` | `bubbleRegion`, `G/UI/ContentView.swift:66-98` | `.accessibilityActions { ForEach … }` replaces the fixed named actions |
| `.labChrome()` | `GyreApp.swift:7-9` + `ContentView.swift:42, 61` | |
| `LabTheme` tokens | section 4 | must be `nonisolated public enum` |

Menus are left to apps as plain SwiftUI. Use the pattern from `TopBar.swift:43-94`:
- `Menu { Section("…") { Button { Label(title, systemImage:); Text(subtitle) } } }` for two-line items;
- `Toggle(isOn:) { Label; Text(subtitle) }` sections;
- `.disabled(!available)` for unavailable sensors.

Experiments follow `Knobs.swift:283-349` (title, subtitle, symbol, preset). In LabKit a preset is just `[ParamID: Double]`, applied with `withAnimation(LabTheme.Motion.preset) { store.apply(preset) }` and followed by `haptics.ramp()`.

### 3.5 LabKitRender: MTKView host, targets, bloom/EDR post chain, line/point primitives, sky backdrop

| LabKit | From Gyre | Change |
|---|---|---|
| `LabRenderHost(scene:preferredFPS:)` (`UIViewRepresentable`) | `HoloView`, `G/Render/HoloRenderer.swift:719-751` | MTKView configuration is verbatim |
| `LabRenderer: NSObject, MTKViewDelegate` (`@MainActor`) | `HoloRenderer.swift:14-425` | Scene, gyro and bubble passes become `LabRenderScene` hooks |
| `protocol LabRenderScene` | the `GyroModel` calls inside `draw(in:)`, `:261-289` | new |
| `LabFrameContext` | new | |
| `PipelineFactory.make(vertex:fragment:vertexLibrary:fragmentLibrary:format:blend:depth:label:)`, `LabBlend` | `HoloRenderer.swift:98-126, 204` | Library mixing added. **Never assign `label = nil`**: it asserted under Metal validation in the smoke run. |
| `DepthStates.make(_:reversed:)` | `HoloRenderer.swift:157-168` | |
| `RenderTargets(device:size:wantsBehind:)` | `HoloRenderer.swift:15-25, 235-253` | The `behind` mip copy is optional; it is used for refraction. |
| `PostChain` | `HoloRenderer.swift:403-424, 653-678` | |
| `LineBatch` (`begin`, `cue`, `width`, `seg`, `point`, `polyline`, `ring`, `arrow`, `surroundFade`, `billboard`), `ViewBasis` | `G/Render/HoloScene.swift:76-271, 428-432` | Adds `cueEnabled` for flat 2D and `polyline` |
| `LineRenderer` (triple-buffer upload, instanced draw) | `HoloRenderer.swift:75, 295-308, 505-514` | |
| `LayoutCamera.perspective(…)` / `.orthographic(…)` | `phoneSetup`, `HoloRenderer.swift:431-461` | Adds an orthographic mode for Rheo's 2D tank |
| `MeshBuilder`, `GPUMesh` | `G/Render/GyroMeshes.swift:23-172` | |
| `LabShaders.library(device:)`, `.functionNames` | `makeDefaultLibrary()` at `HoloRenderer.swift:92` | now `makeDefaultLibrary(bundle: .module)` |
| `LabKitShaderTypes.h` (`LabFrameUniforms`, `LabLineInstance`, `LabMeshVertex`, buffer-index enums) | Swift mirrors (`HoloScene.swift:4-30`, `GyroMeshes.swift:4-21`) ↔ `Holo.metal:8-47` | One header shared by Swift and MSL, so layouts can't drift |
| `LabKit.metal` + header-only `LabKitShaderLib.h` | `Holo.metal` subset (section 10) | |
| **Stays in Gyre** (or a later `LabKitMaterials`) | the bubble (`bubbleVertex`, `bubbleFilmFragment`, `bubbleLensFragment`); `metalFragment` GGX + `environment()`/`studio()` IBL; `planetFragment`; `glassOrbFragment` + `abrasion`; AR camera setup `arSetup` (`:464-490`) | Not needed for Rheo v1. Glass-orb refraction is the best reference for fluid refraction (section 10.4). |

```swift
@MainActor public protocol LabRenderScene: AnyObject {
  var isRunning: Bool { get }; var reduceMotion: Bool { get }
  var canvasRegion: CGRect { get }                 // from CanvasRegion(onFrame:) = onGeometryChange(.global)
  var projection: LabProjection { get }            // default .perspective
  var drawsBackdrop: Bool { get }                  // default true
  func advance(dt: Double)                         // the ONLY place simulation time moves
  func encodeCompute(_ cmd: MTLCommandBuffer, context: LabFrameContext)            // default no-op; Rheo: MPM P2G/grid/G2P
  func encodeScene(_ enc: MTLRenderCommandEncoder, uniforms: inout LabFrameUniforms, context: LabFrameContext)
  func buildLines(_ batch: inout LineBatch, context: LabFrameContext)
  func fillUniforms(_ u: inout LabFrameUniforms)    // e.g. world.x north azimuth, world.y has-north
}
public enum LabProjection: Sendable { case perspective, orthographic }
public struct LabFrameContext { device, targets: RenderTargets, setup: LayoutCamera.Setup, depth: DepthStates,
                                time: Float, dt: Double, frameIndex: Int /* 0…2, matches the triple buffer */ }
```

The smoke app (`$SCRATCH/SmokeApp/Smoke/SmokeApp.swift`) is a complete, compiling and running example of `@MainActor @Observable final class SmokeModel: LabRenderScene`. It wires `ParamStore`, `MotionSource`, `MicListener`, `HapticEngine`, `SourceConditioner`, `ModulationRouter`, `LabEnvironment`, `Throttle(hz: 10)` telemetry, `KnobConsole`, `LabTopBar`, `TelemetryCard` and `CanvasRegion`.

---

## 4. Design tokens (verbatim from source)

Prototype: `P/LabKitUI/Theme.swift`. All values below were re-read in this session.

### 4.1 Colour

| Token | Value | Source |
|---|---|---|
| background | `Color.black` | `ContentView.swift:42` |
| LaunchBackground (asset) | sRGB (0.006, 0.012, 0.030) | `Assets.xcassets/LaunchBackground.colorset` |
| AccentColor (asset) | sRGB (0.38, 0.88, 1.00) | `AccentColor.colorset` |
| primaryAction (`.glassProminent` tint) | (0.2, 0.62, 0.85) | `Console.swift:188, 214` |
| liveGreen (mic-on glass tint, ×0.6 opacity) | (0.2, 0.75, 0.45) | `Console.swift:129` |
| phosphor (level meter; gradient + shadow r 4 at 0.8) | (0.35, 1.0, 0.55) | `Console.swift:305-307` |
| selectedTile (×0.45) | (0.25, 0.7, 1.0) | `Console.swift:287` |
| timeChip (capsule ×0.35) | (0.72, 0.55, 1.0) | `TopBar.swift:123` |
| telemetryIcon | (0.36, 0.86, 1.0) | `TopBar.swift:108` |
| secondaryLabel | white × 0.62 | `GlassKnob.swift:28` |
| knob track / meter track | white × 0.1 | `GlassKnob.swift:55`, `Console.swift:303` |
| simulated flag | `.orange` | `TopBar.swift:147` |

**Per-knob tints** (`Knobs.swift`): Motor (0.36, 0.86, 1.0) · Inertia (0.30, 1.0, 0.82) · Gravity (1.0, 0.70, 0.28) · Balance (1.0, 0.45, 0.62) · Friction (1.0, 0.50, 0.30) · Air (0.55, 0.75, 1.0) · Magnet (0.55, 1.0, 0.45) · Time (0.72, 0.55, 1.0) · Listen (0.35, 1.0, 0.6) · Drives (1.0, 0.62, 0.85) · Gain (0.45, 0.85, 1.0) · Scope (0.4, 1.0, 0.55) · **Visual (1.0, 0.55, 0.4)** · **Radio (0.45, 0.7, 1.0)** · Frost (0.8, 0.9, 1.0) · Dispersion (1.0, 0.55, 0.85) · Refraction (0.5, 0.85, 1.0).

**Rule:** carry the shared physical quantities' hues across apps:
- Gravity is always amber (1.0, 0.70, 0.28).
- Time is always violet (0.72, 0.55, 1.0).
- Magnet is always green (0.55, 1.0, 0.45).
- Listen / Drives / Gain / Scope keep their hues.

**Hologram palette** (`HoloScene.swift:32-58`, linear `F3`):

| Token | Value | Token | Value |
|---|---|---|---|
| rotor | (0.30, 0.88, 1.00) | field | (0.50, 1.00, 0.42) |
| rotorCore | (0.85, 0.97, 1.00) | trailHead | (0.35, 1.00, 0.90) |
| cage | (0.62, 0.42, 1.00) | trailTail | (0.55, 0.35, 1.00) |
| axle | (0.75, 0.86, 1.00) | horizon | (0.45, 0.60, 1.00) |
| momentum | (0.25, 1.00, 0.85) | north | (1.00, 0.35, 0.40) |
| torque | (1.00, 0.32, 0.80) | mote | (0.70, 0.85, 1.00) |
| gravity | (1.00, 0.66, 0.22) | emitter | (0.30, 0.75, 1.00) |
| phosphor | (0.35, 1.00, 0.55) | fieldLine | (0.40, 1.00, 0.72) |
| emf | (1.0, 0.85, 0.35) | `spectrum(x)` | t = 0.85x; rgb = 0.55 + 0.45·cos 2π(t + {0, 0.67, 0.33}) |

**Sky** (`Holo.metal:100-120`):
- skyTop (0.003, 0.006, 0.022), skyHorizon (0.018, 0.030, 0.075), groundHorizon (0.020, 0.012, 0.032), groundLow (0.002, 0.002, 0.005).
- Horizon glow (0.05, 0.075, 0.16)·e^(−38|z|).
- Grid lines (0.035, 0.065, 0.15) above the horizon and (0.07, 0.035, 0.11) below; 90° meridians at ×0.25.
- Horizon line (0.10, 0.16, 0.32); north tick (0.30, 0.06, 0.10).
- Backdrop focus glow (0.010, 0.030, 0.060)·e^(−0.55 r²); vignette 1 − 0.8|uv − 0.5|² (`:202-204`).

### 4.2 Type
- SF Pro, with `.monospacedDigit()` on numbers. Gyre never uses `design: .monospaced`; Orbitals does, for readouts.
- Knob title: `.caption2.weight(.semibold)`, `.textCase(.uppercase)`, `.tracking(0.6)`, white 0.62.
- Knob value: `.caption.weight(.medium).monospacedDigit()`, `.contentTransition(.numericText(value:))`, `lineLimit(1)`, `minimumScaleFactor(0.7)`.
- Buttons: `.subheadline.weight(.semibold)`. Toolbar glyphs: `.body.weight(.semibold)` in 42×44.
- Readout: `.headline`, `.headline.monospacedDigit()`, detent label `.caption.weight(.semibold)` tinted, hint `.footnote` secondary.
- Telemetry: headline `.subheadline.weight(.semibold).monospacedDigit()`; sub-line `.caption.monospacedDigit()`; expanded grid `.caption.monospacedDigit()`; time chip `.caption2.weight(.bold)`.
- Banner: `.footnote.weight(.medium)`.
- Info-sheet legend glyph: `.system(.headline, design: .serif).italic()`, frame width 22.
- Info rows: `.subheadline.weight(.semibold)` over `.callout` secondary. Intro `.callout`; method footnote `.footnote` secondary.

### 4.3 Shape and spacing
- Radii: cards and readouts 22; tiles 18; toolbar group and banners `.capsule`; circle buttons `.buttonBorderShape(.circle)` at 36×36; minimum control height 36; tile minimum height 62.
- `GlassEffectContainer` spacing: console 18, top bar 12, tile shelf 4 (tile `HStack` spacing 8).
- Console: outer `VStack` 12, page `VStack` 10, knob `Grid(horizontalSpacing: 2, verticalSpacing: 10)`, controls `HStack(spacing: 10)`, picker `maxWidth: 320`, readout `offset(y: -78)`.
- Screen: top bar `.padding(.horizontal, 16).padding(.top, 6)`; console `.padding(.horizontal, 12).padding(.bottom, 4)`; banner `.padding(.top, 8)`.
- Cards: telemetry padding 14 × 11; readout padding 16 × 12, `maxWidth 420`, outer horizontal 4; banner padding 14 × 10, outer horizontal 16. Telemetry grid spacing 14 × 6.

### 4.4 Motion
- Page `.spring(duration: 0.35, bounce: 0.2)`.
- Readout `.spring(duration: 0.3, bounce: 0.25)`.
- Fold and AR `.spring(duration: 0.45, bounce: 0.2)`.
- Telemetry expand `.spring(duration: 0.4, bounce: 0.25)`.
- Knob grab `.spring(duration: 0.25, bounce: 0.4)`.
- Tile `.spring(duration: 0.35, bounce: 0.25)`.
- Page reset `.smooth(duration: 0.5)`. Preset `.smooth(duration: 0.6)`. Readout value `.smooth(duration: 0.15)`. Meter `.linear(duration: 0.1)`. Double-tap reset `.smooth`.
- Transitions:
  - pages `.blurReplace`;
  - deck `.blurReplace.combined(with: .scale(0.9, anchor: .bottom))`;
  - readout `.opacity` + scale 0.92 from the bottom.
  - **These are `Transition` values, not `AnyTransition`.** `AnyTransition.blurReplace` does not exist (compile error found).
- Symbol effects:
  - `.symbolEffect(.bounce, value:)` on detent hits;
  - `.symbolEffect(.rotate.byLayer, options: .repeat(.continuous), isActive:)` on the telemetry icon;
  - `.contentTransition(.symbolEffect(.replace))` on toggling icons.
- Reduce Motion (`@Environment(\.accessibilityReduceMotion)` pushed into the model) parks the scan band at y = 9 and sets flicker to 1, scanlines to 0, ripples off and the wobble decaying (`HoloScene.swift:431-432`, `HoloRenderer.swift:694-698, 708`).

### 4.5 Knob geometry and feel (`GlassKnob.swift`)
- Frame 84×84 with a circular content shape.
- Arc radius 84/2 − 2 = 40; stroke 3, round caps; value-arc glow is a `.shadow(tint × 0.8, radius 4)`.
- **Sweep 270°**, angle = −135° + 270°·position, measured from up.
- Detent dots: 3×3 at `offset(y: -41)`, white 0.45, or 1.0 on the active detent.
- Puck 60×60:
  - symbol 16 pt semibold at white 0.9;
  - pointer capsule 3.5×10 at `offset(y: -22)` with `.shadow(tint, radius 3)`;
  - `.glassEffect(.regular.tint(tint.opacity(held ? 0.32 : 0.1)).interactive(), in: .circle)`;
  - scale 1.07 while held.
- `DragGesture(minimumDistance: 2)`. **230 pt of (dx − dy) is the full travel.**
- **24 ticks** per sweep. Detent capture within **0.02** of position. Rotary switches (step ≥ 1) click on every value change. Double-tap resets.
- VoiceOver step 1/20 of travel (continuous) or ±1 (switch).
- Bipolar arcs light up from `origin` (Gravity −1…3 and Balance −1…1 use origin 0).
- Orbitals adds `onKeyPress` arrows (now in LabKit) and an optional linear slider (not adopted; it would cost console height).

### 4.6 Haptics (intensity, sharpness)

| Token | Value | Source |
|---|---|---|
| knobGrab | 0.45, 0.7 | `GlassKnob.swift:106` |
| knobTick (every 1/24) | 0.32, 0.9 | `:133` |
| knobDetent | 0.9, 0.3 | `:125` |
| knobSwitch | 0.9, 0.35 | `:114` |
| knobReset (double-tap; VoiceOver switch nudge) | 0.7, 0.4 | `:89, :151` |
| knobNudge (VoiceOver continuous) | 0.4, 0.8 | `:155` |
| toggle (mic, pause) | 0.5, 0.6 | `GyroModel.swift:313`, `Console.swift:221` |
| modeChange (AR, page reset) | 0.6, 0.5 | `GyroModel.swift:298, 324` |
| place | 0.85, 0.35 | `GyroModel.swift:333, 773` |
| select (tile) | 0.7, 0.55 | `GyroModel.swift:287` |
| fold | 0.4, 0.5 | `Console.swift:249` |
| expand (telemetry) | 0.35, 0.6 | `TopBar.swift:161` |
| poke (tap on the object) | 0.9, 0.45 | `GyroModel.swift:811` |
| ripple / beat kick | 0.75, 0.5 | `GyroModel.swift:669` |
| string pull | clamp(\|dL\|/0.0015, 0.15, 0.85), 0.75, **minGap 0.03 s** | `GyroModel.swift:794-795` |
| radio hit | (0.15 + 0.3·depth)·strength, 0.95, **minGap 0.1 s** | `GyroModel.swift:616` |
| crackle | 0.35 + 0.4·magnet, 1.0; above 120 µT; rate min((B − 100)/30, 30)/s; jitter U(0.3, 1.7)/rate | `GyroModel.swift:705-711` |
| spin-up ramp | 0.55 s continuous (0.9, 0.3); intensity curve 0.1→1 and sharpness −0.3→0.4 over 0.5 s; click (1, 0.9) at 0.56 s | `Haptics.swift:113-142` |
| continuous hum | base event intensity 1, sharpness 0.5, duration 30 s, `loopEnabled`; stops below 0.02; **parameters at ≤ 40 Hz** | `Haptics.swift:55-91` |
| hum mapping (template for "what you feel") | intensity = (s > 0.003 ? 0.1 + 0.34√s : 0)(1 + 0.6·nod) + 0.55·strain (×0.35 when AR is placed); sharpness = 0.12 + 0.65s + 0.2·strain | `GyroModel.swift:674-691` |
| engine | `playsHapticsOnly = true`, `isAutoShutdownEnabled = false`; reset handler restarts; stopped handler clears the hum | `Haptics.swift:18-36` |

### 4.7 Rates and throttles

| What | Rate | Source |
|---|---|---|
| Display / sim | 120 Hz (60 in Low Power or AR); `CADisableMinimumFrameDurationOnPhone = true` | `HoloRenderer.swift:732, 749`, `project.yml:38` |
| dt | first 1/120 s, then `min(now − last, 1/15)`; physics also clamps at 0.05 s | `HoloRenderer.swift:264`, `GyroSim.swift:104` |
| Device motion request | 1/120 s, pulled once per frame | `MotionSource.swift:62, 89-96` |
| Telemetry republish | **10 Hz** (`clock − last > 0.1`) | `GyroModel.swift:442` |
| Haptic parameter sends | **≤ 40 Hz** | `Haptics.swift:84` |
| Trail samples | 60 Hz | `GyroModel.swift:434` |
| Spectrum history | 20 Hz, 30 rows | `GyroModel.swift:525-529` |
| Mic tap | 512 frames requested; ring 16384; snapshot 2048 per frame | `MicListener.swift:43, 99`, `GyroModel.swift:381` |
| Onset | rms > 1.9·avg + 0.004; refractory 0.12 s; avg τ 0.25 s; strength ≤ 12 | `MicListener.swift:166-170` |
| Onset ignore after own pokes | 0.2 s | `GyroModel.swift:653, 812` |
| Scope | window 1024, trigger search 900, hysteresis 0.02/(5·gain), 192 points, 3 persistence traces, XY lag 48 × 300 pairs, stride 2 | `GyroModel.swift:478-510` |
| Spectrum | 2048 Hann, 48 bands 45 Hz–15 kHz, (10·log10(p) − 8)/46, release τ 0.22 s, peaks τ 0.9 s | `Spectrum.swift` |
| Layout camera | τ 0.12 s | `HoloRenderer.swift:439` |

### 4.8 Render constants
- Scene `.rgba16Float`; depth `.depth32Float`; drawable `.rgba16Float`, `framebufferOnly`; `CAMetalLayer.wantsExtendedDynamicRangeContent = true`; colour space `extendedLinearDisplayP3`.
- Triple buffering: `DispatchSemaphore(3)`; line buffers grow to 2× the needed size.
- Bloom:
  - prefilter `c·smoothstep(0.35, 1.3, max(rgb))` into ½ resolution;
  - blur H/V at a 1.4-texel step, then copy to ¼ resolution and blur at a 2.2-texel step;
  - 5-tap Gaussian, weights 0.2270270270 / 0.3162162162 / 0.0702702703 at offsets 0 / ±1.3846153846 / ±3.2307692308.
- Composite:
  - chromatic aberration ±(uv − centre)·0.0022;
  - bloom ½·0.6 + ¼·0.54;
  - scanlines 1 − 0.04(0.5 + 0.5 sin(y·2.0944 + 4t));
  - `softClip(x, min(headroom, 3))` with knee k = 0.8;
  - headroom from `view.window?.windowScene?.screen.currentEDRHeadroom` (`HoloRenderer.swift:690`).
- Line cue: `0.72·(0.35 + 0.65·smoothstep(−1.1, 1, p·toEye))·(1 + 0.9·e^(−((y − band)/0.07)²))·flicker`; band = −1.4 + 2.8·fract(t/4.2); flicker = 1 + 0.025 sin 47t sin 13.3t.
- Line width: `w·pxScale·widthScale·(0.75 + 0.25·smoothstep(−1, 1, p·toEye))`; `widthScale = clamp(radius/170, 0.7, 1.5)`.
- Line quad: half-width `w/2 + 2.2w + 2` px; endpoints nudged 0.015 toward the eye. **Butt caps** for polyline segments longer than 1.5 px; round dots for points.
- Line fragment: core `1 − smoothstep(w − 0.6, w + 0.9, d)`; glow `0.45·e^(−d²/g²)` with g = 2.2w + 1.5; output alpha 0 (additive).
- Phone camera: distance 3.2 radii, focal `rPx·√(d² − 1)`, near 0.5, far 10, focus radius = 0.44·min(w, h) of the region.

---

## 5. Frame and time architecture

**The rule: the render loop owns time.** No timers and no `Task.sleep` loops.

```
MTKView (display link, MainActor; MTKViewDelegate.draw is NS_SWIFT_UI_ACTOR in the iOS 27 SDK)
└─ LabRenderer.draw(in:)                                  (HoloRenderer.swift:261-425)
   1. dt = FrameClock.tick(now: CACurrentMediaTime())     first frame 1/120 s, then min(Δ, 1/15)
   2. scene.advance(dt:)                                   ← the ONLY place simulation time moves
        a. MotionSource.sample(dt)                         pull Core Motion, or simulate
        b. p = store.snapshot()                            Sendable copy of the knob values
        c. mic.snapshot(2048, dt) → SourceConditioner.step → ModSources
        d. router.apply(sources, to: &p, specs:, dt:) → ModOutputs (channels + triggers)
        e. env = LabEnvironment.from(sample, gravityScale: p[.gravity], …)
        f. physics step(s): CPU (RK4 with substepCount) and/or record GPU work for step 4
        g. feedback: haptics.updateHum(…) (self-throttled to 40 Hz), synth.controls.set(…) (atomic)
        h. if telemetryGate.ready(at: clock): telemetry = Telemetry(…)   ← 10 Hz, the only per-frame write SwiftUI sees
   3. camera = LayoutCamera(region: scene.canvasRegion, τ 0.12 s)   ← SwiftUI layout drives the Metal camera
   4. inflight.wait() (triple buffer) → LineBatch.begin → scene.buildLines → LineRenderer.upload(frame)
   5. cmd: scene.encodeCompute(cmd)      ← Rheo: MLS-MPM clear/P2G/grid update/G2P on this command buffer
          scene pass: backdrop → scene.encodeScene → lines (additive, depth test without write)
          PostChain: bloom ½, ¼ → composite (aberration, scanlines, EDR soft-clip) → present
```

**Observation discipline**, as in `GyroModel.swift:139-226`:
- *Observed*: user-facing state only. That means the `ParamStore` values, toggles, `paused`, `telemetry` (one small `Equatable` struct), `activeKnob`, `isRunning`, `micState`, and the selected material or object.
- *`@ObservationIgnored`*: everything that changes per frame (samples, trails, ripples, scope, clocks, `canvasRegion`, solver state) and every subsystem (motion, mic, haptics, synth, solver).
- **The 120 Hz engine never invalidates SwiftUI.** Reading an `@Observable` property outside a tracking scope (as `store.snapshot()` does in `advance`) records nothing.

**Lifecycle**:
- `.onAppear`: push `reduceMotion`, then `model.start()`.
- `onChange(of: scenePhase)`: `.active` calls `start()`, `.background` calls `stop()`.
- First start applies launch arguments (`-startMic`, …); later starts resume AR, if any.
- `LabRenderHost.updateUIView` sets `view.isPaused = !scene.isRunning`.
- Source: `ContentView.swift:44-60`, `GyroModel.swift:246-268`, `HoloRenderer.swift:746-750`.

**The layout trick to reuse**: `CanvasRegion` publishes `.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) }` into `scene.canvasRegion`. `LayoutCamera` eases toward it with τ 0.12 s. Folding the console (`LabTheme.Motion.fold`) therefore lets the tank swell, with no explicit animation (`ContentView.swift:90`, `HoloRenderer.swift:431-443`).

**Rheo specifics (inferred, not built):**
- **Substeps for MPM:** use `substepCount(dt: simDt, fastestRate: c/dx, phasePerStep: CFL)`, with c the elastic or bulk wave speed (√(E/ρ) or √(K/ρ)) plus the max particle velocity. A CFL of about 0.3–0.5 is typical for explicit MPM. The 1/15 s dt cap bounds the worst case.
- **Do not block the main thread longer than a frame.** `inflight.wait()` runs on the main thread (Gyre does this), so if GPU compute exceeds one frame, UI touches stall. Rheo must budget its MPM work, for example by dropping substeps under load and watching `ProcessInfo.thermalState`.
- **CPU reference solver:** keep it in LabKitCore style (pure Swift + simd) inside Rheo's own `Physics/` folder or a `RheoCore` target, so `labkit-physcheck`-style harnesses can run it on the Mac.

---

## 6. Modulation ("Drives") system

### 6.1 Sources (`ModSourceID`, `P/LabKitCore/Modulation.swift`; conditioner in `Environment.swift`)

| ID | Meaning, units | Conditioning (constants) |
|---|---|---|
| `mic.envelope` | loudness above the room's floor, 0…1 | `EnvelopeFollower`: (dB + 55)/45; floor τ 0.4 s falling, 20 s rising; above = max(0, raw − floor − 0.04)/max(1 − floor, 0.25); attack 0.03 s, release 0.35 s toward min(1.5·above, 1) |
| `mic.level` | raw level 0…1 | clamp((20·log10(level·gain) + 55)/45) |
| `mic.bass` | RMS < 150 Hz × gain | one-pole a = 1 − e^(−2π·150/fs) |
| `mic.onset` | impulse 0…12 on the frame it fires | rms > 1.9·avg + 0.004; refractory 0.12 s |
| `mic.low`, `mic.mid`, `mic.high` | spectrum means, bands 0..<10, 10..<30, 30..<48 | `GyroModel.swift:522-524` |
| `motion.shake` | \|userAcceleration\| (g) | none |
| `motion.jerk` | \|Δa\|/dt (g/s), τ 0.05 s | new (the τ follows Gyre's ω̇ filter at `GyroModel.swift:358`) |
| `motion.turn` | \|ω\| (rad/s) | none |
| `motion.tilt` | screen-normal angle from vertical / π | new |
| `mag.field` | \|B\| (µT) | calibrated device-motion field |
| `mag.delta` | \|B\| − baseline (µT), baseline τ 8 s | new: "magnet approaching" (Rheo's MR fluid) |
| `mag.emf` | flicker RMS (µT) | `EMFMeter` (mean τ 0.5 s, variance τ 0.4 s, zero-crossing Hz over 0.5 s windows) |
| `baro.ratio` | p / 101.325 kPa | barometer is opt-in |
| `device.thermal` | `ProcessInfo.thermalState` 0, ⅓, ⅔, 1 | new: a playful "phone heat" source for Temperature |
| `lfo.1`, `lfo.2` | 0.25 Hz sine; 1.3 Hz triangle | `LFO` (sine, triangle, square, sample-and-hold) |
| `touch.speed`, `touch.down` | finger speed (pt/s ÷ 1000); finger down | apps fill these from `CanvasRegion.onTouch` |

### 6.2 Routing

```swift
public enum ModCurve { case linear, power(Double), smooth, exponential(Double), gate(Double), invert, normalize(Double) }
public enum ModMode  { case add(Double), multiply(Double), rangeFraction, trigger(threshold: Double) }
public struct ModGate { var param: ParamID; var index: Int }   // route live only while a rotary switch sits on index
public struct ModRoute { id, source, target: ParamID, depth = 1, depthParam: ParamID? = nil, gate: ModGate? = nil,
                         curve = .linear, mode = .add(1), attack = 0, release = 0, clampToRange = false, enabled = true }
public struct ModulationRouter: Sendable {
  public var routes: [ModRoute]
  public mutating func apply(_ s: ModSources, to p: inout ParamValues, specs: [ParamID: ParamSpec], dt: Double) -> ModOutputs
}
```

- A route whose target is a **registered `ParamID`** modulates the frame's copy of that parameter.
- Any **other ID is a channel** (`out["filmShimmer"]`), read by the engine.
- `.trigger` routes are edge-detected: they re-arm when the source drops back below the threshold. Each fires a `ModTrigger(strength = depth·curve(raw))`.
- Effective depth = `depth × params[depthParam]`. Triggers need depth > 0.01, as Gyre's `depth > 0.01` does.

**Gyre's five drives, expressed as routes.** Behaviour is identical to `GyroModel.swift:386-405`; the Gravity and Kicks routes are verified in the harness.

```swift
ModRoute("gravity", source: .micEnvelope, target: "gravity", depthParam: "listen", gate: ModGate("drives", 0), mode: .add(2))
ModRoute("air",     source: .micEnvelope, target: "air",     depthParam: "listen", gate: ModGate("drives", 1), mode: .multiply(3))
ModRoute("turbulence", source: .micEnvelope, target: "airTurbulence", depthParam: "listen", gate: ModGate("drives", 1), mode: .add(0.004)) // engine re-aims it every 0.1 s, eases τ 0.08 s
ModRoute("spin",    source: .micEnvelope, target: "spinTorque", depthParam: "listen", gate: ModGate("drives", 2), mode: .add(0.003))
ModRoute("kick",    source: .micOnset, target: "kick", depthParam: "listen", gate: ModGate("drives", 3), curve: .normalize(5), mode: .trigger(threshold: 0))
ModRoute("film",    source: .micEnvelope, target: "filmShimmer", depthParam: "listen", gate: ModGate("drives", 4))
ModRoute("ripple",  source: .micOnset, target: "ripple", depthParam: "listen", gate: ModGate("drives", 4), mode: .trigger(threshold: 0))
ModRoute("jiggle",  source: .micBass, target: "jiggle", depthParam: "listen", gate: ModGate("drives", 4), mode: .add(2))
```

**Rheo mapping (suggested; for the Rheo UX agent to confirm).** Keep Gyre's UX: a Listen depth knob plus a Drives rotary switch. Its destinations could be:

| Drive | Route | Physical meaning |
|---|---|---|
| Vibrate ("cornstarch monsters") | `mic.envelope` + `mic.bass` → `shakerAmplitude` channel (`.add(k)`), `mic.onset` → `kick` trigger | a speaker cone under the tank |
| Stir | `mic.envelope` → `stirRate` channel | an impeller |
| Heat | `mic.envelope` → `temperature` (`.rangeFraction`) | heat lamp |
| Magnet | `mic.envelope` → `magnet` (`.add`) | coil current |
| Gravity | `mic.envelope` → `gravity` (`.add(2)`) | as in Gyre |

Plus always-on physical routes, with no gate:
- `mag.delta` → `magnet` (`.normalize(500)`), so a real magnet stiffens the MR fluid;
- `motion.jerk` → `shakeImpulse` trigger;
- `device.thermal` → `temperature` (small depth; off by default).

Every route must have a **manual override**, per house rule 13: knobs always win, and depth 0 disables the route.

---

## 7. Simulator fake-sensor scheme

**Pattern (Gyre):**
- Every live source exposes `isLive` / `fake`, plus a deterministic synthetic generator.
- The generator feeds **the same downstream path**: the same ring, analyser and snapshot type.
- The UI shows an explicit simulated flag: the orange "Simulated motion. Drag outside the bubble to tilt." in the telemetry card (`TopBar.swift:144-149`).
- Without motion hardware, dragging outside the focus tilts the simulated phone (`GyroModel.swift:746, 753-755`).

| Argument | Reader (LabKit) | Effect | Gyre source |
|---|---|---|---|
| `-simSway` | `MotionSource.simSway` | yaw += 0.9 sin(0.31t), pitch += 0.3 sin(0.23t + 1), roll += 0.25 sin(0.17t). The base pose is pitch 60°; ω comes from the quaternion delta; the field is (0, 22, −40) µT in the world frame. | `MotionSource.swift:120-139` |
| `-fakeMic` | `MicListener.fake` | skips the permission prompt and the engine; synthetic room (§3.2) | `MicListener.swift:40, 59-63, 175, 188-211` |
| `-startMic` | the app's `start()` | mic on at launch | `GyroModel.swift:255` |
| `-fakeAR` / `-startAR` | `LabKitAR` (not prototyped) | synthetic camera, 62° FOV, procedural 256×512 YCbCr room. **Gated on `!ARWorldTrackingConfiguration.isSupported`.** | `ARController.swift:65-66, 284-335` |
| `-fakeRadio` | `LabKitRadio` (not prototyped) | 11 synthetic BLE radios, Wi-Fi, 5G | `RadioSense.swift:31, 52-57, 151-163` |
| **`-fakeMagnet`** (new) | `MotionSource.simMagnet` | adds `(0, 0, 2000 µT)·(0.5 + 0.5 sin(2πt/6))⁶`: a bar magnet swinging past every 6 s | prototype only |
| **`-fakeShake`** (new) | `MotionSource.simShake` | 0.4 s bursts of 12 Hz at ±1.2 g every 3 s on x | prototype only |

**Gating policy** (`LaunchOptions.fake(_:hardwareAvailable:)`): honour a fake flag in **DEBUG builds**, or whenever the real hardware is missing. This merges Gyre's `-fakeAR` hardware gate with the house rule "gate fakes behind `#if DEBUG`" (`design-house-rules.md §4`). A stray flag can then never fake a sensor in a Release build on the iPhone 15 Pro Max.

Launch example (simctl syntax as used for the smoke app):
`xcrun simctl launch booted com.utkarsh.rheo -simSway -fakeMic -startMic -fakeMagnet -fakeShake`.
**Verified:** the smoke app launched this way showed envelope 0.94 and gravity 2.13 g.

Still to add for Rheo: `-fakeTouch`, a scripted poke and stir path for deterministic screenshots and UI tests. Also add a "Sensor census" debug row (sdk-sensors §7) showing `MotionSource.measuredRate`.

---

## 8. Swift 6 strict concurrency

### 8.1 Verdict per module (prototype compiled in Swift 6 mode; app target with `SWIFT_STRICT_CONCURRENCY: complete`; 0 warnings)

| Module | Isolation choice | Swift 5 needed? | Why it is safe |
|---|---|---|---|
| LabKitCore | nonisolated default. Values are `Sendable`. `ParamStore` is `@MainActor @Observable`. `Spectrum` is a non-Sendable class confined to its owner. | No | pure values; `ParamSpec.format` is `@Sendable (Double) -> String`, which is what makes static spec tables legal |
| LabKitSensors | `MotionSource` and `MicListener` are `@MainActor`. `MicRing: Sendable` via `Mutex`. The tap is built in a `nonisolated static func`. | No | `installAudioTap`'s provider is `@Sendable`; the barometer handler runs on `.main`, so its MainActor-inferred closure is correct |
| LabKitFeedback | `HapticEngine`, `SynthHost` and `AudioRoute` are `@MainActor`. Handlers and render block are built in `nonisolated static` factories. `SynthControls: Sendable` uses `InlineArray<16, Atomic<UInt64>>`. Kernels are `@unchecked Sendable` (render-thread confined). | No | relaxed atomics are plain loads and stores on arm64; the `@unchecked` is justified because only `render` touches kernel state, serially |
| LabKitUI | `.defaultIsolation(MainActor.self)` | No | needs three escapes (8.4) |
| LabKitRender | `LabRenderer` is `@MainActor`, because `MTKViewDelegate` methods are `NS_SWIFT_UI_ACTOR` (`MTKView.h:260, 267`). `LineBatch` is a value. The completion handler captures only a `DispatchSemaphore`. AR textures go in `KeepAlive: @unchecked Sendable`. | No | |

### 8.2 The one real trap (verified in SIL)

The type `AVAudioSourceNodeRenderBlock` is `NS_SWIFT_NONSENDABLE` (`AVAudioSourceNode.h:41`). Any **non-Sendable closure formed inside a `@MainActor` method inherits MainActor isolation**. `$SCRATCH/isolation/iso.swift`, compiled with `-swift-version 6 -emit-sil`, shows:
- `closure #1 in BadSynth.build()` (the render block): `// Isolation: global_actor. type: MainActor`, **with a `swift_task_isCurrentExecutor` call at entry** (SIL lines 193-217).
- `closure #1 in BadSynth.tapOld()` (the deprecated `installTap` block): MainActor, **with an executor check** (line 402).
- `closure #1 in static GoodSynth.makeNode(_:)`: `nonisolated`, no check.
- `closure #1 in GoodSynth.tapNew()` (`installAudioTap`): `nonisolated`.

On the audio I/O thread, that check traps; this is the widely seen "_dispatch_assert_queue_fail" crash. **Rule: build every render, tap or callback block in a `nonisolated static func` (or mark it `@Sendable`).** Gyre gets away with it today only because its classes are nonisolated in Swift 5 mode.

Core Haptics handler closures assigned in a `@MainActor` method are also inferred MainActor (`iso2.swift`), but **no runtime check is emitted** for property assignment. A mistake there would be a silent data race, not a crash. Use `{ @Sendable [weak owner] in Task { @MainActor in … } }`, which is verified nonisolated.

### 8.3 What Gyre itself hits under Swift 6 (copy compiled with `-swift-version 6 -wmo -emit-sil`)

| Gyre location | Diagnostic | LabKit fix |
|---|---|---|
| `Knobs.swift:105, 189, 253` | error: static `[KnobSpec]` "not concurrency-safe" (key path + non-Sendable `format` closure) | `ParamSpec` is `Sendable` with an `@Sendable` format; no key path |
| `MicListener.swift:8` | error: `static var recording` is nonisolated global mutable state | `@MainActor enum AudioRoute` |
| `Haptics.swift:25, 29` | error: sending `self` risks causing data races (`DispatchQueue.main.async` in handlers) | §8.2 pattern |
| `MicListener.swift:76` | error: sending `self` / `changed` (permission callback) | `async` start using `await AVAudioApplication.requestRecordPermission()` |
| `RadioSense.swift:45` | error: capture of non-Sendable `self` in a `@Sendable` closure (`NWPathMonitor` handler) | for `LabKitRadio`: `@MainActor` class + `Task { @MainActor }` hop |
| `HumSynth.swift:60` | warning: non-Sendable `self` captured in the `@Sendable` observer closure | `@MainActor` host + `MainActor.assumeIsolated` (the observer queue is `.main`) |
| `HoloRenderer.swift:90, 142, 434, 690` | warnings: main-actor `MTKView` and `UIView` properties used from a nonisolated context | `@MainActor final class LabRenderer` |
| `HoloRenderer.swift:312` | warning: `[AnyObject]` captured in the `@Sendable` completion handler | `KeepAlive: @unchecked Sendable` |
| `HumSynth.swift:79`, `MicListener.swift:99` | silent today; **trap** once the owner becomes `@MainActor` (§8.2) | nonisolated factories / `installAudioTap` |

### 8.4 SwiftUI-module escapes under `defaultIsolation(MainActor)` (each was a compile error, then fixed)
- `Shape` conformers must be `nonisolated public struct KnobArc: Shape`. Otherwise: "conformance of 'KnobArc' to protocol 'Shape' crosses into main actor-isolated code".
- Token enums must be `nonisolated public enum LabTheme`, or shapes and renderers can't read `LabTheme.Knob.arcInset`.
- Tokens that call MainActor SwiftUI APIs (`Transition` builders) need an explicit `@MainActor public static var deck: some Transition`.

---

## 9. iOS 27 SDK deprecations and gotchas (header- or compile-verified unless noted)

| API | iOS 27 SDK state | LabKit uses |
|---|---|---|
| `AVAudioNode.installTap(onBus:bufferSize:format:block:)` | deprecated `ios(8.0, 27.0)` (`AVAudioNode.h:117`) | **`try installAudioTap(onBus:bufferSize:format:tapProvider:)`** (iOS 27; `@Sendable (AVReadOnlyAudioPCMBuffer, AVAudioTime)`; `channelData(i)` returns `.float(Span<Float>)`, which is `~Escapable`, so copy it inside the closure). Compiled; no warning. |
| `AVAudioEngine.connect(_:to:format:)` | deprecated (`AVAudioEngine.h:281`) | `try connectNode(_:to:format:)` (`:295`) |
| `AVAudioNode.auAudioUnit` | deprecated 27, "in favour of `withAUAudioUnit`" (AVFAudio.swiftinterface:64-77) | not used |
| `AVAudioSessionInterruptionNotification` + type/option keys | deprecated `ios(6.0, 27.0)` (`AVAudioSessionTypes.h:229, 331, 334`) | `AVAudioSession.didBecomeInactiveNotification` (`:316`) + `.resumptionRecommendationNotification` (`:321`); the reason key is now `AVAudioSessionDeactivationContext.interruptionDetails.reason` (`:337`) |
| `AVAudioSourceNode(format:realtimeSafeRenderBlock:)` | new in 27, **`__SWIFT_UNAVAILABLE`** (`AVAudioSourceNode.h:48, 88, 116`) | keep `renderBlock` |
| `AVAudioSessionCategoryOptionAllowBluetooth` | deprecated; replaced by `…AllowBluetoothHFP` (`AVAudioSessionTypes.h:501-502`) | `.allowBluetoothA2DP` only |
| `AVAudioPlayerNode.play()` | deprecated; replaced by `playAudio()` (from design-gyre; not re-checked) | not used |
| `UIScreen.main` | deprecated `ios(2.0, 26.0)` (`UIScreen.h:57`) | `view.window?.windowScene?.screen.currentEDRHeadroom` |
| `CMDeviceMotion.headingAccuracy`, `CMMotionManager.deviceMotionBody` | **new in iOS 27** (`CMDeviceMotion.h:147`, `CMMotionManager.h:334`) | not used yet |
| CoreHaptics / MetalKit / CoreMotion | no `27.0` deprecations (header grep count 0) | |
| `TabsPickerStyle` / `.pickerStyle(.tabs)` | `@available(iOS 27.0, macOS 27.0, …)`, unavailable on watchOS (`SwiftUI.swiftinterface:16490-16492`) | `KnobConsole` |
| Liquid Glass | `glassEffect`, `GlassEffectContainer`, `glassEffectID`, `.glass`, `.glassProminent`; no new glass API in 27 (memory note) | all compile in the prototype |
| `AnyTransition.blurReplace` | **doesn't exist**; `.blurReplace` is on `Transition` | use `some Transition` |
| `MTLRenderPipelineDescriptor.label = nil` | **asserts** in `MTLReportFailure` under the Simulator's Metal validation (crash log `Smoke-2026-10-03-154740.ips`) | `if let label { d.label = label }` |
| PackageDescription `.iOS(.v27)` | needs `swift-tools-version: 6.4` | |
| `UIRequiresFullScreen` | deprecated in iOS 26 (memory) | don't add it |

**SF Symbols.** These were checked against `/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist` (9,524 symbols on this macOS 27.2 host). Method: `plutil -convert json -o x.json <plist>`, then look up `symbols[name]`; the value is the release year.
- **`magnet` and `magnet.fill` do not exist.** Use `location.north.line.fill`, as Gyre does for Magnet.
- **`spoon` does not exist.**
- All 49 symbol names in Gyre's sources exist.
- Verified OK for Rheo: `drop`, `drop.fill`, `drop.halffull`, `drop.degreesign`, `drop.triangle`, `humidity.fill`, `water.waves`, `thermometer.medium`, `thermometer.snowflake`, `thermometer.sun`, `thermometer.variable`, `flame.fill`, `hourglass`, `tortoise.fill`, `hare.fill`, `hand.tap.fill`, `hand.draw.fill`, `hand.point.up.left.fill`, `hand.raised.fingers.spread.fill`, `hand.pinch.fill`, `waveform`, `waveform.path`, `waveform.path.ecg`, `waveform.badge.mic`, `speaker.wave.3.fill`, `metronome.fill`, `bolt.horizontal`, `circle.hexagongrid.fill`, `aqi.medium`, `bubbles.and.sparkles`, `flask.fill`, `testtube.2`, `atom`, `dial.medium.fill`, `hurricane`, `tornado`, `wind`, `gauge.with.needle`, `cup.and.saucer.fill`, `fork.knife`, `mug.fill`, `paintbrush.fill`, `paintpalette.fill`, `microbe.fill`, `allergens`, `scribble.variable`, `move.3d`, `iphone.gen3.radiowaves.left.and.right`, `iphone.motion`, `snowflake`, `sun.max.fill`, `globe.americas.fill`, `moon.fill`, `cube.transparent`, `square.3.layers.3d`.
- The CoreGlyphs file belongs to the Mac host, not the iOS SDK. Treat a 2024+ symbol as needing a device check (inferred).

**Layout gotchas learned in Gyre (memory, unchanged):**
- `.fixedSize()` on telemetry text inside the top bar overflowed the whole VStack sideways. Use `lineLimit(1)` + `minimumScaleFactor`.
- Additive line segments with round caps bead at polyline joints. LabKit's line vertex keeps butt caps (`Holo.metal:627-629`).

---

## 10. Metal: the shared shader library and how SwiftPM ships it

### 10.1 What moves into `LabKitRender/Shaders/` (prototype `P/LabKitRender/Shaders/LabKit.metal` + `LabKitShaderLib.h`)

| LabKit function (prefix `lab`) | From `Holo.metal` | Kind |
|---|---|---|
| `labFullscreenVertex` | `fullscreenVertex` `:188-194` | vertex |
| `labBackdropFragment` | `backgroundFragment` `:196-206` (sky window + focus glow + vignette) | fragment |
| `labLineVertex`, `labLineFragment` | `:595-651` | instanced line primitive (points are zero-length segments) |
| `labPrefilterFragment`, `labCopyFragment`, `labBlurFragment` | `:655-676` | bloom |
| `labCompositeFragment` | `:687-708` | aberration, bloom, scanlines, optional AR camera underlay, EDR soft-clip |
| header-only `static inline` helpers in `LabKitShaderLib.h`: `labToWorld`, `labHash13`, `labNoise`, `labFbm`, `labLineMask`, `labSky`, `labCameraColor`, `labSoftClip`, `labThinFilm` | `:55-123, 146-153, 242-257, 680-685` | for app shaders |
| samplers `labLinearClamp`, `labCubeSampler`, `labMipClamp` | `:49-51` | |
| **Candidates for a later `LabKitMaterials.metal`** (not prototyped): `environment()` + `studio()` IBL, `metalFragment` GGX/Smith/Schlick with anisotropic brushing, `oxideFilm`, `abrasion` | `:127-179, 346-430, 484-499` | |

`labSky` takes `world = (northAzimuth, hasNorth, …)` instead of Gyre's `u.film.zw`. It uses `fwidth`, so call it from fragment shaders only.

### 10.2 Shared layout header (`Sources/LabKitShaderTypes/include/LabKitShaderTypes.h`)

```c
typedef struct {
  simd_float4x4 viewProj;   // scene frame → clip
  simd_float4x4 attitude;   // scene frame → world (Z up); drives the world-anchored backdrop
  simd_float4 viewport;     // width, height, focus centre x, y (pixels)
  simd_float4 camera;       // focal (px), camera distance, time (s), EDR headroom
  simd_float4 post;         // bloom gain, scanline depth, chromatic aberration, reduce motion
  simd_float4 misc;         // focus radius (px), scan-band y, flicker gain, AR probe flag
  simd_float4 eye;          // eye position in the scene frame, AR flag
  simd_float4 camA;         // view → camera-image transform a, b, c, d
  simd_float4 camB;         // tx, ty, app slot, app slot
  simd_float4 world;        // north azimuth, has north, horizon glow, grid strength
} LabFrameUniforms;
typedef struct { simd_float4 a, b, ca, cb; } LabLineInstance;   // 64 bytes, same as Gyre's LineInstance
typedef struct { simd_float4 position, normal; } LabMeshVertex;
enum LabBufferIndex { LabBufferInstances = 0, LabBufferFrame = 1, LabBufferApp = 2 };          // vertex stage
enum LabFragmentBufferIndex { LabFragmentFrame = 0, LabFragmentApp = 1 };                         // fragment stage
```

Gyre-specific uniforms (`gravity`, `jiggle`, `film`, `lightA`, `lightB`, `ripples[4]`; `Holo.metal:13-23`) become **app uniforms at `LabBufferApp` / `LabFragmentApp`**.

Binding layout kept from Gyre:
- Lines: vertex buffer 0 = instances, buffer 1 = frame uniforms; drawn as a triangle strip of 4 vertices × instances, with `baseInstance`.
- Composite: fragment textures 0 scene, 1 bloom ½, 2 bloom ¼, 3 luma, 4 chroma; buffer 0 uniforms.
- Blur: fragment buffer 0 holds the `float2` texel step.

### 10.3 How the package ships it (each point verified)

1. **No manifest entry.** Xcode compiles every `.metal` in a SwiftPM target into `<Package>_<Target>.bundle/default.metallib`. The prototype produced `LabKit_LabKitRender.bundle/default.metallib`, 45,912 bytes. `metal-nm` lists all 8 `lab*` functions. The `.h` sitting beside it caused no warning.
2. **Runtime load:** `try device.makeDefaultLibrary(bundle: .module)`. The XCTest `ShaderBundleTests.testPackageMetallibLoads` passed on the iPhone 17 Pro simulator, and the smoke app renders with it.
3. **The bundle is embedded in the app** next to the app's own `default.metallib`, with no clash: `Smoke.app/LabKit_LabKitRender.bundle/default.metallib` and `Smoke.app/default.metallib`.
4. **Includes:** the package's Metal compile does **not** get the dependency C target's include directory. `#include "LabKitShaderTypes.h"` failed with "file not found". Use the relative `#include "../../LabKitShaderTypes/include/LabKitShaderTypes.h"` in both `LabKit.metal` and `LabKitShaderLib.h`; quoted includes resolve relative to the including file. Swift imports the same header through the C target (`import LabKitShaderTypes`).
5. **App shaders** reuse LabKit helpers and types through XcodeGen target settings:
   `MTL_HEADER_SEARCH_PATHS: "$(SRCROOT)/../LabKit/Sources/LabKitRender/Shaders $(SRCROOT)/../LabKit/Sources/LabKitShaderTypes/include"`, then `#include "LabKitShaderLib.h"`. Verified with `Smoke.metal`. Helpers are `static inline` so several app `.metal` files can include them without duplicate symbols.
6. **Mixing libraries in one pipeline works:** `PipelineFactory.make(vertex: "labFullscreenVertex", fragment: "smokeTankFragment", fragmentLibrary: device.makeDefaultLibrary()!, …)` rendered correctly on screen (`smoke2.png`).
7. `swift build` (SwiftPM command line) **cannot** compile the Metal target ("missing Metal Toolchain"), while xcodebuild can. That is why `LabKitCore` must stay Metal-free.

### 10.4 Notes for Rheo's 2.5D fluid shading (inferred, not built)
- **Refraction of what lies behind the fluid.** Use Gyre's glass-orb two-pass:
  1. Draw the backdrop and everything behind the fluid.
  2. Blit to the mipmapped `behind` texture and `generateMipmaps` (`HoloRenderer.swift:369-377`; `RenderTargets(wantsBehind: true)`).
  3. Draw the fluid sampling `behind`, offset along the screen-space normal of the thickness field.
  - Use per-channel offsets for dispersion and mip LOD for turbidity (`glassOrbFragment`, `Holo.metal:504-561`: `bend = refraction·(0.01 + 0.12·rim^2.2)`, `spread = dispersion·(0.2 + 1.3·rim)`, `lod = 0.4·frost + scuff·5`).
  - Oobleck is milky: high LOD. Honey is clear and amber: low LOD with an absorption tint.
- Specular and Fresnel: the bubble film's `pow(nh, 1400)` glints from world-anchored lights (`Holo.metal:286-290`). The lights are `inverse.act(V3(0.25, −0.45, 0.86))` × 1.1 and `(−0.7, 0.5, 0.2)` × 0.45 (`HoloRenderer.swift:699-700`), so glints slide as you tilt.
- Keep fluid and solid colour below the 0.8 soft-clip knee, so only intended highlights glow into EDR.
- `LayoutCamera.orthographic` maps tank units (y ∈ [−1, 1], 1 unit = half the region height) onto the eased canvas region. The smoke app's tank used the perspective camera, so the orthographic path compiles but has **not been looked at on screen**.

---

## 11. Tooling for LabKit-based apps

**Build mirror.** `xcodebuild` hangs inside the iCloud folder, and a local package path is relative (`../LabKit`), so mirror **both** directories with the same layout. This generalises `Gyre/Tools/build.sh:1-20`:

```zsh
#!/bin/zsh
# Rheo/Tools/build.sh — mirror Rheo + LabKit out of iCloud, then build.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"          # …/AI Stuff
WORK="${RHEO_BUILD_DIR:-${TMPDIR:-/tmp}/RheoBuild}"
mkdir -p "$WORK/src"
rsync -a --delete --exclude '.build' "$ROOT/LabKit/" "$WORK/src/LabKit/"
rsync -a --delete --exclude 'Rheo.xcodeproj/xcuserdata' "$ROOT/Rheo/" "$WORK/src/Rheo/"
cd "$WORK/src/Rheo"; xcodegen generate --quiet
case "${1:-sim}" in
  sim)    xcodebuild -project Rheo.xcodeproj -scheme Rheo -configuration Debug \
            -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$WORK/dd" build ;;
  device) xcodebuild -project Rheo.xcodeproj -scheme Rheo -configuration Release \
            -destination 'generic/platform=iOS' -allowProvisioningUpdates -derivedDataPath "$WORK/dd" build ;;
  test)   (cd "$WORK/src/LabKit" && xcodebuild test -scheme LabKit-Package \
            -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$WORK/dd-labkit") ;;
esac
```

**XcodeGen** (verified with `SmokeApp/project.yml`):

```yaml
packages:
  LabKit:
    path: ../LabKit
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
targets:
  Rheo:
    dependencies:
      - { package: LabKit, product: LabKitCore }
      - { package: LabKit, product: LabKitSensors }
      - { package: LabKit, product: LabKitFeedback }
      - { package: LabKit, product: LabKitUI }
      - { package: LabKit, product: LabKitRender }
    settings:
      base:
        MTL_FAST_MATH: YES
        MTL_HEADER_SEARCH_PATHS: "$(SRCROOT)/../LabKit/Sources/LabKitRender/Shaders $(SRCROOT)/../LabKit/Sources/LabKitShaderTypes/include"
```

Info keys (carry over from Gyre's `project.yml:20-40` and keep them in `project.yml`):
- `UIUserInterfaceStyle: Dark`, `UIStatusBarHidden: true`, portrait only, `CADisableMinimumFrameDurationOnPhone: true`, `ITSAppUsesNonExemptEncryption: false`, `UILaunchScreen.UIColorName: LaunchBackground`.
- `NSMicrophoneUsageDescription`, worded in Gyre's voice: "Rheo listens so sound can shake the fluid. Nothing is recorded or kept."
- `NSMotionUsageDescription`, only if the barometer is used.
- **Run `xcodegen generate` in the source tree whenever `project.yml` changes.** Gyre's checked-in `Info.plist` drifted from its `project.yml` (section 1).

**Harnesses:**
- `swift run -c release labkit-physcheck` runs in LabKit (Mac, seconds once warm).
- Rheo should add `Tools/rheocheck`, built on `PhysCheck`, against its CPU reference solver. Example checks: Bingham plug width, power-law velocity profile, Maxwell relaxation time, thixotropic recovery curve, Newtonian Poiseuille flow, energy decay.
- XCTest via `xcodebuild test -scheme LabKit-Package`.

---

## 12. Verified vs inferred

**Verified (by building, running or reading source in this session):**
- Every Gyre value and `file:line` quoted above was re-read from current source (3 October 2026, ~15:11 state).
- Gyre's physcheck: 8/8 PASS.
- `installAudioTap` exists in the iOS 27 AVFAudio module (swiftinterface:63). It compiles with `.float(Span)` access and no warning.
- `AVAudioSourceNodeRenderBlock` is `NS_SWIFT_NONSENDABLE`. MainActor inference plus an executor check on render and tap closures formed in `@MainActor` methods is shown in SIL. Nonisolated factories and `@Sendable` closures avoid it.
- Gyre under Swift 6 produces the diagnostics listed in §8.3.
- The LabKit prototype (Swift 6, 7 targets + harness + tests) builds for the iOS Simulator with 0 warnings. `xcodebuild test` passes 3/3 on the iPhone 17 Pro simulator. The Mac harness passes 9/9 checks.
- The SwiftPM `.metal` produces `default.metallib` in the resource bundle; it loads via `Bundle.module` at runtime; and the app bundle embeds it.
- The relative include is required; `MTL_HEADER_SEARCH_PATHS` works for app shaders; mixed-library pipelines work.
- `swift build` cannot compile Metal on this host.
- A Swift 6 strict-concurrency app (the smoke app) builds and runs with LabKit, shown in the screenshot: telemetry 2.13 g, consistent with 1 + 0.6·0.94·2.
- `.iOS(.v27)` needs tools-version 6.4.
- `TabsPickerStyle` is iOS 27-only.
- The iOS 27 audio-session notifications, `AllowBluetooth`, `realtimeSafeRenderBlock` (Swift-unavailable), `headingAccuracy` and `deviceMotionBody` were all checked in the headers. `UIScreen.main` was deprecated in 26.
- SF Symbol names were checked against CoreGlyphs (`magnet` and `spoon` are missing).
- Metal validation asserts on `label = nil`.
- `AnyTransition.blurReplace` doesn't exist.
- The `KnobArc` and `LabTheme` isolation errors under `defaultIsolation(MainActor)` were seen and fixed.

**Inferred (not tested):**
- Real-device behaviour of everything new: `installAudioTap` delivery size on the iPhone 15 Pro Max, `Atomic` controls under real audio load, haptic feel at `strength` 0.85, and EDR on the device.
- `LabKitAR` and `LabKitRadio` Swift 6 ports (designs given, not compiled).
- The orthographic camera path on screen.
- The Rheo drive mapping, the MPM CFL substep advice and fluid refraction (§5, §6.2, §10.4).
- That Mac CoreGlyphs availability matches iOS 27 for 2024+ symbols.

---

## 13. Open questions and risks for implementers

1. **Main-thread blocking.** The frame loop (and `inflight.wait()`) runs on the main thread. A heavy MPM compute load will stall UI gestures before it drops frames. Measure on the A17 Pro first, and give `LabRenderer` a frame budget or adaptive substeps.
2. **Two LabKit efforts may be running.** A "LabKit Probe" app is installed on the shared iPhone 17 Pro simulator, apparently from another session. Agree on one package API (this note's prototype is one candidate) before Rheo code lands, to avoid divergence.
3. **Gyre is not migrated.** LabKit is lifted, not adopted. Leave Gyre as is unless the user asks. A migration would rename `KnobSpec` to `ParamSpec`, swap in `HapticEngine` and `SynthHost` with a `RotorHumKernel`, and move the bubble shaders to app-side files that `#include "LabKitShaderLib.h"`.
4. **`@unchecked Sendable` kernels** depend on AVAudioEngine calling a source node's render block serially. That is standard Core Audio behaviour, but not documented in the header.
5. **Fakes in Release** are blocked by the gating policy. UI tests that run against Release would need a `-ui-testing` exception (house rule).
6. **The prototype lives in scratch.** Copy `$SCRATCH/LabKitProto/` to `/path/to/developer/Documents/AI Stuff/LabKit/` (minus `.build/`) as the starting point. Its file and type names match this note exactly.
