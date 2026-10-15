// LiteraturePoints.swift — OWNER: UI (Documentation/REDESIGN-OWNERSHIP.md).
//
// Published measurements drawn on the Rheometer's flow curve as hollow `measured` rings (§9.6, §3.12), each with its
// Citation. Values come from rheology-models.md §3.1–§3.3 (the papers' own fits). Bibliographic data of every
// citation was checked against Crossref on 8 October 2026. Temperature-dependent points (honey, water) follow the
// paper's own law at the tank's temperature; the others are shown at the temperature they were measured at.

import Foundation
import LabKitCore

struct LiteraturePoint: Sendable, Identifiable {
  let id: String
  let material: MaterialID
  /// "Honey · Saxena et al. 2014".
  let label: String
  /// What the rings are, in one sentence.
  let note: String
  let citation: Citation
  /// (γ̇ s⁻¹, σ Pa) at a temperature in K.
  let points: @Sendable (_ temperature: Double) -> [SIMD2<Double>]
}

enum LiteraturePoints {
  static let gasConstant = 8.314_462_618

  static let cheng2008 = Citation(
    "Formula for the viscosity of a glycerol–water mixture", publisher: "Cheng, Ind. Eng. Chem. Res. 47, 3285 (2008)",
    url: URL(string: "https://doi.org/10.1021/ie071349z")!, kind: .paper, checked: "2026-10-08")
  static let saxena2014 = Citation(
    "Rheology of Indian honey: effect of temperature and gamma radiation",
    publisher: "Saxena, Panicker & Gautam, Int. J. Food Sci. 2014, 935129",
    url: URL(string: "https://doi.org/10.1155/2014/935129")!, kind: .paper, checked: "2026-10-08")
  static let koocheki2009 = Citation(
    "The rheological properties of ketchup as a function of different hydrocolloids and temperature",
    publisher: "Koocheki et al., Int. J. Food Sci. Tech. 44, 596 (2009)",
    url: URL(string: "https://doi.org/10.1111/j.1365-2621.2008.01868.x")!, kind: .paper, checked: "2026-10-08")
  static let shaw1968 = Citation(
    "The viscosity of basaltic magma: field measurements in Makaopuhi lava lake, Hawaii",
    publisher: "Shaw, Wright, Peck & Okamura, Am. J. Sci. 266, 225 (1968)",
    url: URL(string: "https://doi.org/10.2475/ajs.266.4.225")!, kind: .paper, checked: "2026-10-08")

  static let all: [LiteraturePoint] = [
    LiteraturePoint(
      id: "honey-saxena", material: "honey", label: "Honey · Saxena et al. 2014",
      note: "One Indian honey's measured Arrhenius law (85 kJ/mol), at the tank's temperature.", citation: saxena2014,
      points: { t in
        let eta = 1.1e-14 * exp(85_000 / (gasConstant * t))
        return [0.03, 0.3, 3, 30].map { SIMD2($0, eta * $0) }
      }),
    LiteraturePoint(
      id: "water-cheng", material: "waterLike", label: "Water · Cheng 2008",
      note: "Water's viscosity from Cheng's fit to measurements, at the tank's temperature.", citation: cheng2008,
      points: { t in
        let c = min(max(t - 273.15, 0), 100)
        let eta = 1.790e-3 * exp((-1230 - c) * c / (36_100 + 360 * c))
        return [20, 100, 500].map { SIMD2($0, eta * $0) }
      }),
    LiteraturePoint(
      id: "ketchup-koocheki", material: "ketchup", label: "Ketchup · Koocheki et al. 2009",
      note: "A Herschel–Bulkley fit to one measured ketchup at 25 °C: 4.41 Pa yield, K 16.2 Pa·sⁿ, n 0.25.",
      citation: koocheki2009,
      points: { _ in [0.1, 1, 10, 100].map { SIMD2($0, 4.41 + 16.18 * pow($0, 0.25)) } }),
    LiteraturePoint(
      id: "lava-shaw", material: "lava", label: "Lava · Shaw et al. 1968",
      note: "Basalt measured in a Hawaiian lava lake near 1130 °C: 70–120 Pa yield, 650–750 Pa·s. Midpoints shown.",
      citation: shaw1968,
      points: { _ in [0.01, 0.1, 1].map { SIMD2($0, 95 + 700 * $0) } }),
  ]

  static func forMaterial(_ id: MaterialID) -> [LiteraturePoint] { all.filter { $0.material == id } }
}
