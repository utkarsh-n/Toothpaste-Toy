// ToothpasteToyApp.swift — OWNER: UI (Documentation/REDESIGN-OWNERSHIP.md).
//
// The app entry point. The model is created once, after the first frame, so the launch screen shows at once; and
// never under XCTest (unit tests build their own headless models). Until the model exists the window shows Metro's
// canvas (0.025, 0.042, 0.058), the same colour as the launch screen (`LaunchBackground`), so launch → placeholder →
// chamber never flashes.

import LabKitCore
import LabKitSensors
import LabKitUI
import SwiftUI

@main
struct ToothpasteToyApp: App {
  @State private var model: ToothpasteModel?
  /// `-perfLog` / `-autoTour` (App/PerfLog.swift).
  @State private var perf: ToothpastePerfSession?

  static var isRunningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

  var body: some Scene {
    WindowGroup {
      Group {
        if let model {
          if LaunchOptions.has("-uiTour") {
            ToothpasteTourHost(model: model)
          } else {
            ToothpasteScreen(model: model)
          }
        } else {
          Metro.Colour.canvas.color.ignoresSafeArea()
        }
      }
      .modifier(ToothpasteAXOverride(on: LaunchOptions.has("-ax")))
      .metroChrome()
      .task {
        if model == nil, !Self.isRunningTests {
          let m = ToothpasteModel()
          model = m
          if LaunchOptions.has("-snapshot") { ToothpasteSnapshot.schedule() }
          if LaunchOptions.has("-perfLog") || LaunchOptions.has("-autoTour") {
            let session = ToothpastePerfSession(model: m)
            session.start()
            perf = session
          }
        }
      }
    }
  }
}

extension View {
  /// The app root's chrome: dark, Metro's canvas behind everything, action cyan as the tint, no status bar or home
  /// indicator over the instrument, and LabKit's palette for the plots (LabPlot reads it).
  func metroChrome() -> some View {
    self
      .labPalette(.rheo)
      .background(Metro.Colour.canvas.color.ignoresSafeArea())
      .tint(Metro.Colour.actionCyan.color)
      .preferredColorScheme(.dark)
      .statusBarHidden()
      .persistentSystemOverlays(.hidden)
  }
}
