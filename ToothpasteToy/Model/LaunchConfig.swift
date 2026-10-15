// LaunchConfig.swift — OWNER: PLAY (was PHYS; Documentation/REDESIGN-OWNERSHIP.md).
//
// Parses Toothpaste Toy's launch arguments into `ToothpasteLaunch` (Interfaces.swift). LabKit's sensor fakes (-simSway, -fakeMic,
// -startMic, -fakeMagnet, -fakeShake, -fakeThermal, -fakeLowPower) are read by LabKitSensors itself.
//
//   -material <id>             start with this material ("honey", "ketchup", …; LabPalette.rheoFluids ids:
//                              waterLike honey ketchup mayonnaise toothpaste oobleck slime sillyPutty yogurt quicksand
//                              mrFluid paint lava)
//   -experiment <id>           apply an experiment at launch (punch slowfast monsters ketchup toothpaste moon honey
//                              putty slime quicksand magnet paint lava twofluids); it plays its scripted demonstration
//   -fakeTouch [poke|stir|punch|slow]  a scripted finger looping every 4 s after 1.5 s (default poke: 0.6 s down,
//                              held 1 s; punch: 30 ms down; slow: 2 s down; stir: continuous circles)
//   -quality standard|high|bench  Δx 2.0 / 1.6 / 1.1 mm (high steps down to standard after 3 s of lag)
//   -ui-testing                defaults, no persistence
//   -noPersist                 neither load nor save settings
//   -thermalHeat               the phone's thermal state warms the tank (device.thermal → Heat, up to +30 °C)

import Foundation
import LabKitMPM

extension ToothpasteLaunch {
  static var current: ToothpasteLaunch { parse(ProcessInfo.processInfo.arguments) }

  /// `-thermalHeat`: the playful device.thermal → Heat route (off by default; ARCHITECTURE.md §6).
  static var thermalHeatRequested: Bool { ProcessInfo.processInfo.arguments.contains("-thermalHeat") }

  static func parse(_ args: [String]) -> ToothpasteLaunch {
    // A later flag overrides an earlier one (tests prepend defaults such as `-material oobleck`).
    func value(_ flag: String) -> String? {
      guard let i = args.lastIndex(of: flag), i + 1 < args.count, !args[i + 1].hasPrefix("-") else { return nil }
      return args[i + 1]
    }
    let quality: MPMQuality
    switch value("-quality") {
    case "high": quality = .high
    case "bench": quality = .bench
    default: quality = .standard
    }
    var touch: String?
    if args.contains("-fakeTouch") { touch = value("-fakeTouch") ?? "poke" }
    let uiTesting = args.contains("-ui-testing")
    return ToothpasteLaunch(
      material: value("-material"), experiment: value("-experiment"), fakeTouch: touch, quality: quality,
      capacity: 40_000, uiTesting: uiTesting, persist: !(uiTesting || args.contains("-noPersist")))
  }
}
