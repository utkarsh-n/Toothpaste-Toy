// Experiments.swift — OWNER: PLAY (was PHYS; Documentation/REDESIGN-OWNERSHIP.md).
//
// The 14 experiments of ARCHITECTURE.md §6. Each refills the tank and restarts the clock. `values` are knob values
// (LabKitCore `Experiment`); everything else an experiment does (what fills the tank, props, and a short scripted
// demonstration: a punch, a slow finger, a tilt, a shake, a pour, a knob turn, a moving magnet) is its
// `ExperimentRecipe`, which only PHYS reads. Script times are simulated seconds after the experiment starts; a real
// touch takes over from a scripted finger. Positions are fractions of the tank (x of its width, y of its height).

import Foundation
import LabKitCore

/// What fills the tank: a rectangle, a polygon or a disc, in fractions of the tank's width and height.
enum FillShape: Sendable {
  case rect(MaterialID, x0: Double, y0: Double, x1: Double, y1: Double)
  case polygon(MaterialID, [SIMD2<Double>])
  case disc(MaterialID, centre: SIMD2<Double>, radius: Double /* fraction of the width */)

  var material: MaterialID {
    switch self {
    case .rect(let m, _, _, _, _), .polygon(let m, _), .disc(let m, _, _): m
    }
  }
}

/// One scripted step of an experiment's demonstration.
enum ScriptAction: Sendable {
  /// A jab straight down at x (fraction of the width) from just above the fill to the height `bottom` (fraction of
  /// the tank height), at `speed` m/s, held briefly, then lifted.
  case jab(x: Double, bottom: Double, speed: Double)
  /// A slow finger: from above the fill at x down at `speed` m/s to `bottom`, held for `hold` s, then lifted.
  case press(x: Double, bottom: Double, speed: Double, hold: Double)
  /// A knob turn (shown on the knob).
  case knob(ParamID, Double)
  /// A tilt of the simulated phone (radians of roll, + tips the right side down). Only when motion is simulated.
  case tilt(Double)
  /// A synthetic shake of the tank: horizontal, `g` peak at `hz`, for `seconds`.
  case shake(g: Double, hz: Double, seconds: Double)
  /// Pour `material` from above x for `seconds`.
  case pour(MaterialID, x: Double, seconds: Double)
  /// Drop a prop above x: from the top of the tank, or (`gently`) set down just above the fill.
  case drop(PropKind, x: Double, gently: Bool)
  /// Slide the magnet under the floor to x over `seconds`.
  case magnet(x: Double, seconds: Double)
}

struct ScriptStep: Sendable {
  var at: Double
  var action: ScriptAction
  init(_ at: Double, _ action: ScriptAction) {
    self.at = at
    self.action = action
  }
}

/// What an experiment does beyond knob values.
struct ExperimentRecipe: Sendable {
  /// Layers bottom-up: material and fraction of the tank height. Empty (and no shapes) = the experiment's material at
  /// its usual fill.
  var layers: [(material: MaterialID, fraction: Double)] = []
  /// Shapes filled after the layers.
  var shapes: [FillShape] = []
  var props: [PropKind] = []
  var script: [ScriptStep] = []
  /// Magnet start position (fraction of the width).
  var magnetX: Double = 0.5
}

enum ToothpasteExperiments {
  static let effects: ExperimentEffects = [.refillsTank, .restartsClock]

  static let all: [Experiment] = [
    Experiment(
      "punch", title: "Punch the oobleck", subtitle: "Hit it hard and it holds", icon: "hand.raised.fill",
      note: "Punch fast: the grains jam into a solid that stops your finger. Stop, and it flows again.",
      values: [.gravity: 1, .time: 1, .shake: 0, .stir: 0, .packing: 0.52], material: "oobleck", effects: effects,
      sources: [ToothpasteSources.han2018, ToothpasteSources.waitukaitis2012, ToothpasteSources.han2016]),
    Experiment(
      "slowfast", title: "Slow and fast finger", subtitle: "Drag slowly, then flick", icon: "hand.draw.fill",
      note: "A slow finger sinks through oobleck. A fast one meets a solid.",
      values: [.gravity: 1, .time: 1, .shake: 0, .stir: 0, .finger: 8, .packing: 0.52], material: "oobleck",
      effects: effects, sources: [ToothpasteSources.han2018]),
    Experiment(
      "monsters", title: "Oobleck monsters", subtitle: "Shake 17 g at 120 Hz", icon: "speaker.wave.3.fill",
      note: "A thin layer on a floor shaking at 17 g. Real layers grow holes and fingers; this 2D one jams on every bounce and quivers like a solid.",
      values: [.shake: 17, .rate: 120, .listen: 0.5, .packing: 0.52], material: "oobleck", effects: effects,
      sources: [ToothpasteSources.merkt2004]),
    Experiment(
      "ketchup", title: "Ketchup won't pour", subtitle: "Tilt, then shake", icon: "waterbottle.fill",
      note: "Tilt the phone: the ketchup holds. Shake it, and it thins and slides.",
      values: [.gravity: 1, .shake: 0, .stir: 0], material: "ketchup", effects: effects,
      sources: [ToothpasteSources.mewisWagner2009]),
    Experiment(
      "toothpaste", title: "Toothpaste holds shape", subtitle: "250 Pa yield stress", icon: "paintbrush.pointed.fill",
      note: "Below its yield stress the paste is a soft solid. Push harder and it flows.",
      values: [.gravity: 1, .stir: 0], material: "toothpaste", effects: effects),
    Experiment(
      "moon", title: "Mayonnaise on the Moon", subtitle: "One-sixth gravity, 80 Pa yield", icon: "moon.fill",
      note: "In weak gravity the yield stress wins: the pile stands tall. Back on Earth, it slumps.",
      values: [.gravity: 0.166, .stir: 0], material: "mayonnaise", effects: effects),
    Experiment(
      "honey", title: "Honey, cold and warm", subtitle: "4 °C, then 37 °C", icon: "thermometer.snowflake",
      note: "Cold honey pours in a thick rope and piles up. Warm it and the pile runs flat.",
      values: [.heat: 4, .stir: 0], material: "honey", effects: effects, sources: [ToothpasteSources.saxena2014]),
    Experiment(
      "putty", title: "Putty bounce and slump", subtitle: "Fast: it bounces. Slow: it flows", icon: "circle.fill",
      note: "Silly Putty is elastic for a tenth of a second and a liquid over seconds.",
      values: [.gravity: 1, .time: 1, .stir: 0], material: "sillyPutty", effects: effects,
      sources: [ToothpasteSources.cross2012]),
    Experiment(
      "slime", title: "Slime puddle", subtitle: "0.4 s of memory", icon: "bubbles.and.sparkles.fill",
      note: "Slime springs back from a quick drop, then spreads into a puddle.",
      values: [.gravity: 1, .stir: 0], material: "slime", effects: effects, sources: [ToothpasteSources.ramlawi2024]),
    Experiment(
      "quicksand", title: "Quicksand: shake, sink", subtitle: "A glass marble, then 3 g", icon: "hurricane",
      note: "A marble rests on firm quicksand. Shake the floor and the sand liquefies: the marble sinks.",
      values: [.shake: 0, .gravity: 1, .rate: 50, .stir: 0], material: "quicksand", effects: effects,
      sources: [ToothpasteSources.khaldoun2005]),
    Experiment(
      "magnet", title: "Magnet and MR fluid", subtitle: "207 mT, a magnet 1 cm away", icon: "location.north.line.fill",
      note: "Near the magnet the iron chains up: the thin layer heaps over it and stiffens. Drag the magnet along the floor and the heap follows. Real MR fluid also grows spikes; this one does not.",
      values: [.magnet: 207, .stir: 0], material: "mrFluid", effects: effects),
    Experiment(
      "paint", title: "Paint levels", subtitle: "Brush marks flow out", icon: "paintpalette.fill",
      note: "Fresh brush marks on the surface flow out flat within seconds.",
      values: [.gravity: 1, .stir: 0], material: "paint", effects: effects),
    Experiment(
      "lava", title: "Lava crust", subtitle: "1170 °C basalt", icon: "flame.fill",
      note: "The surface cools first and darkens into a crust over the flowing core.",
      values: [.gravity: 1, .heat: 1170, .stir: 0], material: "lava", effects: effects, sources: [ToothpasteSources.shaw1968]),
    Experiment(
      "twofluids", title: "Two fluids", subtitle: "Honey over oobleck", icon: "drop.halffull",
      note: "Two materials share the tank. Honey is denser than oobleck, so it slowly sinks into it.",
      values: [.gravity: 1, .stir: 0], material: "honey", effects: effects),
  ]

  static let recipes: [String: ExperimentRecipe] = [
    "punch": ExperimentRecipe(
      layers: [("oobleck", 0.45)],
      script: [ScriptStep(1.0, .jab(x: 0.5, bottom: 0.2, speed: 1.2)), ScriptStep(3.5, .jab(x: 0.3, bottom: 0.2, speed: 1.2))]),
    "slowfast": ExperimentRecipe(
      layers: [("oobleck", 0.45)],
      script: [
        ScriptStep(0.8, .press(x: 0.3, bottom: 0.15, speed: 0.02, hold: 0.4)),
        ScriptStep(3.8, .jab(x: 0.7, bottom: 0.15, speed: 1.0)),
      ]),
    "monsters": ExperimentRecipe(
      layers: [("oobleck", 0.12)], script: [ScriptStep(0.8, .jab(x: 0.5, bottom: 0.04, speed: 0.4))]),
    "ketchup": ExperimentRecipe(
      layers: [("ketchup", 0.05)],
      shapes: [.polygon("ketchup", mound(peak: 0.13, base: 0.05, from: 0.2, to: 0.8))],
      script: [
        ScriptStep(0.6, .tilt(0.3)), ScriptStep(3.0, .shake(g: 1.5, hz: 10, seconds: 1.2)),
        ScriptStep(5.0, .shake(g: 1.5, hz: 10, seconds: 1.2)),
      ]),
    "toothpaste": ExperimentRecipe(
      // A 20 × 30 mm column: a 14 mm one yields at its base under its own weight (about 400 Pa there against LabKit's
      // 150 Pa yield stress) and topples within 3–8 s (measured); 20 mm stands. The app's toothpaste is 250 Pa
      // (ToothpasteTuning), which only adds margin.
      shapes: [
        .rect("toothpaste", x0: 0.10, y0: 0, x1: 0.38, y1: 0.30),
        .polygon("toothpaste", ribbon(x0: 0.45, x1: 0.92, y: 0.0, height: 0.09)),
      ],
      script: [ScriptStep(2.5, .press(x: 0.7, bottom: 0.08, speed: 0.03, hold: 0.6))]),
    "moon": ExperimentRecipe(
      shapes: [.polygon("mayonnaise", mound(peak: 0.5, base: 0.0, from: 0.25, to: 0.75))],
      script: [ScriptStep(4.0, .knob(.gravity, 1))]),
    "honey": ExperimentRecipe(
      layers: [("honey", 0.12)],
      script: [ScriptStep(0.3, .pour("honey", x: 0.5, seconds: 3.2)), ScriptStep(4.5, .knob(.heat, 37))]),
    "putty": ExperimentRecipe(
      layers: [("sillyPutty", 0.04)], shapes: [.disc("sillyPutty", centre: SIMD2(0.5, 0.5), radius: 0.17)]),
    "slime": ExperimentRecipe(
      shapes: [.disc("slime", centre: SIMD2(0.5, 0.5), radius: 0.2)]),
    "quicksand": ExperimentRecipe(
      layers: [("quicksand", 0.4)],
      script: [
        // A glass marble (2.5 g/cm³, a little denser than the 2 g/cm³ quicksand), as Khaldoun et al. 2005 used an
        // aluminium bead: a steel ball (7.85 g/cm³) presses so hard that it slowly sinks into the rested bed too.
        // Set down once the fresh fill has settled (its loading wave would otherwise unbuild the bed under it).
        // 2.5 s of shaking liquefies the bed (λ 0.9 → 0.07) and the marble sinks through it to the floor within about
        // 1.5 s of the shake starting (it rides the shaken bed: Props.swift); the bed then rebuilds (t_build 10 s).
        ScriptStep(0.8, .drop(.glassMarble, x: 0.5, gently: true)), ScriptStep(3.2, .knob(.shake, 3)),
        ScriptStep(5.7, .knob(.shake, 0)),
      ]),
    "magnet": ExperimentRecipe(
      // A thin layer (10 mm): it heaps over the magnet (about 4 mm in 2 s, LabKit M5) and the heap follows the slide.
      // A deep pool's surface sits outside the field's capped zone and stays flat (measured: 30 mm layer −1.3 mm).
      layers: [("mrFluid", 0.1)],
      script: [ScriptStep(2.0, .magnet(x: 0.25, seconds: 1.5)), ScriptStep(4.5, .magnet(x: 0.75, seconds: 2.0))],
      magnetX: 0.5),
    "paint": ExperimentRecipe(
      shapes: [.polygon("paint", brushed(level: 0.4, amplitude: 0.05, waves: 5))]),
    "lava": ExperimentRecipe(shapes: [.rect("lava", x0: 0, y0: 0, x1: 0.35, y1: 0.45)]),
    "twofluids": ExperimentRecipe(
      layers: [("oobleck", 0.25), ("honey", 0.2)],
      script: [ScriptStep(4.0, .press(x: 0.3, bottom: 0.15, speed: 0.03, hold: 0.5)), ScriptStep(7.0, .jab(x: 0.7, bottom: 0.15, speed: 1.0))]),
  ]

  // MARK: Shapes (fractions of the tank)

  /// A parabolic mound from x `from` to `to`, `peak` tall at the centre, standing on a base of height `base`.
  static func mound(peak: Double, base: Double, from: Double, to: Double, steps: Int = 24) -> [SIMD2<Double>] {
    var pts: [SIMD2<Double>] = [SIMD2(from, 0)]
    for i in 0...steps {
      let u = Double(i) / Double(steps)
      let x = from + (to - from) * u
      let s = 2 * u - 1
      pts.append(SIMD2(x, base + (peak - base) * max(0, 1 - s * s)))
    }
    pts.append(SIMD2(to, 0))
    return pts
  }

  /// A squeezed ribbon of toothpaste lying on the floor: a rounded strip with ridges.
  static func ribbon(x0: Double, x1: Double, y: Double, height: Double, steps: Int = 32) -> [SIMD2<Double>] {
    var pts: [SIMD2<Double>] = [SIMD2(x0, y)]
    for i in 0...steps {
      let u = Double(i) / Double(steps)
      let edge = min(1, min(u, 1 - u) * 8)
      let ridge = 0.8 + 0.2 * cos(u * 6 * 2 * .pi)
      pts.append(SIMD2(x0 + (x1 - x0) * u, y + height * edge * ridge))
    }
    pts.append(SIMD2(x1, y))
    return pts
  }

  /// A pool filled to `level` with brush marks: `waves` ridges of ±`amplitude` across the width.
  static func brushed(level: Double, amplitude: Double, waves: Int, steps: Int = 64) -> [SIMD2<Double>] {
    var pts: [SIMD2<Double>] = [SIMD2(0, 0)]
    for i in 0...steps {
      let u = Double(i) / Double(steps)
      pts.append(SIMD2(u, level + amplitude * sin(u * Double(waves) * 2 * .pi)))
    }
    pts.append(SIMD2(1, 0))
    return pts
  }
}
