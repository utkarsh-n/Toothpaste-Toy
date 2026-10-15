# Rheo: PB-MPM on Metal (2D) with rheology extensions, and the 2.5D fluid renderer

Research date: 3 October 2026 (continuation run). Target: Rheo on iPhone 15 Pro Max (A17 Pro, Apple9 GPU, 32 KB threadgroup memory, 1,024 threads per threadgroup) and the iOS 27 simulator (16 KB, 512 threads, `toolchain-checks.md` §1 item 7). Measurements: Apple M1 Max (Apple7, 32-core GPU), macOS 27.2, Metal Toolchain 32023.917, Swift 6.4. The machine ran at a load average of 110–280 from other sessions, so GPU times are medians and can be off by ±50 %.

Tags:

| Tag | Meaning |
|---|---|
| **[V]** | Verified here: compiled, ran, or read at the cited commit and line. |
| **[I]** | Inferred or estimated. Needs a device run or a calibration before it becomes a number in code. |
| **[S]** | From a sibling note in this folder. |

**Where the code is.** `$MC` below is `/private/tmp/claude-501/-Users-utkarsh-Documents-AI-Stuff/b53a2b83-9308-4477-a9dd-fedd258cad75/scratchpad/mpm-metal-check`. Implementers start from **`$MC/pbmpm-metal/`**:

| File | Lines | What |
|---|---|---|
| `PBMPMShared.h` | 239 | Structs shared by Swift and MSL (particle 96 B, constants 176 B, shape 64 B, material 144 B, counters 48 B, stats 32 B). |
| `PBMPM.metal` | 1,044 | The solver: fused `pbG2P2G`, merged binning, reference passes, emitter, telemetry, debug kernels. A derivative of EA's PB-MPM (BSD-3); carries the notice. |
| `LICENSE-PBMPM.md` | 9 | EA's BSD-3 text. It must travel with the two files above. |
| `PBMPMRender.h`, `PBMPMRender.metal` | 57, 278 | The 2.5D renderer (new code). |
| `host/main.swift`, `host/render.swift`, `host/Bridging.h`, `host/build.sh` | 587, 201 | The macOS command-line host that produced every [V] number below. |
| `host/run_all.txt`, `host/run_sweep_*.txt`, `host/run_materials.txt`, `host/render_check.png` | | Logs and the render contact sheet. |

The upstream clones are `$MC/pbmpm/` (`main` 61749b6) and `$MC/pbmpm-sig2024/` (`siggraph2024` 5a2f438). Build and run with `$MC/pbmpm-metal/host/build.sh && $MC/pbmpm-metal/host/pbhost all`.

---

## 0. Summary and decisions

| # | Decision | Evidence |
|---|---|---|
| 1 | **Production path: the fused `g2p2g` with 8×8 bukkit tiles** (upstream `main`), N + 1 passes per substep, plus 2 binning dispatches. The `siggraph2024` passes stay in the same file as a parity reference. | Fused vs reference: 1.5e-5 cells apart after 8 substeps; the fused path is 2.5× cheaper (1.2 against 3.1 ms per frame, 48 against 128 dispatches) [V §1]. |
| 2 | **Keep upstream's bukkit size 6** (64 threads, 3,328 B of threadgroup memory). Size 14 (256 threads, 11,776 B) is no faster. Both fit the simulator and the A17 Pro. | 1.20 against 1.29 ms per frame [V §7]. |
| 3 | **Fixed point 2²⁴ with round-to-nearest** (upstream: 10⁷, truncated), a ±120-unit per-contribution clamp, and an overflow counter at 2³⁰. **Body impulses at 2²⁰**, reduced in float per SIMD-group before conversion. | 0 overflows in every run at Π ≤ 2.4; the grid mass equals the particle mass to 5e-9 [V §8]. |
| 4 | **Exact grid clearing across substeps.** `pbBukkitAllocate` zeroes the grid the last pass read. Upstream's rotation leaves stale sums wherever the active tile set shrinks. | Upstream-style: 1.7e-3 of the mass leaked into the grids; this port: 4.9e-9 [V §2.3]. |
| 5 | **Exact rigid-body impulses in the fused kernel, attributed on the particle side.** Each particle adds −w·m·Δd for the nodes a body collider changed. This sums to exactly Σ m_i·Δd_i over all G2P passes, so no node is counted twice when tiles overlap. | Particle-side and grid-side sums agree to 2e-5 per frame; buoyancy on a submerged box is 0.999× ρgA (fused) and 1.033× (reference) [V §9]. |
| 6 | **Substeps are set by a hydrostatic number Π = g·dt²·H/Δx² ≤ 0.07** (H is the fluid depth), together with the advection CFL and the vibration rule. Iterations stay at N = 3. Π collapses the volume loss across grid resolutions. | Δx 1.10, 1.60 and 1.96 mm all give occupancy 0.975–0.98 at Π ≈ 0.07–0.085 and 0.85–0.90 at Π ≈ 0.19–0.29 [V §12]. |
| 7 | **Budget consequence: Δx ≈ 2 mm by default at 120 Hz** (5,152 particles, 12 × 3 substeps, occupancy 0.975, 0.96 ms per frame on the M1 Max, dispatch-bound). Use Δx ≈ 1.6 mm for a 60 Hz quality mode. At Δx 1.1 mm with 16k particles, real gravity needs 24 substeps (3.7 ms per frame on the M1 Max), roughly 15–22 ms on the A17 Pro [I]. | §12.3 [V on Mac]. |
| 8 | **EVP flow law in parallel (Herschel–Bulkley + solvent) form**, solved per particle by a safeguarded Newton step in γ̇ₚ. The draft's series form let yield-stress materials creep below yield. | Before the fix toothpaste flattened like honey. After it, toothpaste and ketchup stop with residual stress ≈ τ_y, and honey levels [V §11]. |
| 9 | **Renderer: half-resolution MRT splat → 2-pass blur → full-resolution shade**, with refraction of a mipmapped backdrop, Beer–Lambert, wrap subsurface, Schlick Fresnel, GGX and temperature glow into EDR. Normals come from a saturating height, which hides the particle lattice. LabKit's bloom and soft-clip finish the frame. | 0.44–0.65 ms per frame at 1,290 × 2,796 with 16k particles on the M1 Max; a PNG contact sheet was rendered from real snapshots [V §14]. |

---

## 1. What was verified (all on the M1 Max unless stated)

| Check | Result | Where |
|---|---|---|
| `PBMPM.metal` and `PBMPMRender.metal` compile with `TOOLCHAINS=metal xcrun -sdk iphoneos metal -Wall -Wextra` and `-sdk macosx`; `metallib` links | 0 warnings, 0 errors; bukkit sizes 6, 14 and 16 all compile | `host/build.sh` [V] |
| Struct layouts: MSL `sizeof` matches Swift `MemoryLayout.stride` (bridging header) | particle 96, constants 176, shape 64, material 144, counters 48, dispatch slot 16, stats 32, thread data 16 | `pbLayoutProbe`, `host/main.swift:26-41` [V] |
| Dam break, 16,000 particles, 73 × 150 grid, Δx 1.103 mm, real g, 3 s at 120 Hz | No NaN, 0 overflow at S ≥ 4; settles (v_max 0.06–0.14 m/s at 3 s); GPU 1.2 ms per frame at 8 × 3 | `run_all.txt` [V] |
| Mass conservation | Σ grid mass (exact int64) equals Σ particle mass to ≤ 6e-9 relative, every 30 frames, every configuration | `pbGridMass` [V] |
| Determinism | Two runs bitwise identical over 960 substeps for S ∈ {1, 8}, N ∈ {1, 3} (after fixing two port bugs, §2.3) | `pbhost det` [V] |
| Binning | Each live particle is in exactly one list, in its own bukkit; 16,000 of 16,000 covered every frame | `pbhost bins` [V] |
| Fused vs reference (siggraph2024 order) | max \|Δx\| 1.5e-5 cells after 1 frame and 1.7e-4 after 10. The paths then diverge chaotically (a dam break is chaotic) | `pbhost parity` [V] |
| Volume vs substeps (Π sweep, three resolutions) | Occupancy 0.36 (S = 2) → 0.75 (S = 8) → 0.98 (S = 24, N = 3) → 0.99 (S = 32, N = 2) at Δx 1.1 mm | §12 [V] |
| Body impulses | Particle-side = grid-side to ≤ 1.4e-4 per frame; buoyancy 0.999 (fused) and 1.033 (reference) × ρgA at Π = 0.07 | §9 [V] |
| Telemetry (`pbStats`) | Live count and v_max equal the CPU values; mean J to 4 digits; KE within 0.1 % | §13 [V] |
| EVP materials | Honey levels; toothpaste and ketchup stop with residual stress ≈ τ_y; 0 NaN | §11 [V], shapes **not yet calibrated** [I] |
| Renderer | 8 panels rendered from real snapshots; 0.44–0.65 ms per frame at device resolution | §14 [V] |
| On the A17 Pro, and in the simulator | **Not run.** Sizes fit both by construction (§7). SIMD-group functions in the simulator are unverified | [I] |

---

## 2. The port: upstream structure, differences, and bugs found

### 2.1 Upstream at the pinned commits [V]

**`siggraph2024` (readable passes)**, per substep (`pbmpm-sig2024/src/sim.js:129-166`):

1. emit + setIndirectArgs;
2. `iterationCount` × (`particleUpdatePBMPM` → `gridZero` → `particleToGrid` → `gridUpdate` → `gridToParticle`);
3. `particleIntegrate`.

Its demo defaults are 480 Hz, 2 iterations and relaxation 2.0 (`src/ui.js:90-102`).

**`main` (fused)**: `src/sim.js:159-205`:

- Per substep: `iterationCount` × `g2p2g` with triple-buffered grids `current`, `next` and `nextNext`; then emission (`doEmission`, `:128-136`); then `bukkitizeParticles` (`:138-157`: clear buffers, `bukkitCount`, `bukkitAllocate`, `bukkitInsert`).
- Dispatch sizes (`:13-18`): particle group 64, grid group 8, bukkit 6, halo 1.

`shaders/g2p2g.wgsl` (486 lines) does the following:

| Lines | Step |
|---|---|
| 39–126 | Grid load and update (mass division, colliders, guardian) |
| 128–135 | Tile store |
| 146–204 | G2P |
| 207–356 | Integrate, on the last iteration |
| 365–424 | Constraints |
| 426–462 | P2G into the threadgroup tile |
| 465–486 | Flush plus clear of `nextNext` |

Iteration 0 skips G2P. Integration runs at `iteration == iterationCount − 1`, followed by a P2G whose result only feeds the emitter's density check (`particleEmit.wgsl:97-99, 114`). So `main` with N iterations does N − 1 G2P solves.

**Gravity is normalised to the grid**: `displacement.y −= gridSize.y · gravityStrength · dt²` (`g2p2g.wgsl:320`, `particleIntegrate.wgsl:145` on `siggraph2024`). The default is `gravityStrength` 2.5 (`main` `src/ui.js:133`).

### 2.2 Deliberate differences in this port

| Topic | Upstream | This port | Why |
|---|---|---|---|
| Passes per substep | N passes: G2P on 1..N−1, integrate + P2G on the last | N + 1 passes: k = 0 constrain + P2G; 0 < k < N G2P + constrain + P2G; k = N G2P + integrate + count bukkits, **no P2G** | N G2P solves, like `siggraph2024` with N iterations. Saves one P2G. Emission reads grid[N % 3] (the last real P2G) instead. |
| Binning | 3 dispatches after emission (count, allocate, insert) plus 5 buffer clears | Count is fused into pass N (and into `pbEmit`). Allocate clears counts, insert counters and the stale grid, writes the particle dispatch args, and zeroes the other dispatch slot. Then insert. **2 dispatches.** | Dispatch count: N + 3 per substep. |
| Grid clearing | Pass k clears grid[(k + 2) % 3] on the *current* tiles only | Same within a substep, plus allocate zeroes grid[N % 3] everywhere | Fixes the stale sums (§2.3). |
| Source tile | Re-encoded as fixed point (`g2p2g.wgsl:130-133`) | Kept as `float4` in threadgroup memory | No double rounding; same memory. |
| Fixed point | 10⁷, truncation toward zero (`simConstants.inc.wgsl:19-27`) | 2²⁴, `rint`, clamp ±120, overflow counter | Unbiased; headroom analysis in §8. |
| Grid validity | `gridVertex <= gridSize` (`g2p2g.wgsl:50`); reads one past the end, which WebGPU's robust access hides | `< gridSize` | Metal has no robust access by default. |
| Mass division | `if (w < 1e-5) d = 0` and then `d /= w` (`gridUpdate.wgsl:29-37`): 0/0 = NaN at empty nodes, encoded via `i32(NaN)` | Guarded | Defined behaviour. |
| SVD | `atan2(0, 0)` for diagonal input (`matrix.inc.wgsl:26-27`) | `safeAtan2` | Defined behaviour in fast math. |
| Collider position | Node index k (no +0.5) for colliders (`g2p2g.wgsl:43, 87`) | k + 0.5 for colliders (the true node position, matching `offset = cell − p + 0.5`); k for the guardian, as upstream | Removes a half-cell offset at body surfaces. |
| Colliders | Static circle and box, normal-only projection | Circle, capsule and rounded box with velocity, angular velocity and Coulomb friction; impulses summed per shape | Finger tool, Box2D props (§9). |
| Gravity | grid-normalised | `g⃗·dt²/Δx` per substep, any direction | SI (§4). |
| Emission | Particles at `id + (i, j)/ppc + jitter/ppc` (off-centre); displacement 0 | Centred in the cell; displacement = shape velocity | Cell centred. |
| Materials | 4 upstream models | + `PB_MODEL_EVP` (§11) | Rheology. |

### 2.3 Bugs found and fixed in this run (evidence from the host)

1. **Stale grid sums across substeps (upstream behaviour, confirmed by emulation).**
   - **Mechanism.** The grid written by the last P2G of substep s is cleared by a pass of substep s + 1, but only on substep s + 1's tiles. Where a bukkit empties (a fluid front moving, a splash leaving), the sums survive. They are added back when a tile covers those nodes again.
   - **Measurement.** The `stale` mode emulates upstream's global rotation and skips the allocate clear. The sum over the 3 grids then exceeds the particle mass by up to **1.74e-3** relative (6.9 grid units, about 28 particles' worth). With this port's clear, the excess is **4.9e-9** (`run_all.txt`) [V].
   - Upstream partly hides this by recreating its grid buffers every frame (`sim.js:171-180`).
2. **Momentum-only tile nodes were dropped (draft bug; caused non-determinism).**
   - **Mechanism.** The draft flushed a tile node only `if (mass != 0 || volume != 0)`. A node far from a chunk's particles (w ≈ 1e-8) can round its mass to 0 but not its momentum, at |d| of tens of cells. Whether that contribution survived therefore depended on which particles shared a 64-particle chunk, and the insertion order is atomic and so random.
   - **Symptom.** Two identical runs diverged after 4–12 frames (first difference 4e-6 cells, then chaos). Cloning the full buffer state and re-running gave identical results, which pointed at the list order.
   - **Fix.** Flush `if (any(v != 0))` (`PBMPM.metal:753`). Now bitwise identical over 960 substeps [V].
3. **Bukkit index from a float division (preventive).**
   - Upstream computes `vec2i(position / f32(BukkitSize))` (`bukkit.inc.wgsl:12-15`). Under fast math that can become `position * (1/6)`. A particle one ulp below a bukkit edge then lands in the next bukkit, with its stencil one node outside the tile.
   - This port uses `int2(floor(position)) / PB_BUKKIT_SIZE` (`PBMPM.metal:109-110`), which always agrees with the stencil base `floor(p) − 1`.
   - Not shown to fire in a test [I]; it costs nothing.
4. **The flow law was in series form (draft bug).** γ̇ₚ = τ/η₀ + ((τ − τ_y)/k)^(1/n) lets a Bingham material creep at τ/η₀ below yield. Toothpaste (τ_y = 100 Pa) flattened exactly like honey. §11 gives the corrected parallel form [V].
5. **Telemetry KE truncated to 0** (per-particle `uint` conversion of microjoules). It now takes a float SIMD-group sum first, then converts at 10 nJ per unit [V].
6. **Sub-word threadgroup array.**
   - The draft tagged nodes with a `threadgroup uchar` array written by neighbouring threads. An A/B run with every other fix in place showed no corruption, so this was *not* the cause of the early overflow/NaN events, which were the chaotic consequence of bug 2.
   - The port still uses `uint` (+192 B per tile), as a precaution against byte-store hazards on other GPUs [I].

---

## 3. Data layout

### 3.1 Particle (`PBParticle`, 96 bytes, 8-byte aligned; `PBMPMShared.h`)

| Offset | Field | Unit | Written by |
|---|---|---|---|
| 0 | `position` float2 | cells | integrate (pass N), emit |
| 8 | `displacement` float2 | cells per substep (= v·dt/Δx); **includes the next substep's gravity kick** | G2P, integrate |
| 16 | `deformationGradient` float2x2 | F; for EVP the isochoric elastic part Fe (det = 1) | integrate |
| 32 | `deformationDisplacement` float2x2 | B = dt·∇v, dimensionless | G2P |
| 48 | `liquidDensity` | J (volume ratio) | G2P (grid-volume mix), integrate |
| 52 | `mass` | grid units = (ρ/ρ_ref)·V | emit |
| 56 | `volume` | cells² (0.25 at 2 × 2 per cell) | emit |
| 60 | `logJp` | sand hardening (upstream). Reserved on liquid/EVP for an integral pressure term, which **failed** (§12.4) | integrate |
| 64 | `structure` λ | 0..1 (Moore) | integrate |
| 68 | `contact` f | 0..1 (Wyart–Cates) | integrate |
| 72 | `temperature` | K | integrate, emit |
| 76 | `viscosity` | Pa·s, secant τ/γ̇ₚ of the last return map; 1e30 = unyielded | integrate |
| 80 | `stress` | Pa, equivalent shear stress τ̄ | integrate |
| 84 | `shearRate` | 1/s, √((B₀₀ − B₁₁)² + (B₀₁ + B₁₀)²)/dt | integrate |
| 88 | `material` | index into `PBMaterial[16]` | emit |
| 92 | `flags` | bit 0 enabled | integrate (drain), emit |

AoS was kept from upstream: one 96-byte read per particle per pass is coalesced enough on Apple GPUs for 64-particle chunks. SoA is a later optimisation if Metal System Trace shows bandwidth limits [I].

### 3.2 Grids

- **Three grids** of `int4` per node (x momentum, y momentum, mass, volume) in fixed point: `gridSize.x · gridSize.y · 16` bytes each. That is 175 KB each at 73 × 150.
- Node k sits at k + 0.5 in cell coordinates. Lexicographic order: `index = y·gridSize.x + x`.
- Pass k reads grid[k % 3], accumulates into grid[(k + 1) % 3] and clears grid[(k + 2) % 3] (on its tiles). The reference path uses grid 0 only and stores the updated displacement as float bits in components 0–1 (`pbGridUpdate`, `PBMPM.metal:814`).
- Invariant at every substep boundary: **all three grids are zero everywhere.** It is restored by the allocate clear (§2.3).

### 3.3 Bukkits (tiles)

| Buffer | Size | Notes |
|---|---|---|
| `bukkitCounts` | 4 B × bukkits | Filled by pass N and `pbEmit`; read and zeroed by allocate (`atomic_exchange`). |
| `insertCounters` | 4 B × bukkits | Zeroed by allocate, used by insert. |
| `dispatch` | 2 × `PBBukkitDispatch` (16 B: `groupsX`, 1, 1, `particleAllocator`) | Slot s & 1 drives substep s. Allocate writes slot (s + 1) & 1 and zeroes the other slot. The slots alternate because the dispatch that consumes indirect args cannot also reset them. |
| `threadData` | 16 B × (bukkits + capacity / 64 + 1) | Exact upper bound: each bukkit adds ⌈count / 64⌉ ≤ count / 64 + 1 groups. Upstream sizes it as 10 × bukkits (`sim.js:223-227`). |
| `bukkitIndexStart` | 4 B × bukkits | |
| `bukkitParticles` | 4 B × capacity | The per-bukkit particle lists. |
| `counters` (`PBCounters`, 48 B) | | `particleCount`, `freeCount`, overflow, nanResets, clamped, emitted, drained, impulseOverflow, `particleDispatch[3]` (indirect args at offset 32). |
| `freeIndices` | 4 B × capacity | Drain free list (upstream semantics: `freeCount` may go negative transiently). |
| `bodyImpulse` | 32 shapes × 4 × int32 = 512 B | (Jx, Jy, torque, contacts) per shape, per frame. |

At 73 × 150 nodes and bukkit 6 there are 13 × 25 = 325 bukkits. The dam break used 315–340 thread groups per pass.

### 3.4 Uniforms and tables

- `PBSimConstants` (176 B, `setBytes` per dispatch): grid and bukkit counts, dt, Δx, gravity per substep², iteration k and N, shape count, substep index, border friction, maximum displacement, grid-volume flag and mix, capacity, pointer (2 × float4), field and magnet (2 × float4), ambient temperature, thermal time, κ, Hele-Shaw gap, ρ_ref, debug flags, buffer parity, and the (unused) integral-pressure float4.
- `PBShape[32]` (64 B each) and `PBMaterial[16]` (144 B each) are `constant` buffers, rewritten per frame (shapes per substep if they move, §9).

---

## 4. SI units and conversions

Upstream works in "cells" with the gravity normalised to the window. This port keeps cells inside the solver, because the fixed-point ranges and the PB constraint arithmetic are tuned to unit cells and unit masses. **The CPU converts at the boundary with Δx (m per cell), dt (s per substep) and ρ_ref = 1000 kg/m³.**

| Quantity | Solver unit | SI → solver | Solver → SI |
|---|---|---|---|
| Position | cells | x_c = x/Δx + 4 (walls sit G + 1 = 4 cells in) | x = (x_c − 4)·Δx |
| Grid size | nodes | N_x = W/Δx + 9 (guardian 3 + 1 on each side, + 1) | |
| Velocity | cells per substep (`displacement`) | d = v·dt/Δx | v = d·Δx/dt |
| Acceleration (gravity, tilt, shake, vibration, Kelvin force, push) | cells per substep² | a·dt²/Δx | |
| Velocity gradient | B (dimensionless) | B = dt·∇v | ∇v = B/dt; γ̇ = √((B₀₀ − B₁₁)² + (B₀₁ + B₁₀)²)/dt |
| Mass | grid units | m = (ρ/ρ_ref)·V_cells (V = 0.25 at 2 × 2 per cell) | kg per metre of depth = m·ρ_ref·Δx²; multiply by the gap b for kg in the tank |
| Body impulse | grid mass × cells per substep (accumulated × 2²⁰) | | N·s per metre of depth = J·ρ_ref·Δx³/dt |
| Body angular impulse | grid mass × cells² per substep | | N·m·s per metre = τ·ρ_ref·Δx⁴/dt |
| Collider velocity | cells per substep; rad per substep | v·dt/Δx, ω·dt | |
| Stress, moduli, viscosity, temperature, H | Pa, Pa, Pa·s, K, A/m | SI throughout (`PBMaterial`, flow law) | |
| Magnetometer | A/m | H = B/μ₀ (1 µT = 0.7958 A/m) after baseline removal | |

**Example (Δx = 1.103 mm, 24 substeps per 1/120 s, so dt = 0.347 ms)**: g·dt²/Δx = 1.07e-3 cells per substep². A speed of 1 m/s is 0.31 cells per substep. One particle of water is 0.25 grid units, i.e. 0.30 mg per mm of depth.

**Gravity vector.** `c.gravity = g⃗_tank · dt² / Δx`, where g⃗_tank is the Core Motion gravity in the tank frame. It is multiplied by the preset magnitude (Moon 1.62, Earth 9.81, Jupiter 24.79 m/s²) and has the shake (high-passed user acceleration) and the mic vibration added: g⃗_eff(t) = g⃗ + a⃗_shake(t) + A·ω²·sin(ωt)·ŷ_tank, evaluated per substep.

---

## 5. Kernels

### 5.1 Inventory (`$MC/pbmpm-metal/PBMPM.metal`)

| Kernel | Line | Domain, threads per group | Reads → writes | When |
|---|---|---|---|---|
| `pbG2P2G` | 634 | indirect: one group per (bukkit, ≤ 64-particle chunk), 64 threads (`[[max_total_threads_per_threadgroup(PB_TILE_NODES)]]`) | particles, grid src, shapes, materials → grid dst (atomics), grid clear, particles, body impulses, bukkit counts | N + 1 times per substep |
| `pbBukkitAllocate` | 562 | bukkits, 8 × 8 | counts → thread data, dispatch slot, index start, particle dispatch args; zeroes counts, insert counters and grid[N % 3] | once per substep |
| `pbBukkitInsert` | 610 | particles (indirect args at `counters + 32`), 64 | particles → per-bukkit lists | once per substep |
| `pbBukkitCount` | 550 | particles, 64 | → counts | bootstrap only (pass N counts afterwards) |
| `pbEmit` | 896 | grid, 8 × 8 | grid[N % 3].w, shapes → particles, free list, counts | per substep when an emitter is active |
| `pbStats` | 979 | particles (indirect), 64 | → `PBStats` (SIMD-group reductions) | once per frame |
| `pbClearGrid` | 544 | grid, 8 × 8 | → zeros | bootstrap; reference path |
| Reference: `pbParticleConstrain` 773, `pbParticleToGrid` 784, `pbGridUpdate` 814, `pbGridToParticle` 837, `pbParticleIntegrate` 865 | | particles over capacity (early-out) / grid | siggraph2024 order | parity tests |
| Debug: `pbGridMass` 962, `pbBodyImpulseFromGrid` 1029, `pbLayoutProbe` 1020 | | | exact grid mass; grid-side impulse sums; struct sizes | tests |

### 5.2 The fused pass (`PBMPM.metal:626-771`, verbatim)

```metal
// Pass k of a substep (k = 0..N): src = grid[k % 3], dst = grid[(k + 1) % 3], toBeCleared = grid[(k + 2) % 3].
//   k == 0:      constrain + P2G (no G2P; uses the particle's stored displacement and B)
//   0 < k < N:   grid update + G2P + constrain + P2G
//   k == N:      grid update + G2P + integrate + count the particle's new bukkit (no P2G)
[[max_total_threads_per_threadgroup(PB_TILE_NODES)]]
kernel void pbG2P2G(constant PBSimConstants& c [[buffer(0)]],
        device PBParticle* particles [[buffer(1)]],
        device const int4* gridSrc [[buffer(2)]],
        device atomic_int* gridDst [[buffer(3)]],
        device int4* gridToBeCleared [[buffer(4)]],
        device const PBBukkitThreadData* threadData [[buffer(5)]],
        device const uint* bukkitParticles [[buffer(6)]],
        constant PBShape* shapes [[buffer(7)]],
        constant PBMaterial* materials [[buffer(8)]],
        device PBCountersAtomic& counters [[buffer(9)]],
        device uint* freeIndices [[buffer(10)]],
        device atomic_int* bodyImpulse [[buffer(11)]],           // PB_MAX_SHAPES x (Jx, Jy, torque, contacts)
        device atomic_uint* bukkitCounts [[buffer(12)]],
        uint tid [[thread_index_in_threadgroup]],
        uint group [[threadgroup_position_in_grid]]) {
    threadgroup float4 sSrc[PB_TILE_NODES];                 // updated grid displacement.xy, mass, volume
    threadgroup float2 sBodyD[PB_TILE_NODES];               // displacement change made by body colliders
    threadgroup uint   sBodyS[PB_TILE_NODES];               // shape index that made it, PB_NO_SHAPE if none
    threadgroup atomic_int sDst[PB_TILE_NODES * 4];
    threadgroup atomic_int sImp[PB_MAX_SHAPES * 4];

    const bool doG2P = c.iteration > 0;
    const bool doP2G = c.iteration < c.iterationCount;
    const bool doIntegrate = c.iteration == c.iterationCount;

    PBBukkitThreadData td = threadData[group];
    int2 origin = PB_BUKKIT_SIZE * int2(td.bukkitX, td.bukkitY) - PB_BUKKIT_HALO;
    int2 local = int2(int(tid) % PB_TILE_EDGE, int(tid) / PB_TILE_EDGE);
    int2 node = origin + local;
    bool valid = all(node >= int2(0)) && all(node < int2(c.gridSize));     // upstream used <=
    uint gi = valid ? gridIndex(uint2(node), c.gridSize) : 0;

    for (uint k = 0; k < 4; ++k) atomic_store_explicit(&sDst[tid * 4 + k], 0, memory_order_relaxed);
    for (uint k = tid; k < PB_MAX_SHAPES * 4; k += PB_TILE_NODES) atomic_store_explicit(&sImp[k], 0, memory_order_relaxed);
    NodeState ns;
    ns.g = float4(0); ns.bodyDelta = float2(0); ns.bodyShape = PB_NO_SHAPE; ns.nearOverflow = false;
    if (doG2P && valid) {
        ns = gridNodeUpdate(gridSrc[gi], node, c, shapes);
        if (ns.nearOverflow) atomic_fetch_add_explicit(&counters.overflow, 1u, memory_order_relaxed);
    }
    sSrc[tid] = ns.g;
    sBodyD[tid] = ns.bodyDelta;
    sBodyS[tid] = ns.bodyShape;
    threadgroup_barrier(mem_flags::mem_threadgroup);

    BodyAccum body;
    body.shape = PB_NO_SHAPE; body.J = float3(0); body.shape2 = PB_NO_SHAPE; body.J2 = float3(0);

    if (tid < td.rangeCount) {
        uint pi = bukkitParticles[td.rangeStart + tid];
        PBParticle p = particles[pi];
        constant PBMaterial& m = materials[p.material];
        QuadWeights w = quadraticWeightInit(p.position);

        if (doG2P) {
            float2x2 Bsum = float2x2(0);
            float2 d = float2(0);
            float volume = 0.0f;
            for (int i = 0; i < 3; ++i) {
                for (int j = 0; j < 3; ++j) {
                    float weight = w.w[i].x * w.w[j].y;
                    int2 cell = w.base + int2(i, j);
                    int2 l = cell - origin;
                    uint li = uint(l.y * PB_TILE_EDGE + l.x);
                    float4 n = sSrc[li];
                    float2 wd = weight * n.xy;
                    float2 offset = float2(cell) - p.position + 0.5f;
                    Bsum += outer2(wd, offset);
                    d += wd;
                    volume += weight * n.w;
                    uint bs = sBodyS[li];
                    if (bs < PB_MAX_SHAPES) bodyAdd(body, bs, -weight * p.mass * sBodyD[li], float2(cell) + 0.5f - shapes[bs].position);
                }
            }
            g2pFinish(p, Bsum, d, volume, c);
            if (doIntegrate) {
                pbIntegrate(p, pi, m, c, shapes, counters, freeIndices, body, volume);
                particles[pi] = p;
                uint b;
                if ((p.flags & PB_FLAG_ENABLED) && particleBukkit(p.position, c, b))
                    atomic_fetch_add_explicit(&bukkitCounts[b], 1u, memory_order_relaxed);
            } else if (c.useGridVolume != 0) {
                particles[pi].liquidDensity = p.liquidDensity;
            }
        }

        if (doP2G) {
            float2x2 Bc = pbConstrain(p, m, c);
            bool clampedFlag = false;
            for (int i = 0; i < 3; ++i) {
                for (int j = 0; j < 3; ++j) {
                    float weight = w.w[i].x * w.w[j].y;
                    int2 cell = w.base + int2(i, j);
                    int2 l = cell - origin;
                    uint li = uint(l.y * PB_TILE_EDGE + l.x) * 4;
                    float2 offset = float2(cell) - p.position + 0.5f;
                    float wm = weight * p.mass;
                    float2 momentum = wm * (p.displacement + Bc * offset);
                    atomic_fetch_add_explicit(&sDst[li + 0], encodeFixed(momentum.x, clampedFlag), memory_order_relaxed);
                    atomic_fetch_add_explicit(&sDst[li + 1], encodeFixed(momentum.y, clampedFlag), memory_order_relaxed);
                    atomic_fetch_add_explicit(&sDst[li + 2], encodeFixed(wm, clampedFlag), memory_order_relaxed);
                    if (c.useGridVolume != 0)
                        atomic_fetch_add_explicit(&sDst[li + 3], encodeFixed(p.volume * weight, clampedFlag), memory_order_relaxed);
                }
            }
            if (clampedFlag) atomic_fetch_add_explicit(&counters.overflow, 1u, memory_order_relaxed);
        }
    }

    // Body impulses: SIMD-group reduce in float, then threadgroup int atomics (all threads take part: uniform control flow)
    bodyReduceToThreadgroup(body.shape, body.J, sImp);
    bodyReduceToThreadgroup(body.shape2, body.J2, sImp);

    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (valid && doP2G) {
        int4 v = int4(atomic_load_explicit(&sDst[tid * 4 + 0], memory_order_relaxed),
                      atomic_load_explicit(&sDst[tid * 4 + 1], memory_order_relaxed),
                      atomic_load_explicit(&sDst[tid * 4 + 2], memory_order_relaxed),
                      atomic_load_explicit(&sDst[tid * 4 + 3], memory_order_relaxed));
        if (any(v != int4(0))) {             // skip untouched nodes only: a mass sum that rounds to 0 can carry momentum
            atomic_fetch_add_explicit(&gridDst[gi * 4 + 0], v.x, memory_order_relaxed);
            atomic_fetch_add_explicit(&gridDst[gi * 4 + 1], v.y, memory_order_relaxed);
            atomic_fetch_add_explicit(&gridDst[gi * 4 + 2], v.z, memory_order_relaxed);
            atomic_fetch_add_explicit(&gridDst[gi * 4 + 3], v.w, memory_order_relaxed);
        }
    }
    if (valid) gridToBeCleared[gi] = int4(0);
    for (uint k = tid; k < c.shapeCount * 4; k += PB_TILE_NODES) {
        int v = atomic_load_explicit(&sImp[k], memory_order_relaxed);
        if (v != 0) atomic_fetch_add_explicit(&bodyImpulse[k], v, memory_order_relaxed);
    }
}
```

Why the stencil never leaves the tile: a particle binned in bukkit b has floor(p) ∈ [6b, 6b + 5]. So its stencil floor(p) − 1 … floor(p) + 1 lies in [6b − 1, 6b + 6], which is the tile [origin, origin + 7]. Positions do not change between binning and pass N. Integration changes them, but no stencil is read after it in the same substep.

### 5.3 Grid update and colliders (`PBMPM.metal:157-206`, verbatim)

```metal
// Grid-level collider response (upstream g2p2g.wgsl:77-100) in the collider's frame of motion, plus Coulomb friction.
static inline float2 applyCollider(constant PBShape& s, float2 gp, float2 d) {
    float2 u = shapeVelocityAt(s, gp);
    float2 rel = d - u;
    CollideResult r = collide(s, gp + rel);
    if (r.collides) {
        float gap = min(0.0f, dot(r.normal, r.pointOnCollider - gp));
        float pen = dot(r.normal, rel) - gap;
        if (pen > 0.0f) {
            rel -= pen * r.normal;
            float2 t = rel - dot(rel, r.normal) * r.normal;
            float tl = length(t);
            if (tl > 0.0f) rel -= t * min(1.0f, s.friction * pen / tl);
        }
        d = rel + u;
    }
    return d;
}

struct NodeState { float4 g; float2 bodyDelta; uint bodyShape; bool nearOverflow; };
static inline NodeState gridNodeUpdate(int4 raw, int2 node, constant PBSimConstants& c, constant PBShape* shapes) {
    NodeState s;
    s.nearOverflow = any(abs(raw) > int4(PB_NEAR_OVERFLOW));
    float mass = decodeFixed(raw.z);
    float vol = decodeFixed(raw.w);
    float2 d = mass < 1e-5f ? float2(0) : float2(decodeFixed(raw.x), decodeFixed(raw.y)) / mass;
    float2 gp = float2(node) + 0.5f;
    s.bodyDelta = float2(0);
    s.bodyShape = PB_NO_SHAPE;
    if (mass >= 1e-5f) {
        for (uint i = 0; i < c.shapeCount; ++i) {
            if (shapes[i].functionality != PB_FN_COLLIDER) continue;
            float2 after = applyCollider(shapes[i], gp, d);
            if (shapes[i].bodyIndex >= 0 && any(after != d)) { s.bodyDelta += after - d; s.bodyShape = i; }
            d = after;
        }
    }
    // Guardian (upstream main g2p2g.wgsl:102-122: positions without the +0.5, bounds GuardianSize + 1)
    float2 displaced = float2(node) + d;
    float2 diff = projectInsideGuardian(displaced, c.gridSize, float(PB_GUARDIAN + 1)) - displaced;
    if (diff.x != 0.0f) { d.x = 0.0f; d.y = mix(d.y, 0.0f, c.borderFriction); }
    if (diff.y != 0.0f) { d.y = 0.0f; d.x = mix(d.x, 0.0f, c.borderFriction); }
    s.g = float4(d, mass, vol);
    return s;
}
```

`collide()` (`:120-150`) returns signed-distance results for circle, capsule (segment along local x, half length `halfSize.x`) and rounded box (`halfSize` + `radius`), with the normal pointing *into* the collider as upstream. The `gap` term keeps upstream's semantics:

- a node outside the body may not move into it;
- a node already inside is pushed back to the surface.

### 5.4 Binning (`PBMPM.metal:562-622`, verbatim)

```metal
kernel void pbBukkitAllocate(constant PBSimConstants& c [[buffer(0)]],
                             device atomic_uint* bukkitCounts [[buffer(1)]],
                             device atomic_uint* insertCounters [[buffer(2)]],
                             device PBBukkitDispatchAtomic* dispatch [[buffer(3)]],   // 2 slots
                             device PBBukkitThreadData* threadData [[buffer(4)]],
                             device uint* bukkitIndexStart [[buffer(5)]],
                             device PBCountersAtomic& counters [[buffer(6)]],
                             device int4* gridToClear [[buffer(7)]],
                             uint2 id [[thread_position_in_grid]]) {
    device PBBukkitDispatchAtomic& mine = dispatch[c.bufferParity];
    if (all(id == uint2(0))) {
        // The other slot was last used by the previous substep's passes; zero it for the next allocate.
        device PBBukkitDispatchAtomic& other = dispatch[c.bufferParity ^ 1u];
        atomic_store_explicit(&other.groupsX, 0u, memory_order_relaxed);
        atomic_store_explicit(&other.particleAllocator, 0u, memory_order_relaxed);
        other.groupsY = 1; other.groupsZ = 1;
        uint n = min(atomic_load_explicit(&counters.particleCount, memory_order_relaxed), c.particleCapacity);
        counters.particleDispatch[0] = (n + PB_PARTICLE_GROUP - 1) / PB_PARTICLE_GROUP;
        counters.particleDispatch[1] = 1; counters.particleDispatch[2] = 1;
    }
    if (id.x >= c.bukkitCount.x || id.y >= c.bukkitCount.y) return;
    // Clear this bukkit's interior nodes of the grid the last pass read (keeps all three grids zero between substeps).
    if ((c.debugFlags & PB_DEBUG_NO_ALLOC_CLEAR) == 0) {
        for (uint y = 0; y < PB_BUKKIT_SIZE; ++y) {
            for (uint x = 0; x < PB_BUKKIT_SIZE; ++x) {
                uint2 node = id * PB_BUKKIT_SIZE + uint2(x, y);
                if (all(node < c.gridSize)) gridToClear[gridIndex(node, c.gridSize)] = int4(0);
            }
        }
    }
    uint b = id.y * c.bukkitCount.x + id.x;
    atomic_store_explicit(&insertCounters[b], 0u, memory_order_relaxed);
    uint count = atomic_exchange_explicit(&bukkitCounts[b], 0u, memory_order_relaxed);
    if (count == 0) return;
    uint groups = (count + PB_TILE_NODES - 1) / PB_TILE_NODES;
    uint residual = count % PB_TILE_NODES;
    uint dispatchStart = atomic_fetch_add_explicit(&mine.groupsX, groups, memory_order_relaxed);
    uint particleStart = atomic_fetch_add_explicit(&mine.particleAllocator, count, memory_order_relaxed);
    bukkitIndexStart[b] = particleStart;
    for (uint i = 0; i < groups; ++i) {
        PBBukkitThreadData t;
        t.rangeStart = particleStart + i * PB_TILE_NODES;
        t.rangeCount = (residual != 0 && i == groups - 1) ? residual : PB_TILE_NODES;
        t.bukkitX = id.x; t.bukkitY = id.y;
        threadData[dispatchStart + i] = t;
    }
}

kernel void pbBukkitInsert(constant PBSimConstants& c [[buffer(0)]],
                           device PBCountersAtomic& counters [[buffer(1)]],
                           device atomic_uint* insertCounters [[buffer(2)]],
                           device const PBParticle* particles [[buffer(3)]],
                           device uint* bukkitParticles [[buffer(4)]],
                           device const uint* bukkitIndexStart [[buffer(5)]],
                           uint id [[thread_position_in_grid]]) {
    if (id >= atomic_load_explicit(&counters.particleCount, memory_order_relaxed) || id >= c.particleCapacity) return;
    if ((particles[id].flags & PB_FLAG_ENABLED) == 0) return;
    uint b;
    if (!particleBukkit(particles[id].position, c, b)) return;
    uint slot = atomic_fetch_add_explicit(&insertCounters[b], 1u, memory_order_relaxed);
    bukkitParticles[bukkitIndexStart[b] + slot] = id;
}
```

### 5.5 Constraint and integration

- **`pbConstrain`** (`:289-338`) keeps upstream's liquid, elastic, sand and visco constraints line for line (`g2p2g.wgsl:368-424`) and adds the EVP constraint (§11.2). Liquid:
  - viscosity: `B += r·½·(−(B + Bᵀ))`, with r = `viscosityRelax` (0.01);
  - volume: `B += ω·α·I`, with α = ½·(1/J − tr B − 1) and ω = `liquidRelaxation` (1.5).
- **`pbIntegrate`** (`:348-506`), run once per substep in pass N, in this order:
  1. `J ← J·(1 + tr B)` (liquid/EVP), or `F ← (I + B)·F` and the upstream elastic, sand and visco return maps;
  2. the EVP return map and rheology state (§11);
  3. temperature relaxation;
  4. `x ← x + d`;
  5. pointer push/grab;
  6. `d += c.gravity`;
  7. the Kelvin force for MR fluid;
  8. the implicit thin-tank wall drag;
  9. collider push-out (counted as a body impulse) and drains;
  10. the guardian clamp;
  11. the CFL clamp `|d| ≤ maxDisplacement` (counted);
  12. the NaN reset (counted).
- **`g2pFinish`** (`:508-516`): `B = 4·Σ w·d_i ⊗ (x_i − x_p)` (D_p⁻¹ = 4 for quadratic B-splines in cell units). `J ← J + 0.1·(1/V_grid − J)` when 1/V_grid < 1, the upstream grid-volume correction (`gridToParticle.wgsl:71-85`). The survey shows this is the ingredient that keeps volume (`oss-engine-survey.md` §6.1) [S].

---

## 6. Dispatch order

### 6.1 Per substep s (fused path), all in one compute encoder (serial dispatch type)

```
substep s (dt, gravity = g_eff(t_s) dt^2/dx, shapes interpolated to t_s):
  for k in 0...N:                                    // N + 1 dispatches
      pbG2P2G   indirect: dispatch slot (s & 1), 64 threads per group
                buffers: src = grid[k % 3], dst = grid[(k + 1) % 3], clear = grid[(k + 2) % 3]
                k = N also: integrate, drains, count new bukkits, push-out impulses
  [pbEmit]      grid-parallel, reads grid[N % 3].w, counts new particles      (only if an emitter is active)
  pbBukkitAllocate   bufferParity = (s + 1) & 1, gridToClear = grid[N % 3]
  pbBukkitInsert     indirect: counters + 32
per frame, after the last substep:
  pbStats into the frame's shared ring slot; body impulses already summed into the frame's slot
app start (once): zero both dispatch slots and all grids on the CPU; pbBukkitCount -> pbBukkitAllocate(parity 0) -> pbBukkitInsert
```

That is **N + 3 dispatches per substep** (N + 4 with an emitter): 6 at N = 3. Upstream `main` uses N + 5 dispatches plus 5 buffer clears; the reference path uses 5N + 1. At 24 substeps × 6 = 144 dependent dispatches per frame, use a concurrent encoder with explicit `memoryBarrier(scope: .buffers)` between dispatches. The sibling measured 4.4 µs per dispatch that way, against 8–10 µs serial (`oss-integration-lessons.md` §3.10) [S].

### 6.2 Swift encode loop (from `host/main.swift:195-253`, trimmed)

```swift
let dt = frameDt / Float(S)
for s in 0..<S {
    var c = base
    c.dt = dt; c.gravity = gTank * dt * dt / dx; c.iterationCount = UInt32(N); c.substepIndex = globalSub
    let slot = Int(globalSub & 1)
    for k in 0...N {
        c.iteration = UInt32(k)
        e.setComputePipelineState(g2p2g)
        e.setBytes(&c, length: MemoryLayout<PBSimConstants>.stride, index: 0)
        e.setBuffer(particles, offset: 0, index: 1)
        e.setBuffer(grids[k % 3], offset: 0, index: 2); e.setBuffer(grids[(k + 1) % 3], offset: 0, index: 3)
        e.setBuffer(grids[(k + 2) % 3], offset: 0, index: 4)
        e.setBuffer(threadData, offset: 0, index: 5); e.setBuffer(bukkitParticles, offset: 0, index: 6)
        e.setBuffer(shapes, offset: shapeOffset(s), index: 7); e.setBuffer(materials, offset: 0, index: 8)
        e.setBuffer(counters, offset: 0, index: 9); e.setBuffer(freeIndices, offset: 0, index: 10)
        e.setBuffer(bodyImpulse, offset: frameSlot * 512, index: 11); e.setBuffer(bukkitCounts, offset: 0, index: 12)
        e.dispatchThreadgroups(indirectBuffer: dispatch, indirectBufferOffset: slot * 16,
                               threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1))
    }
    if emitting { /* pbEmit over the grid with grids[N % 3] */ }
    var ca = base; ca.bufferParity = (globalSub + 1) & 1
    // pbBukkitAllocate over bukkitCount (8 x 8 groups) with gridToClear = grids[N % 3]
    // pbBukkitInsert with dispatchThreadgroups(indirectBuffer: counters, indirectBufferOffset: 32, 64 threads)
    globalSub += 1
}
```

---

## 7. Threadgroup sizing (A17 Pro and simulator)

| Bukkit size | Tile (threads) | `staticThreadgroupMemoryLength` | Simulator (≤ 512 threads, ≤ 16 KB) | A17 Pro (≤ 1,024, ≤ 32 KB) | M1 Max GPU time, dam break 8 × 3 |
|---|---|---|---|---|---|
| **6 (default, upstream)** | 8 × 8 = 64 | **3,328 B** [V] | fits | fits | **1.20 ms per frame** [V] |
| 14 | 16 × 16 = 256 | 11,776 B [V] | fits | fits | 1.29 ms per frame [V] |
| 16 | 18 × 18 = 324 | ≈ 14.8 KB (scales as 41 B × tile + 512 B) [I] | fits (largest) | fits | not timed |
| 20 | 484 | ≈ 20 KB [I] | **no** (16 KB) | fits | — |

Breakdown per tile node: 16 B source (`float4`) + 8 B body Δd + 4 B body tag + 16 B destination atomics, plus 512 B of per-shape impulse accumulators. Particle-parallel kernels use 64 threads; grid and bukkit kernels use 8 × 8.

Rules:

- Size threadgroups from `PB_TILE_NODES`, never from `maxTotalThreadsPerThreadgroup`. The attribute `[[max_total_threads_per_threadgroup(PB_TILE_NODES)]]` reports it back (64 or 256) [V].
- Size 6 wastes the most halo (64 nodes for 36 interior, 1.78×), but its chunks of ≤ 64 particles keep thread use high. The halo saving at 14 (1.31×) did not pay off [V].
- SIMD-group functions (`simd_sum`, `simd_max`, `simd_any`, `simd_broadcast_first`, `simd_is_first`) appear in the impulse reduction, `pbStats` and `pbGridMass`. They are verified on the M1 Max (Apple7) and are supported on Apple9 (A17 Pro) per the feature tables [I].
  - The **simulator reports only Apple2/Common1 families**, so they are unverified there.
  - Before shipping, run one `pbStats` dispatch in the simulator.
  - If it fails, swap `bodyReduceToThreadgroup` for direct threadgroup atomics (contributions still sum correctly, with more rounding) [I].

---

## 8. Fixed point: scale choice and overflow analysis

**Grid sums (`PB_FIXED_SCALE` = 2²⁴, clamp ±120 per contribution, overflow counter at |sum| > 2³⁰).**

- int32 holds ±2³¹/2²⁴ = **±128 grid units per node component**.
- Node mass ≤ Σ w·m ≈ (ρ/ρ_ref)/J. The densest preset is MR fluid at ρ ≈ 3,100 kg/m³ [I], and the worst compression seen at S ≥ 4 is J ≈ 0.3 (sweep minimum), so mass ≤ 3.1/0.3 ≈ 10 units.
- Momentum ≤ mass × (|d| + 1.5·|B|) with |d| ≤ `maxDisplacement` = 2 cells per substep: ≤ 10 × 3 = 30 units. That is **4.3× headroom** to 128.
- The overflow counter trips at 64 units, so overflow is flagged at 2× the worst expected load.
- Volume ≤ 1/J ≈ 3.3 units.
- **Resolution**: 2⁻²⁴ = 6e-8. The smallest physically relevant increment is the gravity kick per substep, g·dt²/Δx = 1.07e-3 cells at Δx 1.1 mm and S = 24. Weighted by w·m ≈ 0.025 that is 2.7e-5 units = **450 LSB**. Rounding is unbiased (`rint`).
- Upstream's 10⁷ truncation has 2.1× more range but biases every contribution toward zero.

**Measured [V]**:

- 0 overflow events at every S ≥ 4, including the water splash with 2 m/s peaks.
- At S = 2 (Π = 9.6, far outside the valid range) there were 185 events and 382k CFL clamps, so the counters do flag a bad configuration.
- Mass: Σ grid mass equals Σ particle mass to ≤ 6e-9 relative. That is the per-contribution rounding: 9 contributions of ±0.5 LSB per particle.

**Body impulses (`PB_IMPULSE_SCALE` = 2²⁰).**

- **Range.** The per-frame sum per shape (all passes, all substeps) is ±2048 grid momentum units.
- **Typical loads.** A submerged 22 × 11 mm box gets 2.39 N/m buoyancy, which is about 5.2 units per frame at Δx 1.1 mm and S = 24. A 0.2 kg/m prop stopped from 1 m/s is about 52 units.
- **Rounding.** Contributions are summed in float across a SIMD-group (≤ 32 particles) before conversion. A single-particle hydrostatic contribution (≈ 3e-5 units) would round to ±31 LSB alone; summed first, the rounding error is negligible.
- **Clamping.** Each SIMD-group's sum is clamped to ±2000 units before conversion.
- **Gap.** `impulseOverflow` is declared but **not yet incremented**: add it in `bodyReduceToThreadgroup` when a clamp fires [I].

**Budget for Δx changes**: unit masses (ρ/ρ_ref per cell) and displacements in cells are independent of Δx. The analysis above holds at any resolution, provided substeps follow §12, which keeps |d| < 1 cell.

---

## 9. Colliders and rigid-body coupling

### 9.1 Tank walls

- The **guardian band** (upstream) is the tank:
  - nodes whose displaced position leaves [G + 1, N − G − 2] (G = 3) lose the normal component;
  - the tangential component is scaled by 1 − `borderFriction` (0 = slip, 1 = no slip; upstream default 0.5, `main` `ui.js:146`);
  - particles are clamped to [G, N − G − 1] after integration.
- Interior walls and obstacles are static `PBShape` colliders with `bodyIndex = −1`.
- The thin-tank walls (front and back glass) are the implicit wall drag of §11.4, not colliders.

### 9.2 Kinematic finger capsule (poke, punch, stir)

One `PBShape` per active touch:

| Field | Value |
|---|---|
| `shapeType` | `PB_SHAPE_CAPSULE` |
| `position` | Per substep: lerp(touch_prev, touch_now, (s + ½)/S), in cells |
| `rotation` | atan2 of the touch motion |
| `halfSize.x` | 0 for a round fingertip. ½·\|motion per substep\| for a swept capsule on fast punches, so the tool cannot tunnel through a thin sheet. |
| `radius` | Fingertip radius, 4–6 mm, in cells |
| `velocity` | (touch_now − touch_prev)/frameDt · dt/Δx (cells per substep) |
| `angularVelocity` | 0 |
| `friction` | 0.3–0.6 (μ) |
| `bodyIndex` | 0..k, so the fluid's reaction on the finger is summed |

- **Poke.** Grow `radius` from 0 over about 30 ms, so the tool does not appear inside the fluid at full size. Otherwise every node inside is projected out in one substep.
- **Punch.** Large `velocity`, which is what jams oobleck (§11).
- **Stir.** A circular touch path.
- **Haptics.** The finger's summed impulse per frame ÷ frameDt is the reaction force, in N per metre of depth (× gap for N). Map it to haptic intensity through LabKit's haptic vocabulary (`labkit-from-orbitals-spectra.md` §5).

### 9.3 Box2D bodies (footprints with integer impulse sums)

Per frame, each Box2D shape that touches the tank becomes one `PBShape` with `functionality = PB_FN_COLLIDER`, `bodyIndex = Box2D body slot`:

| Box2D v3.1.1 shape | `PBShape` |
|---|---|
| `b2_circleShape` | `PB_SHAPE_CIRCLE`, `radius` |
| `b2_capsuleShape` | `PB_SHAPE_CAPSULE`: midpoint, segment angle, half length, `radius` |
| `b2_polygonShape` that is a box (`b2MakeBox` / `b2MakeRoundedBox`) | `PB_SHAPE_BOX`: centre, angle, half extents, `radius` = polygon radius |
| other convex polygons | their oriented bounding box, or several boxes [I] |

- **Pose and velocity.**
  - `position` = the body transform applied to the shape centre; `rotation` = atan2(q.s, q.c).
  - `velocity` = (v_com + ω × (c_shape − c_com))·dt/Δx; `angularVelocity` = ω·dt.
  - Box2D steps once per 1/120 s frame (4 internal substeps, `oss-engine-survey.md` §7.4). Inside the frame, the MPM substeps extrapolate each shape linearly from the start-of-frame pose. Write a `PBShape[32]` block per substep, and bind it with a buffer offset.
- **Fluid → body.**
  - `bodyImpulse[shape]` holds the impulse **on the body** for the whole frame: (Jx, Jy, τ about `shape.position`, contact count) × 2²⁰, in grid units.
  - Convert to SI: J = Jgrid·ρ_ref·Δx³/dt and L = τgrid·ρ_ref·Δx⁴/dt, per metre of depth. Treat Box2D's 2D world as per metre of depth, so a body of density ρ_b (kg/m³) gets Box2D density ρ_b. The fluid and the body then share units.
  - Apply at the next frame with `b2Body_ApplyLinearImpulse(body, J, c_shape, true)` and `b2Body_ApplyAngularImpulse(body, L + (c_shape − c_com) × J, true)`, summed over the body's shapes.
  - Kinematic bodies (the finger) ignore impulses; their sums are read for haptics only.
- **Why particle-side attribution.**
  - Each pass k ≥ 1 projects every node it loads. A node lies in up to 4 tiles' halos, and in several chunks of one bukkit, so a grid-side sum inside the fused kernel would double count.
  - Instead, the grid stage records, per tile node, the displacement change Δd_i made by body colliders and the shape that made it (`sBodyD`, `sBodyS`).
  - Each particle then adds −w_ip·m_p·Δd_i in G2P. Summed over all particles, this gives −Σ_i Δd_i·Σ_p w_ip·m_p = −Σ_i m_i·Δd_i exactly. Every particle is G2P'd exactly once per pass, and m_i is the P2G of the same particles at the same positions.
  - Over the passes of a substep, the total equals the fluid's momentum change due to that body: the constraints change only B, and Σ_i w_ip·(x_i − x_p) = 0 for B-splines, so P2G conserves momentum.
  - The particle push-out in integrate (`PBMPM.metal:470-476`) is added on the particle side too.
  - SIMD-group float reduction (`bodyReduceToThreadgroup`, `:518-541`) → threadgroup int atomics → one device atomic per shape per group.
- **Verification [V]** (`pbhost box`):
  - Setup: water pool 64 × 70 cells; static box 20 × 10 cells at mid-depth with `bodyIndex 0`; wall drag b = 5 mm and η 0.05 Pa·s to damp sloshing; mean over t = 2–4 s.

| Check | Result |
|---|---|
| Particle-side sums vs `pbBodyImpulseFromGrid` on the same grids (push-out excluded) | Equal to ≤ 1.4e-4 per frame (fixed-point rounding) |
| Buoyancy, S = 24 (Π = 0.07, J = 0.95) | 2.386 N/m (fused) and 2.467 N/m (reference) against ρgA = 2.388 N/m: **0.999 and 1.033** |
| Fx, torque | ≈ 0 (0.012 N/m, 1.8e-4 N) |
| Buoyancy, S = 8 (J = 0.80, compressed) | 1.08–1.15 |
| Undamped pool | F_y swings 0.64–1.44× ρgA on 0.25 s windows: PB liquids slosh with little damping |

The compressed result is consistent with a denser fluid.

**Limits.**

- A node changed by two body shapes is attributed to the last one.
- A particle touching a third body shape drops that share (never seen in tests).
- The coupling has a one-frame lag. Clamp the per-frame impulse for very light props in jammed fluid (survey risk 5) [I].

---

## 10. Emitters, drains and the pointer

- **Emitter** (`pbEmit`, `PBMPM.metal:896-958`; upstream `particleEmit.wgsl:86-148`).
  - Any shape with `PB_FN_EMIT`. Each grid cell inside it holds a 2 × 2 set of slots. A slot emits when `(hash(slot) + substepIndex) % emitEvery == 0`, with emitEvery = max(1, ⌊1/(rate·dt)⌋). The hash staggers neighbouring slots.
  - Volume flux is (cells in shape) × Δx² × rate / 4 per slot. For a pour at speed v, choose rate ≈ 2v/Δx, so successive particles are Δx/2 apart (v = 0.3 m/s at Δx = 2 mm gives 300 Hz).
  - Emitted particles take `displacement = shape.velocity`, J = 1, λ = 1, T = ambient, η = 1e30 (unyielded).
  - Emission is skipped where grid[N % 3].w > 1.5, i.e. where the fluid is already compressed (upstream e0536f8).
  - Slots come from the free list first, then from `particleCount` up to capacity. Past capacity, emission stops and `particleCount` is rolled back.
- **Drain** (`PB_FN_DRAIN`): particles inside are disabled in integrate and pushed onto the free list (upstream `particleIntegrate.wgsl:165-176`).
- **`PB_FN_INITIAL`** fills a shape at substep 0. Scene presets should instead seed particles from the CPU, as the host does (`particlesIn`, `host/main.swift`).
- **Pointer**: the "magic hand" tools; the physical finger is §9.2 (upstream `g2p2g.wgsl:299-317`).
  - *Push*: particles within `pointer.z` cells get `d += r̂ · pointerMotion.z` each substep. That is an acceleration: `pointerMotion.z = a_push·dt²/Δx`, with a_push ≈ 20–50 m/s².
  - *Grab*: `d ← mix(d, v_finger·dt/Δx, blend)`. Upstream `main` uses blend = 1; `siggraph2024` uses 0.7·v (`particleIntegrate.wgsl:139`).

---

## 11. Rheology inside PB-MPM

### 11.1 Where the state lives and when it changes

| State | Storage | Updated | Read |
|---|---|---|---|
| Elastic part Fe (isochoric) | `deformationGradient` | Return map, once per substep (pass N) | EVP shape constraint, every pass |
| Volume J | `liquidDensity` | Integrate: J·(1 + tr B); every G2P: grid-volume mix | Volume constraint, every pass |
| Secant viscosity η = τ/γ̇ₚ | `viscosity` | Return map | Shape-constraint weight (Maxwell secant modulus), next substep |
| Stress τ̄, shear rate γ̇ | `stress`, `shearRate` | Integrate | Telemetry, diagnostics, Wyart–Cates |
| Structure λ (thixotropy) | `structure` | Integrate (backward Euler) | Flow law (τ_y, k) |
| Contact fraction f (Wyart–Cates) | `contact` | Integrate (relaxation toward f_eq(τ)) | Flow law (jammed or not, η divergence) |
| Temperature T | `temperature` | Integrate (relaxation to ambient with `thermalTime`); emitters set it | Arrhenius aT; lava glow |
| Local field H | not stored | Computed per particle from `field` (magnetometer) + `magnet` (virtual dipole) | MR yield, Kelvin force |

Everything is per particle and updated in one place (`pbIntegrate`, pass N). Constraints read it in every pass. Within a substep the rheology is frozen across iterations; this is the operator split.

### 11.2 EVP constraint (`PBMPM.metal:278-288, 324-336`)

```metal
// XPBD-style weight of the EVP shape constraint: series Maxwell stiffness against the grid's inertial stiffness.
static inline float evpShapeRelaxation(thread const PBParticle& p, constant PBMaterial& m, constant PBSimConstants& c) {
    float G = m.shearModulus;
    if (G <= 0.0f) return 0.0f;
    float eta = p.viscosity;                                   // secant viscosity from the last return map
    float Geff = G * eta / (eta + G * c.dt);
    float Gref = c.kappaElastic * m.density * c.dx * c.dx / (c.dt * c.dt);
    return m.elasticRelaxation * Geff / (Geff + Gref);
}
...
    } else {   // PB_MODEL_EVP
        float2x2 S = 0.5f * (B + transpose(B));
        B -= m.viscosityRelax * (S - 0.5f * tr2(S) * kIdentity);          // numerical viscosity, deviatoric only
        float rE = evpShapeRelaxation(p, m, c);
        if (rE > 1e-3f) {
            float2x2 Fe = p.deformationGradient;
            SVDResult s = svd2((kIdentity + B) * Fe);
            float2x2 diff = (s.U * s.Vt) * inverse2(Fe) - kIdentity - B;   // drive Fe toward its rotation
            diff -= 0.5f * tr2(diff) * kIdentity;                            // shape only; volume is the next constraint
            B += rE * diff;
        }
        float alpha = 0.5f * (1.0f / p.liquidDensity + p.logJp - tr2(B) - 1.0f);
        B += m.liquidRelaxation * alpha * kIdentity;
    }
```

- **Meaning.** The shape constraint pulls (I + B)·Fe toward its rotation, as upstream's elastic material does (`g2p2g.wgsl:382-398`), but only in its deviatoric part. Its weight is the series Maxwell secant modulus G_eff = G·η/(η + G·dt) over a substep, compared with the inertial stiffness of a cell, G_ref = κ·ρ·Δx²/dt² (Pa). XPBD gives the same form, with compliance α̃ = 1/(k·dt²) (Macklin et al. 2016).
- **Behaviour.** Unyielded material (η → ∞) holds its shape like an elastic solid of modulus G. Flowing material (small η) barely resists.
- **κ is not calibrated** [I]. At Δx 1.1 mm and S = 8, G_ref ≈ 1.1–1.5 kPa for κ = 1. Whether the apparent modulus is invariant under S changes is untested; G_ref scales as 1/dt², so it should be.
- **Calibration plan**: a bouncing putty ball's rebound period and a cantilever's sag against the CPU explicit oracle with G softened to the same c, across S = 8, 16, 24 (`oss-engine-survey.md` §7.6 items 4–5) [I].

### 11.3 Flow law and return map (`PBMPM.metal:205-277`, verbatim core)

```metal
// Flow law, parallel (Herschel-Bulkley + solvent) form, one set of parameters per state:
//   tau = tauY + k gammaDotP^n + eta gammaDotP   for tau > tauY;   gammaDotP = 0 below yield.
// Jammed Wyart-Cates states switch to a Bingham "failure" branch: tauY = tau_f, eta = 1 / phi_f, k = 0.
struct FlowLaw { float tauY; float k; float n; float eta; bool jammed; };

static inline FlowLaw flowLaw(constant PBMaterial& m, thread const PBParticle& p, float H) {
    FlowLaw f;
    float aT = m.eaOverR > 0.0f ? exp(m.eaOverR * (1.0f / max(p.temperature, 150.0f) - 1.0f / m.refTemperature)) : 1.0f;
    float lam = p.structure;
    f.tauY = m.yieldStress * (1.0f - m.thixoYield + m.thixoYield * lam);                       // Moore-type structure
    if (m.mrYieldSat > 0.0f) f.tauY += m.mrYieldSat * tanh(m.mrHScale * max(H - m.mrDeadZone, 0.0f));   // MR
    f.k = m.consistency * aT * (1.0f + m.thixoConsistency * pow(lam, m.thixoExponent));
    f.n = clamp(m.flowIndex, 0.05f, 1.0f);
    f.eta = m.eta0 * aT;
    f.jammed = false;
    if (m.phi > 0.0f) {                                             // Wyart-Cates: phi_J(f) = f phi_m + (1 - f) phi_0
        float phiJ = p.contact * m.phiM + (1.0f - p.contact) * m.phi0;
        if (m.phi >= phiJ) {
            f.jammed = true;
            f.tauY = max(f.tauY, m.failureStress > 0.0f ? m.failureStress : 1e9f);
            f.k = 0.0f;
            f.eta = m.failureFluidity > 0.0f ? 1.0f / m.failureFluidity : 1e7f;
        } else {
            float x = 1.0f - m.phi / phiJ;
            f.eta = min(f.eta / (x * x), 1e7f);                      // Krieger-type divergence toward phi_J
        }
    }
    return f;
}
// Backward-Euler Maxwell / Herschel-Bulkley return map. Unknown x = gammaDotP (1/s):
//   tauY + k x^n + (eta + G dt) x = tauTrial,  tau = tauTrial - G dt x.
// The left side is monotone in x, so the root is bracketed by [0, (tauTrial - tauY) / (eta + G dt)]; safeguarded Newton.
static inline float returnMap(FlowLaw f, float tauTr, float Gdt, thread float& gdp) {
    gdp = 0.0f;
    if (tauTr <= f.tauY) return tauTr;                                       // below yield: purely elastic
    float excess = tauTr - f.tauY;
    float a = f.eta + Gdt;
    float lo = 0.0f, hi = excess / a;
    if (f.k <= 0.0f) { gdp = hi; return tauTr - Gdt * gdp; }                 // Bingham / Newtonian: closed form
    float x = min(hi, pow(excess / f.k, 1.0f / f.n));                         // power-law-only estimate
    for (int i = 0; i < 24; ++i) {
        float xn = pow(max(x, 1e-30f), f.n);
        float g = f.k * xn + a * x - excess;
        if (g > 0.0f) hi = x; else lo = x;
        float dg = f.k * f.n * xn / max(x, 1e-30f) + a;
        float xNew = x - g / dg;
        if (!(xNew > lo && xNew < hi)) xNew = 0.5f * (lo + hi);              // bisection fallback (also catches NaN)
        bool done = fabs(xNew - x) <= 1e-6f * x + 1e-12f;
        x = xNew;
        if (done) break;
    }
    gdp = x;
    return max(tauTr - Gdt * x, f.tauY);
}
```

In integrate (`:404-416`):

- Take the SVD of the trial Fe_tr = (I + B)·Fe, with singular values clamped to [0.1, 10⁴].
- The Hencky deviatoric principal strain is ε = ½·(ln σ₁ − ln σ₂), and the trial equivalent shear stress is τ_tr = 2G·ε.
- `returnMap` gives τ and γ̇ₚ. Then ε_new = ε·τ/τ_tr, Fe = U·diag(e^ε_new, e^−ε_new)·Vᵀ (det 1), η = τ/γ̇ₚ (1e30 below yield), and `stress` = τ.
- For G = 0 (no elastic memory) the code evaluates τ = flowStress(γ̇) as a diagnostic only. **A yield stress needs G > 0 to hold a plug**: with G = 0 the yield stress acts only through the wall drag.

### 11.4 State updates and body forces (`PBMPM.metal:417-469`)

- **Thixotropy (Moore 1959).** dλ/dt = a·(1 − λ) − b·γ̇ₚ·λ, solved by backward Euler: λ ← (λ + a·dt)/(1 + a·dt + b·γ̇ₚ·dt). Then τ_y = τ_y0·(1 − c + c·λ) and k = k₀·aT·(1 + β·λ^m).
- **Wyart–Cates.** f_eq = 1 − exp(−τ/σ*), with f relaxing at rate γ̇·dt/γ* + dt/t_unjam. φ_J = f·φ_m + (1 − f)·φ_0. Jammed when φ ≥ φ_J. Otherwise η = η₀·aT/(1 − φ/φ_J)², capped at 10⁷ Pa·s.
- **Arrhenius.** aT = exp[(E_a/R)·(1/T − 1/T_ref)]. Temperature relaxes toward ambient with `thermalTime` (s).
- **MR fluid.**
  - τ_y += τ_sat·tanh(c_H·max(\|H\| − H_dead, 0)), the saturating form after Carlson's MRF-132DG curves; parameters in `rheology-models.md` §3.8 [S].
  - Kelvin body force a = μ₀·χ·H·∇H/ρ, clamped at 5 g.
  - H = \|H_magnetometer\| + H₀·(r₀/r)³ for the virtual magnet, with ∇H = −3·H_m/r·r̂ pointing toward it.
- **Thin-tank (Hele-Shaw) wall drag**, implicit per substep:
  - d ← d/(1 + dt·12·η_w/(ρ·b²)), with γ̇_w = 6·\|v\|/b (wall shear rate of plane Poiseuille flow). For EVP materials η_w = τ_flow(γ̇_w)/γ̇_w, with the yield part scaled by `wallYieldFactor` (wall slip); for liquids η_w = η₀.
  - For a yield-stress fluid this gives a Coulomb-like deceleration of 2·τ_y/(ρ·b) that stops without reversing. That is real thin-cell physics: toothpaste (τ_y = 100 Pa) does not slide under gravity in a 10 mm cell.
  - Expose b and `wallYieldFactor` per preset as tuning constants, not knobs (survey §6.4) [S].

### 11.5 Material runs [V] (`run_materials.txt`)

Setup: dam break of a 44 × 66 mm column in the 70.6 mm tank, S = 8, N = 3, κ = 1, 3 s, 9,600 particles, 0 NaN, 0 overflow.

| Preset (G, η₀, τ_y, k, n) | Peak v | At 3 s | Surface at 10/30/50/70/90 % of the width | Residual τ̄ max | Particles still yielding |
|---|---|---|---|---|---|
| Honey (10 kPa, 10 Pa·s, 0, 0, 1) | 0.15 m/s | v 0.003 m/s (at rest) | 34/34/34/34/34 mm (level) | 50 Pa (noise) | all (Newtonian) |
| Toothpaste (3 kPa, 0.1, 100 Pa, 20, 0.4) | 0.08 m/s | KE 6e-10 J/m (stopped) | 33/33/33/34/39 mm | **108.5 Pa ≈ τ_y** | 41 % |
| Ketchup (1 kPa, 0.05, 15 Pa, 6, 0.35) | 0.36 m/s | KE 6e-10 J/m (stopped) | 34/34/34/35/35 mm | **22.9 Pa ≈ 1.5 τ_y** | 57 % |

- **Qualitatively right.** The yield-stress fluids stop dead with stress at the yield surface, and the Newtonian one levels.
- **Not quantitatively right yet** [I].
  - A quasi-static Bingham slump into a 70 mm tank should leave toothpaste sloping from about 49 mm at the back wall to about 35 mm at the front: h₀² − h₁² = 2τ_y·L/(ρg).
  - The run instead froze a 6 mm bump at the far wall, where the front ran up.
  - Likely causes: inertia of the PB dam break; the 18 % hydrostatic compression at S = 8; the uncalibrated κ; and plane strain against depth-averaged yield.
- **Next steps.** The inclined-layer stoppage test (h_c = τ_y/(ρ·g·sin θ)) and the flow-curve strip (`oss-engine-survey.md` §7.6 items 5–6), against the CPU oracle, decide κ and any per-model corrections.
- **Earlier failure.** Before the flow-law fix (§2.3 item 4), all three ended level at 34 mm.

---

## 12. Substeps, iterations and the adaptive rule

### 12.1 Why real gravity costs substeps

PB-MPM's volume constraint drives tr B toward 1/J − 1. It generates "pressure" only from compression error. In a resting column, each substep's gravity kick (g·dt²/Δx per particle) must be cancelled by constraint pushes that grow with the weight above, so the steady error grows with depth. Dimensional analysis and the data both give

  **1 − J ≈ f(Π, N), with Π = g·dt²·H/Δx²**

where H is the fluid depth (m). Π is the depth in cells times the gravity kick in cells. Upstream's demo hides this: gravity of 2.5 domain heights/s² at 240 Hz in a 135-cell window gives Π ≈ 0.26 for a third-full window (§2.1). Real g in a 70 mm pool at Δx 1.1 mm and 2 substeps per 120 Hz frame gives Π = 9.6.

### 12.2 Measurements [V] (water dam break settling to a 69 mm pool, 3 s, three resolutions; logs `host/run_sweep_*.txt`)

| Δx (interior cells) | S × N per 1/120 s | Π | Occupancy at 3 s | Mean J | v_max at 3 s | GPU ms per frame (M1 Max) | Particles |
|---|---|---|---|---|---|---|---|
| 1.10 mm (64) | 2 × 3 | 9.65 | 0.36 | 1.15 (broken) | 0.57 | 0.34 | 16,000 |
| 1.10 mm | 4 × 3 | 2.41 | 0.53 | 0.53 | 0.10 | 0.67 | 16,000 |
| 1.10 mm | 8 × 2 | 0.60 | 0.70 | 0.70 | 0.14 | 0.94 | 16,000 |
| 1.10 mm | 8 × 3 | 0.60 | 0.75 | 0.75 | 0.11 | 1.21 | 16,000 |
| 1.10 mm | 8 × 5 / 8 × 8 | 0.60 | 0.83 / 0.88 | 0.82 / 0.87 | 0.13 / 0.06 | 1.53 / 2.22 | 16,000 |
| 1.10 mm | 12 × 3 | 0.27 | 0.86 | 0.85 | 0.08 | 1.81 | 16,000 |
| 1.10 mm | 16 × 2 | 0.15 | 0.88 | 0.87 | 0.16 | 1.87 | 16,000 |
| 1.10 mm | 16 × 3 | 0.15 | 0.92 | 0.90 | 0.06 | 2.46 | 16,000 |
| 1.10 mm | 24 × 2 | 0.067 | 0.95 | 0.93 | 0.05 | 2.86 | 16,000 |
| **1.10 mm** | **24 × 3** | **0.067** | **0.98** | **0.95** | **0.03** | **3.74** | 16,000 |
| 1.10 mm | 32 × 2 | 0.038 | 0.99 | 0.96 | 0.06 | 4.36 | 16,000 |
| 1.60 mm (44) | 4 × 3 | 1.14 | 0.66 | 0.67 | 0.06 | 0.51 | 7,728 |
| 1.60 mm | 8 × 3 | 0.29 | 0.85 | 0.84 | 0.06 | 0.86 | 7,728 |
| 1.60 mm | 12 × 3 | 0.13 | 0.93 | 0.92 | 0.05 | 1.16 | 7,728 |
| **1.60 mm** | **16 × 3** | **0.071** | **0.98** | **0.95** | **0.03** | **1.47** | 7,728 |
| 1.60 mm | 24 × 2 | 0.032 | 1.00 | 0.96 | 0.05 | 1.92 | 7,728 |
| 1.96 mm (36) | 8 × 3 | 0.19 | 0.90 | 0.89 | 0.02 | 0.65 | 5,152 |
| **1.96 mm** | **12 × 3** | **0.085** | **0.975** | **0.94** | **0.02** | **0.96** | 5,152 |
| 1.96 mm | 16 × 3 | 0.048 | 1.01 | 0.96 | 0.01 | 1.28 | 5,152 |

"Occupancy" is the number of cells holding a particle divided by the initial count (the survey's metric). Mean J is what the solver believes. All three resolutions give 0.975–0.98 at Π ≈ 0.07–0.085 (N = 3) and 0.85–0.90 at Π ≈ 0.19–0.29, so **Π, not Δx or S on their own, sets the volume error**. Iterations help less than substeps: 8 × 8 (64 passes) reaches 0.88, against 24 × 2 (72 passes) at 0.95. This agrees with the survey's CPU result of 12–16 substeps for a 28 mm pool (`oss-engine-survey.md` §6.1) [S].

### 12.3 The rule

Per frame (simulated time T_f = frameDt × timeScale):

```
H      = fluid depth from last frame's telemetry (m)   // max column height; pbStats can add it, or use area / tank width
g_eff  = |g_preset| + |a_shake| + A·ω²                  // peak magnitudes this frame
v_max  = last frame's max speed × 1.25
S_hyd  = ceil(T_f · sqrt(g_eff · H / (Π_max · Δx²)))   // Π_max = 0.07 (≤ 5 % loss, N = 3); 0.15 for a ≤ 10 % "toy" mode
S_adv  = ceil(T_f · v_max / (1.0 · Δx))                 // ≤ 1 cell per substep
S_vib  = ceil(8 · f_drive · T_f)                        // ≥ 8 substeps per vibration period
S      = clamp(max(S_hyd, S_adv, S_vib, 2), 2, S_max)
N      = 3 (2 in the low-power mode)
if the max would exceed S_max:  S = S_max and dilate time (simulate S_max · dt_needed < T_f), as the sibling governor does
                                (`SubstepGovernor`, `$MC/doc/MPMEngine.swift:15-33`, from an earlier explicit-MPM draft)
```

In the dam break S_hyd dominated: v_max ≤ 1.6 m/s needed only 0.44 cells per substep at S = 24.

The cost of the rule scales as particles × S ∝ (W·H/Δx²)·(√(gH)/Δx), i.e. ∝ Δx⁻³. **Halving Δx costs 8×.**

| Mode | Δx | Grid (nodes) | Particles (69 mm pool) | S × N at Π ≤ 0.085 | Occupancy | M1 Max GPU per frame [V] | A17 Pro estimate [I] |
|---|---|---|---|---|---|---|---|
| **120 Hz default** | **1.96 mm** | 45 × 88 | 5,152 | 12 × 3 per 1/120 s (Π 0.085) | 0.975 | **0.96 ms**: about 13 µs per dispatch × 72, mostly fixed dispatch cost | 2–4 ms |
| 60 Hz quality | 1.60 mm | 53 × 106 | 7,728 | 32 × 3 per 1/60 s (= 16 per 1/120 s) | 0.98 | 2 × 1.47 = 2.9 ms per 1/60 s | 10–15 ms. Use Π 0.15 (≈ 24 per 1/60 s) to leave room for rendering. |
| Reference only | 1.10 mm | 73 × 150 | 16,000 | 24 × 3 per 1/120 s | 0.98 | 3.74 ms | 15–22 ms (out of budget) |

At 5k particles the frame is dispatch-bound, not compute-bound. A concurrent encoder with explicit barriers (≈ 4.4 µs per dispatch, sibling measurement) roughly halves it [S/I]. Folding binning into fewer passes would cut it further: a persistent-threads substep is a later optimisation.

The A17 Pro factor is inferred from the M1 Max having about 5× the GPU cores at similar clocks and 8× the memory bandwidth. **Phase 0 must measure it** with Metal System Trace on the 15 Pro Max. Shallower fills help as √H; the time-scale knob helps linearly.

### 12.4 Remedies tried that did not work [V] (S = 8, N = 3, Π = 0.60)

| Change | Occupancy | Outcome |
|---|---|---|
| Baseline (relaxation 1.5, grid-volume mix 0.1) | 0.75 | Settles |
| More iterations, N = 5 / 8 | 0.83 / 0.88 | Settles. Costs as much as more substeps, for less gain. |
| `liquidRelaxation` 2.5 | 1.07 | Unstable: J explodes, 4.3M CFL clamps, v_max 2.1 m/s at 3 s |
| Grid-volume mix 0.5 (upstream 0.1) | 0.75 | No effect |
| **Integral pressure**: λ_p += k_I·(1/J − 1) per substep, carried in `logJp` and added to the volume target; decayed at the free surface | 0.81–1.17 | **Rejected**. It holds volume, but the pool never settles: v_max 0.9–1.5 m/s at 3 s for k_I from 0.005 to 0.4, i.e. it injects energy. The hook stays in the code, disabled (`pressure.x = 0`). A grid-smoothed or damped (PI-D) form might work and is left as an experiment. |

### 12.5 Iterations

N = 3 is the default: it reaches about 3 % more occupancy than N = 2 at the same S, for 1.3× the passes. Upstream's demo uses 5 iterations on `main` (4 G2P solves) and 2 on `siggraph2024`.

---

## 13. Telemetry readback

- **Per frame, after the last substep.** `pbStats` (indirect over particles; SIMD-group reductions, then one device atomic per SIMD-group) fills `PBStats` (32 B):
  - live count; max speed (float bits, **minus the gravity kick already in `displacement`**); max τ̄;
  - jammed count; yielding count; Σ J × 1024; Σ λ × 1024; Σ KE in 10 nJ per metre.
- **Readback.** `PBStats` (32 B), `PBCounters` (48 B) and `bodyImpulse` (512 B) go into a triple-buffered `storageModeShared` ring, one slot per frame in flight. The CPU reads them in `addCompletedHandler` and passes them through a `Mutex` mailbox to the main actor (`oss-integration-lessons.md` §3.9) [S].
- **Uses.** H and v_max for the substep rule; the impulse inbox for Box2D; the finger force for haptics; jam and yield counts for UI cues.
- **Verified [V].** On the same particle state, GPU vs CPU:
  - live 16,000 = 16,000;
  - v_max 0.1133 = 0.1133 m/s;
  - mean J 0.7506 = 0.7506;
  - KE 4.979e-3 against 4.978e-3 J/m.
- **Caveat.** At rest, 1e-7 J/m is below the 10 nJ quantum.
- **Gotcha.** The stored displacement already holds the next substep's gravity kick. At rest it reads g·dt (0.0102 m/s at S = 8) unless the kick is subtracted.

---

## 14. The 2.5D fluid renderer (`$MC/pbmpm-metal/PBMPMRender.metal`, `PBMPMRender.h`)

### 14.1 Passes and costs

| # | Pass | Target | What |
|---|---|---|---|
| 0 | Backdrop and everything behind the fluid → `behind` (`rgba16Float`, mipmapped; `generateMipmaps`) | full res | Gyre's glass-orb two-pass (`labkit-from-gyre.md` §10.4, `HoloRenderer.swift:369-377`) [S] |
| 1 | `flSplatVertex` / `flSplatFragment`: one instanced quad per particle, additive into an MRT | ½ res, 2 × `rgba16Float` | A = (t, t·diag, t·speed, t·T/1000); W = t per material slot (4 slots) |
| 2 | `flBlurFragment` horizontal then vertical, both targets at once | ½ res | 9-tap separable Gaussian via 5 linear taps (Gyre `Holo.metal:665-676` weights 0.2270 / 0.3162 / 0.0703 at 0 / ±1.385 / ±3.231 texels; step 1.4 texels) |
| 3 | `flShadeFragment` | full res, scene `rgba16Float` | Surface, normals, refraction, absorption, scattering, Fresnel, GGX, environment, rim, glow; or a diagnostic map |
| 4 | Debug overlays (`flParticleVertex`, `flStreakVertex`) | full res, alpha blend | Particle discs or velocity streaks coloured from the LUT |
| 5 | LabKit `PostChain`: bloom ½ + ¼ and composite with the EDR soft-clip | drawable | Gyre constants (§14.6) |

- **Cost [V].** Passes 1–3 at 1,290 × 2,796 (thickness at 645 × 1,398) with 16,000 particles take **0.44–0.65 ms median, 1.0–1.4 ms p90** on the M1 Max (`run_render.txt`, `run_all.txt`). The sibling's earlier, simpler shader measured 0.33–0.53 ms (`$MC/render/`).
- **A17 Pro estimate:** 2–3 ms [I], plus Gyre's post chain (≈ 1 ms [I]; the survey budgets 2.5–3 ms for render and post together, `oss-engine-survey.md` §7.5).
- **Rendering at full rate.** The fluid passes can run at 60 Hz while the UI and post run at 120 Hz, if the budget needs it [I].

### 14.2 Splat details

- **Footprint.** Radius 1.2 cells (2 × 2 particles per cell). The profile is a sphere, t = √(1 − r²)·w, with w = 1/(4·(2/3)π·1.2²) = 0.0829, so a filled region sums to t ≈ 1.
- **Iso level and edge.** The surface is at t = 0.35, and the edge ramp is ±0.08.
- **Mapping.** `cellsToClip` maps tank cells to clip space: x_clip = (x_c − 3.5)·2/W − 1, and the same for y.
- **Disabled and hidden particles.** These are moved outside the clip volume in the vertex shader, so the draw can use `instanceCount = particleCount` (or indirect draw args from `counters`) [V].
- **Material slots.** `materialSlot[16]` maps a material index to one of 4 RGBA weight channels. The shade pass normalises W and blends the 4 `FluidLook` records (`blendLooks`), so two materials meeting (MR fluid poured into slime) blend at the interface [V for one slot; mixing [I]].
- **Diagnostics.** The value per particle is computed in the vertex shader (`diagValue`, `:17-31`) and splat-averaged, so the map shows a smooth field and not points.

### 14.3 Shading model (`flShadeFragment`, `PBMPMRender.metal:129-204`, verbatim)

```metal
    float2 uv = in.uv;
    float4 A = float4(fieldA.sample(linearClamp, uv));
    float h = A.r;
    float3 bg = float3(backdrop.sample(mipClamp, uv, level(0.0f)).rgb);
    float cover = smoothstep(u.threshold - u.softness, u.threshold + u.softness, h);
    if (cover <= 0.0f) return float4(bg, 1);

    float4 W = float4(fieldW.sample(linearClamp, uv));
    W /= max(W.x + W.y + W.z + W.w, 1e-4f);
    FluidLook L = blendLooks(looks, W);

    // Height-field normal (uv.y points down the screen). The height saturates inside the fluid, so the interior is a
    // flat pane with a rounded rim; raw thickness would print the 2x2 particle lattice as ripples.
    float lo = u.threshold - u.softness, hi = u.threshold + 0.6f;
    float hL = smoothstep(lo, hi, float(fieldA.sample(linearClamp, uv - float2(u.texel.x, 0)).r));
    float hR = smoothstep(lo, hi, float(fieldA.sample(linearClamp, uv + float2(u.texel.x, 0)).r));
    float hU = smoothstep(lo, hi, float(fieldA.sample(linearClamp, uv - float2(0, u.texel.y)).r));
    float hD = smoothstep(lo, hi, float(fieldA.sample(linearClamp, uv + float2(0, u.texel.y)).r));
    float3 n = normalize(float3((hL - hR) * L.extra.z, (hD - hU) * L.extra.z, 1.0f));
    float3 v = float3(0, 0, 1);
    float NoV = saturate(n.z);

    float ior = max(L.surface.x, 1.0f);
    float f0s = (ior - 1.0f) / (ior + 1.0f); f0s *= f0s;
    float3 F0 = mix(float3(f0s), L.albedo.rgb, L.surface.z);                 // metal-like sheen for MR fluid
    float3 F = F0 + (1.0f - F0) * pow(1.0f - NoV, 5.0f);

    float depth = max(h - u.threshold, 0.0f) + u.threshold * 0.5f;           // optical depth proxy (thickness units)
    float tau = depth * L.absorption.a;
    float3 T = exp(-L.absorption.rgb * tau);

    // Refraction: offset along the surface slope, scaled by depth; turbidity via backdrop mip level
    float2 uvR = uv + float2(-n.x, n.y) * L.surface.w * saturate(depth);
    float3 behind = float3(backdrop.sample(mipClamp, uvR, level(L.extra.x)).rgb);

    float3 key = normalize(u.keyLight.xyz), fill = normalize(u.fillLight.xyz);
    float wrap = L.scatter.a;
    float dKey = saturate((dot(n, key) + wrap) / (1.0f + wrap));
    float dFill = saturate((dot(n, fill) + wrap) / (1.0f + wrap));
    float lightAmt = 0.18f + dKey * u.keyLight.w + dFill * u.fillLight.w;
    float3 sss = L.scatter.rgb * (1.0f - exp(-tau)) * (0.35f + 0.65f * dKey);

    float3 body;
    if (u.view == FL_VIEW_DIAG) {
        float d = saturate(A.g / max(h, 1e-4f));
        float3 cm = float3(lut.sample(linearClamp, float2(d, (float(u.colormap) + 0.5f) / float(lut.get_height()))).rgb);
        body = cm * (0.55f + 0.45f * dKey);
    } else {
        float3 clear = behind * T + sss;                                       // translucent path
        float3 opaque = L.albedo.rgb * lightAmt + sss;                         // scattering path
        body = mix(clear, opaque, L.albedo.a);
    }

    float3 r = reflect(-v, n);
    float3 env = studioEnv(r) * F * (1.0f - L.surface.y * 0.7f);
    float3 spec = ggxLight(n, v, key, L.surface.y, F0, u.keyLight.w * 3.0f)
                + ggxLight(n, v, fill, L.surface.y, F0, u.fillLight.w * 3.0f);
    float rim = L.extra.w * pow(1.0f - NoV, 3.0f);

    float3 c = body * (1.0f - F) + env + spec + rim;
    if (L.emission.a > 0.0f) {                                                 // lava: temperature glow into EDR
        float Tk = A.a / max(h, 1e-4f) * 1000.0f;
        float g = pow(saturate((Tk - 700.0f) / 800.0f), 2.0f) * L.emission.a;
        c += glowColour(Tk) * L.emission.rgb * g;
    }
    return float4(mix(bg, c, cover), 1);
```

The equations, in order:

- **Surface.** Coverage = smoothstep(t₀ − s, t₀ + s, t).
- **Height and normal.** Height h_v = smoothstep(t₀ − s, t₀ + 0.6, t); n = normalize(−∂h_v/∂x·k, ∂h_v/∂y·k, 1), with k = `extra.z` of 6–10.
  - The saturation is essential. With raw t, the 2 × 2 particle lattice printed ripples and speckled highlights over the whole interior (first contact sheet).
- **Fresnel (Schlick 1994).** F = F₀ + (1 − F₀)(1 − n·v)⁵, with F₀ = ((η − 1)/(η + 1))². That is 0.020 for water (1.333) and 0.039 for honey (1.49). MR fluid blends F₀ toward its albedo (`surface.z`) for a dark metallic sheen.
- **Refraction.** uv' = uv + (−n_x, n_y)·`surface.w`·min(depth, 1), sampling `behind` at LOD `extra.x`. That LOD is the turbidity: 0 for honey and water, 4 for milky oobleck.
- **Absorption (Beer–Lambert).** T = exp(−σ·τ) per channel, with τ = (t − t₀ + t₀/2)·`absorption.a`.
  - Thickness here is the splat depth proxy, not the 5–10 mm tank gap.
  - Tune σ per preset so that honey reads amber in a thin film and deep brown in the pool [I].
- **Scattering body.**
  - Wrap diffuse: (n·l + w)/(1 + w), with a key and a fill light.
  - Subsurface tint: `scatter.rgb`·(1 − e^−τ).
  - Opacity `albedo.a` mixes the transmitted path (backdrop·T + SSS) with the scattering path (albedo·light + SSS).
- **Specular.** GGX D with Smith–Schlick visibility, k = (α + 1)²/8 (Karis 2013), from two lights. The lights match Gyre's key (0.25, 0.45, 0.86) × 1.1 and fill (−0.7, 0.5, 0.2) × 0.45. In the app, make them world-anchored, so highlights slide as the phone tilts (`labkit-from-gyre.md` §10.4) [S]. A studio-gradient environment reflection is weighted by F.
- **Glow (lava).** T_K is the splat-averaged temperature. Colour ≈ (1, 0.18 + 0.62x², 0.02 + 0.35x⁴), with x = (T − 700)/900. Intensity is `emission.a`·((T − 700)/800)². This exceeds 1 on purpose, feeding the bloom and EDR. The colour fit is not colorimetric [I].

### 14.4 Appearance presets (`FluidLook`; linear values; the first six were rendered [V], the rest are starting points [I])

| Preset | albedo (rgb, opacity) | σ_abs (rgb, scale) | scatter (rgb, wrap) | IOR, rough, metal, refract | glow (rgb, gain) | LOD, height k, rim |
|---|---|---|---|---|---|---|
| Ketchup (glossy red) | 0.42, 0.020, 0.010, **0.85** | 0.6, 6, 8, 1.5 | 0.55, 0.03, 0.01, 0.4 | 1.42, **0.12**, 0, 0.010 | — | 1, 8, 0 |
| Oobleck (opaque white) | 0.82, 0.80, 0.74, **0.92** | 0.4, 0.45, 0.6, 1 | 0.9, 0.88, 0.82, 0.6 | 1.40, 0.45, 0, 0.004 | — | **4**, 6, 0.05 |
| Honey (amber) | 0.55, 0.30, 0.05, **0.12** | 0.25, 0.9, 3.2, 1.2 | 0.6, 0.3, 0.04, 0.3 | **1.49**, 0.08, 0, **0.030** | — | 0.5, 8, 0 |
| Slime (translucent green) | 0.12, 0.65, 0.18, **0.25** | 2.5, 0.35, 2.2, 1 | 0.2, 0.8, 0.25, 0.5 | 1.36, 0.18, 0, 0.025 | — | 1.5, 7, 0.10 |
| MR fluid (black glossy) | 0.020, 0.020, 0.022, **1.0** | 8, 8, 8, 1 | 0, 0, 0, 0 | 1.60, 0.15, **0.6**, 0 | — | 0, **10**, 0.08 |
| Lava (glowing) | 0.06, 0.03, 0.02, 1.0 | 4, 4, 4, 1 | 0.3, 0.05, 0, 0.2 | 1.50, 0.6, 0, 0 | **3.0, 1.0, 0.6, 4.0** | 0, 6, 0 |
| Water (reference) | 0.6, 0.8, 0.9, 0.0 | 0.45, 0.09, 0.05, 0.6 | 0.02, 0.05, 0.06, 0.2 | 1.333, 0.05, 0, 0.040 | — | 0, 8, 0 |
| Toothpaste | 0.90, 0.92, 0.95, 0.98 | 1, 1, 1, 1 | 0.9, 0.95, 1.0, 0.5 | 1.45, 0.25, 0, 0 | — | 3, 7, 0.03 |
| Mayonnaise | 0.85, 0.80, 0.58, 0.97 | 1, 1, 1.2, 1 | 0.9, 0.82, 0.55, 0.6 | 1.46, 0.35, 0, 0 | — | 3, 6, 0.03 |
| Yogurt | 0.88, 0.87, 0.82, 0.95 | 1, 1, 1, 1 | 0.9, 0.9, 0.85, 0.7 | 1.40, 0.5, 0, 0 | — | 4, 5, 0.02 |
| Silly putty | 0.85, 0.35, 0.55, 1.0 | — | 0.6, 0.2, 0.3, 0.3 | 1.45, 0.30, 0, 0 | — | 0, 9, 0.05 |
| Quicksand | 0.55, 0.45, 0.30, 1.0 | — | 0.4, 0.3, 0.2, 0.2 | 1.50, 0.8, 0, 0 | — | 0, 4, 0 |
| Paint (user colour) | c, 1.0 | — | 0.5c, 0.3 | 1.45, 0.20, 0, 0 | — | 0, 8, 0.02 |

Keep albedo × light below the 0.8 soft-clip knee, so only highlights and lava glow reach EDR (`labkit-from-gyre.md` §10.4) [S]. Quicksand and toothpaste want a texture term (grain noise; stripes from a per-particle tag in the diagnostic channel) [I].

### 14.5 Diagnostic colour maps and debug views

| Mode (`FL_DIAG_*`) | Quantity → [0, 1] | Suggested LUT row |
|---|---|---|
| `SHEAR_RATE` | (log₁₀ γ̇ + 2)/5, i.e. 10⁻² … 10³ s⁻¹ | 0 viridis [V rendered] |
| `VISCOSITY` | (log₁₀ η + 3)/9, i.e. 10⁻³ … 10⁶ Pa·s | 3 cividis |
| `STRESS` | (log₁₀ τ + 1)/5, i.e. 0.1 … 10⁴ Pa | 1 magma |
| `STRUCTURE` | λ | 0 viridis |
| `JAM` | contact fraction f (jammed when φ ≥ φ_J(f)) | 2 inferno |
| `TEMPERATURE` | (T − 273)/1200 K | 2 inferno |
| `COMPRESSION` | (J − 0.7)/0.6 | 4 turbo (diverging around 0.5 = J 1.0) |
| `SPEED` | \|v\|/v_max | 1 magma [V rendered, streaks] |

- **LUT.** A 256 × 5 `rgba8Unorm_srgb` texture (rows: viridis, magma, inferno, cividis, turbo), generated from matplotlib 3.10.9: `$MC/pbmpm-metal/host/colormaps_256x5_rgba8.bin`.
  - **Use the `_srgb` format.** The bytes are sRGB-encoded; sampling them as linear washed the map out in the first contact sheet [V].
  - The scratch degree-6 polynomial fits (`$MC/colormaps/coeffs.txt`) are off by up to 0.12 (turbo) and 0.057 (inferno), so use the LUT.
  - Licences: viridis, magma and inferno are CC0 (van der Walt and Smith); turbo is Apache-2.0 (Google); cividis is from Nuñez et al. 2018 as shipped in matplotlib. Check each before shipping the data [I].
- **Diagnostic view.** The map replaces the body colour, but the normals and specular remain, so the fluid still reads as a shape.
- **Particle view** (`flParticleVertex`): 1.6 px discs coloured by the diagnostic, over the shaded fluid. **Flow view** (`flStreakVertex`): 1.5 px streaks from x to x − v·0.02 s, coloured by speed (magma) [V rendered].
- A coarse velocity-arrow grid can reuse LabKit's `LineBatch` from `pbStats`-style grid sampling [I].

### 14.6 Bloom and EDR (Gyre style, via LabKit `PostChain`) [S]

- **Targets.** Scene `rgba16Float`; drawable `rgba16Float`; `CAMetalLayer.wantsExtendedDynamicRangeContent = true`; colour space `extendedLinearDisplayP3` (Gyre `HoloRenderer.swift:738-739`).
- **Bloom.**
  - Prefilter c·smoothstep(0.35, 1.3, max(rgb)) into ½ resolution (Gyre `Holo.metal:655-659`).
  - Blur H/V at a 1.4-texel step, copy to ¼, blur at a 2.2-texel step.
  - Composite: bloom ½ × 0.6 + ¼ × 0.54.
- **Soft clip.** `softClip(x, min(headroom, 3))` with knee k = 0.8: x ≤ k passes, and above it k + (h − k)(1 − e^(−(x − k)/(h − k))) (`Holo.metal:680-685, 706`). The headroom comes from `currentEDRHeadroom` (`HoloRenderer.swift:690`).
- **For the fluid.** The lava glow and GGX highlights are the only intended values above 1. Rheo should skip Gyre's scanlines (`post.y = 0`) and keep a little chromatic aberration (0.0022) only if it suits the lab look.
- **Offline check.** `flTestCompositeFragment` applies the same soft clip and clamps to SDR for the PNG.

### 14.7 Render check [V]

**`$MC/pbmpm-metal/host/render_check.png`** (1,720 × 1,864):

- 8 panels rendered from real PB-MPM states: a water dam break and a ketchup (EVP) dam break at t = 0.30 s, S = 24.
- Row 1: ketchup, oobleck, honey, slime looks. Row 2: MR fluid, lava (temperature set from 1,450 K at the bottom to cooler in the splash), the shear-rate map over ketchup, and flow streaks.

Observations:

- **Particle lattice.** The 2 × 2 lattice is invisible after the saturating-height change.
- **Translucent presets.** Honey and slime show the backdrop grid refracted only faintly, because the backdrop is dark and the pool is deep. Tune σ, or use a lighter tray backdrop [I].
- **Lava.** The hot core clips to white in SDR, as expected; on device it goes into EDR.

---

## 15. Risks and open items

1. **A17 Pro throughput is not measured.**
   - At 5k particles the solver is dispatch-bound (≈ 13 µs per dependent dispatch on a loaded M1 Max).
   - Phase 0: run the dam break on the 15 Pro Max under Metal System Trace with a concurrent encoder plus barriers, and replace the §12.3 estimates.
2. **PB-MPM at real gravity is compressible unless Π ≤ 0.07–0.085.** This sets the substep count and therefore Δx.
   - The integral-pressure experiment failed (§12.4).
   - If the budget cannot meet Π, either accept up to 10 % loss (Π 0.15), use the time-scale knob, or move the liquid phase to a pressure projection (a later research item).
3. **EVP calibration.** κ, the effective Maxwell viscosity, and the yield-stress shapes against the CPU oracle (§11.5). Until then, presets are tuned by eye.
4. **Simulator:** SIMD-group functions are unverified (§7).
5. **`impulseOverflow`** is declared but not incremented (§8). A node touched by two body shapes is attributed to the last one (§9).
6. **Determinism** is bitwise on one GPU. Across GPUs (M1 Max vs A17 Pro), fast-math differences will diverge chaotically. Physics checks must use tolerances (`toolchain-checks.md` §4.4) [S].
7. **Undamped sloshing.** PB liquids slosh for seconds; the buoyancy test needed the wall drag. Give every preset a wall drag (b ≈ 5–8 mm, η_w from the material) so the tank calms the way a real thin cell does.
8. **Box2D at centimetre scale.** Props of 1–3 cm are below Box2D's tuned 0.1–10 m range. Follow `oss-integration-lessons.md` §3.5 (length units per metre) [S].
9. **Licence.**
   - `PBMPM.metal` and `PBMPMShared.h` are BSD-3 derivatives: keep the header notice and `LICENSE-PBMPM.md`, credit EA in-app, and never "powered by EA" (`oss-engine-survey.md` §8) [S].
   - `PBMPMRender.*` is new code.

---

## 16. Reproduce

```zsh
cd $MC/pbmpm-metal
./host/build.sh                       # metallibs (macOS b6/b14, iOS), host; 0 warnings
./host/pbhost all                     # dam, sweep, timing, parity, stale, box, materials (≈ 2 min)
PB_S=24 PB_NOPUSH=1 ./host/pbhost box # exact impulse parity + buoyancy at Π 0.07
./host/pbhost det                     # bitwise determinism (PB_S, PB_N)
./host/pbhost bins                    # binning consistency
./host/pbhost render                  # render_check.png + render pass timing
PB_W=36 PB_LIST=12x3 ./host/pbhost sweep   # other resolutions (PB_W = interior width in cells)
# iOS compile only:
TOOLCHAINS=metal xcrun -sdk iphoneos metal -Wall -Wextra -c PBMPM.metal -o /tmp/x.air
```

Tool notes:

- `xcrun -sdk macosx metal` without `TOOLCHAINS=metal` hits the stub ("missing Metal Toolchain"). `-sdk iphoneos` finds the real compiler on its own (`toolchain-checks.md` §1 item 3) [V].
- The host imports the C structs through `-import-objc-header host/Bridging.h`. In LabKit, the same header goes in a C target's `include/` and is reached from `.metal` files by a relative path (`toolchain-checks.md` §1 item 2) [S].

---

## 17. Sources

- PB-MPM:
  - C. Lewin, "A Position Based Material Point Method", SIGGRAPH 2024 talk.
  - Code: https://github.com/electronicarts/pbmpm (BSD-3), `main` 61749b6c2d2631ed243f86882752ba43196f2de7 and `siggraph2024` 5a2f438b7115741c41ed429a2a0360d0e5f4b5a9.
  - Files cited: `shaders/g2p2g.wgsl`, `bukkit*.wgsl`, `particleEmit.wgsl`, `particle.inc.wgsl`, `simConstants.inc.wgsl`, `matrix.inc.wgsl`, `src/sim.js`, `src/ui.js`, and on `siggraph2024`: `particleUpdatePBMPM.wgsl`, `particleToGrid.wgsl`, `gridUpdate.wgsl`, `gridToParticle.wgsl`, `particleIntegrate.wgsl` [V].
- P. Gimeno, robust 2 × 2 SVD, https://scicomp.stackexchange.com/q/14103 (as cited upstream).
- M. Macklin, M. Müller, N. Chentanez, "XPBD: Position-Based Simulation of Compliant Constrained Dynamics", MIG 2016 (compliance form of §11.2).
- Rheology:
  - D. W. Moore 1959 (thixotropy);
  - M. Wyart and M. E. Cates, PRL 112, 098302 (2014);
  - G. Klár et al., "Drucker–Prager elastoplasticity for sand animation", SIGGRAPH 2016 (upstream sand);
  - J. D. Carlson, MRF-132DG data;
  - details and parameters in `rheology-models.md` [S].
- Rendering:
  - W. J. van der Laan, S. Green, M. Sainz, "Screen Space Fluid Rendering with Curvature Flow", I3D 2009;
  - C. Schlick 1994 (Fresnel approximation);
  - B. Walter et al. 2007 (GGX);
  - B. Karis, "Real Shading in Unreal Engine 4", SIGGRAPH 2013 course (Smith–Schlick k).
- Gyre (local): `Gyre/Gyre/Render/Holo.metal:655-706` (bloom prefilter, blur, soft clip), `HoloRenderer.swift:690, 738-739` (EDR headroom, layer) [V].
- Sibling notes:
  - `oss-engine-survey.md` §3.1, §6, §7, §8;
  - `oss-integration-lessons.md` §3.5, §3.7–3.10;
  - `toolchain-checks.md` §1, §4;
  - `labkit-from-gyre.md` §4.8, §10.4;
  - `labkit-from-orbitals-spectra.md` §5;
  - `rheology-models.md`.
