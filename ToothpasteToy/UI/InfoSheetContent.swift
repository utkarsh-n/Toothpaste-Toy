// InfoSheetContent.swift — OWNER: UI (Documentation/REDESIGN-OWNERSHIP.md).
//
// "How Toothpaste Toy works": Metro's separate explanation surface (spec §4, §12 — a large rounded title, readable
// native prose in quiet content panels, units and assumptions beside every number). Nine panels in LabKit's fixed order:
// 01 what you're looking at (with REDESIGN.md §6's honesty sentence, verbatim), 02 play, 03 the hologram (what each
// colour and effect means, and that it is a look), 04 the controls, 05 experiments, 06 what's real and what's
// illustrative (with this build's numbers, read from the solver), 07 sensors, 08 sound and feel, 09 sources and
// licences (papers, published measurements, Box2D, PB-MPM, Wave) with the method and privacy notes.
//
// The copy lives in ToothpasteCopy (linted by UITests). `-info` opens it, `-large` at the large detent, `-infoPanel 06`
// scrolled to a panel (pictures).

import LabKitCore
import LabKitMPM
import LabKitSensors
import LabKitUI
import SwiftUI

struct ToothpasteInfoSheet: View {
  @Bindable var model: ToothpasteModel
  @Environment(\.dismiss) private var dismiss
  @State private var detent: PresentationDetent = ToothpasteUIArgs.has("-large") ? .large : .medium

  var body: some View {
    NavigationStack {
      ToothpasteInfoContent(model: model)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button(ToothpasteCopy.done) { dismiss() }.accessibilityIdentifier("info-done")
          }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    .presentationDetents([.medium, .large], selection: $detent)
    .presentationBackground(Metro.Colour.canvas.color)
    .accessibilityIdentifier("info")
  }
}

struct ToothpasteInfoContent: View {
  @Bindable var model: ToothpasteModel

  private var domain: MPMDomain { model.resources.solver?.domain ?? MPMDomain() }
  private var lifeSize: Bool { model.tankView.isLifeSize }
  /// The chamber's drawn scale (region points per tank metre × metres per point), nil on an unknown phone.
  private var drawnScale: Double? {
    let v = model.tankView
    return v.metresPerPoint.map { $0 / v.baseMetresPerPoint }
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text(ToothpasteCopy.howItWorks)
            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            .foregroundStyle(Metro.Colour.displayInk.color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
          looking.id("01")
          play.id("02")
          hologram.id("03")
          controls.id("04")
          experiments.id("05")
          honesty.id("06")
          sensors.id("07")
          feel.id("08")
          sources.id("09")
        }
        .padding(16)
      }
      .task {
        guard let target = ToothpasteUIArgs.value("-infoPanel") else { return }
        try? await Task.sleep(for: .milliseconds(600))
        proxy.scrollTo(target, anchor: .top)
      }
    }
    .background { InstrumentDesignBackground() }
  }

  // MARK: 01

  private var looking: some View {
    InfoPanel("01", ToothpasteCopy.panelLooking) {
      Text(ToothpasteCopy.introLine)
        .font(.system(.title3, design: .rounded, weight: .semibold))
        .foregroundStyle(Metro.Colour.displayInk.color)
        .fixedSize(horizontal: false, vertical: true)
      Text(ToothpasteCopy.honestySentence)
        .font(.system(.body, design: .serif, weight: .medium))
        .italic()
        .foregroundStyle(Metro.Colour.instrumentCyan.color)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("info-honesty")
      Prose(ToothpasteCopy.introDetail(
        tank: model.engine.tankSize, lifeSize: lifeSize, scale: drawnScale, materials: model.catalog.materials.count))
      FlowCurvePlot(model: model, viscosity: false, compact: false, overview: true)
        .frame(height: 220)
        .padding(8)
        .background(Metro.Colour.plot.color, in: .rect(cornerRadius: Metro.Radius.plot))
      Caption(ToothpasteCopy.introCaption)
    }
  }

  // MARK: 02

  private var play: some View {
    InfoPanel("02", ToothpasteCopy.panelPlay) {
      ForEach(ToothpasteCopy.playNotes, id: \.title) { note in
        Note(title: note.title, text: note.text)
      }
    }
  }

  // MARK: 03

  private var hologram: some View {
    InfoPanel("03", ToothpasteCopy.panelHologram) {
      ForEach(ToothpasteCopy.hologramLegend, id: \.title) { item in
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Circle().fill(item.colour.color).frame(width: 9, height: 9).accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 2) {
            Text(item.title).font(.system(.subheadline, design: .rounded, weight: .semibold))
              .foregroundStyle(Metro.Colour.displayInk.color)
            Prose(item.text)
          }
        }
        .accessibilityElement(children: .combine)
      }
      Text(ToothpasteCopy.honestySentence)
        .font(.system(.subheadline, design: .serif, weight: .medium))
        .italic()
        .foregroundStyle(Metro.Colour.instrumentCyan.color)
        .fixedSize(horizontal: false, vertical: true)
      Divider().overlay(Color.white.opacity(0.07))
      ForEach(model.catalog.materials) { m in
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Circle().fill(Color(LabPalette.rheo.data(m.id))).frame(width: 8, height: 8).accessibilityHidden(true)
          Prose("\(m.title): \(ToothpasteCopy.hologramIdentity(m))")
        }
      }
    }
  }

  // MARK: 04

  private var controls: some View {
    InfoPanel("04", ToothpasteCopy.panelControls) {
      ForEach(ToothpasteCopy.controlNotes(gravity: model.params.spec(.gravity), heat: model.params.spec(.heat)), id: \.title) {
        Note(title: $0.title, text: $0.text)
      }
    }
  }

  // MARK: 05

  private var experiments: some View {
    InfoPanel("05", ToothpasteCopy.panelExperiments) {
      Caption(Experiment.commonEffects(model.catalog.experiments).sentence)
      ForEach(model.catalog.experiments) { e in
        VStack(alignment: .leading, spacing: 3) {
          Label {
            Text("\(e.title)\(LabFormat.separator)\(e.subtitle)")
              .font(.system(.subheadline, design: .rounded, weight: .semibold))
              .foregroundStyle(Metro.Colour.displayInk.color)
          } icon: {
            Image(systemName: e.icon).foregroundStyle(Metro.Colour.actionCyan.color)
          }
          Prose(e.note)
          ForEach(e.sources) { SourceLink($0) }
        }
      }
    }
  }

  // MARK: 06

  private var honesty: some View {
    InfoPanel("06", ToothpasteCopy.panelHonesty) {
      Text(ToothpasteCopy.honestySentence)
        .font(.system(.body, design: .serif, weight: .medium))
        .italic()
        .foregroundStyle(Metro.Colour.instrumentCyan.color)
        .fixedSize(horizontal: false, vertical: true)
      ProvenanceLegend()
      ForEach(
        ToothpasteCopy.honesty(
          tank: model.engine.tankSize, gap: domain.heleShawGap, cell: domain.cellSize, lifeSize: lifeSize,
          scale: drawnScale, honeyRatio: honeyRatio),
        id: \.self
      ) { line in
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Text("•").foregroundStyle(Metro.Colour.actionCyan.color).accessibilityHidden(true)
          Prose(line)
        }
      }
      SectionHeader(ToothpasteCopy.perPasteHeader)
      ForEach(model.catalog.materials) { m in
        VStack(alignment: .leading, spacing: 3) {
          Label(m.title, systemImage: m.icon)
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(Color(LabPalette.rheo.data(m.id)))
          Prose("\(ToothpasteCopy.realTitle): \(m.real)")
          Prose("\(ToothpasteCopy.tunedTitle): \(m.tuned)").opacity(0.8)
        }
        .accessibilityElement(children: .combine)
      }
    }
  }

  /// Modelled honey viscosity at 10 °C over 60 °C, from the catalog's own flow curve.
  private var honeyRatio: Double {
    let cold = model.catalog.flowCurve("honey", shearRates: [1], temperature: 283.15)[0]
    let warm = model.catalog.flowCurve("honey", shearRates: [1], temperature: 333.15)[0]
    return cold / warm
  }

  // MARK: 07

  private var sensors: some View {
    InfoPanel("07", ToothpasteCopy.panelSensors) {
      Prose(ToothpasteCopy.sensorsIntro)
      LiveSensorRows(model: model)
      Toggle(ToothpasteCopy.useTilt, isOn: $model.layers.useTilt)
      Toggle(ToothpasteCopy.useMagnetometer, isOn: $model.layers.useMagnetometer)
      LiveMicGate(model: model)
    }
  }

  // MARK: 08

  private var feel: some View {
    InfoPanel("08", ToothpasteCopy.panelFeel) {
      FeedbackSettings(
        feedback: model.feedback, feelTitle: ToothpasteCopy.feelToggle, feelExplanation: ToothpasteCopy.feelExplanation,
        soundExplanation: ToothpasteCopy.soundExplanation)
    }
  }

  // MARK: 09

  private var papers: [Citation] {
    var seen = Set<String>()
    let code = Set(ToothpasteLicences.all.map { $0.citation.url })
    let all = model.catalog.sources + model.catalog.experiments.flatMap(\.sources) + LiteraturePoints.all.map(\.citation)
    return all.filter { c in !code.contains(c.url) && seen.insert(c.id).inserted }
  }

  private var sources: some View {
    InfoPanel("09", ToothpasteCopy.panelSources) {
      SectionHeader(ToothpasteCopy.papersHeader)
      VStack(alignment: .leading, spacing: 4) {
        ForEach(papers) { SourceLink($0) }
      }
      SectionHeader(ToothpasteCopy.codeHeader).id("09-code")
      ForEach(ToothpasteLicences.all) { l in
        VStack(alignment: .leading, spacing: 6) {
          SourceLink(l.citation)
          Prose(l.summary)
          DisclosureGroup(ToothpasteCopy.licenceDisclosure) {
            Text(l.text)
              .font(.system(.caption2, design: .monospaced))
              .foregroundStyle(Metro.Colour.secondaryInk.color)
              .fixedSize(horizontal: false, vertical: true)
              .textSelection(.enabled)
              .padding(.top, 6)
          }
          .font(.subheadline)
          .tint(Metro.Colour.actionCyan.color)
          .accessibilityIdentifier("licence-\(l.licence)")
        }
      }
      LiveMethodNote(model: model, cell: domain.cellSize)
        .id("09-end")
    }
  }
}

// MARK: - Panel parts

/// A numbered Metro content panel: "01 / WHAT YOU'RE LOOKING AT" in cyan monospace, then the content.
private struct InfoPanel<Content: View>: View {
  let number: String
  let title: String
  let content: Content

  init(_ number: String, _ title: String, @ViewBuilder content: () -> Content) {
    self.number = number
    self.title = title
    self.content = content()
  }

  var body: some View {
    InstrumentContentPanel {
      VStack(alignment: .leading, spacing: 12) {
        Text("\(number) / \(title.uppercased())")
          .font(.system(.caption, design: .monospaced, weight: .medium))
          .tracking(1.7)
          .foregroundStyle(Metro.Colour.actionCyan.color)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityLabel("\(number). \(title)")
          .accessibilityAddTraits(.isHeader)
        content
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct Prose: View {
  let text: String
  init(_ text: String) { self.text = text }
  var body: some View {
    Text(text)
      .font(.subheadline)
      .foregroundStyle(Metro.Colour.displayInk.color.opacity(0.88))
      .fixedSize(horizontal: false, vertical: true)
  }
}

private struct Caption: View {
  let text: String
  init(_ text: String) { self.text = text }
  var body: some View {
    Text(text)
      .font(.footnote)
      .foregroundStyle(Metro.Colour.secondaryInk.color)
      .fixedSize(horizontal: false, vertical: true)
  }
}

private struct Note: View {
  let title: String
  let text: String
  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.system(.subheadline, design: .rounded, weight: .semibold))
        .foregroundStyle(Metro.Colour.displayInk.color)
      Prose(text)
    }
    .accessibilityElement(children: .combine)
  }
}

private struct SectionHeader: View {
  let text: String
  init(_ text: String) { self.text = text }
  var body: some View {
    Text(text.uppercased())
      .font(.system(.caption2, design: .monospaced, weight: .medium))
      .tracking(1.4)
      .foregroundStyle(Metro.Colour.secondaryInk.color)
      .padding(.top, 4)
      .accessibilityAddTraits(.isHeader)
  }
}

// MARK: - The parts that follow the 10 Hz telemetry

/// Panel 07's live sensor rows, each with its provenance.
private struct LiveSensorRows: View {
  let model: ToothpasteModel
  var body: some View {
    let t = model.telemetry
    let motion: Provenance = t.simulatedMotion ? .simulated : .live
    let mic = model.feel.micState
    let thermal = model.resources.thermal
    VStack(spacing: 6) {
      SensorRow(TelemetryRow(ToothpasteCopy.rowTilt, icon: "level", value: ToothpasteCopy.tiltValue(t.tiltDegrees), provenance: motion))
      SensorRow(TelemetryRow(ToothpasteCopy.rowShake, icon: "iphone.motion", value: ToothpasteCopy.shakeValue(t.shakeG), provenance: motion))
      SensorRow(TelemetryRow(
        ToothpasteCopy.rowField, icon: "location.north.line.fill",
        value: ToothpasteCopy.fieldValue(t.fieldMicroTesla, enabled: model.layers.useMagnetometer),
        provenance: LaunchOptions.has(LaunchOptions.fakeMagnet) || t.simulatedMotion ? .simulated : .live))
      SensorRow(TelemetryRow(
        ToothpasteCopy.rowMic, icon: mic == .denied ? "mic.slash.fill" : "mic.fill",
        value: ToothpasteCopy.micValue(mic, dBFS: t.micDBFS),
        provenance: LaunchOptions.has(LaunchOptions.fakeMic) ? .simulated : .live))
      SensorRow(TelemetryRow(
        ToothpasteCopy.rowHeat, icon: "thermometer.medium", value: ToothpasteCopy.heatValue(thermal.state),
        provenance: thermal.isFake ? .simulated : .live))
    }
  }
}

/// Panel 07's microphone line: the PermissionGate when it is refused or failed, the hint while it is off.
private struct LiveMicGate: View {
  let model: ToothpasteModel

  var body: some View {
    let _ = model.telemetry.micDBFS  // subscribes to the 10 Hz tick
    switch model.feel.micState {
    case .denied, .failed:
      PermissionGate(
        ToothpasteCopy.micDeniedTitle, icon: "mic.slash.fill", message: ToothpasteCopy.micDeniedText,
        canOpenSettings: model.feel.micState == .denied)
    case .off:
      Caption(ToothpasteCopy.micHint)
    case .on, .starting:
      EmptyView()
    }
  }
}

/// Panel 09's closing footnote (the method, with the live particle count) and the privacy sentence.
private struct LiveMethodNote: View {
  let model: ToothpasteModel
  let cell: Double
  var body: some View {
    SourceList([], method: ToothpasteCopy.method(particles: model.telemetry.particles, cell: cell), privacy: ToothpasteCopy.privacy)
  }
}
