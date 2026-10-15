// Persistence.swift — OWNER: PLAY (was PHYS; Documentation/REDESIGN-OWNERSHIP.md).
//
// Saves the material, shelf mode and Layers settings in UserDefaults ("ToothpasteToy.settings", a versioned JSON blob).
// Haptics, Strength, Feel and Sound are persisted by LabFeedback itself ("ToothpasteToy.haptics", "ToothpasteToy.hapticStrength",
// "ToothpasteToy.feel", "ToothpasteToy.sound").
//
// Knob values deliberately do not persist: every launch (like every Fill) starts the material at its own defaults, so
// a knob left at an extreme (Gravity −1, Time ×0.05, Shake 27 g) never greets you as a broken tank. The material
// itself does persist, so you come back to the same fluid.

import Foundation
import LabKitMPM

@MainActor final class ToothpastePersistence: ToothpasteSettingsStoring {
  private let enabled: Bool
  private let defaults: UserDefaults
  static let key = "ToothpasteToy.settings"
  static let version = 2

  init(enabled: Bool, defaults: UserDefaults = .standard) {
    self.enabled = enabled
    self.defaults = defaults
  }

  private struct Blob: Codable {
    var version: Int?
    var material: String
    var shelfMode: String
    var stressLight, dyeLines, particles, rheometerCursor, useTilt, useMagnetometer: Bool
    var diagnostic: Int
  }

  func load() -> ToothpasteSettings? {
    guard enabled, let data = defaults.data(forKey: Self.key),
      let b = try? JSONDecoder().decode(Blob.self, from: data), (b.version ?? 1) <= Self.version
    else { return nil }
    var layers = ToothpasteLayers()
    layers.stressLight = b.stressLight
    layers.dyeLines = b.dyeLines
    layers.particles = b.particles
    layers.rheometerCursor = b.rheometerCursor
    layers.useTilt = b.useTilt
    layers.useMagnetometer = b.useMagnetometer
    layers.diagnostic = FluidDiagnostic(rawValue: b.diagnostic) ?? .none
    return ToothpasteSettings(material: b.material, shelfMode: ShelfMode(rawValue: b.shelfMode) ?? .fill, layers: layers)
  }

  func save(_ s: ToothpasteSettings) {
    guard enabled else { return }
    let l = s.layers
    let b = Blob(
      version: Self.version, material: s.material, shelfMode: s.shelfMode.rawValue, stressLight: l.stressLight,
      dyeLines: l.dyeLines, particles: l.particles, rheometerCursor: l.rheometerCursor, useTilt: l.useTilt,
      useMagnetometer: l.useMagnetometer, diagnostic: l.diagnostic.rawValue)
    if let data = try? JSONEncoder().encode(b) { defaults.set(data, forKey: Self.key) }
  }
}
