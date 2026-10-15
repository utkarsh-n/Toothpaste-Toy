// RheometerSheet.swift — OWNER: UI (Documentation/REDESIGN-OWNERSHIP.md).
//
// The Rheometer (REDESIGN.md §4; Metro "signal lab" panel, spec §12): the paste's flow curve σ(γ̇) — or η(γ̇) — on log-log
// axes, the current paste bright and the other twelve faint, iso-viscosity guides and the yield floor, published
// measurements as hollow rings, and the live cursor at the probe (the lens, or the most sheared spot). Under it, the
// probe's three readouts (Metro telemetry: label, rounded numerals, monospaced unit) and the published measurements with
// their sources. The plot says what is modelled and what is measured. Presented from the floating action group, and
// pushed from More.

import LabKitCore
import LabKitSensors
import LabKitUI
import SwiftUI

struct RheometerSheet: View {
  let model: ToothpasteModel
  @Environment(\.dismiss) private var dismiss
  @State private var detent: PresentationDetent = ToothpasteUIArgs.has("-large") ? .large : .medium

  var body: some View {
    NavigationStack {
      RheometerContent(model: model)
        .navigationTitle(ToothpasteCopy.rheometer)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button(ToothpasteCopy.done) { dismiss() }.accessibilityIdentifier("rheometer-done")
          }
        }
    }
    .presentationDetents([.medium, .large], selection: $detent)
    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    .presentationBackground(Metro.Colour.canvas.color)
    .accessibilityIdentifier("rheometer")
  }
}

struct RheometerContent: View {
  let model: ToothpasteModel
  @State private var viscosityView = false

  private var material: MaterialInfo { model.catalog.material(model.materialID) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        InstrumentContentPanel {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text(viscosityView ? ToothpasteCopy.viscosityCurveTitle : ToothpasteCopy.flowCurveTitle)
                .font(.system(.caption, design: .monospaced, weight: .medium))
                .tracking(1.7)
                .foregroundStyle(Metro.Colour.secondaryInk.color)
              Spacer()
              Picker(ToothpasteCopy.curveSwitchLabel, selection: $viscosityView) {
                Text("σ").tag(false)
                Text("η").tag(true)
              }
              .pickerStyle(.segmented)
              .frame(width: 96)
              .accessibilityIdentifier("rheometer-curve")
            }
            FlowCurvePlot(model: model, viscosity: viscosityView, compact: false)
              .frame(height: 230)
              .padding(8)
              .background(Metro.Colour.plot.color, in: .rect(cornerRadius: Metro.Radius.plot))
              .overlay {
                RoundedRectangle(cornerRadius: Metro.Radius.plot)
                  .strokeBorder(.white.opacity(Metro.Opacity.plotBorder), lineWidth: Metro.Stroke.plot)
              }
            ProbeReadouts(model: model)
            Text(ToothpasteCopy.rheometerCaption)
              .font(.footnote)
              .foregroundStyle(Metro.Colour.secondaryInk.color)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        literature
      }
      .padding(16)
    }
    .background { InstrumentDesignBackground() }
  }

  /// Published measurements: the current paste's first, then the others, each with its source.
  private var literature: some View {
    let current = LiteraturePoints.forMaterial(model.materialID)
    let others = LiteraturePoints.all.filter { $0.material != model.materialID }
    return InstrumentContentPanel {
      VStack(alignment: .leading, spacing: 12) {
        Text(ToothpasteCopy.literature.uppercased())
          .font(.system(.caption, design: .monospaced, weight: .medium))
          .tracking(1.7)
          .foregroundStyle(Metro.Colour.secondaryInk.color)
          .accessibilityAddTraits(.isHeader)
        ForEach(current + others) { p in
          let m = model.catalog.material(p.material)
          VStack(alignment: .leading, spacing: 4) {
            LegendRow(LabPalette.rheo.data(m.id), glyph: "○", "\(p.label). \(p.note)")
              .opacity(p.material == model.materialID ? 1 : 0.75)
            SourceLink(p.citation)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// η, σ and γ̇ at the probe (10 Hz), as Metro telemetry.
private struct ProbeReadouts: View {
  let model: ToothpasteModel

  var body: some View {
    let t = model.telemetry
    let eta = ToothpasteCopy.quantity(t.probeViscosity, unit: "Pa·s")
    let sigma = ToothpasteCopy.quantity(t.stress, unit: "Pa")
    let rate = ToothpasteCopy.quantity(t.shearRate, unit: "s⁻¹")
    HStack(spacing: 0) {
      cell(ToothpasteCopy.probeViscosity, eta, Metro.Colour.displayInk.color, "readout-viscosity")
      divider
      cell(ToothpasteCopy.stressLabel, sigma, Metro.Colour.actionAmber.color, "readout-stress")
      divider
      cell(ToothpasteCopy.shearLabel, rate, Metro.Colour.actionCyan.color, "readout-shear-rate")
    }
  }

  private var divider: some View {
    Rectangle().fill(.white.opacity(Metro.Opacity.divider)).frame(width: 1, height: 30).accessibilityHidden(true)
  }

  private func cell(_ label: String, _ q: (value: String, unit: String), _ colour: Color, _ id: String) -> some View {
    VStack(spacing: 5) {
      Text(label.uppercased())
        .font(.system(.caption2, design: .monospaced))
        .tracking(Metro.Typography.telemetryLabelTracking)
        .foregroundStyle(Metro.Colour.secondaryInk.color)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(q.value).font(.system(.title3, design: .rounded, weight: .medium)).monospacedDigit().lineLimit(1)
          .minimumScaleFactor(0.6)
        Text(q.unit).font(.system(.caption2, design: .monospaced))
      }
      .foregroundStyle(colour)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .accessibilityValue("\(q.value) \(LabFormat.spoken(q.unit))")
    .accessibilityIdentifier(id)
  }
}

/// The flow curve: the current material bright, the others faint, iso-viscosity guides, a yield floor, published
/// points as hollow rings, and the live cursor at the probe.
struct FlowCurvePlot: View {
  @Bindable var model: ToothpasteModel
  let viscosity: Bool
  let compact: Bool
  /// The info sheet's overview shows every curve at the same weight.
  var overview = false

  static let x = PlotAxis(title: "Shear rate", symbol: "γ̇", unit: "s⁻¹", domain: 0.01...1000, scale: .log10)
  static let stressAxis = PlotAxis(title: "Stress", symbol: "σ", unit: "Pa", domain: 0.01...10_000, scale: .log10)
  static let viscosityAxis = PlotAxis(title: "Viscosity", symbol: "η", unit: "Pa·s", domain: 1e-3...1e5, scale: .log10)

  /// Room temperature, K: the air while lava is in the tank (the engine's ambient then).
  static let roomKelvin = 293.15

  /// The temperature a material's curve (and its published points) is drawn at, K. The Heat knob is the tank's
  /// temperature, 0–90 °C, for every fluid but lava; while lava is in the tank the knob is re-registered as lava's
  /// eruption temperature, 1050–1200 °C, and the air stays at room temperature. So lava's curve follows the knob when it
  /// reads a lava temperature (else lava's reference, 1130 °C), and the other fluids follow it only when it reads a tank
  /// temperature (else room temperature). Never honey at 1170 °C.
  static func curveTemperature(_ m: MaterialInfo, heatCelsius: Double) -> Double {
    let knob = heatCelsius + 273.15
    if m.id == "lava" { return heatCelsius >= 1000 ? knob : m.fillTemperature }
    return heatCelsius <= 100 ? knob : roomKelvin
  }

  var body: some View {
    let palette = LabPalette.rheo
    let x = Self.x
    let y = viscosity ? Self.viscosityAxis : Self.stressAxis
    let rates = (0..<64).map { x.value(at: Double($0) / 63) }
    let current = model.materialID
    let heat = model.params[.heat]
    func temperature(_ m: MaterialInfo) -> Double { Self.curveTemperature(m, heatCelsius: heat) }
    var series = model.catalog.materials.map { m -> PlotSeries in
      let sigma = model.catalog.flowCurve(m.id, shearRates: rates, temperature: temperature(m))
      let points = zip(rates, sigma).map { r, s in SIMD2(r, viscosity ? s / r : s) }
      let bright = overview || m.id == current
      return PlotSeries(
        id: m.id, label: m.title, colour: palette.data(m.id), points: points,
        style: .line(width: m.id == current ? 2 : 1.2, glow: m.id == current ? 0.22 : 0, dash: []), provenance: .modelled,
        opacity: bright ? 1 : 0.3)
    }
    // The current material's curve last, so it draws on top.
    if let i = series.firstIndex(where: { $0.id == current }) { series.append(series.remove(at: i)) }
    for p in LiteraturePoints.all {
      let m = model.catalog.material(p.material)
      let pts = p.points(temperature(m)).map { viscosity ? SIMD2($0.x, $0.y / $0.x) : $0 }
      series.append(
        PlotSeries(
          id: "lit-" + p.id, label: p.label, colour: palette.data(m.id), points: pts,
          style: .markers(diameter: compact ? 5 : 7, hollow: true), provenance: .measured,
          opacity: overview || p.material == current ? 1 : 0.3))
    }
    // The overview (info sheet) has no cursor, so it doesn't read the 10 Hz telemetry and redraw with it.
    let t = overview ? ToothpasteTelemetry() : model.telemetry
    let cursor: SIMD2<Double>? =
      t.shearRate > 0 && t.stress > 0 && t.shearRate.isFinite && t.stress.isFinite
      ? SIMD2(t.shearRate, viscosity ? t.stress / t.shearRate : t.stress) : nil
    let m = model.catalog.material(current)
    return LabPlot(
      title: viscosity ? "Viscosity curve" : "Flow curve", x: x, y: y, series: series, guides: guides(m),
      cursor: cursor,
      summary: ToothpasteCopy.plotSummary(m, catalog: model.catalog, temperature: temperature(m)),
      identifier: compact ? "rheometer-strip" : (overview ? "info-flow-curve" : "flow-curve"))
  }

  /// Iso-viscosity guides (straight lines of slope 1 on σ(γ̇), flat lines on η(γ̇)); on σ(γ̇), a yield floor for
  /// the current material when it has one.
  private func guides(_ m: MaterialInfo) -> [PlotGuide] {
    if viscosity {
      return [
        .horizontal(y: 0.01, label: "0.01 Pa·s"), .horizontal(y: 1, label: "1 Pa·s"),
        .horizontal(y: 100, label: "100 Pa·s"),
      ]
    }
    var g: [PlotGuide] = [
      .powerLaw(prefactor: 0.01, exponent: 1, label: "η 0.01 Pa·s"),
      .powerLaw(prefactor: 1, exponent: 1, label: "1 Pa·s"),
      .powerLaw(prefactor: 100, exponent: 1, label: "100 Pa·s"),
    ]
    let tauY = ToothpasteKnobs.yieldStress(m.material)
    if !overview, tauY > 0.05 {
      g.append(.horizontal(y: tauY, label: "yield " + LabFormat.engineering(tauY, unit: "Pa")))
    }
    return g
  }
}
