# LabKit + Rheo: architecture contract

Date: 3 October 2026. Status: **binding for implementation**. This file is the contract between the work packages that build LabKit (the shared toy engine) and Rheo (the non-Newtonian toy). Where it is silent, follow the research notes in `Rheo/Documentation/research/`, in this order of authority:

| Topic | Authority |
|---|---|
| Constitutive equations, presets, verification cases V1–V14, honesty notes | `rheology-models.md` §4–§8 and Appendices A–C |
| GPU solver (PB-MPM port, kernels, fixed point, substep rule Π ≤ 0.07, colliders, impulses, renderer) | `mpm-metal.md`; starting code in `$MC/pbmpm-metal/` |
| LabKit Core/Sensors/Feedback/Render APIs, frame loop, drives, fakes, Swift 6 rules | `labkit-from-gyre.md`; starting code is the current `LabKit/` (seeded from LabKitProto) |
| Design tokens, components, haptics/sound policy, copy, Rheo screen layout | `labkit-from-orbitals-spectra.md` (its §1.3 lists the 20 changes to apply to the prototype; §9 is Rheo's screen) |
| Box2D vendoring, provenance files, threading | `oss-integration-lessons.md` §4–§5 |
| Package/XcodeGen/Metal toolchain facts | `toolchain-checks.md` |
| Why this solver, licences | `oss-engine-survey.md` (revision 2) |

`$SCRATCH` = `/private/tmp/claude-501/-Users-utkarsh-Documents-AI-Stuff/b53a2b83-9308-4477-a9dd-fedd258cad75/scratchpad`; `$MC` = `$SCRATCH/mpm-metal-check`.

---

## 0. What we are building

- **LabKit** (`AI Stuff/LabKit`): one local SwiftPM package that gives every toy app the same look, feel and physics plumbing: design tokens and Liquid Glass chrome, glass knobs and consoles, haptics and a synth host, sensors with simulator fakes, parameters and the modulation ("drives") router, integrators, a Metal render host with bloom/EDR, a Box2D rigid-body wrapper, and a 2D MPM continuum engine (GPU solver + CPU oracle + fluid surface renderer).
- **Rheo** (`AI Stuff/Rheo`, display name **Rheo**, subtitle "Non-Newtonian Toy", bundle `com.utkarsh.rheo`): an iOS 27 iPhone app. A thin glass tank of fluid, drawn life-size, that you poke, punch, stir, tilt, shake, shout at, heat, magnetise and slow down. 13 materials (Water-like, Honey, Ketchup, Mayonnaise, Toothpaste, Oobleck, Slime, Silly Putty, Yogurt, Quicksand, MR fluid, Paint, Lava) can share the tank, and rigid props (Box2D) sink, float and bounce in them.

**Non-goals for v1:** migrating Gyre, Orbitals or Spectra onto LabKit (LabKit is lifted from them, not yet adopted by them); AR; 3D; iPad; landscape; networking.

## 1. Global rules (every work package)

1. **Never build inside iCloud.** `xcodebuild` and SwiftPM hang or misbehave in `AI Stuff`. Use `LabKit/Tools/lk.sh <your-work-name> <command…>` for package work (it mirrors LabKit to `$TMPDIR/labkit-<work-name>/LabKit`). Use a unique work name per package so parallel builds never share a mirror. Rheo builds use `Rheo/Tools/build.sh` (mirrors LabKit and Rheo side by side).
2. **Metal on the host** needs `TOOLCHAINS=metal` for `swift build/test/run` (the default toolchain's `metal` is a stub). xcodebuild compiles Metal without it.
3. **Swift 6, strict concurrency complete.** Every closure that runs off the main thread (audio render block, audio tap, Core Motion handlers, Core Haptics handlers, Metal completion handlers) is built in a `nonisolated static` factory or marked `@Sendable` (`labkit-from-gyre.md` §8.2 — a MainActor-inferred audio closure compiles silently and crashes). No Swift 5-mode islands.
4. **iOS 27 only, iPhone portrait.** Gate simulator-only fakes with `LaunchOptions` (DEBUG builds or missing hardware). `#if os(iOS)` around UIKit/Core Motion/AVAudioSession code so LabKitCore, LabKitMPM, LabKitMPMReference and LabKitRigid build and test on macOS.
5. **Ownership.** Edit only the files your package owns (§2). `LabKit/Package.swift` belongs to the integrator: you may change only your own target's `swiftSettings`/`cSettings`/`resources`/`exclude`. If you need something else, say so in your report.
6. **Provenance.** Ported or vendored code keeps its licence header and gets an entry in `LabKit/THIRD_PARTY_NOTICES.md` (create if missing; same format as `Powder Modernization/Native/THIRD_PARTY_NOTICES.md`) plus `UPSTREAM.md`/`UPSTREAM.json` next to vendored sources.
7. **Units.** Public APIs take SI (metres, seconds, kilograms, pascals, kelvin, tesla) in `Double` on the CPU side; GPU structs are `Float` in solver units, converted in one place.
8. **Copy.** British spelling, plain words, "oobleck" in the UI. Honest provenance: every displayed value is tagged measured/modelled/illustrative/simulated where the component supports it.
9. **Tests.** XCTest (house rule: no Swift Testing) for unit tests; `PhysCheck`-style Mac harnesses for physics. Every claim in a report must say whether it was built, run, or only written.
10. **SF Symbols**: check names against `/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist` (`magnet`, `spoon` do not exist).

## 2. Layout and ownership

```
LabKit/
  Package.swift                     integrator
  THIRD_PARTY_NOTICES.md            WP-R (Box2D) and WP-G (PB-MPM) append their sections
  README.md                         WP-C writes; others append their module section
  Tools/lk.sh                       integrator
  Sources/
    LabKitCore/                     WP-C   (ContinuumMaterial.swift: integrator-owned contract file; WP-O adds ContinuumPresets.swift)
    LabKitSensors/                  WP-C
    LabKitFeedback/                 WP-C
    LabKitUI/                       WP-C
    LabKitShaderTypes/              WP-C
    LabKitRender/                   WP-C
    CBox2D/                         WP-R   (vendored Box2D v3.1.1 + module.modulemap + UPSTREAM files + LICENSE)
    LabKitRigid/                    WP-R
    LabKitMPMTypes/                 WP-G   (C header(s) shared by Swift and MSL: particle, constants, shape, material, stats)
    LabKitMPM/ (+ Shaders/)         WP-G   (solver, surface renderer, Swift host)
    LabKitMPMReference/             WP-O   (CPU Double oracle)
    LabKitPhyscheck/main.swift      WP-O   (Core checks from the prototype stay; add V1–V13)
    LabKitGPUCheck/main.swift       WP-G   (GPU solver checks + V14 parity against WP-O's oracle)
  Tests/
    LabKitCoreTests, LabKitRenderTests   WP-C
    LabKitRigidTests                     WP-R
    LabKitMPMTests                       WP-G
    LabKitMPMReferenceTests              WP-O
Rheo/                               wave 2 (WP-A*), §6
```

Wave 1 runs WP-C, WP-R, WP-G and WP-O in parallel. Wave 2 builds Rheo on the APIs wave 1 actually shipped.

## 3. WP-C: LabKit chrome, feedback, sensors, render host

Start from the seeded prototype in `LabKit/Sources` (it builds, 0 warnings). Apply:

- `labkit-from-orbitals-spectra.md` §1.3 (the 20 changes) and §2–§8: palette mechanism (per-app accent + parameter hues), `InstrumentPanel`, `Readout`/`ReadoutGrid`/`ProvenanceBadge`, `ParamSpec` changes (`icon`, `ParamFormat`, lower-bound quantisation), `GlassKnob` with `KnobFocus` + keyboard + VoiceOver adjustable, rotary switch, `GlassToggle`/`ChoiceChips`/`GlassTile`, `KnobConsole(… open: nil, uniformHeight: true)`, `LabTopBar`/`ToolbarGlyph`/`TelemetryCard`/`TelemetryHeadline`/`StatusBanner`, `LabInfoSheet` + field notes + `Citation` + provenance, `ExperimentMenu` + `Experiment` model, `LabPlot` (log-log axes, curves, scatter, cursor, guides with label culling), `CanvasRegion`, `PermissionGate`, `FeedbackSettings`, `LabMetrics.millimetresPerPoint` (model-identifier table; `iPhone16,2` → 0.16565), accessibility and Reduce Motion rules.
- Haptics policy (§5 of that note): transients + causal hum (idle 8 s, fade 0.25 s), Strength 0.2–1 (default 0.85), stop rules, the tap vocabulary. Sound policy (§6): `SynthHost` + `SynthKernel` (Rheo writes its own kernel), cues paired with haptics, mic ducking.
- Sensors: `MotionSource` (+ `-simSway`, `-fakeMagnet`, `-fakeShake`, `simulatedTilt`), `MicListener` (`installAudioTap`, `Mutex` ring, `-fakeMic`, `-startMic`), `LaunchOptions`, thermal state source.
- **Render host extension for refraction (required by Rheo):** `LabRenderScene` gains a two-phase scene so a refractive layer can sample what lies behind it:
  ```swift
  @MainActor public protocol LabRenderScene: AnyObject {
    // … existing members (isRunning, reduceMotion, canvasRegion, projection, drawsBackdrop, advance(dt:), buildLines, fillUniforms) …
    /// Compute and offscreen passes on the frame's command buffer, before any scene pass (Rheo: MPM substeps, fluid splat/blur).
    func encodeCompute(_ cmd: MTLCommandBuffer, context: LabFrameContext)
    /// Opaque layer drawn after the backdrop, before the `behind` copy (Rheo: tank back wall, props behind the fluid).
    func encodeBehind(_ enc: MTLRenderCommandEncoder, uniforms: inout LabFrameUniforms, context: LabFrameContext)
    /// Layers drawn after the `behind` mip copy; may sample `context.targets.behind` (Rheo: fluid shade, front glass, overlays).
    func encodeScene(_ enc: MTLRenderCommandEncoder, uniforms: inout LabFrameUniforms, context: LabFrameContext)
    var wantsBehindCopy: Bool { get }   // default false: one scene pass, as before
  }
  ```
  The renderer splits the scene pass when `wantsBehindCopy` is true: pass 1 (backdrop + `encodeBehind`) → blit to the mipmapped `behind` texture + `generateMipmaps` → pass 2 (load, `encodeScene`, lines) → `PostChain`. Scene colour stays `rgba16Float`, depth `depth32Float`. `LayoutCamera.orthographic` must be checked on screen (it never has been).
- **Frame budget**: at most 2 frames in flight, non-blocking `wait(timeout: .now())` (skip the frame rather than block the main thread), `ProcessInfo.thermalState` / Low Power → 60 fps cap.
- Deliver: package builds for iOS Simulator and device with 0 warnings; `LabKitCoreTests` + `LabKitRenderTests` pass; `labkit-physcheck` core checks pass; a short `LabKit/README.md` (module map, how an app adopts LabKit, launch arguments, build commands).

## 4. WP-R: Box2D + LabKitRigid

- Vendor **Box2D v3.1.1** (MIT, commit `8c661469c9507d3ad6fbd2fea3f1aa71669c2fe3`) verbatim into `Sources/CBox2D` (`src/`, `include/box2d/`, `LICENSE`, hand-written `include/module.modulemap` exporting `box2d/box2d.h`), with `UPSTREAM.md` + `UPSTREAM.json` (commit, tag, archive SHA-256, file manifest hash) and a THIRD_PARTY_NOTICES section (`oss-integration-lessons.md` §4).
- `LabKitRigid` uses `internal import CBox2D` and exposes SI value types. Contract (names may grow, not shrink):
  ```swift
  public struct RigidBodyID: Hashable, Sendable
  public enum RigidShape: Sendable { case circle(radius: Double), box(halfWidth: Double, halfHeight: Double), capsule(halfLength: Double, radius: Double), polygon([SIMD2<Double>]) }
  public enum RigidBodyKind: Sendable { case dynamic, kinematic, fixed }
  public struct RigidBodySpec: Sendable { var kind; var shape; var position: SIMD2<Double>; var angle: Double; var density: Double /* kg/m² (2D) */; var friction: Double; var restitution: Double; var linearDamping: Double; var angularDamping: Double; var enableSleep: Bool = false; var userTag: Int }
  public struct RigidPose: Sendable { var position: SIMD2<Double>; var angle: Double; var velocity: SIMD2<Double>; var angularVelocity: Double }
  public final class RigidWorld {           // not Sendable; confined to the simulation's isolation domain (main actor in Rheo)
    public init(gravity: SIMD2<Double>, lengthUnitsPerMetre: Double = 0.1)   // b2SetLengthUnitsPerMeter once per process, never changed
    public var gravity: SIMD2<Double>
    public func add(_ spec: RigidBodySpec) -> RigidBodyID
    public func remove(_ id: RigidBodyID); public func removeAll()
    public func addWalls(width: Double, height: Double, thickness: Double)    // static tank walls, origin bottom-left
    public func pose(_ id: RigidBodyID) -> RigidPose
    public func setTarget(_ id: RigidBodyID, position: SIMD2<Double>, angle: Double, dt: Double)  // kinematic tools
    public func applyImpulse(_ id: RigidBodyID, linear: SIMD2<Double>, angular: Double)          // fluid → body, at the COM
    public func applyForce(_ id: RigidBodyID, _ f: SIMD2<Double>)                                   // e.g. magnet on a steel ball
    public func step(dt: Double, subSteps: Int = 4)
    public var bodies: [RigidBodyID] { get }
    public func shape(_ id: RigidBodyID) -> RigidShape
    public func mass(_ id: RigidBodyID) -> Double
    public func query(point: SIMD2<Double>) -> RigidBodyID?                                        // pick a prop under a finger
  }
  ```
  2D density is per unit area; the app converts from kg/m³ × the tank gap. Bodies coupled to fluid use `enableSleep = false`.
- Tests (serialised suite; Box2D has process-global state): free fall vs ½gt² (≤ 0.5 %), resting box height, restitution bounce, kinematic target tracking, impulse → Δv = J/m, buoyancy-style force balance using `applyForce`. Build for iOS Simulator + device with 0 warnings.

## 5. WP-G: LabKitMPM (GPU solver + surface renderer) and WP-O: LabKitMPMReference (CPU oracle)

### 5.1 Physics (both packages)

- **Grid/transfer:** 2D MLS-MPM/APIC with quadratic B-splines, 2×2 particles per cell, the PB-MPM fused `g2p2g` tile infrastructure on the GPU (bukkit size 6, int32 fixed point 2²⁴ round-to-nearest, overflow counter, exact grid clearing), grid-volume J correction.
- **Material update:** the unified EVP model of `rheology-models.md` §4(a) on the CPU, and the same update run as a compliant constraint inside PB-MPM iterations on the GPU (§4(b), Appendix C). **With iterations k = 1 and ω = 0 the GPU path is explicit MLS-MPM and must match the oracle (V14).** One parameter type, `ContinuumMaterial` (LabKitCore), drives both. Per-particle state: isochoric elastic b̄ₑ (or Fe), J, λ (structure), f (contact fraction), T, last γ̇ₚ, plus diagnostics (σ̄, γ̇, η_secant) for rendering and the rheometer.
- **Substeps:** the largest of Π = g·dt²·H/Δx² ≤ 0.07, ≤ 1 cell of travel per substep, ≥ 8 substeps per vibration period, and the elastic wave rule c·dt/Δx ≤ √(k/2). Above the per-frame cap, simulated time slows (report `lagging`). Iterations default 3.
- **Body forces and stimuli:** gravity vector (tilt × Gravity knob), frame acceleration (−user acceleration, for shakes), floor vibration (amplitude g, frequency Hz, applied as a moving floor or an oscillating body force), Hele-Shaw drag with the gap-averaged power-law viscosity (`rheology-models.md` §4.9), temperature (per-particle T relaxing to ambient, Arrhenius), magnetic field H (uniform measured field + an optional virtual magnet position), Kelvin body force for MR fluid.
- **Resolution:** domain 71.2 × 101.4 mm by default (life-size tank on the 15 Pro Max), Δx selectable: 2.0 mm (default, 120 Hz), 1.6 mm (60 Hz quality), 1.1 mm (Mac/benchmarks). Expose particle capacity ≥ 40 k.

### 5.2 LabKitMPM public API (WP-G; wave 2 codes against this)

```swift
public struct MPMDomain: Sendable { public var size: SIMD2<Double> /* m */; public var cellSize: Double /* m */; public var heleShawGap: Double /* m, 0 = off */ }
public struct MPMQuality: Sendable { public static let standard /* Δx 2.0 mm */, high /* 1.6 mm */, bench /* 1.1 mm */; public var cellSize: Double; public var maxSubsteps: Int; public var iterations: Int }

public struct MPMCollider: Sendable {          // a shape the fluid feels, in metres (tank frame, origin bottom-left, y up)
  public enum Shape: Sendable { case circle(radius: Double), box(halfSize: SIMD2<Double>), capsule(halfLength: Double, radius: Double) }
  public var shape: Shape; public var position: SIMD2<Double>; public var angle: Double
  public var velocity: SIMD2<Double>; public var angularVelocity: Double; public var friction: Double
  public var bodyIndex: Int?                    // 0..<16: accumulate fluid impulses for this collider (props, finger)
}
public struct MPMEmitter: Sendable { public var position: SIMD2<Double>; public var radius: Double; public var velocity: SIMD2<Double>; public var material: Int; public var rate: Double /* particles/s */ }
public struct MPMFrameInput: Sendable {
  public var dt: Double                         // simulated seconds this frame (already × time scale, ≤ 1/15)
  public var gravity: SIMD2<Double>             // m/s², tank frame
  public var frameAcceleration: SIMD2<Double>   // m/s², the tank's own acceleration (shake); fluid feels −a
  public var vibration: (amplitude: Double /* m/s² */, frequency: Double /* Hz */)
  public var ambientTemperature: Double         // K
  public var magneticField: SIMD2<Double>       // H, A/m, tank frame (uniform)
  public var magnet: (position: SIMD2<Double>, strength: Double /* A/m at 1 cm */)?
  public var colliders: [MPMCollider]           // ≤ 32 (tank walls are implicit)
  public var emitters: [MPMEmitter]             // pour
  public var drains: [(position: SIMD2<Double>, radius: Double)]  // scoop/erase
  public var probe: SIMD2<Double>?              // where the rheometer samples (finger or strongest shear)
}
public struct MPMStats: Sendable {              // from the latest *completed* frame (1–2 frames old)
  public var liveParticles: Int; public var maxSpeed: Double; public var kineticEnergy: Double
  public var meanViscosity: Double              // Pa·s, mass-weighted secant viscosity of the yielded fluid
  public var yieldedFraction: Double; public var jammedFraction: Double; public var volumeRatio: Double
  public var probe: (shearRate: Double, stress: Double, viscosity: Double, solidFraction: Double)
  public var bodyImpulses: [SIMD3<Double>]      // per bodyIndex: (Jx, Jy, angular), N·s (per metre of gap × gap)
  public var substeps: Int; public var lagging: Bool; public var overflowCount: Int; public var nanCount: Int
  public var gpuMilliseconds: Double
}
public final class MPMSolver {                  // used from the main actor in Rheo; not Sendable
  public init(device: MTLDevice, domain: MPMDomain, quality: MPMQuality, capacity: Int) throws
  public var materials: [ContinuumMaterial]     // ≤ 16; index = particle material id
  public func fill(rect: CGRect /* m */, material: Int, temperature: Double)   // seeds 2×2 per cell, at rest
  public func fill(polygon: [SIMD2<Double>], material: Int, temperature: Double)
  public func clear()
  public func setQuality(_ q: MPMQuality)       // resamples the current fluid onto the new grid
  public func encode(into cmd: MTLCommandBuffer, input: MPMFrameInput)          // all substeps for this frame
  public private(set) var stats: MPMStats
  public var particleBuffer: MTLBuffer { get }; public var particleCount: Int { get }
  public var debugValidation: Bool              // NaN/overflow checks every frame (DEBUG default on)
}

public struct FluidLook: Sendable { /* per material: base colour, absorption, opacity/turbidity, roughness, specular, subsurface, emission-from-temperature, grain */ }
public enum FluidDiagnostic: Int, Sendable { case none, shearRate, viscosity, stress, structure, jam, temperature, speed }
public struct FluidRenderOptions: Sendable { public var diagnostic: FluidDiagnostic; public var glow: Float; public var grain: Float; public var tracers: Float; public var depth: Float; public var showParticles: Bool }
public final class MPMSurfaceRenderer {
  public init(device: MTLDevice, colorFormat: MTLPixelFormat /* .rgba16Float */, depthFormat: MTLPixelFormat /* .depth32Float */) throws
  public var looks: [FluidLook]                 // index = material id
  /// Half-resolution splat + blur passes into its own textures. Call from `encodeCompute`, after `MPMSolver.encode`.
  public func encodePrepass(_ cmd: MTLCommandBuffer, solver: MPMSolver, tankToClip: simd_float4x4, drawableSize: SIMD2<Int>, options: FluidRenderOptions)
  /// Full-resolution shade inside the scene's second pass; samples the mipmapped `behind` texture for refraction.
  public func encodeShade(_ enc: MTLRenderCommandEncoder, behind: MTLTexture, tankToClip: simd_float4x4, time: Float, options: FluidRenderOptions)
}
```

Deliver (WP-G): the shaders under `Sources/LabKitMPM/Shaders/` (ported from `$MC/pbmpm-metal/`, keeping EA's BSD-3 notice), shared structs in `Sources/LabKitMPMTypes/include/` (MSL includes them by relative path), the API above, `LabKitMPMTests` (determinism, mass conservation, binning, no NaN/overflow on a dam break, buoyancy via `bodyImpulses`, `fill` counts), `labkit-gpucheck` (dam break timings, Π-volume table, material slump shapes for Honey/Toothpaste/Ketchup/Oobleck punch, V13 viscosity, V14 parity vs the oracle), and an iOS Simulator build with 0 warnings. Simulator GPU limits: 512 threads per group, 16 KB threadgroup memory, SIMD-group functions unverified → provide the fallback path the note describes and select it at runtime.

### 5.3 LabKitMPMReference public API (WP-O)

```swift
public struct EVPState: Sendable { public var b11, b12, b22, J, structure, contact, temperature, plasticRate: Double }
public enum EVP {                               // the single-particle constitutive update, Double
  /// Advances one particle's state over dt given velocity gradient C (c11 = ∂vx/∂x, c12 = ∂vx/∂y, c21, c22) and |H|; returns Kirchhoff stress (t11, t12, t22).
  public static func update(_ s: inout EVPState, velocityGradient c: simd_double2x2, dt: Double, material: ContinuumMaterial, fieldMagnitude: Double) -> SIMD3<Double>
}
public struct ReferenceScene: Sendable { /* domain, Δx, periodic flags per axis, walls, body force(t), particles with material ids */ }
public final class ReferenceSolver2D {          // explicit MLS-MPM, quadratic B-splines, 2×2 ppc, Double
  public init(scene: ReferenceScene, materials: [ContinuumMaterial])
  public func step(dt: Double)
  public var particles: [ReferenceParticle] { get }   // x, v, C, state, material, mass, volume
  public func gridVelocity(atRow:) …                   // profile helpers for V2–V5
}
public enum ContinuumPresets { public static let waterLike, honey, ketchup, mayonnaise, toothpaste, oobleck, slime, sillyPutty, yogurt, quicksand, mrFluid, paint, lava: ContinuumMaterial; public static let all: [(name: String, material: ContinuumMaterial)] }
```

`ContinuumPresets` lives in **LabKitCore** (`ContinuumPresets.swift`, WP-O writes it first, from `rheology-models.md` §6 and `$SCRATCH/rheology/calc/presets2.json`), so the GPU package and Rheo use the same values. Deliver: `LabKitMPMReferenceTests` (fast unit tests: V6, V7, V8, V10, V12 at constitutive level) and `labkit-physcheck` running V1–V10 + V12 with the tolerances in the rheology note (resolution-aware where it says so), printing a PASS/FAIL table; record measured numbers in `LabKit/Documentation/VERIFICATION-MPM.md`.

## 6. Rheo app (wave 2; outline, refined after wave 1)

- **Frame loop:** `RheoModel` (`@MainActor @Observable`) is the `LabRenderScene`. `advance(dt)`: sample motion → snapshot params → mic + sources → drives router → build `MPMFrameInput` (gravity = screen gravity × Gravity knob; frame acceleration from user acceleration; vibration from Shake/Rate knobs + mic drive; temperature from Heat; field from magnetometer Δ|B| + Magnet knob; colliders = finger capsule + stir paddle + Box2D props; emitters while pouring) → Box2D step with last frame's `bodyImpulses` → feedback (hum from probe stress/solid fraction per the haptics note §5.3; transients on yield/jam/impact; synth `GloopKernel`) → 10 Hz telemetry. `encodeCompute`: `solver.encode` + `surface.encodePrepass`. `encodeBehind`: tank back wall, props behind. `encodeScene`: `surface.encodeShade`, props in front, tank glass, dye tracers, rheometer cursor.
- **Screen:** `labkit-from-orbitals-spectra.md` §9 exactly (full-bleed life-size tank, top bar with telemetry + Material/Experiments/Layers/Info, material shelf, five console pages Fluid/World/Touch/Signals/View with the §9.5 knobs, controls row Refill/Freeze/Rheometer/Reset, Rheometer sheet with the log-log flow curve, info sheet §9.9). Additions: the material shelf has a mode chip **Fill · Pour · Drop**: Fill refills the tank with the tapped material; Pour makes the next drag pour that material in (mixing materials in one tank); Drop shows prop tiles (steel ball, glass marble, cork block, die) that drop a Box2D prop at the top centre; props can be dragged.
- **Experiments** (each refills and restarts the clock): Punch the oobleck · Slow finger, fast finger · Cornstarch monsters (Shake 17 g at 120 Hz, Listen on) · Ketchup won't pour (tilt, then shake) · Toothpaste holds its shape · Mayonnaise on the Moon · Honey, cold and warm · Silly Putty bounce and slump · Slime puddle · Quicksand: shake to sink (steel ball) · Magnet and MR fluid · Paint levels · Lava crust · Two fluids (honey over oobleck).
- **Sensors:** tilt (always), shake (always), magnetometer (MR routes, `mag.delta`), microphone (just-in-time, first raise of Listen), thermal state (playful Heat route, off by default). One usage string: microphone.
- **Docs:** README.md, VERIFICATION.md, Documentation/RESEARCH.md (index of the research notes), THIRD_PARTY notices in-app.

## 7. Acceptance (whole project)

1. `LabKit` builds for iOS Simulator and device with 0 warnings; all XCTest targets pass; `labkit-physcheck` and `labkit-gpucheck` print PASS for every check marked required in §5, with numbers recorded.
2. Rheo builds (`Tools/build.sh sim|device`), launches in the simulator with `-simSway -fakeMic -startMic -fakeMagnet -fakeShake`, and shows every material and experiment without NaN or overflow (screenshots per material in `Rheo/Documentation/screenshots/`).
3. Rheo installs and launches on the iPhone 15 Pro Max; GPU frame time measured on device and the default quality chosen from it.
4. Every non-trivial claim in README/VERIFICATION is marked verified or not.
