import SwiftUI

// Metro Station design foundations (the skill's swiftui-starter, edition 1.0). Minimum deployment: iOS 26.
// Toothpaste Toy adoption (FOUNDATION, 13 October 2026): copied into ToothpasteToy/Design/Metro with the touch bridge,
// LensRefraction and InstrumentLensOptics.metal (compiled into the app's default library); the palette and metrics now
// read the typed tokens in MetroTokens.swift (`Metro`), the app's single source of Metro values. UsageExample.swift sits
// next to this file as a reference only (excluded from the target in project.yml). Domain clocks, sensor
// permission/mapping and haptics stay with the host app. This file introduces no audio or motion manager.

public enum InstrumentPalette {
    public static let canvas = Metro.Colour.canvas.color
    public static let content = Metro.Colour.content.color
    public static let actionCyan = Metro.Colour.actionCyan.color
    public static let actionAmber = Metro.Colour.actionAmber.color
    public static let instrumentCyan = Metro.Colour.instrumentCyan.color
    public static let instrumentAmber = Metro.Colour.instrumentAmber.color
    public static let displayInk = Metro.Colour.displayInk.color
    public static let secondaryInk = Metro.Colour.secondaryInk.color
    public static let wave = Metro.Colour.wave.color
    public static let waveDepth = Metro.Colour.waveDepth.color
    public static let spectrum = Metro.Colour.spectrum.color
    public static let spectrumDepth = Metro.Colour.spectrumDepth.color
    public static let carrier = Metro.Colour.carrier.color
}

public enum InstrumentMetrics {
    public static let panelInset: CGFloat = Metro.Spacing.panelInset
    public static let panelRadius: CGFloat = Metro.Radius.contentPanel
    public static let controlTarget: CGFloat = Metro.Layout.secondaryTargetMin
    public static let stepperHeight: CGFloat = Metro.Layout.stepperMinHeight
    public static let gridSpacing: CGFloat = Metro.Surroundings.gridSpacing
    public static let lensDiameterRatio: CGFloat = Metro.Gauge.lensDiameterRatio
    public static let lensOpacity: Double = Metro.Opacity.lensComposite
}

public struct InstrumentDesignBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init() {}

    public var body: some View {
        ZStack {
            InstrumentPalette.canvas
            if !reduceTransparency {
                RadialGradient(colors: [InstrumentPalette.actionCyan.opacity(Metro.Opacity.environmentWash), .clear],
                               center: .topTrailing, startRadius: Metro.Surroundings.washRadii.lowerBound,
                               endRadius: Metro.Surroundings.washRadii.upperBound)
            }
            Canvas { context, size in
                var grid = Path()
                for x in stride(from: 0.0, through: size.width, by: InstrumentMetrics.gridSpacing) {
                    grid.move(to: CGPoint(x: x, y: 0))
                    grid.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: 0.0, through: size.height, by: InstrumentMetrics.gridSpacing) {
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(grid, with: .color(.white.opacity(Metro.Opacity.grid)), lineWidth: Metro.Stroke.grid)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

public struct InstrumentContentPanel<Content: View>: View {
    private let content: Content
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        content
            .padding(InstrumentMetrics.panelInset)
            .background(InstrumentPalette.content.opacity(reduceTransparency ? 1 : Metro.Opacity.panelFill),
                        in: .rect(cornerRadius: InstrumentMetrics.panelRadius))
            .overlay {
                RoundedRectangle(cornerRadius: InstrumentMetrics.panelRadius)
                    .stroke(.white.opacity(contrast == .increased ? Metro.Opacity.panelBorderIncreasedContrast : Metro.Opacity.panelBorder),
                            lineWidth: Metro.Stroke.panel)
                    .allowsHitTesting(false)
            }
    }
}

@available(iOS 26.0, *)
public struct InstrumentGlassIconButton: View {
    private let symbol: String
    private let label: String
    private let accent: Color
    private let action: () -> Void

    public init(_ symbol: String, label: String,
                accent: Color = InstrumentPalette.actionCyan,
                action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.accent = accent
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: InstrumentMetrics.controlTarget, height: InstrumentMetrics.controlTarget)
                .glassEffect(.regular.tint(accent.opacity(Metro.Opacity.crownGlassTint)).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .instrumentControlOwnsTouches(identifier: "glassIconButton")
    }
}

public struct InstrumentMetricReadout: View {
    private let label: String
    private let value: String
    private let unit: String
    private let color: Color

    public init(_ label: String, value: String, unit: String,
                color: Color = InstrumentPalette.actionCyan) {
        self.label = label
        self.value = value
        self.unit = unit
        self.color = color
    }

    public var body: some View {
        VStack(spacing: 5) {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .tracking(Metro.Typography.telemetryLabelTracking)
                .foregroundStyle(InstrumentPalette.secondaryInk)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.title3, design: .monospaced))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit).font(.system(.caption2, design: .monospaced))
            }
            .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value) \(unit)")
    }
}

public struct InstrumentParameterStepper: View {
    @Binding private var value: Int
    private let label: String
    private let unit: String
    private let range: ClosedRange<Int>
    private let onEditingChanged: (Bool) -> Void
    private let onAcceptedChange: (Int) -> Void
    @ScaledMetric(relativeTo: .caption2) private var labelSize = 11.0
    @ScaledMetric(relativeTo: .body) private var valueSize = 18.0
    @Environment(\.dynamicTypeSize) private var dynamicType

    /// The Binding is updated before onAcceptedChange is called. Use that
    /// notification for feedback or dependent work; do not write/increment
    /// the same value again or publish a second copy of a Binding-side command.
    public init(_ label: String, value: Binding<Int>, in range: ClosedRange<Int>,
                unit: String, onEditingChanged: @escaping (Bool) -> Void = { _ in },
                onAcceptedChange: @escaping (Int) -> Void = { _ in }) {
        self.label = label
        self._value = value
        self.range = range
        self.unit = unit
        self.onEditingChanged = onEditingChanged
        self.onAcceptedChange = onAcceptedChange
    }

    public var body: some View {
        Stepper {
            Group {
                if dynamicType.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        parameterLabel
                        parameterValue
                    }
                } else {
                    HStack(spacing: 10) {
                        parameterLabel
                        parameterValue
                    }
                }
            }
        } onIncrement: {
            adjust(1)
        } onDecrement: {
            adjust(-1)
        } onEditingChanged: { editing in
            onEditingChanged(editing)
        }
        .frame(minHeight: InstrumentMetrics.stepperHeight)
        .padding(.horizontal, Metro.Layout.stepperHorizontalPadding)
        .background(InstrumentPalette.content.opacity(Metro.Opacity.panelFill), in: .capsule)
        .overlay {
            Capsule().strokeBorder(InstrumentPalette.actionCyan.opacity(0.14), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .instrumentControlOwnsTouches(identifier: "parameterStepper")
        .accessibilityHint("Hold plus or minus for repeated adjustments.")
    }

    private var parameterLabel: some View {
        Text(label)
            .font(.system(size: labelSize, weight: .medium, design: .monospaced))
            .tracking(Metro.Typography.stepperLabel.tracking)
            .foregroundStyle(InstrumentPalette.secondaryInk)
    }

    private var parameterValue: some View {
        Text("\(value) \(unit)")
            .font(.system(size: valueSize, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(InstrumentPalette.actionCyan)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func adjust(_ direction: Int) {
        guard (direction > 0 && value < range.upperBound)
                || (direction < 0 && value > range.lowerBound) else { return }
        value += direction
        // Post-write notification; the Binding already owns the value change.
        onAcceptedChange(value)
    }
}

public struct InstrumentLargeReadout: View {
    private let diameter: CGFloat
    private let value: String
    private let unit: String
    private let meaning: String?
    private let spokenLabel: String
    @ScaledMetric(relativeTo: .caption2) private var unitSize = 11.0
    @Environment(\.dynamicTypeSize) private var dynamicType

    public init(diameter: CGFloat, value: String, unit: String,
                meaning: String? = nil, spokenLabel: String) {
        self.diameter = max(1, diameter.isFinite ? diameter : 1)
        self.value = value
        self.unit = unit
        self.meaning = meaning
        self.spokenLabel = spokenLabel
    }

    public var body: some View {
        ZStack {
            Text(value)
                .font(.system(size: diameter * Metro.Typography.heroValueRatio, weight: Metro.Typography.heroValueWeight, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(InstrumentPalette.displayInk)
                .minimumScaleFactor(Metro.Typography.heroValueMinScale)
                .lineLimit(1)
                .frame(width: diameter * Metro.Gauge.readoutWidthRatio)
                .position(x: diameter / 2, y: diameter * Metro.Gauge.readoutYRatio)
            if !dynamicType.isAccessibilitySize {
                Text(unit)
                    .font(.system(size: unitSize, weight: .medium, design: .monospaced))
                    .tracking(Metro.Typography.heroUnit.tracking)
                    .foregroundStyle(.white.opacity(Metro.Opacity.dialMetadataInk))
                    .position(x: diameter / 2, y: diameter * Metro.Gauge.unitsYRatio)
            }
            if let meaning {
                Text(meaning)
                    .font(.system(.subheadline, design: .serif, weight: .medium))
                    .italic()
                    .foregroundStyle(InstrumentPalette.instrumentCyan)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(width: diameter * Metro.Gauge.readoutWidthRatio)
                    .position(x: diameter / 2, y: diameter * (dynamicType.isAccessibilitySize
                        ? Metro.Gauge.meaningYAccessibilityRatio : Metro.Gauge.meaningYRatio))
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityValue([value, unit, meaning ?? ""].filter { !$0.isEmpty }.joined(separator: ", "))
    }
}

// Face must be pure SwiftUI drawing content, preferably Canvas or Shapes.
// UIKit/AppKit-backed subviews cannot be assumed to participate in layerEffect.
// Supply filtered screen-space tilt and a scale sampled from the host's clock.
// This presentation component does not own the host's dial gestures.
@available(iOS 26.0, *)
public struct InstrumentLensSurface<Face: View, Readout: View>: View {
    private let diameter: CGFloat
    private let inputScale: Double
    private let filteredTilt: SIMD2<Double>
    private let motionActive: Bool
    private let face: Face
    private let readout: Readout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase

    public init(diameter: CGFloat, radiusScale: Double = 1,
                filteredTilt: SIMD2<Double> = .zero, motionActive: Bool = false,
                @ViewBuilder face: () -> Face, @ViewBuilder readout: () -> Readout) {
        self.diameter = max(1, diameter.isFinite ? diameter : 1)
        self.inputScale = radiusScale.isFinite
            ? min(Metro.Gauge.radiusScaleRange.upperBound, max(Metro.Gauge.radiusScaleRange.lowerBound, radiusScale)) : 1
        self.filteredTilt = filteredTilt
        self.motionActive = motionActive
        self.face = face()
        self.readout = readout()
    }

    private var enabled: Bool {
        motionActive && !reduceMotion && !reduceTransparency && scenePhase == .active
    }
    private var scale: Double { reduceMotion || scenePhase != .active ? 1 : inputScale }
    private var radius: CGFloat { diameter * Metro.Gauge.lensRadiusRatio * scale }
    private var enhanced: (x: Double, y: Double) {
        LensRefraction.enhancedTilt(x: filteredTilt.x, y: filteredTilt.y, enabled: enabled)
    }
    private var samplingBound: CGFloat {
        LensRefraction.maximumShift(diameter: diameter)
            + LensRefraction.maximumChannelSplit(diameter: diameter) * Metro.Optics.channelOffsetFractionOfTotal
    }

    public var body: some View {
        ZStack {
            face
                .frame(width: diameter, height: diameter)
                .layerEffect(shader, maxSampleOffset: CGSize(width: samplingBound, height: samplingBound),
                             isEnabled: enabled)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Color.clear
                .frame(width: diameter * InstrumentMetrics.lensDiameterRatio,
                       height: diameter * InstrumentMetrics.lensDiameterRatio)
                .glassEffect(.clear, in: .circle)
                .scaleEffect(scale, anchor: .center)
                .opacity(reduceTransparency ? Metro.Opacity.lensCompositeReduceTransparency : InstrumentMetrics.lensOpacity)
                .frame(width: diameter, height: diameter)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if enabled { edgeReflection }
            readout.frame(width: diameter, height: diameter)
        }
        .frame(width: diameter, height: diameter)
        .transaction { $0.animation = nil }
    }

    private var shader: Shader {
        ShaderLibrary.instrumentLensOptics(
            .float2(Float(diameter / 2), Float(diameter / 2)),
            .float(Float(radius)),
            .float2(Float(enhanced.x), Float(enhanced.y)),
            .float(Float(LensRefraction.maximumShift(diameter: diameter))),
            .float(Float(LensRefraction.rimStart)),
            .float(Float(LensRefraction.curvature)),
            .float(Float(LensRefraction.maximumChannelSplit(diameter: diameter))),
            .float(Float(LensRefraction.chromaticInnerStart)),
            .float(Float(LensRefraction.chromaticPeakRadius))
        )
    }

    private var edgeReflection: some View {
        Canvas { context, _ in
            let center = CGPoint(x: diameter / 2, y: diameter / 2)
            let rim = radius * Metro.Optics.rimRadiusRatio
            let angle = Metro.Optics.rimAngleBase + enhanced.x * Metro.Optics.rimAngleTiltX
                + enhanced.y * Metro.Optics.rimAngleTiltY
            let start = angle - Metro.Optics.rimArcDegrees / 2
            let end = angle + Metro.Optics.rimArcDegrees / 2
            let arc = Path { path in
                path.addArc(center: center, radius: rim, startAngle: .degrees(start),
                            endAngle: .degrees(end), clockwise: false)
            }
            let a = CGPoint(x: center.x + rim * cos(start * .pi / 180),
                            y: center.y + rim * sin(start * .pi / 180))
            let b = CGPoint(x: center.x + rim * cos(end * .pi / 180),
                            y: center.y + rim * sin(end * .pi / 180))
            context.stroke(arc, with: .linearGradient(Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(Metro.Opacity.rimLightPeak), location: 0.5),
                .init(color: .clear, location: 1)
            ]), startPoint: a, endPoint: b), style: StrokeStyle(lineWidth: Metro.Stroke.glassRimLight, lineCap: .round))
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

