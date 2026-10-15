# Rheo: open-source engine survey for a real-time non-Newtonian fluid toy

Research date: 3 October 2026. Target: Rheo ("Non-Newtonian Toy") on iPhone 15 Pro Max (A17 Pro, 6-core GPU, iOS 27.2), built on the shared **LabKit** package. Toolchain on this Mac: Xcode-beta (`iPhoneOS27.0.sdk`, Swift 6.4 `swiftlang-6.4.0.20.104`), Metal Toolchain v27.1 (`metal` 32023.917), M1 Max (32-core GPU) for desktop measurements.

**Revision 2 (same day, 16:30).** Revision 1 recommended PB-MPM's position-based solver as Rheo's material solver and planned 2–8 substeps per 120 Hz frame. Both points were wrong, and the sibling notes had already flagged the conflict (`oss-integration-lessons.md` §3.10 and §8 call the substep count "unresolved"). A new CPU experiment (§6.1) settles it:

- At **real gravity in a phone-sized tank**, PB-MPM needs **12–16 substeps × 2–3 iterations, about 32–48 grid passes per 120 Hz frame**, to hold volume within 5 %. Explicit MLS-MPM needs about the same: **38–53 passes**.
- PB-MPM's cheap 2-substep demo settings work only because its gravity is normalised to 2.5 grid heights per s². In Rheo's 72 × 154 mm tank that is about 0.39 m/s², 25 times weaker than Earth.
- So the 2D explicit MLS-MPM hypothesis **stands**, using the backward-Euler elasto-viscoplastic return map from `rheology-models.md`.
- PB-MPM is still ported, with attribution. We take its **GPU infrastructure** (tile binning, fused `g2p2g`, fixed-point tile atomics, guardian band, emitter free list) and its **grid-volume J correction**. Without that correction, a J-tracked explicit liquid loses 16–34 % of its real area in 3 s.

Revised sections: §0, §2 (PB-MPM row), §3.1, §4 (scaling), §6, §7.1–7.5, §9. The Box2D build was re-run in this revision and still passes (§5.1).

Evidence tags used throughout:

| Tag | Meaning |
|---|---|
| **[V]** | Verified here: built, ran, or read the source at the cited commit/line. |
| **[R]** | Read in official docs, README or release notes (not exercised). |
| **[I]** | Inferred or estimated. Needs on-device measurement before it becomes a number in code. |

Scratch work (not part of any project) lives in `/private/tmp/claude-501/-Users-utkarsh-Documents-AI-Stuff/b53a2b83-9308-4477-a9dd-fedd258cad75/scratchpad/`:
`box2d-check/` (Box2D SwiftPM package, host app, logs), `mpm-bench/` (Metal MLS-MPM benchmark), `oss-survey/` (PB-MPM clones). No existing project was modified.

---

## 0. Decisions in one table

| # | Decision | Evidence |
|---|---|---|
| 1 | **Vendor Box2D v3.1.1 verbatim** (MIT, C17) as LabKit's `CBox2D` C target for rigid props. Pin the tag; do not track `main` (3.2.0-dev renames files and APIs). | §5: builds clean for iOS device + simulator, 0 warnings with upstream's strict flags, smoke test passes on iPhone 17 Pro simulator [V]. |
| 2 | **Keep the hypothesis: 2D explicit MLS-MPM on Metal compute**, with the backward-Euler elasto-viscoplastic (EVP) return map from `rheology-models.md` §1 as the constitutive update. Viscosity and yield go inside the return map and therefore never limit the time step. Elasticity is explicit, with softened moduli (wave speed c ≈ 2–3 m/s). | §6.1: measured on CPU [V]. Sibling GPU runs hold honey (10 Pa·s), toothpaste, putty and a jammed-oobleck analogue stable with 0 NaN at 60–65 substeps per frame [S: `mpm-metal-check/bench/run_materials.txt`]. |
| 3 | **Port PB-MPM's infrastructure to MSL, with attribution** (EA SEED, BSD-3-Clause, WGSL), not its material solver. Take: bukkit tile binning, the fused `g2p2g` with threadgroup fixed-point tiles, the guardian band, the emitter free list, and the **grid-volume J correction** (`gridToParticle.wgsl:71-85`). PB-MPM's position-based constraint solve stays an optional experiment. | §6.1: at real gravity PB-MPM costs as many passes as explicit (32–48 against 38–53 per 120 Hz frame) and is not in SI units. Without the grid-volume correction, explicit liquids lose 16–34 % of their area in 3 s; with it they hold 0.98–1.05 [V]. |
| 4 | **Budget substeps by the advection CFL as well as the wave CFL.** In a 72 mm tank at Δx = 1.125 mm and real g, either method needs about 40–55 grid passes per 120 Hz frame (§6.1). Each substep must therefore be 1–2 fused dispatches, against the sibling cap of about 100 dependent dispatches per frame (`oss-integration-lessons.md` §3.10). A governor dilates time when the cap would be exceeded. | §6.1, §7.4, §7.5. |
| 5 | P2G accumulation: **int32 fixed-point atomics in threadgroup memory** (PB-MPM "bukkit" tiles). MSL has **no threadgroup `atomic_float`** even at `-std=metal4.0`. Device-memory `atomic_float` exists but is 1.3–1.5x slower than int32 here. | §4 [V]. |
| 6 | Two-way prop coupling: grid-momentum impulses accumulated as integers on the GPU, applied to Box2D one frame later with `b2Body_ApplyLinearImpulse` / `b2Body_ApplyAngularImpulse` (the CPIC-style scheme used by dimforge/slosh). At most 16 dynamic props. | §3.6, §7.4. |
| 7 | Use as **reference only** (read, re-derive, cite; no code copied): nialltl/incremental_mpm, taichi_mpm `mls-mpm88-explained.cpp`, Taichi `mpm88/mpm99`, matsuoka-601 WebGPU-Ocean/Splash, Lague Fluid-Sim, PavelDoGreat WebGL fluid, chunleili non-Newtonian SPlisHSPlasH fork, dimforge/slosh, Genesis, larsblatny/matter (GPL). | §3. |
| 8 | **Exclude**: LiquidFun (archived, Box2D 2.3, CPU), Taichi runtime on iOS (experimental, project dormant since July 2025), PhysX 5 particles (CUDA-only), NVIDIA Warp/Newton (no Metal), FluidX3D (non-commercial + "no AI training" licence; OpenCL), Ziran2020 (no licence). Apple ships no fluid framework. | §3. |

---

## 1. What the solver has to do (requirements → solver demands)

Rheo's material list and stimuli (from the project brief) translate into these solver demands:

| Material / stimulus | Physics needed | Solver demand |
|---|---|---|
| Oobleck (cornstarch) | Discontinuous shear thickening, impact jamming, "running on oobleck", vibration "monsters" | Stress-activated jamming state per particle; near-rigid response within one frame; stable at effectively infinite viscosity |
| Ketchup, paint | Shear thinning (power law / Carreau / Cross) | Per-particle rate-dependent viscosity from the local strain rate |
| Toothpaste, mayo | Bingham / Herschel–Bulkley yield stress | A stable plug (zero flow below yield) without tiny time steps |
| Slime, silly putty | Viscoelastic (Maxwell): bounces on impact, flows over time | Elastic deformation gradient with relaxation; history on particles |
| Yogurt, quicksand | Thixotropy: structure breaks under shear, rebuilds at rest | Scalar structure parameter λ advected with material |
| MR fluid | Field-dependent yield (magnetometer + Magnet knob) | Yield stress τ_y(H); optional anisotropy along the field |
| Honey | Newtonian high viscosity control | Stable at μ ≈ 10 Pa·s |
| Tilt / shake / Moon–Jupiter | Gravity vector and magnitude, impulses | Cheap global body force; CFL-aware substeps |
| Poke / punch / stir | Moving colliders with momentum transfer | Kinematic colliders on the grid; two-way props |
| Sound (mic) | Vertical vibration | Effective gravity g + A·ω²·sin ωt; needs substeps ≥ ~8 per drive period |
| Temperature | Arrhenius viscosity | Per-particle or per-material scalar |

Two consequences drive every choice below:

1. **History lives on material points.** Elastic strain, plastic strain, the thixotropic λ and the jam fraction all move with the material. That favours particle or hybrid particle–grid methods (MPM, SPH) over pure Eulerian grids or LBM.
2. **Stiffness spans ten orders of magnitude.** Water (μ = 1 mPa·s) and jammed oobleck (η → ∞) must share one time step at 120 Hz. Viscosity and yield must therefore be treated implicitly. A backward-Euler return map does this per particle, with no linear solve. Elasticity can stay explicit if the moduli are softened (§6.1).
3. **The tank is small and gravity is real.** A 72 × 154 mm tank at Earth gravity (up to Jupiter's 24.79 m/s²) moves fluid many cells per frame. The advection CFL, not stiffness alone, sets the substep count for every candidate solver (§6.1).

---

## 2. Comparison table

Particle counts are for **2D** unless marked 3D, at 120 Hz with about 4 ms of GPU time per frame for simulation, on A17 Pro. All phone counts are **[I]** unless stated: they scale this Mac's measurements (§4) by 5–8x (A17 Pro ≈ 2.15 TFLOPS FP32 and 51.2 GB/s versus M1 Max ≈ 10.4 TFLOPS and 400 GB/s).

| Candidate | Licence | Last activity (checked 3 Oct 2026) | Lang | Dim | iOS / Metal viability | Non-Newtonian / viscoplastic support | Realistic phone count | Integration effort | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| **Box2D v3** (erincatto/box2d) | MIT | Release **v3.1.1** 2025-06-04 (lightweight tag `8c661469`); `main` = 3.2.0-dev, pushed 2026-09-24 [V] | C17 | 2D | **Builds for iOS device + sim via SwiftPM, 0 warnings, test passes** [V] | None (rigid only) | Hundreds–thousands of bodies; we need ≤ 16 dynamic props [I] | Low (done: §5) | **Vendor verbatim** |
| **PB-MPM** (electronicarts/pbmpm) | BSD-3-Clause | v1.0.0; `main` `61749b6` 2024-10-17 (HEAD unchanged, re-checked 16:30); `siggraph2024` branch `5a2f438` 2024-08-05 [V] | WGSL + JS (~2,000 lines on `main`) | 2D | WGSL → MSL is close to mechanical; workgroup int atomics map to threadgroup `atomic_int` [V compiled] | Liquid with relaxation viscosity, elastic, Drucker–Prager sand, simple "visco" yield clamp [V]; no rate-dependent viscosity, thixotropy or jamming. Relaxation factors are not SI | Real gravity in a 72 mm tank needs 32–48 passes per 120 Hz frame (§6.1) [V CPU], the same as explicit. Phone count as for explicit (§7.5) [I] | Medium: port binning, fused-tile kernel and grid-volume correction (~2–3 days) | **Port the infrastructure and grid-volume correction with attribution**; not the material solver |
| **Explicit MLS-MPM + EVP return map** (the hypothesis; new code per `rheology-models.md`, structure after Hu 2018 / mpm88) | ours | n/a | MSL + Swift | 2D | Sibling prototype compiles at `-std=metal3.1` and `metal4.1` and runs on M1 Max [S: `mpm-metal-check/doc/`] | All Rheo classes through one return map (`rheology-models.md` §1) | 38–53 passes per 120 Hz frame at Δx 1.125 mm (§6.1) [V CPU]; ~3.5–8k particles at 120 Hz on A17 Pro [I] | Medium–high (new constitutive code; infrastructure from PB-MPM) | **Build** |
| LiquidFun (google/liquidfun) | zlib | **Archived**; last commit 2018-01-10; last release v1.1.0 2014-07-16 [V] | C++ | 2D | Builds on iOS historically (ObjC++ samples exist), CPU only | Heuristic flags: `b2_viscousParticle`, `b2_elasticParticle`, `b2_springParticle`, `b2_powderParticle`, `b2_tensileParticle`, `b2_staticPressureParticle` (`b2Particle.h:34-77`) [V]; not rheology | ~3–8k CPU [I] | Medium; conflicts with Box2D v3 (based on Box2D 2.3) | **Exclude** |
| SPlisHSPlasH (InteractiveComputerGraphics) | MIT | v2.18.1 2026-09-01 [V] | C++ (Eigen, OpenMP) | 3D + 2D ("now supports 2D", Changelog) [V] | CPU desktop library; heavy deps; not real-time on a phone [I] | Mainline has **no NonNewton module** (only implicit viscosity: Weiler 2018, Peer 2015/16, Takahashi 2015, Bender 2017; elasticity: Becker 2009, Peer 2018, Kugelstadt 2021, Kee 2023) [V tree] | n/a | High | **Reference only** (desktop cross-check) |
| chunleili/nonNewtonCode (SPlisHSPlasH fork, TVCG 2024 "A Unified Particle-Based Solver for Non-Newtonian Behaviors Simulation") | MIT | last commit 2025-10-14 [V] | C++ | 3D | Same as above | `NonNewton.cpp`: Newtonian, power law, Cross, Casson, Carreau, Bingham, Herschel–Bulkley, time and temperature hooks [V] | n/a | n/a | **Reference for formulas only** (has bugs, §3.3) |
| Taichi (taichi-dev/taichi) + taichi-aot-demo | Apache-2.0 | v1.7.4 2025-07-31; last commit 2025-07-30 (dormant) [V] | Python → C-API runtime | 2D/3D | iOS static C-API build script exists (`.github/workflows/scripts/ti_build/ios.py`: `TI_WITH_METAL`, no LLVM, `ENABLE_BITCODE=True`, deployment 13.0) [V]; Metal in C-API is "Tier 2"/experimental [R] | mpm88 (fluid), mpm99 (fluid/jelly/snow) | Similar to hand-written Metal [I] | High (Python AOT pipeline, bitcode patching, large runtime) | **Reference only** |
| taichi_mpm `mls-mpm88-explained.cpp` (yuanming-hu) | MIT | 2022-02-23 [V] | C++ | 2D | Trivial to port | Snow plasticity + hardening | CPU reference | Low | **Reference for CPU harness** |
| nialltl/incremental_mpm | MIT | 2019-04-29 [V] | C# (Unity Burst) | 2D | Port by hand | Newtonian fluid with dynamic viscosity + Neo-Hookean; "recompute volume each step" trick [R] | CPU reference | Low | **Reference for CPU harness** |
| Ziran2020 (penn-graphics-research) | **None** (no LICENSE file) [V] | 2021-07-12 | C++ | 2D/3D | Linux toolchain (GCC 7) | Snow, Cam-Clay, von Mises, Drucker–Prager, smudge (`Lib/Ziran/Physics/PlasticityApplier.h`) [V] | n/a | n/a | **Exclude code** (all rights reserved); cite papers |
| matsuoka-601 WebGPU-Ocean / WaterBall / Splash | MIT | 2025-06-09 / 2025-02-21 / 2025-04-22 [V] | TypeScript + WGSL | **3D** | Port by hand | Newtonian (Tait EOS) | 3D: README claims ~100k on integrated GPUs, ~300k on discrete [R]; phone ~20–40k 3D [I] | Medium | **Reference** (fixed-point P2G, narrow-range filter rendering) |
| holtsetio/flow | MIT | 2025-05-07 [V] | JS (three.js TSL) | 3D | n/a | Newtonian | n/a | n/a | Reference (minor) |
| dimforge/slosh | Apache-2.0 | v0.8.0, pushed 2026-09-29 [V] | Rust + Slang | 2D/3D | wgpu runs on Metal and Slang can emit MSL, but needs a Rust staticlib + Slang toolchain in the iOS build [I] | Linear elastic, Neo-Hookean, Drucker–Prager, PML; **rigid coupling** via integer impulses, ≤ 16 bodies (`rigid_impulses.slang`) [V] | n/a | High | **Reference** for two-way coupling |
| Sebastian Lague Fluid-Sim | MIT | 2025-10-19 [V] | C# + HLSL (Unity) | 2D/3D | Port by hand | Newtonian SPH with near-density (Clavet 2005 style), no springs [V] | 2D SPH tens of thousands on desktop [R] | Medium | **Reference** (GPU counting-sort spatial hash, SSFR) |
| PavelDoGreat WebGL-Fluid-Simulation | MIT | 2024-11-12 [V] | JS + GLSL | 2D Eulerian | Ports easily; runs on phones today [R] | Newtonian only, no free surface | Grid sim, not particles | Low | **Reference** for bloom/sunrays/dye look |
| PhysX 5 (NVIDIA-Omniverse) | BSD-3-Clause | 2026-09-18 [V] | C++ | 3D | Rigid CPU builds exist; **PBD particles and deformables need a CUDA context** [R]; no MPM in tree [V] | PBD fluids only (CUDA) | 0 on iOS | n/a | **Exclude** |
| NVIDIA Warp / Newton | Apache-2.0 | 2026-10-03 [V] | Python/CUDA | 3D | macOS wheels are **CPU-only, no Metal** (README) [R] | MPM examples (granular) | 0 on iOS | n/a | **Exclude** |
| Genesis World (+ Quadrants compiler) | Apache-2.0 | 2026-10-01 [V] | Python | 3D | Metal on macOS via Quadrants; no iOS runtime [R] | MPM: elastic, elasto-plastic, liquid, sand, snow, muscle (`genesis/engine/materials/MPM/`) [V tree] | 0 on iOS | n/a | Reference (desktop prototyping) |
| Jolt Physics | MIT | v5.6.0 2026-07-11 [V] | C++17 | 3D | iOS ARM64 listed as supported [R] | Rigid + XPBD soft bodies; no fluids | n/a | Medium | **Not for Rheo**; LabKit's future 3D rigid choice |
| Bullet 3 | zlib | 2025-10-22 [V] | C++ | 3D | Builds on iOS | Soft bodies; no non-Newtonian | n/a | Medium | Exclude |
| FluidX3D | **Custom, source-available**: no commercial use, no military use, **"You may not train AI models on the source code"** (clause 4) [V licence only] | 2026-10-03 | C++/OpenCL | 3D LBM | OpenCL does not exist on iOS | Non-Newtonian LBM possible in principle | 0 | n/a | **Exclude; do not read or port its source** |
| larsblatny/matter | **GPL-3.0** | 2026-09-22 [V] | C++/OpenMP | 2D/3D | CPU | von Mises, Drucker–Prager, Modified Cam-Clay, **Viscous von Mises** with Hencky elasticity [R] | CPU | n/a | **Reference to papers only** (GPL would infect LabKit) |
| Apple frameworks | n/a | n/a | n/a | n/a | SpriteKit and RealityKit have rigid physics only; SceneKit is soft-deprecated since WWDC25 [R]; MPS has no physics | None | n/a | n/a | **None exist** |
| Small Metal repos (hagmas/MobileFluidSimulation MIT 2017; yangfengzzz/fluid-engine-Swift MIT 2020; mchapman87501/DMCLBMMetal MIT 2022; Pierre-Joly/SPH-Fluid-Metal-GPU MIT 2026; dustin-biser/LiquidMetal no licence 2016) | mixed | stale or tiny [V metadata] | Swift + MSL | 2D | Yes | None non-Newtonian | n/a | n/a | Glance only |

GitHub searches for "mpm metal", "mls-mpm metal", "material point method swift", "non-newtonian mpm" and "oobleck" turned up **no open-source Metal/iOS MPM** and **no real-time non-Newtonian toy engine** [V, searched 3 Oct 2026]. Whatever we build in Metal will be new code. The best starting point is a port.

---

## 3. Notes per candidate

### 3.1 PB-MPM (Electronic Arts SEED): the infrastructure to port

- **Source** [V]: `https://github.com/electronicarts/pbmpm`. On `main`, the solver is one fused kernel, `shaders/g2p2g.wgsl` (486 lines), plus bukkit (tile) binning: `bukkitCount`, `bukkitAllocate`, `bukkitInsert`, `setIndirectArgs`, `particleEmit`. The `siggraph2024` branch (`5a2f438`) is the readable version with separate passes: `gridZero`, `particleToGrid`, `gridUpdate`, `gridToParticle`, `particleUpdatePBMPM`, `particleIntegrate` (1,072 WGSL lines). **Port the readable branch first, then the fused one.**
- **Per substep** (`src/sim.js:134-197`): emit, then indirect args, then bukkit count/allocate/insert, then `iterationCount` × `g2p2g` with triple-buffered grids.
- **Defaults on `main`** (`src/ui.js:127-145`) [V]: 240 Hz sim rate, 5 iterations, 8 px per cell, 2×2 particles per cell, fixed-point multiplier 10^7, liquid relaxation 1.5, elastic relaxation 1.5, liquid viscosity 0.01, friction angle 30°, visco plasticity 0.9, `useGridVolumeForLiquid` on.
- **Defaults on `siggraph2024`** (`src/ui.js:89-105`) [V]: 480 Hz, **2** iterations, liquid relaxation 2.0, visco plasticity 0. Liquid and sand are emitted at **1 particle per cell** whatever the UI says (`particleEmit.wgsl`: `select(particlesPerCellAxis, 1, material == Liquid || material == Sand)`).
- **Gravity is normalised to the grid, not SI** [V]: `displacement.y -= gridSize.y · gravityStrength · dt²` (`particleIntegrate.wgsl:145`; `g2p2g.wgsl:320` on `main`), with `gravityStrength` 2.5. The demo world falls 2.5 domain heights per s².
  - In Rheo's 154 mm tank that is 0.385 m/s², or **1/25 of Earth gravity**.
  - Characteristic speeds in cells per second are therefore about 5x lower than Rheo's.
  - That is why 2 iterations at 480 Hz, or 5 at 240 Hz, look stable in the demo. §6.1 measures what real gravity costs.
- **Tiles**: `BukkitSize 6`, halo 1, so each tile is 8×8 nodes × 4 components = 1,024 `atomic<i32>` in workgroup memory, double-buffered (`g2p2g.wgsl:21-27`). That is 8 KB, well under the A17 Pro's 32 KB threadgroup limit.
- **Particle** (`particle.inc.wgsl:6-21`): position, displacement, deformation gradient F, deformation displacement B, liquidDensity, mass, material, volume, lambda, logJp, colour, enabled.
- **Materials** (`g2p2g.wgsl`):
  - Liquid: volume-preservation constraint `alpha = 0.5·(1/liquidDensity − tr(B) − 1)`, plus viscosity by removing a fraction of sym(B) per iteration (lines 368–380).
  - Elastic: shape matching toward a blend of the rotation `U·Vᵀ` and the volume-preserving `Q = F/√|det F|` (lines 382–398).
  - Sand: Drucker–Prager return mapping after Klár et al. 2016 (lines 239–275).
  - Visco: singular-value clamp to `[1/e^(1−plasticity), e^(1−plasticity)]` with volume re-scaling (lines 277–290).
- **What we take (ported to MSL with attribution)**:
  - Bukkit tile binning plus the fused tile-local `g2p2g`, with `atomic<i32>` tiles in workgroup memory. The tile layout carries over unchanged to an explicit solver: P2G of momentum and mass is the same scatter.
  - The fixed-point encode and decode (`simConstants.inc.wgsl:19-27`) and the "positions in cells, mass ≈ 1" unit discipline.
  - The guardian band (`particle.inc.wgsl:27-43`) and the grid-side guardian projection (`gridUpdate.wgsl:68-89`).
  - The emitter and free list (`particleEmit.wgsl`, `particleIntegrate.wgsl:147-176`) and the push/grab pointer tools (`particleIntegrate.wgsl:124-142`).
  - The **grid-volume J correction** (`gridToParticle.wgsl:59-85`). P2G also scatters particle volume as a 4th grid component. G2P interpolates it, forms J_grid = 1/Σ w·V_node, and when J_grid < 1 (compressed) relaxes the particle's J 10 % of the way toward it. §6.1 shows this is the ingredient that keeps volume, in PB-MPM and in explicit MPM alike.
- **What we leave**:
  - The position-based constraint solve. It needs as many passes as explicit at real gravity (§6.1), and its "relaxation" factors have no SI meaning.
  - Grid-normalised gravity (`particleIntegrate.wgsl:145`).
  - The clamp-to-yield "visco" plasticity, which is not a flow law.
- **What neither version has, and we add** (§7): rate-dependent viscosity, yield, thixotropy, jamming, field and temperature dependence (all in the EVP return map), and rigid-body two-way coupling. PB-MPM's colliders are one-way analytic shapes.

### 3.2 Box2D v3

- Release v3.1.1 is the latest tag; `main` is 3.2.0-dev with large file churn [V]:
  - `world.c` → `physics_world.c`.
  - New `parallel_for.c`, `recording.c`, `replay.c`, `pogo_joint.c`, `mover_joint.c`.
  - `mouse_joint.c` removed.
  - New public headers `config.h`, `constants.h`, `math_types.h`.
  - Commit #1108 "Rename stuff for consistency".
- `main` also compiles clean for iOS (§5.5). Pin v3.1.1 now and upgrade when 3.2.0 is tagged.
- v3.1 dropped the SIMDe dependency in favour of custom NEON/SSE2 (`docs/release_notes_v310.md`) [V]. The vendored tree is self-contained: 57 `.c/.h` files plus 6 public headers, 34,143 lines.
- Relevant v3.1 features: `b2Body_SetTargetTransform` (kinematic finger/stirrer), `b2World_Explode` (a "punch" shock), sensor events, surface materials with rolling resistance, cross-platform determinism.

### 3.3 SPlisHSPlasH and the non-Newtonian fork

- Mainline SPlisHSPlasH has no non-Newtonian module (tree listing at HEAD) [V].
- The NonNewton code lives in Chunlei Li's fork `chunleili/nonNewtonCode` (MIT), in `SPlisHSPlasH/My/NonNewton/` [V]. It is useful as a **formula catalogue** (`NonNewton.cpp:373-447`):
  - Power law: `K·γ̇^(n−1)`
  - Cross: `μ∞ + (μ0−μ∞)/(1+(Kγ̇)^n)`
  - Casson: `(√μc + √(τy/γ̇))²`
  - Carreau: `μ∞ + (μ0−μ∞)/(1+Kγ̇²)^((1−n)/2)`
  - Bingham / Herschel–Bulkley in bi-viscosity form: `μ0` below a critical γ̇_c, else `τ0/γ̇ + Kγ̇^(n−1)` with `τ0 = μ0γ̇_c − Kγ̇_c^n`
- **Bugs found** [V]:
  - The strain-rate loop overwrites instead of accumulating (`NonNewton.cpp:247-249`: `strainRate = velGrad + velGrad.transpose(); strainRate *= m;` inside the neighbour loop). The norm therefore comes from the last neighbour only.
  - Every model prints to `std::cout` every step.
  - Do not use it as a numerical oracle. Write our own CPU reference.

### 3.4 Taichi

- The language is excellent for prototyping on a Mac (Metal backend).
- For shipping on iOS it is a poor bet:
  - The project has been dormant since 2025-07-30.
  - The iOS path is a static C-API library with `ENABLE_BITCODE=True` hard-coded. Bitcode has been deprecated since Xcode 14, so it needs patching.
  - Kernels must be AOT-compiled from Python.
  - Metal in the C-API is documented as experimental / Tier 2.
- `mpm88.py` / `mpm99.py` (Apache-2.0) remain the clearest algorithm references. Read them; do not copy them.

### 3.5 LiquidFun

- Google archived it.
- It sits on Box2D 2.3 (C++ `b2World`), so it cannot coexist conceptually with Box2D v3's C API.
- Its "viscous/elastic/powder" flags are tuned heuristics with strengths in [0,1] (`b2ParticleSystem.h:167-177`), not rheological models.
- It is CPU-only.

### 3.6 dimforge/slosh: reference for MPM ↔ rigid coupling

- `shaders/slosh/solver/rigid_impulses.slang` accumulates per-body impulses as `int` with `FLOAT_TO_INT_FACTOR = 1e5`.
- It is limited to 16 bodies "due to the CPIC affinity bitmask size".
- It applies the impulses to bodies in a 16-thread kernel.
- The same scheme maps to Box2D: the GPU sums impulses, the CPU reads them next frame and calls the Box2D impulse API (§7.4).
- Apache-2.0: re-implement from the idea; do not copy the code.

### 3.7 Rendering references (2.5D look)

- matsuoka-601/Splash (MIT): screen-space fluid rendering with the Narrow-Range Filter (Truong & Yuksel 2018) and ray-marched shadows through the density grid from an extra P2G [R].
- Sebastian Lague (MIT): bilateral and Gaussian smoothing passes, foam [V file list].
- PavelDoGreat (MIT): bloom and sunrays post [R].
- In 2D the pipeline gets simpler:
  1. Splat particles additively into a half-resolution thickness/velocity texture.
  2. Separable blur.
  3. Normals from the thickness gradient (height field).
  4. Refraction offset of the background, Fresnel specular, tint by material.
  5. LabKit's bloom/EDR chain.
- This needs no depth pass.

### 3.8 Excluded with reasons

- **FluidX3D**: licence clause 4 forbids training AI models on its source, and it bans commercial and military use. It is OpenCL-only, which is not on iOS. Its source was **not read** for this note; only `LICENSE.md` was.
- **PhysX 5**: GPU particles/deformables need a CUDA context. There is no MPM in the tree; the current headers are `PxPBDParticleSystem.h`, `PxDeformableVolume.h`, … [V tree].
- **Warp / Newton**: no Metal.
- **Genesis**: desktop Python.
- **Ziran2020**: no licence.
- **matter**: GPL-3.0. Its "Viscous von Mises" (Perzyna-type) model is exactly the elasto-viscoplastic family Rheo needs, so read its cited papers instead of its code.

---

## 4. Measured: 2D MLS-MPM cost in Metal (M1 Max) and what it means for A17 Pro

To ground the particle counts, I wrote a minimal explicit 2D MLS-MPM (mpm88-style: weakly compressible fluid with E = 400, APIC affine C, J tracking). It has 4 kernels per step (`clearGrid`, `p2g*`, `gridUpdate`, `g2p`), runs from a Swift CLI and is timed with `MTLCommandBuffer.gpuStartTime/gpuEndTime` over 600 steps in batches of 50. The square domain is filled over ¼ of its area at 2×2 particles per cell. Files: `scratchpad/mpm-bench/{mpm.metal, main.swift}` [V].

| Grid | Particles | `atomic_float` P2G (ms/step) | int32 fixed-point P2G (ms/step) |
|---|---|---|---|
| 128² | 16,129 | 0.095 | 0.069 |
| 181² | 32,400 | 0.157 | 0.117 |
| 256² | 65,025 | 0.301 | 0.232 |
| 362² | 130,321 | 0.538 | 0.358 |
| 512² | 261,121 | 1.134 | 0.742 |

Physics sanity [V]: both variants give identical centre-of-mass drops (mean y 0.400 → 0.315 at 128², which matches ½gt² for 0.13 s of free fall).

Lessons [V]:

1. **MSL has no threadgroup float atomics.**
   - `threadgroup atomic_float` fails to compile for iOS at `-std=metal3.0`, `metal3.1` and `metal4.0`. The candidates are `volatile device _atomic<T>` only.
   - `threadgroup atomic_int` compiles.
   - So PB-MPM's tile accumulation must stay fixed-point.
2. **Fixed-point needs unit design.**
   - My first multiplier (scaled per grid size) silently truncated the per-step gravity momentum `m·g·dt` to zero, and the fluid hung in mid-air.
   - With `scale = 2^20 / particleMass` it matched the float path.
   - In a long splash run at 65k it later overflowed and exploded (J → ∞).
   - Rule: express grid quantities in grid units with particle mass ≈ 1 (as PB-MPM does: positions in cells, multiplier 10^7, `simConstants.inc.wgsl:19-27`).
   - Add a debug overflow check in physcheck.
3. **Atomic contention can dominate.**
   - When a naive boundary let about 6,100 particles pile into **one cell**, step time grew from 0.29 to 4.6 ms (16x) at 65k.
   - Production layout: bin particles into tiles (PB-MPM bukkits), accumulate in threadgroup memory, flush once per tile.
   - Make boundaries project particles cleanly (PB-MPM's "guardian" band, `particle.inc.wgsl:27-43`).
4. **Package shaders work.** `.metal` files in a SwiftPM target with `resources: [.process("Shaders")]` compile to `<Pkg>_<Target>.bundle/default.metallib`. `MTLDevice.makeDefaultLibrary(bundle: Bundle.module)` loaded all 5 functions in an XCTest on the iPhone 17 Pro iOS 27.0 simulator [V]. LabKit can own its shaders.
5. **Toolchain quirk.** `xcrun -sdk iphoneos metal` resolves to the downloaded Metal Toolchain (cryptex v27.1). `xcrun -sdk macosx metal` resolves to a stub that errors "missing Metal Toolchain" [V]. Runtime `makeLibrary(source:)` worked on macOS, so Mac harnesses can compile MSL from source at run time.

**Scaling to A17 Pro** [I]: divide M1 Max throughput by 5–8x (FLOPs ratio 4.8, bandwidth ratio 7.8), then allow about 30% thermal headroom.

- 16k particles: ≈ 0.35–0.55 ms per explicit step or PB-MPM iteration.
- 32k particles: ≈ 0.6–0.95 ms.
- 65k particles: ≈ 1.2–1.9 ms.

PB-MPM's fused, tile-local `g2p2g` does more maths per particle (2×2 SVD) but far less global traffic, so one iteration ≈ one explicit step is a fair first guess. **Phase 0 must replace these with on-device numbers** (Metal System Trace on the 15 Pro Max).

**Fused-kernel numbers from the sibling solver prototype** [S: `scratchpad/mpm-metal-check/bench/run_fused.txt`, M1 Max, shared GPU, noisy ×1.5–2]. One clear plus one fused `g2p2g` per substep, Z-order sorted every 16 substeps:

| Grid | Particles | µs per substep |
|---|---|---|
| 64 × 136 | 6,400 | 32.6 |
| 64 × 136 | 15,200 | 40.7 |
| 96 × 205 | 20,384 | 46.5 |
| 128 × 273 | 31,680 | 67.5 |
| 128 × 273 | 68,688 | 120.6 |

- Below about 30k particles, the cost per substep is dominated by fixed per-dispatch latency, at about 4–10 µs per dependent dispatch (`oss-integration-lessons.md` §3.10).
- That latency probably does not shrink by the 5–8x throughput ratio on A17 Pro, but it does not grow either. Phone estimates below apply the full ratio and are therefore pessimistic at small particle counts [I].
- GPU parity against the CPU reference was 0.0019 mm centroid difference over 400 substeps [S].

---

## 5. Box2D v3.1.1 on iOS: build check

### 5.1 What was done [V]

1. `git clone --depth 1 --branch v3.1.1 https://github.com/erincatto/box2d.git` (commit `8c661469c9507d3ad6fbd2fea3f1aa71669c2fe3`, a lightweight tag, 2025-06-03).
2. Copied `src/*.c src/*.h` → `Sources/CBox2D/src/`, `include/box2d/*.h` → `Sources/CBox2D/include/box2d/`, and `LICENSE` → `Sources/CBox2D/LICENSE`. No upstream file was edited.
3. Added `Sources/CBox2D/include/module.modulemap` (below), a Swift 6 target calling the C API, and an XCTest.
4. Ran these builds and tests (all from the scratchpad, derived data in the scratchpad):

   | Command | Result |
   |---|---|
   | `xcodebuild -scheme LabBox2D -destination 'generic/platform=iOS Simulator' -derivedDataPath ../DerivedData build` | **BUILD SUCCEEDED** in 7.4 s, arm64 + x86_64, **0 warnings** |
   | `xcodebuild test -scheme LabBox2D -destination 'platform=iOS Simulator,name=iPhone 17 Pro' …` | **TEST SUCCEEDED** |
   | `xcodebuild -scheme LabBox2D -configuration Release -destination 'generic/platform=iOS' … OTHER_CFLAGS='$(inherited) -Wall -Wextra -pedantic -Wmissing-prototypes -Wshorten-64-to-32' build` | **BUILD SUCCEEDED**, **0 warnings**; `CBox2D.o` 1.6 MB (unstripped object) |
   | Direct `clang -std=gnu17 -O2 -ffp-contract=off -target arm64-apple-ios27.0` with upstream's Apple warning set over all 35 `.c` files (22 private headers) | 0 warnings. `-std=c17` (no GNU extensions) also gave 0 warnings and 0 errors. |
   | XcodeGen app (`SWIFT_VERSION 6.0`, `SWIFT_STRICT_CONCURRENCY: complete`) depending on the package by local `path:` | **BUILD SUCCEEDED**. A local path package with `unsafeFlags` is accepted. |

   The smoke test is Box2D's "hello world": a 1 m box dropped from y = 4 onto a ground slab, 90 steps at 60 Hz with 4 sub-steps. It printed `Box2D 3.1.1 final x=-8.306993e-05 y=0.9999111 angle=-5.5743403e-06`, i.e. at rest on the ground at y = 1 ± 0.02.

   **Re-run in revision 2 (16:29)** into a fresh `DerivedData-recheck` [V]:
   - The simulator build gave **BUILD SUCCEEDED** in 12 s with 0 warnings. The log shows `-std=gnu17` and `-ffp-contract=off`.
   - `xcodebuild test` on the iPhone 17 Pro simulator gave **TEST SUCCEEDED**, with bit-identical output. Both tests passed: the Box2D smoke test and the package-metallib load test.
   - `git ls-remote` confirms that **v3.1.1 is still the newest tag** (`8c661469`) and that `HEAD` is still `956ce4e`.
   - Logs: `box2d-check/build-sim-recheck.log` and `test-sim-recheck.log`.

5. C globals imported cleanly in Swift 6 language mode, with no concurrency diagnostics: `b2_nullBodyId`, `b2Rot_identity`, `b2Vec2_zero` (`static const` in `id.h:77-81` and `math_functions.h:81-84`) and the macro `B2_DEFAULT_CATEGORY_BITS`.

### 5.2 Exact package definition (verified)

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LabBox2D",
    platforms: [.iOS("27.0"), .macOS("15.0")],
    products: [.library(name: "LabBox2D", targets: ["Box2DSmoke"])],
    targets: [
        .target(
            name: "CBox2D",
            exclude: ["LICENSE"],                       // + "src/box2d.natvis", "src/CMakeLists.txt" if src/ is copied whole
            cSettings: [
                .define("NDEBUG", .when(configuration: .release)), // disables B2_ASSERT (core.h:15-19)
                .unsafeFlags(["-ffp-contract=off"]),              // upstream CMakeLists.txt:38-41 (determinism)
            ]
        ),
        .target(name: "Box2DSmoke", dependencies: ["CBox2D"],
                resources: [.process("Shaders")],
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "Box2DSmokeTests", dependencies: ["Box2DSmoke"]),
    ],
    cLanguageStandard: .gnu17   // upstream: C_STANDARD 17, C_EXTENSIONS YES (src/CMakeLists.txt "C17 for _Static_assert and anonymous unions")
)
```

```
// Sources/CBox2D/include/module.modulemap
module CBox2D {
    header "box2d/box2d.h"
    header "box2d/math_functions.h"
    header "box2d/collision.h"
    header "box2d/id.h"
    header "box2d/types.h"
    header "box2d/base.h"
    export *
}
```

The compiler response file confirmed `-std=gnu17`, `'-ffp-contract=off'` and `-DSWIFT_PACKAGE`, plus `-O0 -g` (Debug) or `-Os -DNDEBUG` (Release) [V].

### 5.3 Flags and defines: what is needed and what is not

- **SIMD: no flags needed.** `src/core.h:59-82` picks the path from the target [V via `clang -E -dM`]:

  | Target | Defines |
  |---|---|
  | `arm64-apple-ios27.0` | `B2_CPU_ARM`, `B2_PLATFORM_IOS`, `B2_SIMD_NEON`, `B2_SIMD_WIDTH 4` |
  | `arm64-apple-ios27.0-simulator` | `B2_SIMD_NEON` |
  | `x86_64-apple-ios27.0-simulator` | `B2_SIMD_SSE2` |

  - Opt out with `BOX2D_DISABLE_SIMD`.
  - `BOX2D_AVX2` is x86-only and irrelevant.
  - `BOX2D_ENABLE_SIMD`, which third-party wrappers still pass (e.g. LuizZak/SwiftBox2D), is **not referenced anywhere** in v3.1.1 or `main` [V grep]. It is a no-op.
- **C standard**: `.gnu17`. `.c17` also compiles clean.
- **`-ffp-contract=off`**: optional. Keep it so a recorded scene replays identically on simulator and device. It needs `unsafeFlags`, which SwiftPM accepts for root and local-path packages (verified through XcodeGen) but rejects for versioned remote dependencies. That is fine because LabKit is consumed by path.
- **Do not set `BOX2D_VALIDATE`** in app builds: heavy validation only, `core.h:21-25`.
- **Warnings**:
  - Clean under `-Wall -Wextra -pedantic -Wmissing-prototypes -Wshorten-64-to-32`.
  - `-Wconversion -Wdouble-promotion` produce **875 warnings** (754 sign-conversion, 103 double-promotion, 14 implicit-int, 4 int-float).
  - So **never pass global `OTHER_CFLAGS`** with conversion warnings to package targets. SwiftPM targets do not inherit the app's `CLANG_WARN_*` settings, only command-line overrides.
- **SwiftPM header layout gotcha** [V]:
  - An umbrella header `include/CBox2D.h` next to the `include/box2d/` directory fails with "invalid header layout: umbrella header found … but directories exist next to it". Use the explicit `module.modulemap` above.
  - `exclude:` entries must exist on disk. Excluding a missing `src/box2d.natvis` fails package resolution.
- **Threading**: `b2WorldDef.workerCount/enqueueTask/finishTask` (`types.h:126-136`) are optional. The default is single-threaded, which is ample for ≤ 16 props.

### 5.4 Coupling API (v3.1.1 signatures, `include/box2d/box2d.h`) [V]

```c
B2_API void b2World_Step( b2WorldId worldId, float timeStep, int subStepCount );          // :39
B2_API void b2World_SetGravity( b2WorldId worldId, b2Vec2 gravity );                        // :134
B2_API void b2World_Explode( b2WorldId worldId, const b2ExplosionDef* explosionDef );      // :142
B2_API b2Transform b2Body_GetTransform( b2BodyId bodyId );                                  // :245
B2_API b2Vec2 b2Body_GetLinearVelocity( b2BodyId bodyId );                                  // :265
B2_API float  b2Body_GetAngularVelocity( b2BodyId bodyId );                                 // :268
B2_API void b2Body_SetTargetTransform( b2BodyId bodyId, b2Transform target, float timeStep ); // :280  (kinematic finger/stirrer)
B2_API void b2Body_ApplyLinearImpulse( b2BodyId bodyId, b2Vec2 impulse, b2Vec2 point, bool wake ); // :321
B2_API void b2Body_ApplyAngularImpulse( b2BodyId bodyId, float impulse, bool wake );        // :339
B2_API b2Vec2 b2Body_GetWorldCenterOfMass( b2BodyId bodyId );                               // :351
```

### 5.5 Upgrade path to 3.2.0 [V]

- `main` (`956ce4e`, 2026-09-24, `project(box2d VERSION 3.2.0)`) compiled clean as a SwiftPM C target for the iOS simulator with `exclude: ["src/CMakeLists.txt", "src/box2d.natvis", "src/box2d.pc.in"]`.
- It also compiled clean with direct strict-flag `clang` for the device.
- Expect Swift call-site changes: renames and joint changes.

### 5.6 Provenance record for LabKit (mirror Powder's `UPSTREAM.json`)

```json
{
  "upstream": "https://github.com/erincatto/box2d",
  "tag": "v3.1.1",
  "tagType": "lightweight",
  "commit": "8c661469c9507d3ad6fbd2fea3f1aa71669c2fe3",
  "archiveURL": "https://github.com/erincatto/box2d/archive/refs/tags/v3.1.1.tar.gz",
  "archiveSHA256": "fb6ef914b50f4312d7d921a600eabc12318bb3c55a0b8c0b90608fa4488ef2e4",
  "licenseSHA256": "68a3e676d7e94093b102d5cba0d4e04af812040d6f230c3db67a6664574e43d2",
  "vendoredRoot": "Sources/CBox2D",
  "modifiedUpstreamFiles": [],
  "addedFiles": ["include/module.modulemap"]
}
```

The archive hash was computed on 3 Oct 2026 from GitHub's generated tarball (780,115 bytes). GitHub generated archives are usually stable but not contractually so, so the commit hash is the authority.

---

## 6. Challenging the "2D MLS-MPM on Metal" hypothesis

### 6.1 What really limits the time step (revision 2: measured)

**What revision 1 got wrong.** It applied the explicit *viscous* limit, dt ≤ ρΔx²/(4μ), to every stiff material, and concluded that only a position-based solver could carry honey, a Bingham plug, jammed oobleck or bouncing putty at 120 Hz. Two things were missed.

1. **The viscous limit disappears under an implicit return map.** `rheology-models.md` (§1 items 2–3, §5.4) puts viscosity and yield in a per-particle backward-Euler Herschel–Bulkley return map on the elastic predictor. That map is unconditionally stable for any viscosity and reproduces the steady flow curve exactly whatever Δt is [C there].
   - The only stiffness limit left is the elastic wave CFL, dt ≤ C·Δx/(c + v).
   - It is acceptable once K and G are softened to c ≈ 2–3 m/s (shear modulus G ≈ 3 kPa instead of putty's 10⁵ Pa).
   - The sibling GPU prototype ran putty (G 3 kPa: it bounced, bottom 3.4 → 19.2 → 23.9 mm), honey (10 Pa·s), toothpaste (τ_y 150 Pa; the plug stopped flowing by 0.3–0.5 s) and a jammed-oobleck analogue (G 6 kPa, τ_y 2 kPa). All were stable with 0 NaN at 60–65 substeps per 1/120 s frame [S: `mpm-metal-check/bench/run_materials.txt`].
2. **Real gravity in a small tank makes the advection CFL dominate for every solver.**
   - A 63 mm dam-break column reaches √(2gh) ≈ 1.1 m/s, with splash peaks around 2 m/s.
   - At Δx = 1.125 mm that is roughly 1,000–1,800 cells/s, or 8–15 cells per 1/120 s frame.
   - PB-MPM's iterations cannot replace substeps here: the transfer itself must not skip cells.
   - PB-MPM's demo hides this behind gravity normalised to 2.5 domain heights per s² (§3.1), 1/25 of Earth's in Rheo's tank.

**Experiment** [V]. Files are in `scratchpad/oss-survey/pbcheck/`: `main.swift`, `diag.swift`, `run_full2.txt`. Build with `xcrun swiftc -O -o pbcheck main.swift diag.swift && ./pbcheck`. The run took 104 s of wall time on 10 cores.

- **Scene**: a CPU dam break in a 72 mm-wide tank on a 64 × 136 node grid (Δx = 1.125 mm). The water column is 31.5 × 63 mm, with 6,272 particles at 2×2 per cell. It runs for 3 s of 1/120 s frames.
- **PB-MPM**: the `siggraph2024` pass order for liquids, line for line, with the `main` defaults (relaxation 1.5, viscosity 0.01, grid-volume correction on). It uses float sums instead of fixed-point atomics, and PB-MPM's own sticky guardian walls.
- **Explicit**: mpm88-style weakly compressible MLS-MPM in SI units. Stress is K(J−1)I + 2μ·sym(C), with μ = 1 mPa·s and slip walls. dt = 0.5·Δx/(c + 1.25·v_max).
- **Metrics**:
  - "Occupied" is the number of cells holding at least one particle at t = 3 s, divided by the initial 1,568.
  - Values from 0.95 to 1.10 mean volume was kept. Values above 1 come from surface spray and roughness.
  - Mean J is what each solver *believes* its volume is.

| Solver and setting | Gravity | Passes per 1/120 s frame | Occupied / initial | Mean J | Max cells moved per substep |
|---|---|---|---|---|---|
| PB-MPM 2 substeps × 3 iterations (revision 1's plan) | 9.81 | 6 | **0.461** | 0.536 | 8.04 |
| PB-MPM 4 × 3 | 9.81 | 12 | 0.676 | 0.672 | 2.23 |
| PB-MPM 8 × 3 | 9.81 | 24 | 0.860 | 0.855 | 1.44 |
| PB-MPM 12 × 3 | 9.81 | 36 | 0.936 | 0.917 | 1.18 |
| PB-MPM 16 × 2 | 9.81 | 32 | 0.960 | 0.928 | 0.89 |
| **PB-MPM 16 × 3** | 9.81 | **48** | **0.985** | 0.949 | 0.89 |
| PB-MPM 24 × 2 | 9.81 | 48 | 1.014 | 0.965 | 0.61 |
| PB-MPM 16 × 3, grid-volume correction **off** | 9.81 | 48 | **0.688** | 0.968 | 0.86 |
| PB-MPM 2 × 5 (PB demo regime) | 0.385 | 10 | 0.997 | 0.943 | 1.35 |
| PB-MPM 24 × 3 | 24.79 (Jupiter) | 72 | 0.979 | 0.944 | 0.94 |
| PB-MPM 32 × 3 | 24.79 | 96 | 1.013 | 0.966 | 0.71 |
| Explicit c = 2 m/s, J-tracked only | 9.81 | 38.9 | **0.659** | 0.980 | 0.25 |
| Explicit c = 3 m/s, J-tracked only | 9.81 | 52.7 | 0.740 | 0.989 | 0.23 |
| Explicit c = 5 m/s, J-tracked only | 9.81 | 82.1 | 0.841 | 0.996 | 0.14 |
| **Explicit c = 2 m/s + PB grid-volume correction** | 9.81 | **37.6** | **0.989** | 0.962 | 0.31 |
| **Explicit c = 3 m/s + correction** | 9.81 | **52.6** | 1.054 | 0.984 | 0.20 |
| Explicit c = 5 m/s + correction | 9.81 | 81.5 | 1.133 | 0.993 | 0.15 |
| Explicit c = 3 m/s + correction | 24.79 | 55.7 | 0.979 | 0.958 | 0.25 |

What the table shows:

1. **PB-MPM at revision 1's 2 × 3 setting loses half the water**: occupancy 0.46, with a column of particles stuck to the right-hand wall in the ASCII dump. To keep volume within ~5 % it needs ≤ 1 cell per substep, i.e. **12–16 substeps and 32–48 passes per frame at Earth gravity**, and 72–96 at Jupiter gravity.
2. **Explicit needs about the same pass count**: 38 at c = 2 m/s and 53 at c = 3 m/s. Both solvers' passes have the same shape: one fused tile `g2p2g` plus a clear. So PB-MPM has **no budget advantage** in Rheo's regime. It also has no SI meaning, while the explicit EVP route reproduces measured flow curves.
3. **The real volume-keeper is PB-MPM's grid-volume correction, not its constraint solve.**
   - PB-MPM without the correction: 0.69.
   - Explicit with only J tracking: 0.66–0.84, while its mean J still reads 0.98–1.00. The particles clump while J "believes" nothing happened. This is the classic J-drift that nialltl's "recompute volume" and WebGPU-Ocean's grid-density EOS also address.
   - Explicit with the correction (J ← J + 0.1·(J_grid − J) when J_grid < 1): 0.98–1.05.
   - The sibling's explicit water run shows the same loss: occupied 1,605 mm² against 2,025 mm² of particle area [S: `run_eos.txt`]. Its grid-density EOS variant went unstable [S].
4. Revision 1's PB-MPM budget (2 × 3 passes, 16k particles at 120 Hz) is withdrawn. §7.5 replaces it.

Caveats [I]:
- CPU float without fixed point; a liquid dam break only.
- Walls differ (sticky for PB, slip for explicit).
- The occupancy metric is coarse (±5 %).
- PB-MPM's elastic and sand paths were not exercised here.
- The pass counts scale with 1/Δx (finer grids need more substeps) and with √g.

### 6.2 Alternatives considered

| Option | For | Against | Verdict |
|---|---|---|---|
| **Explicit MLS-MPM + EVP return map + PB grid-volume correction** (GPU) | SI units; exact steady flow curves; one per-particle return map covers every class (`rheology-models.md`); viscosity and yield never limit dt; same pass count as PB-MPM at real gravity (§6.1) | Elastic moduli must be softened (c ≈ 2–3 m/s), so putty bounces softer than real; 40–55 passes per 120 Hz frame at Δx 1.125 mm; J-tracked liquids drift without the grid-volume correction | **Choose** |
| PB-MPM position-based solve (GPU) | Rigid and incompressible limits by iteration; BSD-3 code exists; 2D | No advantage at real gravity (needs ≤ 1 cell per substep like everyone else, §6.1); relaxation factors are not SI and depend on iteration count; no flow-law structure for HB, thixotropy or DST | **Port infrastructure only**; keep the constraint solve as an experiment for "rigid jam" if softened-G oobleck feels too soft |
| Implicit MPM (Newton/CG, e.g. HOT 2020) | Physically calibrated | Per-step linear solves; far too heavy for a phone at 120 Hz | No |
| SPH (Clavet 2005 viscoelastic springs, DFSPH + implicit viscosity) | Good "goo" look; SPlisHSPlasH formulas | GPU neighbour search costs about 3x MPM (WebGPU-Ocean: ~30k SPH vs ~100k MPM on the same iGPU [R]); stiff viscosity also needs implicit solves; yield/jamming less natural | No |
| Eulerian grid (stable fluids) with viscosity field | Very cheap; PavelDoGreat runs on phones | Free surface, tearing, chunks and elastic snap-back are hard; no material history | No (keep for post effects / dye) |
| LBM (non-Newtonian via local relaxation time) | Massively parallel | Free surface is complex; solid-like or yield behaviour is weak; FluidX3D unusable | No |
| LiquidFun particles | Box2D-native API | Archived, CPU, heuristic | No |
| 3D MPM in a thin slab | "Real" 3D look | 27-node stencil (3x per particle) and more particles for the same frontal area | No; 2D + Hele-Shaw drag + 2.5D rendering instead |
| "Zoomed world" (render a 15 cm tank, simulate it as ~0.5–1 m with gravity scaled down, as PB-MPM's demo does) | 3–5x fewer substeps | Splashes, slumps and stoppage heights stop matching a real tray; conflicts with the Moon–Jupiter presets | No. Use the time-dilation governor (§7.4) for overload instead |

### 6.3 Box2D for props: kept, with limits

- Box2D brings proper rigid–rigid contact, joints (a hinged paddle, a stirring rod) and kinematic targets.
- The alternative (props as stiff elastic MPM particles) gives two-way coupling for free, but props stay slightly soft, cost particles and have no joints.
- Use Box2D for ≤ 16 dynamic props plus kinematic "tools".
- The MPM grid sees each body as a moving collider. Fluid → body reaction comes back as impulses (§7.4).

### 6.4 Thin-tank (Hele-Shaw) framing: one extra term

- For a cell of gap b, depth-averaging plane Poiseuille flow across the gap adds a wall drag per unit volume: **f = −(12 μ_eff / b²) · v** (N/m³).
- Applied implicitly on the grid each substep: `v ← v / (1 + dt · 12 μ_eff / (ρ b²))`.
- It is unconditionally stable and gives the "thin tank" damping.
- With μ_eff from the material law it also makes shear-thinning visibly different from Newtonian in the gap.
- Expose b (e.g. 2–10 mm) as a hidden tuning constant, not a knob.

---

## 7. Recommended architecture

### 7.1 What goes where

| Layer | Content | Provenance |
|---|---|---|
| `LabKit/Sources/CBox2D/` | Box2D v3.1.1 `src/` + `include/box2d/` + `LICENSE`, plus our `include/module.modulemap` | **Vendored verbatim** (MIT) |
| `LabKit/Sources/LabRigid2D/` | Swift wrapper: `RigidWorld2D` (owns `b2WorldId`), `Prop` value types, a fixed 1/120 s step with `subStepCount 4`, impulse inbox from the GPU | New code |
| `LabKit/Sources/CLabShaderTypes/include/MPMShared.h` | Structs shared by Swift and MSL (`simd/simd.h` types, `#ifdef __METAL_VERSION__` guards) | New code |
| `LabKit/Sources/LabMPM/Shaders/MPMTiles.metal` (+ `.h`) | MSL port of PB-MPM's infrastructure: bukkit count, allocate and insert; indirect args; the fused tile-local `g2p2g` skeleton with threadgroup `atomic_int` tiles; fixed-point encode and decode; guardian projection; emitter free list; the grid-volume J correction | **Ported with attribution** (BSD-3, EA). Every ported file keeps the EA copyright, licence text and a "Ported to Metal and modified for LabKit, 2026" line. |
| `…/Shaders/MPMExplicit.metal` | The explicit MLS-MPM substep: node update (gravity, vibration, rotating frame, colliders, Hele-Shaw drag, rigid impulse sums), then the fused G2P → EVP return map → P2G. Render splats | New code, per `rheology-models.md` and the sibling solver note `mpm-metal.md` |
| `LabKit/Sources/LabMPM/*.swift` | `MPMSolver` (buffers, indirect dispatch, the CFL substep governor with time dilation, readback ring), `MaterialTable` (SI presets → per-material constants) | New code |
| Placement | Generic parts (tiles, fixed point, governor, reference integrator) live in LabKit. The Rheo constitutive law can start in `Rheo/Packages/RheoEngine`, as `oss-integration-lessons.md` §8 recommends, and move into LabKit when a second app needs it | [I] |
| `LabKit/Sources/LabMPMReference/` | CPU Swift (Double) explicit MLS-MPM + the same constitutive functions, used by physcheck and XCTest | New code, informed by nialltl (MIT), `mls-mpm88-explained.cpp` (MIT) and Taichi mpm88/99 (Apache-2.0). No code copied. |
| `Rheo/Tools/physcheck/` | Mac harness (`check(name, ok, detail)` pattern from `Gyre/Tools/physcheck/main.swift:7`): CPU reference tests + GPU-vs-CPU parity via runtime `makeLibrary(source:)` | New code |
| Rendering | 2D SSFR-style thickness/normal/refraction + LabKit bloom/EDR | New code, informed by Splash (MIT), Lague (MIT), PavelDoGreat (MIT) |

### 7.2 Shared particle and constant layouts (proposal)

This layout was compiled both as MSL (`metal -std=metal3.1`, iOS) and as C for arm64 iOS with `static_assert(sizeof == 80, alignof == 8)`, and both passed [V]. `MTLDispatchThreadgroupsIndirectArguments` is usable from MSL [V compiled].

```c
// CLabShaderTypes/include/MPMShared.h  — 80-byte particle, 8-byte aligned (verified in MSL and C)
#pragma once
#ifdef __METAL_VERSION__
#include <metal_stdlib>
#else
#include <stdint.h>
#endif
#include <simd/simd.h>
typedef struct {
    simd_float2   position;      // grid units (cells)
    simd_float2   displacement;  // cells per substep (PB-MPM "displacement")
    simd_float2x2 F;             // elastic deformation gradient
    simd_float2x2 B;             // PB-MPM "deformationDisplacement" (affine, per substep)
    float liquidDensity;         // det(F) proxy for liquid-phase volume constraint
    float mass;                  // ≈ 1 in solver units (keeps fixed-point in range)
    float volume;
    float logJp;                 // Drucker–Prager hardening (sand / quicksand grains)
    float structure;             // thixotropic λ ∈ [0,1]
    float jam;                   // shear-thickening jammed fraction ∈ [0,1]
    float temperature;           // K
    uint32_t material;           // index into MPMMaterial table
} MPMParticle;

typedef struct {                 // SI parameters converted to solver units on the CPU
    float tauYield, K, n, mu0, muInf;    // HB / Carreau family (Pa, Pa·s^n, –, Pa·s, Pa·s)
    float shearModulus, relaxTime;       // Maxwell (Pa, s)
    float lambdaBuild, lambdaBreak;      // thixotropy (1/s, –)
    float sigmaStar, phi, phiM, phi0;    // Wyart–Cates jamming (Pa, –, –, –)
    float mrYieldGain, mrSaturation;     // MR fluid: τy(H) gain and saturation
    float activationEnergy, refTemp;     // Arrhenius (J/mol, K)
    float density;                       // kg/m³
    uint32_t phaseModel;                 // liquid / visco / elastic blend selector
} MPMMaterial;
```

Core kernels (MSL signatures). Indices follow PB-MPM's binding order where it exists:

```metal
kernel void mpmBukkitCount   (constant MPMSimConstants& k [[buffer(0)]],
                              device const MPMParticle* particles [[buffer(1)]],
                              device const uint* particleCount [[buffer(2)]],
                              device atomic_uint* bukkitCounts [[buffer(3)]],
                              uint id [[thread_position_in_grid]]);
kernel void mpmBukkitAllocate(constant MPMSimConstants& k [[buffer(0)]],
                              device const uint* bukkitCounts [[buffer(1)]],
                              device MTLDispatchThreadgroupsIndirectArguments* dispatch [[buffer(2)]],
                              device MPMBukkitThreadData* threadData [[buffer(3)]],
                              device atomic_uint* particleAllocator [[buffer(4)]],
                              device uint* indexStart [[buffer(5)]],
                              uint2 bukkit [[thread_position_in_grid]]);
kernel void mpmBukkitInsert  (constant MPMSimConstants& k [[buffer(0)]],
                              device const uint* particleCount [[buffer(1)]],
                              device atomic_uint* bukkitCounts2 [[buffer(2)]],
                              device const MPMParticle* particles [[buffer(3)]],
                              device uint* bukkitParticles [[buffer(4)]],
                              device const uint* indexStart [[buffer(5)]],
                              uint id [[thread_position_in_grid]]);
kernel void mpmG2P2G         (constant MPMSimConstants& k [[buffer(0)]],
                              device MPMParticle* particles [[buffer(1)]],
                              device const int4* gridSrc [[buffer(2)]],          // fixed-point mvx, mvy, m, vol
                              device atomic_int* gridDst [[buffer(3)]],
                              device atomic_int* gridDstNext [[buffer(4)]],      // zeroed for next iteration
                              device const MPMBukkitThreadData* threadData [[buffer(5)]],
                              device const uint* bukkitParticles [[buffer(6)]],
                              device const MPMCollider* colliders [[buffer(7)]], // analytic + Box2D-driven
                              constant MPMMaterial* materials [[buffer(8)]],
                              device atomic_int* rigidImpulses [[buffer(9)]],    // 3 ints per prop (x, y, angular)
                              uint tid [[thread_index_in_threadgroup]],
                              uint3 tg [[threadgroup_position_in_grid]]);
// threadgroup storage inside mpmG2P2G (PB-MPM g2p2g.wgsl:21-27):
//   threadgroup atomic_int tileSrc[1024], tileDst[1024];   // 8x8 nodes x 4 comps, 8 KB total
kernel void mpmSplat         (constant MPMSimConstants& k [[buffer(0)]],
                              device const MPMParticle* particles [[buffer(1)]],
                              texture2d<half, access::write> thickness [[texture(0)]], ...);
```

### 7.3 Constitutive extensions inside the PB-MPM iteration (where each knob acts)

Per particle per iteration, let D = sym(B)/dt_sub (strain rate, 1/s) and γ̇ = √(2 D′:D′), where D′ is the deviatoric part.

1. **Generalised-Newtonian viscosity.**
   - Replace PB-MPM's constant `liquidViscosity` relaxation r (`g2p2g.wgsl:370-372`: `B += r·0.5·(−(B+Bᵀ))`) with r_i = R(μ_eff(γ̇, T, λ, H)).
   - Herschel–Bulkley with Papanastasiou regularisation: μ_eff = K·γ̇^(n−1) + τ_y·(1 − e^(−mγ̇))/γ̇, where m ≈ 1000 s.
   - Arrhenius: μ ← μ · exp[(E_a/R)(1/T − 1/T_ref)].
   - R(μ) comes from a calibration table (§7.6).
2. **Yield and plug.**
   - For Bingham/HB materials, also run PB-MPM's elastic shape-matching constraint with weight w = clamp(1 − γ̇/γ̇_c, 0, 1).
   - Below yield the material is an elastic solid (plug); above it, it flows.
3. **Maxwell viscoelasticity** (slime, putty).
   - Elastic constraint as PB-MPM "elastic". After each substep, relax F toward its rotation: F ← U·Σ^(1−dt/τ_relax)·Vᵀ (log-strain decay).
   - Small τ_relax flows like slime; large τ_relax bounces like putty.
4. **Thixotropy** (yogurt, quicksand): dλ/dt = (1 − λ)/t_build − k_break·γ̇·λ, and τ_y = τ_y0·λ.
5. **Shear thickening / jamming** (oobleck), after Wyart & Cates 2014 and Baumgarten & Kamrin 2019.
   - f = exp(−σ*/σ), where σ is the local shear stress estimate μ_eff·γ̇.
   - φ_J = f·φ_m + (1 − f)·φ_0.
   - If φ ≥ φ_J, the particle is jammed: jam → 1 with a short time constant, and it switches to the elastic constraint with high relaxation (rigid-like).
   - Otherwise η = η_s·(1 − φ/φ_J)^(−2) through rule 1.
   - Punching (high σ) jams within one substep; resting fluid un-jams and flows.
6. **MR fluid**: τ_y = τ_y0 + k_H·min(H, H_sat)² (and optional anisotropy along the field), with H from the magnetometer plus the Magnet knob.
7. **Global forces**:
   - Gravity vector from Core Motion × preset (Moon 1.62, Mars 3.71, Earth 9.81, Jupiter 24.79 m/s²).
   - Shake impulses.
   - Mic vibration as g_eff(t).
   - The Hele-Shaw drag of §6.4.

Rules 1–3 are PB-MPM's own mechanisms with per-particle parameters. Rules 4–6 add three floats per particle. None of them needs a linear solve.

### 7.4 Frame loop and Box2D coupling

```
frame (1/120 s, MTKView draw):
  CPU: read rigidImpulses ring slot from frame N−1 (shared MTLBuffer, triple-buffered)
       → b2Body_ApplyLinearImpulse(body, J, comWorld, true); b2Body_ApplyAngularImpulse(body, L, true)
       finger/stirrer → b2Body_SetTargetTransform(kinematic, target, 1/120)
       b2World_Step(world, 1/120, 4)
       write MPMCollider[] from b2Body_GetTransform / velocities (≤ 16 dynamic + kinematic tools)
  GPU: for s in substeps (2 at 120 Hz; more when the CFL or vibration rule demands):
         bukkitCount → bukkitAllocate → bukkitInsert → g2p2g × iterations (3–5)
         (grid stage: collider projection; Δp_node inside body footprint → atomic int impulse sum)
       splat → blur → normals/refraction → bloom/EDR
```

- Use substep rule `n = clamp(ceil(max(dt·v_max/(C·Δx), 8·f_drive·dt)), 2, 8)`, where C ≈ 1 cell per substep (advection CFL) and f_drive is the vibration frequency in Hz. This follows Gyre's adaptive rule `n = clamp(ceil(dt·fastest/0.1), 1, 2000)` at `Gyre/Gyre/Physics/GyroSim.swift:140`, with the frame-time clamp at `Gyre/Gyre/Render/HoloRenderer.swift:264`.
- The one-frame impulse lag is acceptable for a toy. It is the same compromise slosh makes by applying impulses in a separate pass.

### 7.5 Budget targets [I]

| Mode | Grid (portrait, 2.17:1) | Particles (2×2 ppc, ~45% fill) | Substeps × iterations | Est. A17 Pro GPU sim |
|---|---|---|---|---|
| 120 Hz default | 64 × 140 | ~16k | 2 × 3 | 2.1–3.3 ms |
| 120 Hz high | 80 × 174 | ~25k | 2 × 3 | 3.3–5 ms (borderline) |
| 60 Hz quality / Low Power | 96 × 208 | ~36k | 2 × 4 | 5–8 ms of 16.7 |

Render plus post at about 2.5–3 ms is in line with Gyre's Metal post chain. **Phase 0 deliverable**: port the `siggraph2024` passes, run a dam break on the 15 Pro Max under Metal System Trace, and replace this table with measured values.

### 7.6 Physics checks (physcheck + XCTest)

Calibration and acceptance tests, CPU reference first and then GPU parity:

1. **Free fall.** The centre of mass accelerates at g ± 0.5% (no walls).
2. **Hydrostatics.** A settled column has J within 1 ± 0.02 and bottom pressure within ρgh ± 5% (CPU explicit).
3. **Dam break.** The front position is compared with Martin & Moyce (1952) for a low-viscosity liquid.
4. **Viscosity calibration** (generates R(μ) for §7.3):
   - Decay of a sinusoidal shear wave, u(y,t) = u₀·sin(ky)·e^(−νk²t).
   - Fit ν_eff against PB-MPM's r, dt, Δx and iteration count.
   - Store the table in `MaterialTable`.
   - Start from r ≈ 1 − exp(−ν·dt/(C·Δx²)) and fit C.
5. **Flow curves.** A plate-driven periodic Couette strip measures τ against γ̇ for each preset. The fit must recover (τ_y, K, n) within 10%.
6. **Yield stop.** A Bingham layer on an incline is static when h < h_c = τ_y/(ρ·g·sin θ) and flows above it.
7. **Thixotropy loop.** A shear ramp up and down shows hysteresis area > 0. Recovery after rest follows t_build.
8. **Jamming.** An impactor at speed v₀ on the oobleck preset stops within d < 2 body radii above a critical v₀. Below it, the impactor sinks.
9. **Buoyancy (Box2D coupling).** A prop with ρ_b/ρ_f = 0.5 floats with a submerged area fraction of 0.5 ± 0.05.
10. **Parity.** GPU and CPU explicit modes on a 2k-particle scene over 100 steps agree to an RMS position difference < 0.05 cell, with no fixed-point overflow (debug counter).

---

## 8. Licence and attribution obligations

| Component | How used | Obligations |
|---|---|---|
| **Box2D v3.1.1**, MIT, © 2022 Erin Catto | Vendored verbatim in `LabKit/Sources/CBox2D` | Keep `LICENSE` (SHA-256 `68a3e676…43d2`) in the vendored folder. Reproduce the notice in `LabKit/THIRD_PARTY_NOTICES.md` and in each app's About/credits (house rule: licences credited in-app, `Spectra/Docs/research/design-house-rules.md:185,234`). Record provenance in `UPSTREAM.json` (§5.6). |
| **PB-MPM**, BSD-3-Clause, © 2024 Electronic Arts Inc. | MSL port (a derivative work) | **Clause 1**: keep the copyright notice, conditions and disclaimer in the source. Put the full licence at the top of every ported `.metal` file, or in `LabMPM/Shaders/LICENSE-PBMPM.md` referenced from each file header. Add "Ported to Metal and modified for LabKit, 2026." **Clause 2**: binary redistribution must reproduce the notice in documentation or other materials, so include it in THIRD_PARTY_NOTICES and in-app credits. **Clause 3**: do not use EA's name to endorse or promote, so no "Powered by EA" wording. Credit the talk ("A Position Based Material Point Method", Chris Lewin, SIGGRAPH 2024) in Documentation. Provenance: `main` `61749b6c2d2631ed243f86882752ba43196f2de7`, `siggraph2024` `5a2f438b7115741c41ed429a2a0360d0e5f4b5a9`, licence SHA-256 `7bb46d23…d5f3`. |
| nialltl/incremental_mpm, taichi_mpm, matsuoka-601, Sebastian Lague, PavelDoGreat, chunleili (all MIT) | Ideas/algorithms only | No legal obligation if no code is copied; credit them in `Documentation/research` and optionally in About. If any snippet is copied, include that project's MIT notice. |
| Taichi mpm88/mpm99, dimforge/slosh, Genesis, Warp (Apache-2.0) | Ideas only | If code is ever copied: include the Apache-2.0 licence and any NOTICE file, and mark modified files (§4(b)). Recommendation: do not copy. |
| larsblatny/matter (GPL-3.0) and Powder Modernization's GPL engine | Not used | Do not copy into LabKit (it would make LabKit GPL). Cite the papers instead. LabKit (MIT/BSD-compatible) **can** be used inside the GPL Powder app, not the reverse. |
| Ziran2020 (no licence) | Not used | All rights reserved. Papers only. |
| FluidX3D (custom: no commercial, no military, no AI training) | **Not used, source not read** | Keep it out of the repository and out of any agent's context. |
| Papers (Hu 2018 MLS-MPM; Klár 2016; Wyart & Cates 2014; Baumgarten & Kamrin 2019; Yue 2015 Continuum foam; Ram 2015 viscoelastic MPM; Li 2024 TVCG non-Newtonian SPH) | Formulas | Cite in Documentation and the in-app methodology sheet ("what is real and what is metaphor"). |

**THIRD_PARTY_NOTICES.md skeleton for LabKit:**

```
## Box2D v3.1.1
Copyright (c) 2022 Erin Catto. MIT License. https://github.com/erincatto/box2d
Commit 8c661469c9507d3ad6fbd2fea3f1aa71669c2fe3. Vendored unmodified in Sources/CBox2D (module.modulemap added).
<full MIT text>

## PB-MPM (A Position Based Material Point Method)
Copyright (c) 2024 Electronic Arts Inc. All rights reserved. BSD 3-Clause License.
https://github.com/electronicarts/pbmpm (main 61749b6, siggraph2024 5a2f438).
Ported from WGSL to Metal Shading Language and modified (rheology extensions, Box2D coupling) for LabKit.
<full BSD-3 text including disclaimer>
```

---

## 9. Risks and open questions

1. **Phone throughput is estimated, not measured** (§4/§7.5). Run Phase 0 on the 15 Pro Max before freezing grid sizes. Thermal throttling over 10+ minutes may force the 60 Hz mode.
2. **PB-MPM is not calibrated in SI.** Relaxation stiffness depends on iteration count and dt. Without the §7.6 calibration, "honey" and "ketchup" will not hold their ratios when the substep count changes (e.g. under vibration). Consider XPBD-style compliance (α = 1/(k·dt²)) to decouple stiffness from iterations.
3. **Fixed-point range.** int32 P2G overflowed in my 65k splash test. Normalise particle mass ≈ 1, positions in cells, a 10^7-class multiplier, plus a debug overflow counter.
4. **Atomic contention pathologies.** Boundary pile-ups gave a 16x slowdown in the naive kernel. Tile binning and guardian projection are mandatory, not optional optimisations.
5. **One-frame lag in prop coupling.** Very light props in very stiff (jammed) fluid may jitter. Clamp impulse magnitude per frame, or sub-iterate the rigid step for the props involved.
6. **Box2D `main` churn.** Pin v3.1.1. 3.2.0 renames APIs (`mouse_joint` removed, `world.c` → `physics_world.c`).
7. **Vibration realism.** Real "cornstarch monsters" need about 100 Hz shaking, which needs ≥ 8 substeps per drive period and is beyond budget. Map mic energy to a visual-rate drive (15–30 Hz) and say so in the in-app methodology sheet.
8. **2D vs reality.** Plane flow and the Hele-Shaw drag change spreading rates compared with an open bowl. The methodology sheet should state the thin-tank framing.
9. **Metal Toolchain dependency.** The `metal` compiler is a separately downloaded component. Build machines need `xcodebuild -downloadComponent MetalToolchain` if missing (the macOS-SDK `xcrun metal` here resolves to a stub).

---

## 10. Sources

- Box2D: https://github.com/erincatto/box2d (MIT; v3.1.1 release 2025-06-04; v3.1 release notes in `docs/release_notes_v310.md`)
- PB-MPM: https://github.com/electronicarts/pbmpm (BSD-3-Clause); demo https://electronicarts.github.io/pbmpm/
- LiquidFun: https://github.com/google/liquidfun (zlib, archived)
- SPlisHSPlasH: https://github.com/InteractiveComputerGraphics/SPlisHSPlasH (MIT); non-Newtonian fork https://github.com/chunleili/nonNewtonCode (MIT); paper https://arxiv.org/abs/2312.04814
- Taichi: https://github.com/taichi-dev/taichi (Apache-2.0); AOT demo https://github.com/taichi-dev/taichi-aot-demo; iOS C-API question https://github.com/taichi-dev/taichi/issues/7935; AOT blog https://docs.taichi-lang.org/blog/taichi-aot-the-solution-for-deploying-kernels-in-mobile-devices
- taichi_mpm (MLS-MPM 88 lines): https://github.com/yuanming-hu/taichi_mpm (MIT)
- nialltl: https://github.com/nialltl/incremental_mpm (MIT); article https://nialltl.neocities.org/articles/mpm_guide.html
- Ziran2020: https://github.com/penn-graphics-research/ziran2020 (no licence)
- matsuoka-601: https://github.com/matsuoka-601/WebGPU-Ocean, https://github.com/matsuoka-601/WaterBall, https://github.com/matsuoka-601/Splash (MIT); Codrops write-up https://tympanus.net/codrops/2025/02/26/webgpu-fluid-simulations-high-performance-real-time-rendering/
- holtsetio/flow: https://github.com/holtsetio/flow (MIT)
- dimforge/slosh: https://github.com/dimforge/slosh (Apache-2.0)
- Sebastian Lague: https://github.com/SebLague/Fluid-Sim (MIT)
- PavelDoGreat: https://github.com/PavelDoGreat/WebGL-Fluid-Simulation (MIT)
- PhysX: https://github.com/NVIDIA-Omniverse/PhysX (BSD-3); particle docs https://nvidia-omniverse.github.io/PhysX/physx/5.4.1/docs/ParticleSystem.html
- Warp: https://github.com/NVIDIA/warp (Apache-2.0); Newton: https://github.com/newton-physics/newton
- Genesis: https://github.com/Genesis-Embodied-AI/genesis-world (Apache-2.0)
- Jolt: https://github.com/jrouwe/JoltPhysics (MIT)
- Bullet: https://github.com/bulletphysics/bullet3 (zlib)
- FluidX3D licence: https://github.com/ProjectPhysX/FluidX3D/blob/master/LICENSE.md
- matter: https://github.com/larsblatny/matter (GPL-3.0)
- Swift Box2D precedents: https://github.com/LuizZak/SwiftBox2D (MIT, v3.0), https://github.com/AchrafKassioui/SpriteKit-Box2D (Apache-2.0)
- SceneKit soft deprecation: https://developer.apple.com/videos/play/wwdc2025/288/
- A17 Pro GPU figures: https://en.wikipedia.org/wiki/Apple_A17 and https://www.cpu-monkey.com/en/igpu-apple_a17_pro_6_gpu_cores (2.15 TFLOPS FP32, 51.2 GB/s; secondary sources)
- Dense suspensions: Baumgarten & Kamrin, PNAS 116(42) 20828 (2019), https://arxiv.org/pdf/1905.09779; microstructural SPH for DST https://arxiv.org/pdf/2311.13759
- Hu et al. 2018 MLS-MPM: https://yzhu.io/publication/mpmmls2018siggraph/paper.pdf
