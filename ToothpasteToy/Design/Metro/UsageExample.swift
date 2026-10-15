// REFERENCE ONLY — not compiled (project.yml excludes ToothpasteToy/Design/Metro/UsageExample.swift). The Metro Station
// starter's angle-explorer screen, kept verbatim as a composition example for the UI area.

import SwiftUI

// A complete visual integration example. This is an angle explorer, not a
// metronome. It has no audio, haptic engine or motion manager. Supply the host's
// filtered screen-space vector to InstrumentLensSurface when adding tilt.
@available(iOS 26.0, *)
public struct InstrumentDesignUsageExample: View {
    @State private var angle = 45
    @State private var showsExplanation = false
    @ScaledMetric(relativeTo: .title) private var titleSize = 27.0

    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            let diameter = min(360, max(1, geometry.size.width - 48))
            ZStack {
                InstrumentDesignBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Angle Lab")
                                    .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                                Text("ANGLE EXPLORER")
                                    .font(.system(.caption2, design: .monospaced))
                                    .tracking(2)
                                    .foregroundStyle(InstrumentPalette.secondaryInk)
                            }
                            Spacer()
                            InstrumentGlassIconButton("info", label: "Angle explanation") {
                                showsExplanation = true
                            }
                        }
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [
                                    Color(red: 0.055, green: 0.073, blue: 0.090),
                                    Color(red: 0.021, green: 0.032, blue: 0.042)
                                ], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1.4))
                                .shadow(color: .black.opacity(0.8), radius: 22, y: 16)
                            InstrumentLensSurface(diameter: diameter) {
                                calibration(diameter: diameter)
                            } readout: {
                                InstrumentLargeReadout(diameter: diameter, value: "\(angle)",
                                                       unit: "DEGREES", meaning: "Angle",
                                                       spokenLabel: "Selected angle")
                            }
                        }
                        .frame(width: diameter, height: diameter)

                        InstrumentParameterStepper("ANGLE", value: $angle, in: 0...180, unit: "°")
                            .frame(maxWidth: 380)

                        InstrumentContentPanel {
                            HStack(spacing: 12) {
                                InstrumentMetricReadout("DEGREES", value: "\(angle)", unit: "°")
                                InstrumentMetricReadout(
                                    "RADIANS",
                                    value: (Double(angle) * .pi / 180).formatted(.number.precision(.fractionLength(2))),
                                    unit: "rad", color: InstrumentPalette.actionAmber)
                            }
                        }
                        Text("Adjust the angle with the Stepper. The readout stays centered.")
                            .font(.body)
                            .foregroundStyle(InstrumentPalette.secondaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 98)
                    .frame(maxWidth: 540)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .overlay(alignment: .bottom) {
                    GlassEffectContainer(spacing: 14) {
                        Button {
                            angle = 45
                        } label: {
                            Label("Reset angle", systemImage: "arrow.uturn.backward")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 58)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(InstrumentPalette.actionCyan)
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 12)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsExplanation) {
            NavigationStack {
                Form {
                    Section("Angle") {
                        Text("A degree is one three-hundred-and-sixtieth of a full turn.")
                        Text("Radians = degrees × π / 180")
                            .font(.system(.callout, design: .monospaced))
                        Text("The scale runs from zero to 180 degrees. Positive angles point upward from the right-hand direction.")
                    }
                }
                .navigationTitle("Angle")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showsExplanation = false }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func calibration(diameter: CGFloat) -> some View {
        Canvas { context, _ in
            let center = CGPoint(x: diameter / 2, y: diameter / 2)
            let radius = diameter * 0.445
            for index in 0...36 {
                let radians = -Double(index * 5) * .pi / 180
                let long = index % 6 == 0
                let inner = radius - (long ? 12 : 6)
                var mark = Path()
                mark.move(to: CGPoint(x: center.x + inner * cos(radians),
                                     y: center.y + inner * sin(radians)))
                mark.addLine(to: CGPoint(x: center.x + radius * cos(radians),
                                         y: center.y + radius * sin(radians)))
                context.stroke(mark, with: .color(.white.opacity(long ? 0.36 : 0.16)),
                               lineWidth: long ? 1 : 0.6)
            }
            let pivot = center
            let radians = -Double(angle) * .pi / 180
            let length = diameter * 0.20
            var pointer = Path()
            pointer.move(to: pivot)
            pointer.addLine(to: CGPoint(x: pivot.x + length * cos(radians),
                                        y: pivot.y + length * sin(radians)))
            context.stroke(pointer, with: .color(InstrumentPalette.instrumentAmber),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .frame(width: diameter, height: diameter)
    }
}

