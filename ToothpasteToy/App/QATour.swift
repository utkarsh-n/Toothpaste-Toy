// QATour.swift — OWNER: UI (was integrator QA, 9 October 2026; Documentation/REDESIGN-OWNERSHIP.md).
//
// `-uiTour -tourOnly qa-`: the QA pass's in-app pictures (Documentation/screenshots/qa-*.png). Unlike the UI tour's
// fixed real-time dwells, each step can wait for the *simulated* clock (a loaded simulator runs the world slower than
// real time) and can script touches (a pour is a drag in Pour mode). Every material, every experiment at two moments,
// the shelf modes, the Rheometer, the info sheet, a poke, a punch, a stir, honey poured onto oobleck, a dropped steel
// ball, Moon gravity, Heat low and high, the magnet with MR fluid, Time × 0.25 and Accessibility XXXL.
//
// Run: launch with `-uiTour -tourOnly qa- -noPersist -simSway` (add `-tourOnly qa-exp-` for a subset); pictures land in
// the app's tmp as ui-qa-*.png and tmp/ui-tour-done.txt marks the end.

import Foundation
import LabKitCore
import LabKitMPM

@MainActor enum ToothpasteQATour {
  static let materials: [MaterialID] = [
    "waterLike", "honey", "ketchup", "mayonnaise", "toothpaste", "oobleck", "slime", "sillyPutty", "yogurt",
    "quicksand", "mrFluid", "paint", "lava",
  ]

  /// Two moments (simulated seconds after the experiment starts) per experiment, and the console page to show.
  static let experiments: [(id: String, early: Double, late: Double, page: String)] = [
    ("punch", 1.15, 2.6, "fluid"),
    ("slowfast", 2.5, 3.95, "touch"),
    ("monsters", 1.5, 4.0, "touch"),
    ("ketchup", 2.5, 6.8, "world"),
    ("toothpaste", 1.0, 5.0, "fluid"),
    ("moon", 3.5, 7.5, "world"),
    ("honey", 2.0, 8.0, "world"),
    ("putty", 0.8, 6.0, "fluid"),
    ("slime", 0.6, 5.0, "fluid"),
    ("quicksand", 2.5, 7.0, "touch"),
    ("magnet", 1.5, 5.0, "world"),
    ("paint", 0.3, 4.0, "fluid"),
    ("lava", 1.0, 8.0, "world"),
    ("twofluids", 3.0, 9.0, "fluid"),
  ]

  /// Puts the world back to its defaults (knobs, no props, no zoom or colour map) and, given a material, a plain tank
  /// of it (Fill). Experiments refill the tank themselves.
  static func plain(_ m: ToothpasteModel, _ material: MaterialID?) {
    m.paused = false
    m.zoom = 1
    m.layers.diagnostic = .none
    m.perform(.clearProps)
    m.params.resetAll()
    m.shelfMode = .fill
    if let material { m.choose(material: material) }
  }

  /// A one-finger drag in tank fractions over `seconds` of real time (the hub's touch path, as a real finger).
  static func drag(_ m: ToothpasteModel, from a: SIMD2<Double>, to b: SIMD2<Double>, seconds: Double) async {
    try? await Task.sleep(for: .milliseconds(250))  // the engine reads the shelf mode on its next frame
    let tank = m.engine.tankSize
    let p0 = a * tank, p1 = b * tank
    let id = 7001
    func now() -> Double { ProcessInfo.processInfo.systemUptime }
    m.engine.touches([TankTouch(id: id, position: p0, start: p0, phase: .began, timestamp: now())])
    let n = max(Int(seconds / 0.033), 1)
    for i in 1...n {
      try? await Task.sleep(for: .milliseconds(33))
      let p = p0 + (p1 - p0) * (Double(i) / Double(n))
      m.engine.touches([TankTouch(id: id, position: p, start: p0, phase: .moved, timestamp: now())])
    }
    m.engine.touches([TankTouch(id: id, position: p1, start: p0, phase: .ended, timestamp: now())])
  }

  static var steps: [ToothpasteTourStep] {
    var s: [ToothpasteTourStep] = []

    // Every material at rest (the simulated phone sways with -simSway), Fluid page.
    for id in materials {
      s.append(ToothpasteTourStep(name: "qa-mat-\(id)", args: ["-touched"], dwell: 25, simulated: 2.5) { plain($0, id) })
    }

    // Every experiment, early and late.
    for e in experiments {
      s.append(
        ToothpasteTourStep(
          name: "qa-exp-\(e.id)-1", args: ["-touched", "-page", e.page], dwell: 3 * e.early + 20, simulated: e.early,
          fromExperiment: true
        ) { m in
          plain(m, nil)
          m.perform(.experiment(e.id))
        })
      s.append(
        ToothpasteTourStep(
          name: "qa-exp-\(e.id)-2", args: ["-touched", "-page", e.page], dwell: 3 * e.late + 20, simulated: e.late,
          fromExperiment: true))
    }

    // Shelf modes.
    for mode in ShelfMode.allCases {
      s.append(
        ToothpasteTourStep(name: "qa-shelf-\(mode.rawValue)", args: ["-shelf", "-touched"], dwell: 6) { m in
          plain(m, "oobleck")
          m.shelfMode = mode
        })
    }

    // Rheometer: the strip with honey stirred (a live cursor), then the large detent.
    s.append(
      ToothpasteTourStep(name: "qa-rheo-strip", args: ["-rheometer", "-touched"], dwell: 25, simulated: 2.0) { m in
        plain(m, "honey")
        m.params[.stir] = 1
      })
    s.append(
      ToothpasteTourStep(name: "qa-rheo-large", args: ["-rheometer", "-large", "-touched"], dwell: 25, simulated: 2.0) { m in
        plain(m, "ketchup")
        m.params[.stir] = 0.6
      })

    // Info sheet: medium, large, the honesty panel.
    s.append(ToothpasteTourStep(name: "qa-info-medium", args: ["-info"], dwell: 6) { plain($0, "oobleck") })
    s.append(ToothpasteTourStep(name: "qa-info-large", args: ["-info", "-large"], dwell: 6))
    s.append(ToothpasteTourStep(name: "qa-info-honesty", args: ["-info", "-large", "-infoPanel", "06"], dwell: 6))

    // A poke and a punch in oobleck at the centre, caught mid-stroke and after.
    s.append(
      ToothpasteTourStep(name: "qa-poke", args: ["-touched"], dwell: 20, simulated: 2.6) { m in
        plain(m, "oobleck")
      } act: { m in
        try? await Task.sleep(for: .seconds(1))
        let t = m.engine.tankSize
        m.perform(.poke(SIMD2(t.x * 0.5, t.y * 0.32)))
      })
    s.append(
      ToothpasteTourStep(name: "qa-punch-1", args: ["-touched"], dwell: 25, simulated: 0.1) { m in
        let t = m.engine.tankSize
        m.perform(.punch(SIMD2(t.x * 0.5, t.y * 0.22)))
      })
    s.append(ToothpasteTourStep(name: "qa-punch-2", args: ["-touched"], dwell: 25, simulated: 1.2))

    // Stirring: oobleck (jams around the paddle when fast) and honey.
    s.append(
      ToothpasteTourStep(name: "qa-stir-oobleck", args: ["-touched", "-page", "touch"], dwell: 30, simulated: 2.5) { m in
        plain(m, "oobleck")
        m.params[.stir] = 2
      })
    s.append(
      ToothpasteTourStep(name: "qa-stir-honey", args: ["-touched", "-page", "touch"], dwell: 30, simulated: 2.5) { m in
        plain(m, "honey")
        m.params[.stir] = 1
      })

    // Honey poured onto oobleck (Pour mode, a drag across the top), during and after.
    s.append(
      ToothpasteTourStep(name: "qa-pour-honey-1", args: ["-touched"], dwell: 30, simulated: 1.6) { m in
        plain(m, "oobleck")
        m.shelfMode = .pour
        m.perform(.pourMaterial("honey"))
      } act: { m in
        await drag(m, from: SIMD2(0.25, 0.85), to: SIMD2(0.75, 0.85), seconds: 2.0)
      })
    s.append(ToothpasteTourStep(name: "qa-pour-honey-2", args: ["-touched"], dwell: 30, simulated: 4.0))

    // A steel ball dropped into oobleck: held by the jam, then sinking.
    s.append(
      ToothpasteTourStep(name: "qa-ball-1", args: ["-touched"], dwell: 25, simulated: 0.4) { m in
        plain(m, "oobleck")
        m.drop(.steelBall)
      })
    s.append(ToothpasteTourStep(name: "qa-ball-2", args: ["-touched"], dwell: 30, simulated: 4.0))

    // Every prop dropped into honey.
    s.append(
      ToothpasteTourStep(name: "qa-props-honey", args: ["-touched"], dwell: 30, simulated: 4.0) { m in
        plain(m, "honey")
        for p in PropKind.allCases { m.drop(p) }
      })

    // Moon gravity: water sloshing at 1/6 g (World page shows the knob).
    s.append(
      ToothpasteTourStep(name: "qa-moon-water", args: ["-touched", "-page", "world"], dwell: 25, simulated: 3.0) { m in
        plain(m, "waterLike")
        m.params[.gravity] = 0.166
        m.perform(.tilt(dx: 0.35, dy: 0))
      })

    // Heat low and high: the cold-honey pour at 4 °C and the same pour at 80 °C.
    s.append(
      ToothpasteTourStep(
        name: "qa-heat-low", args: ["-touched", "-page", "world"], dwell: 30, simulated: 3.0, fromExperiment: true
      ) { m in
        plain(m, nil)
        m.perform(.experiment("honey"))
      })
    s.append(
      ToothpasteTourStep(
        name: "qa-heat-high", args: ["-touched", "-page", "world"], dwell: 30, simulated: 3.0, fromExperiment: true
      ) { m in
        plain(m, nil)
        m.perform(.experiment("honey"))
        m.params[.heat] = 80
      })
    // Lava erupting cool (1050 °C) and hot (1200 °C).
    s.append(
      ToothpasteTourStep(
        name: "qa-lava-1050", args: ["-touched", "-page", "world"], dwell: 30, simulated: 3.0, fromExperiment: true
      ) { m in
        plain(m, nil)
        m.perform(.experiment("lava"))
        m.params[.heat] = 1050
      })
    s.append(
      ToothpasteTourStep(
        name: "qa-lava-1200", args: ["-touched", "-page", "world"], dwell: 30, simulated: 3.0, fromExperiment: true
      ) { m in
        plain(m, nil)
        m.perform(.experiment("lava"))
        m.params[.heat] = 1200
      })

    // Time × 0.25: the punch in slow motion.
    s.append(
      ToothpasteTourStep(
        name: "qa-time-quarter", args: ["-touched", "-page", "world"], dwell: 40, simulated: 1.15, fromExperiment: true
      ) { m in
        plain(m, nil)
        m.perform(.experiment("punch"))
        m.params[.time] = 0.25
      })

    // Colour by shear rate while stirring oobleck (the legend card).
    s.append(
      ToothpasteTourStep(name: "qa-diag-shear", args: ["-touched", "-page", "view"], dwell: 25, simulated: 2.0) { m in
        plain(m, "oobleck")
        m.params[.stir] = 1.5
        m.layers.diagnostic = .shearRate
      })

    // Accessibility XXXL.
    s.append(ToothpasteTourStep(name: "qa-ax-fluid", args: ["-ax", "-touched"], dwell: 7) { plain($0, "honey") })
    s.append(ToothpasteTourStep(name: "qa-ax-shelf", args: ["-ax", "-shelf", "-touched"], dwell: 7))
    s.append(ToothpasteTourStep(name: "qa-ax-strip", args: ["-ax", "-rheometer", "-touched"], dwell: 8))
    s.append(ToothpasteTourStep(name: "qa-ax-info", args: ["-ax", "-info", "-large", "-infoPanel", "06"], dwell: 7))
    s.append(ToothpasteTourStep(name: "qa-ax-world", args: ["-ax", "-page", "world", "-touched"], dwell: 7))
    return s
  }
}
