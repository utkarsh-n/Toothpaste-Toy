// PastePicker.swift — OWNER: UI (Documentation/REDESIGN-OWNERSHIP.md).
//
// The material picker (REDESIGN.md §1, §5.7): toothpaste is the hero — one large tile at the top — and the twelve other
// materials Rheo built stay as "Other pastes", a quiet grid of Metro content tiles (data-hue swatch, name, what it does).
// Tapping a tile fills the chamber with that paste (a Fill) and closes the sheet; the chosen tile carries a cyan border
// and a check (selected state by shape and text as well as colour).

import LabKitCore
import LabKitUI
import SwiftUI

struct PastePicker: View {
  let model: ToothpasteModel
  let choose: (MaterialID) -> Void
  @Environment(\.dismiss) private var dismiss

  private var hero: MaterialInfo { model.catalog.material(defaultMaterialID) }
  private var others: [MaterialInfo] { model.catalog.materials.filter { $0.id != defaultMaterialID } }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          heroTile
          Text(ToothpasteCopy.otherPastes.uppercased())
            .font(.system(.caption, design: .monospaced, weight: .medium))
            .tracking(1.7)
            .foregroundStyle(Metro.Colour.secondaryInk.color)
            .accessibilityAddTraits(.isHeader)
          LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(others) { m in tile(m) }
          }
          Text(ToothpasteCopy.pastesFootnote)
            .font(.footnote)
            .foregroundStyle(Metro.Colour.secondaryInk.color)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
      }
      .background { InstrumentDesignBackground() }
      .navigationTitle(ToothpasteCopy.pastesTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(ToothpasteCopy.done) { dismiss() }.accessibilityIdentifier("pastes-done")
        }
      }
    }
    .presentationDetents([.medium, .large])
    .presentationBackground(Metro.Colour.canvas.color)
    .accessibilityIdentifier("pastes")
  }

  private var heroTile: some View {
    let m = hero
    let selected = model.materialID == m.id
    return Button {
      choose(m.id)
    } label: {
      HStack(alignment: .center, spacing: 14) {
        StripeSwatch(colour: Color(LabPalette.rheo.data(m.id)))
          .frame(width: 54, height: 54)
        VStack(alignment: .leading, spacing: 4) {
          Text(m.title)
            .font(.system(.title2, design: .rounded, weight: .semibold))
            .foregroundStyle(Metro.Colour.displayInk.color)
          Text(ToothpasteCopy.heroMeaning)
            .font(.system(.subheadline, design: .serif, weight: .medium))
            .italic()
            .foregroundStyle(Metro.Colour.instrumentCyan.color)
          Text(ToothpasteCopy.heroLine(yield: ToothpasteKnobs.yieldStress(m.material)))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(Metro.Colour.secondaryInk.color)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
        if selected {
          Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Metro.Colour.actionCyan.color)
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Metro.Colour.content.color.opacity(Metro.Opacity.panelFill), in: .rect(cornerRadius: Metro.Radius.contentPanel))
      .overlay {
        RoundedRectangle(cornerRadius: Metro.Radius.contentPanel)
          .strokeBorder(selected ? Metro.Colour.actionCyan.color.opacity(0.45) : .white.opacity(Metro.Opacity.panelBorder), lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(m.title)
    .accessibilityValue(selected ? ToothpasteCopy.inTheTube : "")
    .accessibilityHint(ToothpasteCopy.tileHint(m))
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier("paste-\(m.id)")
  }

  private func tile(_ m: MaterialInfo) -> some View {
    let selected = model.materialID == m.id
    return Button {
      choose(m.id)
    } label: {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          Circle()
            .fill(Color(LabPalette.rheo.data(m.id)))
            .frame(width: 10, height: 10)
            .shadow(color: Color(LabPalette.rheo.data(m.id)).opacity(0.6), radius: 4)
          Text(m.title)
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(Metro.Colour.displayInk.color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
          Spacer(minLength: 0)
          if selected {
            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Metro.Colour.actionCyan.color)
          }
        }
        Text(m.hint)
          .font(.caption)
          .foregroundStyle(Metro.Colour.secondaryInk.color)
          .lineLimit(2, reservesSpace: true)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Metro.Colour.content.color.opacity(Metro.Opacity.panelFill), in: .rect(cornerRadius: 14))
      .overlay {
        RoundedRectangle(cornerRadius: 14)
          .strokeBorder(selected ? Metro.Colour.actionCyan.color.opacity(0.45) : .white.opacity(Metro.Opacity.panelBorder), lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(m.title)
    .accessibilityValue(selected ? ToothpasteCopy.inTheTube : "")
    .accessibilityHint(ToothpasteCopy.tileHint(m))
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier("paste-\(m.id)")
  }
}

/// Toothpaste's three stripes as a small holographic swatch: white core between cyan and violet bands.
struct StripeSwatch: View {
  let colour: Color

  var body: some View {
    Canvas { context, size in
      let r = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
      let shape = Path(roundedRect: r, cornerRadius: r.width * 0.28)
      context.fill(shape, with: .color(Metro.Colour.plot.color))
      context.clip(to: shape)
      let bands: [Color] = [Metro.Colour.instrumentCyan.color, Metro.Colour.displayInk.color, Metro.Colour.spectrum.color]
      for (i, c) in bands.enumerated() {
        var p = Path()
        for s in 0...20 {
          let t = CGFloat(s) / 20
          let x = r.minX + t * r.width
          let y = r.midY + (CGFloat(i) - 1) * r.height * 0.2 + sin(t * .pi * 2) * r.height * 0.12
          if s == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(p, with: .color(c.opacity(0.9)), style: StrokeStyle(lineWidth: r.height * 0.13, lineCap: .round))
      }
      context.stroke(shape, with: .color(colour.opacity(0.5)), lineWidth: 1)
    }
    .accessibilityHidden(true)
  }
}
