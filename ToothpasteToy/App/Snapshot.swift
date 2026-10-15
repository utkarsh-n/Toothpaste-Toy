// Snapshot.swift — OWNER: UI (Documentation/REDESIGN-OWNERSHIP.md).
//
// In-process screenshots, for a host too loaded for `simctl io screenshot` (SpringBoard can take minutes to bring the
// app forward, and the simulator's display freezes while the app keeps running; SKELETON.md §8).
//
//   -snapshot          captures the key window to tmp/tt-ui-snap-<n>.png at 8, 14 and 22 s
//   -uiTour            steps through the screen's states, sheets and pastes in one launch, re-creating the screen with
//                      each step's UI arguments, and captures tmp/tt-ui-<step>.png; writes tmp/ui-tour-done.txt at the end
//   -tourOnly <prefix> only the steps whose names start with the prefix
//   -ax                Accessibility XXXL inside the app (the system argument also works for sheets)
//
// `drawHierarchy(in:afterScreenUpdates:)` includes the Metal stage (unlike `layer.render(in:)`). Copy the files out
// with `xcrun simctl get_app_container <udid> com.utkarsh.toothpastetoy data`.

import LabKitCore
import LabKitSensors
import SwiftUI
import UIKit

@MainActor enum ToothpasteSnapshot {
  /// Captures every visible window to `directory`/`prefix``name`.png (default: tmp/tt-ui-<name>.png).
  static func capture(name: String, directory: URL? = nil, prefix: String = "tt-ui-") {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap(\.windows).filter { !$0.isHidden }
    guard let key = windows.first(where: \.isKeyWindow) ?? windows.first else { return }
    let format = UIGraphicsImageRendererFormat()
    format.scale = key.screen.scale
    let image = UIGraphicsImageRenderer(bounds: key.bounds, format: format).image { _ in
      // Every visible window in order (sheets and menus may live in their own).
      for w in windows.sorted(by: { $0.windowLevel.rawValue < $1.windowLevel.rawValue }) {
        _ = w.drawHierarchy(in: w.frame, afterScreenUpdates: true)
      }
    }
    let url = (directory ?? FileManager.default.temporaryDirectory).appending(path: "\(prefix)\(name).png")
    try? image.pngData()?.write(to: url)
  }

  static func schedule() {
    Task { @MainActor in
      for (n, delay) in [(1, 8.0), (2, 6.0), (3, 8.0)] {
        try? await Task.sleep(for: .seconds(delay))
        capture(name: "snap-\(n)")
      }
    }
  }
}

/// One step of the tour: a name, the UI arguments the screen is re-created with, and what to do to the model first.
struct ToothpasteTourStep {
  let name: String
  let args: [String]
  /// Real seconds before the capture; with `simulated`, the most real seconds to wait for it.
  var dwell = 4.5
  /// QA steps (App/QATour.swift): capture once the simulated clock has run this many seconds since the step began, or
  /// since its experiment started (`fromExperiment`: an experiment restarts the clock at 0).
  var simulated: Double? = nil
  var fromExperiment = false
  var setup: @MainActor (ToothpasteModel) -> Void = { _ in }
  /// Runs alongside the wait (scripted touches).
  var act: (@MainActor (ToothpasteModel) async -> Void)? = nil
}

@MainActor enum ToothpasteTour {
  /// Back to a fresh toothpaste chamber with default knobs, running, unzoomed.
  static func fresh(_ m: ToothpasteModel, _ material: MaterialID = defaultMaterialID) {
    m.paused = false
    m.zoom = 1
    m.layers.diagnostic = .none
    m.layers.solid = false
    m.params.resetAll()
    m.shelfMode = .fill
    if m.materialID != material { m.choose(material: material) } else { m.refill() }
  }

  static let steps: [ToothpasteTourStep] = [
    ToothpasteTourStep(name: "main", args: [], dwell: 9) { fresh($0) },
    ToothpasteTourStep(name: "squeeze", args: ["-squeezeDemo"], dwell: 4.5),
    ToothpasteTourStep(name: "lens", args: ["-lensDemo"], dwell: 4),
    ToothpasteTourStep(name: "banner-material", args: ["-banner", "material"], dwell: 3),
    ToothpasteTourStep(name: "pastes", args: ["-pastes"], dwell: 4),
    ToothpasteTourStep(name: "more", args: ["-more"], dwell: 4),
    ToothpasteTourStep(name: "rheometer", args: ["-rheometer"], dwell: 5),
    ToothpasteTourStep(name: "rheometer-large", args: ["-rheometer", "-large"], dwell: 5),
    ToothpasteTourStep(name: "info-01", args: ["-info", "-large"], dwell: 5),
    ToothpasteTourStep(name: "info-02", args: ["-info", "-large", "-infoPanel", "02"], dwell: 5),
    ToothpasteTourStep(name: "info-03", args: ["-info", "-large", "-infoPanel", "03"], dwell: 5),
    ToothpasteTourStep(name: "info-04", args: ["-info", "-large", "-infoPanel", "04"], dwell: 5),
    ToothpasteTourStep(name: "info-06", args: ["-info", "-large", "-infoPanel", "06"], dwell: 5),
    ToothpasteTourStep(name: "info-09", args: ["-info", "-large", "-infoPanel", "09-code"], dwell: 5),
    ToothpasteTourStep(name: "moon", args: ["-squeezeDemo"], dwell: 6) { m in
      fresh(m)
      m.params[.gravity] = 0.166
    },
    ToothpasteTourStep(name: "heat", args: ["-lensDemo"], dwell: 5) { m in
      fresh(m)
      m.params[.heat] = 60
    },
    ToothpasteTourStep(name: "oobleck", args: ["-lensDemo"], dwell: 6) { fresh($0, "oobleck") },
    ToothpasteTourStep(name: "honey", args: ["-squeezeDemo"], dwell: 6) { fresh($0, "honey") },
    ToothpasteTourStep(name: "lava", args: [], dwell: 5) { fresh($0, "lava") },
    ToothpasteTourStep(name: "solid", args: ["-lensDemo"], dwell: 5) { m in
      fresh(m)
      m.layers.solid = true
    },
    ToothpasteTourStep(name: "frozen", args: [], dwell: 4) { m in
      m.layers.solid = false
      m.paused = true
    },
    // Accessibility XXXL: the crowns stack, the telemetry stacks, the chamber keeps its minimum and the page scrolls.
    ToothpasteTourStep(name: "ax", args: ["-ax"], dwell: 5) { m in m.paused = false },
    ToothpasteTourStep(name: "ax-more", args: ["-ax", "-more"], dwell: 5),
  ]
}

/// Hosts the screen for `-uiTour`: re-creates it per step (`.id`) with the step's arguments, then captures it.
struct ToothpasteTourHost: View {
  let model: ToothpasteModel
  @State private var step = 0
  @State private var ax = false

  var body: some View {
    ToothpasteScreen(model: model)
      .modifier(ToothpasteAXOverride(on: ax))
      .id(step)
      .task {
        let only = LaunchOptions.value(after: "-tourOnly")
        let base = LaunchOptions.arguments.filter { $0 != "-uiTour" } + ["-quietSensors"]
        try? await Task.sleep(for: .seconds(4))
        // The QA steps run only when asked for (`-tourOnly qa-…`).
        let steps = only?.hasPrefix("qa") == true ? ToothpasteQATour.steps : ToothpasteTour.steps
        for (i, s) in steps.enumerated() where only.map({ s.name.hasPrefix($0) }) ?? true {
          let before = model.latestFrame.simTime
          s.setup(model)
          ToothpasteUIArgs.override = base + s.args
          ax = s.args.contains("-ax")
          step = i + 1
          let act = s.act.map { a in Task { @MainActor in await a(model) } }
          if let target = s.simulated {
            // An experiment restarts the clock on its next frame: let that frame happen first.
            if s.fromExperiment { try? await Task.sleep(for: .milliseconds(300)) }
            let limit = ContinuousClock.now + .seconds(s.dwell)
            while ContinuousClock.now < limit {
              let t = model.latestFrame.simTime
              if (s.fromExperiment ? t : t - before) >= target { break }
              try? await Task.sleep(for: .milliseconds(10))
            }
          } else {
            try? await Task.sleep(for: .seconds(s.dwell))
          }
          ToothpasteSnapshot.capture(name: s.name)
          await act?.value
        }
        let done = FileManager.default.temporaryDirectory.appending(path: "ui-tour-done.txt")
        try? "done\n".write(to: done, atomically: true, encoding: .utf8)
      }
  }
}

/// `-ax`: Accessibility XXXL inside the app (stage chrome still caps itself at `.accessibility1`).
struct ToothpasteAXOverride: ViewModifier {
  let on: Bool
  func body(content: Content) -> some View {
    if on { content.environment(\.dynamicTypeSize, .accessibility5) } else { content }
  }
}
