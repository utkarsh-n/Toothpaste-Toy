// MetroActions.swift — OWNER: UI (Documentation/REDESIGN-OWNERSHIP.md).
//
// The floating action group (Metro spec §12, REDESIGN.md §4): native Liquid Glass over the page, no backing strip, one
// prominent primary action between secondary ones — Refill · Freeze · SQUEEZE · Rheometer · Info. The primary is the
// press-and-hold Squeeze (the accessible twin of the Squeeze crown): cyan at rest, amber while it squeezes (Metro: cyan
// stopped, amber running). Label frames are sized before the glass (52 × 58 side actions, the primary takes the rest,
// row spacing 10, glass container spacing 14); the screen reserves the group's real footprint.

import LabKitCore
import SwiftUI

struct FloatingActions: View {
  let motion: ChamberMotion
  let paused: Bool
  let refill: () -> Void
  let toggleFreeze: () -> Void
  let rheometer: () -> Void
  let info: () -> Void

  static let sideWidth: CGFloat = 52
  static let height: CGFloat = Metro.Layout.transportLabelMinHeight
  /// The space the group takes at the bottom of the screen (label height + Metro's 10 pt top and 12 pt bottom insets).
  static let reserve: CGFloat = height + Metro.Spacing.transportTop + Metro.Spacing.transportBottom

  var body: some View {
    GlassEffectContainer(spacing: Metro.Layout.transportGlassSpacing) {
      HStack(spacing: 10) {
        side("arrow.counterclockwise", ToothpasteCopy.refillCaption, ToothpasteCopy.refillLabel, "action-refill", refill)
        side(
          paused ? "play.fill" : "pause.fill", paused ? ToothpasteCopy.resumeCaption : ToothpasteCopy.freezeCaption,
          paused ? ToothpasteCopy.resumeLabel : ToothpasteCopy.freezeLabel, "action-freeze", toggleFreeze)
        SqueezeHoldButton(motion: motion)
        side("chart.xyaxis.line", ToothpasteCopy.flowCaption, ToothpasteCopy.rheometer, "action-rheometer", rheometer)
        side("info", ToothpasteCopy.infoCaption, ToothpasteCopy.howItWorks, "action-info", info)
      }
    }
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
  }

  private func side(_ symbol: String, _ caption: String, _ label: String, _ id: String, _ action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      VStack(spacing: 4) {
        Image(systemName: symbol).font(.system(size: 18, weight: .medium))
        Text(caption)
          .font(.system(size: 9, weight: .medium, design: .monospaced))
          .tracking(0.8)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      .foregroundStyle(Metro.Colour.actionCyan.color)
      .frame(width: Self.sideWidth, height: Self.height)
      .contentShape(.capsule)
      .glassEffect(.regular.tint(Metro.Colour.actionCyan.color.opacity(0.06)).interactive(), in: .capsule)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .accessibilityIdentifier(id)
    .instrumentControlOwnsTouches(identifier: id)
  }
}

/// Press and hold to squeeze; release to tear the ribbon off. VoiceOver's activate squeezes for 1.5 s.
struct SqueezeHoldButton: View {
  let motion: ChamberMotion
  @State private var holding = false

  var body: some View {
    let squeezing = motion.squeezeSource != .none
    let tint = squeezing ? Metro.Colour.actionAmber.color : Metro.Colour.actionCyan.color
    HStack(spacing: 8) {
      Image(systemName: squeezing ? "drop.fill" : "drop")
        .font(.system(size: 17, weight: .semibold))
      Text(squeezing ? ToothpasteCopy.squeezingTitle : ToothpasteCopy.squeezeTitle)
        .font(.system(size: 17, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .foregroundStyle(Metro.Colour.canvas.color)
    .frame(maxWidth: .infinity, minHeight: FloatingActions.height, maxHeight: FloatingActions.height)
    .contentShape(.capsule)
    .glassEffect(.regular.tint(tint.opacity(0.92)).interactive(), in: .capsule)
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { _ in
          guard !holding else { return }
          holding = true
          motion.setSqueeze(.button)
        }
        .onEnded { _ in
          holding = false
          if motion.squeezeSource == .button { motion.setSqueeze(.none) }
        })
    .instrumentControlOwnsTouches(identifier: "action-squeeze")
    .accessibilityElement(children: .ignore)
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel(ToothpasteCopy.squeezeTitle)
    .accessibilityValue(squeezing ? ToothpasteCopy.squeezingTitle : "")
    .accessibilityHint(ToothpasteCopy.squeezeButtonHint)
    .accessibilityAction {
      motion.setSqueeze(.button)
      Task { @MainActor in
        try? await Task.sleep(for: .seconds(1.5))
        if motion.squeezeSource == .button { motion.setSqueeze(.none) }
      }
    }
    .accessibilityIdentifier("action-squeeze")
    .onDisappear {
      if holding, motion.squeezeSource == .button { motion.setSqueeze(.none) }
      holding = false
    }
  }
}
