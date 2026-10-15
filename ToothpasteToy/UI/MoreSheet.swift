// MoreSheet.swift — OWNER: UI (Documentation/REDESIGN-OWNERSHIP.md).
//
// "More" (REDESIGN.md §4; Metro spec §12 "Settings and explanations"): a quiet native Form for everything the main
// screen leaves out — the tube (stripes, bore), time, the paste's own rheology knobs, shake and stir, sound in the room,
// the magnet, the look (the hologram or the solid paste, glow, grain, dye, colour maps), sensors, sound and feel,
// experiments, the Rheometer's flow curve and "How Toothpaste Toy works". Whole numbers use Metro's native Stepper;
// continuous knobs use native sliders over the parameter's own sweep (logarithmic where the knob is), named states use a
// Picker. Every slider says its value and unit, and VoiceOver reads the spec's spoken value.

import LabKitCore
import LabKitFeedback
import LabKitMPM
import LabKitUI
import SwiftUI

struct MoreSheet: View {
  @Bindable var model: ToothpasteModel
  /// Swaps this sheet for another (the info sheet) or closes it (nil).
  let open: (ScreenSheet?) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var haptics = true
  @State private var feel = true
  @State private var sound = true

  private var material: MaterialInfo { model.catalog.material(model.materialID) }

  var body: some View {
    NavigationStack {
      Form {
        tube
        timeSection
        paste
        shake
        listen
        magnet
        look
        sensors
        feelSection
        experiments
        explain
        Section {
          Button(ToothpasteCopy.backToDefaults, role: .destructive) { model.perform(.resetAll) }
            .accessibilityIdentifier("more-reset")
        } footer: {
          Text(ToothpasteCopy.backToDefaultsNote)
        }
      }
      .scrollContentBackground(.hidden)
      .background { InstrumentDesignBackground() }
      .navigationTitle(ToothpasteCopy.more)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(ToothpasteCopy.done) { dismiss() }.accessibilityIdentifier("more-done")
        }
      }
      .onAppear {
        haptics = model.feedback.haptics.enabled
        feel = model.feedback.haptics.humEnabled
        sound = model.feedback.sound
      }
    }
    .presentationDetents([.large])
    .presentationBackground(Metro.Colour.canvas.color)
    .accessibilityIdentifier("more")
  }

  // MARK: Sections

  private var tube: some View {
    Section {
      InstrumentParameterStepper(
        ToothpasteCopy.stripesLabel,
        value: Binding(get: { model.squeeze.stripes }, set: { model.squeeze.stripes = $0 }),
        in: 0...SqueezeState.maxStripes, unit: ToothpasteCopy.bandsUnit(model.squeeze.stripes))
      .listRowBackground(Color.clear)
      .accessibilityIdentifier("more-stripes")
      InstrumentParameterStepper(
        ToothpasteCopy.boreLabel,
        value: Binding(
          get: { Int(model.squeeze.nozzleDiameter.rounded()) }, set: { model.squeeze.nozzleDiameter = Double($0) }),
        in: Int(SqueezeState.nozzleDiameterRange.lowerBound)...Int(SqueezeState.nozzleDiameterRange.upperBound),
        unit: "mm")
      .listRowBackground(Color.clear)
      .accessibilityIdentifier("more-bore")
    } header: {
      Text(ToothpasteCopy.tubeSection)
    } footer: {
      Text(ToothpasteCopy.tubeFootnote)
    }
  }

  private var timeSection: some View {
    Section {
      ParamSlider(store: model.params, id: .time, held: held)
      Picker(ToothpasteCopy.timePresets, selection: Binding(
        get: { abs(model.params[.time] - 0.25) < 0.005 ? 0.25 : abs(model.params[.time] - 1) < 0.005 ? 1.0 : -1 },
        set: { if $0 > 0 { model.params[.time] = $0 } })
      ) {
        Text(ToothpasteCopy.slowMotionPreset).tag(0.25)
        Text(ToothpasteCopy.realTimePreset).tag(1.0)
        if !(abs(model.params[.time] - 0.25) < 0.005 || abs(model.params[.time] - 1) < 0.005) {
          Text(model.params.spec(.time).formatted(model.params[.time])).tag(-1.0)
        }
      }
      .pickerStyle(.segmented)
    } header: {
      Text(ToothpasteCopy.timeSection)
    }
  }

  private var paste: some View {
    Section {
      ForEach(model.catalog.pages.first(where: { $0.id == "fluid" })?.knobs ?? [], id: \.self) { id in
        ParamSlider(store: model.params, id: id, held: held, dimmed: !material.activeKnobs.contains(id))
      }
      ForEach(model.catalog.cardKnobs, id: \.self) { id in
        ParamSlider(store: model.params, id: id, held: held)
      }
      Button(ToothpasteCopy.pasteValues(material)) {
        model.params.reset((model.catalog.pages.first(where: { $0.id == "fluid" })?.knobs ?? []) + model.catalog.cardKnobs)
      }
    } header: {
      Text(ToothpasteCopy.pasteSection(material))
    } footer: {
      Text(ToothpasteCopy.pasteFootnote)
    }
  }

  private var shake: some View {
    Section(ToothpasteCopy.shakeSection) {
      ParamSlider(store: model.params, id: .shake, held: held)
      ParamSlider(store: model.params, id: .rate, held: held)
      ParamSlider(store: model.params, id: .stir, held: held)
    }
  }

  private var listen: some View {
    Section {
      ParamSlider(store: model.params, id: .listen, held: held)
      ParamSlider(store: model.params, id: .drives, held: held)
      ParamSlider(store: model.params, id: .gain, held: held)
      ParamSlider(store: model.params, id: .band, held: held)
    } header: {
      Text(ToothpasteCopy.listenSection)
    } footer: {
      Text(ToothpasteCopy.listenFootnote)
    }
  }

  private var magnet: some View {
    Section {
      ParamSlider(store: model.params, id: .magnet, held: held, dimmed: model.materialID != "mrFluid")
    } header: {
      Text(ToothpasteCopy.magnetSection)
    } footer: {
      Text(ToothpasteCopy.magnetFootnote)
    }
  }

  private var look: some View {
    Section {
      Toggle(ToothpasteCopy.solidLook, isOn: $model.layers.solid).accessibilityIdentifier("more-solid")
      Toggle(ToothpasteCopy.stressLight, isOn: $model.layers.stressLight)
      Toggle(ToothpasteCopy.dyeLines, isOn: $model.layers.dyeLines)
      Toggle(ToothpasteCopy.particles, isOn: $model.layers.particles)
      Toggle(ToothpasteCopy.rheometerCursor, isOn: $model.layers.rheometerCursor)
      Picker(ToothpasteCopy.colourBy, selection: $model.layers.diagnostic) {
        ForEach(FluidDiagnostic.allCases, id: \.self) { d in Text(ToothpasteCopy.colourByTitle(d)).tag(d) }
      }
      ForEach([ParamID.glow, .grain, .tracers, .depth], id: \.self) { id in
        ParamSlider(store: model.params, id: id, held: held)
      }
    } header: {
      Text(ToothpasteCopy.lookSection)
    } footer: {
      Text(ToothpasteCopy.lookFootnote)
    }
  }

  private var sensors: some View {
    Section(ToothpasteCopy.sensorsSection) {
      Toggle(ToothpasteCopy.useTilt, isOn: $model.layers.useTilt)
      Toggle(ToothpasteCopy.useMagnetometer, isOn: $model.layers.useMagnetometer)
    }
  }

  private var feelSection: some View {
    Section {
      Toggle(ToothpasteCopy.hapticsToggle, isOn: $haptics)
        .onChange(of: haptics) { _, on in model.feedback.haptics.enabled = on }
      Toggle(ToothpasteCopy.feelToggle, isOn: $feel)
        .onChange(of: feel) { _, on in model.feedback.haptics.humEnabled = on }
      Toggle(ToothpasteCopy.soundToggle, isOn: $sound)
        .onChange(of: sound) { _, on in model.feedback.sound = on }
    } header: {
      Text(ToothpasteCopy.feelSectionTitle)
    } footer: {
      Text(ToothpasteCopy.feelFootnote)
    }
  }

  private var experiments: some View {
    Section {
      ForEach(model.catalog.experiments) { e in
        Button {
          model.apply(e)
          model.feedback.haptics.success()
          dismiss()
        } label: {
          Label {
            VStack(alignment: .leading, spacing: 2) {
              Text(e.title).foregroundStyle(Metro.Colour.displayInk.color)
              Text(e.subtitle).font(.caption).foregroundStyle(Metro.Colour.secondaryInk.color)
            }
          } icon: {
            Image(systemName: e.icon).foregroundStyle(Metro.Colour.actionCyan.color)
          }
        }
        .accessibilityIdentifier("experiment-\(e.id)")
      }
    } header: {
      Text(ToothpasteCopy.experimentsSection)
    } footer: {
      Text(Experiment.commonEffects(model.catalog.experiments).sentence)
    }
  }

  private var explain: some View {
    Section {
      NavigationLink {
        RheometerContent(model: model)
          .navigationTitle(ToothpasteCopy.rheometer)
          .navigationBarTitleDisplayMode(.inline)
      } label: {
        Label(ToothpasteCopy.rheometer, systemImage: "chart.xyaxis.line")
      }
      .accessibilityIdentifier("more-rheometer")
      Button {
        open(.info)
      } label: {
        Label(ToothpasteCopy.howItWorks, systemImage: "info.circle")
      }
      .accessibilityIdentifier("more-info")
    } header: {
      Text(ToothpasteCopy.explainSection)
    }
  }

  private func held(_ id: ParamID, _ on: Bool) {
    model.heldKnobs = on ? [id] : []
  }
}

/// One parameter as a native control: a slider over its sweep (logarithmic when the knob is), or a Picker for a rotary
/// switch. Title, the formatted value with its unit, and the knob's hint underneath.
struct ParamSlider: View {
  let store: ParamStore
  let id: ParamID
  let held: (ParamID, Bool) -> Void
  var dimmed = false

  var body: some View {
    let spec = store.spec(id)
    let value = store[id]
    VStack(alignment: .leading, spacing: 6) {
      if spec.isSwitch {
        Picker(spec.title, selection: Binding(get: { Int(value.rounded()) }, set: { store[id] = Double($0) })) {
          ForEach(0..<spec.switchCount, id: \.self) { i in
            Text(spec.formatted(spec.range.lowerBound + Double(i) * spec.step)).tag(Int(spec.range.lowerBound) + i)
          }
        }
      } else {
        HStack(alignment: .firstTextBaseline) {
          Text(spec.title)
          Spacer(minLength: 8)
          Text(spec.formatted(value))
            .font(.system(.body, design: .rounded, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Metro.Colour.actionCyan.color)
        }
        Slider(
          value: Binding(get: { spec.position(of: store[id]) }, set: { store[id] = spec.value(at: $0) }), in: 0...1
        ) { editing in
          held(id, editing)
        }
        .accessibilityLabel(spec.accessibilityLabel)
        .accessibilityValue(spec.accessibilityValue(value))
      }
      Text(dimmed ? ToothpasteCopy.dimmedNote(spec.title) : spec.hint)
        .font(.footnote)
        .foregroundStyle(Metro.Colour.secondaryInk.color)
        .fixedSize(horizontal: false, vertical: true)
    }
    .opacity(dimmed ? 0.55 : 1)
    .accessibilityIdentifier("param-\(id.rawValue)")
  }
}
