# LabKit and Rheo: toolchain checks (Xcode 27 beta, iOS 27 SDK, Swift 6.4)

Date: 3 October 2026. Scope: the build decisions for **LabKit** (a local SwiftPM package that will be shared by the toy apps) and **Rheo** (an XcodeGen iOS 27 app that depends on it), checked by building and running a throwaway prototype.

No existing project was changed. Everything ran in the session scratchpad:

```
/private/tmp/claude-501/-Users-utkarsh-Documents-AI-Stuff/b53a2b83-9308-4477-a9dd-fedd258cad75/scratchpad/toolchain-check/
  LabKitProbe/            local SwiftPM package (C, Swift 6, Swift 5, Metal, iOS-only and Box2D targets + 3 XCTest targets)
  ProbeApp/project.yml    XcodeGen iOS 27 app that references ../LabKitProbe
  ProbeApp/ProbeApp/      ProbeApp.swift (prints every check to stdout and os_log), AppShaders.metal
  tc/apis.swift           Swift 6 typecheck of every SDK spelling in §6
  mirror-build.sh         prototype of Rheo/Tools/build.sh (mirror app + package, build)
  box2d-src/              git clone of Box2D v3.1.1 (vendored copy is in LabKitProbe/Sources/Box2D)
  logs-*.txt, run*.txt    raw build and run logs; probe-screenshot.png
  r2/                     round 2 (16:17-16:30, load 30-300): superset copy of LabKitProbe + ProbeApp
    LabKitProbe/          + Parity.metal / ParitySafe.metal / Parity.swift (GPU-vs-CPU parity, P2G determinism),
                            ProbeMainDefault (SE-0466 defaultIsolation target), probe-physcheck / probe-corecheck
                            executables, Swift Testing suite, CProbe/include/ProbeRheo.h (header-only MSL helpers)
    ProbeApp/             + ProbeAppTests hosted unit-test target (the RheoTests shape), scheme testTargets
    neg-md/, nores/       negative-test copies (cross-module MainActor calls; no `resources:` under xcodebuild)
    logs-r2-*.txt, run-r2-*.txt
```

The scratchpad is session-specific. Copy `r2/LabKitProbe/` and `r2/ProbeApp/` (the newest, superset versions) if you want to keep them as the starting skeleton.

Round 2 (§12) closed four of the open items from round 1 and added GPU-numerics and isolation checks that bear directly on the MPM solver and on the `LabKitUI` isolation choice in `labkit-from-gyre.md`.

## How this was checked

| Tag | Meaning |
|---|---|
| **RUN-SIM** | Built with `xcodebuild`, installed with `xcrun simctl install`, and run on the booted **iPhone 17 Pro simulator (iOS 27.0)**. The output was read with `simctl launch --console-pty` and `log show`. |
| **RUN-MAC** | Run headless on this Mac (Apple M1 Max, macOS 27.2) under `swift test`, including GPU kernels. |
| **BUILD** | Compiled and linked. The device build used `generic/platform=iOS` in Release with `CODE_SIGNING_ALLOWED=NO`, so nothing was signed and nothing was installed on the phone. |
| **TC** | Type-checked with `swiftc -typecheck -swift-version 6` against both `iPhoneOS27.0.sdk` and `iPhoneSimulator27.0.sdk`. |
| **SDK** | Read in the SDK headers or `.swiftinterface` files (line numbers are cited). |
| **NEG** | Negative test: the setting was removed and the expected failure was observed. |
| **INF** | Inferred from the above and not run. |
| **DEV?** | Needs his iPhone 15 Pro Max (A17 Pro, Apple9 GPU, iOS 27.2). Not run here: the phone shows "available (paired)" in `devicectl`, but installing a probe on it was out of scope. |

Toolchain on this Mac:
- Xcode 27.0 beta (27A5194q) at `/Applications/Xcode-beta.app`, which is also `xcode-select -p`.
- Swift 6.4 (`swiftlang-6.4.0.20.104`).
- XcodeGen 2.46.0.
- Metal Toolchain component 27A5194o, identifier `com.apple.dt.toolchain.Metal.32023.917`, metal version 32023.917.
- Simulators: iPhone 17 Pro `9AC0979F-7162-42A7-A2BD-FB3CC1D6439D` (booted, and shared with other sessions) and an "Orbitals QA" iPhone 15 Pro Max simulator (shut down).

**The machine was heavily loaded during every round-1 timing:** `uptime` load averages were 690–850 on 10 cores because many agent sessions were building in parallel. Treat those absolute times as pessimistic; the ratios between them are still meaningful. Round 2 re-timed the main steps at a load of about 30 (§8).

---

## 1. Headline findings

1. **Metal inside a SwiftPM target works with Xcode and with `swift build`.** The `.metal` file is compiled into a `default.metallib` inside the package's resource bundle, and `device.makeDefaultLibrary(bundle: .module)` loads it.
   - On iOS the path is `Rheo.app/<Package>_<Target>.bundle/default.metallib`, a flat bundle at the app root.
   - On macOS the path is `…bundle/Contents/Resources/default.metallib`.
   - The kernel ran on the simulator GPU and on the M1 Max: 1,024 threads added `1.0f` into one `atomic_float` and the sum was 1024.0. A non-uniform dispatch of 1,000 threads summed to 1000.0. (RUN-SIM, RUN-MAC)
2. **No `-I` from dependency targets reaches the Metal compiler, in either Xcode or SwiftPM.**
   - `#include "CProbe.h"` from a package `.metal` file fails with `fatal error: 'CProbe.h' file not found`, even though the target depends on `CProbe`.
   - Fix for package shaders: include the shared header **by relative path**, `#include "../../LabKitShaderTypes/include/LabKitShaderTypes.h"`.
   - Fix for app shaders: `MTL_HEADER_SEARCH_PATHS: $(SRCROOT)/../LabKit/Sources/<C target>/include`.
   - Header dependency tracking works through both routes: touching the header rebuilt both metallibs. (BUILD, RUN-SIM)
3. **The SwiftPM CLI needs `TOOLCHAINS=metal`.**
   - `XcodeDefault.xctoolchain/usr/bin/metal` is a stub. It prints `cannot execute tool 'metal' due to missing Metal Toolchain`, even though the component is installed.
   - `swift build` / `swift test` (the default `swiftbuild` engine) invokes that stub, so it fails on any `.metal` file.
   - `TOOLCHAINS=metal swift test` makes it find the real compiler in the Metal Toolchain cryptex (`/var/run/com.apple.security.cryptexd/mnt/com.apple.MobileAsset.MetalToolchain-v27.1.5194.15.*/Metal.xctoolchain/usr/bin/metal`), and Swift stays on the Xcode default compiler.
   - `xcodebuild` finds the cryptex on its own. (RUN-MAC, NEG)
4. **`swift test` runs headless on macOS from a non-iCloud copy.**
   - It covers a Foundation+simd Swift 6 core, a C target, a Metal target on the Mac GPU, and Box2D.
   - Clean run: 56.6 s at load 700+, and **15.7 s** at load 30 (round 2). No-op run: 4.9 s.
   - Conditions: the package declares `.macOS(.v27)`, and the UIKit and CoreMotion code is inside `#if canImport(UIKit)` / `#if os(iOS)`. (RUN-MAC, NEG)
5. **Per-target Swift 5 mode is `swiftSettings: [.swiftLanguageMode(.v5)]`.** Use it with `swiftLanguageModes: [.v6]` at package level. `swiftLanguageVersion(_:)` is deprecated and renamed in tools 6.0 (PackageDescription interface line 79). Proof that it applies:
   - With the setting, a nonisolated global `var` compiles.
   - Without it, the same code fails with `var 'legacyCounter' is not concurrency-safe because it is nonisolated global shared mutable state`.
   - At runtime, `#if swift(>=6)` reports `app=6 ProbeCore=6 ProbeLegacy=5`. (RUN-SIM, NEG)
6. **Swift 6 crash that compiles with zero warnings.** An `AVAudioSourceNode` render closure written inline inside a `@MainActor` method:
   - **traps on the audio thread** (`EXC_BREAKPOINT` on `AURemoteIO::IOThread`: `_dispatch_assert_queue_fail ← _swift_task_checkIsolatedSwift ← closure #1 in ProbeSynth.start`);
   - is fine when built in a `nonisolated static func` factory: 73,216 frames rendered in 1.5 s;
   - is also fine as an inline closure explicitly marked `{ @Sendable … }`: 73,728 frames. (RUN-SIM)

   Gyre never hits this, because it is in Swift 5 mode and `HumSynth` is not `@MainActor` (`Gyre/Gyre/Feedback/HumSynth.swift:79`).
7. **The simulator GPU is not an A17.**
   - `supportsFamily` is **false for apple7, apple8, apple9, apple10, metal3 and metal4**. Only Apple1, Apple2 and Common1 return true.
   - `maxThreadsPerThreadgroup` is 512, threadgroup memory is 16 KB, `maxBufferLength` is 256 MB, and `hasUnifiedMemory` is false.
   - Even so, MSL 4.1 kernels, `atomic_float` and non-uniform `dispatchThreads` all work.
   - **`MTLGPUFamily.metal4` does not exist in the iPhoneSimulator27.0 SDK**, so it is a compile error there. Use `MTLGPUFamily(rawValue: 5002)!`. (RUN-SIM, TC)
8. **iOS 27 SDK changes that affect compute code:**
   - `MTLCommandBuffer.waitUntilCompleted()` is `NS_SWIFT_UNAVAILABLE_FROM_ASYNC` (`MTLCommandBuffer.h:354`); use `await commandBuffer.completed()`.
   - Inside an `async` function, `device.makeComputePipelineState(function:)` resolves to the async overload and needs `await`. (BUILD)
9. **XcodeGen 2.46 local packages work as written.**
   - `packages: LabKit: path: ../LabKit` plus `- package: LabKit` and `products: [A, B, …]` generates an `XCLocalSwiftPackageReference` with `relativePath = ../LabKitProbe` and one `XCSwiftPackageProductDependency` per product.
   - Generation takes 0.1 s. (BUILD)
10. **Box2D v3.1.1 (MIT) builds warning-free as a vendored C17 SwiftPM target.** Verified on macOS, the iOS simulator and iOS device (NEON path), and it is callable from Swift 6.
    - A 1 m box dropped from 10 m was at y = 5.0746 m after 1 s at 60 Hz (analytic 5.095).
    - It settles at y = 0.4999 m and goes to sleep.
    - Under Moon gravity it was at y = 9.1866 m after 1 s (analytic 9.19). (RUN-SIM, RUN-MAC)
11. **Parallel sessions share the booted simulator.** Another session had installed a different app under `com.utkarsh.labkitprobe`. Installing over it silently ran their binary, which printed `PROBE box2d …`.
    - Every probe or QA app needs a unique bundle id.
    - Better: give Rheo its own simulator ("Rheo QA").

Round 2 additions (§12 says where each is written up):

12. **`defaultIsolation(MainActor.self)` makes the §5 crash the default, and walls the module off from nonisolated code.** In a target built with it (the `LabKitUI` proposal in `labkit-from-gyre.md:118`):
    - an unannotated class is MainActor, and an inline render block formed in its method **trapped on `AURemoteIO::IOThread`** with the same stack as §5 (RUN-SIM, crash report `LabKitProbeApp-2026-10-03-162545.ips`). It compiled with zero warnings. The `nonisolated static` factory in the same class rendered 50,688 frames in 1 s.
    - unannotated free functions, struct initialisers, methods **and the struct's `Equatable` conformance** are MainActor. A normal Swift 6 target calling them from synchronous code gets 6 errors, including `main actor-isolated conformance of 'MDSpec' to 'Equatable' cannot be used in nonisolated context` (NEG). `nonisolated public func` / `nonisolated public struct … : Equatable, Sendable` compile cleanly from the same caller.
13. **`atomic_float` P2G is not repeatable; 32-bit fixed point is, and is faster.** A spatially coherent 3×3 quadratic-B-spline P2G (262,144 particles, 128² grid) gave a different bit pattern on **7 of 7** repeat runs (up to 4,807 of 5,565 occupied cells differed, by up to 7.2e-7). The 2²⁴ fixed-point `atomic_int` version was bit-identical on every run, 4× faster on the M1 Max (0.40 ms vs 1.62 ms), and within 1.8e-5 relative of a Double CPU scatter (RUN-MAC, RUN-SIM). This corroborates `oss-integration-lessons.md` §3.7 with a realistic stencil.
14. **Fast math costs no accuracy on a realistic rheology chain; bit parity with the CPU is impossible either way.** Arrhenius × regularised Herschel–Bulkley × Wyart–Cates jamming, 4,096 inputs: GPU fast / `precise::` / `#pragma METAL fp math_mode(safe)` all land at 5.5–5.7e-6 max relative error against Double. That equals CPU `Float` (5.8e-6). Only 144 (fast) to 1,105 (safe) of 4,096 results were bit-equal to CPU `Float`. Physics checks must use relative tolerances (≈1e-5 for float chains), never bitwise GPU-vs-CPU equality (RUN-MAC, RUN-SIM).
15. **SwiftPM umbrella-header rule.** If a C target has `include/<TargetName>.h`, SwiftPM uses it as the umbrella header, and any other header in `include/` is invisible to Swift (`warning: umbrella header for module 'CProbe' does not include header 'ProbeRheo.h'`, then `cannot find 'ProbeScatterArgs' in scope`). `LabKitShaderTypes.h` must `#include` every sibling header (NEG, then fixed).
16. **Closed from round 1:** `resources: [.process("Shaders")]` is optional under `xcodebuild` too; hosted unit tests (`bundle.unit-test` depending only on the app target) can `import` package modules and load the package metallib with no duplicate linking; Swift Testing and XCTest run side by side under `swift test` and `xcodebuild test`; `swift run <exe>` builds only that product's closure, so a Core-only physcheck needs no `TOOLCHAINS=metal` even when the package has `.metal` files.
17. **Correction to `labkit-from-gyre.md:69`** ("`swift build` on the command line **cannot** build `LabKitRender`"): it can, with `TOOLCHAINS=metal` (finding 3). `TOOLCHAINS=metal swift run -c release probe-physcheck` built a Metal target, found `Bundle.module` next to the executable, and ran the GPU kernels on the Mac (13.5 s for the Release build and run, after a first attempt had already compiled part of the graph).

---

## 2. Package.swift: the exact manifest that built and ran

The file is `LabKitProbe/Package.swift` and it is verified as written. It builds:
- with `xcodebuild` for the iOS simulator and for iOS device;
- with `TOOLCHAINS=metal swift build` / `swift test` on macOS.

```swift
// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "LabKitProbe",
  platforms: [.iOS(.v27), .macOS(.v27)],
  products: [
    .library(name: "ProbeCore", targets: ["ProbeCore"]),
    .library(name: "ProbeLegacy", targets: ["ProbeLegacy"]),
    .library(name: "ProbeMetal", targets: ["ProbeMetal"]),
    .library(name: "ProbeKit", targets: ["ProbeKit"]),
    .library(name: "ProbePhysics", targets: ["ProbePhysics"]),
  ],
  targets: [
    // (d) tiny C target; its public header is shared by Swift and MSL.
    .target(
      name: "CProbe",
      cSettings: [.define("CPROBE_VERSION", to: "3")]
    ),
    // (a) Swift 6 mode (package default below), Foundation + simd only.
    .target(name: "ProbeCore", dependencies: ["CProbe"]),
    // (b) Swift 5 language mode for this one target.
    .target(
      name: "ProbeLegacy",
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    // (c) Swift 6 target with a .metal file; resources declared explicitly.
    .target(
      name: "ProbeMetal",
      dependencies: ["CProbe"],
      resources: [.process("Shaders")]
    ),
    // iOS-only UI/audio/sensor patterns in Swift 6 mode.
    .target(name: "ProbeKit", dependencies: ["ProbeCore", "ProbeMetal"]),
    // Vendored Box2D v3.1.1 (MIT), C17, compiled as-is from include/ + src/.
    .target(
      name: "Box2D",
      exclude: ["LICENSE"],
      sources: ["src"],
      publicHeadersPath: "include",
      cSettings: [.headerSearchPath("src")]
    ),
    .target(name: "ProbePhysics", dependencies: ["Box2D"]),
    .testTarget(name: "ProbePhysicsTests", dependencies: ["ProbePhysics"]),
    .testTarget(name: "ProbeCoreTests", dependencies: ["ProbeCore"]),
    .testTarget(name: "ProbeMetalTests", dependencies: ["ProbeMetal"]),
  ],
  swiftLanguageModes: [.v6],
  cLanguageStandard: .c17
)
```

Manifest facts, from `…/usr/lib/swift/pm/ManifestAPI/PackageDescription.swiftmodule/arm64-apple-macos.swiftinterface` (SDK):

- `.iOS(.v27)` / `.macOS(.v27)` need **tools 6.4** (line 655: `@available(_PackageDescription 6.4) public static let v27`). The string form `.iOS("27.0")` works with any tools version (lines 518, 524), so use it if the manifest ever has to drop to 6.2.
- `swiftLanguageMode(_:_:)` is tools 6.0 (line 82). `swiftLanguageVersion` is deprecated in 6.0 and renamed (line 79). The package-level `swiftLanguageModes:` replaces `swiftLanguageVersions:` (lines 343–361).
- Also available, but not used here:
  - `defaultIsolation(MainActor.self)` (tools 6.2, line 88);
  - `strictMemorySafety()` (6.2);
  - `treatAllWarnings(as:)` and `treatWarning(_:as:)` (6.2);
  - `enableUpcomingFeature` (5.8).
- **`.macOS(.v27)` is load-bearing for `swift test`.** Without a macOS minimum, the Metal target compiles for an old macOS and fails with `unknown type name 'atomic_float'`. Swift-side `Synchronization.Atomic` (macOS 15+) would fail too. (NEG)
- `resources: [.process("Shaders")]` is optional for `.metal` files:
  - with it removed, `swift build` still compiled `default.metallib` and generated `Bundle.module`, and the GPU test passed (RUN-MAC);
  - round 2: with it removed, `xcodebuild -scheme ProbeMetal -destination 'generic/platform=iOS Simulator'` still produced `LabKitProbe_ProbeMetal.bundle/{Info.plist,_CodeSignature,default.metallib}` from 3 `CompileMetalFile` steps, and `Bundle.module` compiled (BUILD, `r2/nores/`).
  - Keep the explicit declaration anyway: it documents intent, and it is what makes `Bundle.module` exist if every `.metal` file is ever moved out.
- A transitive C module is **not** visible to app code automatically: the error is `cannot find type 'ProbeUniforms' in scope`. In round 1, `import CProbe` in the app compiled and ran even though `CProbe` was not a product (BUILD); that relies on Xcode exposing every module in the build graph. Round 2 made `CProbe` a product and listed it in the app's `products:`; that is the shape to copy (BUILD, RUN-SIM).

Round 2 manifest (`r2/LabKitProbe/Package.swift`, verified with `TOOLCHAINS=metal swift test`, `swift run`, and `xcodebuild` for simulator Debug and device Release). Only the differences from the block above are shown:

```swift
  products: [
    .library(name: "CProbe", targets: ["CProbe"]),                    // shared-types C target as a product
    // … ProbeCore, ProbeLegacy, ProbeMetal, ProbeKit, ProbePhysics as above …
    .library(name: "ProbeMainDefault", targets: ["ProbeMainDefault"]),
    .executable(name: "probe-physcheck", targets: ["ProbePhyscheck"]), // Core + Metal: needs TOOLCHAINS=metal
    .executable(name: "probe-corecheck", targets: ["ProbeCorecheck"]), // Core only: plain `swift run`
  ],
  targets: [
    // …
    .target(name: "ProbeMainDefault", swiftSettings: [.defaultIsolation(MainActor.self)]),  // SE-0466
    .executableTarget(name: "ProbePhyscheck", dependencies: ["ProbeCore", "ProbeMetal"]),
    .executableTarget(name: "ProbeCorecheck", dependencies: ["ProbeCore"]),
    .testTarget(name: "ProbeCoreTests", dependencies: ["ProbeCore", "ProbeMainDefault"]), // XCTest + Swift Testing
    // …
  ],
```

### 2.1 How this maps onto LabKit (INF: same constructs, not built under these names)

Module names follow `labkit-from-gyre.md` §2 (`LabKitRender`, `labkit-physcheck`), so the two notes agree. Every construct below was built in the probe under a different name.

```swift
// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "LabKit",
  platforms: [.iOS(.v27), .macOS(.v27)],                                // .macOS(.v27) is load-bearing for swift test (atomic_float)
  products: [
    .library(name: "LabKitCore", targets: ["LabKitCore"]),               // Foundation + simd: params, drives, integrators, physcheck helpers
    .library(name: "LabKitShaderTypes", targets: ["LabKitShaderTypes"]), // C header shared by Swift and MSL (a product: §2 bullet)
    .library(name: "LabKitRender", targets: ["LabKitRender"]),           // render host, bloom/EDR post chain, shared kernels (Shaders/*.metal)
    .library(name: "LabKitUI", targets: ["LabKitUI"]),                   // tokens, GlassKnob, console, top bar, info sheet
    .library(name: "LabKitFeedback", targets: ["LabKitFeedback"]),       // CoreHaptics + AVAudioEngine synth
    .library(name: "LabKitSensors", targets: ["LabKitSensors"]),         // motion, magnetometer, barometer, mic, thermal + fakes
    .library(name: "Box2D", targets: ["Box2D"]),                         // vendored v3.1.1
    .executable(name: "labkit-physcheck", targets: ["LabKitPhyscheck"]),
  ],
  targets: [
    .target(name: "LabKitShaderTypes"),                                  // include/LabKitShaderTypes.h must #include every sibling header (§4.2)
    .target(name: "LabKitCore"),                                         // nonisolated default: never defaultIsolation here (§5.1)
    .target(name: "LabKitRender", dependencies: ["LabKitCore", "LabKitShaderTypes"], resources: [.process("Shaders")]),
    .target(name: "LabKitUI", dependencies: ["LabKitCore", "LabKitFeedback"],
            swiftSettings: [.defaultIsolation(MainActor.self)]),         // only if the §5.1 rules are followed
    .target(name: "LabKitFeedback", dependencies: ["LabKitCore"]),
    .target(name: "LabKitSensors", dependencies: ["LabKitCore", "LabKitFeedback"]),
    .target(name: "Box2D", exclude: ["LICENSE"], sources: ["src"], publicHeadersPath: "include",
            cSettings: [.headerSearchPath("src")]),
    .executableTarget(name: "LabKitPhyscheck", dependencies: ["LabKitCore"]),  // add LabKitRender only with TOOLCHAINS=metal
    .testTarget(name: "LabKitCoreTests", dependencies: ["LabKitCore"]),
    .testTarget(name: "LabKitRenderTests", dependencies: ["LabKitRender"]),
  ],
  swiftLanguageModes: [.v6],
  cLanguageStandard: .c17
)
```

If a Gyre file is lifted verbatim before it is ported to strict concurrency, give it its own target with `swiftSettings: [.swiftLanguageMode(.v5)]` rather than downgrading LabKit.

---

## 3. project.yml: the exact spec that built and ran

`ProbeApp/project.yml` (verified):

```yaml
name: LabKitProbeApp
options:
  bundleIdPrefix: com.utkarsh
  deploymentTarget:
    iOS: "27.0"
  xcodeVersion: "27.0"
  createIntermediateGroups: true
packages:
  LabKitProbe:
    path: ../LabKitProbe
settings:
  base:
    SWIFT_VERSION: "6.0"
    MARKETING_VERSION: "1.0"
    CURRENT_PROJECT_VERSION: "1"
    DEVELOPMENT_TEAM: ""
    CODE_SIGN_STYLE: Automatic
targets:
  LabKitProbeApp:
    type: application
    platform: iOS
    sources: [ProbeApp]
    dependencies:
      - package: LabKitProbe
        products: [ProbeCore, ProbeLegacy, ProbeMetal, ProbeKit, ProbePhysics]
    info:
      path: ProbeApp/Info.plist
      properties:
        CFBundleDisplayName: LabKit Probe
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        NSMicrophoneUsageDescription: "LabKit Probe listens to test the audio path. Nothing is recorded or kept."
        NSMotionUsageDescription: "LabKit Probe reads the barometer to test the sensor path."
        UILaunchScreen: {}
        UIApplicationSceneManifest:
          UIApplicationSupportsMultipleScenes: false
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
        UIUserInterfaceStyle: Dark
        CADisableMinimumFrameDurationOnPhone: true
        ITSAppUsesNonExemptEncryption: false
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.utkarsh.labkitprobe.toolchaincheck
        TARGETED_DEVICE_FAMILY: "1"
        MTL_FAST_MATH: YES
        MTL_HEADER_SEARCH_PATHS: $(SRCROOT)/../LabKitProbe/Sources/CProbe/include
        SWIFT_STRICT_CONCURRENCY: complete
        SUPPORTS_MACCATALYST: NO
```

Round 2 additions to the same file (`r2/ProbeApp/project.yml`, verified with `xcodebuild test`: `** TEST SUCCEEDED **`, 11.2 s including the incremental build):

```yaml
targets:
  LabKitProbeApp:
    dependencies:
      - package: LabKitProbe
        products: [CProbe, ProbeCore, ProbeLegacy, ProbeMetal, ProbeKit, ProbePhysics, ProbeMainDefault]
    scheme:
      testTargets: [ProbeAppTests]        # puts the hosted tests into the auto-generated app scheme
    # … info / settings as above …
  ProbeAppTests:
    type: bundle.unit-test
    platform: iOS
    sources: [ProbeAppTests]
    dependencies:
      - target: LabKitProbeApp            # no package products here: they come from the host app
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        PRODUCT_BUNDLE_IDENTIFIER: com.utkarsh.labkitprobe.toolchaincheck.tests
```

What the hosted test proved (RUN-SIM):
- `import ProbeMetal` compiles in the test target although the target lists no package product. The package code is statically linked into the host app, and the test bundle (`LabKitProbeApp.app/PlugIns/ProbeAppTests.xctest`) resolves against it.
- `ProbeMetal.makeLibrary(device:)` found `LabKitProbe_ProbeMetal.bundle/default.metallib` inside the **host app**, and the fixed-point scatter kernel ran on the simulator GPU.
- No `Class … is implemented in both` warning, because the package objects were linked only once.
- A Swift Testing `@Test` in the same file ran too (`✔ Test hostedSwiftTestingSeesHostApp() passed`), and `Bundle.main` was the host app.
- XcodeGen leaves `SWIFT_DEFAULT_ACTOR_ISOLATION` and `SWIFT_APPROACHABLE_CONCURRENCY` unset (`-showBuildSettings`), so app code is nonisolated by default, unlike Xcode's new-project template.

### 3.1 Rheo version (INF: same keys as above; values follow Gyre `project.yml:1-48` and house rules)

```yaml
name: Rheo
options:
  bundleIdPrefix: com.utkarsh
  deploymentTarget:
    iOS: "27.0"
  xcodeVersion: "27.0"
  createIntermediateGroups: true
packages:
  LabKit:
    path: ../LabKit
settings:
  base:
    SWIFT_VERSION: "6.0"
    MARKETING_VERSION: "1.0"
    CURRENT_PROJECT_VERSION: "1"
    DEVELOPMENT_TEAM: ""
    CODE_SIGN_STYLE: Automatic
targets:
  Rheo:
    type: application
    platform: iOS
    sources: [Rheo]
    dependencies:
      - package: LabKit
        products: [LabKitCore, LabKitShaderTypes, LabKitRender, LabKitUI, LabKitFeedback, LabKitSensors, Box2D]
    scheme:
      testTargets: [RheoTests]   # verified shape (round 2, §3 above)
    info:
      path: Rheo/Info.plist
      properties:
        CFBundleDisplayName: Rheo
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        NSMicrophoneUsageDescription: "Rheo listens so sound can shake the fluid. Nothing is recorded or kept."
        NSMotionUsageDescription: "Rheo reads the barometer so the air pressure around you can press on the fluid."
        UILaunchScreen:
          UIColorName: LaunchBackground
        UIApplicationSceneManifest:
          UIApplicationSupportsMultipleScenes: false
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
        UIUserInterfaceStyle: Dark
        UIStatusBarHidden: true
        CADisableMinimumFrameDurationOnPhone: true   # 120 Hz MTKView on ProMotion (Gyre project.yml:38)
        ITSAppUsesNonExemptEncryption: false
        LSApplicationCategoryType: public.app-category.entertainment
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.utkarsh.rheo
        TARGETED_DEVICE_FAMILY: "1"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
        MTL_FAST_MATH: YES
        MTL_HEADER_SEARCH_PATHS: $(SRCROOT)/../LabKit/Sources/LabKitShaderTypes/include
        SWIFT_STRICT_CONCURRENCY: complete
        SUPPORTS_MACCATALYST: NO
  RheoTests:
    type: bundle.unit-test
    platform: iOS
    sources: [RheoTests]
    dependencies:
      - target: Rheo
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
```

Notes:
- `MTL_FAST_MATH: YES` matches Gyre (`project.yml:47`) and Orbitals (`project.yml:51`). Fast math is the default anyway (§4).
- `SWIFT_STRICT_CONCURRENCY: complete` is redundant under Swift 6, but it is the Orbitals house style (`Orbitals/project.yml:53`).
- Do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` on Rheo until every real-time closure follows §5 (INF from the crash in §5).

---

## 4. Metal in the package and in the app

### 4.1 What the build produces (BUILD, RUN-SIM, RUN-MAC)

| | Package target `ProbeMetal` | App target |
|---|---|---|
| Built in Xcode as | target `LabKitProbe_ProbeMetal` (resource bundle) | the app target |
| Output, iOS | `LabKitProbeApp.app/LabKitProbe_ProbeMetal.bundle/{Info.plist,_CodeSignature,default.metallib}` | `LabKitProbeApp.app/default.metallib` |
| Output, macOS `swift test` | `.build/out/Products/Debug/LabKitProbe_ProbeMetal.bundle/Contents/Resources/default.metallib`, copied into `ProbeMetalTests.xctest/Contents/Resources/` | n/a |
| Loader | `try device.makeDefaultLibrary(bundle: .module)` | `device.makeDefaultLibrary()` |
| Functions seen at runtime | `lk_fullscreen_vertex`, `lk_probe_atomic_add`, `lk_probe_fragment` | `app_probe_kernel` only; `makeFunction(name: "lk_probe_atomic_add")` on the app library returns nil |
| Compiler flags (Debug, simulator) | `-target air64-apple-ios27.0-simulator -fmetal-math-mode=fast -fmetal-math-fp32-functions=fast` | same, plus `-gline-tables-only -frecord-sources` |
| `__METAL_VERSION__` (no `-std`) | 410 (MSL 4.1) | 410 |
| `__FAST_MATH__` | defined | defined |
| Size | 12,992 B (sim Debug), 12,912 B (device Release) | 55,040 B (sim Debug, includes recorded sources) |
| Linking | static: `.o` files are linked into the app and there is no `Frameworks/` folder | |

Consequences:

- **Two libraries, two loaders.** LabKit should expose something like `LabKitRender.library(device:) throws -> MTLLibrary` that wraps `makeDefaultLibrary(bundle: .module)`, and cache it. Rheo's own kernels (for example MPM P2G/G2P) come from `device.makeDefaultLibrary()`.
  - If a single pipeline must mix functions from both libraries, look up each `MTLFunction` in its own library. A pipeline takes functions from any library on the same device (INF).
- **Package shaders carry no shader sources in Debug.** The app gets `-gline-tables-only -frecord-sources` and the package does not, so GPU frame captures of LabKit kernels show no source lines (INF from the flags).
  - Package targets have no `metalSettings`, so this cannot be changed from `Package.swift`.
- **Fast math is on by default for package shaders and cannot be switched off with a flag.** For kernels that are parity-checked against the CPU reference, use per-file `#pragma METAL fp math_mode(safe)` and `#pragma METAL fp contract(off)`, or `precise::` functions.
  - The pragmas compiled with the real `metal` both with fast math on and with `-std=metal3.1` (BUILD).
  - Their numeric effect was not measured.

### 4.2 The shared Swift/MSL struct header (RUN-SIM, RUN-MAC)

`Sources/CProbe/include/CProbe.h`:

```c
#ifndef CPROBE_H
#define CPROBE_H
#ifdef __METAL_VERSION__
#include <metal_stdlib>
typedef metal::float2 lk_float2;
typedef uint lk_uint;
#else
#include <simd/simd.h>
#include <stdint.h>
typedef simd_float2 lk_float2;
typedef uint32_t lk_uint;
#endif
typedef struct {
  lk_float2 gravity;   // m/s^2
  float dt;            // s
  lk_uint count;
} ProbeUniforms;
#ifndef __METAL_VERSION__
float cprobe_mix(float a, float b, float t);
int cprobe_version(void);
long cprobe_stdc_version(void);
#endif
#endif
```

- Swift side: `MemoryLayout<ProbeUniforms>.size == 16`, `stride == 16`, and `setBytes(&u, length: MemoryLayout<ProbeUniforms>.stride, index: 1)` works.
- In the app kernel, `u.gravity.y` read back as -1.62 and in the package kernel as -9.81.
- `cSettings: [.define("CPROBE_VERSION", to: "3")]` arrived (`cprobe_version() == 3`).
- The C file compiled as C17 (`__STDC_VERSION__ == 201710`).
- Package shader include (works in both Xcode and SwiftPM):
  `#include "../../CProbe/include/CProbe.h"  // SwiftPM passes no dependency -I to metal; include relatively`
- App shader include: `#include "CProbe.h"` plus `MTL_HEADER_SEARCH_PATHS: $(SRCROOT)/../LabKitProbe/Sources/CProbe/include`.
- `-MMD` dependency files work. After `touch CProbe.h`, the next build ran `CompileMetalFile` twice (package and app) and `SwiftCompile` for its importers.

Round 2: a second public header, `include/ProbeRheo.h`, holds a C struct (`ProbeScatterArgs`) plus **header-only MSL helpers** (a `PROBE_RHEO_DEFINE(NAME, EXPF, POWF)` macro and `probe_bspline`) inside `#ifdef __METAL_VERSION__`, so the Clang importer sees only the struct. Two rules came out of it (NEG, then fixed; BUILD, RUN-SIM, RUN-MAC):
- **Umbrella header.** SwiftPM's generated module map uses `include/<TargetName>.h` as the umbrella header when that file exists. A sibling header that it does not include is invisible to Swift: `warning: umbrella header for module 'CProbe' does not include header 'ProbeRheo.h'`, then `error: cannot find 'ProbeScatterArgs' in scope`. The fix is one line at the end of `CProbe.h`, inside its include guard: `#include "ProbeRheo.h"`. For LabKit: `LabKitShaderTypes.h` includes every other header in `include/`. The alternative is to have no header named after the target, so SwiftPM falls back to an umbrella directory.
- Touching `ProbeRheo.h` recompiled all three package `.metal` files and the app's `.metal` file (8.96 s at load 300), because `CProbe.h` now pulls it in. That fan-out is the price of keeping MSL helpers reachable from the umbrella header; at 9 s it does not matter yet. (Moving MSL-only helpers somewhere else, such as a `.h` beside the `.metal` files, was not tried; under `.process("Shaders")` it might be copied into the bundle as a resource.)

### 4.3 MLS-MPM-relevant GPU checks

| Check | Simulator (Apple iOS simulator GPU) | Mac (M1 Max) | iPhone 15 Pro Max |
|---|---|---|---|
| `device atomic_float*` + `atomic_fetch_add_explicit(…, memory_order_relaxed)`, 1,024 threads | 1024.0 ✓ | 1024.0 ✓ | DEV? (Apple9 supports it per the MSL spec) |
| Non-uniform `dispatchThreads(1000)` with 256-wide groups | 1000.0 ✓ | 1000.0 ✓ | DEV? |
| `supportsFamily(.apple9)` | **false** | n/a | expected true (A17 Pro = Apple9), DEV? |
| All `supportsFamily` raw values that return true | `[1001, 1002, 3001]` | — | DEV? |
| `maxThreadsPerThreadgroup.width` | 512 | — | DEV? (1024 on Apple GPUs) |
| `maxThreadgroupMemoryLength` | 16,384 | — | DEV? (32 KB) |
| `maxBufferLength` | 256 MB | — | DEV? |
| `recommendedMaxWorkingSetSize` | 0 | — | DEV? |
| `hasUnifiedMemory` | false | — | DEV? |

Rule: **never hard-gate a feature on `supportsFamily` without a simulator escape.** Use `#if targetEnvironment(simulator)`, or test the feature you actually need.
- Size threadgroups from `pipeline.maxTotalThreadsPerThreadgroup` (as the probe does), never from a constant 1024.
- Keep the MPM grid and particle buffers well under 256 MB, or the simulator path dies.

### 4.4 GPU vs CPU numeric parity (round 2; RUN-MAC under `swift test`, RUN-SIM in the app)

The kernel is the kind of constitutive chain Rheo will run per particle (`ProbeRheo.h`, mirrored in Swift by `probeRheoCPU<F>` in `Parity.swift`):

- Arrhenius shift aT = exp((Ea/R)(1/T − 1/T_ref)), with Ea/R = 7216.743 K (60 kJ/mol ÷ 8.314 J/(mol·K)) and T_ref = 293.15 K.
- Papanastasiou-regularised Herschel–Bulkley: η = τ_y(1 − e^(−m·γ̇))/γ̇ + K·γ̇^(n−1), with τ_y = 10 Pa, K = 5 Pa·sⁿ, n = 0.4, m = 1000 s, and γ̇ clamped to ≥ 1e-6 s⁻¹.
- Wyart–Cates jamming: σ = aT·η·γ̇, f = 1 − e^(−σ/σ*), φ_J = 0.58f + 0.64(1 − f), η ×= (1 − 0.55/φ_J)^(−2), with σ* = 50 Pa. The result is scaled by 1/400.
- Inputs: 4,096 points, γ̇ log-spaced from 1e-3 to 1e3 s⁻¹, and T from 273 to 333 K.

| Variant (all against a Swift `Double` reference) | max relative error | mean relative error | max ULP vs CPU `Float` | bit-equal to CPU `Float` |
|---|---|---|---|---|
| CPU `Float` (libm `expf`/`powf`) | 5.80e-6 | 8.79e-7 | 0 | 4096/4096 |
| GPU, package default (`-fmetal-math-mode=fast`) | 5.69e-6 | 1.10e-6 | 94 | 144/4096 |
| GPU, `metal::precise::exp/pow` in the fast file | 5.46e-6 | 1.05e-6 | 93 | 166/4096 |
| GPU, file-scope `#pragma METAL fp math_mode(safe)` + `#pragma METAL fp contract(off)` | 5.71e-6 | 8.79e-7 | 59 | 1105/4096 |

- The simulator GPU gave **identical** statistics to the M1 Max, as expected if the simulator forwards to the host GPU. The A17 Pro may differ (DEV?).
- The safe pragma takes effect: its mean error equals CPU `Float` to three digits, and its bit-equal count is 8× the fast file's. That closes the round-1 open item on the pragma's numeric effect.
- The jamming factor (1 − φ/φ_J)^(−2) amplifies rounding, so every float path sits near 6e-6. Fast math is **not** the accuracy bottleneck for this chain.

Decision for LabKit's physics checks: compare GPU kernels with the CPU reference at a **relative tolerance of 1e-5** for float chains like this one, and keep fast math on (the default). Use the safe pragma only in a dedicated parity kernel file if a check ever needs tighter agreement.

### 4.5 P2G scatter determinism (round 2; RUN-MAC, RUN-SIM, and hosted test)

`lk_p2g_float` / `lk_p2g_fixed` in `Parity.metal`:
- 262,144 particles in a pooled blob (x ∈ [0.1, 0.9], y ∈ [0.05, 0.45] of the unit square), each with mass 0.0137 × (1 + 0.1u).
- Each particle scatters m·w_ij to its 3×3 quadratic B-spline stencil on a 128 × 128 grid. That is 2.36 M atomic adds, with neighbouring threads hitting neighbouring cells, as in a real P2G.
- 8 runs per variant.
- Fixed point uses `int(rint(m·w·2²⁴))` into `atomic_int`. A cell overflows Int32 at 128 mass units; the densest cell here held 0.93.

| Variant | Runs not bit-identical to run 0 | Most cells differing in one run | Max run-to-run delta | Max relative error vs Double (cells with > 1e-3 mass) | GPU ms per dispatch, M1 Max / simulator |
|---|---|---|---|---|---|
| `atomic_float` | **7 of 7** | 4,807 of 5,565 | 7.2e-7 | 1.3e-6 | 1.62 / 0.53 |
| 2²⁴ fixed point, `atomic_int` | **0 of 7** | 0 | 0 | 1.8e-5 | 0.40 / 0.12 |

- The hosted unit test (65,536 particles, 4 runs) reproduced this: 3 of 3 repeat float runs differed, and fixed point was identical.
- **Decision:** Rheo's P2G (mass, momentum, and the two-way Box2D impulse buffer) accumulates in 32-bit fixed point. Choose the scale per quantity from its worst-case cell sum: 2²⁴ leaves 7 bits of headroom above unit cell mass. Quantisation is an absolute error of at most 0.5/2²⁴ ≈ 3e-8 per add, so the worst relative error (1.8e-5) sits in near-empty cells just above the 1e-3 cut, and it shrinks as cell mass grows. That buys bit-identical replays, exact mass conservation tests, and, on this GPU, 4× speed.
- MSL has no 64-bit atomic add, so 32-bit fixed point is the only order-independent option (`oss-integration-lessons.md:53` notes there is no `threadgroup atomic_float` either).
- The timings are from an M1 Max (Apple7) under load. The A17 Pro (Apple9) ratio is DEV?.

---

## 5. Swift 6 strict concurrency: real-time callbacks (the LabKit port rule)

What the SDK says about Sendability (SDK):

| Callback type | Annotation | Where |
|---|---|---|
| `AVAudioSourceNodeRenderBlock` | `NS_SWIFT_NONSENDABLE` | `AVFAudio.framework/Headers/AVAudioSourceNode.h:41` |
| `AVAudioSourceNodeRenderBlockRealtimeSafe` (new in iOS 27) | `__SWIFT_UNAVAILABLE_MSG("Swift is not supported for use with audio realtime threads")` | same file, line 48 |
| `AVAudioNodeTapBlock` (old `installTap`) | `NS_SWIFT_NONSENDABLE` | `AVAudioNode.h:32` |
| `installAudioTap(onBus:bufferSize:format:tapProvider:)` (iOS 27) | `tapProvider: @escaping @Sendable (AVReadOnlyAudioPCMBuffer, AVAudioTime) -> Void`, `throws` | `AVFAudio.swiftmodule/arm64e-apple-ios.swiftinterface:63` |
| `CMDeviceMotionHandler`, `CMMagnetometerHandler`, `CMAltitudeHandler` | none (implicitly non-Sendable) | `CMMotionManager.h:70, 78`; `CMAltimeter.h:23` |
| `CHHapticEngineStoppedHandler`, `CHHapticEngineResetHandler` | none | `CHHapticEngine.h:118, 128` |
| `MTLCommandBufferHandler` | `NS_SWIFT_SENDABLE` (safe) | `MTLCommandBuffer.h:221` |
| `MTKViewDelegate.mtkView(_:drawableSizeWillChange:)`, `draw(in:)` | `NS_SWIFT_UI_ACTOR` (main actor) | `MTKView.h:260, 267` |

Verified behaviour (RUN-SIM, iPhone 17 Pro simulator; the source is `LabKitProbe/Sources/ProbeKit/Synth.swift`):

```swift
// SAFE: built in a nonisolated context, so the closure carries no actor isolation.
nonisolated static func makeRenderBlock(state: SynthState, sampleRate: Double) -> AVAudioSourceNodeRenderBlock {
  var phase: Float = 0
  return { _, _, frameCount, abl in /* … */ state.framesRendered.add(Int(frameCount), ordering: .relaxed); return noErr }
}

// SAFE: explicit @Sendable makes the inline closure nonisolated even inside a @MainActor method.
node = AVAudioSourceNode(format: format) { @Sendable _, _, frameCount, abl in /* … */ return noErr }

// CRASH (compiles with no warning): inline closure inside a @MainActor method inherits @MainActor,
// and Swift 6 inserts an executor check that fires on AURemoteIO::IOThread.
node = AVAudioSourceNode(format: format) { _, _, frameCount, abl in /* … */ return noErr }
```

Crash report `~/Library/Logs/DiagnosticReports/LabKitProbeApp-2026-10-03-153250.ips`:
- `EXC_BREAKPOINT (SIGTRAP)` on thread `AURemoteIO::IOThread`;
- frames: `_dispatch_assert_queue_fail` → `dispatch_assert_queue` → `_swift_task_checkIsolatedSwift` → `swift_task_isCurrentExecutorWithFlagsImpl` → `closure #1 in ProbeSynth.start(isolatedBlock:)` → `+[AVAudioSourceNode pullInputBlockFromRenderBlock:]_block_invoke`.

The rules for LabKit follow from this:

1. Every closure handed to an Apple API that calls it **off the main thread** must be built in a `nonisolated` function or be explicitly `@Sendable`. That covers:
   - the audio render block;
   - the audio tap;
   - CoreMotion handlers on a non-main `OperationQueue`;
   - CoreHaptics `resetHandler` / `stoppedHandler`.

   Typechecked spellings (TC):
   - `h.resetHandler = { @Sendable in }`
   - `h.stoppedHandler = { @Sendable _ in }`

   This applies to code ported from Gyre:
   - `Gyre/Gyre/Feedback/HumSynth.swift:79`: inline render block.
   - `Gyre/Gyre/Feedback/Haptics.swift:24-27`: handlers that hop with `DispatchQueue.main.async`.
   - `Gyre/Gyre/Sensors/MicListener.swift:99`: deprecated `installTap`; move to `installAudioTap`, whose block is already `@Sendable`.

   Gyre is safe today only because it compiles in Swift 5 mode (`Gyre/project.yml:10`) with non-actor classes.
2. Share parameters with the real-time thread through `Synchronization.Atomic`, held in a `final class …: Sendable`. In the probe this was `Atomic<UInt32>` holding a `Float` bit pattern, plus `Atomic<Int>` counters (RUN-SIM). No locks on the render thread.
3. CoreMotion delivered to `.main` passes the check. The probe uses `MainActor.assumeIsolated { … }` inside the handler (BUILD).
   - This is not runtime-tested, because the simulator reports `deviceMotion=false magnetometer=false altimeter=false`.
   - For 100 Hz motion feeding the physics thread, use a private serial `OperationQueue` and a nonisolated handler that writes into an atomic or lock-protected snapshot (INF).
4. A `@MainActor final class Renderer: NSObject, MTKViewDelegate` is the correct Swift 6 shape. It compiled warning-free and drew 91 frames in about 1.5 s (RUN-SIM).
5. `AVAudioSourceNodeRenderBlockRealtimeSafe` cannot be used from Swift. Stay on the classic render block.

### 5.1 `defaultIsolation(MainActor.self)` (round 2; RUN-SIM, NEG)

Target `ProbeMainDefault`, built with `swiftSettings: [.defaultIsolation(MainActor.self)]` under tools 6.4. Its source is `r2/LabKitProbe/Sources/ProbeMainDefault/MainDefault.swift`:
- `public final class MDSynth` has no annotation. `MainActor.assertIsolated` inside it passes, so it is MainActor.
- It holds an explicitly `nonisolated public final class MDCounters: Sendable` (an `Atomic<Int>`) that the render thread may touch.
- `start(inline:)` builds the `AVAudioSourceNode` render block either inline or through `nonisolated static func makeBlock(_:)`.

| Case | Result |
|---|---|
| Compile the target, with the inline render block (`xcodebuild` sim Debug, device Release, `swift build`) | 0 warnings |
| Run `-mdInline` (closure formed inline in the implicitly MainActor method) | **trap**. `EXC_BREAKPOINT` on `AURemoteIO::IOThread`: `_dispatch_assert_queue_fail ← dispatch_assert_queue ← _swift_task_checkIsolatedSwift ← swift_task_isCurrentExecutorWithFlagsImpl ← closure #1 in MDSynth.start(inline:) ← +[AVAudioSourceNode pullInputBlockFromRenderBlock:]_block_invoke` (`~/Library/Logs/DiagnosticReports/LabKitProbeApp-2026-10-03-162545.ips`) |
| Run the default, with `nonisolated static func makeBlock` | 50,688 frames rendered in 1.0 s, no trap |
| A normal (nonisolated-default) Swift 6 target calls `mdKnobMap(_:)`, `MDSpec(lo:hi:)`, `MDSpec.map(_:)` and a generic `same<T: Equatable>(MDSpec, MDSpec)` from synchronous code | **6 errors**: `call to main actor-isolated global function 'mdKnobMap' in a synchronous nonisolated context`, `… initializer 'init(lo:hi:)' …`, `… instance method 'map' …`, and `main actor-isolated conformance of 'MDSpec' to 'Equatable' cannot be used in nonisolated context` (SE-0470 isolated conformances are inferred under this mode) |
| The same caller uses `nonisolated public func mdKnobMapNonisolated`, `nonisolated public struct MDSpecNonisolated: Equatable, Sendable`, and a `Task.detached` that compares two of them | builds clean (3.4 s) |
| An XCTest method calls the MainActor API | needs `@MainActor func test…()`; then it passes under `swift test` |

What this means for `LabKitUI` (the module `labkit-from-gyre.md:118` puts under this mode):
1. Everything left unannotated in `LabKitUI` is MainActor-only, **including value types and their `Equatable`/`Hashable` conformances**. Anything a physics step, the render thread or `LabKitCore` must call (knob mapping maths, detent tables, theme constants read by renderers) must live in `LabKitCore` or be declared `nonisolated`. This generalises the three escapes `labkit-from-gyre.md` §8.4 found.
2. Inside `LabKitUI`, any closure handed to an API that calls it off the main thread is a trap by default, and it compiles silently. Keep audio, haptics and motion callbacks out of `LabKitUI` entirely (they belong in `LabKitFeedback` / `LabKitSensors`, which stay nonisolated-default with explicit `@MainActor` owners). If one must live in `LabKitUI`, build it in a `nonisolated static` factory or mark it `{ @Sendable … }`.
3. Never apply this mode to `LabKitCore`, `LabKitRender` kernels or the CPU reference solver.

---

## 6. SDK API verification (iPhoneOS27.0.sdk / iPhoneSimulator27.0.sdk)

All rows were type-checked in Swift 6 mode against both SDKs (`tc/apis.swift`). The only diagnostic was the iOS 26 deprecation of `UIScreen.main`. The same APIs were also compiled inside `ProbeKit` for simulator Debug and device Release (BUILD); where a row says RUN-SIM, it also ran.

| API | Swift spelling used | Declaration (SDK) | Status |
|---|---|---|---|
| Tabs picker | `.pickerStyle(.tabs)` | `SwiftUI.swiftinterface:16485-16492` `TabsPickerStyle`, `@available(iOS 27.0, macOS 27.0, …)` | TC, RUN-SIM (rendered, see screenshot). Also compiles on macOS 27 under `swift test`. Gyre uses it: `Gyre/Gyre/UI/Console.swift:27` |
| `Glass` | `Glass.regular.tint(.cyan.opacity(0.2)).interactive()`, `.clear`, `.identity` | `SwiftUICore.swiftinterface:6874-6886`: `struct Glass: Equatable, Sendable`, `tint(_:)`, `interactive(_:)`; iOS 26+ | TC, RUN-SIM |
| `glassEffect` | `.glassEffect(.regular, in: .rect(cornerRadius: 22))` | `SwiftUICore.swiftinterface:2899`: `glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape())`; iOS 26+ | TC, RUN-SIM. Gyre: `UI/GlassKnob.swift:79` |
| `GlassEffectContainer` | `GlassEffectContainer(spacing: 18) { … }` | `SwiftUICore.swiftinterface:10990`: `init(spacing: CGFloat? = nil, @ContentBuilder content:)` | TC, RUN-SIM. Gyre: `UI/Console.swift:20` |
| `glassEffectID` | `.glassEffectID("reset", in: ns)` with `@Namespace` | `SwiftUICore.swiftinterface:21206`: `glassEffectID(_ id: (some Hashable & Sendable)?, in: Namespace.ID)` | TC, RUN-SIM. Gyre: `UI/Console.swift:189` |
| `glassEffectUnion` | `.glassEffectUnion(id: "u", namespace: ns)` | `SwiftUICore.swiftinterface:12111` | TC |
| Glass buttons | `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)` | `SwiftUI.swiftinterface:1455, 4377` | TC, RUN-SIM |
| `connectNode` | `try engine.connectNode(node, to: engine.mainMixerNode, format: format)` | `AVAudioEngine.h:295` `NS_SWIFT_NAME(connectNode(_:to:format:))`, iOS/macOS 27. Old `connect:to:format:` deprecated in iOS 27 (`:281`) | TC, RUN-SIM (73k frames rendered) |
| `installAudioTap` | `try node.installAudioTap(onBus: 0, bufferSize: 1024, format: nil) { buf, when in … }`, with `buf.channelData(0)` returning `.float(Span<Float>)` | `AVFAudio.swiftinterface:63`, `AVReadOnlyAudioPCMBuffer: Sendable` at `:335` | TC, RUN-SIM (15 tap buffers in 1.5 s on the mixer) |
| `CHHapticEngine` | `CHHapticEngine.capabilitiesForHardware().supportsHaptics`, `try CHHapticEngine()`, `playsHapticsOnly`, `isAutoShutdownEnabled`, `makeAdvancedPlayer(with:)`, `sendParameters(_:atTime: CHHapticTimeImmediate)` | `CHHapticEngine.h:143, 180, 217, 231` | TC. The simulator reports `supportsHaptics=false`, so it was not exercised (DEV?) |
| `CMMotionManager` | `startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { m, _ in … }`, `startMagnetometerUpdates(to:)`, iOS 27 `deviceMotionBody = view` | `CMMotionManager.h:401, 282, 334` (all `API_UNAVAILABLE(macos)`) | TC. The simulator reports unavailable (fakes required, house rule 14) |
| `CMAltimeter` | `CMAltimeter.isRelativeAltitudeAvailable()`, `startRelativeAltitudeUpdates(to: .main)`, `CMAltimeter.authorizationStatus()`, `isAbsoluteAltitudeAvailable()` | `CMAltimeter.h:57, 70, 86` (`API_UNAVAILABLE(macos)`); needs `NSMotionUsageDescription` | TC. Unavailable in the simulator |
| Thermal state | `ProcessInfo.processInfo.thermalState` (`.nominal/.fair/.serious/.critical`), `isLowPowerModeEnabled`; typed message `for await _ in NotificationCenter.default.messages(of: ProcessInfo.processInfo, for: .thermalStateDidChange)` | `NSProcessInfo.h:480, 508`; `Foundation.swiftinterface:15904` `ThermalStateDidChangeMessage: AsyncMessage` (iOS 26) | TC, RUN-SIM (`thermal=0 nominal`). Orbitals uses it: `Orbitals/Rendering/OrbitMetalView.swift:176` |
| `MTKView.preferredFramesPerSecond` | `view.preferredFramesPerSecond = 120` | `MTKView.h:178` (an `NSInteger` with no stated cap; it picks the closest rate the screen supports) | RUN-SIM: reads back 120. The simulator screen's `maximumFramesPerSecond` is **60**, so about 60 fps was delivered (91 frames in about 1.5 s). On device it needs `CADisableMinimumFrameDurationOnPhone: true`, as Gyre already sets at `HoloRenderer.swift:732`. 120 Hz on the phone is DEV? |
| `supportsFamily(.apple9)` | `device.supportsFamily(.apple9)` | `MTLDevice.h:199` (`MTLGPUFamilyApple9 = 1009`), `:200` Apple10, `:213` Metal4 (iOS 26) | TC, RUN-SIM (false on the simulator, see §4.3). `.metal4` is missing from the simulator SDK: use `MTLGPUFamily(rawValue: 5002)!` |
| Command-buffer wait | `await cb.completed()` | `MTLCommandBuffer.h:354` `waitUntilCompleted` `NS_SWIFT_UNAVAILABLE_FROM_ASYNC("Use 'await completed()' instead.")`; `Metal.swiftinterface:73` | BUILD, RUN-SIM |

Also from the iOS 27 SDK:
- `CMMotionManager.deviceMotionBody` (iOS 27, `CMMotionManager.h:334`) accepts a `UIView`. This confirms the Spectra `sdk-sensors.md` finding 7.
- `MTKView.currentMTL4RenderPassDescriptor` exists (iOS 26, `MTKView.h:170`).

---

## 7. Commands that worked

**App: simulator build, install, and run with console output (RUN-SIM)**
```zsh
cd …/ProbeApp && xcodegen generate --quiet
xcodebuild -project LabKitProbeApp.xcodeproj -scheme LabKitProbeApp -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath ../dd-app build
U=9AC0979F-7162-42A7-A2BD-FB3CC1D6439D
xcrun simctl install $U ../dd-app/Build/Products/Debug-iphonesimulator/LabKitProbeApp.app
xcrun simctl launch --console-pty --terminate-running-process $U com.utkarsh.labkitprobe.toolchaincheck -probeAndExit
xcrun simctl spawn $U log show --last 10m --style compact \
  --predicate 'subsystem == "com.utkarsh.labkitprobe.toolchaincheck"'     # os_log Logger lines also land here
xcrun simctl io $U screenshot probe.png
```
- Launch arguments after the bundle id reach `ProcessInfo.processInfo.arguments` (`-probeAndExit`, `-isolatedBlock`, `-sendableBlock`).
- That is the same mechanism as Gyre's `-fakeMic` / `-fakeAR` / `-simSway`.
- `print` + `fflush(stdout)` lines appear live under `--console-pty`.
- The app calls `exit(0)` when it is done, so the command returns: 3.5 s for launch, probe and exit.

**App: device compile (no signing, nothing installed) (BUILD)**
```zsh
xcodebuild -project LabKitProbeApp.xcodeproj -scheme LabKitProbeApp -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath ../dd-dev CODE_SIGNING_ALLOWED=NO build
```
For a real install, use the house-rule-21 command (`-allowProvisioningUpdates DEVELOPMENT_TEAM=YOUR_TEAM_ID`, then `xcrun devicectl device install app --device 47C11007-EC72-5611-98B6-FC3FC5CD65F2 …`). The phone is currently paired over the network ("available (paired)").

**Package: tests on macOS (RUN-MAC)**
```zsh
cd <non-iCloud copy>/LabKit
TOOLCHAINS=metal swift test                    # all test targets, Metal included, GPU kernels run on the Mac
# alternatives:
swift build --product LabKitPackageTests && swift test --skip-build   # only if NO test target depends on a Metal target
xcodebuild test -scheme LabKit-Package -destination 'platform=macOS'  # finds the Metal toolchain itself (383 s wall under load)
```
Notes:
- `swift test --filter X` does **not** narrow what gets built.
- `swift build --target <TestTarget>` fails with `Could not find target`.
- `--target` and `--build-tests` are mutually exclusive.
- `swift build --product <Package>PackageTests` builds only the test targets and their dependencies. It skipped the Metal and UIKit targets, and 4 of 4 ProbeCore tests passed.
- Harmless noise:
  - `warning: missing creator for mutated node: (…_ProbeMetal.bundle/Contents/MacOS)`;
  - Swift Testing's `Test run with 0 tests` banner after the XCTest results.
- `--build-system native` is deprecated, copies `Probe.metal` raw into the bundle and does not compile it, so do not use it.

**Round 2: executables, hosted tests, Swift Testing (RUN-MAC, RUN-SIM)**
```zsh
cd <non-iCloud copy>/LabKit
swift run labkit-physcheck                                  # Core-only exe: builds just its closure, no TOOLCHAINS needed
TOOLCHAINS=metal swift run -c release labkit-physcheck      # needed once the exe depends on LabKitRender (.metal)
swift run --scratch-path /tmp/x/build-a probe-corecheck     # --scratch-path keeps separate build trees side by side

cd <non-iCloud copy>/Rheo && xcodegen generate --quiet
xcodebuild test -project Rheo.xcodeproj -scheme Rheo \
  -destination 'platform=iOS Simulator,id=<UDID>' -derivedDataPath ../dd      # hosted RheoTests (XCTest + Swift Testing)
xcodebuild -project Rheo.xcodeproj -scheme Rheo -showBuildSettings | grep -E 'SWIFT_DEFAULT_ACTOR|EFFECTIVE_SWIFT'
```
- Probe equivalents: `swift run probe-corecheck` printed `corecheck: languageMode=6 sheDrift=0.0253…` with **no** `TOOLCHAINS` on a fresh scratch path (24 s cold). `swift run probe-physcheck` without it failed in `CompileMetalFile` on the XcodeDefault stub, and passed with it.
- Swift Testing `@Test(arguments:)` and XCTest can share one test target. `swift test` prints the XCTest suites, then Swift Testing's own run (`Test "Symplectic Euler free fall matches the closed form" with 3 test cases passed`). The `Test run with 0 tests` banners are the other test bundles.
- `-destination 'platform=iOS Simulator,id=<UDID>'` pins the device. Use it with a dedicated simulator so parallel sessions cannot swap the app under you (finding 11).

**Mirror build for the iCloud folder (`mirror-build.sh`, verified on the scratch layout: 72 s clean, including rsync and xcodegen)**
```zsh
#!/bin/zsh
# Rheo/Tools/build.sh: xcodebuild hangs on projects inside the iCloud-synced folder (Gyre Tools/build.sh:2-3),
# so mirror BOTH Rheo and its sibling LabKit, keeping the ../LabKit relative path, and build there.
set -e
APP="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(dirname "$APP")"
WORK="${RHEO_BUILD_DIR:-${TMPDIR:-/tmp}/RheoBuild}"
mkdir -p "$WORK/src"
for d in Rheo LabKit; do
  rsync -a --delete --exclude '.build' --exclude '*.xcodeproj' --exclude '* 2.*' --exclude '* 2' \
    "$ROOT/$d/" "$WORK/src/$d/"
done
cd "$WORK/src/Rheo"
xcodegen generate --quiet
case "${1:-sim}" in
  sim)    xcodebuild -project Rheo.xcodeproj -scheme Rheo -configuration Debug \
            -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$WORK/dd" build ;;
  device) xcodebuild -project Rheo.xcodeproj -scheme Rheo -configuration Release \
            -destination 'generic/platform=iOS' -allowProvisioningUpdates -derivedDataPath "$WORK/dd" build ;;
  test)   cd "$WORK/src/LabKit" && TOOLCHAINS=metal swift test ;;
esac
```
- `'* 2.*'` / `'* 2'` drop iCloud conflict copies (house rules note).
- Excluding `*.xcodeproj` forces a clean regeneration.

---

## 8. Timings (M1 Max, 10 cores, 64 GB; round 1 at load average 690–850, round 2 at 30–300)

| Step | Wall time |
|---|---|
| `xcodegen generate` | 0.10 s |
| Package-only `xcodebuild -scheme ProbeMetal` (simulator, clean) | 13.3 s |
| App simulator Debug, **clean** (C + Swift 6/5 + 2 metallibs, before Box2D) | 28.8 s |
| App simulator Debug, clean, **with Box2D**, through `mirror-build.sh` (rsync + xcodegen + build) | 72.0 s |
| No-op rebuild | 3.6 s |
| Touch one package Swift file | 4.9 s |
| Touch package `.metal` | 3.8 s (CompileMetalFile + MetalLink of the bundle only) |
| Touch app Swift file | 4.7 s |
| Touch the shared C/MSL header | 6.4 s (both metallibs rebuilt) |
| Device Release, generic iOS, clean (before Box2D) | 14.2 s |
| Device Release, incremental, adding Box2D | 15.4 s |
| `simctl install` | 0.7 s |
| `simctl launch --console-pty` → probe → `exit(0)` | 3.5 s (the probe itself takes 1.7–1.8 s, including a 1.5 s audio wait) |
| `TOOLCHAINS=metal swift test`, clean, 3 test bundles (core, Metal GPU, Box2D) | 56.6 s (40.9 s before Box2D) |
| `TOOLCHAINS=metal swift test`, no-op | 4.9 s |
| `swift build --product ProbeCore` (first) | 21 s |
| `xcodebuild test -scheme LabKitProbe-Package -destination platform=macOS`, clean | 383.6 s wall, 70 s user (dominated by contention) |

**Round 2 re-timings (16:17–16:28).** The 1-minute load average was about 30 at the start and rose to about 300 mid-way, as other sessions resumed. These are the more representative numbers:

| Step | Load | Wall time |
|---|---|---|
| `TOOLCHAINS=metal swift test`, **clean** copy (no `.build`), round-1 package (C + Swift 6/5 + Metal + Box2D, 3 test bundles) | ~30 | **15.7 s** (36 s user) |
| `TOOLCHAINS=metal swift test`, incremental after adding parity/scatter/MainDefault/Swift Testing | ~30 | 10.5 s |
| App simulator Debug, **clean**, round-1 sources (incl. Box2D, 2 metallibs) | ~30 | **15.2 s** |
| App simulator Debug, incremental after round-2 sources | ~30 | 7.2 s |
| `xcodebuild test` hosted tests (incremental build + install + 2 tests) | ~30 | 11.2 s |
| `swift run probe-corecheck`, fresh scratch path, no `TOOLCHAINS` | ~30 | 24.2 s (cold module cache for that path) |
| `xcodebuild -scheme ProbeMetal`, generic iOS Simulator, clean (the no-`resources:` copy) | ~30 | 15.0 s |
| No-op app rebuild | ~270 | 6.0 s |
| Touch package `.metal` | ~270 | 5.6 s |
| Touch shared header `ProbeRheo.h` (3 package + 1 app shader recompiled) | ~300 | 9.0 s |
| Touch package Swift file | ~300 | 7.0 s |
| Touch app Swift file | ~300 | 6.7 s |
| Device Release, generic iOS, **clean**, all round-2 sources | ~300 | 23.9 s (app 636 KB; package metallib 38,744 B, app metallib 4,624 B) |
| `simctl install` (simulator just booted) | ~30 | 24.3 s (round 1, warm: 0.7 s) |
| `simctl launch --console-pty` → full probe → `exit(0)` | ~30 | 7.1 s (probe 3.73 s, including 2.5 s of audio waits) |

At normal load, a clean LabKit `swift test` and a clean Rheo simulator build should each take about 15 s on this M1 Max. The incremental edit-build loop takes 5–7 s.

---

## 9. Gotchas (each one was hit during this check)

1. The `metal` stub in XcodeDefault fails under the SwiftPM CLI. Fix with `TOOLCHAINS=metal`; it does not change the Swift compiler (`TOOLCHAINS=metal swift --version` is still 6.4). If Xcode updates and the component goes missing, run `xcodebuild -downloadComponent MetalToolchain`. Check with `xcodebuild -showComponent MetalToolchain -json`.
2. Neither builder passes dependency include paths to `metal`. Use relative includes in package shaders and `MTL_HEADER_SEARCH_PATHS` in the app.
3. `MTLGPUFamily.metal4` is absent from the simulator SDK (and present in the device SDK). Use the raw value 5002.
4. The simulator GPU fails every modern `supportsFamily` check, has 512 max threads per group, 16 KB threadgroup memory, a 256 MB max buffer, and its screen runs at 60 Hz.
5. `waitUntilCompleted()` is a compile error inside `async` functions. `makeComputePipelineState` silently becomes `async` there.
6. The Swift 6 executor-check trap: §5. It compiles cleanly and crashes only at runtime on the callback thread.
7. CoreMotion, CMAltimeter and UIKit are unavailable on macOS. Wrap with `#if os(iOS)` so `swift test` builds the whole package. SwiftUI Glass, `.pickerStyle(.tabs)`, AVFAudio `connectNode` / `installAudioTap` and `Synchronization.Atomic` **do** compile on macOS 27.
8. The package needs `.macOS(.v27)`, or Metal falls back to an old MSL and `atomic_float` is unknown.
9. A C module that is not a product needs an explicit `import`, and depending on that leak is fragile. Make shared-types targets products.
10. A shared booted simulator plus a reused bundle id means you silently run someone else's app. Use unique ids or a dedicated device (`xcrun simctl create "Rheo QA" "iPhone 15 Pro Max" …`).
11. App metallibs in Debug embed sources (55 KB) and package metallibs do not (13 KB).
12. `IDERunDestination: Supported platforms for the buildables in the current scheme is empty` is printed by `xcodebuild` on package schemes. It is harmless.
13. The `appintentsmetadataprocessor` "Metadata extraction skipped" warning appears on every app build. It is harmless.
14. SwiftPM uses `include/<TargetName>.h` as the umbrella header when it exists, and sibling headers it does not `#include` are invisible to Swift (§4.2).
15. Under `defaultIsolation(MainActor.self)`, unannotated value types, free functions **and conformances** are MainActor. Callers in nonisolated targets get errors. Inline real-time closures in that module trap at runtime and produce no warning (§5.1).
16. `atomic_float` accumulation gives a different bit pattern on almost every run. GPU kernels must never be checked bitwise against a previous GPU run or against the CPU. Use fixed point for order-independent sums, and relative tolerances for parity (§4.4, §4.5).
17. XCTest methods are nonisolated. To test MainActor API, mark the test method `@MainActor`.
18. `swift run X` / `swift build --product X` build only X's dependency closure. That is how a Core-only physcheck avoids the Metal toolchain, but it also means a plain `swift build` (all targets) still needs `TOOLCHAINS=metal`.

---

## 10. Box2D v3.1.1 vendoring details

- Source: <https://github.com/erincatto/box2d>, tag `v3.1.1`, commit `8c661469c9507d3ad6fbd2fea3f1aa71669c2fe3`. **MIT License**, "Copyright (c) 2022 Erin Catto". Ship `LICENSE` and a `THIRD_PARTY_NOTICES.md` / `UPSTREAM.md` the way Powder does (`Powder Modernization/Native/Packages/PowderEngine/UPSTREAM.md`).
- Layout used: copy `include/` and `src/` (minus `src/CMakeLists.txt` and `src/box2d.natvis`) plus `LICENSE` into `Sources/Box2D/`. The target is `sources: ["src"], publicHeadersPath: "include", cSettings: [.headerSearchPath("src")]`. SwiftPM generates the module map, and `import Box2D` exposes the `b2*` C API.
- Upstream CMake builds with `C_STANDARD 17` (`src/CMakeLists.txt:92`). SIMD is chosen in `src/core.h:60-74`: NEON on arm64, so the iOS device build uses `B2_SIMD_NEON`. No defines were needed. Leave `BOX2D_VALIDATE` / `BOX2D_AVX2` off.
- Swift 6 call pattern that ran (from `ProbePhysics.swift`):
  - `var worldDef = b2DefaultWorldDef(); worldDef.gravity = b2Vec2(x: 0, y: g); let world = b2CreateWorld(&worldDef)`
  - `b2CreateBody(world, &bodyDef)`
  - `b2MakeBox(0.5, 0.5)`
  - `b2CreatePolygonShape(body, &shapeDef, &box)`
  - `b2World_Step(world, 1.0 / 60.0, 4)`
  - `b2Body_GetPosition(body).y`
  - `b2DestroyWorld(world)`

  The handles (`b2WorldId`, `b2BodyId`) import as small value structs, so they are Sendable-friendly.
- Builds: warning-free on macOS (`swift test`), on the iOS simulator and on iOS device Release.

---

## 11. Not verified (and what would settle each)

- On the iPhone 15 Pro Max:
  - `supportsFamily(.apple9) == true`;
  - `maxThreadsPerThreadgroup`;
  - `atomic_float` throughput;
  - actual 120 Hz delivery;
  - CoreMotion, CMAltimeter and CoreHaptics callbacks under Swift 6;
  - fast-math versus CPU parity on Apple9 (§4.4), and the `atomic_float` versus fixed-point P2G ratio on Apple9 (§4.5).

  To settle these, install the round-2 probe app on the phone after asking him. `-probeAndExit` prints everything, parity and scatter included.
- Whether `xcodebuild` or `swift test` also hang when the **package** (not only the project) sits in the iCloud folder. Not tried, because this task was confined to the scratchpad. The mirror script sidesteps the question.
- `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` set on the **app** target (Xcode build setting rather than the SwiftPM setting). It is expected to behave like §5.1, because it is the same compiler flag, but it was not run.
- Closed in round 2: `resources:` under `xcodebuild` (§2), the numeric effect of the safe pragma (§4.4), and `defaultIsolation(MainActor.self)` behaviour (§5.1).

---

## 12. Round 2 index (what was added on the continuation, and where it is written up)

| Check | Result | Section |
|---|---|---|
| `resources:` removed, `xcodebuild` | metallib still built into the resource bundle; `Bundle.module` compiles | §2 |
| Shared-types C target as an explicit product | app imports it explicitly; builds and runs | §2, §3 |
| XcodeGen hosted unit-test target + `scheme.testTargets` | `TEST SUCCEEDED`; package modules importable; package metallib loads from the host app | §3 |
| Second public header in the C target | invisible to Swift until the umbrella header includes it | §4.2 |
| GPU vs CPU parity, fast / `precise::` / safe pragma | all within 5.5–5.7e-6 of Double, same as CPU `Float`; never bitwise | §4.4 |
| P2G `atomic_float` vs 2²⁴ fixed point | float differs on 7/7 runs; fixed point bit-identical and 4× faster (M1 Max) | §4.5 |
| SE-0466 `defaultIsolation(MainActor.self)` | inline render block traps; value types and conformances become MainActor-only | §5.1 |
| `swift run` Core-only vs Metal-dependent executable | Core-only needs no `TOOLCHAINS`; Metal one needs it; `Bundle.module` works for executables | §7 |
| Swift Testing + XCTest in one target | both run under `swift test` and `xcodebuild test` | §7 |
| Re-timing at lower load | clean `swift test` 15.7 s; clean sim build 15.2 s; incremental 5–7 s | §8 |
| SDK spot-check of round-1 citations | `TabsPickerStyle` 16492, `Glass` 6874, `GlassEffectContainer` 10990, `glassEffectID` 21206, `connectNode` `AVAudioEngine.h:295`, `MTLGPUFamilyMetal4` only in the device SDK (`MTLDevice.h:213`) | §6 |
