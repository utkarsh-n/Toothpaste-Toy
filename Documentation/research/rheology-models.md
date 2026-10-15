# Rheo: rheology and constitutive-model reference

The physics "bible" for **Rheo** (subtitle *Non-Newtonian Toy*) and for the rheology module of the shared **LabKit** engine. It covers every material class the toy simulates, with equations, units and literature parameter values. It then defines **one unified elasto-viscoplastic constitutive update** for explicit planar-2D MLS-MPM that reproduces all of them per material, followed by toy-scale nondimensionalisation, a 13-preset parameter table and a closed-form verification suite for the CPU reference.

Compiled 2026-10-03. SI units throughout (Pa, Pa·s, Pa·sⁿ, s, m, K, A/m, T). British spelling.

---

## 0. How to read this document

### 0.1 Tags

| Tag | Meaning |
|---|---|
| **[V]** | Read in the primary source this session, as raw text I extracted (pypdf) from the paper, datasheet or thesis PDF, or from the app source (file:line). |
| **[S]** | Secondary: a search-result snippet, or a page read through a summarising fetcher. Fine for UI copy and starting values. Re-check before using as a test oracle. |
| **[C]** | Computed or numerically verified this session by the reference code in §0.3 (Python 3.10 + numpy 2.2, Swift 6.4, Metal on an M1 Max). |
| **[I]** | Inferred or designed by me (a toy calibration or engineering choice). It is not a literature value. |
| **[!]** | Flag: an uncertainty, a trap or a disagreement with the brief. They are all collected in §9. |

### 0.2 Notation and conventions (used everywhere below)

- Velocity gradient **C** = ∇v (from APIC/MLS, §4.4). The rate of deformation is **D** = ½(C + Cᵀ). Planar 2D has components c11 = ∂vₓ/∂x, c12 = ∂vₓ/∂y, c21 = ∂v_y/∂x and c22 = ∂v_y/∂y.
- **Equivalent shear rate** γ̇ = √2‖dev D‖_F. In planar 2D this is **γ̇ = √((c11 − c22)² + (c12 + c21)²)**. In simple shear u = γ̇y it equals γ̇ [C].
- **Kirchhoff stress** τ = Jσ, with σ the Cauchy stress. Its deviator is s = dev τ.
- **Equivalent shear stress** τ̄ = ‖s‖_F/√2. In planar 2D, with s22 = −s11, this is **τ̄ = √(s11² + s12²)**. In simple shear τ̄ equals τ_xy when normal stresses vanish.
- Every flow law is written in **rheometer convention**: τ = τ_y + k γ̇ⁿ, where τ_y is the shear yield stress. Yue et al. 2015 instead use a uniaxial σ_Y with Φ = ‖s‖ − √(2/3)σ_Y. The conversion is **σ_Y = √3 τ_y** and **η_Yue = k·2^{(1+n)/2}** (so η_Yue = 2μ_p for Bingham) [C, derived in §4.3].
- dev in d dimensions: dev A = A − (tr A/d) I, with **d = 2** (planar, §4.5).
- Temperatures are in K inside formulas. Some literature fits use °C, and those are labelled.

### 0.3 Reference code written for this note (scratch, not part of any app)

Location: `/private/tmp/claude-501/-Users-utkarsh-Documents-AI-Stuff/b53a2b83-9308-4477-a9dd-fedd258cad75/scratchpad/rheology/`

| File | What it does |
|---|---|
| `calc/evp.py` | Python reference of the unified per-particle update (float64) |
| `calc/evp_vec.py` | Vectorised update with a fixed 4-iteration Newton solve (GPU-like) |
| `calc/t1_homogeneous.py` | Steady shear, Maxwell relaxation and start-up, N₁, Moore, viscosity bifurcation, φ_DST, front speed |
| `calc/t2_dst.py` | Oobleck branch: ramp, impact, hold and release |
| `calc/t3_channel_film.py`, `t3b.py` | 1D staggered-grid Poiseuille, incline film and Couette against closed forms |
| `calc/t4_newton_f32.py`, `t5_unified_flow_f32.py` | float32 Newton convergence |
| `calc/t6_saos_vft.py` | SAOS moduli, glycerol VFT fit |
| `calc/t7_gnf_map.py` | Cross/Carreau mapped onto the unified law |
| `calc/worked_numbers.py`, `calc/presets.py` (+ `presets.json`) | Numbers and the preset table |
| `gpu/RheoConstitutive.metal` | The MSL kernel (Appendix A). Compiles for `iphoneos` with `-std=metal4.0`, no warnings |
| `gpu/RheoXPBD.metal`, `gpu/xpbd_check.swift` | XPBD-EVP constraint step and SI native viscosity for PB-MPM (Appendix C), with a GPU smoke test |
| `calc/t8_closed_forms.py`, `calc/t15_kolmogorov_closed.py` | Every §7 closed form against independent quadrature or ODE integration (65/65 pass) |
| `calc/t9_mpm2d_cases.py` (+ `t9b`, `t10`–`t13`) | numpy 2D explicit MLS-MPM oracle prototype running the §7 cases, with convergence studies |
| `calc/presets2.py` (+ `presets2.json`), `calc/t14_piles.py` | Revision-2 preset table (§6) and toy-scale regime and acceptance numbers (§5) |
| `pbmpm/pbmpm2d.py`, `t1_shearwave.py`, `t2_stability_map.py`, `t2b_boundary.py`, `t3_warm_beta.py` | numpy 2D PB-MPM: native-viscosity calibration and XPBD-EVP stability (§4.10) |
| `gpu/main.swift` | Swift CPU reference (Double) plus a Metal GPU run on macOS, cross-checked |

Outputs are in the `*_out.txt` files next to each script. Appendix A reproduces the kernel, Appendix B the Swift reference and Appendix C the PB-MPM constraint step. The scratch folder is session-local, so treat the appendices as the durable copy.

---

## 1. Summary and decisions

1. **The hypothesis holds, with one refinement.** A single per-particle elasto-viscoplastic (EVP) update covers every class in the brief. It follows Yue et al. 2015 ("Continuum Foam"): an isochoric left Cauchy–Green tensor b̄ₑ, a backward-Euler Herschel–Bulkley return map on a scalar equation, and a separately tracked volume ratio J. It needs only 8 floats of rheology state per particle. The refinement: the flow law is a **sum of three monotone inverse branches**, each giving the plastic rate as a function of stress:

   γ̇ₚ(τ̄) = φ₀ τ̄ + ((τ̄ − τ_y)₊/k)^{1/n} + φ_f (τ̄ − τ_f)₊

   - The first term is a Newtonian or zero-shear plateau, with fluidity φ₀ = 1/η₀.
   - The second is Herschel–Bulkley.
   - The third is a failure branch, used by jammed oobleck and as an elastic-strain limiter.

   Structure λ (thixotropy and rheopexy), contact fraction f (Wyart–Cates DST), temperature T (Arrhenius) and the magnetic field H (MR) only *modulate* τ_y, k, φ₀, τ_f and φ_f.
2. **The return map is unconditionally stable for any viscosity.**
   - **Revised:** it reproduces the steady flow curve exactly only as Wi → 0. At finite Weissenberg number it under-predicts by about 2Wi² (−1.9 % at Wi = 0.1), independent of Δt [C, §4.6].
   - It must be backward Euler. An exponential-relaxation update loses viscosity: at Δt/λ = 2 it gives only 31 % of η·γ̇ [C, §4.6].
3. **Newton from the "min of single-branch roots" start converges monotonically and needs no safeguard.** Four to five float32 iterations reach machine precision for n ∈ [0.2, 1] across 7 decades of stress [C]. Restrict **n ≤ 1**. Shear thickening comes from the Wyart–Cates branch, not from n > 1.
4. **Planar 2D (d = 2) is exact for plane-strain plasticity.** In 2D, von Mises equals Tresca, and τ̄ is the maximum in-plane shear. Use 2×2 tensors throughout. To convert a 3D bulk modulus, use K₂D = K₃D + G/3 (§4.5).
5. **DST uses the stress-controlled Wyart–Cates law with the contact fraction f lagged one step**, plus Han et al.'s strain scale γ* = 0.197. The flow law then stays monotone (closed form), while the S-curve, hysteresis, jamming fronts and stop-go emerge from the f dynamics. A jammed region is a creeping elastic solid (t_jam) with a failure stress τ_jam and strain-induced unjamming (γ_break) [I, tested in §4.7].
6. **Keep ρ, g, L, τ_y, k, n and η physical. Soften only K and G.**
   - Revised in §5.3: for Maxwell materials whose G must be softened (Silly Putty), keep λ physical and let η follow. This keeps Deborah numbers right; creep is then sped up, and that is disclosed.
   - Constraints: yield strain τ_y/G ≤ 0.05, Wi_num ≤ 0.1 at the working shear rate, and compression ≤ 3 % over the tank height (oracle).
   - Slumps, stoppage heights and pile shapes then match reality at tank scale.
   - Cost: the explicit oracle needs 113–130 substeps per 1/120 s frame. The PB-MPM GPU path needs 6–20 substeps × 3 iterations (§5.4).
7. **The constitutive update is cheap.** It measured 0.06–0.12 ns per particle-update on an M1 Max GPU (ALU-bound, in-kernel loop) [C, `gpu_out2.txt`]. For A17 Pro I estimate about 0.5 ns [I]. In the PB-MPM path the update runs k + 1 = 4 times per substep (k evaluations plus the commit). At 20 substeps per 1/120 s frame and 50 k particles that is about 2 ms per frame [I]. The P2G/G2P transfers will dominate.
8. **Ferrofluid spikes (Rosensweig) are not an MPM continuum effect.** They need surface tension, magnetic normal traction and λ_c ≈ 10 mm resolved by ≥ 10 cells. Fake them with the analytic dispersion relation (§3.10).

---

## 2. Kinematics and stress measures shared by every model

### 2.1 Generalised-Newtonian and viscoplastic tensor forms

For an incompressible fluid with a shear-rate-dependent viscosity:

σ = −p I + 2 η(γ̇) D,  γ̇ = √(2 D:D) (3D), or √2‖dev D‖ (planar, §0.2).

For a yield-stress (Bingham or HB) fluid, using von Mises:

- unyielded (rigid or elastic) where τ̄ = √(½ s:s) ≤ τ_y;
- otherwise σ_dev = 2 (τ_y/γ̇ + k γ̇^{n−1}) D.

Sources: the textbook form in Saramito 2009 §1 [V] and Yue 2015 §5 [V].

### 2.2 Dimensionless groups used in §5

| Group | Definition | Meaning |
|---|---|---|
| Reynolds | Re = ρUL/η_eff | inertia vs viscosity |
| Bingham | Bi = τ_y/(k (U/L)ⁿ) | yield vs viscous stress |
| Yield (plasticity) number | Y = τ_y/(ρ g L) = ℓ_y/L | yield vs gravity |
| Deborah | De = λ/t_obs (Reiner 1964) | relaxation vs observation time |
| Weissenberg | Wi = λ γ̇ | elastic vs viscous in flow |
| Mach | Ma = U/c_p | flow speed vs elastic P-wave speed (numerics only) |

Yield length: **ℓ_y = τ_y/(ρ g)**. This is the height of a sheet that just stands under its own weight on a vertical-ish face (order of magnitude). It sets the visible "body" of every paste (§5.2).

---

## 3. Material classes

### 3.1 Newtonian: water, glycerol, honey (Rheo's control fluid)

σ = −pI + 2ηD. Temperature dependence:

- **Arrhenius:** η(T) = A exp(E_a/(RT)), shift factor a_T = η(T)/η(T_ref) = exp[(E_a/R)(1/T − 1/T_ref)], R = 8.314 462 618 J/(mol·K).
- **Vogel–Fulcher–Tammann (VFT):** ln η = A + B/(T − T₀). This fits glass-forming liquids such as glycerol and sugar syrups over wide ranges.
- **WLF:** log₁₀ a_T = −C₁(T − T_r)/(C₂ + T − T_r), with the "universal" C₁ = 17.44 and C₂ = 51.6 K at T_r = T_g (Williams–Landel–Ferry 1955) [S]. It is used for honey near T_g ≈ −45 °C.

**Water and glycerol** (Cheng 2008, *Ind. Eng. Chem. Res.* 47, 3285, DOI 10.1021/ie071349z; T in °C; result in mPa·s) [S formula, C values]:

- μ_w = 1.790 exp[(−1230 − T)T/(36100 + 360T)]
- μ_g = 12100 exp[(−1233 + T)T/(9900 + 70T)]

| T (°C) | 0 | 10 | 20 | 25 | 30 | 40 | 60 | 80 | 100 |
|---|---|---|---|---|---|---|---|---|---|
| water (mPa·s) | 1.790 | 1.310 | **1.005** | 0.893 | 0.800 | 0.655 | 0.468 | 0.356 | 0.283 |
| glycerol (Pa·s) | 12.10 | 3.817 | **1.414** | 0.906 | 0.598 | 0.282 | 0.0822 | 0.0315 | 0.0148 |

Effective Arrhenius E_a between 15 and 25 °C: water 17.5 kJ/mol, glycerol 66.0 kJ/mol [C].

A glycerol VFT fit to the Cheng curve over 0–100 °C is **η = exp(−11.657 + 1558.36/(T − 163.20)) Pa·s**, with T in K and a maximum error of 2.4 % [C].

**Honey.** Newtonian at ordinary rates. Its viscosity is dominated by water content and temperature.

- Yanniotis et al. 2006 (*J. Food Eng.* 72, 372) report E_a from 70.8 to 96.3 kJ/mol, falling linearly with moisture, over 25–45 °C at 17–21 % water [S].
- Saxena, Panicker & Gautam 2014 (*Int. J. Food Sci.* 2014:935129, DOI 10.1155/2014/935129) give seven brands at 25 °C spanning 2.3–16 Pa·s, with E_a from 54 to 89 kJ/mol. Brand II has **E_a = 85 kJ/mol and A₀ = 1.1 × 10⁻¹⁴ Pa·s** [S]. That gives [C]:

| T (°C) | 10 | 15 | 20 | 25 | 30 | 40 | 50 | 60 |
|---|---|---|---|---|---|---|---|---|
| η (Pa·s) | 52.7 | 28.2 | **15.4** | 8.57 | 4.87 | 1.66 | 0.604 | 0.234 |

With E_a = 85 kJ/mol, viscosity halves for every **6.0 K** rise near 25 °C [C].

**What the toy shows.** Honey is the "control" fluid: no yield, no elasticity, pure viscosity, so coiling and rope-like pours show at the tank scale. The Heat knob changes it by about ×65 between 10 and 60 °C. In the unified model it is the Maxwell branch with G ≥ 10 η γ̇_max (§5.3).

### 3.2 Generalised Newtonian (shear-thinning): ketchup, paint, shampoo, blood

| Model | η(γ̇) or τ(γ̇) | Parameters (units) | Source |
|---|---|---|---|
| Power law (Ostwald–de Waele) | τ = k γ̇ⁿ, so η = k γ̇^{n−1} | k (Pa·sⁿ), n (–) | textbook |
| Cross | η = η_∞ + (η₀ − η_∞)/[1 + (λγ̇)^m] | η₀, η_∞ (Pa·s), λ (s), m (–) | Cross 1965, *J. Colloid Sci.* 20, 417 |
| Carreau–Yasuda | η = η_∞ + (η₀ − η_∞)[1 + (λγ̇)^a]^{(n−1)/a}; Carreau has a = 2 | η₀, η_∞, λ, n, a | Carreau 1972, *Trans. Soc. Rheol.* 16, 99; Yasuda et al. 1981, *Rheol. Acta* 20, 163 |
| Casson | √τ = √τ_y + √(η_c γ̇) for τ ≥ τ_y | τ_y (Pa), η_c (Pa·s) | Casson 1959 |

Literature values:

- **Blood** (Carreau; Cho & Kensey 1991, *Biorheology* 28, 241): η₀ = 0.056 Pa·s, η_∞ = 0.00345 Pa·s, λ = 3.313 s, n = 0.3568 [S]. That gives η = 56.0, 54.3, 27.1, 8.98, 4.71 and 3.74 mPa·s at γ̇ = 0.01, 0.1, 1, 10, 100 and 1000 s⁻¹ [C]. The Casson yield stress of blood is only about 0.001–0.006 Pa (0.01–0.06 dyn/cm², Merrill and co-workers) [S]. That is invisible at toy scale.
- **Ketchup.** Herschel–Bulkley with n ≈ 0.22–0.26. One formulation at 25 °C gave τ₀ = 4.41 Pa, K = 16.18 Pa·sⁿ and n = 0.250 (Koocheki et al. 2009, *Int. J. Food Sci. Tech.* 44, 596) [S]. Commercial ketchups are also thixotropic [S].
- **Paint** (latex, architectural). Coatings practice targets an "ICI" high-shear viscosity of 1–2 P (0.1–0.2 Pa·s) at 10⁴ s⁻¹ for low brush drag, and a low-shear viscosity of 25–100 Pa·s for levelling without sag. Below about 10 Pa·s it sags [S, paint.org JCT 1997 and coatings application notes]. An HB fit that satisfies both is **τ_y = 3 Pa, k = 3.5 Pa·sⁿ, n = 0.65**. It gives η = 37.8 Pa·s at 0.1 s⁻¹ and 0.140 Pa·s at 10⁴ s⁻¹ [C].
- **Shampoo.** Wormlike-micelle solutions are close to single-mode Maxwell, with a Newtonian plateau and then strong thinning above γ̇_c ≈ 1/λ_Maxwell [S, NIST and UMass wormlike-micelle papers]. Representative toy values are η₀ ≈ 5–10 Pa·s, λ ≈ 0.05–0.5 s and m ≈ 0.8 [I].

**Mapping onto the unified law** (§4). Use a sum of rates, γ̇ = τ/η₀ + (τ/k)^{1/n}, plus an optional parallel η_∞:

- Carreau → φ₀ = 1/(η₀ − η_∞), **k = (η₀ − η_∞) λ^{n−1}**, same n.
- Cross → **k = (η₀ − η_∞) λ^{−m}**, **n = 1 − m**.

Shape error: Carreau (blood) is within −15 % everywhere, worst at γ̇ ≈ 0.4 s⁻¹. Cross with m = 0.8 is up to +53 % at the crossover γ̇ ≈ 7 s⁻¹. Refit k by eye if that matters [C, `t7_gnf_map.py`]. Casson's exact inverse γ̇ = (√τ − √τ_y)²/η_c is convex in τ, so it can be added as a branch with the same Newton guarantee [C, analytic].

### 3.3 Viscoplastic: Bingham and Herschel–Bulkley (toothpaste, mayonnaise, ketchup, mustard, hair gel, lava, mud)

τ = τ_y + k γ̇ⁿ when τ̄ > τ_y; otherwise no flow (rigid, or elastic in EVP). Bingham is the case n = 1 (k = μ_p, the plastic viscosity). Sources: Bingham 1922, *Fluidity and Plasticity*; Herschel & Bulkley 1926, *Kolloid-Z.* 39, 291.

| Material | τ_y (Pa) | k (Pa·sⁿ) | n | Source / tag |
|---|---|---|---|---|
| Toothpaste | 41–286 reported (100–150 typical) | — | ≈0.3–0.5 | search summary of TA Instruments RH025 and toothpaste studies [S] |
| Mayonnaise | ~20 (pourable) to ~200 (spoonable); one study 85–193 | 8.5–26 (another 45–118 with n 0.19–0.24) | <1 | Heliyon 2020 mayonnaise study, Thermo app note [S] |
| Ketchup | 4–30 | 8–18 | 0.22–0.30 | Koocheki 2009 [S] |
| Mustard | ~20–40 | ~10–20 | ~0.3–0.4 | [I], no primary value found |
| Hair gel (Carbopol 0.2–0.5 %) | ~10–60 | 0.75–13 | 0.5–0.6 | Carbopol model-fluid literature, e.g. Dinkgreve 2018 [S] |
| Basaltic lava (Makaopuhi, ~1130 °C) | **70 and 120** | **650–750 Pa·s** | 1 | Shaw et al. 1968, *Am. J. Sci.* 266, 225 [S] |
| Basaltic lava (channel levées) | 10²–10⁴ | — | — | Hulme 1974, *Geophys. J. R. Astr. Soc.* 39, 361 [S] |
| Kīlauea pāhoehoe | — | ~116 Pa·s at 1150 °C to 167 at 1115 °C, max 1800 at 1105 °C | — | field measurement summary, Chevrel et al. (EPSL 2018) [S] [!] |
| Mud / debris | 10–10³ | — | ≈1/3 | Coussot 1997, *Mudflow Rheology and Dynamics* [S] |

**Geological use of the same law.** A Bingham sheet on slope α stops at **h = τ_y/(ρ g sin α)**. Levée width w gives τ_y = 2ρ g w sin²α (Hulme 1974) [S]. Rheo uses exactly this as verification case V5.

**What the toy shows.** For mayonnaise, ℓ_y = τ_y/(ρg) = 8.9 mm, so a blob stands about 1–2 cm tall and holds peaks. For ketchup ℓ_y = 2.3 mm, so it mounds then creeps. For toothpaste ℓ_y = 11.3 mm, so a ribbon keeps its shape. Lava at 100 Pa has ℓ_y = 3.9 mm (§5.4).

### 3.4 Discontinuous shear thickening: cornstarch "oobleck"

#### 3.4.1 Wyart–Cates model (WC)

Wyart & Cates 2014, *PRL* 112, 098302, DOI 10.1103/PhysRevLett.112.098302 [V]:

- Particle pressure P = λ γ̇ (φ_J(p) − φ)⁻², with p = P/P*.
- **φ_J = φ_m f + φ₀(1 − f)**, where f ∈ [0,1] is the fraction of lubrication films broken into frictional contacts.
- φ₀ ≈ 0.64 is frictionless random close packing, and φ_m ≈ 0.58 is frictional jamming (for spheres).
- Their numerics use **f = 1 − exp(−p)**.
- DST between two flowing branches (S-shaped, hysteretic) appears for φ_DST < φ < φ_m, with φ_DST ≈ 0.55 for spheres. Above φ_m the high-stress state is completely jammed and "cannot flow without inhomogeneity or fracture".

**Shear-stress form used by experimenters** (Han, Wyart, Peters & Jaeger 2018, *Phys. Rev. Fluids* 3, 073301, arXiv 1711.02196) [V]:

- Σ = η₀ γ̇ [1 − φ/φ_eff]⁻²
- φ_eff = g(γ) f(Σ) φ_m + [1 − f(Σ) g(γ)] φ₀
- f(Σ) = 1 − exp(−Σ/Σ*), g(γ) = 1 − exp(−γ/γ*)

The fit for cornstarch in a glycerol/water/CsCl solvent (density-matched, 1.62 g/cm³, solvent 11 mPa·s) is **φ₀ = 0.593, φ_m = 0.452, η₀ = 13.6 mPa·s, Σ* = 20.4 Pa, γ* = 0.197**. The same paper puts the steady-state upper stress at about **500 Pa**, set by surface tension [V].

The **inverse form f = exp(−σ*/σ)** is sharper (f′(0) = 0) and is also widely used. One cornstarch fit: ν₀ = 0.93 × 10⁻⁶ m²/s, **τ* = 3.6 Pa**, frictionless 0.58, frictional 0.45, with η = ν₀ρ_s(φ_J − Φ)⁻² (Shi & Zhao 2024, arXiv 2311.14408) [V]. **[!]** Their text labels φ₀ and φ_m the other way round from WC. Physically the frictionless value 0.58 is the larger one. Other reports give τ* from 2.6 to 8 Pa and Σ* = 10.2 Pa [S]. **Σ* depends on the f-form. Never mix a fit made with one form with the other.**

**DST onset packing fraction** [C]. For η ∝ (φ_J − φ)⁻² with f = exp(−σ*/σ):

**φ_DST = φ₀ − 2e^{−1/2}(φ₀ − φ_m)**

This is 0.4220 with Han's φ's and 0.4223 with Shi & Zhao's, matching the 0.43 they quote. The derivation: the slope dγ̇/dσ = 0 gives (φ₀ − φ)/(φ₀ − φ_m) = e^{−x}(1 + 2x) with x = σ*/σ, whose maximum is 2e^{−1/2} at x = ½. For the (1 − φ/φ_J)⁻² form I find φ_DST = 0.433 numerically with the inverse f-form, and 0.404 with the WC f-form [C].

**Bounds.** The lubrication contribution caps the effective viscosity at about 4 × 10⁴ η_water for 14 µm cornstarch, yet measured DST viscosities reach ≥ 10⁷ η_water, which is frictional (Brown & Jaeger 2014, *Rep. Prog. Phys.* 77, 046602) [V]. DST occupies a stress window [τ_min, τ_max]. τ_min is roughly independent of φ. τ_max scales with the confining stress γ_surface/a [V].

**Kitchen recipe to φ.** Han's eq. 11 uses moisture ξ = 0.13, internal porosity ψ = 0.31 and ρ_cs = 1.63 g/cm³, with water as solvent [C]:

| cornstarch:water by mass | 1.0:1 | 1.2:1 | 1.25:1 | 1.5:1 | 1.6:1 |
|---|---|---|---|---|---|
| φ (Han scale) | 0.465 | 0.517 | 0.528 | 0.581 | 0.600 |
| density (g/cm³) | 1.20 | 1.23 | 1.23 | 1.25 | 1.26 |

Classic oobleck (≈ 1.2:1 by mass) therefore sits at φ ≈ 0.52 on this scale. That is between φ_m = 0.452 and φ₀ = 0.593: fluid at low stress, jammable at high stress. That is exactly the oobleck regime.

#### 3.4.2 Impact-activated solidification and running on oobleck

- **Waitukaitis & Jaeger 2012** (*Nature* 487, 205, DOI 10.1038/nature11187): impact on cornflour/water creates a *dynamic jamming front* that turns compressible fluid into a rigidly jammed region growing much faster than the impactor. The stresses come from momentum transfer to this growing solid ("added mass") [S]. Ultrasound later showed it is **shear jamming without a measurable rise in φ** (Δφ ≤ 0.006–0.02), and the jammed region liquefies once the impactor stops (Han, Peters & Jaeger 2016, *Nat. Commun.* 7, 12243) [S].
- **Front-speed constitutive law** (Han et al. 2018) [V]: **Σ = ρ k U₀²**, with k = U_f/U₀ = 1/γ_∞ and **γ_∞ = γ* ln[(φ₀ − φ_m)/(φ − φ_m)]**. That gives [C]:

| φ | 0.47 | 0.50 | 0.52 | 0.53 | 0.54 | 0.55 |
|---|---|---|---|---|---|---|
| k = U_f/U₀ | 2.47 | 4.71 | 6.96 | 8.57 | 10.8 | 14.0 |
| Σ at U₀ = 1 m/s, ρ = 1630 (kPa) | 4.0 | 7.7 | 11.4 | 14.0 | 17.6 | 22.7 |

  Han et al. note that k can reach about 10, "like running on a liquid ten times denser than water" [V].
- **Running vs walking** (Mukhopadhyay, Allen & Brown 2018, *PRE* 97, 052604). Added mass alone explains support only for pool depth > 1.2 m and foot speed > 1.7 m/s. In shallower pools the dynamically jammed region spans to the bottom and carries the load [S]. Companion paper: Maharjan et al. 2018, *PRE* 97, 052602.
- **Stop-go settling.** A sphere settling in cornstarch oscillates in speed and, near the bottom, stops and restarts repeatedly (von Kann, Snoeijer & van der Meer 2011, *PRE* 84, 042301) [S]. The unified DST branch produces this kind of jam, creep, unjam cycle (§4.7).

#### 3.4.3 "Cornstarch monsters": vertically vibrated layers

Merkt, Deegan, Goldman, Rericha & Swinney 2004 (*PRL* 92, 184501, arXiv nlin/0311026) [V]:

- **Setup.** A 0.5 cm deep layer of cornstarch (23.22 g) in density-matched CsCl solution (36.78 g, 1.68 g/cm³), driven at **f = 50–180 Hz** with peak acceleration **a ≤ 27 g**.
- **Persistent holes appear above a ≈ 10 g.** They form only after a finite perturbation: an indentation deeper than 50 % of the layer and 0.4–2.0 cm wide.
- **Hole size.** About 4 mm across at 120 Hz and 6 mm at 180 Hz. Holes last more than 10⁵ cycles and their radius oscillates by about 15 % at the drive frequency.
- **Higher accelerations.** Above about 17 g the rim goes unstable (fingers, hole division). Higher still, the state delocalises and the surface is covered in erratic undulations.

Deegan 2010 (*PRE* 81, 036319) attributes the persistence to **stress hysteresis** in the shear-rate response, not to shear thickening per se [S]. The lagged-f model has exactly this kind of history dependence. **[!]** Whether a 2D MPM layer reproduces holes and fingers is untested. Treat it as a hypothesis for the prototype phase.

### 3.5 Viscoelastic: Maxwell, Kelvin–Voigt, UCM/Oldroyd-B (Silly Putty, slime)

| Model | 1D law | Creep under τ₀ | Relaxation after γ₀ | SAOS |
|---|---|---|---|---|
| Maxwell (1867) | τ + λτ̇ = ηγ̇, λ = η/G | γ = τ₀/G + τ₀t/η | τ = Gγ₀e^{−t/λ} | G′ = Gω²λ²/(1+ω²λ²), G″ = Gωλ/(1+ω²λ²) |
| Kelvin–Voigt | τ = Gγ + ηγ̇ | γ = (τ₀/G)(1 − e^{−Gt/η}) | stress steps to Gγ₀ and stays there | G′ = G, G″ = ηω |
| UCM / Oldroyd-B (Oldroyd 1950) | τ_p + λ τ_p^∇ = 2η_p D; total σ = −pI + 2η_s D + τ_p | — | — | steady shear: τ_xy = (η_p+η_s)γ̇, **N₁ = 2η_p λ γ̇²**, N₂ = 0 |

Startup of shear for Maxwell: τ(t) = ηγ̇(1 − e^{−t/λ}). The **Deborah number** De = λ/t_obs (Reiner 1964, *Physics Today* 17(1), 62) decides solid-like (De ≫ 1) versus liquid-like (De ≪ 1).

Saramito's EVP family combines Oldroyd viscoelasticity with HB plasticity (Saramito 2009, *JNNFM* 158, 154, DOI 10.1016/j.jnnfm.2008.12.001) [V]:

(1/(2μ)) τ^□ + max(0, (|τ_d| − τ₀)/(2ⁿ k |τ_d|ⁿ))^{1/n} τ = D(v), with σ = −pI + 2ηD + τ

Here τ^□ is the Gordon–Schowalter derivative. Below yield this is a Kelvin–Voigt solid; above yield, a nonlinear viscoelastic fluid. Rheo's unified model is the finite-strain (b̄ₑ) cousin of this family, the Yue/Simo flavour (§4.3).

**Silly Putty** (Cross 2012, *Am. J. Phys.* 80, 870, DOI 10.1119/1.4732086) [S]:

- stress relaxes with τ ≈ 0.1 s (about 0.025 s under large impact force);
- Young's modulus for rapid deformation E ≈ 1.7 MPa, so G = E/3 ≈ 567 kPa for an incompressible solid;
- slow-compression viscosity ≈ 8 × 10⁴ Pa·s;
- consistency check: η/G = 0.141 s [C]. A single Maxwell mode fits.

**PVA–borax slime** (2.75 wt % PVA, 1.25 wt % borax; Ramlawi, Hossain, Shetty & Ewoldt 2024, arXiv 2402.19357) [V]:

- "nearly Maxwellian", with mean relaxation time **τ₀ = 0.402 s** and plateau compliance J₀ = 1/G₀ = 0.9 × 10⁻³ Pa⁻¹, so **G₀ ≈ 1.11 kPa and η₀ = G₀τ₀ ≈ 447 Pa·s** [C];
- it "bounce[s] upon impact" yet creeps under its own weight over tens of seconds [V];
- activation energy of the borate–diol complex dissociation is about 42 kJ/mol (Schultz & Myers 1969, *Macromolecules* 2, 281) [S]. Use it as E_a for the slime's λ.

### 3.6 Thixotropy: Moore, Coussot (yogurt, bentonite, quicksand)

**Moore (1959)** structure kinetics (Moore 1959, *Trans. Br. Ceram. Soc.* 58, 470; reviewed in Mewis & Wagner 2009, *Adv. Colloid Interface Sci.* 147–148, 214, and Larson & Wei 2019, *J. Rheol.* 63, 477) [S]:

- **dλ/dt = a(1 − λ) − b γ̇ λ**, with λ = 1 fully built and 0 fully broken. a (s⁻¹) is the build-up rate and b (–) the breakdown coefficient. Moore's viscosity is η = η_∞ + cλ.
- Steady state λ_ss = a/(a + bγ̇).
- Step response at constant γ̇: **λ(t) = λ_ss + (λ₀ − λ_ss) e^{−(a + bγ̇)t}** [C, V8].
- General form: dλ/dt = −k₁γ̇^a λ^b + k₂γ̇^c(1 − λ)^d [S].

**Coussot et al. 2002** viscosity bifurcation (*J. Rheol.* 46, 573; *PRL* 88, 175501) [S]: dλ/dt = 1/θ − αγ̇λ, η = η₀(1 + λⁿ). Bentonite, a polymer gel and laponite all show a critical stress. Below it the viscosity diverges with time; above it the flow is finite and accelerates (avalanche). Rheo gets the same physics from the bounded Moore λ with a steep k(λ) = k₀(1 + βλ^m). The steady curve τ(γ̇) = k₀(1 + β λ_ss^m)γ̇ is non-monotonic. Example with k₀ = 0.05, β = 2 × 10⁴, m = 3, a = 0.1, b = 1: a local maximum **τ = 14.8 Pa at γ̇ = 0.050 s⁻¹** and a local minimum 0.25 Pa at 3.2 s⁻¹. That is the bifurcation, and under stress control the material either stops or avalanches [C, V9].

**Quicksand** (Khaldoun, Eiser, Wegdam & Bonn 2005, *Nature* 437, 635, DOI 10.1038/437635a) [S]:

- natural quicksand is fine sand, clay and salt water;
- at rest its viscosity slowly grows (clay ageing);
- at slightly higher stress it liquefies spectacularly: a stress change of less than 1 % moves the steady viscosity by orders of magnitude, "nearly a million" in press summaries;
- after liquefaction it segregates into water-rich and sand-rich phases, so the trapped body is held by dense sediment;
- density ≈ 2 g/cm³ against ≈ 1 g/cm³ for a person, so a body cannot be pulled fully under (Archimedes).

**[!]** The single-phase toy cannot segregate. Fake the "trap" by speeding up structure rebuild once flow stops, and give quicksand a high vibration sensitivity w_vib (§4.2).

**Yogurt** (stirred). Thixotropic HB: τ_y of tens of Pa when rested, a few Pa when broken; n ≈ 0.3–0.5; recovery is slow and incomplete [S, Tiu–Boger type structural models]. Toy values are in §6.

### 3.7 Rheopexy (anti-thixotropy)

Structure *builds* under shear and decays at rest, the reverse of Moore. Examples are gypsum pastes, some printing inks and lubricants, and some polymer–colloid mixtures [S, Mewis & Wagner 2009; Larson & Wei 2019]. The unified kinetics (§4.2) cover it with build rate A₁γ̇ and rest decay B₀:

dλ/dt = (A₀ + A₁γ̇)(1 − λ) − (B₀ + B₁γ̇)λ

Thixotropy is A₀ > 0, B₁ > 0; rheopexy is A₁ > 0, B₀ > 0. No preset uses it yet. "Rheopectic cream" is an optional extra row (§6.4).

### 3.8 Magnetorheological (MR) fluids

**Composition.** Micron carbonyl iron (3–5 µm, saturation magnetisation about 2.15 T for iron) at 20–45 % by volume in oil, water or glycol. Pigment-size (≈30 nm) oxide fluids are limited to about 5 kPa (Yang 2001 PhD thesis, UIUC, Ch. 2) [V].

**Bingham with field-dependent yield.** τ = τ₀(H) sgn(γ̇) + η γ̇, or HB to capture off-state thinning (Yang 2001, eqs. 2.1–2.3) [V].

**Carlson's empirical laws** (Carlson, in Schwartz (ed.), *Smart Materials*, CRC 2009, ch. 17; quoted in a COMSOL 2016 paper [V]). H is in A/m, τ in Pa, B in T:

- **τ_y(H) = C · 271 700 · φ^1.5239 · tanh(6.33 × 10⁻⁶ H)**, with C = 0.95 (silicone oil), 1.0 (hydrocarbon oil) or 1.16 (water).
- **B = 1.91 φ^1.133 [1 − exp(−10.97 μ₀H)] + μ₀H.**

**LORD MRF-132DG datasheet** (DS7015) [V]:

- viscosity 0.112 ± 0.02 Pa·s at 40 °C, as the slope between 800 and 1200 s⁻¹;
- density 2.95–3.15 g/cm³, solids 80.98 wt %;
- operating range −40 to +130 °C;
- the yield-vs-H plot runs to about 50–60 kPa by 250–350 kA/m.

From the wt % I get φ ≈ **0.315** and an implied density of 3.06 g/cm³, which matches [C]. The **MRF-132LD** off-state (Yang Table 2.1) is η = 0.94 Pa·s at 10 s⁻¹ and 0.33 at 50 s⁻¹. A Bingham fit gives **τ_y0 = 7.6 Pa, μ_p = 0.178 Pa·s** [C].

Carlson's laws at φ = 0.315, C = 1 (τ_y,sat = 46.7 kPa) [C]:

| H (A/m) | 40 (Earth) | 400 | 1 000 | 4 000 | 10 000 | 20 000 | 50 000 | 100 000 | 200 000 | 300 000 |
|---|---|---|---|---|---|---|---|---|---|---|
| B in the fluid (mT) | 0.33 | 3.3 | 8.3 | 32.7 | 79 | 149 | 320 | 512 | 735 | 885 |
| τ_y (Pa) | 11.8 | 118 | 296 | 1 183 | 2 954 | 5 884 | 14 314 | 26 172 | 39 844 | 44 678 |

- Initial susceptibility χ₀ = 1.91 φ^1.133 × 10.97 = 5.66 (μ_r = 6.66); M_s = 411 kA/m [C].
- **[!]** At very low field, real MR yield grows like H² (dipolar chains) and Earth's field shows nothing visible. Carlson's tanh is linear there and predicts 12 Pa at 40 A/m. **Subtract the launch-time magnetometer baseline and add a dead zone of about 100 µT** (§4.2 d).

**Typical maxima.** MR: 50–100 kPa at about 250 kA/m, plastic viscosity 0.1–10 Pa·s, −40 to 150 °C, 3–4 g/cm³, energy density 0.1 J/cm³. ER: 2–5 kPa at about 4 kV/mm, 0.1–1.0 Pa·s, +10 to 90 °C, 1–2 g/cm³, 0.001 J/cm³ (Yang Table 2.2, after Carlson & Spencer) [V].

**Response time.** For MRF-132DG in shear mode, T₉₀ = 0.8–1.4 ms (shorter at higher shear rate) with about 0.4 ms dead time (Kubík et al. 2022, *Sci. Rep.* 12, 10612, DOI 10.1038/s41598-022-14718-5) [S]. Device-level response is 10–20 ms, limited by the coil and magnetic circuit [S]. Model it as a first-order lag with T₆₃ ≈ 1 ms, which is instant at 60 fps and visible in slow-motion.

**Magnetic body force** (for MR "jumping to the magnet"): **f = μ₀ M(|H|) ∇|H|**, with μ₀M from Carlson's B–H. Take a 1 cm³ NdFeB magnet (B_r = 1.3 T, m = 1.03 A·m²) on axis [C]:

| r | H | B₀ | τ_y | f (vs ρg = 3.0 × 10⁴ N/m³) |
|---|---|---|---|---|
| 1 cm | 165 kA/m | 207 mT | 36.4 kPa | 2.3 × 10⁷ N/m³ |
| 2 cm | 20.6 kA/m | 25.9 mT | 6.05 kPa | 3.9 × 10⁵ N/m³ |
| 3 cm | 6.1 kA/m | — | 1.8 kPa | 2.5 × 10⁴ N/m³ |
| 5 cm | 1.3 kA/m | — | 0.39 kPa | 7.3 × 10² N/m³ |

Clamp the force (§4.8).

### 3.9 Electrorheological (ER) fluids

- **Conventional ER.** τ_y ∝ E² (polarisation). Using about 3 kPa at 3 kV/mm, **α = 3.33 × 10⁻¹⁰ Pa·m²/V²** [C], so 333 Pa at 1 kV/mm.
- **Giant ER** (urea-coated nanoparticles; Wen, Huang, Yang, Lu & Sheng 2003, *Nat. Mater.* 2, 727, DOI 10.1038/nmat993): yield **130 kPa**, rising **near-linearly** with E (about 26 Pa per V/mm at 5 kV/mm) [S].
- Response is in milliseconds. The phone has no E-field sensor, so drive it from a "Volts" knob (0–5 kV/mm) through the same τ_field slot as MR, with law E² or E.

### 3.10 Ferrofluids and the Rosensweig (normal-field) instability

Ferrofluids are stable nanoparticle colloids: essentially Newtonian, with no yield stress (only a weak magnetoviscous effect). Under a normal field, the flat surface breaks into hexagonal spikes once M exceeds (Cowley & Rosensweig 1967, *J. Fluid Mech.* 30, 671; Rosensweig 1985, *Ferrohydrodynamics*):

- **critical magnetisation M_c² = (2/μ₀)(1 + 1/r₀)√(g Δρ σ)**, with r₀ = √(μ_c μ_t)/μ₀ (chord and tangent permeabilities). For a linear fluid r₀ = μ_r [S];
- **wavelength λ_c = 2π√(σ/(g Δρ))**;
- **inviscid deep-layer dispersion relation ρω² = ρgk + σk³ − μ₀M² [r₀/(1 + r₀)] k²** (my form). At M = M_c it has a double root at k_c = √(ρg/σ), which I verified numerically [C].

**Worked example, Ferrotec APG 512a** (Gollwitzer et al. 2009, arXiv 0904.3864, Table 1 [V]: σ = 30.57 mN/m, ρ = 1236 kg/m³, η = 120 mPa·s, M_s = 28.7 kA/m, χ₀ = 1.2023). Under the linear approximation [C]:

- λ_c = **9.98 mm**, M_c = 6 674 A/m, internal H = 5 551 A/m;
- applied **B₀ = μ₀(H + M) = 15.4 mT**, against the paper's single spike at "around 16 mT" in a small dish [V];
- at M/M_c = 1.1 the fastest-growing λ is 7.3 mm with growth rate 61 s⁻¹; at 1.3, 4.8 mm and 148 s⁻¹.

**Can a 2D continuum toy show it?** Not as emergent MPM physics, for three reasons:

1. It needs surface tension, which MPM lacks unless added with CSF on the grid.
2. It needs the magnetic normal traction μ₀M_n²/2 from a self-consistent field around the deformed surface.
3. It needs λ_c resolved by at least about 10 cells (Δx ≤ 1 mm, where Rheo plans 1.5 mm).

**Recommendation [I].** Ferrofluid is a bonus preset: Newtonian with η = 0.12 Pa·s and ρ = 1236. Get spikes from the analytic dispersion relation:

- compute the growth rate and wavenumber k* for the current M;
- seed a cos(k*x) surface perturbation;
- apply a body force confined to a 2–3-cell skin, proportional to (μ₀M² r₀/(1+r₀)) k*² × local surface displacement;
- saturate the amplitude at about 0.5 λ_c.

A vertical 2D slice through a hexagonal pattern shows a row of peaks spaced λ_c, which is the right visual.

### 3.11 Temperature effects (summary)

| Class | What T does | Model in Rheo |
|---|---|---|
| Newtonian liquids | η falls strongly (×65 for honey from 10 to 60 °C) | a_T on k (Arrhenius E_a; VFT optional) |
| Food pastes (ketchup, mayo, yogurt) | k and τ_y fall mildly; mayo breaks if heated (emulsion), not modelled | a_T with small E_a (≈10–15 kJ/mol [I]) |
| Oobleck | solvent η_s follows water (E_a ≈ 17.5 kJ/mol); σ* barely moves | a_T on η_s only. Stress-controlled DST onset is unchanged, rate onset shifts |
| Slime | λ and η fall with E_a ≈ 42 kJ/mol (borate complex) | a_T on k (G fixed) |
| Lava | η and τ_y both rise steeply on cooling (crystallisation) | a_T and a_Ty with E_a ≈ 171 kJ/mol [C from S] over 1100–1200 °C [!] |
| MR fluid | carrier viscosity falls; τ_y nearly unchanged | a_T on k only |
| Honey/glycerol | glass-like curvature | VFT if the Heat knob spans more than about 40 K |

For lava, E_a = R ln(167/116)/(1/1388.15 − 1/1423.15) = 171 kJ/mol [C], from the two pāhoehoe field values in §3.3 [S]. Render lava emission from T (blackbody colour) and let cooling raise τ_y. That gives crusting and levées for free.

---

## 4. The unified constitutive model

One per-particle update covers every class in §3. Part (a), §4.1–4.9, is the explicit form the **CPU MLS-MPM oracle** (Swift, Double) runs, step by step. Part (b), §4.10, maps the same update onto **PB-MPM's position-based iterations** on the GPU and corrects `oss-engine-survey.md` §7.3 where it disagrees.

### 4.1 State and parameters

**Per-particle rheology state** (32 bytes, `RheoState` in Appendix A) [C: compiled for iOS, stride checked from Swift]:

| Field | Meaning | Units | Initial value |
|---|---|---|---|
| `b11, b12, b22` | isochoric elastic left Cauchy–Green tensor b̄ₑ (symmetric, det = 1) | – | 1, 0, 1 |
| `J` | elastic volume ratio (PB-MPM's `liquidDensity` plays this role) | – | 1 |
| `lam` | structure λ ∈ [0, 1] (1 = fully built) | – | 1 (rested) |
| `f` | fraction of frictional contacts (DST) ∈ [0, 1] | – | 0 |
| `T` | temperature | K | 293.15 |
| `gdotP` | last plastic shear rate (render and diagnostics only) | 1/s | 0 |

b̄ₑ replaces PB-MPM's 2×2 `deformationGradient` for every Rheo material (3 floats instead of 4). The rotation in Fₑ is not needed because every material is isotropic.

**Per-material parameters** (44 floats, 176 bytes, `RheoMaterial` in Appendix A). They are grouped in §4.2 and tabulated per preset in §6.

### 4.2 Stress, flow law and modulators

**Stress (Kirchhoff, planar d = 2)**, after Yue et al. 2015 eq. 2 with d = 2 [V]:

τ = G·dev b̄ₑ + ½K(J² − 1)·I,  with σ = τ/J (Cauchy)

- G is the shear modulus (Pa) and K the 2D bulk modulus (Pa, §4.5).
- dev A = A − ½(tr A)I.
- The volumetric term comes from Yue's W_v = ½K[½(J² − 1) − ln J].

**Flow law: the plastic rate as a function of stress.** The equivalent shear stress τ̄ = ‖dev τ‖_F/√2 (§0.2) drives a scalar plastic rate:

γ̇ₚ(τ̄) = φ₀·τ̄ + ((τ̄ − τ_y)₊/k)^{1/n} + φ_f·(τ̄ − τ_f)₊      (Eq. 4.1)

| Branch | Parameters | Units | Used for |
|---|---|---|---|
| Newtonian fluidity | φ₀ = 1/η₀ | 1/(Pa·s) | zero-shear plateau (Cross/Carreau mapping, §3.2), DST suspension viscosity |
| Herschel–Bulkley | τ_y, k, n (0.15 ≤ n ≤ 1) | Pa, Pa·sⁿ, – | every paste, power-law fluids (τ_y = 0), Newtonian (τ_y = 0, n = 1, k = η) |
| Failure | τ_f, φ_f | Pa, 1/(Pa·s) | jammed oobleck (τ_jam, s/η_post); optional elastic-strain limiter |

Each branch is monotone and convex in τ̄ for n ≤ 1, so the sum is too (§4.3). Restrict n ≤ 1; shear thickening comes from the DST block, not from n > 1.

**Modulators.** Structure λ, contact fraction f, temperature T and field H only change the branch parameters.

(a) **Temperature** (Arrhenius, §3.1, §3.11):
- a_T = exp[(E_a/R)(1/T − 1/T_ref)], with R = 8.314 462 618 J/(mol·K).
- a_Ty is the same expression with E_a,y.
- Effect: k ← a_T·k, φ₀ ← φ₀/a_T and τ_y ← a_Ty·τ_y. For oobleck, η_s ← a_T·η_s.

(b) **Structure (thixotropy and rheopexy)**, generalised Moore (§3.6–3.7):
- dλ/dt = (A₀ + A₁γ̇_s)(1 − λ) − (B₀ + B₁γ̇_s)λ.
- The driving rate is γ̇_s = (1 − w_vib)·γ̇ₚ + w_vib·γ̇_tot. The plastic rate breaks structure; the total rate (including elastic wobble) adds only the w_vib share. That share is quicksand's "liquefies when shaken".
- In Moore's form, **A₀ = 1/t_build** (s⁻¹) and **B₁ = k_break** (–).
- Yield: τ_y = a_Ty(τ_y0 + Δτ_λ·λ^m). Consistency: k = a_T·k₀(1 + β·λ^m).
  - τ_y0 is the fully broken yield stress.
  - Δτ_λ is the extra yield stress of rested structure.
  - m = 3 with large β gives the Coussot viscosity bifurcation (§3.6).
- Update, implicit and unconditionally stable, keeping λ ∈ [0, 1] for any dt:

  λ ← (λ + A·dt)/(1 + (A + B)·dt), with A = A₀ + A₁γ̇_s and B = B₀ + B₁γ̇_s.

(c) **Shear jamming (Wyart–Cates, oobleck)**, §3.4:
- **Contact fraction:** df/dt = c·(f_ss(τ̄ₙ) − f), with c = γ̇_tot/γ* + 1/t_melt.
  - The strain term is the differential form of Han et al.'s g(γ) = 1 − e^{−γ/γ*}. From f = 0 under steady stress it gives f = f_ss(1 − e^{−γ/γ*}) exactly [C, analytic].
  - 1/t_melt lets a jammed region relax at rest (Han 2016: the region liquefies once the impactor stops) [I].
- **Steady contact fraction:** f_ss = 1 − exp(−τ̄/σ*) (WC/Han form, `fForm = 0`) or exp(−σ*/τ̄) (`fForm = 1`). **Never mix σ* fitted with one form into the other** (§3.4.1).
- **Lagged stress.** τ̄ₙ is the start-of-step stress recomputed from b̄ₑ. Lagging it keeps Eq. 4.1 a closed-form monotone law within the step. Using the current-iteration stress σ = μ_eff·γ̇ instead (survey rule 5) creates a positive feedback inside one step (more stress → more contacts → more viscosity → more stress) [I].
- **Update:** f ← (f + c·dt·f_ss)/(1 + c·dt), which is implicit.
- **Jamming packing fraction and gap:** φ_J = f·φ_m + (1 − f)·φ₀, and gap = 1 − φ/φ_J.
- **Flowing branch:** η_fluid = a_T·η_s/max(gap, Δφ_min)², with s = smoothstep((Δφ_min − gap)/w_jam).
- **Effective branch parameters** [I, tested in §4.7]:
  - φ₀ = 1/[(1 − s)·η_fluid + s·G·t_jam];
  - τ_y = τ_field;
  - k = 0;
  - τ_f = τ_jam when s > 0;
  - φ_f = s/η_post.
- **Strain-induced unjamming:** f ← f/(1 + dt·φ_f·(τ̄ − τ_f)₊/γ_break).

(d) **Field-driven yield (MR, ER)**, §3.8–3.9:
- **MR law** (Carlson) with a toy clamp: τ_field = min(τ_sat·tanh(|H|/H_sat), c_clamp·G).
  - τ_sat = C·271 700·φ^1.5239 Pa; C = 1, φ = 0.315 gives 46.7 kPa.
  - H_sat = 1/(6.33 × 10⁻⁶) = 1.58 × 10⁵ A/m.
  - c_clamp = 0.05 keeps the yield strain ≤ 5 %.
- **Response lag:** first order with T₆₃ ≈ 1 ms (§3.8), H_eff ← H_eff + (H − H_eff)(1 − e^{−dt/T₆₃}).
- **Field from the phone:** H = gain·max(|B_meas − B_launch| − 100 µT, 0)/μ₀. B_launch is the magnetometer baseline sampled at launch, and gain is the Magnet knob.
- **Body force**, clamped (§4.8): f = μ₀M(|H|)·∇|H|.
- **ER:** τ_field = αE² (α = 3.33 × 10⁻¹⁰ Pa·m²/V²) or the GER linear law, driven from a Volts knob.

(e) **Vibration** enters as the body force g_eff(t) = g + A·ω²·sin ωt·ĝ and through w_vib. A ≤ 2 mm and f_drive ≤ 200 Hz come from the mic envelope [I].

### 4.3 The return map: derivation, conventions and solvers

**Derivation** (Yue et al. 2015 eqs. 13–18 [V], rewritten for d = 2 and rheometer units):

1. **Elastic predictor:** b̄ₑ,tr = f̄ b̄ₑ,ₙ f̄ᵀ, where f = I + Δt·C and f̄ = f/√det f. Renormalise to det 1.
2. **Plastic corrector**, backward Euler of the Simo flow rule L_v b̄ₑ = −(2/d)·tr(b̄ₑ)·γ·ŝ:

   b̄ₑ,ₙ₊₁ − b̄ₑ,tr = −(2/d)·Δt·tr(b̄ₑ,ₙ₊₁)·γ·ŝₙ₊₁

   - ŝ is deviatoric, so tr b̄ₑ,ₙ₊₁ = tr b̄ₑ,tr.
   - Multiplying the deviatoric part by G gives sₙ₊₁ − s_tr = −2μ̃Δt·γ·ŝₙ₊₁, with **μ̃ = G·tr(b̄ₑ,tr)/d**.
   - sₙ₊₁ and s_tr are parallel, so only the magnitude changes.
3. **To rheometer units:** ‖s‖ = √2·τ̄, and the equivalent plastic shear rate is γ̇ₚ = √2·γ (from D_p = γŝ). That gives the **scalar return equation**:

   **τ̄ₙ₊₁ = τ̄_tr − μ̃·Δt·γ̇ₚ(τ̄ₙ₊₁)**      (Eq. 4.2)

4. **Corrector:**
   - Scale the deviator: dev b̄ₑ,ₙ₊₁ = dev b̄ₑ,tr·(τ̄ₙ₊₁/τ̄_tr), and keep the trace.
   - Renormalise det → 1 (Yue: "the determinant ... will always have a value equal to or slightly larger than 1. We thus renormalize" [V]).
   - Diagnostic: γ̇ₚ = (τ̄_tr − τ̄ₙ₊₁)/(μ̃Δt).

**Conversion to Yue's parameters** [C]:
- Yue's yield is Φ = ‖s‖ − √(2/3)σ_Y, and γ = (Φ/η_Yue)^{1/h}.
- Matching gives **σ_Y = √3·τ_y**, **η_Yue = 2^{(n+1)/2}·k** and **h = n**.
- For Bingham, η_Yue = 2μ_p.
- Yue's closed form, eq. 17 (n = 1), is the same as the n = 1 line below.

**Closed forms** (single active branch):
- **Newtonian or Maxwell** (φ₀ only): τ̄ₙ₊₁ = τ̄_tr/(1 + μ̃Δt·φ₀).
  - In the small-strain limit this is the backward-Euler Maxwell update τ ← (τ + GΔtγ̇)/(1 + Δt/λ), with λ = η/G.
- **Bingham** (n = 1): τ̄ₙ₊₁ = (τ̄_tr + μ̃Δt·τ_y/k)/(1 + μ̃Δt/k) when τ̄_tr > τ_y. Otherwise τ̄ₙ₊₁ = τ̄_tr: elastic, the plug.
- **Bingham plus failure branch**, both active: τ̄ = (τ̄_tr + μ̃Δt·τ_y/k + μ̃Δt·τ_f·φ_f)/(1 + μ̃Δt/k + μ̃Δt·φ_f).

**Newton for the general sum** [C, `t4_newton_f32.py`, `t5_unified_flow_f32.py`]:
- **Residual:** r(t) = t − τ̄_tr + μ̃Δt·γ̇ₚ(t). For n ≤ 1, r is increasing and convex on [0, τ̄_tr].
- **Start:** t₀ = the minimum of the single-branch roots:
  - τ̄_tr/(1 + μ̃Δt·φ₀);
  - τ_y + min(X, k(X/(μ̃Δt))ⁿ), with X = τ̄_tr − τ_y;
  - max(τ_f, (τ̄_tr + μ̃Δt·φ_f·τ_f)/(1 + μ̃Δt·φ_f)).
- **Why it converges:** adding branches only raises γ̇ₚ, so every single-branch root lies to the right of the joint root. Newton from the right on an increasing convex function then converges monotonically, with no bracketing and no safeguard.
- **Iteration count:**
  - In float32 with n ∈ [0.2, 1] over 7 decades of stress, worst relative error is 1.1 × 10⁻⁷ after 4 iterations (n = 0.2: 7.8 × 10⁻², 9.4 × 10⁻³, 1.5 × 10⁻⁴, 1.1 × 10⁻⁷ after 1–4).
  - The full three-branch law needs 5 iterations for float32 precision (6.8 × 10⁻⁷).
  - The GPU kernel uses a fixed 5. The Double oracle iterates to |Δt| ≤ 10⁻¹⁴·τ̄_tr (at most 40).
- **Clamp:** t ← max(t − r/r′, 0). For n > 1 (not used) Newton must run on g = γ̇ₚ instead, which is convex in g.

### 4.4 Per-particle algorithm for the CPU oracle (explicit MLS-MPM, Double)

The oracle is plain explicit MLS-MPM (Hu et al. 2018), using quadratic B-splines with D⁻¹ = 4/Δx² and SI units throughout. Per substep:

1. **P2G.** For each particle p and node i:
   - m_i += w_ip·m_p;
   - (mv)_i += w_ip·[m_p(v_p + C_p·(x_i − x_p)) − Δt·V⁰_p·(4/Δx²)·τ_p·(x_i − x_p)].
   - τ_p is the Kirchhoff stress from the committed state. V⁰_p is the reference volume (m² per unit depth in 2D).
2. **Grid.** v_i = (mv)_i/m_i + Δt·g_eff. Then:
   - Hele-Shaw drag (§4.10.5): v_i ← v_i/(1 + Δt/t_HS).
   - Colliders and walls.
   - Optional MR body force.
3. **G2P.** v_p = Σ w_ip v_i, C_p = (4/Δx²)·Σ w_ip v_i (x_i − x_p)ᵀ and x_p += Δt·v_p. Here C_p is ∇v (c11 = ∂vₓ/∂x, c12 = ∂vₓ/∂y, and so on).
4. **Constitutive update** with C_p. This is the function `rheoUpdate` (Appendix A in MSL, Appendix B in Swift):
   1. **Lagged stress:** τ̄ₙ = G·√(dₙ² + b12²), with dₙ = ½(b11 − b22).
   2. **Kinematics:** f = I + Δt·C and J ← J·det f. Then f̄ = f/√det f, b̄_tr = f̄ b̄ f̄ᵀ, rescaled to det 1.
   3. **Trial values:** d = ½(b11 − b22) and τ̄_tr = G√(d² + b12²); tr = b11 + b22, μ̃Δt = G·(tr/2)·Δt. Total rate: γ̇_tot = √((c11 − c22)² + (c12 + c21)²).
   4. **Modulators** (§4.2):
      - a_T, a_Ty, τ_field;
      - for DST, the f update and the jam blend;
      - the effective (φ₀, τ_y, k, n, τ_f, φ_f).
   5. **Return map** when φ₀ > 0, or τ̄_tr > τ_y with k > 0, or τ̄_tr > τ_f:
      - solve Eq. 4.2 (§4.3);
      - scale (d, b12) by t/τ̄_tr;
      - rebuild b11 = d + tr/2 and b22 = −d + tr/2;
      - renormalise det → 1;
      - γ̇ₚ = (τ̄_tr − t)/(μ̃Δt).
   6. **DST unjamming** (§4.2 c).
   7. **Structure:** λ ← (λ + A·Δt)/(1 + (A + B)·Δt).
   8. **Volume.** J ← clamp(J, J_min, J_max) and τ_v = ½K(J² − 1).
      - If τ_v > J·p_tens (Cauchy tension above the cap), project J to (p_t + √(p_t² + K²))/K. That root solves ½K(J² − 1) = J·p_t: tearing or cavitation, a plastic dilation.
      - For liquids, also apply the PB-MPM grid-volume correction J ← J + 0.1·(J_grid − J) when J_grid < 1 (`gridToParticle.wgsl:78-85` [V]; survey §6.1).
   9. **Return** τ = G·(b̄ − ½ tr b̄·I) + τ_v·I.

The order matches standard MLS-MPM: stress from the state at tⁿ, the velocity gradient from the new grid velocity. Kinematics, return map and λ all use the same C_p, so the update stays first order in time and keeps exact stationary states.

### 4.5 Planar 2D specialisation

- **2×2 tensors throughout, with d = 2** in dev, μ̃ and the det-renormalisation (det^{−1/2}).
- **Equivalent measures** (§0.2):
  - τ̄ = √(s11² + s12²) = G√(d² + b12²);
  - γ̇_tot = √((c11 − c22)² + (c12 + c21)²);
  - in simple shear u = γ̇y both equal the rheometer τ_xy and γ̇.
- **Plane strain.** For an incompressible viscoplastic flow with D_zz = 0, associated flow gives s_zz = 0. In-plane von Mises then equals Tresca and the 2×2 law is exact.
  - For the elastic part, a d = 2 neo-Hookean differs from a 3D plane-strain neo-Hookean only at O(γₑ²).
  - γₑ ≤ τ_y/G ≤ 0.05 here, so the difference is at most about 0.25 % [I, analytic order].
- **Bulk modulus.** In plane strain the in-plane bulk modulus is **K₂D = K₃D + G/3** (λ_L + μ). The P-wave modulus is M = K₂D + G, so c_p = √((K₂D + G)/ρ) and c_s = √(G/ρ).
- **Per unit depth.** Particle volume V⁰ = (Δx/ppc)² and mass ρV⁰. Forces are per unit depth (N/m), and the Hele-Shaw drag (§4.10.5) stands in for the missing third dimension.

### 4.6 What the backward-Euler map guarantees, and what it does not

1. **Stability.** The map is unconditionally stable for any viscosity, because the stress can never exceed the elastic trial.
   - The explicit force then sees an effective viscosity η_num = ηGΔt/(η + GΔt) ≤ GΔt.
   - The elastic wave CFL c_s·Δt/Δx ≲ 0.7 therefore also covers the viscous limit [C, §4.10.3: Π = 8η_num·Δt/(ρΔx²)].
2. **Steady flow curves.** In the small-elastic-strain limit, the discrete steady state equals Eq. 4.1 for any Δt.
   - **Correction to §1 item 2.** At finite Weissenberg number Wi = (η_eff/G)·γ̇, the b̄ₑ model under-predicts steady shear stress by about **2·Wi²**.
     - Measured: −0.4 % at Wi = 0.05, −1.9 % at Wi = 0.1, −26 % at Wi = 0.5 and −48 % at Wi = 1 [C, `t1_out.txt` A and D].
     - This is a property of the Simo/Yue flow rule and isochoric renormalisation, not of Δt: errors are independent of Δt for γ̇Δt ≤ 10⁻².
   - So **Newtonian and paste presets need Wi ≤ 0.1 at their working shear rate** (§5.3).
   - For Maxwell materials (slime, putty), the same effect acts as shear thinning above Wi ≈ 0.3. That is qualitatively right for PVA–borax, which thins strongly above 1/λ [S, Ramlawi 2024].
3. **Normal stresses.** N₁ matches upper-convected Maxwell (2ηλγ̇²) only at small Wi: N₁/N₁,UCM = 1.00 at Wi = 0.01, 0.97 at 0.1 and 0.59 at 0.5 [C]. Rod climbing and die swell are therefore under-predicted for Wi ≥ 0.3 [!].
4. **Exponential relaxation is wrong here.** Updating τ ← τe^{−Δt/λ} + … loses viscosity once Δt ≳ λ: it gives 99 %, 90 % and 31 % of ηγ̇ at Δt/λ = 0.02, 0.2 and 2 [C, `t1_out.txt` B]. Backward Euler gives 100 % in all three cases.
5. **Maxwell relaxation accuracy.** The backward-Euler error after time t is about +t·Δt/(2λ²): +1.25 % at t = 1 s, λ = 0.4 s, Δt = 4 ms [C, `t8_out.txt`]. At the oracle's Δt ≈ 7 × 10⁻⁵ s it is negligible for every preset λ ≥ 1 ms.

### 4.7 Oobleck branch behaviour (what the lagged-f law does)

All numbers are [C] from `t1_out.txt` I, `t2_out.txt` I′, J and K, and `gpu_out2.txt`, with φ = 0.52, φ₀ = 0.593, φ_m = 0.452 and η_s = 1 mPa·s.

- **Hysteretic S-curve.** In a rate-controlled ramp of 0.02 s per rate, upward at γ̇ = 14.7 s⁻¹ the stress is 0.89 Pa with f = 0.14. At 21.5 s⁻¹ it jumps, and by 31.6 s⁻¹ it reads 1 767 Pa with f = 0.63 and the material jammed. Downward, the material stays on the upper branch to γ̇ = 1 s⁻¹ (1 354 Pa). That is the hysteresis Deegan 2010 links to the "monsters" (§3.4.3).
- **Impact then hold.** Applying 200 s⁻¹ for 10 ms gives τ_xy ≈ 4.9–5.0 kPa. Holding still, stress relaxes over t_jam (0.05 s) while f climbs to 0.98, then the region melts within about 0.3 s.
  - GPU float32 tracks the CPU Double run to ≤ 5 × 10⁻⁴ in stress through the whole sequence.
  - During the melt the contact fraction f differs by up to 0.04 absolute (0.30 against 0.34 at +0.35 s). The melt is a sensitive transition, so parity tests on f need a ±0.05 band.
- **Slow strain does not jam.** The same strain of 2.0 applied at 2 s⁻¹ ends at τ_xy = 0.085 Pa, with f = 0.017 and no jam. This is the "walk slowly and you sink" behaviour.
- **What is not shown.** Front propagation (Han's U_f/U₀ = 1/γ_∞) needs the spatial solver. That is verification case V11 (§7).

### 4.8 Robustness clamps (all [I] unless marked)

| Clamp | Value | Why |
|---|---|---|
| J ∈ [J_min, J_max] | [0.6, 1.5] | Survives crushing between colliders; PB-MPM clamps `liquidDensity ≥ 0.1` (`particleIntegrate.wgsl:47` [V]) |
| Tensile cap p_tens | Per preset, 0–4 kPa (§6) | Liquids tear and drip instead of acting as rubber |
| det f > 0 | if det(I + ΔtC) ≤ 0.05, rescale C so it equals 0.05 (CFL breach) and count it | The b̄ₑ renormalisation needs det > 0 |
| b̄ₑ renormalisation | rsqrt(b11·b22 − b12²) after every write | Float drift; Yue does the same [V] |
| Newton | fixed 5 iterations, t ≥ 0 | Branch-free GPU code |
| τ_field | ≤ 0.05·G | Yield strain stays elastic-small; G sets the CFL |
| MR body force | ≤ 3ρ|g| per particle | One magnet near the glass would otherwise give 2.3 × 10⁷ N/m³ (§3.8) |
| Structure λ, contact f | implicit updates, then clamp to [0, 1] | Already unconditionally bounded; the clamp guards float rounding |
| Temperature | T ∈ [T_ref − 40 K, T_ref + 80 K] per preset | Arrhenius over- or under-flow; lava uses its own T_ref |
| Arrhenius | a_T ≤ 10⁴ | Glass-like freezing would stall the solver; render a "solid" look instead |
| Velocity | after G2P, ‖v_p‖ ≤ 0.5·Δx/Δt (CFL guard, counted) | The time-dilation governor should trip first (survey §7.4) |

### 4.9 Time-step constraints for the oracle

Take the minimum of:

1. **Elastic wave CFL:** Δt ≤ C_e·Δx/(c_p + |v|_max), with c_p = √((K + G)/ρ) and C_e = 0.4 for quadratic MLS-MPM [C: 1D/2D tests stable at 0.3–0.4]. **This is the only stiffness limit.** Viscosity, yield, thixotropy and DST are implicit (§4.6).
2. **Advection:** |v|_max·Δt ≤ 0.5·Δx. Particles must not skip cells.
3. **Vibration:** Δt ≤ 1/(8·f_drive), at least 8 samples per drive period.
4. **Accuracy of the slow ODEs:** (γ̇/γ* + 1/t_melt)·Δt ≤ 0.5 (DST) and (A + B)·Δt ≤ 0.2 (λ). Both are always met when (1) holds.

For the presets this is 64–74 µs, or 113–130 substeps per 1/120 s frame, at Δx = 1.5 mm and c_p ≈ 7–8 m/s (§5.4). That is fine for an offline Double oracle. The GPU path is governed by §4.10.3 instead.

### 4.10 (b) Mapping onto PB-MPM's position-based iterations (GPU)

The brief fixes the GPU solver as a Metal port of PB-MPM with Rheo's constitutive extensions. **[!] Conflict with the sibling survey.** `oss-engine-survey.md` Revision 2 (§0 decision 3, §6.1) recommends porting only PB-MPM's infrastructure and running explicit MLS-MPM. This section shows the two choices meet:

- Rheo's update can run *inside* PB-MPM's iteration as a compliant constraint.
- With one iteration and a full warm start, that constraint *is* explicit MLS-MPM.

Either decision therefore uses the same constitutive code. The new experiments are in `scratchpad/rheology/pbmpm/`: `pbmpm2d.py`, `t1_shearwave.py`, `t2_stability_map.py`, `t2b_boundary.py` and `t3_warm_beta.py`, with outputs `t1_out.txt`, `t2_out.txt`, `t2b_out.txt` and `t3_out.txt`. They are a numpy 2D PB-MPM that mirrors the `siggraph2024` pass order (`src/sim.js:148-163` at `5a2f438` [V]).

#### 4.10.1 PB-MPM's variables in SI, and the stress-to-B conversion

- **Loop** (Lewin 2024, Alg. 1 [V]): for each iteration, SolveConstraints → P2G → GridUpdate → G2P. After the loop, Integrate. The material solve is `particleUpdatePBMPM.wgsl`; the commit is `particleIntegrate.wgsl` (`siggraph2024`).
- **Variables.** `displacement` d = Δt·v, and `deformationDisplacement` B = Δt·∇v, which is dimensionless and refined by the iterations. PB-MPM stores positions in cells, so d_cells = Δt·v/Δx; B and all stresses are unaffected.
- **Gravity in SI.** Use d_y −= g·Δt²/Δx (cells) instead of `gridSize.y·gravityStrength·Δt²` (`particleIntegrate.wgsl:145` [V]). That line is grid-normalised and is 1/25 of Earth's gravity in Rheo's tank (survey §3.1).
- **Applying a Kirchhoff stress τ inside the iteration.** MLS-MPM adds −Δt·V⁰(4/Δx²)·τ·(x_i − x_p)·w_ip to node momentum. P2G scatters m_p·w_ip·(d + B(x_i − x_p)). The same impulse is therefore

  **B ← B − κ·τ, with κ = 4Δt²/(ρ₀Δx²)** (1/Pa)

  [C: derived; checked by `t3_out.txt` B, where one iteration with τ = τₙ reproduces the exact elastic shear-wave frequency, ω/ω_exact = 0.998–1.000].

#### 4.10.2 Measured: PB-MPM's native "liquid viscosity" in SI

- **Code** (`particleUpdatePBMPM.wgsl:31-33` on `siggraph2024`, `g2p2g.wgsl:370-372` on `main` [V]): `B += r·0.5·(−(B + Bᵀ))`, i.e. **B ← B − r·sym(B)**.
  - This removes the whole symmetric part, *including the trace*. The volume constraint on the next lines (`alpha = 0.5·(1/liquidDensity − tr B − 1)`, `B += liquidRelaxation·alpha·I`) restores the trace.
  - The talk's Algorithm 2 line 6 instead writes D_visc = −(D − tr(D)I). In 2D that is neither deviatoric nor symmetric; it would damp rotation too [V]. Follow the code.
- **Theory [C].** Removing r·sym(B) once equals applying τ = r·sym(B)/κ. With sym(B) = Δt·D, that is a viscosity η = rρΔx²/(8Δt) per iteration, hence

  **ν_eff = r·k·Δx²/(8Δt)** (k = iterations per substep)

- **Measured [C, `t1_out.txt`].** Viscous shear-wave decay at Δx = 1.5 mm, Δt = 1/240 s and k = 1–16 (ν_eff divided by r·k·Δx²/Δt):

  | r | 0.010 | 0.0146 | 0.597 | 0.937 | 0.978 | 0.993 |
  |---|---|---|---|---|---|---|
  | measured coefficient (theory 0.125) | 0.148 | 0.141 | 0.125 | 0.1245 | 0.125 | 0.125 |

  - Linear in k to 3 digits.
  - The excess at small r (+0.023 and +0.016) is the same absolute amount in both columns: the transfers' own numerical diffusion, about 2.3 × 10⁻⁴·kΔx²/Δt (1.25 × 10⁻⁷·k m²/s) at k_wΔx = 0.1.
  - PB-MPM's default (r = 0.01, 5 iterations, 240 Hz) is ν_eff ≈ 4.0 × 10⁻⁶ m²/s at Δx = 1.5 mm: four times water, and it doubles with k.
- **Consequence 1: R(μ) is closed form.** **r = min(1, 8·μ·Δt/(ρ·k·Δx²))**. Survey §7.6 item 4's calibration table and its starting guess r ≈ 1 − exp(−νΔt/(CΔx²)) are unnecessary; keep the shear-wave decay as a regression test (V13).
- **Consequence 2: a hard ceiling** at r = 1: **ν_max = k·Δx²/(8Δt)**. At Δx = 1.5 mm and ρ = 1000:

  | Substep Δt | k | ν_max (m²/s) | η_max (Pa·s) |
  |---|---|---|---|
  | 1/240 s | 5 | 3.4 × 10⁻⁴ | 0.34 |
  | 1/1440 s | 3 | 1.2 × 10⁻³ | 1.2 |
  | 1/1920 s | 3 | 1.6 × 10⁻³ | 1.6 |

  - Honey (η = 15 Pa·s, ν = 1.1 × 10⁻²) is 7–30 times out of reach.
  - A Papanastasiou-regularised plug (μ ≈ τ_y·m ≈ 10⁴–10⁵ Pa·s at m = 1000 s) is 4–5 orders out of reach.
  - Putty (8 × 10⁴ Pa·s) is out of reach too.
  - Above ν_max the relaxation saturates, and the material looks as viscous as the iteration can make it, whatever the preset says.

#### 4.10.3 The EVP update as a compliant constraint ("XPBD-EVP")

Lewin's talk anticipates this: "an XPBD variant of MPM is very likely possible" [V]. Per substep, for each particle:

```
// committed state S_n = (b̄e, J, λ, f, T); d, B from the last G2P; κ = 4Δt²/(ρ0 Δx²)
a      = β · s(S_n)                  // applied deviatoric Kirchhoff stress estimate (s11, s12); β = 1: warm start
a_prev = 0
for it in 0 ..< k:
    (s, θ) = rheoEvaluate(S_n, C = B/Δt)   // §4.4 steps 1–5 with NO state write; θ = 1/(1 + μ̃Δt·γ̇p'(τ̄)), 1 if elastic
    a     += ω/(1 + κ·2G·θ) · (s − a)        // Newton-preconditioned Jacobi step
    Δ      = a − a_prev ; a_prev = a
    B_scatter = B − κ·[[Δ11, Δ12], [Δ12, −Δ11]]
    B_scatter += α_vol · alpha · I            // PB-MPM liquid volume constraint (cold), alpha from J = liquidDensity
    P2G(d, B_scatter) → grid (colliders, Hele-Shaw drag, guardian) → G2P → d, B
S_{n+1} = rheoUpdate(S_n, C = B/Δt)           // §4.4 with state write (b̄e, J, λ, f)
x += d ;  d += g Δt² / Δx  (cells)
```

- **Special case [C, by construction].** k = 1, ω = 0 and β = 1 give B_scatter = B − κ·sₙ, which is exactly explicit MLS-MPM. With α_vol = 0 and the volumetric stress warm-started too, the GPU path becomes the CPU oracle. That is the GPU-versus-CPU parity mode (V14).
- **Stability and accuracy** [C: `t2b_out.txt` and `t3_out.txt`; periodic shear wave, Δx = 1.5 mm, Δt = 1/240 s, volumetric part cold]. Π = κ·2G·θ, which is 8(c_sΔt/Δx)² for an elastic solid.

  | k | Elastic: stable up to Π (fails at) | Viscous (λ = Δt/20): stable up to Π | Accuracy when stable |
  |---|---|---|---|
  | 1 (explicit) | 8 (12) | 3.8 (7.6) | ν_eff/ν = 1.000–1.001; ω/ω_ex = 0.999–1.000 |
  | 2 | 16 (24) | 7.6 (15) | 1.000–1.003 |
  | 4 | 32 (48) | 15 (30) | 1.000–1.007 |
  | 8 | 64 (96) | 30 (61) | 0.999–1.016 |
  | 16, ω = 1.5 | ≥ 128 | — | — |

  - **Rule: Π = κ·2G·θ ≤ 4k**, i.e. **c_s·Δt/Δx ≤ √(k/2)**: 1.22 at k = 3.
  - Viscosity never needs more than this: θ ≤ 1 and η_num ≤ GΔt (§4.6).
- **Cold start (β = 0)** is unconditionally stable in every case tried, up to Dn = νΔt/Δx² = 16. It saturates at the **same ceiling as native relaxation**: ν_eff ≈ kΔx²/(8Δt), measured 0.12–0.13 in those units [C, `t3_out.txt` A]. Native relaxation is the cold-started form of this constraint.
- **Partial warm start β = min(1, 8k/Π) does not help viscous cases**, which still diverge. It stabilises elastic cases only by slowing the waves by √β (ω/ω_ex = 0.73 at β = 1/2 and 0.52 at β = 1/4) [C]. **Do not use it. Raise the substep count instead.**
- **Cost per pass [C, from the rule].** The elastic limit scales as Π ∝ Δt². k substeps buy k² in stiffness; k iterations buy k. For stiffness-limited presets (oobleck jam, putty, lava, MR), explicit substeps are therefore the cheaper currency. Real gravity already forces about one cell per substep (survey §6.1).
  - **Recommended:** k = 2–3. Spend the iterations on what only PB-MPM has: the cold volume constraint (incompressibility without a stiff K, plus grid-volume correction) and collider contacts.
  - **Substep count** = max(⌈Δt_frame·|v|_max/Δx⌉, ⌈Δt_frame·c_s/(√(k/2)·Δx)⌉, 8·f_drive·Δt_frame). §5.4 lists it per preset: 6–20 substeps per 1/120 s frame at k = 3.
- **Extra particle state:** a (2 floats) and a_prev (2 floats), 16 bytes, live only between iterations. The fused `g2p2g` (`main`) keeps the particle in registers across the tile pass. It must write them back, as it already does for B.

#### 4.10.4 Rule-by-rule check of `oss-engine-survey.md` §7.3

| Survey rule (§7.3) | Verdict | Correction |
|---|---|---|
| 1. GNF viscosity via relaxation r = R(μ_eff), Papanastasiou HB (m ≈ 1000 s), Arrhenius on μ, R from a calibration table | **Partly wrong.** R is closed form; relaxation saturates at ν_max = kΔx²/(8Δt), about 0.3–1.6 Pa·s here; it removes the trace as well; the Papanastasiou plug becomes a fluid creeping at ν_max, so incline stoppage (V5) fails | Run the EVP update as the constraint (§4.10.3). Keep native relaxation only for Water-like, with r = 8μΔt/(ρkΔx²) applied to the **deviatoric** symmetric part (B −= r·dev sym B). Arrhenius: a_T on k, φ₀ and η_s in the EVP law (§4.2 a) |
| 2. Yield and plug: shape-matching weight w = clamp(1 − γ̇/γ̇_c) | **Wrong criterion.** Yield is a stress threshold. A rate switch has no τ_y, so h_c = τ_y/(ρg sin θ) and the plug width τ_y/G_p cannot come out; shape-matching stiffness is not SI | The b̄ₑ return map is the plug: elastic where τ̄_tr ≤ τ_y, flowing above. Its stiffness is G, in SI |
| 3. Maxwell: F ← U·Σ^{1−Δt/τ}·Vᵀ after each substep | **Unstable for Δt > τ.** It is forward Euler in log strain: the sign flips for Δt > τ and it diverges for Δt > 2τ. Water-like λ = η/G ≈ 10⁻⁵ s would explode. It also relaxes the volume if applied to the full Σ | Backward Euler: the φ₀ (or n = 1) branch of Eq. 4.2. In log-strain form that is ε_dev ← ε_dev,tr/(1 + Δt/λ) on the isochoric part only, with J untouched |
| 4. Thixotropy: dλ/dt = (1 − λ)/t_build − k_break·γ̇·λ, τ_y = τ_y0·λ | **Equation right, details missing** | Implicit update (§4.2 b), which stays in [0, 1] for any Δt. Drive with γ̇ₚ (plus the w_vib share), not total γ̇. τ_y = τ_y,broken + Δτ·λ^m, so broken yogurt keeps a few Pa; k also depends on λ (β) |
| 5. Jamming: f = exp(−σ*/σ) with σ = μ_eff·γ̇; φ_J; jammed → elastic constraint with high relaxation; else η via rule 1 | **Feedback and units problems.** Current-iteration σ = μγ̇ is a same-step positive feedback; σ* must match its f-form (Han's 20.4 Pa is for 1 − e^{−σ/σ*}); f needs the strain scale γ* (Han's g(γ)); the near-jam η divergence is capped by ν_max; "high relaxation" has no SI stiffness | Lagged τ̄ₙ from b̄ₑ; f relaxes over strain γ* = 0.197 plus 1/t_melt; jammed = creeping elastic solid (G, t_jam) with failure τ_jam and unjamming γ_break (§4.2 c, §4.7), all inside the XPBD-EVP. A *rigid* jam with PB-MPM shape matching stays an experiment (survey §6.2) [I] |
| 6. MR: τ_y = τ_y0 + k_H·min(H, H_sat)² | **Wrong shape.** Carlson's datasheet-validated law is tanh: linear at low H, saturating at about 158 kA/m. Squared-then-clipped, matched at H_sat, is too weak at mid field (0.25 τ_sat against 0.46 at H_sat/2), 31 % too strong at H_sat, and has a kink there | τ_field = min(τ_sat·tanh(H/H_sat), 0.05·G), with dead zone, 1 ms lag and μ₀M∇H body force (§4.2 d, §3.8) |
| 7. Hele-Shaw drag v ← v/(1 + Δt·12μ_eff/(ρb²)) | **Right for Newtonian only** | Gap-averaged power-law viscosity, yield handled by wall slip, drag-time floor, per-particle application (§4.10.5) |
| "Rules 1–3 are PB-MPM's own mechanisms … rules 4–6 add three floats" | **Superseded** | State is b̄ₑ (3) + J + λ + f + T, the same 80-byte particle with F replaced by b̄ₑ and J (survey §7.2 layout), plus 16 bytes of iteration scratch |

#### 4.10.5 Hele-Shaw (thin-tank) drag, corrected

For a gap b between the tank's front and back faces, depth-averaging the cross-gap flow adds a body-force drag f = −(12μ_HS/b²)·Ū. It is applied implicitly per substep:

**v ← v/(1 + Δt/t_HS), with t_HS = ρb²/(12μ_HS)**

1. **Newtonian:** μ_HS = η. This is exact for plane Poiseuille across the gap [C, V10].
2. **Power law** (exact slot flow) [C, `t8_out.txt`: 12 checks to 10⁻¹⁵]:
   - μ_HS = ((2n + 1)/(3n))·k·γ̇_w^{n−1}, with wall shear rate γ̇_w = 2(2n + 1)Ū/(n·b).
   - For n = 1 this gives γ̇_w = 6Ū/b and μ_HS = k.
   - Under drag alone, dŪ/dt = −cŪⁿ with c = 2k(2(2n + 1)/n)ⁿ/(ρb^{n+1}). For n < 1 the block **stops in finite time**: t_stop = Ū₀^{1−n}/((1 − n)c), which is 28 ms for k = 1, n = 0.5, b = 5 mm, Ū₀ = 5 cm/s.
   - Using the in-plane γ̇ instead of γ̇_w (as survey rule 7 implies) is wrong: an in-plane plug can still slide past the faces.
3. **Yield stress in the gap** behaves like Coulomb friction:
   - flow starts at a gradient of **2τ_y/b**;
   - the fast limit is 12μ_pŪ/b² + **3τ_y/b** (Buckingham slot flow) [C].
   - At b = 5 mm that is 2τ_y/b = 32 kPa/m for mayonnaise, **3.5 g of body force**: mayonnaise would never slide in a 5 mm cell.
   - That is real, but real pastes also slip on smooth glass. **Recommendation [I]:** omit the gap yield term (wall slip, `wSlip = 1`), or scale it by (1 − wSlip).
4. **Floor on t_HS.** With physical b and η, honey in a 5 mm gap is pure Darcy flow, creeping at ρgb²/(12η) = 1.9 mm/s, with t_HS = 0.2 ms. Putty would be frozen.
   - Use an effective gap b_eff ≈ 10 mm [I], and clamp t_HS ≥ 0.1 s so in-plane rheology, not gap friction, governs everything faster than 0.1 s.
   - Water-like keeps t_HS = ρb²/(12η) = 8.3 s at b = 10 mm, which damps sloshing over seconds.
   - Honest copy for this is in §8.
5. **Where to apply it.** μ_HS is per particle, but the drag acts on velocity. Use the decay factor 1/(1 + Δt/t_HS,p) on the particle's d at Integrate (and in the oracle at G2P). Alternatively, scatter m_p/t_HS,p as a fifth grid channel and apply it on nodes. For a uniform block both are exact [C: V10 to 10⁻¹⁵].

#### 4.10.6 Where each piece sits in the PB-MPM passes

| PB-MPM pass (`siggraph2024`) | Rheo content |
|---|---|
| `particleUpdatePBMPM` (each iteration) | `rheoEvaluate` without state write. Update a, a_prev and B_scatter; PB-MPM volume constraint with J |
| `particleToGrid` / `gridUpdate` / `gridToParticle` (each iteration) | Unchanged, except SI body forces. Colliders and guardian as in PB-MPM. Grid-volume J correction (`gridToParticle.wgsl:78-85`) for liquids |
| `particleIntegrate` (once) | `rheoUpdate` with state write: b̄ₑ, J, λ, f, temperature diffusion and gdotP. Hele-Shaw decay on d. x += d; d += gΔt²/Δx; MR body force |
| `main` fused `g2p2g` | The same calls inside the tile kernel (`61749b6`): the constraint where `g2p2g.wgsl` does its liquid/elastic solve (lines 365–425), and the commit inside its last-iteration integrate block (lines 207–320; gravity at 320) |

---

## 5. Toy-scale nondimensionalisation

### 5.1 Reference scales [I unless marked]

| Quantity | Value | Note |
|---|---|---|
| Tank | 72 × 154 mm portrait, 2D | `oss-engine-survey.md` §6.1; the brief's "about 7 × 15 cm" |
| Grid | Δx = 1.5 mm (48 × 103 cells); the survey also uses 1.125 mm | Δx enters only the costs and the numerical ν (§4.10.2) |
| Gravity | g = 9.81 m/s², real; presets Moon 1.62, Mars 3.71, Jupiter 24.79 | Never normalised to the grid (§4.10.1) |
| Blob or layer size | L = 3 cm | A dollop of 12 cm² per unit depth |
| Finger poke | U_f ≈ 0.3 m/s over about 1 cm, so γ̇_f ≈ 30 s⁻¹; contact about 0.1 s | Lava uses γ̇_ref = 3 s⁻¹; slime and putty 5 s⁻¹ (they are pulled, not stirred) |
| Punch, flick | ≤ 1 m/s, contact about 10 ms | Sets |v|_max for the CFL |
| Shake | 5 Hz × 1 cm, so 0.3 m/s | |
| Mic vibration | 50–200 Hz, A·ω² up to a few g | At least 8 substeps per period |
| Observation times | poke 0.1 s; slump 1–10 s; patience about 30 s | For Deborah numbers |

### 5.2 The groups that decide what the user sees

| Group | Definition | Controls | Kept physical by |
|---|---|---|---|
| Yield number | **Y = τ_y/(ρgL) = ℓ_y/L** | Pile height, peaks, stoppage depth h_c = τ_y/(ρg sin θ), whether a blob holds its shape when tilted | τ_y, ρ, g, L all physical. **Never scale g to the grid.** |
| Bingham | **Bi = τ_y/(k·γ̇ⁿ)** | Plug versus sheared fraction under a finger or stir | τ_y, k, n physical |
| Reynolds | Re = ρUL/η_eff | Splash and wave (water, MR off-state, oobleck below onset) versus creep (pastes, honey, putty) | ρ, η physical. Numerical ν is ≤ 1.3 × 10⁻⁷·k m²/s (§4.10.2), small next to water's 10⁻⁶ |
| Deborah | **De = λ/t_obs** | Putty bounces at a 10 ms punch (De ≫ 1) and slumps over 10 s (De ≪ 1). Slime "bounces then puddles" | **λ physical** for Maxwell presets, even when G is softened (§5.3) |
| Weissenberg | **Wi = λ·γ̇** | Elastic recoil and rod climbing in flow (Maxwell presets). For all other presets it is a *numerical* artefact: λ_num = η_eff/G | Maxwell: physical λ. Others: **Wi_num ≤ 0.1** at γ̇_ref, so the 2Wi² deficit (§4.6) is ≤ 2 % |
| Yield strain | γ_y = τ_y/G | How much a paste wobbles before it yields | **≤ 0.05**. Real pastes sit at about 0.01–0.1 [S], so this is near-physical |
| Onset ratio (oobleck) | σ*/(ρgL) | Whether gravity-driven flow can jam | σ* physical (5 Pa ≪ ρgL ≈ 360 Pa: a tilted pool *can* jam; it oozes through the jam-creep branch, which is what real oobleck does) |
| Field ratio (MR) | τ_field/(ρgL) | Whether the magnet freezes the tank | τ(H) physical up to the 0.05·G clamp (1.5 kPa, ℓ_y = 50 mm, enough to hold everything in the tank) |
| Thixotropy | t_build/t_obs and k_break·γ̇·t | Yogurt "heals" over about 100 s; quicksand liquefies in about 1 s of shaking | Times physical or tuned within literature ranges (§6.2) |
| Mach (oracle only) | U/c_p ≤ 0.15 and ρgH_tank/K ≤ 3 % | Compressibility | Softened K (§5.3). On the GPU, PB-MPM's volume constraint replaces K |

### 5.3 What to soften, and what must stay physical

**Stays physical:** ρ, g, the tank size, τ_y (and its λ and T dependence), k, n, Newtonian η, Maxwell λ, the field yield curve, E_a, thixotropy times, σ*, φ, φ₀, φ_m and γ*.

**Softened:**

1. **K, always.**
   - Oracle: K = max(ρgH_tank/0.03, 2G), so a full tank compresses by at most 3 %.
   - GPU: PB-MPM's cold volume constraint plus grid-volume correction (survey §6.1). K matters only in parity mode.
2. **G, only where the physical value breaks the budget** (putty, jammed oobleck, MR on-state; lava's glassy G is irrelevant). The window is

   **max(20·τ_y,rest, 10·η_eff(γ̇_ref)·γ̇_ref) ≤ G ≤ ρ·(√(k/2)·Δx/Δt_sub)²**

   - The left bound keeps γ_y ≤ 0.05 and Wi_num ≤ 0.1.
   - The right bound is the PB-MPM stability rule of §4.10.3 at the substep budget. With 20 substeps per 1/120 s and k = 3, c_s ≤ 4.4 m/s, so G ≤ 2.1 × 10⁴ Pa (ρ = 1100) up to 5.0 × 10⁴ Pa (ρ = 2600).
3. **Maxwell presets with softened G: keep λ, let η follow** (η_toy = G_toy·λ_real) [I]. Silly Putty's G drops 28× (567 → 20 kPa), so its η drops 28× too (8 × 10⁴ → 2.8 × 10³ Pa·s) [C, `presets2_out.txt`]:

   | Silly Putty | Toy | Real |
   |---|---|---|
   | λ (s) | 0.14 | 0.14 |
   | De at a 0.1 s poke | 1.4 | 1.4 |
   | Bounce (De at a 10 ms punch) | 14 | 14 |
   | Slump rate ρgL/η | 0.12 s⁻¹ | 0.004 s⁻¹ |
   | Impact strain ρv²/G at 1 m/s | 5.5 % | 0.2 % |

   - Keeping η physical instead would give λ_toy = 4 s. A one-second stretch would then snap back elastically (De = 4) where real putty flows (De = 0.14), which is a qualitative error. The faster slump is a time-lapse, and §8 says so.
4. **Newtonian and paste presets**: G is numerical and chosen inside the window. Honey needs 10 kPa (Wi_num = 0.046 at 30 s⁻¹); 5 kPa in revision 1 of the table gave 0.09–0.15.
5. **Never soften** τ_y, k or η to buy time steps. They do not limit Δt (§4.6). Softening them would move Y and Bi, which are the visible physics.

### 5.4 Per-preset regime numbers [C, `presets2.py` → `presets2_out.txt`]

At Δx = 1.5 mm and 1/120 s frames, explicit substeps use CFL 0.4 and |v|_max = 1 m/s. PB substeps use k = 3, c_sΔt/Δx ≤ 1.22 and ≤ 1 cell per substep.

| Preset | ℓ_y = τ_y/ρg (mm) | Y (L = 3 cm) | Bi (30 s⁻¹) | Re (0.3 m/s, 1 cm) | λ (s): physical or *numerical* | Wi at γ̇_ref | γ_y | c_s (m/s) | Oracle substeps / frame | PB substeps / frame (passes) |
|---|---|---|---|---|---|---|---|---|---|---|
| Water-like | 0 | 0 | 0 | 3 000 | *1 × 10⁻⁵* | 0.000 | – | 0.32 | 113 | 6 (18) |
| Honey | 0 | 0 | 0 | 0.28 | *1.5 × 10⁻³* | 0.046 | – | 2.65 | 120 | 13 (39) |
| Ketchup | 2.3 | 0.076 | 1.1 | 2.1 | *3.2 × 10⁻³* | 0.094 | 0.050 | 0.67 | 113 | 6 (18) |
| Mayonnaise | 8.9 | 0.30 | 2.4 | 0.73 | *1.9 × 10⁻³* | 0.056 | 0.040 | 1.47 | 115 | 7 (21) |
| Toothpaste | 11.3 | 0.38 | 1.5 | 0.49 | *1.7 × 10⁻³* | 0.050 | 0.030 | 1.92 | 116 | 9 (27) |
| Oobleck (fluid branch) | 0 | 0 | – | 56 | *3 × 10⁻⁶* (jammed: t_jam = 0.05) | 0.000 | – | 4.03 | 128 | 19 (57) |
| Slime | 0 | 0 | 0 | 0.007 | **0.40** | 2.0 (5 s⁻¹) | – | 1.04 | 114 | 6 (18) |
| Silly Putty | 0 | 0 | 0 | 0.001 | **0.14** | 0.70 (5 s⁻¹) | – | 4.26 | 129 | 20 (60) |
| Yogurt | 2.9 | 0.098 | 0.64 | 1.2 | *3.2 × 10⁻³* | 0.096 | 0.037 | 0.88 | 114 | 6 (18) |
| Quicksand (rested) | 3.1 | 0.10 | 0.002 | 0.006 | *0.20* (solid-like at rest) | 6.0 | 0.012 | 1.58 | 115 | 8 (24) |
| MR fluid (off) | 0.25 | 0.008 | 1.4 | 21 | *1.4 × 10⁻⁵* | 0.000 | 0.000 | 3.13 | 122 | 15 (45) |
| Paint | 0.39 | 0.013 | 0.16 | 3.2 | *2.5 × 10⁻³* | 0.074 | 0.010 | 0.62 | 113 | 6 (18) |
| Lava (1130 °C) | 3.9 | 0.13 | 0.005 | 0.011 | *0.015* | 0.044 (3 s⁻¹) | 0.002 | 4.39 | 130 | 20 (60) |

**Visual acceptance numbers** (rested yield, 2D lubrication "Nye" pile h² = 2ℓ_y(L − x), from a 12 cm² dollop) [C, `t14_out.txt`]:

| Preset | Pile half-width | Pile height | h_c on a 30° tilt | ℓ_y on Moon / Mars / Jupiter |
|---|---|---|---|---|
| Ketchup | 5.6 cm (wall to wall) | 1.6 cm | 4.6 mm | 13.8 / 6.0 / 0.9 mm |
| Mayonnaise | 3.6 cm | 2.5 cm | 17.7 mm | 53.7 / 23.4 / 3.5 mm |
| Toothpaste | 3.3 cm | 2.7 cm | 22.7 mm | 68.6 / 29.9 / 4.5 mm |
| Yogurt (rested) | 5.2 cm | 1.7 cm | 5.9 mm | 17.8 / 7.8 / 1.2 mm |
| Lava | 4.7 cm | 1.9 cm | 7.8 mm | 23.7 / 10.4 / 1.6 mm |

The Moon preset turns mayonnaise into something that stands 5 cm tall. That is real physics (ℓ_y ∝ 1/g), and worth a line of in-app copy (§8).

### 5.5 Rules of thumb for new presets

1. Start from literature τ_y, k, n and η. Set ρ and E_a.
2. G = max(20τ_y, 10·η_eff(γ̇_ref)·γ̇_ref). If the material is genuinely viscoelastic, use its G (and λ) unless it exceeds the budget; then soften G and keep λ.
3. K from the compression rule (oracle only).
4. Check c_s against the substep budget (§4.10.3), and add the preset to the V-suite runs (§7).

---

## 6. Preset parameter table (revision 2)

SI units. Field names follow `RheoMaterial` (Appendix A). The machine-readable copy is `calc/presets2.json`, written by `presets2.py`; it supersedes revision 1's `presets.json`.

**Changes from revision 1:**
- Honey G 5 → 10 kPa, yogurt G 400 → 800 Pa, paint G 300 → 500 Pa and lava G 30 → 50 kPa, for Wi_num ≤ 0.1.
- Silly Putty keeps λ = 0.14 s with η_toy = 2.8 × 10³ Pa·s, instead of η = 8 × 10⁴ with λ = 4 s (§5.3).
- K follows the 3 % compression rule.

**Provenance tags:**
- **M**: measured, from a primary source read here [V].
- **L**: literature value or range, from a secondary source [S].
- **C**: computed or fitted here from M/L data.
- **T**: tuned by me for the toy [I].

### 6.1 Mechanical core

| Preset | ρ (kg/m³) | G toy (Pa) [physical] | K oracle (Pa) | τ_y (Pa): broken + Δτ·λ^m | k (Pa·sⁿ) | n | Relaxation time λ = η/G (s) | p_tens (Pa) | Tags |
|---|---|---|---|---|---|---|---|---|---|
| Water-like | 1000 | 100 [numerical] | 5.0 × 10⁴ | 0 | 1.0 × 10⁻³ | 1 | *1 × 10⁻⁵* | 10 | ρ, η: M/C (Cheng); G, p_tens: T |
| Honey | 1420 | 1.0 × 10⁴ [numerical] | 7.2 × 10⁴ | 0 | 15.4 (at 20 °C) | 1 | *1.5 × 10⁻³* | 50 | η: L (Saxena 2014); G: T |
| Ketchup | 1120 | 500 [≈10²–10³, I; stiffened] | 5.6 × 10⁴ | 10 + 15λ | 8.0 | 0.30 | *≈3 × 10⁻³ at 30 s⁻¹* | 30 | τ_y, k, n: L (Koocheki 2009 ranges); split into broken and rested: T |
| Mayonnaise | 920 | 2 000 [≈10³, I] | 4.6 × 10⁴ | 60 + 20λ | 10 | 0.35 | *≈2 × 10⁻³* | 120 | L ranges; T within them |
| Toothpaste | 1350 | 5 000 [≈10³–10⁴, I] | 6.8 × 10⁴ | 150 | 30 | 0.35 | *≈2 × 10⁻³* | 200 | τ_y: L (41–286 Pa); k, n: T |
| Oobleck | 1230 | 2.0 × 10⁴ jammed [≫ 10⁶, I] | 6.2 × 10⁴ | 0 (DST block, §6.2) | – (η_s = 1.0 × 10⁻³) | – | jammed creep t_jam = 0.05 | 0 | φ's, γ*: M (Han 2018); rest: T |
| Slime | 1010 | 1 100 [1 110, M] | 5.1 × 10⁴ | 0 | 447 (= η₀) | 1 | **0.40** | 2 000 | G₀, λ: M (Ramlawi 2024) |
| Silly Putty | 1100 | 2.0 × 10⁴ [5.67 × 10⁵, L] | 5.5 × 10⁴ | 0 | 2 800 [real 8 × 10⁴] | 1 | **0.14** [real 0.10–0.14] | 4 000 | E, λ, η: L (Cross 2012); G, η softened: T |
| Yogurt | 1040 | 800 [≈10²–10³, I; stiffened] | 5.2 × 10⁴ | 5 + 25λ | 4.0·(1 + 2λ) | 0.40 | *≈3 × 10⁻³* | 40 | thixotropic HB form: L; values: T |
| Quicksand | 2000 | 5 000 [?] | 1.0 × 10⁵ | 0 + 60λ³ | 0.05·(1 + 2 × 10⁴λ³) | 1 | *0.20 rested, 1 × 10⁻⁵ broken* | 0 | ρ: L (Khaldoun 2005); bifurcation law: L (Coussot 2002) form; values: T |
| MR fluid (off-state) | 3060 | 3.0 × 10⁴ [≈10⁵–10⁶ on-state, I] | 1.5 × 10⁵ | 7.6 + τ_field(H) (§6.2) | 0.18 | 1 | *≈1 × 10⁻⁵* | 50 | ρ, φ: M/C (MRF-132DG); τ_y0, μ_p: C (fit to MRF-132LD) |
| Paint | 1300 | 500 [≈10–10², I; stiffened] | 6.5 × 10⁴ | 3 + 2λ | 3.5 | 0.65 | *≈2.5 × 10⁻³* | 20 | C (fit to L coatings targets); thixotropy: T |
| Lava (T_ref = 1130 °C) | 2600 | 5.0 × 10⁴ [glass ≈10¹⁰, irrelevant] | 1.3 × 10⁵ | 100 | 700 | 1 | *0.014* | 0 | τ_y, η: L (Shaw 1968); ρ: L |

- Italic λ values are *numerical* (η_eff/G) and must stay small. Bold λ values are physical Maxwell times.
- "Stiffened" means toy G ≥ physical G, raised for Wi_num ≤ 0.1. It is harmless: the paste wobbles less, not more.
- The Newtonian branch can equally be written φ₀ = 1/η with k = 0. The kernel accepts both, and they agree to 10⁻⁶ (`gpu_out2.txt`).

### 6.2 Modulator parameters

| Preset | Structure: t_build = 1/A₀ (s), k_break = B₁, m, w_vib | Arrhenius E_a (kJ/mol) on k [on τ_y], T_ref | DST: φ, φ₀, φ_m, σ* (form), γ*, t_melt, t_jam, τ_jam, η_post, γ_break, Δφ_min, w_jam | Field | Tags |
|---|---|---|---|---|---|
| Water-like | – | 17.5, 20 °C | – | – | E_a: C (Cheng, 15–25 °C) |
| Honey | – | 85, 20 °C (halves per 6 K) | – | – | L (Saxena 2014 brand II); VFT optional (§3.1) |
| Ketchup | 20 s, 0.5, 1, 0 | 10, 20 °C | – | – | T |
| Mayonnaise | 50 s, 0.2, 1, 0 | 10, 20 °C | – | – | T |
| Toothpaste | – | 10, 20 °C | – | – | T |
| Oobleck | – | 17.5 on η_s (water), 20 °C | 0.52, 0.593, 0.452, **5 Pa (1 − e^{−σ/σ*})**, 0.197, 0.05 s, 0.05 s, 1 500 Pa, 2 Pa·s, 0.1, 0.01, 0.02 | – | φ₀, φ_m, γ*: M (Han 2018); φ: C (1.2:1 recipe); σ*: within L kitchen 2.6–8 Pa, but Han's density-matched fit is 20.4 Pa with this form [!]; rest: T |
| Slime | – | 42 (borate), 20 °C | – | – | L (Schultz & Myers 1969) |
| Silly Putty | – | 40, 20 °C | – | – | T (no source found) [!] |
| Yogurt | 100 s, 0.2, 1, 0 | 15, 20 °C | – | – | T (slow, partial recovery is L) |
| Quicksand | 10 s, 1.0, 3, **0.5** | 17.5, 20 °C | – | – | T (Coussot-type bifurcation, §3.6) |
| MR fluid | – | 20 on k, 20 °C | – | τ_sat = 46.7 kPa (C = 1, φ = 0.315), H_sat = 1.58 × 10⁵ A/m, clamp 0.05·G = 1.5 kPa, T₆₃ = 1 ms, dead zone 100 µT | Carlson law: M (COMSOL quote); datasheet: M; clamp and lag: T and L |
| Paint | 2 s, 0.05, 1, 0 | 15, 20 °C | – | – | T |
| Lava | – | 171 [171], 1130 °C | – | – (glow from T) | C from L (Kīlauea pair) [!] |

### 6.3 Appearance hints (for the renderer and the material picker)

| Preset | Look | Behaviour cue to show off |
|---|---|---|
| Water-like | clear, refractive, specular | splash, slosh, Hele-Shaw damping over seconds |
| Honey | amber, glossy, thick refraction | rope-like pour, coiling, much thinner when heated |
| Ketchup | opaque red, matte to satin | mounds, then flows when shaken (thixotropic) |
| Mayonnaise | off-white, satin | holds peaks; on the Moon it stands 5 cm tall |
| Toothpaste | white or striped, matte | ribbon keeps its shape |
| Oobleck | chalky white, matte; cracks when punched | punch is solid, slow finger sinks; vibration monsters |
| Slime | translucent, glossy, tinted | bounces, then puddles over seconds |
| Silly Putty | pastel, opaque, satin | bounces and snaps; slowly slumps (sped up 28×, §8) |
| Yogurt | white, soft gloss | spoon marks heal slowly |
| Quicksand | wet sand, grainy | firm until shaken, then liquefies |
| MR fluid | dark grey, metallic | stiffens and climbs toward a magnet |
| Paint | saturated colour, glossy | levels without sagging |
| Lava | black crust over an orange-white glow driven by T | crusts, levées, slows as it cools |

### 6.4 Optional extras

| Preset | Parameters | Tags |
|---|---|---|
| Rheopectic cream | τ_y = 2 + 40λ; A₀ = 0, A₁ = 0.05 (builds under shear), B₀ = 0.02 s⁻¹ (decays at rest) | T (form: L, §3.7) |
| Ferrofluid | Newtonian η = 0.12 Pa·s, ρ = 1236; Rosensweig spikes by the analytic overlay (§3.10) | M (Gollwitzer 2009) |
| Blood (Carreau mapped) | φ₀ = 1/(η₀ − η_∞), k = (η₀ − η_∞)·λ^{n−1}, n = 0.357, plus η_∞ | L (Cho & Kensey 1991), C mapping (§3.2) |
| Shampoo | Maxwell η₀ = 5–10 Pa·s, λ = 0.05–0.5 s | L / T |
| Glycerol | VFT η = exp(−11.657 + 1558.36/(T − 163.20)) Pa·s | C (fit to Cheng 2008) |

---

## 7. Analytic verification suite (CPU oracle first, then GPU parity)

**How to read the measurements.**
- Every formula below was checked against independent quadrature or ODE integration: 60/60 closed forms in `calc/t8_out.txt`, plus 5/5 for V4 in `calc/t15_out.txt` [C].
- Every set-up was run through a numpy prototype of the oracle: `calc/t9_mpm2d_cases.py`, a 2D explicit MLS-MPM with quadratic B-splines, 2×2 particles per cell, float64 and the unified EVP update. Outputs are in `t9_out_*.txt`, `t9_log_*.txt`, `t11_out.txt`, `t12_out.txt` and `t12b_out.txt`.
- The "Measured" column is what that prototype achieved. The "Tolerance" column is what the Swift oracle must meet (and the GPU, via V14).
- Walls are PB-MPM-style sticky grid nodes (v = 0 for nodes at or beyond the wall).
- Loads are ramped over ≥ 0.05 s. A sudden load overshoots stress by up to 2× and yields material that should stay rigid.

| ID | Case | Exact solution | 2D set-up | Measured [C] | Tolerance |
|---|---|---|---|---|---|
| V1 | Hydrostatic column | p(Z) = ρ₀gZ, with Z the Lagrangian depth; with Rheo's volumetric law, J(Z) = −a + √(a² + 1), a = ρ₀gZ/K; settled height h = (K/ρ₀g)·[½(a_H√(a_H² + 1) + asinh a_H) − ½a_H²]; τ_xy = 0 | Periodic x (4 cells), no-slip floor, free top; H₀ = 20 mm in 32 rows; ρ 1000, Newtonian 0.05 Pa·s, G 5 kPa, K 25 kPa; g ramped over 0.05 s; Hele-Shaw t_HS = 0.02 s for damping; 0.4 s | Interior row-mean p within 0.17–0.23 % of ρ₀gH₀ (32 and 64 rows, 2 or 3 ppc); \|J − J_ex\| ≤ 1.3 × 10⁻³; mean p/(ρ₀gH₀/2) = 1.003–1.005. **The first particle row at the floor reads +9 %**, a sticky-wall artefact that does not shrink with refinement | Interior rows ≤ 0.5 %; J ≤ 2 × 10⁻³; exclude the wall row, or test the floor reaction force instead |
| V2 | Plane Couette (any n, τ_y) | Uniform τ = τ_y + k(U/h)ⁿ; u = Uy/h (no plug, because the stress is uniform) | Walls at y = 0 (fixed) and y = h = 5 mm (U = 0.05 m/s), periodic x, 20 rows; G 5 kPa, K 20 kPa; 0.15 s, averaged over the last 0.03 s | τ_wall: −0.46 % (Bingham τ_y 10, k 1), −0.15 % (τ_y 10, k 2, n 0.4), −0.86 % (Newtonian); particle scatter 0.8–2.5 %; profile within 0.4–1.4 % of U | Mean τ ±1.5 %; profile ±2 % of U |
| V3 | Walled plane Poiseuille, including plug width | u(y) = (n/(n+1))·k^{−1/n}G_p^{−1}·[(G_pH − τ_y)^{(n+1)/n} − (G_p\|y\| − τ_y)₊^{(n+1)/n}]; **plug half-width y₀ = τ_y/G_p**; flow rate q = 2[u_pH − (n/(n+1))(n/(2n+1))k^{−1/n}G_p^{−2}(G_pH − τ_y)^{(2n+1)/n}]. Limits: Newtonian u_max = G_pH²/(2μ); power law u_max = (n/(n+1))(G_p/k)^{1/n}H^{(n+1)/n}; Bingham slot mean (Buckingham) Ū = (G_pH²/3μ_p)(1 − 3ξ/2 + ξ³/2), ξ = y₀/H | Walls at y = 0 and 2H, H = 5 mm, periodic x, body force G_p/ρ along x (a tilted tank); from rest, ≥ 20ρH²/η_eff. Cases: Newtonian μ 1, G_p 4000 (u_max 5.0 cm/s); Bingham τ_y 10, μ_p 1, G_p 4000 (y₀ = 2.5 mm, u_p = 1.25 cm/s); power law k 1, n 0.5, G_p 1000 (4.17 cm/s); HB τ_y 10, k 1, n 0.5, G_p 4000 (8.33 cm/s) | max\|u − u_ex\|/u_c: Newtonian 0.77 % (24 rows). Bingham 3.5 / 4.5 / 3.3 % (12 / 24 / 48 rows), with the plug edge one particle spacing inside the exact edge (0.75 cell). Power law 34 / 11 % (12 / 24). HB n 0.5: 62 / 31 / 9 % (12 / 24 / 48). Stress slope −3675 / −3855 / −3957 against −4000. A 1D staggered column with the same update converges to 4 × 10⁻⁴ (`t10_out.txt`), so the error is the 2D wall discretisation, amplified 3(τ_w/(τ_w − τ_y)) = 6× for n = 0.5 | Newtonian ≤ 1.5 % at 24 cells across; Bingham ≤ 5 % and plug edge ±1 cell; n = 0.5: ≤ 12 % at 48 cells, **and** the error must fall ≥ 2.5× per halving of Δx |
| V4 | Wall-free periodic shear ("Kolmogorov" flow): **the tight test** | Body force b_x = F sin κy, κ = 2π/L_y. Stress τ_xy = A cos κy with A = F/κ. Newtonian u = (A/μκ) sin κy. Bingham: plugs of half-width **y₀ = asin(τ_y/A)/κ** centred on κy = π/2 and 3π/2, plug speed u_p = (A cos θ₀ − τ_y(π/2 − θ₀))/(μκ) with θ₀ = κy₀; for \|θ\| ≤ π/2 − θ₀ (θ = κy wrapped to (−π, π]), u = sgn θ·(A sin\|θ\| − τ_y\|θ\|)/(μκ), mirror-symmetric about θ = ±π/2. Power law n = ½: u = sgn θ·(A/k)²κ⁻¹·(a/2 + sin 2a/4) with a = min(\|θ\|, π − \|θ\|) | Fully periodic strip, L_x = 4Δx, L_y = 1 cm, 32–64 rows; G 5 kPa, K 20 kPa; F 2 × 10⁴ N/m³ (Newtonian, Bingham τ_y = 20 Pa) and 6 × 10³ (power law); 0.6 s, averaged over the last 15 %. **Keep Re_K = u_max/(ν_effκ) ≤ 0.3**: laminar Kolmogorov flow loses stability at Re = √2 (Meshalkin & Sinai 1961) [S] | Newtonian 0.13 % (32 rows), 0.28 % (64). Bingham 1.3 / 1.7 %, plug half-width 0.70 / 0.98 mm against 1.08 (1.2 / 0.7 cell). Power law (Re_K = 1.7, narrow strip) 8.8 / 1.35 % | Newtonian ≤ 0.5 % at 32 cells per period; Bingham ≤ 2 % and plug ±1 cell at 64; power law ≤ 2 % at 64 |
| V5 | Incline stoppage and film | **h_c = τ_y/(ρg sin θ)**. For h > h_c, with S = ρg sin θ and z from the floor: u(z) = (n/(n+1))(S/k)^{1/n}·[(h − h_c)^{(n+1)/n} − (h − h_c − z)₊^{(n+1)/n}]; surface u_s = (n/(n+1))(S/k)^{1/n}(h − h_c)^{(n+1)/n}; flux q = (n/(n+1))(S/k)^{1/n}·[(h − h_c)^{(n+1)/n}h − (n/(2n+1))(h − h_c)^{(2n+1)/n}] | Periodic x, no-slip floor, free top; gravity (g sin θ, −g cos θ) ramped over 0.1 s; 16 rows across the film; ketchup-like ρ 1100, τ_y 15, k 8, n 0.3, θ 30°, so h_c = 2.781 mm; G 2 kPa; 0.6 s | h = 0.8h_c: u_s = 2.5 × 10⁻⁸ m/s, zero plastic rate. h = 2.5h_c: u_s = 3.005 against 3.023 cm/s (−0.6 %). h = 1.5h_c: 4.6 × 10⁻⁴ against 2.6 × 10⁻⁴ m/s (+78 %): u_s ∝ (h − h_c)^{4.3} turns the +9 % wall-row stress (V1) into an effective h_c about 7 % low | Static for h ≤ 0.85h_c (\|u_s\| ≤ 10⁻⁶ m/s, no plastic rate after the ramp); flowing for h ≥ 1.15h_c; u_s within 3 % at h ≥ 2.5h_c |
| V6 | Maxwell stress relaxation | τ(t) = Gγ₀e^{−t/λ}; backward-Euler discrete τₙ = Gγ₀(1 + Δt/λ)^{−n}, error vs exact ≈ +tΔt/(2λ²) | Fully periodic 8 × 8-cell block; initial b̄ₑ = FFᵀ with F = [[1, γ₀], [0, 1]], γ₀ = 0.01; v = 0; G 10 kPa; λ/Δt = 100, 10 and 1; run 3λ | Matches the backward-Euler discrete solution to 4 × 10⁻⁶ – 1 × 10⁻⁵·Gγ₀; against the exponential, max 1.8 × 10⁻³ / 1.8 × 10⁻² / 0.13·Gγ₀ (the backward-Euler error itself) | \|τ − τ_BE\| ≤ 10⁻⁴·Gγ₀ |
| V7 | Maxwell start-up and normal stress (homogeneous) | τ_xy(t) = ηγ̇(1 − e^{−t/λ}); upper-convected Maxwell N₁ = 2ηλγ̇² | Single particle, prescribed C = [[0, γ̇], [0, 0]], Δt = λ/200 | Start-up error 9 × 10⁻⁴ (Wi 0.01) and 1.2 × 10⁻² (Wi 0.1); steady τ/(ηγ̇) = 0.9998 / 0.981 / 0.742 / 0.523 at Wi 0.01 / 0.1 / 0.5 / 1; N₁/N₁,UCM = 1.002 / 0.969 / 0.59 (`t1_out.txt` D) | Wi ≤ 0.1: start-up ≤ 2 %, N₁ within 5 %. Wi ≥ 0.5: regression values only (model property, §4.6) |
| V8 | Thixotropic λ step response | λ(t) = λ_ss + (λ₀ − λ_ss)e^{−(A+B)t}, λ_ss = A/(A + B), with A = A₀ + A₁γ̇ₚ and B = B₀ + B₁γ̇ₚ; recovery at rest λ(t) = 1 − (1 − λ₀)e^{−t/t_build}; discrete: (1 + (A + B)Δt)^{−n} | Constitutive level (prescribed γ̇), then V2's Couette geometry with a Bingham fluid (uniform γ̇ₚ ≈ U/h): A₀ = 0.05 s⁻¹, B₁ = 0.5, γ̇ = 2 s⁻¹ (λ_ss = 0.0476, rate 1.05 s⁻¹); then stop the wall and watch recovery over 1/A₀ = 20 s | Implicit update against exact: 1.8 × 10⁻⁴ (Δt 1 ms), 1.8 × 10⁻³ (10 ms); closed form against ODE 2 × 10⁻⁹ (`t1_out.txt` E, `t8_out.txt`) | Against the discrete form 10⁻⁹; against exact ≤ 0.2(A + B)Δt |
| V9 | Viscosity bifurcation (quicksand law) | Steady τ(γ̇) = k₀(1 + βλ_ss^m)γ̇ with λ_ss = A₀/(A₀ + B₁γ̇); local maximum 14.8 Pa at γ̇ = 0.050 s⁻¹, minimum 0.25 Pa at 3.2 s⁻¹ (k₀ 0.05, β 2 × 10⁴, m 3, A₀ 0.1, B₁ 1) | Homogeneous, stress-controlled: τ steps of 10 and 20 Pa from rest | Curve extrema as stated (`t1_out.txt` F) | Below the maximum it stops (γ̇ → 0 within 5/A₀); above it avalanches to the low-viscosity branch |
| V10 | Hele-Shaw drag decay | Newtonian v(t) = v₀e^{−t/t_HS}, t_HS = ρb²/(12η), discrete v₀(1 + Δt/t_HS)^{−n}. Power law: dŪ/dt = −cŪⁿ, c = 2k(2(2n+1)/n)ⁿ/(ρb^{n+1}), **finite stop** t_stop = Ū₀^{1−n}/((1 − n)c), Ū(t) = (Ū₀^{1−n} − (1 − n)ct)₊^{1/(1−n)} | Fully periodic 8 × 8-cell block, uniform v₀ (0.1 and 0.05 m/s), no gravity; b = 5 mm; η = 0.01 Pa·s (t_HS = 0.208 s), and k = 1, n = 0.5 (t_stop = 27.95 ms); power-law drag semi-implicit with μ_HS from the previous speed | Newtonian equals the discrete form to 10⁻¹⁵; power law \|Ū − Ū_ex\| = 1.2 × 10⁻⁴ m/s (0.25 % of Ū₀) at t_stop/2 and 8 × 10⁻⁵ at 0.9t_stop; 0 after t_stop | Newtonian 10⁻¹²; power law ≤ 0.5 % of Ū₀ |
| V11 | Oobleck jamming front (spatial) | Han et al. 2018: U_f/U₀ = 1/γ_∞, with γ_∞ = γ*·ln((φ₀ − φ_m)/(φ − φ_m)); **6.96** at φ = 0.52 (§3.4.2) | Layer 4 cm deep × 7 cm wide; a 1 cm kinematic plate pushed down at 0.3–1 m/s; track the jammed region (s > 0.5) ahead of the plate | **Not run** [!] | Hypothesis: ratio within ±30 %. Slow push (0.02 m/s) must not jam |
| V12 | Field and temperature laws (unit tests) | τ_field(H) against the §3.8 table; a_T against the honey table (§3.1) and the Cheng water and glycerol table | Constitutive only | Tables reproduced [C] | 10⁻⁴ relative |
| V13 | PB-MPM viscosity regression | Shear wave u = u₀ sin(k_wy)·e^{−νk_w²t} | Periodic 4 × 64 cells, Δx 1.5 mm, Δt = 1/240 s, u₀ = 1 cm/s; native r = 8νΔt/(kΔx²); XPBD-EVP warm start with Π ≤ 4k | Native: ν_eff/(rkΔx²/Δt) = 0.125 (r ≥ 0.6) to 0.148 (r = 0.01). XPBD-EVP: ν_eff/ν = 0.999–1.016; elastic ω/ω_ex 0.998–1.000 (§4.10) | Native within −2 % / +20 %; XPBD-EVP within 2 %; elastic ω within 0.5 % |
| V14 | GPU–CPU parity | GPU with k = 1, ω = 0, β = 1 (explicit) against the Double oracle | V2, V4 and V6 states; a 2 k-particle mixed scene over 100 steps | Constitutive level: float32 GPU against Double CPU \|Δτ̄\|/τ̄ = 2 × 10⁻⁸ – 3 × 10⁻⁶ on 15 steady-shear cases; oobleck impact-hold-melt within 5 × 10⁻⁴ in stress, f within 0.04 (`gpu/gpu_out2.txt`) | τ̄ ≤ 10⁻⁵; f ≤ 0.05; positions RMS < 0.05 cell (survey §7.6 item 10) |

**What V3 and V5 say about the app's resolution [!].**
- At Δx = 1.5 mm, a 1 cm channel is 7 cells across. Shear-thinning (n ≈ 0.3–0.5) flows through narrow gaps are then only qualitatively right: the V3 trend suggests 30–60 % velocity error.
- Pile shapes, stoppage and slumps of 2–3 cm blobs (14–20 cells, near-uniform stress) are well inside tolerance.
- Treat V3 at 12 rows as the "phone resolution" regression value, not as a pass/fail on physics.

---

## 8. In-app honesty notes

Copy for an "About the physics" sheet. Short sentences, one per claim. Each line is tagged with the section that backs it.

### 8.1 Global

- **Real numbers inside.** Yield stresses, viscosities, flow indices, densities and gravity come from measurements and the literature. A mayonnaise pile, a ketchup drip or honey under heat behaves at the scale of a real 7 × 15 cm tray. (§3, §5.2)
- **Gravity is real.** Moon, Mars and Jupiter use their true values. On the Moon, mayonnaise stands about 5 cm tall, because the height a paste can hold scales as 1/g. (§5.4)
- **Stiffness is softened.** Real liquids carry sound at about 1.5 km/s. The toy uses 1–4 m/s so it can run on a phone. You may see a slight squash (up to about 3 %) and a softer bounce. Flow, yield and viscosity are not softened. (§5.3)
- **It is a thin slice.** The tank is two-dimensional: everything moves in the plane of the screen. The front and back glass add a light drag, like a cell about 1 cm thick with slippery faces. In a real 5 mm cell, honey would creep at about 2 mm/s and mayonnaise would not slide at all. (§4.10.5)
- **What 2D changes.**
  - Honey folds instead of coiling (coiling is a 3D instability).
  - Threads and sheets do not pinch into drops: there is no surface tension. Drips form by tearing at a tension limit.
  - Ferrofluid spikes are drawn from the real Rosensweig wavelength (about 1 cm), not computed. (§3.10)
- **Resolution.** Cells are 1.5 mm. Anything thinner than about 5 mm is smoothed. Shear-thinning flow through narrow gaps is right in kind but can be off by tens of per cent. (§7, V3)
- **Time.** The toy runs in real time. If the phone cannot keep up, the clock slows and a "slow-motion" badge appears. (survey §7.4)
- **Temperature.** Viscosity follows measured Arrhenius laws: honey is about 65× runnier at 60 °C than at 10 °C. Heated mayonnaise would split in reality; the toy does not model that. (§3.1, §3.11)

### 8.2 Per material

| Preset | Real | Tuned or changed |
|---|---|---|
| Water-like | viscosity and its temperature dependence | numerical shear stiffness only |
| Honey | 15 Pa·s at 20 °C, halves per 6 K | – |
| Ketchup, mayonnaise, toothpaste | yield stress, consistency and flow index from measured ranges | rested-versus-stirred split and recovery times are tuned |
| Oobleck | the jamming law (Wyart–Cates), packing fractions, strain scale (Han et al. 2018); "walk slowly and sink, punch and it's solid" | the jammed solid is far softer than real and creeps over 0.05 s; onset stress is chosen within the kitchen range; no water–starch separation, so dry cracks are drawn |
| Slime | stiffness and relaxation time (0.4 s) of a measured PVA–borax slime | – |
| Silly Putty | bounce and snap time (0.14 s) | stiffness 28× lower; **creep 28× faster than real**, so you can watch it flow in seconds instead of minutes |
| Yogurt | thixotropic yield-stress behaviour | all numbers tuned |
| Quicksand | liquefies when shaken (Khaldoun 2005); about twice the density of a body | single phase: real quicksand traps by separating into water and packed sand. The toy fakes the "trap" with fast rebuild. You would float half-submerged |
| MR fluid | the yield-versus-field curve of a commercial fluid (LORD MRF-132DG, Carlson's law) | capped at 1.5 kPa (real: 50 kPa); in this tank that looks identical. The phone measures the field at its sensor, not in the tank, and subtracts Earth's field |
| Paint | low-shear and high-shear viscosity targets from coatings practice | recovery time tuned |
| Lava | yield stress and viscosity of Hawaiian basalt near 1130 °C, and how fast they rise on cooling | glow colour from temperature; cooling time sped up if shown |

---

## 9. Flags and open questions (the [!] list)

1. **Solver decision conflict.** `oss-engine-survey.md` Revision 2 prefers explicit MLS-MPM with PB-MPM infrastructure; the brief fixes PB-MPM.
   - Resolution: XPBD-EVP with k = 1, ω = 0, β = 1 *is* explicit MLS-MPM (§4.10.3). The constitutive code is identical, and the iteration count becomes a tuning knob.
   - Measured fact: per pass, substeps buy k² in elastic stiffness and iterations buy k.
2. **Survey §7.3 rules 1–7 are corrected in §4.10.4.** The decisive ones:
   - relaxation viscosity saturates at ν_max = kΔx²/(8Δt);
   - the rate-based plug switch cannot give h_c;
   - forward-Euler Maxwell is unstable for Δt > λ.
3. **Correction to §1 item 2.** The steady flow curve is exact only as Wi → 0. At finite Wi the b̄ₑ model under-predicts it by about 2Wi² (§4.6). N₁ is under-predicted for Wi ≥ 0.3.
4. **Sticky-wall artefact.** The particle row next to a sticky wall carries about +9 % stress (V1). That shifts the incline threshold by about 7 % (V5) and limits walled-Poiseuille accuracy (V3).
   - Open: try slip walls with friction, or a level-set wall placed half a cell outside the material, in the oracle.
5. **Resolution of shear-thinning flows.** n = 0.5 needs about 48 cells across a sheared layer for 10 % accuracy. The app has 7–20.
6. **V11 (oobleck jamming front) was not run.** The DST block is verified only at constitutive level (§4.7).
7. **PB-MPM stability** was measured on a periodic shear wave with the volume part cold and K-based. It was not measured with free surfaces, colliders or PB-MPM's own liquid constraint. Use Π ≤ 3k for margin until the Metal port's dam-break runs (sibling `mpm-metal.md`).
8. **Oobleck σ* = 5 Pa** (WC form) is tuned within kitchen reports (2.6–8 Pa, mixed forms). Han's density-matched fit is 20.4 Pa with this form. Do not mix forms (§3.4.1).
9. **Shi & Zhao 2024 label φ₀ and φ_m the other way round** from Wyart–Cates (§3.4.1).
10. **Merkt "monsters" in a 2D MPM layer** are untested (§3.4.3).
11. **Lava:** the pāhoehoe viscosity pair is from a summary of Chevrel et al. 2018 [S]; E_a = 171 kJ/mol rests on two points (§3.3, §3.11).
12. **MR at low field:** real yield grows like H² below a few kA/m, whereas Carlson's tanh is linear there. The magnetometer baseline and a 100 µT dead zone keep Earth's field from showing (§3.8).
13. **Physical G of pastes** (ketchup, mayonnaise, toothpaste, yogurt, paint) are my order-of-magnitude estimates [I]. Toy G is set by the Wi and yield-strain rules anyway (§5.3).
14. **Silly Putty E_a** has no source (40 kJ/mol assumed).
15. **Hele-Shaw b_eff = 10 mm, wall slip of the yield term and the t_HS ≥ 0.1 s floor** are toy choices [I] (§4.10.5).
16. **Quicksand segregation is not modelled** (§3.6).
17. **Ferrofluid spikes are an analytic overlay**, not emergent (§3.10).
18. **GPU budget.** The survey's revision 1 budget (2 substeps × 3 iterations) is withdrawn there and here. §5.4 needs 6–20 substeps × 3 iterations per 1/120 s frame, depending on the preset. Phone timing is unmeasured.

---

## 10. Sources

Read as primary text this session [V] (PDFs and repos in `scratchpad/rheology/pdf/` and `scratchpad/oss-survey/`):

- Yue, Smith, Batty, Zheng, Grinspun 2015, "Continuum Foam: A Material Point Method for Shear-Dependent Flows", *ACM Trans. Graph.* 34(5), 160. DOI 10.1145/2751541 [V text; DOI S]. Eqs. 1–3, 5, 7, 9–18 and Algorithm 1 are used in §4.2–4.3.
- Lewin 2024, "A Position Based Material Point Method", SIGGRAPH Talks '24. DOI 10.1145/3641233.3664323 [V]. Algorithms 1–2 and the XPBD remark are used in §4.10.
- EA SEED, PB-MPM, https://github.com/electronicarts/pbmpm, BSD-3-Clause. `main` 61749b6 (17 Oct 2024) and `siggraph2024` 5a2f438 (5 Aug 2024) [V]. Files cited: `shaders/particleUpdatePBMPM.wgsl:29-58`, `particleIntegrate.wgsl:34-145`, `gridToParticle.wgsl:56-85`, `particleToGrid.wgsl:50-63`, `gridUpdate.wgsl:24-93`, `src/sim.js:148-163`, `src/ui.js:89-105` (`siggraph2024`) and `ui.js:130-145`, `g2p2g.wgsl:207-320, 365-425` (`main`).
- Saramito 2009, *J. Non-Newtonian Fluid Mech.* 158, 154. DOI 10.1016/j.jnnfm.2008.12.001 [V].
- Wyart & Cates 2014, *PRL* 112, 098302 [V].
- Han, Wyart, Peters & Jaeger 2018, *Phys. Rev. Fluids* 3, 073301, arXiv 1711.02196 [V].
- Brown & Jaeger 2014, *Rep. Prog. Phys.* 77, 046602 [V].
- Shi & Zhao 2024, arXiv 2311.14408 [V].
- Merkt et al. 2004, *PRL* 92, 184501 [V].
- Ramlawi, Hossain, Shetty & Ewoldt 2024, arXiv 2402.19357 [V].
- Yang 2001, PhD thesis, UIUC, ch. 2 [V].
- LORD MRF-132DG datasheet DS7015 [V].
- Gollwitzer et al. 2009, arXiv 0904.3864 [V].
- Coussot review (pdf in scratch) [V].

Secondary or not re-read here [S]:

- Hu, Fang, Ge, Qu, Zhu, Pradhana, Jiang 2018, "A moving least squares material point method …", *ACM Trans. Graph.* 37(4), 150. DOI 10.1145/3197517.3201293 (MLS-MPM transfers, §4.4).
- Macklin, Müller & Chentanez 2016, "XPBD", MIG '16. DOI 10.1145/2994258.2994272.
- Simo & Hughes 1998, *Computational Inelasticity*, Springer (§9 flow rule).
- Meshalkin & Sinai 1961, *J. Appl. Math. Mech.* 25, 1700 (Kolmogorov-flow stability, Re_c = √2).
- Buckingham 1921, *Proc. ASTM* 21, 1154 (Bingham slot flow).
- Bird, Armstrong & Hassager 1987, *Dynamics of Polymeric Liquids* vol. 1 (power-law slot flow).
- Moore 1959; Mewis & Wagner 2009; Larson & Wei 2019; Coussot et al. 2002; Khaldoun et al. 2005; Cross 2012; Schultz & Myers 1969; Waitukaitis & Jaeger 2012; Han, Peters & Jaeger 2016; Mukhopadhyay, Allen & Brown 2018; von Kann et al. 2011; Deegan 2010; Carlson 2009 (quoted via COMSOL 2016); Kubík et al. 2022; Cheng 2008; Yanniotis et al. 2006; Saxena et al. 2014; Koocheki et al. 2009; Cho & Kensey 1991; Shaw et al. 1968; Hulme 1974; Chevrel et al. 2018; Coussot 1997; Dinkgreve et al. 2018; Cowley & Rosensweig 1967; Rosensweig 1985; Wen et al. 2003; Klár et al. 2016. Full references are at first use in §3.

Computed this session [C]: every script and output under `scratchpad/rheology/calc/`, `gpu/` and `pbmpm/` (§0.3).

---

## Appendix A. MSL kernel (`gpu/RheoConstitutive.metal`)

- **Status.** Compiles for `iphoneos` with `-std=metal4.0`, no warnings [C]. It matches the Double oracle to 2 × 10⁻⁸ – 3 × 10⁻⁶ in steady shear [C, `gpu_out2.txt`].
- **Throughput.** On an M1 Max with the update loop inside the kernel and no transfers: Newtonian 0.065, Bingham 0.124, HB n = 0.3 0.058, fluidity + HB 0.065 and DST 0.079 ns per particle-update [C].
- **Field naming:** `fieldScale` = τ_sat and `fieldK` = 1/H_sat (§4.2 d).
- **Not inside this function:**
  - the MR lag (per frame on the CPU);
  - the det f guard and velocity clamp (G2P);
  - the grid-volume J correction (G2P);
  - Hele-Shaw drag (grid or integrate).

The source is reproduced verbatim from the scratch file:

```metal
// RheoConstitutive.metal -- unified elasto-viscoplastic update for planar-2D MLS-MPM (Rheo / LabKit).
// Draft verified on macOS (M1 Max) against the Swift/Python references; see rheology-models.md section 4 and Appendix A.
#include <metal_stdlib>
using namespace metal;

// All SI. 4-float rows keep the struct 16-byte aligned and identical in Swift.
struct RheoMaterial {
    float rho, G, K, pTens;              // density, shear modulus, 2D bulk modulus, max Cauchy tension (Pa)
    float ty0, dtyLam, mLam, k0;         // yield = ty0 + dtyLam*lam^mLam ; consistency k0 (Pa s^n), 0 = HB off
    float n, betaLam, fluidity0, Ea;     // HB index (0.15..1); k *= 1+betaLam*lam^mLam; 1/eta0 Newtonian branch; Arrhenius J/mol
    float EaY, Tref, tauFail, fluidityFail; // Arrhenius on yield; ref T (K); failure branch (generic, INF = off)
    float A0, A1, B0, B1;                // dlam/dt = (A0 + A1 gs)(1-lam) - (B0 + B1 gs) lam
    float wVib, Jmin, Jmax, dst;         // gs = mix(gdot_p, gdot_tot, wVib); J clamp; dst > 0.5 enables DST block
    float phi, phi0, phim, etaS;         // Wyart-Cates: volume fraction, frictionless/frictional jamming, solvent visc
    float sStar, fForm, gStar, tMelt;    // onset stress; 0 = 1-exp(-s/s*), 1 = exp(-s*/s); strain scale; melt time
    float tJam, tauJam, etaPost, gBreak; // jammed creep time; jam failure stress; post-failure visc; unjamming strain
    float dphiMin, wJam, fieldScale, fieldK; // gap floor; jam blend width; tauField = fieldScale*tanh(fieldK*|H|)
    float fieldClampFracG, _p0, _p1, _p2;
};

struct RheoState {          // per particle, 32 bytes
    float b11, b12, b22;    // isochoric elastic left Cauchy-Green (det = 1)
    float J;                // elastic volume ratio
    float lam;              // thixotropic structure [0,1]
    float f;                // fraction of frictional contacts [0,1]
    float T;                // temperature (K)
    float gdotP;            // last plastic shear rate (diagnostic / render)
};

constant float kR = 8.314462618f;
constant float kInf = INFINITY;

// gdot_p(t) = phi0*t + ((t-ty)_+/k)^(1/n) + phif*(t-tf)_+   (all monotone; convex for n <= 1)
static inline float rheo_flow(float t, float phi0, float ty, float k, float invn, float tf, float phif) {
    float a = phi0 * t;
    if (k > 0.0f && t > ty) a += powr((t - ty) / k, invn);
    if (t > tf) a += phif * (t - tf);
    return a;
}
static inline float rheo_dflow(float t, float phi0, float ty, float k, float invn, float tf, float phif) {
    float d = phi0;
    if (k > 0.0f && t > ty) d += invn / k * powr((t - ty) / k, invn - 1.0f);
    if (t > tf) d += phif;
    return d;
}

// Returns Kirchhoff stress (t11, t12, t22). C: c11 = dvx/dx, c12 = dvx/dy, c21 = dvy/dx, c22 = dvy/dy.
static inline float3 rheo_update(thread RheoState& s, float c11, float c12, float c21, float c22,
                                 float dt, constant RheoMaterial& m, float Hmag)
{
    const float G = m.G;
    // 0. start-of-step equivalent shear stress (lagged driver for the DST contact fraction)
    float dn = 0.5f * (s.b11 - s.b22);
    float tauN = G * sqrt(dn * dn + s.b12 * s.b12);

    // 1. kinematics: f = I + dt C, J *= det f, fbar = f / sqrt(det f)
    float f11 = 1.0f + dt * c11, f12 = dt * c12, f21 = dt * c21, f22 = 1.0f + dt * c22;
    float detf = f11 * f22 - f12 * f21;
    s.J *= detf;
    float r = rsqrt(detf);
    f11 *= r; f12 *= r; f21 *= r; f22 *= r;
    float t11 = f11 * s.b11 + f12 * s.b12, t12 = f11 * s.b12 + f12 * s.b22;
    float t21 = f21 * s.b11 + f22 * s.b12, t22 = f21 * s.b12 + f22 * s.b22;
    float n11 = t11 * f11 + t12 * f12;
    float n12 = t11 * f21 + t12 * f22;
    float n22 = t21 * f21 + t22 * f22;
    float q = rsqrt(n11 * n22 - n12 * n12);
    n11 *= q; n12 *= q; n22 *= q;
    float tr = n11 + n22;
    float d11 = 0.5f * (n11 - n22);
    float tauTr = G * sqrt(d11 * d11 + n12 * n12);       // = ||dev tau||_F / sqrt(2)
    float mdt = G * 0.5f * tr * dt;                        // mu_tilde * dt
    float Dd = c11 - c22, Do = c12 + c21;
    float gTot = sqrt(Dd * Dd + Do * Do);                  // sqrt(2)*||dev D||_F

    // 2. Arrhenius shift factors
    float invT = 1.0f / s.T - 1.0f / m.Tref;
    float aT  = m.Ea  > 0.0f ? exp(m.Ea  / kR * invT) : 1.0f;
    float aTy = m.EaY > 0.0f ? exp(m.EaY / kR * invT) : 1.0f;
    float tField = min(m.fieldScale * tanh(m.fieldK * Hmag), m.fieldClampFracG * G);

    // 3. effective flow law
    float phi0f, ty, k, invn, tf, phif;
    if (m.dst > 0.5f) {
        float c = gTot / m.gStar + 1.0f / m.tMelt;
        float fss = (m.fForm < 0.5f) ? (1.0f - exp(-tauN / m.sStar)) : exp(-m.sStar / max(tauN, 1e-6f));
        s.f = (s.f + c * dt * fss) / (1.0f + c * dt);
        float phiJ = s.f * m.phim + (1.0f - s.f) * m.phi0;
        float gap = 1.0f - m.phi / phiJ;
        float sj = smoothstep(0.0f, 1.0f, (m.dphiMin - gap) / m.wJam);
        float gm = max(gap, m.dphiMin);
        float etaFluid = aT * m.etaS / (gm * gm);
        float eta = mix(etaFluid, G * m.tJam, sj);
        phi0f = 1.0f / eta; ty = tField; k = 0.0f; invn = 1.0f;
        tf = sj > 0.0f ? m.tauJam : kInf; phif = sj / m.etaPost;
    } else {
        float lm = powr(max(s.lam, 0.0f), m.mLam);
        ty = aTy * (m.ty0 + m.dtyLam * lm) + tField;
        k = aT * m.k0 * (1.0f + m.betaLam * lm);
        invn = 1.0f / m.n;
        phi0f = m.fluidity0 / aT; tf = m.tauFail; phif = m.fluidityFail;
    }

    // 4. return map on the scalar equation t = tauTr - mdt * gdot_p(t)
    float tNew = tauTr;
    float gP = 0.0f;
    bool flows = (phi0f > 0.0f) || (k > 0.0f && tauTr > ty) || (tauTr > tf);
    if (flows && tauTr > 0.0f) {
        float t0 = tauTr;                                               // every single-branch root is right of the joint root
        if (phi0f > 0.0f) t0 = min(t0, tauTr / (1.0f + mdt * phi0f));
        if (k > 0.0f && tauTr > ty) { float X = tauTr - ty; t0 = min(t0, ty + min(X, k * powr(X / mdt, m.n))); }
        if (tauTr > tf) t0 = min(t0, max(tf, (tauTr + mdt * phif * tf) / (1.0f + mdt * phif)));
        float t = t0;
        for (int it = 0; it < 5; ++it) {                               // 4-5 iterations reach float32 precision
            float res = t - tauTr + mdt * rheo_flow(t, phi0f, ty, k, invn, tf, phif);
            float dres = 1.0f + mdt * rheo_dflow(t, phi0f, ty, k, invn, tf, phif);
            t = max(t - res / dres, 0.0f);
        }
        tNew = t;
        gP = (tauTr - tNew) / mdt;
        float sc = tNew / tauTr;
        d11 *= sc; n12 *= sc;
        n11 = d11 + 0.5f * tr; n22 = -d11 + 0.5f * tr;
        q = rsqrt(n11 * n22 - n12 * n12);
        n11 *= q; n12 *= q; n22 *= q;
        if (m.dst > 0.5f && tNew > tf) s.f /= (1.0f + dt * phif * (tNew - tf) / m.gBreak);
    }
    s.b11 = n11; s.b12 = n12; s.b22 = n22;
    s.gdotP = gP;

    // 5. thixotropic structure (implicit, unconditionally stable)
    float gs = mix(gP, gTot, m.wVib);
    float A = m.A0 + m.A1 * gs, B = m.B0 + m.B1 * gs;
    s.lam = (s.lam + A * dt) / (1.0f + (A + B) * dt);

    // 6. volumetric Kirchhoff part with tensile cap
    s.J = clamp(s.J, m.Jmin, m.Jmax);
    float tvol = 0.5f * m.K * (s.J * s.J - 1.0f);
    if (tvol > s.J * m.pTens) {
        s.J = (m.pTens + sqrt(m.pTens * m.pTens + m.K * m.K)) / m.K;
        tvol = 0.5f * m.K * (s.J * s.J - 1.0f);
    }
    float h = 0.5f * (s.b11 + s.b22);
    return float3(G * (s.b11 - h) + tvol, G * s.b12, G * (s.b22 - h) + tvol);
}

// ---- test kernel: each thread = one homogeneous material point under a scripted velocity gradient
struct ShearJob { float c12; float steps; float dt; float _p; };

kernel void rheo_shear_test(device RheoState* st [[buffer(0)]],
                            device const ShearJob* job [[buffer(1)]],
                            constant RheoMaterial* mats [[buffer(2)]],
                            device float4* out [[buffer(3)]],
                            device const uint* matIndex [[buffer(4)]],
                            uint id [[thread_position_in_grid]])
{
    RheoState s = st[id];
    ShearJob j = job[id];
    constant RheoMaterial& m = mats[matIndex[id]];
    float3 tau = float3(0);
    int steps = int(j.steps);
    for (int i = 0; i < steps; ++i) tau = rheo_update(s, 0.0f, j.c12, 0.0f, 0.0f, j.dt, m, 0.0f);
    st[id] = s;
    float dd = 0.5f * (tau.x - tau.z);
    out[id] = float4(sqrt(dd * dd + tau.y * tau.y), tau.y, s.f, s.gdotP);
}
```

## Appendix B. Swift Double reference (`gpu/main.swift`, core function)

The CPU oracle's constitutive function mirrors Appendix A line for line in Double, iterating Newton to |Δt| ≤ 10⁻¹⁴·τ̄_tr. The test harness around it (steady shear, oobleck impact and hold, throughput) is in the scratch file.

```swift
struct StateD { var b11 = 1.0, b12 = 0.0, b22 = 1.0, J = 1.0, lam = 1.0, f = 0.0, T = 293.15, gdotP = 0.0 }
let kR = 8.314462618

func flow(_ t: Double, _ p0: Double, _ ty: Double, _ k: Double, _ invn: Double, _ tf: Double, _ pf: Double) -> Double {
    var a = p0 * t
    if k > 0 && t > ty { a += pow((t - ty) / k, invn) }
    if t > tf { a += pf * (t - tf) }
    return a
}
func dflow(_ t: Double, _ p0: Double, _ ty: Double, _ k: Double, _ invn: Double, _ tf: Double, _ pf: Double) -> Double {
    var d = p0
    if k > 0 && t > ty { d += invn / k * pow((t - ty) / k, invn - 1) }
    if t > tf { d += pf }
    return d
}

@discardableResult
func rheoUpdateCPU(_ s: inout StateD, c11: Double, c12: Double, c21: Double, c22: Double, dt: Double,
                   _ mf: RheoMaterial, H: Double = 0, iters: Int = 40) -> (Double, Double, Double) {
    let m = mf; let G = Double(m.G)
    let dn = 0.5 * (s.b11 - s.b22)
    let tauN = G * (dn * dn + s.b12 * s.b12).squareRoot()
    var f11 = 1 + dt * c11, f12 = dt * c12, f21 = dt * c21, f22 = 1 + dt * c22
    let detf = f11 * f22 - f12 * f21
    s.J *= detf
    let r = 1 / detf.squareRoot()
    f11 *= r; f12 *= r; f21 *= r; f22 *= r
    let t11 = f11 * s.b11 + f12 * s.b12, t12 = f11 * s.b12 + f12 * s.b22
    let t21 = f21 * s.b11 + f22 * s.b12, t22 = f21 * s.b12 + f22 * s.b22
    var n11 = t11 * f11 + t12 * f12, n12 = t11 * f21 + t12 * f22, n22 = t21 * f21 + t22 * f22
    var q = 1 / (n11 * n22 - n12 * n12).squareRoot()
    n11 *= q; n12 *= q; n22 *= q
    let tr = n11 + n22
    var d11 = 0.5 * (n11 - n22)
    let tauTr = G * (d11 * d11 + n12 * n12).squareRoot()
    let mdt = G * 0.5 * tr * dt
    let gTot = ((c11 - c22) * (c11 - c22) + (c12 + c21) * (c12 + c21)).squareRoot()
    let invT = 1 / s.T - 1 / Double(m.Tref)
    let aT = m.Ea > 0 ? exp(Double(m.Ea) / kR * invT) : 1
    let aTy = m.EaY > 0 ? exp(Double(m.EaY) / kR * invT) : 1
    let tField = min(Double(m.fieldScale) * tanh(Double(m.fieldK) * H), Double(m.fieldClampFracG) * G)
    var p0 = 0.0, ty = 0.0, k = 0.0, invn = 1.0, tf = Double.infinity, pf = 0.0
    if m.dst > 0.5 {
        let c = gTot / Double(m.gStar) + 1 / Double(m.tMelt)
        let fss = m.fForm < 0.5 ? 1 - exp(-tauN / Double(m.sStar)) : exp(-Double(m.sStar) / max(tauN, 1e-6))
        s.f = (s.f + c * dt * fss) / (1 + c * dt)
        let phiJ = s.f * Double(m.phim) + (1 - s.f) * Double(m.phi0)
        let gap = 1 - Double(m.phi) / phiJ
        var x = min(max((Double(m.dphiMin) - gap) / Double(m.wJam), 0), 1)
        x = x * x * (3 - 2 * x)
        let gm = max(gap, Double(m.dphiMin))
        let eta = (1 - x) * aT * Double(m.etaS) / (gm * gm) + x * G * Double(m.tJam)
        p0 = 1 / eta; ty = tField; k = 0; invn = 1
        tf = x > 0 ? Double(m.tauJam) : .infinity; pf = x / Double(m.etaPost)
    } else {
        let lm = pow(max(s.lam, 0), Double(m.mLam))
        ty = aTy * (Double(m.ty0) + Double(m.dtyLam) * lm) + tField
        k = aT * Double(m.k0) * (1 + Double(m.betaLam) * lm)
        invn = 1 / Double(m.n)
        p0 = Double(m.fluidity0) / aT; tf = Double(m.tauFail); pf = Double(m.fluidityFail)
    }
    var gP = 0.0
    let flows = p0 > 0 || (k > 0 && tauTr > ty) || tauTr > tf
    if flows && tauTr > 0 {
        var t0 = tauTr
        if p0 > 0 { t0 = min(t0, tauTr / (1 + mdt * p0)) }
        if k > 0 && tauTr > ty { let X = tauTr - ty; t0 = min(t0, ty + min(X, k * pow(X / mdt, Double(m.n)))) }
        if tauTr > tf { t0 = min(t0, max(tf, (tauTr + mdt * pf * tf) / (1 + mdt * pf))) }
        var t = t0
        for _ in 0..<iters {
            let res = t - tauTr + mdt * flow(t, p0, ty, k, invn, tf, pf)
            let dres = 1 + mdt * dflow(t, p0, ty, k, invn, tf, pf)
            let tn = max(t - res / dres, 0)
            if abs(tn - t) <= 1e-14 * tauTr { t = tn; break }
            t = tn
        }
        gP = (tauTr - t) / mdt
        let sc = t / tauTr
        d11 *= sc; n12 *= sc
        n11 = d11 + 0.5 * tr; n22 = -d11 + 0.5 * tr
        q = 1 / (n11 * n22 - n12 * n12).squareRoot()
        n11 *= q; n12 *= q; n22 *= q
        if m.dst > 0.5 && t > tf { s.f /= (1 + dt * pf * (t - tf) / Double(m.gBreak)) }
    }
    s.b11 = n11; s.b12 = n12; s.b22 = n22; s.gdotP = gP
    let gs = (1 - Double(m.wVib)) * gP + Double(m.wVib) * gTot
    let A = Double(m.A0) + Double(m.A1) * gs, B = Double(m.B0) + Double(m.B1) * gs
    s.lam = (s.lam + A * dt) / (1 + (A + B) * dt)
    s.J = min(max(s.J, Double(m.Jmin)), Double(m.Jmax))
    let K = Double(m.K), pt = Double(m.pTens)
    var tvol = 0.5 * K * (s.J * s.J - 1)
    if tvol > s.J * pt { s.J = (pt + (pt * pt + K * K).squareRoot()) / K; tvol = 0.5 * K * (s.J * s.J - 1) }
    let h = 0.5 * (s.b11 + s.b22)
    return (G * (s.b11 - h) + tvol, G * s.b12, G * (s.b22 - h) + tvol)
}
func tauBar(_ t: (Double, Double, Double)) -> Double { let d = 0.5 * (t.0 - t.2); return (d * d + t.1 * t.1).squareRoot() }
```

## Appendix C. XPBD-EVP constraint step and SI native viscosity (`gpu/RheoXPBD.metal`)

- **Status.** Compiles for `iphoneos` with `-std=metal4.0 -Wall`, no warnings [C].
- **GPU smoke test** (`xpbd_check.swift`, macOS, Newtonian η = 0.5 Pa·s, fresh state, one step of γ̇Δt = 10⁻³) against a Double closed form [C, `xpbd_check_out.txt`]:
  - applied stress a12 within 1.1 × 10⁻⁸;
  - ΔB within 2.5 × 10⁻⁸;
  - native-viscosity output exact to 7 digits.
- **Tangent.** The iteration logic is the numpy one verified in §4.10.3, except that θ uses the **secant** τ̄/τ̄_tr. That equals the tangent for Newtonian and Maxwell, and is ≥ the tangent with a yield stress, so it is conservative [I].

```metal
struct RheoIter {            // per particle, lives between PB-MPM iterations of one substep (16 bytes)
    float a11, a12;          // applied deviatoric Kirchhoff stress estimate (Pa)
    float p11, p12;          // part of it already scattered into B (Pa)
};

// Warm start at the beginning of a substep (beta = 1: explicit-exact; 0: cold, PB-MPM-like softness).
static inline RheoIter rheo_iter_begin(RheoState s, float G, float beta) {
    RheoIter it;
    it.a11 = beta * G * 0.5f * (s.b11 - s.b22);
    it.a12 = beta * G * s.b12;
    it.p11 = 0.0f; it.p12 = 0.0f;
    return it;
}

// One constraint evaluation. B = PB-MPM deformationDisplacement (= dt * grad v), column-major: B[col][row].
// Returns the increment dB to add to B before P2G. The committed state s is passed BY VALUE (no write-back).
static inline float2x2 rheo_constraint(thread RheoIter& it, RheoState s, float2x2 B, float dt, float kappa,
                                       float omega, constant RheoMaterial& m, float Hmag)
{
    float c11 = B[0][0] / dt, c12 = B[1][0] / dt, c21 = B[0][1] / dt, c22 = B[1][1] / dt;
    float3 t = rheo_update(s, c11, c12, c21, c22, dt, m, Hmag);      // s is a local copy
    float d = 0.5f * (t.x - t.z), sxy = t.y;                          // deviatoric Kirchhoff (s11, s12)
    float tb = sqrt(d * d + sxy * sxy);
    float mdt = m.G * 0.5f * (s.b11 + s.b22) * dt;                    // trace is preserved by the return map
    float tbTr = tb + mdt * s.gdotP;                                  // trial stress recovered from gdot_p
    float theta = tbTr > 0.0f ? tb / tbTr : 1.0f;                     // secant <= 1 (>= tangent): conservative
    float w = omega / (1.0f + kappa * 2.0f * m.G * theta);
    it.a11 += w * (d - it.a11);
    it.a12 += w * (sxy - it.a12);
    float d11 = it.a11 - it.p11, d12 = it.a12 - it.p12;
    it.p11 = it.a11; it.p12 = it.a12;
    return float2x2(float2(-kappa * d11, -kappa * d12), float2(-kappa * d12, kappa * d11));
}

// Native PB-MPM relaxation viscosity in SI (Water-like only): r = min(1, 8 mu dt / (rho k dx^2)), deviatoric part only.
static inline float2x2 pb_native_viscosity(float2x2 B, float mu, float rho, float dt, float dx, int k) {
    float r = min(1.0f, 8.0f * mu * dt / (rho * float(k) * dx * dx));
    float e11 = 0.5f * (B[0][0] - B[1][1]);
    float e12 = 0.5f * (B[1][0] + B[0][1]);
    return B - r * float2x2(float2(e11, e12), float2(e12, -e11));
}

```

Use per substep:

```
it = rheo_iter_begin(state, G, 1)
for k iterations:
    B += rheo_constraint(it, state, B, Δt, κ, ω = 1, m, H)
    PB-MPM liquid volume constraint on tr B (J as liquidDensity)
    P2G → grid → G2P
rheo_update(state, B/Δt, …)   // commit
```
