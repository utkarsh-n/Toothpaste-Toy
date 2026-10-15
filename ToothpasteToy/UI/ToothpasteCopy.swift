// ToothpasteCopy.swift — OWNER: UI (Documentation/REDESIGN-OWNERSHIP.md).
//
// Every user-facing string the UI owns, in one place, so `UITests` can lint all of it: British spelling, UI named by its
// live labels, short Metro captions (all caps, tracked) and sentence-case prose, no "simply", "just", "we" or
// exclamation marks. Numbers carry SI units; whole quantities print whole digits (Metro contract 6). Honesty: the physics
// is classical (2D elasto-viscoplastic MPM); "quantum hologram" is a visual style and every surface that mentions it
// says so (REDESIGN.md §6). Wave springs animate the interface only; the paste's motion is the simulation's.

import Foundation
import LabKitCore
import LabKitMPM
import LabKitSensors
import SwiftUI

/// A status banner: one symbol and one human sentence, what VoiceOver says when that differs, and the symbol's colour.
struct ToothpasteBanner: Equatable, Sendable {
  enum Kind: String, Sendable, Equatable {
    case material, prop, experiment, micOn, micDenied, micFailed, slowMotion, magnet, simulatedMotion, quality
  }
  var kind: Kind
  var text: String
  var icon: String
  var spoken: String?
  var tint: LabColor?
}

@MainActor enum ToothpasteCopy {
  // MARK: Names and numbers

  static let appTitle = "Toothpaste Toy"

  /// A material's name inside a sentence: "oobleck", "honey", but "MR fluid" and "Silly Putty" keep their capitals.
  static func inSentence(_ title: String) -> String {
    guard let first = title.first else { return title }
    if title.dropFirst().contains(where: \.isUppercase) { return title }
    return first.lowercased() + title.dropFirst()
  }

  /// "×2", "×0.66", "×1.50".
  static func multiplier(_ x: Double) -> String {
    let whole = x.rounded()
    if abs(x - whole) < 0.005 { return "×" + String(Int(whole)) }
    return "×" + LabFormat.fixed(x, precision: 2)
  }

  /// Three significant figures, whole digits from 100 up.
  static func sig3(_ v: Double) -> String {
    let a = abs(v)
    let digits = a >= 99.95 ? 0 : a >= 9.995 ? 1 : a >= 0.9995 ? 2 : 3
    return String(format: "%.\(digits)f", v)
  }

  /// A quantity split into rounded numerals and a monospaced unit, with a k or m prefix where it reads better:
  /// 250 Pa, 12.4 Pa·s, 1.20 kPa, 3.40 mPa·s, 1.20k s⁻¹.
  static func quantity(_ v: Double, unit: String) -> (value: String, unit: String) {
    guard v.isFinite, v > 0 else { return ("0", unit) }
    let pascals = unit.hasPrefix("Pa")
    if v >= 999.5 {
      return pascals ? (sig3(v / 1000), "k" + unit) : (sig3(v / 1000) + "k", unit)
    }
    if pascals, v < 0.09995 { return (sig3(v * 1000), "m" + unit) }
    return (sig3(v), unit)
  }

  /// A ratio to two significant figures for prose: "230", "65", "4.2".
  static func twoFigures(_ x: Double) -> String {
    guard x.isFinite, x > 0 else { return "—" }
    let e = floor(log10(x)) - 1
    let r = (x / pow(10, e)).rounded() * pow(10, e)
    return r >= 10 ? String(Int(r)) : LabFormat.fixed(r, precision: 1)
  }

  /// A length in metres as millimetres for prose: "10", "2.0", "4.9".
  static func millimetres(_ metres: Double) -> String {
    let v = metres * 1000
    if v >= 9.95 || abs(v - v.rounded()) < 0.005 { return String(Int(v.rounded())) }
    return LabFormat.fixed(v, precision: 1)
  }

  // MARK: Header

  static func subtitle(_ m: MaterialInfo) -> String { "HOLO CHAMBER · \(LabFormat.uppercasedLatin(m.title))" }
  static func subtitleSpoken(_ m: MaterialInfo) -> String { "Holo chamber, \(inSentence(m.title)) in the tube" }
  static let otherPastes = "Other pastes"
  static let more = "More"
  static let done = "Done"

  // MARK: Squeeze

  static let squeezeTitle = "Squeeze"
  static let squeezingTitle = "Squeezing"
  static let squeezeCaption = "SQUEEZE"
  static let ribbonCaption = "RIBBON"
  static let squeezeCrownLabel = "Squeeze cap"
  static let squeezeCrownHint =
    "Hold to squeeze paste out of the nozzle. Turn it either way to squeeze faster. Let go to tear the ribbon off."
  static let squeezeButtonHint = "Hold to squeeze a ribbon of paste. Let go to tear it off."
  static let squeezeRequestedLabel = "Squeeze rate"
  static let ribbonLabel = "Ribbon"
  static func squeezeSpoken(rate: Double) -> String {
    rate > 0 ? "\(Int(rate.rounded())) millimetres per second" : "Not squeezing"
  }
  static func ribbonSpoken(millimetres: Int, emitting: Bool) -> String {
    emitting ? "\(millimetres) millimetres and growing" : millimetres > 0 ? "\(millimetres) millimetres" : "None"
  }

  // MARK: Status

  static func clockState(paused: Bool, slowMotion: Bool) -> (String, Color) {
    if paused { return ("FROZEN", Metro.Colour.actionAmber.color) }
    if slowMotion { return ("SLOW", Metro.Colour.carrier.color) }
    return ("LIVE", Metro.Colour.actionCyan.color)
  }
  static func timeTag(_ scale: Double) -> String { "TIME " + multiplier(scale) }

  // MARK: Chamber

  static func chamberLabel(_ m: MaterialInfo) -> String { "Holo chamber, \(inSentence(m.title))" }
  static let chamberHint = "Drag to move the glass lens through the paste. Two fingers tilt in the simulator."

  /// The chamber's accessibility value: a parseable sentence.
  static func chamberValue(
    _ t: ToothpasteTelemetry, channels c: PasteChannels, material m: MaterialInfo, paused: Bool
  ) -> String {
    var parts = [
      m.title, paused ? "Time frozen" : stateWord(c.state).capitalized,
      "Shear rate \(LabFormat.spoken(quantityText(c.shear.value, unit: "s⁻¹")))",
      "Stress \(LabFormat.spoken(quantityText(c.stress.value, unit: "Pa")))",
      "Tilt \(Int(t.tiltDegrees.rounded())) degrees",
      "\(Int((t.fillFraction * 100).rounded())) percent full",
    ]
    if abs(t.timeScale - 1) > 0.005 { parts.append("Time \(LabFormat.spoken(multiplier(t.timeScale)))") }
    return parts.joined(separator: ". ") + "."
  }

  static func quantityText(_ v: Double, unit: String) -> String {
    let q = quantity(v, unit: unit)
    return "\(q.value) \(q.unit)"
  }

  static let actionPoke = "Poke the paste"
  static let actionSqueeze = "Squeeze a ribbon"
  static let actionPunch = "Punch"
  static let actionTiltLeft = "Tilt left"
  static let actionTiltRight = "Tilt right"
  static let actionShake = "Shake"
  static let actionRefill = "Refill"
  static var actionNames: [String] {
    [actionPoke, actionSqueeze, actionPunch, actionTiltLeft, actionTiltRight, actionShake, actionRefill]
  }

  // MARK: Signals

  static func pillLabel(_ s: PasteSignal) -> String {
    switch s {
    case .shear: "Shear rate, gamma dot"
    case .stress: "Stress, sigma"
    case .structure: "Structure, lambda"
    }
  }

  /// A pill's spoken value: the SI value, where it sits on the pill's scale, and what the scale is.
  static func pillSpoken(_ s: PasteSignal, channels c: PasteChannels) -> String {
    let percent: (Double) -> String = { "\(Int(($0 * 100).rounded())) percent up the scale" }
    switch s {
    case .shear:
      return "\(LabFormat.spoken(quantityText(c.shear.value, unit: "s⁻¹"))), \(percent(c.shear.level)), logarithmic from 0.01 to 1000 per second"
    case .stress:
      return "\(LabFormat.spoken(quantityText(c.stress.value, unit: "Pa"))), \(percent(c.stress.level)), logarithmic from 1 to 10000 pascals"
    case .structure:
      return "\(Int((c.structure.value * 100).rounded())) percent structure, from 0 for fully broken to 1 for fully set"
    }
  }

  static let lensTitle = "AT THE LENS"
  static let probeTitle = "MOST SHEARED"
  static let lensSpokenTitle = "At the lens"
  static let probeSpokenTitle = "At the most sheared spot"

  static func stateWord(_ s: PasteStateWord) -> String {
    switch s {
    case .holding: "holding"
    case .yielding: "yielding"
    case .flowing: "flowing"
    case .jammed: "jammed"
    }
  }

  static func stateMeaning(_ s: PasteStateWord) -> String {
    switch s {
    case .holding: "holds its shape"
    case .yielding: "giving way"
    case .flowing: "flows like a liquid"
    case .jammed: "jammed solid"
    }
  }

  static func lensSpoken(_ c: PasteChannels) -> String {
    "Shear rate \(LabFormat.spoken(quantityText(c.shear.value, unit: "s⁻¹"))), stress \(LabFormat.spoken(quantityText(c.stress.value, unit: "Pa"))), \(stateWord(c.state)): \(stateMeaning(c.state))"
  }

  static let eventsTitle = "Paste events"
  static func eventTile(_ k: PasteEvent.Kind) -> String {
    switch k {
    case .yield: "YIELD"
    case .jam: "JAM"
    case .tearOff: "TEAR-OFF"
    case .impact: "IMPACT"
    }
  }
  static func eventsSpoken(_ counts: [(PasteEvent.Kind, Int)]) -> String {
    counts.map { kind, n in
      let name: String
      switch kind {
      case .yield: name = n == 1 ? "yield" : "yields"
      case .jam: name = n == 1 ? "jam" : "jams"
      case .tearOff: name = n == 1 ? "tear-off" : "tear-offs"
      case .impact: name = n == 1 ? "impact" : "impacts"
      }
      return "\(n) \(name)"
    }.joined(separator: ", ") + " since the last refill"
  }

  // MARK: Telemetry

  static let yieldLabel = "YIELD"
  static let viscosityLabel = "VISCOSITY"
  static let tiltLabel = "TILT"

  static func yieldReadout(_ tauY: Double, spec: ParamSpec) -> (value: String, unit: String) {
    tauY <= 0.1 + 1e-9 ? ("None", "") : quantity(tauY, unit: "Pa")
  }
  static func yieldSpoken(_ tauY: Double, spec: ParamSpec) -> String {
    tauY <= 0.1 + 1e-9 ? "No yield stress" : "Yield stress \(spec.accessibilityValue(tauY))"
  }
  static func viscositySpoken(_ eta: Double) -> String {
    "Mean viscosity of the flowing paste, \(LabFormat.spoken(quantityText(eta, unit: "Pa·s")))"
  }
  static func tiltSpoken(_ degrees: Int) -> String { "\(degrees) degrees from level" }

  // MARK: Crowns

  static let gravityTitle = "Gravity"
  static let gravityHint = "Steps between Zero-g, the Moon, Mars, Earth and Jupiter. Turn the crown or use plus and minus."
  static let strongerGravity = "Stronger gravity"
  static let weakerGravity = "Weaker gravity"
  static func gravityCaption(here: String?, value: String) -> String { "GRAVITY · \(here ?? value)" }

  static let heatTitle = "Heat"
  static let heatHint = "One degree per detent. Warm paste flows more easily."
  static let warmer = "Warmer"
  static let cooler = "Cooler"
  static func heatCaption(_ value: String) -> String { "HEAT · \(value)" }
  static func heatFooter(named: String?) -> String { named.map { "\($0) · ±1 °C" } ?? "±1 °C" }

  // MARK: Floating actions

  static let refillLabel = "Refill"
  static let refillCaption = "REFILL"
  static let freezeLabel = "Freeze time"
  static let freezeCaption = "FREEZE"
  static let resumeLabel = "Resume time"
  static let resumeCaption = "RESUME"
  static let rheometer = "Rheometer"
  static let flowCaption = "FLOW"
  static let howItWorks = "How Toothpaste Toy works"
  static let infoCaption = "INFO"

  // MARK: Pastes

  static let pastesTitle = "Pastes"
  static let heroMeaning = "the hero"
  static func heroLine(yield tauY: Double) -> String {
    "YIELD \(quantityText(tauY, unit: "Pa")) · STACKS AND HOLDS"
  }
  static let inTheTube = "In the tube"
  static func tileHint(_ m: MaterialInfo) -> String { "\(m.hint). Fills the chamber." }
  static let pastesFootnote =
    "Each paste keeps its own measured flow curve. The chamber refills with the one you choose, and the tube squeezes it."

  // MARK: More

  static let tubeSection = "Tube"
  static let stripesLabel = "STRIPES"
  static func bandsUnit(_ n: Int) -> String { n == 1 ? "band" : "bands" }
  static let boreLabel = "BORE"
  static let tubeFootnote = "Stripes are dye carried by the paste, so they stretch, fold and coil with it. 0 squeezes plain paste."
  static let timeSection = "Time"
  static let timePresets = "Time presets"
  static let slowMotionPreset = "Slow motion"
  static let realTimePreset = "Real time"
  static func pasteSection(_ m: MaterialInfo) -> String { "The paste: \(m.title)" }
  static func pasteValues(_ m: MaterialInfo) -> String { "Back to \(inSentence(m.title))'s own values" }
  static let pasteFootnote = "Set by the paste. Turn them to make your own; a refill keeps them."
  static func dimmedNote(_ title: String) -> String { "\(title) does nothing for this paste." }
  static let shakeSection = "Shake and stir"
  static let listenSection = "Sound in the room"
  static let listenFootnote =
    "Turn up Listen and make a noise: sound drives what Drives points at. Toothpaste Toy asks for the microphone then, and keeps nothing it hears."
  static let magnetSection = "Magnet"
  static let magnetFootnote = "A magnet under the floor stiffens MR fluid. It does nothing to the other pastes."
  static let lookSection = "Look"
  static let solidLook = "Solid paste instead of the hologram"
  static let stressLight = "Stress light"
  static let dyeLines = "Dye lines"
  static let particles = "Particles"
  static let rheometerCursor = "Rheometer cursor"
  static let colourBy = "Colour by"
  static func colourByTitle(_ d: FluidDiagnostic) -> String { d == .none ? "Hologram" : d.title }
  static let lookFootnote =
    "The quantum hologram is a look: the shimmer, ghosts and fringes are drawn, not simulated. Colour by paints a measured quantity instead."
  static let sensorsSection = "Sensors"
  static let useTilt = "Use tilt"
  static let useMagnetometer = "Use the magnetometer"
  static let feelSectionTitle = "Sound and feel"
  static let hapticsToggle = "Haptics"
  static let feelToggle = "Feel the paste"
  static let soundToggle = "Sound"
  static let feelFootnote = "Haptics: crown detents and taps. Feel the paste: a buzz while the lens or the nozzle works the paste."
  static let experimentsSection = "Experiments"
  static let explainSection = "Explain"
  static let backToDefaults = "Back to defaults"
  static let backToDefaultsNote = "Every knob back to the paste's values, props cleared, and a fresh chamber."

  // MARK: Rheometer

  static let curveSwitchLabel = "Plot stress or viscosity"
  static let flowCurveTitle = "FLOW CURVE · σ(γ̇)"
  static let viscosityCurveTitle = "VISCOSITY · η(γ̇)"
  static let literature = "Published measurements"
  static let probeViscosity = "Viscosity"
  static let stressLabel = "Stress"
  static let shearLabel = "Shear rate"
  static let rheometerCaption =
    "Lines: modelled steady flow curves at the chamber's temperature. Hollow rings: published measurements. The pink ring is the probe in the chamber, live: the lens, or the most sheared spot."

  /// The plot's VoiceOver summary, regenerated per material.
  static func plotSummary(_ m: MaterialInfo, catalog: any ToothpasteCatalog, temperature: Double) -> String {
    let rates = (0..<41).map { pow(10, -2 + Double($0) * 0.125) }
    let sigma = catalog.flowCurve(m.id, shearRates: rates, temperature: temperature)
    let yieldStress = ToothpasteKnobs.yieldStress(m.material)
    let shape: String
    if m.material.dst != nil {
      if let i = sigma.firstIndex(where: { !$0.isFinite }), i > 0 {
        shape = "\(m.title) flows at low shear rates and jams above about \(LabFormat.sig3(rates[i])) per second."
      } else {
        shape = "\(m.title) flows, then stiffens as it is sheared faster."
      }
    } else if yieldStress > 0.5 {
      shape = "\(m.title) holds below a \(LabFormat.sig3(yieldStress)) pascal yield stress, then flows and thins."
    } else if abs(m.material.flowIndex - 1) < 0.02, let s = sigma.first(where: \.isFinite), let r = rates.first {
      shape = "\(m.title) is a straight line: Newtonian, \(LabFormat.spoken(LabFormat.engineering(s / r, unit: "Pa·s")))."
    } else {
      shape = "\(m.title) thins as it is sheared faster."
    }
    return shape + " The other pastes are faint. The pink ring is the probe in the chamber."
  }

  // MARK: Info sheet

  /// REDESIGN.md §6, verbatim.
  static let honestySentence =
    "The paste obeys real yield-stress physics. The quantum shimmer, ghosts and fringes are a hologram look, not quantum mechanics."
  static let panelLooking = "What you're looking at"
  static let panelPlay = "Play"
  static let panelHologram = "The hologram"
  static let panelControls = "The controls"
  static let panelExperiments = "Experiments"
  static let panelHonesty = "What's real and what's illustrative"
  static let panelSensors = "Sensors in play"
  static let panelFeel = "Sound and feel"
  static let panelSources = "Sources and licences"

  static let introLine =
    "A quantum hologram of toothpaste you can squeeze, poke, stack, tilt and shake: real yield-stress physics, rendered as light."
  static func introDetail(tank: SIMD2<Double>, lifeSize: Bool, scale: Double?, materials: Int) -> String {
    let w = Int((tank.x * 1000).rounded()), h = Int((tank.y * 1000).rounded())
    let size =
      lifeSize
      ? "The chamber holds a \(w) × \(h) mm tank, drawn life-size."
      : scale.map { "The chamber holds a \(w) × \(h) mm tank, drawn at \(multiplier($0)) on this phone so the controls fit beside it." }
        ?? "The chamber holds a \(w) × \(h) mm tank, drawn to fit this screen."
    return "\(size) Toothpaste is the hero; \(materials - 1) other pastes, from water to lava, wait under Other pastes, each with its own flow curve, drawn below in its colour. \(oobleckRecipe)"
  }
  /// The only place the UI names oobleck's recipe.
  static let oobleckRecipe = "Oobleck is cornflour (cornstarch) and water."
  static let introCaption =
    "Modelled steady flow curves at the chamber's temperature, one colour per paste. Rings: published measurements."

  static let playNotes: [(title: String, text: String)] = [
    ("Squeeze",
     "Hold Squeeze, or hold the knurled cap above the chamber and turn it: the faster you turn, the faster paste leaves the nozzle, striped white, cyan and violet. Let go and the ribbon tears off. Toothpaste stacks into a coil that holds its shape, because below its yield stress it is a soft solid."),
    ("The glass lens",
     "Drag anywhere in the chamber and the glass lens follows your fingertip through the paste: cut the ribbon, poke dents that stay, smear it. The readout beside the chamber shows the shear rate, the stress and what the paste is doing at the lens. Let go and the lens glides back to its dock."),
    ("Tilt",
     "Tilt your phone. The pile leans but holds until the slope beats its yield stress, then it slides. In the simulator, drag with two fingers to tilt."),
    ("Shake",
     "Shake your phone. Below its yield stress the paste jiggles like jelly; shake harder and it breaks into flow. More has a vibrating floor too."),
    ("Gravity",
     "Turn Gravity to the Moon and the coils stand taller; on Jupiter they slump. Each step is a real world's surface gravity."),
    ("Heat",
     "Turn Heat up and most pastes run thinner; honey most of all. Lava crusts as it cools."),
    ("Other pastes",
     "The same chamber, other personalities: oobleck jams under a fast lens and flashes amber, honey drips through the stripes, ketchup thins when shaken."),
    ("Freeze and refill",
     "Freeze stops time: the paste holds still while you look. Refill gives a fresh chamber with a short striped coil on the floor."),
  ]

  struct LegendItem {
    let title: String
    let text: String
    let colour: Metro.RGB
  }

  static let hologramLegend: [LegendItem] = [
    LegendItem(
      title: "Cyan: flow", text: "Where the paste flows and shears, it glows cyan, brighter the faster it is sheared.",
      colour: Metro.Colour.instrumentCyan),
    LegendItem(
      title: "Amber: events", text: "A yield, a jam or a tear-off flashes amber where it happens, then fades.",
      colour: Metro.Colour.instrumentAmber),
    LegendItem(
      title: "Violet: structure",
      text: "Structure and memory: a paste that has set glows violet; stirring breaks it and the violet fades.",
      colour: Metro.Colour.spectrum),
    LegendItem(
      title: "Stripes",
      text: "Toothpaste's three stripes are dye carried by the paste, a white core between cyan and violet bands, so they stretch, fold and coil with the flow.",
      colour: Metro.Colour.displayInk),
    LegendItem(
      title: "Rim, fringes and scanlines",
      text: "A bright rim traces the paste's outline; thin-film fringes shift hue as you tilt the phone; fine scanlines sit over it like a projection.",
      colour: Metro.Colour.wave),
    LegendItem(
      title: "Shimmer and ghosts",
      text: "Each simulation particle is a faint point that flickers, and fast paste leaves two or three fading echoes for about a fifth of a second.",
      colour: Metro.Colour.spectrumDepth),
  ]

  static func hologramIdentity(_ m: MaterialInfo) -> String {
    switch m.id {
    case "toothpaste": "three bands, white, cyan and violet."
    case "honey": "amber glass."
    case "oobleck": "milky foam that flashes amber when it jams."
    case "mrFluid": "metallic violet with field lines."
    case "lava": "amber-white light that dims as it cools."
    default: "its own tint and fringes."
    }
  }

  static func controlNotes(gravity: ParamSpec, heat: ParamSpec) -> [(title: String, text: String)] {
    let worlds = NamedDetents.list(gravity).map { "\($0.label) \(gravity.formatted($0.value))" }.joined(separator: ", ")
    return [
      ("Crowns",
       "Gravity is a semantic crown: each amber detent is a named world (\(worlds)). Heat is a fine crown: each cyan detent is 1 °C, from \(heat.formatted(heat.range.lowerBound)) to \(heat.formatted(heat.range.upperBound)). Turn the knurled face or use plus and minus; each accepted step clicks once."),
      ("Signal pills",
       "Three channels beside the chamber, measured at the lens (or the most sheared spot): γ̇ shear rate in cyan, σ stress in amber, both on logarithmic scales, and λ structure in violet, from 0 broken to 1 set. The column is the level now; the faint trail is the last three seconds."),
      ("Lens readout",
       "The shear rate and stress at the lens, and a word for the paste there: holding, yielding, flowing or jammed. It stays still and unfiltered whatever the hologram does."),
      ("Event tiles",
       "Yields, jams and tear-offs since the last refill. Each lights amber when it happens."),
      ("Telemetry",
       "The paste's yield stress τ_y, the mean viscosity η of the paste that is flowing, and the phone's tilt from level."),
      ("Motion",
       "Every interface motion runs on springs, so the lens, the crowns and the numbers carry their speed and can be caught mid-flight. The springs move the interface only; the paste moves by its physics."),
    ]
  }

  static let perPasteHeader = "Each paste: what's real and what's tuned"
  static let realTitle = "Real"
  static let tunedTitle = "Tuned"

  /// Panel 06 with this build's numbers (`gap` and `cell` from the solver's domain, m). `scale`: the chamber's drawn scale,
  /// nil on a phone whose screen size Toothpaste Toy doesn't know (then it claims none).
  static func honesty(
    tank: SIMD2<Double>, gap: Double, cell: Double, lifeSize: Bool, scale: Double?, honeyRatio: Double
  ) -> [String] {
    let w = Int((tank.x * 1000).rounded()), h = Int((tank.y * 1000).rounded())
    let mm = millimetres
    return [
      "The physics is classical: a 2D elasto-viscoplastic continuum simulated with particles on a grid. Yield stresses, viscosities, flow indices, densities and gravity come from measurements and the literature.",
      "The look is not. The hologram's shimmer, ghosts, fringes, scanlines and glow are drawn over the simulated paste; nothing quantum is computed.",
      "It is a thin slice. Everything moves in the plane of the screen, between glass about \(mm(gap)) mm apart that adds a light drag.",
      "What 2D changes. A ribbon folds instead of coiling in 3D, threads tear instead of pinching into drops, and oobleck's jammed front is a slice of a 3D one.",
      "Stiffness is softened. Real paste carries sound at about 1.5 km/s; the chamber uses a few metres per second so it runs on a phone. Flow, yield and viscosity are not softened.",
      "Resolution. The grid's cells are \(mm(cell)) mm, so anything thinner than about \(Int((cell * 2500).rounded())) mm is smoothed.",
      lifeSize
        ? "The tank is drawn life-size: \(w) × \(h) mm on this phone."
        : scale.map { "The tank is \(w) × \(h) mm, drawn at \(multiplier($0)) on this phone." }
          ?? "The tank is \(w) × \(h) mm, drawn to fit this screen.",
      "Gravity is real. The Moon and Jupiter detents use their true values, and a paste holds a taller peak in weaker gravity.",
      "Temperature follows measured laws: honey is about \(twoFigures(honeyRatio)) times runnier at 60 °C than at 10 °C.",
      "Time runs at the speed shown above the signal pills. If the phone can't keep up, the clock slows and the tag says SLOW.",
      "The springs that move the lens, the crowns and the numbers are interface motion, not physics.",
      "γ̇, σ, η and λ are read from the simulation at the probe: modelled, not measured.",
    ]
  }

  static let sensorsIntro =
    "Toothpaste Toy reads these as you play. Simulated values stand in for a sensor this device doesn't have or hasn't allowed."
  static let rowTilt = "Tilt"
  static let rowShake = "Shake"
  static let rowField = "Field"
  static let rowMic = "Mic"
  static let rowHeat = "Heat"
  static var rowTitles: [String] { [rowTilt, rowShake, rowField, rowMic, rowHeat] }
  static func tiltValue(_ degrees: Double) -> String { "\(Int(degrees.rounded()))° from level" }
  static func shakeValue(_ g: Double) -> String { LabFormat.fixed(g, precision: 2) + " g" }
  static func fieldValue(_ microTesla: Double, enabled: Bool) -> String {
    enabled ? "\(Int(microTesla.rounded())) µT" : "Off"
  }
  static func micValue(_ state: MicState, dBFS: Double?) -> String {
    switch state {
    case .on: dBFS.map { LabFormat.fixed($0, precision: 0) + " dBFS" } ?? "Listening"
    case .starting: "Starting"
    case .denied: "Not allowed"
    case .failed: "Unavailable"
    case .off: "Off"
    }
  }
  static func heatValue(_ state: ProcessInfo.ThermalState) -> String {
    switch state {
    case .nominal: "Phone cool"
    case .fair: "Phone warm"
    case .serious: "Phone hot"
    case .critical: "Phone very hot"
    @unknown default: "Phone warm"
    }
  }
  static let micHint = "Turn up Listen in More to let sound shake the chamber. Toothpaste Toy asks for the microphone then."
  static let micDeniedTitle = "Microphone off"
  static let micDeniedText =
    "Toothpaste Toy can't hear the room. Allow the microphone in Settings to let sound shake the paste. Everything else keeps working."
  static let feelExplanation = "A buzz while the lens or the nozzle works the paste, stronger as it resists."
  static let soundExplanation = "The paste squishes and creaks at a pitch set by how thick it is. Follows the silent switch."

  static let papersHeader = "Papers"
  static let codeHeader = "Code and licences"
  static let licenceDisclosure = "Licence texts"

  static func method(particles: Int, cell: Double) -> String {
    let rounded = Int((Double(particles) / 100).rounded()) * 100
    let count = particles > 0 ? "about \(rounded) particles" : "particles"
    return "The physics is position-based MPM on the GPU: \(count) on a \(millimetres(cell)) mm grid, an elasto-viscoplastic flow law and the Wyart–Cates jamming law for oobleck, checked against a CPU reference. Props are Box2D rigid bodies. Interface motion uses Wave springs."
  }
  static let privacy =
    "Toothpaste Toy keeps nothing. Sound is analysed in memory as it arrives and is never recorded, stored or sent. Motion and magnetometer readings stay on the phone."

  // MARK: Banners

  static func materialBanner(_ m: MaterialInfo) -> ToothpasteBanner {
    ToothpasteBanner(kind: .material, text: "\(m.title). \(m.hint).", icon: m.icon, tint: LabPalette.rheo.data(m.id))
  }

  static func propBanner(_ p: PropInfo) -> ToothpasteBanner {
    ToothpasteBanner(kind: .prop, text: "\(p.title). \(p.hint).", icon: p.icon)
  }

  static func experimentBanner(_ e: Experiment) -> ToothpasteBanner {
    ToothpasteBanner(kind: .experiment, text: e.note.isEmpty ? e.title : e.note, icon: e.icon, spoken: e.announcement)
  }

  /// `drives`: the Drives knob's label ("Shake").
  static func micOnBanner(drives: String) -> ToothpasteBanner {
    ToothpasteBanner(kind: .micOn, text: "Listening. The room's sound drives \(drives).", icon: "mic.fill", tint: LabSemantic.live)
  }

  static let micDenied = ToothpasteBanner(
    kind: .micDenied, text: micDeniedText, icon: "mic.slash.fill", tint: LabSemantic.warning)
  static let micFailed = ToothpasteBanner(
    kind: .micFailed, text: "The microphone didn't start. Everything else keeps working.", icon: "mic.slash.fill",
    tint: LabSemantic.warning)
  static let slowMotion = ToothpasteBanner(
    kind: .slowMotion, text: "Slow motion. The phone can't keep up, so the paste runs slower than real time.",
    icon: "tortoise.fill", tint: LabSemantic.simulated)
  static let simulatedNote = "Simulated motion. Drag in the chamber with two fingers to tilt."
  static let simulatedMotion = ToothpasteBanner(
    kind: .simulatedMotion, text: simulatedNote, icon: "iphone.motion", tint: LabSemantic.simulated)
  static let qualityChanged = ToothpasteBanner(
    kind: .quality, text: "Resolution changed to keep the frame rate.", icon: "square.grid.3x3")

  static func magnetBanner(microTesla: Double, isMR: Bool) -> ToothpasteBanner {
    let field = "\(Int(microTesla.rounded())) µT"
    let rest = isMR ? "The MR fluid stiffens." : "Choose MR fluid in Other pastes to watch it stiffen."
    return ToothpasteBanner(
      kind: .magnet, text: "Magnet nearby: \(field) at the phone's sensor. \(rest)", icon: "location.north.line.fill",
      tint: LabPalette.rheo.hue(for: .magnet))
  }

  // MARK: Lint

  /// Every fixed and generated string above, for `UITests`' CopyLint pass.
  static func allStrings(catalog: any ToothpasteCatalog, store: ParamStore) -> [String] {
    let c = PasteChannels()
    var all: [String] = [
      appTitle, otherPastes, more, done, squeezeTitle, squeezingTitle, squeezeCaption, ribbonCaption, squeezeCrownLabel,
      squeezeCrownHint, squeezeButtonHint, squeezeRequestedLabel, ribbonLabel, squeezeSpoken(rate: 0),
      squeezeSpoken(rate: 24), ribbonSpoken(millimetres: 38, emitting: true), ribbonSpoken(millimetres: 0, emitting: false),
      timeTag(0.25), chamberHint, lensTitle, probeTitle, lensSpokenTitle, probeSpokenTitle, lensSpoken(c), eventsTitle,
      eventsSpoken([(.yield, 1), (.jam, 2), (.tearOff, 3)]), yieldLabel, viscosityLabel, tiltLabel,
      viscositySpoken(12.4), tiltSpoken(12), gravityTitle, gravityHint, strongerGravity, weakerGravity,
      gravityCaption(here: "Moon", value: "0.17 g"), heatTitle, heatHint, warmer, cooler, heatCaption("20 °C"),
      heatFooter(named: "Room"), heatFooter(named: nil), refillLabel, refillCaption, freezeLabel, freezeCaption,
      resumeLabel, resumeCaption, rheometer, flowCaption, howItWorks, infoCaption, pastesTitle, heroMeaning,
      heroLine(yield: 250), inTheTube, pastesFootnote, tubeSection, stripesLabel, bandsUnit(1), bandsUnit(3), boreLabel,
      tubeFootnote, timeSection, timePresets, slowMotionPreset, realTimePreset, pasteFootnote, shakeSection,
      listenSection, listenFootnote, magnetSection, magnetFootnote, lookSection, solidLook, stressLight, dyeLines,
      particles, rheometerCursor, colourBy, lookFootnote, sensorsSection, useTilt, useMagnetometer, feelSectionTitle,
      hapticsToggle, feelToggle, soundToggle, feelFootnote, experimentsSection, explainSection, backToDefaults,
      backToDefaultsNote, curveSwitchLabel, flowCurveTitle, viscosityCurveTitle, literature, probeViscosity,
      stressLabel, shearLabel, rheometerCaption, honestySentence, panelLooking, panelPlay, panelHologram, panelControls,
      panelExperiments, panelHonesty, panelSensors, panelFeel, panelSources, introLine, introCaption, perPasteHeader,
      realTitle, tunedTitle, sensorsIntro, micHint, micDeniedTitle, micDeniedText, feelExplanation, soundExplanation,
      papersHeader, codeHeader, licenceDisclosure, method(particles: 3300, cell: 0.002), privacy, micDenied.text,
      micFailed.text, slowMotion.text, simulatedMotion.text, qualityChanged.text, micOnBanner(drives: "Shake").text,
      magnetBanner(microTesla: 312, isMR: true).text, magnetBanner(microTesla: 312, isMR: false).text,
      introDetail(tank: MPMDomain.lifeSizeTank, lifeSize: false, scale: 0.66, materials: catalog.materials.count),
      introDetail(tank: MPMDomain.lifeSizeTank, lifeSize: true, scale: 1, materials: catalog.materials.count),
      introDetail(tank: MPMDomain.lifeSizeTank, lifeSize: false, scale: nil, materials: catalog.materials.count),
    ]
    all += actionNames + rowTitles
    all += PasteSignal.allCases.map(pillLabel)
    all += PasteSignal.allCases.map { pillSpoken($0, channels: c) }
    all += PasteStateWord.allCases.flatMap { [stateWord($0), stateMeaning($0)] }
    all += PasteEvent.Kind.allCases.map(eventTile)
    all += playNotes.flatMap { [$0.title, $0.text] }
    all += hologramLegend.flatMap { [$0.title, $0.text] }
    all += controlNotes(gravity: store.spec(.gravity), heat: store.spec(.heat)).flatMap { [$0.title, $0.text] }
    all += honesty(tank: MPMDomain.lifeSizeTank, gap: 0.01, cell: 0.002, lifeSize: false, scale: 0.66, honeyRatio: 226)
    all += honesty(tank: MPMDomain.lifeSizeTank, gap: 0.01, cell: 0.002, lifeSize: true, scale: 1, honeyRatio: 65)
    all += honesty(tank: MPMDomain.lifeSizeTank, gap: 0.01, cell: 0.002, lifeSize: false, scale: nil, honeyRatio: 65)
    all += FluidDiagnostic.allCases.map(colourByTitle)
    for m in catalog.materials {
      all += [
        chamberLabel(m), subtitle(m), subtitleSpoken(m), materialBanner(m).text, tileHint(m), pasteSection(m),
        pasteValues(m), hologramIdentity(m),
        chamberValue(ToothpasteTelemetry(), channels: c, material: m, paused: false),
      ]
      all.append(plotSummary(m, catalog: catalog, temperature: m.fillTemperature))
    }
    all += catalog.props.map { propBanner($0).text }
    all += catalog.experiments.map { experimentBanner($0).text }
    all += catalog.experiments.flatMap { [$0.title, $0.subtitle] }
    all += catalog.specs.map { dimmedNote($0.title) }
    all += LiteraturePoints.all.flatMap { [$0.label, $0.note] }
    all += ToothpasteLicences.all.flatMap { [$0.name, $0.summary] }
    let effects = Experiment.commonEffects(catalog.experiments)
    all += [effects.menuHeader, effects.sentence].filter { !$0.isEmpty }
    return all
  }
}
