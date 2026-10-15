// Knobs.swift — OWNER: PLAY (was PHYS; Documentation/REDESIGN-OWNERSHIP.md).
//
// The 20 console knobs on five pages plus the Rheometer's two card knobs (labkit-from-orbitals-spectra.md §9.5),
// and the per-material re-registration of the Fluid page, the card knobs (Memory, Rebuild) and Heat for lava.
//
// Knob → material (ToothpasteEngine.applyMaterialKnobs):
//   Yield        τ_y: scales the broken and the rested part together (Pa at λ = 1).
//   Consistency  k (Pa·sⁿ), or 1/φ₀ for a pure Newtonian branch, or the solvent η_s of oobleck. One range,
//                0.001–10 000 Pa·sⁿ, for every material (Silly Putty's 2 800 Pa·s sits inside it).
//   Flow index   n (0.2–1).
//   Packing      φ of the Wyart–Cates block (oobleck only).
//   Memory       the elastic memory time λ = η/G: sets G = η_ref/λ (clamped so the yield strain stays ≤ 5 % and the
//                elastic wave fits the substep budget); for oobleck it is t_melt, how long a jam lasts at rest.
//   Rebuild      θ = t_build = 1/A₀ of thixotropic materials (ketchup, mayonnaise, yogurt, quicksand, paint).
// At its default every knob leaves the preset exactly as LabKit ships it.

import Foundation
import LabKitCore

enum ToothpasteKnobs {
  static let pages: [ConsolePage] = [
    ConsolePage("fluid", title: "Fluid", knobs: [.yield, .consistency, .index, .packing]),
    ConsolePage("world", title: "World", knobs: [.gravity, .heat, .magnet, .time]),
    ConsolePage("touch", title: "Touch", knobs: [.finger, .stir, .shake, .rate]),
    ConsolePage("signals", title: "Signals", knobs: [.listen, .drives, .gain, .band]),
    ConsolePage("view", title: "View", knobs: [.glow, .grain, .tracers, .depth]),
  ]

  static let cardKnobs: [ParamID] = [.memory, .rebuild]

  /// Every spec at the oobleck defaults; `materialSpecs(for:title:)` re-registers the material-dependent ones.
  static var all: [ParamSpec] {
    materialSpecs(for: ContinuumPresets.oobleck, title: "Oobleck") + fixed
  }

  /// The specs that follow the material: the Fluid page, Memory, Rebuild and Heat (lava re-ranges it).
  static func materialSpecs(for m: ContinuumMaterial, title: String) -> [ParamSpec] {
    fluidSpecs(for: m) + [memory(for: m, title: title), rebuild(for: m, title: title), heat(lava: m.referenceTemperature > 1000)]
  }

  // MARK: Fluid page (defaults from the material)

  /// The rested yield stress τ_y = broken + structure (λ = 1), Pa; 0 for materials without one.
  static func yieldStress(_ m: ContinuumMaterial) -> Double { m.yieldBroken + m.yieldStructure }

  /// The consistency the knob shows: k, or the Newtonian viscosity 1/φ₀, or oobleck's solvent viscosity.
  static func consistency(_ m: ContinuumMaterial) -> Double {
    if m.consistency > 0 { return m.consistency }
    if m.fluidity > 0 { return 1 / m.fluidity }
    return m.dst?.solventViscosity ?? 1e-3
  }

  /// One Consistency range for every material (Pa·sⁿ): water's 1 mPa·s to beyond Silly Putty's 2.8 kPa·s.
  static let consistencyRange: ClosedRange<Double> = 0.001...10_000

  static func fluidSpecs(for m: ContinuumMaterial) -> [ParamSpec] {
    let k = consistency(m)
    return [
      ParamSpec(
        .yield, title: "Yield", icon: "square.stack.3d.down.forward", range: 0.1...1000,
        defaultValue: max(0.1, yieldStress(m)), scale: .logarithmic,
        detents: [Detent(15, "Ketchup"), Detent(80, "Mayonnaise"), Detent(250, "Toothpaste")],
        hint: "Stress needed before it flows at all. Below it, the fluid holds its shape.",
        detail: "The yield stress τ_y. Below it the fluid is a soft solid; above it, it flows.",
        glyph: "τ_y", glyphSpoken: "tau y", descriptor: "Stress before it flows",
        format: .off(threshold: 0.1, word: "None", then: .si(unit: "Pa"))),
      ParamSpec(
        .consistency, title: "Consistency", icon: "drop.fill", range: consistencyRange,
        defaultValue: min(max(k, consistencyRange.lowerBound), consistencyRange.upperBound), scale: .logarithmic,
        detents: [Detent(0.001, "Water"), Detent(1.414, "Glycerol"), Detent(15.4, "Honey")],
        hint: "How thick it is at one shear per second.",
        detail: "K in σ = τ_y + K·γ̇ⁿ. Glycerol at 20 °C is 1.41 Pa·s; honey is about 15 Pa·s.",
        glyph: "K", descriptor: "Thickness at 1 s⁻¹", format: .si(unit: "Pa·sⁿ")),
      ParamSpec(
        .index, title: "Flow index", icon: "chart.line.downtrend.xyaxis", range: 0.2...1,
        defaultValue: m.flowIndex, detents: [Detent(0.3, "Ketchup"), Detent(1, "Newtonian")], step: 0.01,
        hint: "Below 1 it thins as you stir faster.",
        detail: "n ≤ 1: shear thinning. Thickening comes from Packing.",
        glyph: "n", descriptor: "Thins below 1", format: .number(precision: 2, unit: "")),
      ParamSpec(
        .packing, title: "Packing", icon: "circle.grid.3x3.fill", range: 0.40...0.60,
        defaultValue: m.dst?.phi ?? 0.52,
        detents: [Detent(0.465, "1 : 1"), Detent(0.52, "Oobleck"), Detent(0.581, "Jammed")], step: 0.001,
        hint: "How crowded the starch grains are. Crowded enough, a hard hit jams it solid.",
        detail: "Volume fraction φ of the Wyart–Cates model, on Han's scale: 1.2 parts starch to 1 of water is 0.52.",
        glyph: "φ", glyphSpoken: "phi", format: .number(precision: 3, unit: "")),
    ]
  }

  // MARK: Card knobs (Rheometer, large detent)

  /// The viscosity that the Memory time is measured against, Pa·s: k (with rested structure) or 1/φ₀.
  static func memoryViscosity(_ m: ContinuumMaterial) -> Double {
    if m.consistency > 0 { return m.consistency * (1 + m.consistencyStructure) }
    if m.fluidity > 0 { return 1 / m.fluidity }
    return m.dst?.solventViscosity ?? 1e-3
  }

  /// The material's elastic memory time, s: t_melt for oobleck, else λ = η_ref/G.
  static func memoryTime(_ m: ContinuumMaterial) -> Double {
    if let d = m.dst { return d.meltTime }
    return memoryViscosity(m) / max(m.shearModulus, 1)
  }

  static let memoryRange: ClosedRange<Double> = 0.001...10

  static func memory(for m: ContinuumMaterial, title: String) -> ParamSpec {
    let lambda = memoryTime(m)
    var detents = [Detent(0.402, "Slime")]
    if abs(lambda - 0.402) > 0.02, memoryRange.contains(lambda) { detents.append(Detent(lambda, title)) }
    return ParamSpec(
      .memory, title: "Memory", icon: "arrow.uturn.backward", range: memoryRange,
      defaultValue: min(max(lambda, memoryRange.lowerBound), memoryRange.upperBound),
      scale: .logarithmic, detents: detents.sorted { $0.value < $1.value },
      hint: m.dst != nil
        ? "How long a jam lasts once you stop pushing."
        : "How long it remembers its shape and springs back.",
      detail: m.dst != nil
        ? "The melt time t_melt: jammed grains let go over this time when nothing deforms them."
        : "The relaxation time λ = η/G. Longer memory: a softer, springier fluid.",
      glyph: "λ", glyphSpoken: "lambda", descriptor: m.dst != nil ? "Time a jam lasts" : "Elastic memory time",
      format: .si(unit: "s"))
  }

  static let rebuildRange: ClosedRange<Double> = 0.1...300

  /// The material's structure rebuild time t_build = 1/A₀, s, or nil without thixotropy.
  static func rebuildTime(_ m: ContinuumMaterial) -> Double? { m.buildRate > 0 ? 1 / m.buildRate : nil }

  static func rebuild(for m: ContinuumMaterial, title: String) -> ParamSpec {
    let theta = rebuildTime(m)
    return ParamSpec(
      .rebuild, title: "Rebuild", icon: "arrow.triangle.2.circlepath", range: rebuildRange,
      defaultValue: theta.map { min(max($0, rebuildRange.lowerBound), rebuildRange.upperBound) } ?? 30,
      scale: .logarithmic, detents: theta.map { [Detent($0, title)] } ?? [],
      hint: "How long its structure takes to set again.",
      detail: "The rebuild time θ = 1/A₀ of the structure λ (Moore 1959): stirring breaks it, rest rebuilds it.",
      glyph: "θ", glyphSpoken: "theta", descriptor: "Time to set again", format: .si(unit: "s"))
  }

  /// Heat, re-registered for lava (1050–1200 °C: the temperature of fresh lava; the air stays at room temperature).
  static func heat(lava: Bool) -> ParamSpec {
    if lava {
      return ParamSpec(
        .heat, title: "Heat", icon: "thermometer.medium", range: 1050...1200, defaultValue: 1170,
        detents: [Detent(1130, "Lava lake"), Detent(1170, "Kīlauea")], step: 1,
        hint: "How hot the lava erupts. It cools at the surface first.",
        glyph: "T", format: .number(precision: 0, unit: "°C"))
    }
    return ParamSpec(
      .heat, title: "Heat", icon: "thermometer.medium", range: 0...90, defaultValue: 20,
      detents: [Detent(4, "Fridge"), Detent(20, "Room"), Detent(37, "Body")], step: 1,
      hint: "Warm fluids flow more easily.", glyph: "T", format: .number(precision: 0, unit: "°C"))
  }

  // MARK: Pages that do not depend on the material

  static let fixed: [ParamSpec] = [
    ParamSpec(
      .gravity, title: "Gravity", icon: "arrow.down.to.line", range: -1...3, defaultValue: 1, origin: 0,
      detents: Gravity.detents.filter { $0.value >= 0 }, step: 0.001,
      hint: "Strength of gravity in the tank. Its direction is your phone's tilt.", glyph: "g", provenance: .live,
      format: .number(precision: 2, unit: "g")),
    ParamSpec(
      .magnet, title: "Magnet", icon: "location.north.line.fill", range: 0...500, defaultValue: 0,
      detents: [Detent(0, "Off"), Detent(207, "1 cm away")], step: 1,
      hint: "A magnet under the tank's floor. Drag its marker to move it. Iron in MR fluid chains up and stiffens.",
      glyph: "B",
      format: .off(threshold: 0.5, word: "Off", then: .number(precision: 0, unit: "mT"))),
    ParamSpec(
      .time, title: "Time", icon: "hourglass", range: 0.05...2, defaultValue: 1, scale: .logarithmic,
      detents: [Detent(0.25, "Slow motion"), Detent(1, "Real time")], hint: "Simulation speed.",
      provenance: .illustrative, format: .multiplier(precision: 2)),
    ParamSpec(
      .finger, title: "Finger", icon: "hand.point.up.left.fill", range: 3...20, defaultValue: 8,
      detents: [Detent(8, "Fingertip")], step: 0.5, hint: "Size of the probe your finger pushes through the fluid.",
      glyph: "r", format: .number(precision: 1, unit: "mm")),
    ParamSpec(
      .stir, title: "Stir", icon: "arrow.trianglehead.2.clockwise.rotate.90", range: 0...5, defaultValue: 0,
      detents: [Detent(0, "Off")], step: 0.05, hint: "A paddle turning at the tank's centre.", glyph: "ω",
      glyphSpoken: "omega", format: .off(threshold: 0.02, word: "Off", then: .number(precision: 2, unit: "rev/s"))),
    ParamSpec(
      .shake, title: "Shake", icon: "water.waves", range: 0...27, defaultValue: 0,
      detents: [Detent(0, "Off"), Detent(10, "Holes"), Detent(17, "Fingers")], step: 0.1,
      hint: "Peak acceleration of a vibrating floor, like a speaker under a tray.", glyph: "a",
      provenance: .simulated, format: .off(threshold: 0.05, word: "Off", then: .number(precision: 1, unit: "g"))),
    ParamSpec(
      .rate, title: "Rate", icon: "metronome.fill", range: 20...200, defaultValue: 120, scale: .logarithmic,
      detents: [Detent(50, "50 Hz"), Detent(120, "Monsters")], hint: "How fast the floor vibrates.", glyph: "f",
      format: .number(precision: 0, unit: "Hz")),
    ParamSpec(
      .listen, title: "Listen", icon: "ear.fill", range: 0...1, defaultValue: 0, detents: [Detent(0, "Off")],
      step: 0.01, hint: "How hard sound shakes the tank. The first turn asks for the microphone.", provenance: .live,
      format: .off(threshold: 0.005, word: "Off", then: .percent)),
    ParamSpec(
      .drives, title: "Drives", icon: "slider.horizontal.3", range: 0...4, defaultValue: 0, step: 1,
      hint: "What sound moves: the floor's shake, gravity, the paddle, a kick per beat, or the heat.",
      provenance: .live, format: .labels(["Shake", "Gravity", "Stir", "Kicks", "Heat"])),
    ParamSpec(
      .gain, title: "Gain", icon: "dial.medium", range: 0.25...8, defaultValue: 1, scale: .logarithmic,
      detents: [Detent(1, "Unity")], hint: "Microphone sensitivity.", provenance: .live,
      format: .multiplier(precision: 2)),
    ParamSpec(
      .band, title: "Band", icon: "waveform", range: 40...2000, defaultValue: 80, scale: .logarithmic,
      detents: [Detent(80, "Bass"), Detent(300, "Voice")], hint: "Which pitches drive the tank.", glyph: "f",
      provenance: .live, format: .si(unit: "Hz")),
    ParamSpec(
      .glow, title: "Glow", icon: "sun.max.fill", range: 0...1, defaultValue: 0.6, detents: [Detent(0, "Off")],
      step: 0.01, hint: "Lights the fluid by how hard it is being sheared.", provenance: .illustrative,
      format: .off(threshold: 0.005, word: "Off", then: .percent)),
    ParamSpec(
      .grain, title: "Grain", icon: "circle.dotted", range: 0...1, defaultValue: 0.5, detents: [Detent(0, "Off")],
      step: 0.01, hint: "Speckle that moves with the fluid.", provenance: .illustrative,
      format: .off(threshold: 0.005, word: "Off", then: .percent)),
    ParamSpec(
      .tracers, title: "Tracers", icon: "scribble.variable", range: 0...1, defaultValue: 0.3,
      detents: [Detent(0, "Off")], step: 0.01, hint: "Dye lines that follow the flow.", provenance: .illustrative,
      format: .off(threshold: 0.005, word: "Off", then: .percent)),
    ParamSpec(
      .depth, title: "Depth", icon: "cube.transparent", range: 0...1, defaultValue: 0.5, step: 0.01,
      hint: "Exaggerates the tank's thickness in the shading.", provenance: .illustrative, format: .percent),
  ]
}
