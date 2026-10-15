// Materials.swift — OWNER: PLAY (was PHYS; Documentation/REDESIGN-OWNERSHIP.md).
//
// The catalog every area reads (`ToothpasteCatalog`): the 13 shelf materials (ContinuumPresets + display copy + FluidLook
// + honesty lines + citations), the Drop-mode props, the knob specs and pages, the experiments, and the modelled
// steady flow curves σ(γ̇) for the Rheometer.
//
// Flow curves follow the knobs: the engine hands the catalog the material row it actually runs (`setLive`), with the
// field the fluid sees, so the Rheometer's curve moves when Yield, Consistency, Flow index, Packing or the magnet
// change. They are the steady state of the same EVP law the solver runs (`FlowCurve`; checked against the GPU's
// constitutive update in ToothpasteToyTests/PhysTests.swift), at rested-to-sheared steady structure λ_ss = A/(A + B).

import Foundation
import LabKitCore
import LabKitMPM
import LabKitRigid

@MainActor final class ToothpasteCatalogData: ToothpasteCatalog {
  let materials: [MaterialInfo]
  let props: [PropInfo]
  let specs: [ParamSpec]
  let pages: [ConsolePage]
  let cardKnobs: [ParamID]
  let experiments: [Experiment]
  let sources: [Citation]
  private let byID: [MaterialID: MaterialInfo]
  /// The rows the solver runs now (knobs applied), and the field magnitude the fluid sees (A/m).
  private var live: [MaterialID: ContinuumMaterial] = [:]
  private var liveField = 0.0

  init() {
    materials = Self.makeMaterials()
    byID = Dictionary(uniqueKeysWithValues: materials.map { ($0.id, $0) })
    props = Self.makeProps()
    specs = ToothpasteKnobs.all
    pages = ToothpasteKnobs.pages
    cardKnobs = ToothpasteKnobs.cardKnobs
    experiments = ToothpasteExperiments.all
    sources = ToothpasteSources.all
  }

  func material(_ id: MaterialID) -> MaterialInfo { byID[id] ?? byID[defaultMaterialID] ?? materials[0] }

  func prop(_ kind: PropKind) -> PropInfo { props.first { $0.id == kind } ?? props[0] }

  /// The engine's current row for `id` (knobs applied) and the field magnitude the fluid sees, A/m.
  func setLive(_ id: MaterialID, material: ContinuumMaterial?, field: Double) {
    live[id] = material
    liveField = field
  }

  /// The material row the solver runs for `id` (the preset when no knob has changed it).
  func running(_ id: MaterialID) -> ContinuumMaterial { live[id] ?? material(id).material }

  func flowCurve(_ id: MaterialID, shearRates: [Double], temperature: Double) -> [Double] {
    let m = running(id)
    let h = m.field != nil ? liveField : 0
    return shearRates.map { FlowCurve.stress(m, shearRate: $0, temperature: temperature, field: h) }
  }

  // MARK: Materials

  /// Display copy per preset id, in `ContinuumPresets.all` order.
  private static let copy: [(id: MaterialID, hint: String, icon: String, real: String, tuned: String)] = [
    ("waterLike", "Splashes, then settles", "drop.fill",
     "Viscosity and how it changes with temperature (Cheng 2008).", "Only a numerical shear stiffness."),
    ("honey", "Thick, and runnier when warm", "drop.halffull",
     "15 Pa·s at 20 °C; its viscosity halves every 6 °C.", "Nothing, beyond the thin-tank drag."),
    ("ketchup", "Thins when you shake it", "waterbottle.fill",
     "Yield stress, consistency and flow index from measured ranges.", "The rested-versus-stirred split and recovery time."),
    ("mayonnaise", "Holds a peak until pushed", "fork.knife",
     "Yield stress, consistency and flow index from measured ranges.", "The rested-versus-stirred split and recovery time."),
    ("toothpaste", "Keeps its shape", "paintbrush.pointed.fill",
     "A yield stress inside the published range.",
     "Consistency and flow index; how much warmth softens it; it grips the chamber's glass without slipping."),
    ("oobleck", "Hit it hard and it holds", "hand.raised.fill",
     "The jamming law, packing fractions and strain scale (Han et al. 2018); jams melt once you stop (Han 2016).",
     "The jammed solid is at least 100× softer than real, so the phone can run it; a jam lets go over about 0.15 s; on a floor shaking above about 3 g it jams on every bounce, and the holes and fingers real layers grow do not form; no water–starch separation."),
    ("slime", "Bounces, then puddles", "bubbles.and.sparkles.fill",
     "Stiffness and relaxation time (0.4 s) of a measured PVA–borax slime.", "Nothing."),
    ("sillyPutty", "Bounces and snaps, then slumps", "circle.fill",
     "Bounce and snap time (0.14 s).", "Stiffness 28× lower, so it creeps 28× faster than real."),
    ("yogurt", "Spoon marks heal slowly", "cup.and.saucer.fill",
     "Thixotropic yield-stress behaviour.", "All numbers are tuned."),
    ("quicksand", "Firm until shaken", "hurricane",
     "It liquefies when shaken (Khaldoun 2005); twice the density of water.",
     "Single phase: real quicksand traps by separating into water and packed sand."),
    ("mrFluid", "Stiffens near a magnet", "location.north.line.fill",
     "The yield-versus-field curve of a commercial MR fluid (Carlson's law).",
     "Capped at 1.5 kPa (real: about 50 kPa). A thin layer heaps over the magnet; a deep pool stays flat, and it never grows spikes. The phone measures the field at its sensor, not in the tank."),
    ("paint", "Levels without sagging", "paintpalette.fill",
     "Low-shear and high-shear viscosity targets from coatings practice.", "The recovery time."),
    ("lava", "Crusts as it cools", "flame.fill",
     "Yield stress and viscosity of Hawaiian basalt near 1130 °C, and how fast they rise on cooling.",
     "Cooling is sped up about 100×: the core over a minute, the crust in seconds. The model stops stiffening below 900 °C (real basalt keeps stiffening as it crystallises), so the coldest crust is drawn darker than it is stiff. The crust's cracks are drawn, not simulated: a pattern carried with the lava, its seams wider where it is hotter."),
  ]

  /// Fluid-page knobs that act on a material (the console dims the others).
  static func activeKnobs(_ m: ContinuumMaterial) -> Set<ParamID> {
    if m.dst != nil { return [.consistency, .packing] }
    var active: Set<ParamID> = [.consistency]
    if m.consistency > 0 { active.insert(.index) }
    if ToothpasteKnobs.yieldStress(m) > 0 { active.insert(.yield) }
    return active
  }

  private static func makeMaterials() -> [MaterialInfo] {
    let presets = ContinuumPresets.all
    precondition(presets.count == copy.count && FluidLook.all.count == presets.count, "catalog out of step with LabKit")
    return presets.enumerated().map { i, p in
      let c = copy[i]
      let m = ToothpasteTuning.material(c.id, p.material)
      return MaterialInfo(
        id: c.id, slot: i, title: p.name, hint: c.hint, icon: c.icon, material: m, look: ToothpasteLooks.look(c.id, FluidLook.all[i].look),
        activeKnobs: activeKnobs(m), fillFraction: fillFractions[c.id] ?? 0.45,
        fillTemperature: m.referenceTemperature, real: c.real, tuned: c.tuned,
        citations: ToothpasteSources.forMaterial[c.id] ?? [])
    }
  }

  /// Share of the tank height a plain Fill fills (experiments choose their own).
  static let fillFractions: [MaterialID: Double] = [:]

  // MARK: Props

  private static func makeProps() -> [PropInfo] {
    [
      PropInfo(
        id: .steelBall, title: "Steel ball", hint: "Sinks in almost anything", icon: "circle.circle.fill",
        shape: .circle(radius: 0.004), density: 7850, friction: 0.3, restitution: 0.4, colour: SIMD3(0.55, 0.57, 0.60)),
      PropInfo(
        id: .glassMarble, title: "Glass marble", hint: "Sinks slowly in honey", icon: "circle.fill",
        shape: .circle(radius: 0.006), density: 2500, friction: 0.3, restitution: 0.5, colour: SIMD3(0.45, 0.70, 0.85)),
      PropInfo(
        id: .corkBlock, title: "Cork block", hint: "Floats on everything", icon: "shippingbox.fill",
        shape: .box(halfWidth: 0.006, halfHeight: 0.004), density: 240, friction: 0.6, restitution: 0.2,
        colour: SIMD3(0.55, 0.35, 0.18)),
      PropInfo(
        id: .die, title: "Die", hint: "Just denser than water", icon: "die.face.5.fill",
        shape: .box(halfWidth: 0.005, halfHeight: 0.005), density: 1150, friction: 0.5, restitution: 0.3,
        colour: SIMD3(0.85, 0.85, 0.82)),
    ]
  }
}

/// Toothpaste Toy's own tuning of LabKit's material presets (the physics the solver runs; LabKit's presets stay as they
/// are for other apps). Every change keeps the value inside its published range and is said in the material's
/// honesty lines.
enum ToothpasteTuning {
  /// How the chamber's floor and side walls hold the paste in it (`MPMSolver.wallFriction`: 0 free slip … 1 no
  /// slip). LabKit's 0.5 is a partial slip that lets anything slide down a tilted floor, however slight the tilt: a
  /// toothpaste pile slid as one block from 1° on (7 mm by 10°, measured). Toothpaste sticks to glass, so its chamber
  /// grips it (no slip): the pile leans elastically and holds until its base yields, then slides (a 30 × 30 mm block
  /// at 26°, a 40 × 15 mm one past 45°, measured). The other pastes keep LabKit's value, which their tests are tuned
  /// to.
  static func wallFriction(_ id: MaterialID) -> Double {
    id == "toothpaste" ? 1 : MPMDomain().wallFriction
  }

  static func material(_ id: MaterialID, _ base: ContinuumMaterial) -> ContinuumMaterial {
    switch id {
    case "toothpaste": toothpaste(base)
    case "oobleck": oobleck(base)
    default: base
    }
  }

  /// Oobleck's jammed-solid stiffness (the GPU budget, REDESIGN.md §7, DEVICE-RUN-1/2): the elastic substep rule
  /// c_s·dt/Δx ≤ √(k/2) with LabKit's G = 20 kPa asks for 14 substeps per 120 Hz frame (15.9 on the iPhone, 8.2–10.1 ms
  /// of GPU, the one material over the 7 ms budget); at G = 10 kPa it asks for 10, as honey does, and the pool's
  /// hydrostatic rule (9) is close behind. The jammed solid is already softened ≥ 50× from the real ≫ 10⁶ Pa (T), so
  /// this halves a toy value; the jam strain at τ_jam = 4 kPa becomes 40 %. Checked against every oobleck scenario
  /// (PhysTests: rest levelling, slow finger sinks / fast finger stops, the jam melts after a punch, stir, vibrated
  /// layer, props, the lens jam).
  static let oobleckShearModulus = 1.0e4

  static func oobleck(_ base: ContinuumMaterial) -> ContinuumMaterial {
    var m = base
    m.shearModulus = min(m.shearModulus, oobleckShearModulus)
    return m
  }

  /// Toothpaste, the hero (REDESIGN.md §5): a 3 s squeeze must stack into folds that stand. LabKit's 150 Pa (mid-range)
  /// let a 30 mm stack's base yield and the folds spread across the floor (measured: 63 mm wide, 31 mm tall 5 s after a
  /// 3 s squeeze at 40 mm/s). τ_y = 250 Pa, still inside the 41–286 Pa that the preset cites (L; the value chosen is T). G stays 5 kPa,
  /// so the yield strain is 5 %, the solver's limit.
  ///
  /// Heat (REDESIGN.md §5.6, "Heat → runnier"): LabKit's toothpaste thins only its consistency with temperature
  /// (E_a = 10 kJ/mol) and keeps τ_y, so a warm coil stood as tall as a cold one. Here τ_y follows an Arrhenius shift too,
  /// E_a,y = 12 kJ/mol (T: the trend — warm toothpaste is softer — is reported for commercial pastes; the size is
  /// chosen): τ_y ≈ 330 Pa from the fridge (4 °C), 250 Pa at room temperature, 190 Pa at body temperature, 140 Pa at
  /// 60 °C and 100 Pa at 90 °C, where a stacked coil slumps. The paste reaches the Heat knob's temperature over the
  /// thermal time (4 s).
  static let yieldActivationEnergy = 12_000.0

  /// Tension limit 200 Pa → 1 kPa (T): the squeezed ribbon hangs from the nozzle and is pulled by the stack it is laid
  /// on; at 200 Pa it tore into a spray of loose particles wherever it was stretched (foam index 1.33 against 1.06 for
  /// the stack, measured). A toothpaste strand is cohesive well beyond its yield stress; it still necks and tears when
  /// the tube lifts away (by plastic flow, at the yield stress).
  static func toothpaste(_ base: ContinuumMaterial) -> ContinuumMaterial {
    var m = base
    m.yieldBroken = 250
    m.tensionLimit = 1000
    m.yieldActivationEnergy = yieldActivationEnergy
    m.shearModulus = max(m.shearModulus, 20 * 250)
    m.bulkModulus = max(m.bulkModulus, 2 * m.shearModulus)
    return m
  }
}

/// Toothpaste Toy's retunes of LabKit's looks (display choices: the physics reads none of them). The renderer takes the catalog's
/// looks (`TankRenderer.init`).
enum ToothpasteLooks {
  static func look(_ id: MaterialID, _ base: FluidLook) -> FluidLook {
    switch id {
    case "mrFluid": mrFluid(base)
    default: base
    }
  }

  /// MR fluid: iron in oil, black with a steel sheen. LabKit's preset read as a flat black slab at rest (a flat face
  /// against the front glass reflects one uniform patch of the studio; only the meniscus showed). A brighter steel F₀,
  /// a rounder pillow so the face curves into its edges and catches the light, a wet clear coat and a fine metallic
  /// grain (iron flakes) that moves with the fluid; TankRenderer adds the room's reflection in the oily face
  /// (`toothpasteSheenFragment`) for metallic looks. All gloss, no spikes (it does not spike; the copy says so).
  static func mrFluid(_ base: FluidLook) -> FluidLook {
    var l = base
    l.metalTint = SIMD3(0.15, 0.155, 0.17)
    l.roughness = 0.14
    l.specular = 1.8
    l.normalScale = 5
    l.rim = 0.28
    l.clearcoat = 0.45
    l.grain = 0.14
    l.grainSize = 0.1
    l.structureGloss = 0.3
    return l
  }
}

// MARK: - Modelled steady flow curves

enum FlowCurve {
  /// Steady simple-shear stress at a shear rate (1/s), temperature (K) and field magnitude |H| (A/m), Pa: the EVP flow
  /// law at steady structure (Moore λ_ss), Arrhenius shifts (in the solver's temperature band), Carlson's field yield,
  /// and the Wyart–Cates block for oobleck (the first steady branch reached on a rising ramp).
  static func stress(_ m: ContinuumMaterial, shearRate rate: Double, temperature T: Double, field: Double = 0) -> Double {
    guard rate > 0, rate.isFinite else { return .nan }
    // The solver's band: T_ref − (the material's `temperatureBandBelow`, else 40 K) … T_ref + 80 K (lava: 230 K below,
    // so its curve stiffens down to 900 °C as the solver's does since LK-FIX).
    let tb = min(max(T, m.referenceTemperature - max(m.temperatureBandBelow ?? 40, 0)), m.referenceTemperature + 80)
    let shift = arrhenius(m.activationEnergy, tb, m.referenceTemperature)
    let tField = fieldYield(m, field: field)
    if let d = m.dst {
      return dst(d, rate: rate, solvent: d.solventViscosity * shift, jamViscosity: m.shearModulus * d.jamTime) + tField
    }
    let build = m.buildRate + m.buildShear * rate
    let destroy = m.breakRate + m.breakShear * rate
    let lambda = build + destroy > 0 ? build / (build + destroy) : 1
    let lm = pow(lambda, m.structureExponent)
    let yieldShift = arrhenius(m.yieldActivationEnergy, tb, m.referenceTemperature)
    let tauY = (m.yieldBroken + m.yieldStructure * lm) * yieldShift + tField
    let k = m.consistency * (1 + m.consistencyStructure * lm) * shift
    let newtonian = m.fluidity > 0 ? rate / m.fluidity * shift : 0
    return tauY + k * pow(rate, m.flowIndex) + newtonian
  }

  static func arrhenius(_ ea: Double, _ t: Double, _ tRef: Double) -> Double {
    guard ea > 0, t > 0 else { return 1 }
    return min(max(exp(ea / ContinuumMaterial.gasConstant * (1 / t - 1 / tRef)), 1e-4), 1e4)
  }

  /// Carlson's MR yield with the toy clamp (rheology-models.md §4.2 d), after the magnetometer dead zone.
  static func fieldYield(_ m: ContinuumMaterial, field h: Double) -> Double {
    guard let f = m.field, f.yieldSaturation > 0, f.saturationField > 0 else { return 0 }
    let dead = f.deadZone / MPMConstants.vacuumPermeability
    let H = max(abs(h) - dead, 0)
    return min(f.yieldSaturation * tanh(H / f.saturationField), f.clampFractionOfG * m.shearModulus)
  }

  /// The steady state of the lagged Wyart–Cates block under steady shear γ̇: the contact fraction settles at
  /// f = c_t/c · f_ss(σ) with c = γ̇/γ* + 1/t_melt and c_t = c − w_rest/t_melt; φ_J = f·φ_m + (1 − f)·φ₀; the flowing
  /// viscosity η_s/max(gap, Δφ_min)² blends into the jammed creep G·t_jam, and above τ_jam the failure branch adds
  /// (s/η_post)(σ − τ_jam). Returns the smallest σ whose plastic rate reaches γ̇ (the branch a rising ramp follows).
  static func dst(_ d: ContinuumMaterial.DST, rate: Double, solvent: Double, jamViscosity: Double) -> Double {
    let c = rate / d.strainScale + 1 / d.meltTime
    let ct = c - min(max(d.restMelt, 0), 1) / d.meltTime
    func plasticRate(_ s: Double) -> Double {
      let fss = d.onsetForm == 0 ? 1 - exp(-s / d.onsetStress) : exp(-d.onsetStress / s)
      let f = ct / c * fss
      let phiJ = f * d.phiFrictional + (1 - f) * d.phiFrictionless
      let gap = 1 - d.phi / phiJ
      var x = min(max((d.gapFloor - gap) / d.blendWidth, 0), 1)
      x = x * x * (3 - 2 * x)
      let gm = max(gap, d.gapFloor)
      let eta = (1 - x) * solvent / (gm * gm) + x * jamViscosity
      var g = s / eta
      if x > 0, s > d.jamFailureStress { g += x / d.postFailureViscosity * (s - d.jamFailureStress) }
      return g
    }
    var lo = 1e-6
    var s = 1e-6
    while s < 1e7 {
      let next = s * 1.05
      if plasticRate(next) >= rate {
        lo = s
        var hi = next
        for _ in 0..<50 {
          let mid = 0.5 * (lo + hi)
          if plasticRate(mid) >= rate { hi = mid } else { lo = mid }
        }
        return hi
      }
      s = next
    }
    return .nan
  }
}

// MARK: - Sources

enum ToothpasteSources {
  static let merkt2004 = Citation(
    "Persistent holes in a fluid", publisher: "Merkt et al., Phys. Rev. Lett. 92, 184501 (2004)",
    url: URL(string: "https://doi.org/10.1103/PhysRevLett.92.184501")!, kind: .paper, checked: "2026-10-03")
  static let han2018 = Citation(
    "Oobleck's jamming law and packing fractions", publisher: "Han, Wyart, Peters & Jaeger, Phys. Rev. Fluids 3, 073301 (2018)",
    url: URL(string: "https://arxiv.org/abs/1711.02196")!, kind: .paper, checked: "2026-10-03")
  static let han2016 = Citation(
    "A jammed region melts once the impactor stops", publisher: "Han, Peters & Jaeger, Nat. Commun. 7, 12243 (2016)",
    url: URL(string: "https://doi.org/10.1038/ncomms12243")!, kind: .paper, checked: "2026-10-08")
  static let wyartCates2014 = Citation(
    "Discontinuous shear thickening without inertia", publisher: "Wyart & Cates, Phys. Rev. Lett. 112, 098302 (2014)",
    url: URL(string: "https://doi.org/10.1103/PhysRevLett.112.098302")!, kind: .paper, checked: "2026-10-03")
  static let waitukaitis2012 = Citation(
    "Impact-activated solidification of cornstarch", publisher: "Waitukaitis & Jaeger, Nature 487, 205 (2012)",
    url: URL(string: "https://doi.org/10.1038/nature11187")!, kind: .paper, checked: "2026-10-03")
  static let ramlawi2024 = Citation(
    "Stiffness and relaxation time of PVA–borax slime", publisher: "Ramlawi, Hossain, Shetty & Ewoldt (2024)",
    url: URL(string: "https://arxiv.org/abs/2402.19357")!, kind: .paper, checked: "2026-10-03")
  static let cross2012 = Citation(
    "Elastic and viscous properties of Silly Putty", publisher: "Cross, Am. J. Phys. 80, 870 (2012)",
    url: URL(string: "https://doi.org/10.1119/1.4732086")!, kind: .paper, checked: "2026-10-03")
  static let khaldoun2005 = Citation(
    "Liquefaction of quicksand under stress", publisher: "Khaldoun, Eiser, Wegdam & Bonn, Nature 437, 635 (2005)",
    url: URL(string: "https://doi.org/10.1038/437635a")!, kind: .paper, checked: "2026-10-03")
  static let coussot2002 = Citation(
    "Avalanche behaviour in yield stress fluids", publisher: "Coussot et al., Phys. Rev. Lett. 88, 175501 (2002)",
    url: URL(string: "https://doi.org/10.1103/PhysRevLett.88.175501")!, kind: .paper, checked: "2026-10-03")
  static let mewisWagner2009 = Citation(
    "Thixotropy", publisher: "Mewis & Wagner, Adv. Colloid Interface Sci. 147–148, 214 (2009)",
    url: URL(string: "https://doi.org/10.1016/j.cis.2008.09.005")!, kind: .paper, checked: "2026-10-03")
  static let cheng2008 = Citation(
    "Viscosity of glycerol–water mixtures", publisher: "Cheng, Ind. Eng. Chem. Res. 47, 3285 (2008)",
    url: URL(string: "https://doi.org/10.1021/ie071349z")!, kind: .paper, checked: "2026-10-03")
  static let saxena2014 = Citation(
    "Viscosity of honeys and its temperature dependence", publisher: "Saxena, Panicker & Gautam, Int. J. Food Sci. 2014, 935129",
    url: URL(string: "https://doi.org/10.1155/2014/935129")!, kind: .paper, checked: "2026-10-08")
  static let shaw1968 = Citation(
    "The viscosity of basaltic magma (Makaopuhi lava lake)", publisher: "Shaw, Wright, Peck & Okamura, Am. J. Sci. 266, 225 (1968)",
    url: URL(string: "https://doi.org/10.2475/ajs.266.4.225")!, kind: .paper, checked: "2026-10-08")
  static let pbmpm = Citation(
    "PB-MPM", publisher: "Electronic Arts SEED", url: URL(string: "https://github.com/electronicarts/pbmpm")!,
    kind: .code, licence: "BSD-3-Clause", checked: "2026-10-03")
  static let lewin2024 = Citation(
    "A Position Based Material Point Method", publisher: "Lewin, SIGGRAPH Talks (2024)",
    url: URL(string: "https://doi.org/10.1145/3641233.3664323")!, kind: .paper, checked: "2026-10-03")
  static let box2d = Citation(
    "Box2D v3.1.1", publisher: "Erin Catto", url: URL(string: "https://github.com/erincatto/box2d")!, kind: .code,
    licence: "MIT", checked: "2026-10-03")

  static let forMaterial: [MaterialID: [Citation]] = [
    "waterLike": [cheng2008],
    "honey": [saxena2014],
    "ketchup": [mewisWagner2009],
    "mayonnaise": [mewisWagner2009],
    "oobleck": [han2018, han2016, wyartCates2014, waitukaitis2012, merkt2004],
    "slime": [ramlawi2024],
    "sillyPutty": [cross2012],
    "yogurt": [mewisWagner2009],
    "quicksand": [khaldoun2005, coussot2002],
    "paint": [mewisWagner2009],
    "lava": [shaw1968],
  ]

  static let all: [Citation] = [
    han2018, han2016, wyartCates2014, waitukaitis2012, merkt2004, ramlawi2024, cross2012, khaldoun2005, coussot2002,
    mewisWagner2009, cheng2008, saxena2014, shaw1968, lewin2024, pbmpm, box2d,
  ]
}
