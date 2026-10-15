// TankLabels.swift — OWNER: HOLO (was RENDER; Documentation/REDESIGN-OWNERSHIP.md).
//
// Text helpers for the tank. The holo chamber (13 October 2026) carries calibration ticks on its housing instead of the
// back wall's ruler numerals, so nothing is drawn into a texture any more; `value(_:logarithmic:)` formats the
// diagnostics legend's end values (UI's stage card).

import Foundation
import LabKitCore

enum TankLabels {
  /// "10⁻²" for log axes, plain numbers otherwise.
  static func value(_ v: Double, logarithmic: Bool) -> String {
    // Whole-number ends print as integers ("0 … 1", "273 … 1473 K"), not "0 … 1.00".
    guard logarithmic, v > 0 else { return v == v.rounded() && abs(v) < 1e6 ? String(Int(v)) : LabFormat.sig3(v) }
    let e = Int((log10(v)).rounded())
    let sup: [Character: Character] = [
      "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻",
    ]
    return "10" + String(String(e).map { sup[$0] ?? $0 })
  }
}
