# OSS integration lessons: vendoring, threading and Metal particle rendering

**For:** LabKit (shared toy engine) and Rheo, the Non-Newtonian Toy
**Date:** 3 October 2026
**Sources read:** Powder Modernization (`Native/Packages/PowderEngine`, `Native/App`, `docs/`) and Nano (`Core`, `Rendering`, `App`, manifests). Gyre was cross-checked through `Spectra/Docs/research/design-gyre.md` and its source.
**Experiments:** run in `scratchpad/oss-integration/` (full path in Appendix A). These were a vendored Box2D probe package, an XcodeGen iOS probe app, Metal atomics and encode benchmarks, and a Swift 6 render-thread skeleton.
**Revision 2 (same day):** re-verified the key claims against source, corrected several Powder line citations, replaced the runtime-shader workaround with `TOOLCHAINS=metal` (re-verified here), moved the manifest to tools-version 6.4, and added §8, which reconciles this note with the sibling notes `oss-engine-survey.md`, `toolchain-checks.md` and `labkit-from-gyre.md`. Where those notes disagree with this one, §8 states which choice to follow.

How each claim is marked:

- **[V]** I verified it in this session by building, running or reading source.
- **[S]** It is reported by the source project's own evidence documents. I did not re-run it.
- **[I]** It is an inference or recommendation that has not been tested.

All performance numbers come from the host, an **Apple M1 Max** running macOS 27.2 with Xcode 27.0 beta (27A5194q) and Swift 6.4. None were measured on the user's iPhone 15 Pro Max (A17 Pro).

---

## 0. Decisions in one screen

1. **Vendor Box2D v3.1.1** (MIT; commit `8c661469c9507d3ad6fbd2fea3f1aa71669c2fe3`) as an **unmodified C17 target, `CBox2D`**, inside LabKit.
   - Expose only `box2d/box2d.h` through a hand-written `module.modulemap`.
   - Wrap it in a Swift target, **`LabKitRigid`**, that uses `internal import CBox2D` so apps never see the C API.
   - No C or C++ bridge is needed, because Box2D is already a C API. [V]
2. **Copy Powder's provenance convention.** Each vendored dependency gets `UPSTREAM.md` and `UPSTREAM.json` next to its source. Every dependency gets a section with its full licence text in the repository's `THIRD_PARTY_NOTICES.md`, and the app bundles that file and credits it in the InfoSheet. [V source, I applied]
3. **Build flags are not optional:**
   - `.define("NDEBUG", .when(configuration: .release))`
   - `.unsafeFlags(["-ffp-contract=off"])`, which mirrors upstream CMake.
   - Optimise the C target in Debug as well (`-O2`).

   SwiftPM's Release build is `-Os` with **no** `NDEBUG`, and Debug is `-O0 -DDEBUG=1`. A Debug `-O0` Box2D step costs about 10–21× more than an optimised one. [V]
4. **Declare a smaller metre:** call `b2SetLengthUnitsPerMeter(0.1)` once per process, before any world exists.
   - Box2D's restitution and sleep thresholds are physical values tuned for bodies of 0.1–10 m.
   - With the defaults, a 4 mm bead does not bounce, and a bead sinking through a viscous fluid at about 3 cm/s **falls asleep mid-fluid after 0.51 s**. [V]
   - Bodies coupled to the fluid should also use `enableSleep = false`.
5. **Box2D state is process-global.** That covers the world table, length units and the assert hook.
   - Create and destroy worlds on one thread.
   - Never change the units after start-up.
   - Run Box2D tests with `swift test --no-parallel`, or put them all in a single `.serialized` suite. Parallel suites gave **flaky results (3 of 5 runs failed)**. [V]
6. **Rheo threading: the render loop owns time** (Gyre's pattern). Do not use Powder's worker-actor and snapshot pattern.
   - MPM state stays resident on the GPU.
   - Encode cost is negligible: 0.05–0.07 ms of CPU for 64–192 dispatches, and 0.25–0.5 ms even for 680. [V]
   - The GPU is the budget. Each *dependent* dispatch also costs about 4–10 µs of fixed GPU time on the M1 Max, so keep it to about 100 dispatches or fewer per 120 Hz frame. Use fused kernels and a concurrent encoder with explicit barriers (§3.10). [V]
   - Advance simulated time in fixed quanta: 1/120 s, scaled by the Time Scale knob. Each quantum is one Box2D step plus n MPM substeps. n comes from the survey's rule (`oss-engine-survey.md` §7.4, n = 2–8), or is higher if the solver stays explicit-elastic.
   - Cap the quanta per display frame, so that a slow GPU degrades into slow motion rather than a death spiral.
   - Keep at most 2 frames in flight, and never block the main thread (use Powder's non-blocking semaphore).
   - Rigid coupling has one frame of latency, through per-slot shared buffers.
   - A `CAMetalDisplayLink` render thread is the drop-in fallback. Its Swift 6 skeleton type-checks. [V]
7. **Do the P2G scatter with 32-bit fixed-point integer atomics, not `atomic_float`.**
   - On the M1 Max, float atomics in a hashed-scatter microbenchmark were 1.5–3.5× slower at MPM-like contention (two sessions) and about 260× slower at extreme contention.
   - They were **non-deterministic**: 6 distinct sums in 6 runs, then 4 in 6 on the re-run. The fixed-point version was bit-identical every time. [V]
   - The survey's realistic P2G measured 1.3–1.5× (`oss-engine-survey.md` §4).
   - MSL has no `threadgroup atomic_float` at all, so tile-local accumulation must use fixed point anyway [S: survey, compiled there].
8. **Share one C header between Swift and MSL** for every GPU struct.
   - The `.metal` file includes it by relative path.
   - xcodebuild compiles the package's `.metal` into `Bundle.module/default.metallib`, and on iOS it loads in 1.2 ms. [V]
   - The SwiftPM CLI compiles package Metal only when it runs with **`TOOLCHAINS=metal`** (§3.6). Then `swift test` builds the real `default.metallib` and the GPU test passes. [V, re-verified in revision 2]
9. **Validate in three tiers:**
   1. A host CPU reference with `swift test`.
   2. GPU kernels against that reference, using an offscreen harness built from the production `.metal`.
   3. Device runs with OSSignposter and command-buffer GPU timing.

   Each tier is recorded in Powder's evidence style: date, command, exit code, counts, and what the result does **not** establish.
10. **Names and placement** (reconciled in §8):
    - The C target is `CBox2D` with an explicit modulemap.
    - The Swift wrapper is `LabKitRigid`, following labkit-from-gyre's `LabKit*` product naming.
    - LabKit-wide GPU structs go in `LabKitShaderTypes`.
    - The MPM solver starts in **`Rheo/Packages/RheoEngine`** and is promoted to a `LabKitMPM` product only when a second toy needs it. [I]

---

## 1. Powder: how a large C++ engine was vendored

**Scope caveat** [V]:

- Powder's active native app is **macOS-only**. It has one `PowderMac` target in `Native/project.yml:22–24`, and its `MetalSimulationView` is an `NSViewRepresentable` (`MetalSimulationView.swift:13`). `Native/README.md:17` says "The active project has no iOS target".
- The engine package still declares `.iOS(.v17)` (`Package.swift:5`).
- So Powder's lessons about SwiftPM layout, the C ABI, provenance and rendering transfer directly. Its iOS build behaviour does not: that was re-verified here with Box2D (§3.2).

### 1.1 SwiftPM layout

`Native/Packages/PowderEngine/Package.swift` [V]:

- **Tools version and platforms:** `// swift-tools-version: 6.0`, with `platforms: [.macOS(.v14), .iOS(.v17)]` (lines 1–5).
- **Three-layer target split:**
  - `JsonCpp`: a C++ dependency with its own `publicHeadersPath: "include"` and `exclude: ["LICENSE"]` (lines 9–11).
  - `CBridge`: the upstream engine plus a C ABI adapter (line 12).
  - `PowderEngine`: a pure Swift value wrapper (line 245).
- **Explicit `sources:` list.** About 230 files are listed one by one (lines 13–241). Upstream GUI, SDL, Lua and network sources stay in the vendored tree "to preserve provenance" but are not compiled.
  - Explicit lists are safe, but noisy for big trees.
  - For Box2D, every `.c` file under `src/` is part of upstream's `BOX2D_SOURCES`, so `sources: ["src"]` is exact. [V: the 35 `.c` files match upstream's CMake list]
- **Header search paths:** `publicHeadersPath: "include"` exports only `include/TPTBridge.h`. `cxxSettings: [.headerSearchPath("Upstream"), .headerSearchPath("Generated")]` keeps the internal upstream headers private (lines 242–243).
- **Platform library:** `linkerSettings: [.linkedLibrary("bz2")]` links the system bzip2 rather than vendoring it (line 244).
- **Language standard:** `cxxLanguageStandard: .cxx20` is set at package level (line 247).
- **Generated build resources:** CMake/meson outputs were replaced with checked-in generated files (`Sources/CBridge/Generated/Config.h`, element number headers and compressed font data).

  > **Pitfall:** SwiftPM defines `DEBUG`, which collided with upstream's `constexpr bool DEBUG`. `Config.h` lines 2–5 do `#ifdef DEBUG #undef DEBUG`. [V source]
  >
  > I confirmed SwiftPM passes `-DDEBUG=1` to C targets in Debug and nothing in Release (§3.3). Box2D 3.1.1 never uses the bare `DEBUG` identifier [V grep], so no workaround is needed for it.

### 1.2 C ABI bridge rather than Swift–C++ interop

`Sources/CBridge/include/TPTBridge.h` (177 lines) is the whole Swift-visible surface. [V]

**Handles and values**

- There is one opaque handle, `typedef struct TPTWorld TPTWorld;` (line 9). Swift sees it as `OpaquePointer`.
- Everything else is a POD struct of fixed-width integers and floats (`TPTParticle`, `TPTAirSample`, `TPTRenderCell`, `TPTRenderInfo`).
- `TPTRenderSnapshot.cpp:13–16` checks their layout with `static_assert(sizeof(TPTRenderCell) == 16)`, `offsetof`, `is_trivially_copyable`.
- XCTest checks the same layout from the Swift side: `MemoryLayout<TPTRenderCell>.stride == 16` in `EngineRenderSnapshotTests.swift:7–8`.

**Buffers and ownership**

- The caller owns output buffers, and passes a capacity. Passing `NULL` returns the required count; otherwise the call returns the number written (header comment at `TPTBridge.h:127–128`; for example `tpt_world_copy_particles` at `:79`).
- The render snapshot is copied "under a single engine lock", and undersized buffers "fail without writing" (`TPTBridge.h:114–118`). A test proves the sentinel bytes are untouched (`EngineRenderSnapshotTests.swift:9–17`).
- Metadata strings have process lifetime (`TPTBridge.h:120, 127`).
- OPS save buffers are `malloc`ed and freed with a matching `tpt_bytes_free` (`TPTBridge.h:169–172`).

**Errors and exceptions**

- Errors are carried by **thread-local** `lastError` (`TPTBridge.cpp:14`) and read with `tpt_last_error()` (`:110`).
- Every entry point is wrapped in `TPT_BEGIN`/`TPT_END(failure)` macros (`TPTBridge.cpp:108–109`). They take the lock, clear the error, `try` the body, and convert `std::exception` and `...` into an error code.
- **No C++ exception ever crosses into Swift.**

**Locking**

- One **process-wide `std::recursive_mutex`** (`tpt_engine_mutex()`, `TPTBridge.cpp:91`; declared with its rationale at `TPTInternal.hpp:15–16`) serialises every call, because upstream keeps global element tables. It is recursive because the save adapters re-enter public entry points. The overlay, save and render-snapshot adapters take the same lock (`TPTOverlays.cpp:40`, `TPTSave.cpp:118`, `TPTRenderSnapshot.cpp:34`).
- As a result, **two worlds can never step in parallel**. That is acceptable for Powder, but it is a design smell to avoid.

**Why this was the right call** (applies to LabKit):

- (a) Swift targets stay in plain C-import mode. With Swift's C++ interoperability mode, every dependent target must also enable `.interoperabilityMode(.Cxx)` [I: from Swift.org's C++ interop documentation, not tested here].
- (b) The threading contract is explicit: one lock, and errors are thread-local.
- (c) The same C ABI is reused by non-Swift harnesses. `scripts/check-legacy-fusion.cpp` links the built CBridge objects to run 256-seed regression checks (`docs/Upstream History.md:43`). [S]

**Box2D is already a C API,** so LabKit needs none of this. The lessons still carry over:

- Assert struct strides in tests.
- Keep the raw API out of app code.
- Know which state is global.

### 1.3 The Swift wrapper: value semantics with copy-on-write

`Sources/PowderEngine/EngineWorld.swift` [V]:

- `EngineError` builds its message from `tpt_last_error()` with a fallback string (lines 5–12).
- `public struct EngineWorld: Sendable` holds a `private final class Storage: @unchecked Sendable { let handle: OpaquePointer; deinit { tpt_world_destroy(handle) } }` (lines 16–21).
- Every mutating method calls `ensureUnique()`. If the storage is not uniquely referenced, that calls `tpt_world_clone` (lines 38–43).
- This is what makes **undo checkpoints and background scene trials free until written**. An undo stack is simply `[Checkpoint(world: EngineWorld)]`.
- Box2D 3.1.1 has **no world clone or snapshot API**, and its FAQ states it "does not have rollback determinism" (`docs/FAQ.md:111`) [V]. So for Rheo, reset and undo mean rebuilding the scene from a deterministic scene description, not cloning engine state (§4.9).

### 1.4 Provenance and licence conventions (copy these)

These files exist [V]:

**`Packages/PowderEngine/UPSTREAM.md`** contains, in order:

- what was built: release, commit, "headless C++20 library behind a C ABI";
- the upstream URL, licence (GPL-3.0) and copyright holder;
- a "Preserved behaviour" list;
- a "Native integration changes" list, one bullet per adapter file;
- every modified upstream file and why;
- what is in the tree but not compiled;
- "Build and checks", with the exact `swift test` command and the cache environment variables.

**`Packages/PowderEngine/UPSTREAM.json`** is machine-readable:

```json
{
  "upstream": "https://github.com/The-Powder-Toy/The-Powder-Toy",
  "tag": "v100.1.400",
  "commit": "d768aeb89acad986bd252d7e904bf44bb374545f",
  "archiveSHA256": "75cd971e…",
  "vendoredRoot": "Sources/CBridge/Upstream",
  "modifiedUpstreamFiles": ["client/GameSave.cpp", "…", "simulation/elements/O2.cpp"],
  "jsoncpp": { "version": "1.9.6", "archiveSHA256": "f93b6dd7…" },
  "tagObject": "c8be5165…"
}
```

Powder separates the *peeled commit* from the *annotated tag object*; `docs/Validation.md:7` calls this out explicitly. Box2D's `v3.1.1` is a **lightweight** tag [V: `git ls-remote` shows no `^{}` entry, and `git cat-file -t v3.1.1` returns `commit`], so `tagObject` is `null`.

**`Native/THIRD_PARTY_NOTICES.md`** has one `##` section per dependency, containing:

- the copyright line;
- repository, release, commit, tag object and archive SHA-256;
- links to the vendored tree, the licence file, the modifications and the JSON;
- the **full licence text in a fenced block**.

It ends with a "Platform libraries" section listing what is *not* vendored (system bzip2, no FFTW, no SDL).

**Per-dependency `NOTICE.md` for small vendored headers.** `Sources/CBridge/PocketFFT/NOTICE.md` records:

- the URL at the exact revision and the retrieval date;
- the licence and what must be retained;
- how the adapter uses the dependency ("internal pool is disabled …").

THIRD_PARTY_NOTICES also records the header's SHA-256 (`3e9a0531…`).

**File-level licence headers on adapters:** for example `// GPL-3.0-or-later. Native C boundary around The Powder Toy v100.1.400.` (`TPTBridge.cpp:1`). Box2D uses SPDX headers (`// SPDX-License-Identifier: MIT`), which LabKit should keep and imitate.

**Licences ship inside the app.** In `Native/project.yml:27–30`, `LICENSE` and `THIRD_PARTY_NOTICES.md` are `buildPhase: resources`. The house rules (Spectra `design-house-rules.md`) add that credits appear in the in-app About or methodology sheet.

**MIT obligation for Box2D:** "The above copyright notice and this permission notice shall be included in all copies or substantial portions". A compiled app counts, so the notice must be inside the `.app` and visible in the InfoSheet credits. [V licence text]

---

## 2. Nano: the small pure-Swift engine pattern

- **A host-testable core without xcodebuild.** `Nano/Package.swift` defines `NanoCore` with `path: "Core"` and tests with `path: "Tests"`, on `platforms: [.macOS(.v14)]` only. The iOS app compiles the same `Core/` files directly through XcodeGen (`project.yml:16–21`).
  - `swift test` runs Swift Testing suites (13 tests) on the Mac with no simulator. [V manifests; S test count, `design-qa.md`]
  - **Constraint:** the core imports only Foundation.
  - **Drawback:** the same files are compiled into two module names (`NanoCore` and `Nano`).

  Powder instead puts the core in a local package under `Packages/` that the app depends on. That is a single source of truth, so prefer Powder's layout for Rheo.
- **Deterministic fixed-step core:**
  - `TorusWorld.fixedDelta = 1/30` (`TorusWorld.swift:5`), a `Codable, Equatable, Sendable` value type.
  - "Rendering and wall-clock time never enter its rules" (line 3).
  - Seeded noise.
  - Tests assert that a clone evolves identically for 900 steps (`Tests/CoreTests.swift:31–40`).
- **Clock on the main actor:** `LabStore.runClock()` (`LabStore.swift:191–211`):
  - loops `Task.sleep(66 ms)`;
  - clamps elapsed time to 0.25 s;
  - accumulates `elapsed × speed`;
  - steps `Int(acc / fixedDelta)` times;
  - `ExperimentLab.advance` caps a batch at 3,600 steps (`ExperimentLab.swift:20`).
- **Visual interpolation is decoupled from the 30 Hz sim.** The SpriteKit `update(_:)` eases nodes toward their target positions with `blend = 1 − exp(−22·dt)` (`TorusScene.swift:455–466`). `preferredFramesPerSecond` is 30 when running and 15 when paused (`TorusViewport.swift:97`).
- **Measured pitfalls** [S]:
  - An unoptimised Debug build took **102 ms vs 4.5 ms** for a 24-step batch (22.7×) and blocked the main actor. The fix was `SWIFT_OPTIMIZATION_LEVEL: '-O'` on the app target (`project.yml:37`, `README.md:56`).
  - Swift Charts updating at the simulation rate pinned the CPU at about 99%. Throttling charts to about 2 Hz with at most 80 points brought it to about 41% (`design-qa.md` item 6).
- **Accessibility of a live canvas:** `TorusSKView` returns `accessibilityElementCount() == 0` so SpriteKit nodes do not flood VoiceOver. The representable supplies one label and value (`TorusViewport.swift:98–104, 140–147`).

---

## 3. Experiments run for this note

All experiments live in `scratchpad/oss-integration/` (Appendix A).

### 3.1 Box2D pin

| Item | Value | Status |
|---|---|---|
| Latest tag | `v3.1.1`, lightweight, commit `8c661469c9507d3ad6fbd2fea3f1aa71669c2fe3`, committed 2025-06-03 | [V] |
| Tree hash | `f411f5197e73db138a249525ad3f1315816a956b` | [V] |
| GitHub tarball | `https://github.com/erincatto/box2d/archive/refs/tags/v3.1.1.tar.gz`, SHA-256 `fb6ef914b50f4312d7d921a600eabc12318bb3c55a0b8c0b90608fa4488ef2e4`, 780,115 bytes | [V] |
| Licence | MIT, "Copyright (c) 2022 Erin Catto"; source files carry SPDX MIT headers | [V] |
| Vendored set | `include/box2d/*.h` (6), `src/*.c` (35) + `src/*.h` (22), `LICENSE`; 1.1 MB | [V] |
| Vendored manifest hash | `5f8e10b1017e90701e9cba7c639169cd4277844db244de0d4a89b0f15943d479`, computed as `find include/box2d src LICENSE -type f \| sort \| xargs shasum -a 256 \| shasum -a 256` | [V] |
| `main` | `956ce4e` (2026-09-24). CMake says **3.2.0, untagged**. It adds recording/replay, snapshots, a built-in scheduler and `include/box2d/config.h`, and **removes `b2CreateMouseJoint`** in favour of a mover joint. `b2CreateWorld` becomes a macro under double precision. | [V] |

**Decision:** pin v3.1.1, which is the only tagged v3 release with cross-platform determinism. The 3.2 snapshot/replay API is attractive for undo and a "replay last 5 s" feature, but it is untagged and breaks the joint API. The wrapper in §4 isolates the API surface so the upgrade is local.

### 3.2 Build results

| Check | Result | Status |
|---|---|---|
| `swift build` (host, Debug) of the whole probe | Complete in 6.7 s, **0 warnings** from Box2D under Swift Build's default C warning set | [V] |
| `swift test` (Debug, then Release with `-Xswiftc -enable-testing`) | 6 + 1 tests pass, Box2D reports `3.1.1` | [V] |
| Swift 6 language mode | `public struct RigidBody: Sendable { let raw: b2BodyId }` compiles. Imported C id structs are implicitly `Sendable`. | [V] |
| `internal import CBox2D` in the wrapper | Builds, and the iOS app compiles **without** seeing the C module | [V] |
| iOS Simulator Debug through XcodeGen + xcodebuild (local package `path: ../LabKitProbe`, `SWIFT_VERSION 6.0`, `SWIFT_STRICT_CONCURRENCY complete`) | **BUILD SUCCEEDED** in 16.5 s. `unsafeFlags` accepted for a local path package. | [V] |
| App launched on the iPhone 17 Pro simulator (iOS 27.0) | Box2D ball fell from 10 m to y = 5.0746 m after 1 s at 60 Hz. `Bundle.module` contains `default.metallib`, and `makeDefaultLibrary(bundle: .module)` took **1.18 ms**. Strides 48 and 16 match. The probe app was uninstalled afterwards. | [V] |
| Generic iOS device Release (`CODE_SIGNING_ALLOWED=NO`) | **BUILD SUCCEEDED**. CBox2D objects are 1.92 MB (36 `.o`). The **app binary is 254,072 bytes** after dead-stripping. | [V] |

### 3.3 Flags SwiftPM really passes to C targets

Read from Swift Build's `*-common-args.resp` [V]:

| Configuration | Flags |
|---|---|
| Debug | `-O0 -g '-DDEBUG=1' -DSWIFT_PACKAGE -DXcode` |
| Release | `-Os -g -DSWIFT_PACKAGE -DXcode` with **no `-DNDEBUG`** (confirmed with a probe C target returning its macro set) |

Box2D's `B2_ASSERT` is active whenever `NDEBUG` is undefined (`include/box2d/base.h:101–112`). Its internal `B2_VALIDATE` turns on only if you define `BOX2D_VALIDATE` (`src/core.h:21–25`). Upstream CMake adds `-ffp-contract=off` on Apple for determinism (`CMakeLists.txt:37–41`). The probe's `cSettings` add `-DNDEBUG` (Release) and `-ffp-contract=off`, and both appeared in the response file. [V]

### 3.4 Box2D speed

Scene: 500 awake balls with sleep disabled, 3 static walls, 4 substeps, 60 warm-up steps, 600 timed steps. Each configuration was run 7 times on a busy host; the table gives medians. [V]

| Build | ms per step (median, range) |
|---|---|
| Debug, C at `-O0` | **5.10** (3.74–8.42) |
| Debug, C at `-O2` (asserts still on) | **0.35** (0.28–1.12) |
| Release, C at `-Os` (SwiftPM default) | **0.75** (0.42–1.71) |
| Release, C at `-O2` | **0.48** (0.15–0.63) |

The wrapper's pose export (three C calls per body, 500 bodies) took 1.29 ms in Debug and **0.020 ms** in Release.

Revision 2 re-ran the Debug configuration on a fresh copy, single runs on a busy host [V]:

| Build | ms per step |
|---|---|
| Swift Debug, C at `-O0` | **3.43** |
| Swift Debug, C with `-O2` added unconditionally (tools-version 6.4 manifest from §4.2) | **0.16** |

That is about 21×. The response file shows `-O0 … '-DDEBUG=1' … '-ffp-contract=off' -O2`. Because `unsafeFlags` are appended after SwiftPM's own `-O0` and clang honours the last `-O`, the override works.

**Lesson:** this is the same trap Nano hit. Ship `-O2` for `CBox2D` in every configuration. The assertions are cheap; `-O0` is not. Rheo will have tens of props, not 500, so Box2D is noise in its frame budget once optimised.

### 3.5 Box2D global state and scale

**Global state** [V source]:

- `b2_worlds[B2_MAX_WORLDS]` is a static table (128 worlds; `src/world.c:35`, `src/constants.h:26–28`). `b2CreateWorld` scans it with **no lock** (`world.c:100–113`).
- `b2_lengthUnitsPerMeter` is a global (`src/core.c:33–38`), and so are the assert hook and allocator.
- A world is `locked` during `b2World_Step`, so callbacks must not mutate it (`world.c:701–729`).

**Flaky parallel tests** [V]: one suite toggled `b2SetLengthUnitsPerMeter` inside `@Suite(.serialized)` while another suite asserted bit-identical reruns.

- Parallel `swift test` **failed 3 of 5 runs**.
- `--no-parallel` passed 3 of 3.
- Skipping the toggling suite passed 5 of 5.
- `.serialized` serialises only *within* its own suite.

**Tolerances are physical** [V]. A 4 mm, 1000 kg/m² bead with restitution 0.8 was dropped from 3 cm, so it hits at 0.71 m/s:

| `b2SetLengthUnitsPerMeter` | Bounce apex | Bead sinking under heavy damping (~3 cm/s) |
|---|---|---|
| 1 (default; restitution threshold 1 m/s, sleep 5 cm/s) | **0 mm** (no bounce) | **Asleep after 61 steps (0.51 s), frozen at y = 0.484 m** |
| 0.1 (thresholds 0.1 m/s and 5 mm/s) | **16.5 mm** (theory: e²h = 16.6 mm) | Still awake and sinking |

Resting penetration was identical under both settings (0.069 mm). My hypothesis that v2-style slop would matter is refuted: v3's soft contacts do not depend on slop that way.

### 3.6 Metal in a SwiftPM target

- **xcodebuild handles it.** It compiles `Sources/<target>/Shaders/*.metal` with `resources: [.process("Shaders")]` into `<Package>_<Target>.bundle/default.metallib`; the probe's was 5,328 bytes. A relative cross-target include, `#include "../../LabShaderTypes/include/LabShaderTypes.h"`, compiled. [V]
- **The SwiftPM 6.4 CLI now also tries to compile `.metal` itself.** It has a `CompileMetalFile` step under `out/Intermediates.noindex`, which is the Swift Build engine. On this host it **fails**:
  - It invokes `XcodeDefault.xctoolchain/usr/bin/metal`, a shim that reports "missing Metal Toolchain".
  - The installed component is **27A5194o** but Xcode is **27A5194q** (`xcodebuild -showComponent metalToolchain`).
  - `xcrun metal` and `xcrun -sdk iphoneos metal` work, because they resolve the cryptex mount. **`xcrun -sdk macosx metal` fails.** [V]

  Powder hit a variant of this: "xcrun could not resolve the installed Metal compiler" (`docs/Rendering-v4.md:41`) [S].

  If the component ever goes missing, the user can run `xcodebuild -downloadComponent MetalToolchain`. I did **not** run that, because it changes the system.
- **The fix is `TOOLCHAINS=metal`** [V, revision 2]. `toolchain-checks.md` §3 found it, and I re-verified it on a fresh copy of the probe with no runtime-shader switch:
  - `TOOLCHAINS=metal swift test --no-parallel` exits 0.
  - The relative cross-target `#include` compiles.
  - `LabKitProbe_LabRender.bundle/Contents/Resources/default.metallib` is produced and embedded in the `.xctest`.
  - `makeDefaultLibrary(bundle: .module)` loads it, and all 7 tests pass. The clean run took 16.8 s.
  - The variable only redirects the `metal` tool to the Metal Toolchain cryptex. The Swift compiler stays 6.4 (`toolchain-checks.md` §9 item 1).
- **Superseded fallback** (keep it only for environments without the Metal Toolchain) [V]:
  - `Package.swift` reads `Context.environment["LABKIT_RUNTIME_SHADERS"]`. When it is set, it uses `.copy("Shaders")` instead of `.process`.
  - The library loader falls back to `makeLibrary(source:)` after inlining the shared header.
  - The host GPU test then passed in 0.19 s, including the runtime compile.
  - Do **not** put this in LabKit's manifest by default. It adds a second code path that production never exercises.
- **Shared Swift/MSL header** [V]: a header-only C target (`include/LabShaderTypes.h` plus an empty `.c`). It uses `#ifdef __METAL_VERSION__` to typedef `metal::float2` versus `simd_float2`. Swift imports it, and MSL includes it. Stride tests passed: `LabFrameUniforms` is 48 bytes and `LabRigidInstance` is 16.

  This removes Powder's hand-mirroring of struct layouts ("Packed 48-byte layout mirrored by RenderUniforms", `MetalParticlePipeline.swift:5`; `ParticleShaders.metal:4–16`).

### 3.7 GPU atomics for P2G (M1 Max, 1,048,576 adds)

[V]

| Contention | `atomic_float` add, GPU ms (6 runs) | Fixed-point `atomic_int` add (×4096), GPU ms | Float result repeatable? |
|---|---|---|---|
| 64 slots (extreme) | 48.5–58.4 | 0.18–1.13 (median about 0.19) | **No: 6 distinct sums in 6 runs** |
| 65,536 slots (about 16 adds per slot, MPM-like) | 0.35–1.23 (median about 0.77) | 0.18–0.30 (median about 0.22) | **No: 6 distinct** |

The fixed-point sums were bit-identical in every run. Both kernels compile for `air64-apple-ios27.0` from `-std=metal3.0` through `metal4.0`. A17 Pro behaviour was **not measured**. M1 is GPU family Apple7 and A17 Pro is Apple9, which may have faster float atomics [I]. Determinism still argues for fixed point.

**Re-run in revision 2** (65,536 slots, 6 runs each) [V]:

| Kernel | GPU ms |
|---|---|
| Float | 0.32–1.10 (median about 0.37), **4 distinct sums** |
| Fixed | 0.18–0.38 (median about 0.25), bit-identical |

The ratio is therefore noisy, at 1.5–3.5×. The hashed scatter has no spatial locality, so it measures contention, not a real P2G. For a real kernel use the survey's numbers (`oss-engine-survey.md` §4): `atomic_float` is 1.3–1.5× slower than int32 across 16k–261k particles.

**Fixed-point units: lessons from the survey** [S]. The scale must be chosen per quantity:

- `2^20 / particleMass` worked.
- A per-grid scale silently truncated `m·g·dt` to zero.
- A long splash run at 65k overflowed int32.

Keep grid quantities in cell units with particle mass ≈ 1, as PB-MPM does, and add an overflow check to physcheck.

### 3.8 Encode cost versus GPU cost for an MPM-shaped frame

Kernels were skeletal: clear grid, P2G (3×3 stencil, 3 int atomics per node), grid update, G2P. Each frame used one compute encoder; 64 measured frames after 16 warm-ups. [V]

| Particles | Grid | Substeps | Dispatches | CPU encode + commit (median / p95) | GPU (median / p95) |
|---|---|---|---|---|---|
| 32,768 | 128×256 | 16 | 64 | **0.050** / 0.52 ms | 2.61 / 3.31 ms |
| 65,536 | 128×256 | 32 | 128 | **0.061** / 0.82 ms | 7.44 / 10.82 ms |
| 131,072 | 192×384 | 48 | 192 | **0.073** / 0.72 ms | 24.93 / 27.65 ms |

That is about **3.6–5 ns per particle-substep on a 32-core M1 Max GPU**, for kernels much simpler than real MLS-MPM. The A17 Pro has a 6-core GPU, so scale by roughly 4–6× and then by 2–4× for real constitutive work [I]. CPU encoding is never the bottleneck: even 192 dispatches cost less than 0.1 ms median.

**Align the particle budget with the survey** (`oss-engine-survey.md` §7.3–7.5) [S]:

- Explicit MLS-MPM at real viscosities is far over budget. Honey at 0.8 mm cells needs about 365 substeps per 1/120 s frame.
- Rheo therefore uses PB-MPM-style relaxation with implicit grid viscosity: 2 substeps × 3–5 iterations at 120 Hz, about 16k particles by default, and about 36k in the 60 Hz quality mode.
- That is about 6–40 dispatches per frame, which is well inside the encode numbers above.
- Device measurement remains the Phase 0 gate.

### 3.9 Swift 6 render-thread skeleton

`scratchpad/oss-integration/RenderHostSkeleton.swift` passes `xcrun -sdk iphoneos swiftc -typecheck -swift-version 6 -strict-concurrency=complete -target arm64-apple-ios27.0`. [V; type-check only, not run]

It contains:

- `SimMailbox: Sendable`, built on `Synchronization.Mutex` (in the iOS 27 SDK);
- a non-`Sendable` `SimEngine`;
- a `RenderThread: NSObject, CAMetalDisplayLinkDelegate, @unchecked Sendable` running `CAMetalDisplayLink` (iOS 17+) on its own `Thread` and run loop.

SDK facts [V]:

- `MTKView` and `MTKViewDelegate.drawInMTKView:` are `NS_SWIFT_UI_ACTOR`, so main-actor.
- `CAMetalDisplayLinkDelegate` has no actor annotation.
- `MTLCommandBufferHandler` is `NS_SWIFT_SENDABLE`.

### 3.10 Per-dispatch GPU overhead and high substep counts (revision 2)

**Why this was measured.** The sibling notes disagree on substep counts:

- `rheology-models.md` §1 item 6 estimates about **170 substeps per 60 Hz frame** for explicit MPM with softened K and G.
- `oss-engine-survey.md` §7.4 plans **2–8** PB-MPM substeps.

I extended the §3.8 benchmark (`encode-bench2/3/4.swift`) to settle what the threading design must absorb. Results are medians of 64 frames on the M1 Max [V]:

| Case | Dispatches per frame | CPU encode + commit | GPU |
|---|---|---|---|
| 16k particles, 64×140 grid, 2 substeps | 8 | 0.035 ms | 0.17 ms |
| 16k particles, 8 substeps | 32 | 0.066 ms | 0.74 ms |
| 16k particles, 85 substeps | 340 | 0.13 ms | 28.3 ms (pile-up, see below) |
| 16k particles, 170 substeps | 680 | 0.27 ms | 50.1 ms (pile-up) |
| **256 particles, 32×32 grid** (isolates fixed cost), 170 substeps, serial encoder | 680 | 0.25 ms | **5.3–6.8 ms** (≈ 8–10 µs per dispatch) |
| Same, `dispatchType: .concurrent` + `memoryBarrier(scope: .buffers)` after each dispatch | 680 | 0.53 ms | **3.0 ms** (≈ 4.4 µs per dispatch) |
| Same, concurrent + barriers, 340 substeps | 1,360 | 1.05 ms | 6.8 ms |

What these show:

1. **CPU encoding stays cheap even at 680 dispatches** (0.25–0.5 ms). The render-loop-owns-time design survives either solver choice.
2. **Fixed GPU cost per dependent dispatch is about 4–10 µs on the M1 Max.** At 170 substeps × 4 kernels, that is 3–7 ms of pure overhead per frame before any physics. It is unmeasured on A17 Pro, and is likely no better there [I].
   - Rule: keep dependent dispatches per frame **at or below about 100 at 120 Hz**.
   - Use a concurrent compute encoder with explicit `memoryBarrier(scope: .buffers)`.
   - Fuse kernels: PB-MPM's `g2p2g` is one dispatch per iteration.
   - An explicit high-substep solver must fuse each substep into 1–2 dispatches, or run several substeps inside one kernel over threadgroup-resident tiles.
3. **The skeleton's GPU time grows superlinearly with substeps** (0.74 ms at 8, 28 ms at 85). It moves particles without boundary projection, so they pile into the bottom cells and the P2G atomics serialise. This reproduces the survey's contention finding (`oss-engine-survey.md` §4, lesson 3: 0.29 → 4.6 ms). These rows are a contention warning, not a throughput estimate.

---

## 4. Recommendation: Box2D in LabKit

### 4.1 Layout

```
LabKit/
  Package.swift
  THIRD_PARTY_NOTICES.md               ← one section per dependency, full licence text
  Sources/
    CBox2D/                            ← C target; upstream is byte-for-byte unmodified
      LICENSE                          (upstream)
      UPSTREAM.md  UPSTREAM.json       (ours)
      include/
        module.modulemap               (ours: the only addition inside include/)
        box2d/{base,box2d,collision,id,math_functions,types}.h   (upstream)
      src/*.c, src/*.h                 (upstream; *.natvis and CMakeLists.txt not copied)
    LabKitRigid/                       ← Swift wrapper: `internal import CBox2D`
      RigidUnits.swift  RigidWorld.swift  RigidTypes.swift  RigidCoupling.swift
    LabKitShaderTypes/                 ← header-only C target shared with MSL
      include/LabKitShaderTypes.h      empty.c
    LabKitRender/                      ← Metal host, bloom/EDR chain; Shaders/*.metal as resources
  Tests/
    LabKitRigidTests/                  ← one `.serialized` suite; CI runs `swift test --no-parallel`
  Tools/
    vendor-box2d.sh                    ← re-vendors a tag and rewrites UPSTREAM.json hashes
```

**Naming.** `CBox2D` follows Powder's `CBridge`. The C module is never a product. If the LabKit architecture note chooses other Swift module names (for example `LabKitPhysics`), keep `CBox2D` and rename only the wrapper.

### 4.2 Manifest excerpt

This merges labkit-from-gyre's verified manifest (`labkit-from-gyre.md` §2) with the Box2D targets.

What was verified [V, revision 2]: the probe ran with `swift-tools-version: 6.4`, `.iOS(.v27), .macOS(.v27)`, `swiftLanguageModes: [.v6]`, the `CBox2D` settings below and `.process("Shaders")`. `TOOLCHAINS=metal swift test` passed 7 of 7 tests. The probe used different wrapper and shader-type target names.

```swift
// swift-tools-version: 6.4
// .iOS(.v27) / .macOS(.v27) need tools-version 6.4. macOS is for host tests and harnesses only.
// Host tests: `TOOLCHAINS=metal swift test --no-parallel` (the SwiftPM CLI needs it to find the Metal compiler).
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
        .library(name: "LabKitRigid", targets: ["LabKitRigid"]),          // Box2D behind a Swift API
        .executable(name: "labkit-physcheck", targets: ["LabKitPhyscheck"]),
    ],
    targets: [
        // … LabKitCore / Sensors / Feedback / UI / Physcheck exactly as in labkit-from-gyre.md §2 …
        .target(name: "LabKitShaderTypes"),                               // C: include/LabKitShaderTypes.h + shim.c
        .target(name: "LabKitRender", dependencies: ["LabKitCore", "LabKitShaderTypes"],
                resources: [.process("Shaders")]),                         // explicit; Xcode also infers it
        // Box2D v3.1.1, unmodified upstream C17. Only box2d/box2d.h is exported (include/module.modulemap).
        .target(
            name: "CBox2D",
            exclude: ["LICENSE", "UPSTREAM.md", "UPSTREAM.json"],
            sources: ["src"],
            publicHeadersPath: "include",
            cSettings: [
                .define("NDEBUG", .when(configuration: .release)),   // SwiftPM never defines it
                .unsafeFlags(["-ffp-contract=off", "-O2"]),          // upstream CMake parity + no -O0 trap
            ]
        ),
        .target(name: "LabKitRigid", dependencies: ["CBox2D", "LabKitShaderTypes"]),
        .testTarget(name: "LabKitRigidTests", dependencies: ["LabKitRigid", "CBox2D"]),
        // … LabKitCoreTests, LabKitRenderTests …
    ],
    swiftLanguageModes: [.v6],
    cLanguageStandard: .c17
)
```

Notes on this manifest:

- `toolchain-checks.md` §10 adds `cSettings: [.headerSearchPath("src")]`. It is **not needed**. Box2D's `src/*.c` include their siblings with quoted includes, which resolve relative to the including file, and the probe builds without it [V].
- `LabKitRigid` depends on `LabKitShaderTypes` only so that `writeInstances` can fill the GPU struct directly.
- `unsafeFlags` is fine because apps reference LabKit by local `path:` (XcodeGen `packages: LabKit: path: ../LabKit`).
- If LabKit is ever consumed as a **remote URL** package, SwiftPM rejects `unsafeFlags`. In that case drop `-O2`, ship Release builds to the device, and keep `-ffp-contract=off` only if cross-device replay matters [I].

`include/module.modulemap`:

```
// LabKit addition (not upstream): exposes only Box2D's public API to Swift.
module CBox2D {
    header "box2d/box2d.h"
    export *
}
```

This avoids SwiftPM's umbrella-guessing. Do not rely on it: on case-insensitive APFS, `include/Box2D/Box2D.h` "exists" for a target named `Box2D`.

### 4.3 `UPSTREAM.json` for CBox2D

These are the verified values.

```json
{
  "name": "Box2D",
  "upstream": "https://github.com/erincatto/box2d",
  "tag": "v3.1.1",
  "commit": "8c661469c9507d3ad6fbd2fea3f1aa71669c2fe3",
  "tagObject": null,
  "tree": "f411f5197e73db138a249525ad3f1315816a956b",
  "archiveURL": "https://github.com/erincatto/box2d/archive/refs/tags/v3.1.1.tar.gz",
  "archiveSHA256": "fb6ef914b50f4312d7d921a600eabc12318bb3c55a0b8c0b90608fa4488ef2e4",
  "license": "MIT",
  "copyright": "Copyright (c) 2022 Erin Catto",
  "vendoredRoot": "Sources/CBox2D",
  "vendoredPaths": ["LICENSE", "include/box2d", "src/*.c", "src/*.h"],
  "vendoredManifestSHA256": "5f8e10b1017e90701e9cba7c639169cd4277844db244de0d4a89b0f15943d479",
  "addedFiles": ["include/module.modulemap", "UPSTREAM.md", "UPSTREAM.json"],
  "modifiedUpstreamFiles": [],
  "notVendored": ["samples", "test", "benchmark", "shared", "extern", "docs", "src/box2d.natvis", "src/CMakeLists.txt", "CMakeLists.txt"],
  "buildSettings": {
    "cLanguageStandard": "c17",
    "defines": {"NDEBUG": "release only"},
    "flags": ["-ffp-contract=off", "-O2"],
    "simd": "NEON (automatic from __aarch64__)",
    "notDefined": ["BOX2D_VALIDATE", "BOX2D_DISABLE_SIMD", "BOX2D_AVX2", "B2_ENABLE_ASSERT"]
  },
  "retrieved": "2026-10-03"
}
```

**`UPSTREAM.md`** should mirror Powder's sections:

- what was built;
- "Preserved behaviour (all upstream; no modifications)";
- "LabKit additions" (the modulemap only);
- "Global state and threading", which lists the facts from §3.5;
- "Tolerances and units", which states that LabKit calls `b2SetLengthUnitsPerMeter(0.1)`;
- "Build and checks": `swift test --package-path LabKit --no-parallel`, plus the cache variables when sandboxed (§6, item 6).

**THIRD_PARTY_NOTICES.md entry:**

````markdown
## Box2D 3.1.1

Copyright (c) 2022 Erin Catto. MIT License. Unmodified upstream C sources are compiled into
LabKit's `CBox2D` target; LabKit adds only a Clang module map.

- Repository: https://github.com/erincatto/box2d
- Release: `v3.1.1` (lightweight tag) · commit `8c661469c9507d3ad6fbd2fea3f1aa71669c2fe3`
- Source archive SHA-256: `fb6ef914b50f4312d7d921a600eabc12318bb3c55a0b8c0b90608fa4488ef2e4`
- Source and notices: [vendored tree](Sources/CBox2D/), [LICENSE](Sources/CBox2D/LICENSE),
  [provenance](Sources/CBox2D/UPSTREAM.md), [machine-readable](Sources/CBox2D/UPSTREAM.json)

```text
<full MIT text from Sources/CBox2D/LICENSE>
```
````

**Apps:** add `../LabKit/THIRD_PARTY_NOTICES.md` as a `buildPhase: resources` source in `project.yml` (Powder `project.yml:27–30`). Render a "Credits & licences" row in the InfoSheet that lists Box2D with its licence text.

### 4.4 Swift wrapper shape (`LabKitRigid`)

Units are SI throughout: metres, kilograms, seconds, radians. Densities are areal (kg/m²), because both Box2D and a 2D thin-tank MPM are "per unit depth". For a thin tank of depth d, areal density is ρ·d.

```swift
internal import CBox2D
import simd

public enum RigidUnits {
    /// Call once per process before the first RigidWorld. Box2D tolerances are physical (tuned for
    /// 0.1–10 m bodies); 0.1 declares a 10 cm "metre" so 2–30 mm props bounce, contact and sleep sanely.
    /// Global and not thread safe: never change after start-up (see §3.5).
    public static func configure(lengthUnitsPerMetre: Float = 0.1)
    /// Routes B2_ASSERT (active in Debug) through os_log before trapping.
    public static func installAssertHandler()
}

public struct RigidBody: Hashable, Sendable { let raw: b2BodyId }     // a handle, not a reference
public enum RigidMotion: Sendable { case fixed, kinematic, dynamic }
public enum RigidShape: Sendable, Equatable {
    case circle(radius: Float)
    case box(halfExtents: SIMD2<Float>, cornerRadius: Float = 0)
    case capsule(a: SIMD2<Float>, b: SIMD2<Float>, radius: Float)
    case polygon([SIMD2<Float>], cornerRadius: Float = 0)              // ≤ 8 vertices (B2_MAX_POLYGON_VERTICES)
}
public struct RigidBodySpec: Sendable {
    public var motion: RigidMotion = .dynamic
    public var shape: RigidShape
    public var position: SIMD2<Float>
    public var angle: Float = 0
    public var arealDensity: Float = 1_000 * 0.01      // kg/m², e.g. ρ = 1000 kg/m³ × 1 cm deep
    public var friction: Float = 0.6
    public var restitution: Float = 0.2
    public var linearDamping: Float = 0
    public var angularDamping: Float = 0.05
    public var canSleep = false                        // fluid-coupled props must stay awake (§3.5)
    public var reportsHits = true                      // enableHitEvents → haptics and sound
    public var tag: UInt32 = 0                         // prop kind for the renderer
}
public struct RigidPose: Sendable, Equatable {
    public var body: RigidBody, tag: UInt32
    public var position: SIMD2<Float>, angle: Float
    public var linearVelocity: SIMD2<Float>, angularVelocity: Float
}
public struct RigidImpulse: Sendable { public var body: RigidBody; public var linear: SIMD2<Float>; public var angular: Float }
public struct RigidHit: Sendable { public var point: SIMD2<Float>; public var approachSpeed: Float; public var tags: (UInt32, UInt32) }

/// One Box2D world. Not Sendable: create, step and destroy it in the single isolation domain that
/// owns the simulation (the main actor in phase 1, the render thread in phase 2).
public final class RigidWorld {
    public init(gravity: SIMD2<Float>, substeps: Int = 4)           // b2DefaultWorldDef(); workerCount 1
    deinit                                                          // b2DestroyWorld
    public var gravity: SIMD2<Float> { get set }                    // tilt, presets (Moon/Mars/Jupiter), shake
    @discardableResult public func add(_ spec: RigidBodySpec) -> RigidBody
    public func remove(_ body: RigidBody)
    public func step(_ dt: Float)                                   // once per display frame, dt = sim time advanced
    public func apply(_ impulses: UnsafeBufferPointer<RigidImpulse>) // fluid → body, from the GPU readback
    public func moveKinematic(_ body: RigidBody, to position: SIMD2<Float>, angle: Float, over dt: Float) // finger paddle
    public func explode(at point: SIMD2<Float>, radius: Float, falloff: Float, impulsePerLength: Float)  // punch
    public func body(at point: SIMD2<Float>) -> RigidBody?          // b2World_OverlapAABB + b2Shape_TestPoint
    public func beginDrag(_ body: RigidBody, at point: SIMD2<Float>, maxForce: Float)  // 3.1.1 mouse joint; 3.2 → mover
    public func updateDrag(to point: SIMD2<Float>)
    public func endDrag()
    public func writePoses(into out: UnsafeMutableBufferPointer<RigidPose>) -> Int
    public func writeInstances(into out: UnsafeMutableBufferPointer<LabRigidInstance>) -> Int // GPU layout (shared header)
    public func drainHits() -> [RigidHit]                           // b2World_GetContactEvents().hitEvents
}
```

Rules for the wrapper:

1. **Always start from `b2Default*Def()`.** Box2D checks a secret cookie (`B2_CHECK_DEF`), so a zero-initialised Swift struct traps in Debug. [V source]
2. **No C types in the public API.** Use `internal import` (verified). `@testable import` still gives tests the raw ids.
3. **`workerCount = 1` and no task callbacks.** A handful of props is microseconds of work. A multi-threaded Box2D would only add a second scheduler next to the GPU.
4. **Never call into the world from inside a callback during `b2World_Step`** (the world is locked). Collect events after the step instead.
5. **Hide every API that 3.2 changes behind wrapper functions.** That means the drag joint, `b2World_OverlapAABB`'s signature, and the world definition fields. Upgrading is then a single-file change, re-verified by the LabKit tests.

### 4.5 Box2D tests (LabKit `physcheck` tier)

All of these go in one `@Suite(.serialized)`, and CI runs `--no-parallel`.

| Test | Pass condition |
|---|---|
| Free fall | 1 s at 120 Hz from rest: error under 0.05 m. Observed 0.0102 m; semi-implicit Euler bias is about g·dt·t/2 = 0.041 m. [V] |
| Settle and determinism | Two identical runs of 20 beads for 600 steps are bitwise equal, and all beads end at rest. [V] |
| Small-prop tolerances | With `RigidUnits.configure(0.1)`, a 4 mm bead with e = 0.8 bounces to at least 12 mm, and a slowly sinking bead never sleeps. [V] |
| ABI | `MemoryLayout<LabRigidInstance>.stride == 16`; `b2GetVersion() == 3.1.1`. [V] |
| Coupling round trip | Apply a known impulse J to a 10 g bead. Δv must equal J/m within 1e-5. [I] |
| Benchmark (informational) | 500 awake balls: Release under 1 ms/step on the host. Record it; it is not a gate. [V numbers above] |

---

## 5. Recommendation: Rheo engine and renderer threading

### 5.1 Why not Powder's model

Powder's model works like this [V source]:

- The engine runs on the CPU at 30 Hz inside `actor SimulationWorker`.
- Commands are batched in a main-actor `pending` array (`PlaygroundSession.swift:58, 147–159`).
- `process(commands, advance:)` returns one immutable `SimulationUpdate` with at most one compact `MetalFrame` (`SimulationWorker.swift:71–192`).
- That frame goes to a non-observed `MetalFrameSource` mailbox, and the `MTKView` is woken with `needsDisplay` (`MetalFrame.swift:88–107`, `MetalSimulationView.swift:72–77`).
- Stats are published at most every 200 ms (`PlaygroundSession.swift:131`).
- The tick loop sleeps for the remainder of 33 ms (30 Hz). When paused with nothing pending, the session waits on a wake `AsyncStream` with `.bufferingNewest(1)` instead of polling (stream at `PlaygroundSession.swift:62, 87`; loop at `:108–119`).
- The worker asserts that it is off the main thread on entry: `assert(!Thread.isMainThread, …)` at `SimulationWorker.swift:73`.
- The engine value never crosses back to the UI. Only the `Sendable` `SimulationUpdate` does (`SimulationWorker.swift:6, 15–33`).
- The view is **draw-on-demand**: `isPaused = true` and `enableSetNeedsDisplay = true` (`MetalSimulationView.swift:58`). New frames and completed GPU work wake it, so an idle canvas costs nothing. Rheo's view runs continuously, but it should drop to on-demand when the user pauses and when the scene has settled (kinetic energy below a threshold for 1 s) [I].
- The completion handler signals the semaphore *before* it hops to the main actor for metrics (`MetalSimulationView.swift:111–120`). Keep that order, so backpressure never waits on the main actor.

This is right for a CPU engine. For a **GPU-resident MPM** it would force a GPU→CPU→GPU round trip of the whole particle state every frame.

Keep these ideas from Powder:

- an ordered command mailbox, with gestures applied in order once per frame;
- SwiftUI never observes per-frame state;
- OSSignposter intervals around step, encode and autosave;
- memory-pressure trimming;
- debounced autosave, which in Rheo saves the *scene description*, not GPU buffers.

### 5.2 Phase 1: render loop owns time on the main actor (Gyre parity)

Gyre already runs this pattern at 120 Hz: `HoloRenderer.draw(in:)` computes `dt = min(now − last, 1/15)` and calls `model.advance(dt:)` (`HoloRenderer.swift:261–272`). Measured encode cost (§3.8) makes it viable for MPM. Per frame:

1. **Controls.** Read the `@ObservationIgnored` engine state and drain the ordered input queue (pokes, stir path, shake, preset changes).
2. **Quantum accumulator.** Simulated time advances in fixed quanta, not in Gyre's raw `dt`. This keeps Box2D on a constant step and keeps replays deterministic. Both Nano (`LabStore.swift:191–211`) and the survey (§7.4: Box2D at 1/120 s with 4 substeps) rely on fixed steps. [I]

   ```swift
   // P: nominal display period (1/120, or 1/60 in quality mode). s: Time Scale knob (0.1…2).
   let q = max(1, Int(s.rounded(.up)))           // quanta per nominal frame; >1 only when s > 1
   let h = P * s / Double(q)                     // quantum length (s): ≤ P, constant while the knob is still
   acc += min(frameDt, 1.0 / 15) / P * Double(q) // measured frame time, expressed in quanta
   var k = Int(acc); acc -= Double(k)
   if k > maxQuantaPerFrame { k = maxQuantaPerFrame; acc = 0; telemetry.lagging = true } // drop the debt
   ```

   - Slow motion **shrinks the quantum** (smooth) instead of skipping frames (stutter).
   - When the cap bites, the debt is dropped, so the sim slows down rather than spiralling.
   - Start with `maxQuantaPerFrame = 2`.
   - Inside each quantum, the MPM substep count comes from the survey's rule, evaluated with `h`: `n = clamp(ceil(max(h·v_max/(C·Δx), 8·f_drive·h)), 2, 8)`.
     - `v_max` is the previous frame's GPU-reported maximum speed, one frame late.
     - `f_drive` is the mic or vibration frequency.
     - Viscosity does not enter `n`, because `rheology-models.md` §1 item 2 shows the backward-Euler return map is stable at any viscosity.
     - An **explicit-elastic** solver (`rheology-models.md` §6, softened K and G with c_p ≈ 5 m/s) must add the elastic-wave term `h·c_p/(C·Δx)` to the `max` and lift the cap from 8. That is about 85 substeps per 1/120 s quantum. §3.10 shows what that does to dispatch overhead.
3. **Non-blocking backpressure.**
   - Use `inFlight.wait(timeout: .now())`, as Powder does (`MetalSimulationView.swift:92–94`). If no slot is free, skip *this* frame's encode; the accumulator keeps the time.
   - **Do not copy Gyre's blocking `inflight.wait()`** (`HoloRenderer.swift:295`). With a GPU-bound sim it stalls SwiftUI on the main thread.
   - Acquire `currentDrawable` **after** the slot is available. Gyre takes it before waiting (`:277` versus `:295`) [I: Apple guidance is to hold drawables briefly].
4. **Rigid step**, once per quantum.
   - At the first quantum, apply the fluid impulses from the most recently **completed** slot with `b2Body_ApplyLinearImpulse` and `b2Body_ApplyAngularImpulse`. The completion handler records the slot index in a `Synchronization.Atomic<Int>`, so no `Task { @MainActor }` hop is needed.
   - Call `rigid.step(h)` with 4 Box2D substeps.
   - Write body poses and velocities into this slot's collider buffer (`LabRigidInstance` or the survey's `MPMCollider`).
5. **Encode** the quantum's `n` MPM substeps into the frame's compute encoder.
   - Rigid bodies act as kinematic colliders on the grid: no-penetration plus Coulomb friction against the body velocity.
   - The grid stage accumulates each body's momentum change into a **fixed-point** per-body impulse buffer (x, y, angular).
   - Repeat steps 4 and 5 for each of the `k` quanta. There is still one command buffer per display frame.
6. **Encode the render passes** (§5.5), then `present` and `commit`. The completion handler signals the semaphore and stores the GPU time and slot index.
7. **Telemetry at 10 Hz** into an observed `Telemetry: Equatable` struct (Gyre's discipline). Charts are throttled to 2 Hz or less (Nano's lesson).

Use **2 frames in flight**, not 3, for touch latency [I]. At 120 Hz each frame in flight adds 8.3 ms between a poke and its visible response, which matters more in a toy you punch than in Gyre.

Start at 120 Hz, using the survey's 16k-particle default. Fall back to `preferredFramesPerSecond = 60`, with P = 1/60, in Low Power Mode, at thermal state `.serious` or above, or in the "quality" mode. Raise particle counts only after device measurements.

The **rigid coupling is explicitly lagged by one frame** [I]. A light bead in a dense fluid can gain energy (added-mass instability). Mitigate by:

- clamping |Δv| per quantum to about `2·g·h + 0.5·|v_rel|`;
- adding a little linear damping to coupled bodies;
- treating very light props as MPM rigid particle clusters instead of Box2D bodies, if tests show instability.

### 5.3 Phase 2 (only if Instruments shows main-thread hitches)

Move the same `SimEngine` onto a `CAMetalDisplayLink` thread. This is the skeleton from §3.9, which type-checks under Swift 6 strict concurrency:

- `SimMailbox: Sendable`, with `Mutex<SimControls>`, a `Mutex<[SimInput]>` queue and `Mutex<SimTelemetry>`;
- the engine and the `RigidWorld` are created *on* that thread;
- `RenderThread` is `@unchecked Sendable`, with a comment stating its confinement rule;
- `link.preferredFrameLatency = 2`.

The engine API should be identical in both phases. Only the `FrameDriver` that calls `engine.frame(…)` changes. LabKit's render host should offer both drivers.

### 5.4 Module layout for Rheo

```
Rheo/
  project.yml                         packages: { LabKit: { path: ../LabKit }, RheoEngine: { path: Packages/RheoEngine } }
  Packages/RheoEngine/
    Package.swift
    Sources/RheoShaderTypes/include/RheoShaderTypes.h   ← particle, grid-node, material, body and uniform structs (C, shared with MSL)
    Sources/RheoCore/                 ← pure Swift CPU reference: constitutive models, MLS-MPM step, scenes. Foundation + simd only.
    Sources/RheoGPU/                  ← Swift encoders + Shaders/*.metal (#include "../../RheoShaderTypes/include/RheoShaderTypes.h")
    Tests/RheoCoreTests/              ← rheology and MPM physics checks (host `swift test`)
    Tests/RheoGPUTests/               ← GPU vs CPU reference on the Mac GPU (`TOOLCHAINS=metal swift test`)
  App/ …                              ← SwiftUI chrome from LabKit, RheoModel (@MainActor @Observable; per-frame state @ObservationIgnored)
  Tools/build.sh  Tools/physcheck.sh
  Documentation/research/…
```

This follows Powder's "core in a local package" approach rather than Nano's dual-compiled `Core/`. It gives one module name and one source of truth. It is still testable on the host without xcodebuild.

**Placement of the MPM solver.** `oss-engine-survey.md` §7.1 instead puts it in LabKit (`LabMPM`, `LabMPMReference`, `CLabShaderTypes`). I recommend starting in `Rheo/Packages/RheoEngine` [I]:

- (a) The solver, its shaders and its constitutive models will change daily while Rheo is being built. LabKit's API should stay stable for Gyre-style consumers.
- (b) LabKit's host test loop stays fast, about 5 s for a no-op `swift test`.
- (c) The promotion is mechanical. The module layout above already mirrors a LabKit product: a C shared-types target, a pure Swift reference, and a GPU target with package shaders. When a second toy needs the solver, move `Packages/RheoEngine/Sources/*` to `LabKit/Sources/LabKitMPM*` and rename the modules.

The threading and encoding design in §5.2–5.3 is the same in either place.

### 5.5 Rendering Rheo, with techniques from Powder and Gyre

**Powder techniques worth reusing** [V source; GPU numbers S]:

| Technique | Where | Rheo use |
|---|---|---|
| Compact GPU struct with stride tests | `TPTRenderCell` 16 B; `MetalPackedCell` | Particle struct and grid node in `RheoShaderTypes.h`, with stride tests |
| Material table uploaded once per identity | `materialBuffer(for:)` (`MetalParticlePipeline.swift:159–169`) | Per-fluid optics: base colour, roughness, transmission, absorption, subsurface tint |
| Compute pre-pass into `rgba16Float` private textures at **sim-grid resolution**, then a full-screen-triangle composite at **drawable resolution** | `shadeParticles` (`ParticleShaders.metal:102–132`); `particleFullscreenVertex` (`:175–181`) | Splat grid mass and particles to a thickness field at 1–2× grid resolution, composite at drawable resolution |
| Height-field normals from bilinear `heightAt` differences | `ParticleShaders.metal:207–211, 281–282` | Normals from the thickness field (Hele-Shaw meniscus look) |
| GGX + Schlick Fresnel + procedural studio environment (no cubemap) | `pbrLighting` (`:224–245`), `environmentLight` (`:190–200`) | Wet-surface specular. Ketchup and honey gloss through roughness. |
| Screen-space transmission: offset UV by N.xy, Beer–Lambert `exp(−(1−albedo)·k·thickness)` | `:396–414` | Honey and slime translucency, cornstarch opacity |
| Contact-shadow march over the height field (3 or 5 taps) | `contactVisibility` (`:212–223`) | Depth cue where fluid piles up |
| Bloom at a grid fraction: divisor 4/2/1, separable Gaussian radius 3/6/12, sigma 1.15/2.1/4.2 | `MetalFrame.swift:114–123`; `gaussianBloom` (`:153–168`) | Magnetorheological spikes glow and specular sparkle |
| Filmic tonemap `x(2.51x+0.03)/(x(2.43x+0.59)+0.14)` | `:183–186` | Only if not outputting EDR. Gyre's EDR path supersedes it. |
| Animation driven by sim time only, so a paused frame stays still | `u.time = tick/30` (`MetalParticlePipeline.swift:128`), tested in Rendering-v4 | Ripple and noise must use simulated time, so "Pause" really freezes. Gyre does the opposite: shader `time = now − startTime`, wall clock (`HoloRenderer.swift:280`). Keep wall-clock time only for chrome effects such as the holographic shimmer, and use sim time for anything drawn from fluid state. |
| Triple-buffer slots + non-blocking semaphore + coalesced redraw + GPU timing from `gpuEndTime − gpuStartTime` | `MetalSimulationView.swift:30–129` | Same, with 2 slots (§5.2) |

**Gyre layers to add** (from `design-gyre.md` §9) [S]:

- `.rgba16Float` drawable with `wantsExtendedDynamicRangeContent` and `extendedLinearDisplayP3`;
- 120 Hz with `CADisableMinimumFrameDurationOnPhone`;
- bloom prefilter `smoothstep(0.35, 1.3, maxRGB)`;
- 5-tap linear-sampled Gaussian at ½ and ¼ resolution;
- chromatic aberration in the composite;
- the layout-driven camera (`onGeometryChange` → bubble region).

**Measured costs** [S]:

- Powder balanced quality, dense 612×384 grid into a 2560×1600 drawable: **GPU 1.775 ms median**, p95 2.302 ms, CPU encode 0.120 ms on the M1 Max (`docs/Rendering-v5.md:44–51`).
- Compact CPU extraction: **0.691 ms for 222,200 particles**, versus 20.189 ms for the old per-particle Swift path. Upload fell from 10.76 to 3.59 MiB per frame (`docs/Engine Performance.md:28–37`).

Rheo has no CPU extraction at all, because particles never leave the GPU. Its render cost is the splat plus the composite. Budget about 2–3 ms of GPU at phone resolution and verify on the device [I].

### 5.6 Validation plan (Powder's evidence discipline)

**Tier 1: host CPU reference** (`swift test --package-path Packages/RheoEngine --no-parallel`):

- **Flow curves:**
  - Herschel–Bulkley `τ = τ_y + K·γ̇ⁿ` against analytic values for n < 1 (ketchup), n = 1 (honey control) and n > 1 (oobleck).
  - Bingham plug width in channel flow against `τ_y/(ΔP/L)`.
  - The thixotropic structure parameter λ recovering with time constant τ_λ after a shear step.
  - Arrhenius viscosity ratio at two temperatures.
- **MPM invariants:**
  - total mass conserved exactly (fixed point);
  - momentum conserved in free flight;
  - finite state under a 10 s stress scene;
  - a clone or replay evolves bitwise identically (Nano's 900-step clone test).

**Tier 2: GPU against reference** (Powder's `verify-material-rendering.swift` pattern):

- Build a harness with the **production** `.metal` and Swift encoders. Run N substeps from the same initial state.
- For short horizons (≤ 20 substeps), compare per-particle positions to the CPU with relative L2 error under 1e-4. For long horizons (chaotic), compare statistics: centre of mass, kinetic energy, total mass, spread.
- Fixed-point P2G makes GPU replays **bit-identical** (§3.7), so assert that too.
- Record the shader and metallib SHA-256 next to the results, as Powder does (`docs/Rendering-v5.md:61`).

**Tier 3: device** (iPhone 15 Pro Max, iOS 27.2):

- OSSignposter intervals for `rigid.step`, `encode` and `frame`.
- `MTLCommandBuffer` GPU times, 32 warm-up frames then 96 samples, reported as median and p95. That is Powder's protocol in `scripts/benchmark-rendering.swift:45–94`.
- Sustained 5-minute run: record the thermal state and the lag ratio.
- **The simulator's Metal runs on the host GPU and is not evidence of phone performance.**

**Evidence log format** (Powder's `docs/Validation.md`): a dated section stating host, command, exit status, test or assertion counts, logs kept under `Documentation/evidence/`, and an explicit "does not establish …" sentence.

### 5.7 Build tooling

Gyre's `Tools/build.sh` mirrors **only its own folder** (`rsync "$SRC/" "$WORK/src/"`). Rheo's `../LabKit` package reference would then be dangling in the mirror. Mirror both projects as siblings [V: the probe used the same sibling layout with `path: ../LabKitProbe` and built]:

```zsh
#!/bin/zsh
# Tools/build.sh — xcodebuild hangs on the iCloud folder: mirror Rheo and LabKit side by side, then build.
#   Tools/build.sh sim | device | test
set -e
SRC="$(cd "$(dirname "$0")/.." && pwd)"
LABKIT="$(cd "$SRC/../LabKit" && pwd)"
WORK="${RHEO_BUILD_DIR:-${TMPDIR:-/tmp}/RheoBuild}"
mkdir -p "$WORK"
rsync -a --delete --exclude '.build' --exclude '.swiftpm' "$LABKIT/" "$WORK/LabKit/"
rsync -a --delete --exclude 'Rheo.xcodeproj/xcuserdata' --exclude 'DerivedData*' --exclude '.build' "$SRC/" "$WORK/Rheo/"
cd "$WORK/Rheo"
xcodegen generate --quiet
case "${1:-sim}" in
  sim)    xcodebuild -project Rheo.xcodeproj -scheme Rheo -configuration Debug \
            -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath "$WORK/dd" build ;;
  device) xcodebuild -project Rheo.xcodeproj -scheme Rheo -configuration Release \
            -destination 'generic/platform=iOS' -allowProvisioningUpdates DEVELOPMENT_TEAM=YOUR_TEAM_ID \
            -derivedDataPath "$WORK/dd" build ;;
  test)   TOOLCHAINS=metal swift test --package-path "$WORK/LabKit" --no-parallel --scratch-path "$WORK/spm-labkit"
          TOOLCHAINS=metal swift test --package-path "$WORK/Rheo/Packages/RheoEngine" --no-parallel --scratch-path "$WORK/spm-rheo" ;;
esac
```

Also run `xcodegen generate` in the **source** tree whenever `project.yml` changes. Gyre's mirror-only regeneration left a stale checked-in `Info.plist` without the camera and microphone usage keys (`design-gyre.md`, "Gotcha found") [S].

---

## 6. Pitfalls the projects hit, and where they apply

1. **iCloud folder.**
   - xcodebuild hangs (Gyre `Tools/build.sh:2–3`).
   - `.app` bundles in Documents gain FinderInfo that breaks strict codesign (`docs/Validation.md:66, 73`).
   - Disabling signing for simulator builds caused **Keychain error −34018** (`:21, :66`).
   - Powder still keeps `DerivedData*` folders inside the iCloud tree, and Nano keeps `.derivedData` there [V `ls`]. Keep all DerivedData and SwiftPM scratch output under `$TMPDIR` or the scratchpad.
   - Ignore `* 2.*` iCloud conflict copies (`Powder 2.xcodeproj` exists [V]).
2. **SwiftPM `DEBUG=1`** collides with upstream identifiers (Powder `Config.h:2–5`). It is harmless for Box2D [V].
3. **Release without `NDEBUG`** keeps Box2D asserts on [V]. **Debug `-O0`** makes the C engine 10–15× slower [V]. Nano's unoptimised Swift core was 22.7× slower and blocked the main actor [S].
4. **Metal toolchain resolution on the beta.**
   - SwiftPM CLI Metal compiles fail by default, and `xcrun -sdk macosx metal` fails while plain `xcrun metal` works [V].
   - **`TOOLCHAINS=metal` fixes the SwiftPM CLI** [V, revision 2].
   - Powder fell back to a host-specific cryptex path (`Rendering-v4.md:41`) [S]. Do not hard-code cryptex paths, because the mount name carries the component version.
5. **No Metal device inside the agent sandbox** for Powder's GPU harness (`Rendering-v4.md:49`) [S]. In this session `swift test` did get a Metal device [V], so this varies by environment. Make the harness fail loudly when there is no device, as Powder's does.
6. **Nested SwiftPM sandbox and module caches** in restricted environments. Use `CLANG_MODULE_CACHE_PATH` and `SWIFTPM_MODULECACHE_OVERRIDE` pointed at writable directories, plus `--disable-sandbox` when needed (`UPSTREAM.md`, Validation §Reproduction) [S]. I needed only the cache variables [V].
7. **Universal Mac test builds** needed `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` (`docs/Mac-v5.md:38`) [S]. This is irrelevant for iPhone-only Rheo.
8. **Process-global engine state:**
   - Powder serialises everything behind one recursive mutex [V].
   - Box2D has an unlocked world table and global units [V].
   - Global state plus parallel tests gives flaky determinism [V].
9. **GPU optimisation without measurement.**
   - Powder's compact path cut CPU encode by about 61% but cost **+0.181 ms GPU** in the dense Retina case.
   - A "texture metadata cache" was discarded after it failed to help (`Rendering-v5.md:51–53`) [S].
   - Measure CPU and GPU separately, with warm-ups and p95.
10. **Telemetry and charts at the simulation rate** saturate the main thread. Publish at 10 Hz and chart at 2 Hz or less (Nano `design-qa.md:6`; Gyre) [S].
11. **Honest fixtures.** Powder corrected two test fixtures (detector identifier, NEUT inside METL) rather than engine rules, and recorded that (`Engine Performance.md:52`, `Mac-v5.md:38`) [S]. Keep that discipline in Rheo's physics checks.
12. **Save quantisation versus in-memory clones.** OPS round trips are not bit-identical, so exactness is tested only for in-memory clones (`Validation.md:28`) [S].

    For Rheo: persist scene descriptions plus the seed. Do not persist GPU buffers expecting bitwise replay across app versions.

---

## 7. Open questions and risks

- A17 Pro GPU throughput for real MLS-MPM kernels, float-atomic behaviour on Apple9 and sustained thermals are **unmeasured**. All budgets in §3.8 and §5.2 are inferred.
- One-frame-lagged rigid–fluid coupling may be unstable for light props in dense or stiff fluids. It needs a dedicated test before the scene catalogue relies on it.
- The Box2D 3.2 upgrade (snapshot, replay, mover joint) is attractive for undo and replay but untagged. Pin 3.1.1 and revisit once `v3.2.0` is tagged.
- Host-side compiled-shader tests depend on `TOOLCHAINS=metal` resolving the Metal Toolchain component. If an Xcode update leaves the component missing, they fail until the user runs `xcodebuild -downloadComponent MetalToolchain`. App builds through xcodebuild are unaffected.
- **The substep count is unresolved between the sibling notes:** about 170 per 60 Hz frame (`rheology-models.md`) versus 2–8 (`oss-engine-survey.md`). At about 4–10 µs of fixed GPU cost per dependent dispatch (§3.10), the high count needs fused kernels to fit at all. That must be settled by the solver prototype on the device, not by this note.
- `unsafeFlags` makes LabKit consumable only as a local `path:` package. That is the current setup, but a future remote-package plan would need flag changes.

---

## 8. Reconciliation with the sibling research notes (revision 2)

Four notes in this folder touch the same build and integration decisions. Where they conflict, this table states what to follow and why. Re-verified items are marked [V].

| Topic | `oss-engine-survey.md` | `toolchain-checks.md` | `labkit-from-gyre.md` | This note | Follow |
|---|---|---|---|---|---|
| Box2D pin | v3.1.1, `8c66146…` | v3.1.1, `8c66146…` | — | v3.1.1, `8c66146…`, tarball SHA-256 and manifest hash recorded | **v3.1.1** (all agree) |
| C target name | `CBox2D` | `Box2D` (`import Box2D`, also exported as a product) | — | `CBox2D` | **`CBox2D`**, never a product. A `Box2D` module next to a `LabKitRigid` wrapper invites apps to bypass the wrapper. Also, `include/Box2D/Box2D.h` matches `box2d/box2d.h` on case-insensitive APFS for umbrella guessing. |
| Module map | Explicit; lists all 6 headers | Generated by SwiftPM | — | Explicit; `header "box2d/box2d.h"` + `export *` | Either explicit form works. `box2d.h` includes the other five [V], so one line is enough. Do **not** rely on generation. |
| `headerSearchPath("src")` | not used | used | — | not used | **Omit it.** The probe builds without it [V]. |
| Release `NDEBUG`, `-ffp-contract=off`, `-O2` | Upstream strict warnings checked | No defines | — | All three | **All three** (§3.3–3.4 [V]) |
| Tools version and platforms | — | — | 6.4, `.iOS(.v27)`, `.macOS(.v27)` | was 6.0 / `"27.0"`, now 6.4 / `.v27` | **6.4 / `.v27`** [V with Box2D] |
| Host Metal compile through the SwiftPM CLI | `xcrun -sdk macosx metal` is a stub; use runtime `makeLibrary(source:)` | **`TOOLCHAINS=metal swift test`** works | "`swift build --target LabKitRender` fails; keep host harness Core-only" | was a runtime-source env switch | **`TOOLCHAINS=metal`** [V]. Keep runtime source compiling only for the physcheck parity harness. |
| `resources: [.process("Shaders")]` | used, works | used; removing it verified under `swift build` only | "No manifest entry needed" under xcodebuild | used | Both work. **Keep it explicit** for readability. |
| Shader-types target | `CLabShaderTypes` (`MPMShared.h`) | `LabKitShaderTypes` | `LabKitShaderTypes` (`LabFrameUniforms`, …) | `LabKitShaderTypes` (LabKit) + `RheoShaderTypes` (MPM) | **`LabKitShaderTypes`** for chrome and rigid instances. MPM structs go in the solver package's own header. |
| Rigid wrapper | `LabRigid2D` / `RigidWorld2D` | `ProbePhysics` (probe only) | — | `LabKitRigid` / `RigidWorld` | **`LabKitRigid`**, matching the `LabKit*` product naming |
| Render target | — | `LabKitMetal` | `LabKitRender` | `LabKitRender` | **`LabKitRender`** (labkit-from-gyre is the LabKit architecture note) |
| MPM placement | LabKit (`LabMPM`, `LabMPMReference`) | — | Rheo `Physics/` or `RheoCore` target | `Rheo/Packages/RheoEngine` | **RheoEngine first, promote later** (§5.4). The orchestrator decides. |
| P2G accumulation | int32 fixed point in threadgroup tiles; float 1.3–1.5× slower | — | — | int32 fixed point; float non-deterministic | **int32 fixed point** (all agree) |
| Substeps per frame | 2–8 at 120 Hz (PB-MPM + implicit viscosity) | — | — | Quantum design absorbs either; ≤ ~100 dependent dispatches per frame | **Unresolved** (§7). It is a solver decision. `rheology-models.md`'s ~170 needs fused kernels (§3.10). |
| Box2D step | fixed 1/120 s, 4 substeps | `1/60`, 4 (smoke test) | — | one step of `h` per quantum, 4 substeps | **1/120 s quanta** (§5.2) |
| Threading | CPU Box2D step → GPU substeps → splat, per frame | — | `LabRenderer` is `@MainActor` (MTKView) | Main-actor render loop owns time; `CAMetalDisplayLink` thread as phase 2 | **Main actor first** (all compatible) |

---

## Appendix A: reproducing the experiments

Root: `/private/tmp/claude-501/-Users-utkarsh-Documents-AI-Stuff/b53a2b83-9308-4477-a9dd-fedd258cad75/scratchpad/oss-integration/`

| Path | Contents |
|---|---|
| `box2d-v3.1.1/`, `box2d-main/` | Upstream clones |
| `gh-v3.1.1.tar.gz` | GitHub tarball, hashed above |
| `LabKitProbe/` | Package. Targets: `CBox2D` (vendored and unmodified, plus the modulemap), `LabBuildProbe` (macro probe), `LabShaderTypes` (shared header), `LabPhysics2D` (wrapper with `internal import`), `LabRender` (Metal resource target). Tests: `ProbeTests`, `ScaleTests`. |
| `ProbeApp/` | XcodeGen iOS 27 app (Swift 6, strict concurrency) depending on the package by `path: ../LabKitProbe` |
| `atomics*.metal`, `atomics*.swift` | Float vs fixed-point scatter benchmark |
| `encode-bench.swift` | MPM-shaped encode and GPU timing (§3.8) |
| `encode-bench2.swift`, `encode-bench3.swift`, `encode-bench4.swift` | Revision 2: high substep counts, isolated per-dispatch overhead, and concurrent encoder with barriers (§3.10) |
| `tc-metal/LabKitProbe/` | Revision 2 copy of the probe: tools-version 6.4, `.v27`, `swiftLanguageModes [.v6]`, unconditional `-O2`, no runtime-shader switch (`tc-metal.log`, `tc64.log`) |
| `RenderHostSkeleton.swift` | Swift 6 `CAMetalDisplayLink` render-thread skeleton (type-check only) |

Commands:

```zsh
cd …/oss-integration/LabKitProbe
export CLANG_MODULE_CACHE_PATH=$PWD/../cache/clang SWIFTPM_MODULECACHE_OVERRIDE=$PWD/../cache/swiftpm
LABKIT_RUNTIME_SHADERS=1 swift test --no-parallel --scratch-path ../build-debug            # original run (fallback path)
LABKIT_RUNTIME_SHADERS=1 swift test -c release -Xswiftc -enable-testing --no-parallel --scratch-path ../build-release
cd ../tc-metal/LabKitProbe && TOOLCHAINS=metal swift test --no-parallel --scratch-path ../build64   # revision 2: compiled metallib
cd ../../ProbeApp && xcodegen generate && xcodebuild -project ProbeApp.xcodeproj -scheme ProbeApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath ../dd-app build
cd .. && xcrun metal -target air64-apple-macos26.0 -c atomics3.metal -o atomics3.air && xcrun metallib atomics3.air -o atomics2.metallib && ./atomics3-check   # binary loads atomics2.metallib by design
xcrun swiftc -O encode-bench.swift -o encode-bench && ./encode-bench      # likewise encode-bench2/3/4
xcrun -sdk iphoneos swiftc -typecheck -swift-version 6 -strict-concurrency=complete -target arm64-apple-ios27.0 RenderHostSkeleton.swift
```
