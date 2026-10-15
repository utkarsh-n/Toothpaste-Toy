// MetroTokens.swift — OWNER: UI (FOUNDATION wrote it, 13 October 2026).
//
// Metro Station design tokens, typed: every value of the skill's `assets/design-tokens.json` (edition 1.0, Metro
// Station build 14) plus the component recipes of `references/design-system-spec.md` §5–§15 that the toy needs, behind
// one namespace, `Metro`. The starter's `InstrumentPalette`, `InstrumentMetrics` and `LensRefraction` read their
// numbers from here, so this file is the app's single source of Metro values; do not scatter literals elsewhere.
//
// Colours: RGB doubles in sRGB are canonical (the JSON's hex strings are approximations). `Metro.RGB` gives a SwiftUI
// `Color`, the gamma-encoded `srgb` triple and the linear-light `linear` triple for Metal (the hologram passes).
// Points describe layout, not millimetres (spec §2). Values marked "current" reproduce Metro Station build 14;
// "recommended" are the spec's consolidation for new apps.

import CoreGraphics
import SwiftUI

enum Metro {
  /// Edition of the token manifest these values come from.
  static let edition = "1.0"
  static let sourceBuild = 14

  // MARK: Colour

  /// One canonical colour: sRGB components in 0…1.
  struct RGB: Sendable, Equatable {
    let red: Double
    let green: Double
    let blue: Double

    init(_ red: Double, _ green: Double, _ blue: Double) {
      self.red = red
      self.green = green
      self.blue = blue
    }

    /// SwiftUI colour (sRGB).
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
    /// Gamma-encoded sRGB, for shaders that work in display space.
    var srgb: SIMD3<Float> { SIMD3(Float(red), Float(green), Float(blue)) }
    /// Linear-light sRGB (IEC 61966-2-1 transfer), for lighting maths in Metal.
    var linear: SIMD3<Float> { SIMD3(Self.decode(red), Self.decode(green), Self.decode(blue)) }

    private static func decode(_ c: Double) -> Float {
      Float(c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4))
    }
  }

  /// `colors` of the manifest (spec §3). Semantic roles: cyan = continuous signal and active control, amber = events
  /// and emphasis, violet/magenta = a second, independent signal family.
  enum Colour {
    // Surfaces and text
    static let canvas = RGB(0.025, 0.042, 0.058)          // surface.canvas #060B0F
    static let content = RGB(0.045, 0.070, 0.087)         // surface.content #0B1216
    static let gaugeHousing = RGB(0.027, 0.041, 0.055)    // surface.gaugeHousing #070A0E
    static let metalLight = RGB(0.055, 0.073, 0.090)      // surface.metalLight #0E1317
    static let metalDark = RGB(0.021, 0.032, 0.042)       // surface.metalDark #05080B
    static let pillLight = RGB(0.055, 0.069, 0.095)       // surface.pillLight #0E1218
    static let pillDark = RGB(0.014, 0.022, 0.037)        // surface.pillDark #040609
    static let plot = RGB(0.022, 0.036, 0.047)            // surface.plot #06090C
    static let displayInk = RGB(0.91, 0.95, 0.97)         // text.display #E8F2F7
    static let secondaryInk = RGB(0.60, 0.69, 0.73)       // text.secondary #99B0BA
    // Accents
    static let actionCyan = RGB(0.34, 0.93, 0.96)         // accent.actionCyan #57EDF5
    static let actionAmber = RGB(1, 0.74, 0.37)           // accent.actionAmber #FFBD5E
    static let instrumentCyan = RGB(0.32, 0.91, 0.96)     // accent.instrumentCyan #52E8F5
    static let instrumentAmber = RGB(1, 0.72, 0.31)       // accent.instrumentAmber #FFB84F
    // Signal families
    static let wave = RGB(0.31, 0.86, 1)                  // signal.wavePrimary #4FDBFF
    static let waveDepth = RGB(0.21, 0.40, 1)             // signal.waveSecondary #3666FF
    static let spectrum = RGB(0.76, 0.57, 1)              // signal.spectrumPrimary #C291FF
    static let spectrumDepth = RGB(0.96, 0.36, 0.84)      // signal.spectrumSecondary #F55CD6
    static let carrier = RGB(1, 0.73, 0.34)               // signal.carrier #FFBA57
    // Crown metal
    static let crownBase = RGB(0.12, 0.15, 0.17)          // metal.crownBase #1F262B
    static let crownRimLight = RGB(0.49, 0.57, 0.61)      // metal.crownRimLight #7D919C
    static let crownRimDark = RGB(0.10, 0.13, 0.15)       // metal.crownRimDark #1A2126
    static let crownRimMid = RGB(0.32, 0.39, 0.43)        // metal.crownRimMid #52636E
    static let crownFaceLight = RGB(0.27, 0.33, 0.37)     // metal.crownFaceLight #45545E
    static let crownFaceDark = RGB(0.08, 0.11, 0.13)      // metal.crownFaceDark #141C21
  }

  // MARK: Spacing, radii, strokes, opacity

  /// `recommendedSpacing` (4-point family) and `componentSpacing` (current), pt.
  enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    /// Current in-component micro values (keep them inside their component recipes).
    static let micro: [CGFloat] = [3, 5, 6, 7, 10]
    static let screenInset: CGFloat = 12
    /// Subsidiary rows add this to the screen inset.
    static let subsidiaryInset: CGFloat = 10
    static let headerInset: CGFloat = 24
    static let headerTop: CGFloat = 10
    static let headerBottom: CGFloat = 12
    static let panelInset: CGFloat = 16
    static let mainStack: CGFloat = 12
    static let landscapeColumns: CGFloat = 24
    static let transportInset: CGFloat = 22
    static let transportTop: CGFloat = 10
    static let transportBottom: CGFloat = 12
  }

  /// `radii`, pt (pills are capsules; controls are circles or capsules).
  enum Radius {
    static let contentPanel: CGFloat = 22
    static let plot: CGFloat = 10
    static let beatTile: CGFloat = 8
  }

  /// `strokes`, pt.
  enum Stroke {
    static let panel: CGFloat = 1
    static let plot: CGFloat = 0.6
    static let grid: CGFloat = 0.5
    static let pill: CGFloat = 0.8
    static let housingRim: CGFloat = 1.4
    static let glassRimLight: CGFloat = 0.9
  }

  /// `opacity`.
  enum Opacity {
    static let panelFill = 0.85
    static let panelBorder = 0.09
    static let panelBorderIncreasedContrast = 0.20
    static let grid = 0.025
    static let environmentWash = 0.085
    /// The isolated lens's constant composite opacity (contract 2), and its Reduce Transparency value.
    static let lensComposite = 0.48
    static let lensCompositeReduceTransparency = 1.0
    static let rimLightPeak = 0.085
    static let crownGlassTint = 0.08
    static let pillPrimaryBorder = 0.36
    static let pillPrimaryBorderIncreasedContrast = 0.7
    static let pillSecondaryBorder = 0.38
    static let plotBorder = 0.075
    static let dialMetadataInk = 0.68
    /// Telemetry dividers (1 × 30 pt) and the pill outline's middle stop (spec §11–§12).
    static let divider = 0.10
    static let pillMiddleBorder = 0.10
    /// Supporting axes and captions (spec §3: white 0.74–0.75).
    static let supportingInk = 0.75
  }

  // MARK: Typography

  /// `typography` (spec §4). Sizes are base points; `scaledRelativeTo` ones go through `@ScaledMetric`.
  enum Typography {
    struct Style: Sendable, Equatable {
      let size: CGFloat
      let weight: Font.Weight
      let design: Font.Design
      let tracking: CGFloat
      let relativeTo: Font.TextStyle?
    }
    static let appTitle = Style(size: 27, weight: .semibold, design: .rounded, tracking: 0, relativeTo: .title)
    static let appTitleMinScale: CGFloat = 0.75
    static let appSubtitle = Style(size: 9, weight: .medium, design: .monospaced, tracking: 2.6, relativeTo: nil)
    /// The spec recommends a scalable 11–12 pt subtitle when it carries content.
    static let appSubtitleRecommended = Style(size: 11, weight: .medium, design: .monospaced, tracking: 2.6, relativeTo: .caption2)
    /// Hero numeral: `heroValueRatio` × the primary object's diameter, light rounded, monospaced digits.
    static let heroValueRatio: CGFloat = 0.23
    static let heroValueWeight: Font.Weight = .light
    static let heroValueMinScale: CGFloat = 0.7
    static let heroUnit = Style(size: 11, weight: .medium, design: .monospaced, tracking: 2.2, relativeTo: .caption2)
    static let stepperValue = Style(size: 18, weight: .medium, design: .rounded, tracking: 0, relativeTo: .body)
    static let stepperLabel = Style(size: 10, weight: .medium, design: .monospaced, tracking: 1.5, relativeTo: nil)
    static let stepperLabelRecommended = Style(size: 11, weight: .medium, design: .monospaced, tracking: 1.5, relativeTo: .caption2)
    static let pillTitle = Style(size: 10, weight: .semibold, design: .monospaced, tracking: 0, relativeTo: .caption2)
    static let pillAxis = Style(size: 9, weight: .medium, design: .monospaced, tracking: 0, relativeTo: .caption2)
    static let telemetryLabelTracking: CGFloat = 1.2
    /// Recommended minimum for reusable captions (smaller calibration stays supplementary).
    static let captionMinimum: CGFloat = 11
  }

  // MARK: Layout and the primary object

  /// `layout` (current), pt.
  enum Layout {
    static let portraitContentMax: CGFloat = 540
    static let clusterMax: CGFloat = 490
    static let gaugeMax: CGFloat = 360
    static let pillWidthCompact: CGFloat = 30
    static let pillWidthRegular: CGFloat = 36
    static let pillWidthBreakpoint: CGFloat = 350
    static let clusterGap: CGFloat = 6
    static let pillHeightMax: CGFloat = 218
    static let pillHeightRatio: CGFloat = 0.66
    static let controlRowMax: CGFloat = 380
    static let stepperMinHeight: CGFloat = 48
    static let stepperHorizontalPadding: CGFloat = 14
    static let secondaryTargetMin: CGFloat = 44
    static let crownDiameter: CGFloat = 62
    static let transportLabelMinHeight: CGFloat = 58
    static let transportRowSpacing: CGFloat = 12
    static let transportGlassSpacing: CGFloat = 14
    static let bottomContentReserve: CGFloat = 98
    static let landscapeInstrumentWidthRatio: CGFloat = 0.47
    static let beatTileHeight: CGFloat = 37
    static let beatTileRowGap: CGFloat = 7
    static let telemetryDivider = CGSize(width: 1, height: 30)
    static let scopeHeight: CGFloat = 140
    /// Crown caption rows (a scaled 14 pt base each, spec §10).
    static let crownCaptionRowHeight: CGFloat = 14
    /// Floating action label frames (spec §12): the leading side action, the trailing one.
    static let transportLeadingWidth: CGFloat = 62
    static let transportTrailingWidth: CGFloat = 54

    /// Spec §5 gauge-cluster calculation for an available width (pt): primary object diameter D, pill width and
    /// height, and the width the cluster really uses.
    static func cluster(availableWidth: CGFloat) -> (diameter: CGFloat, pillWidth: CGFloat, pillHeight: CGFloat, width: CGFloat) {
      let w = min(max(availableWidth, 0), clusterMax)
      let pill = w < pillWidthBreakpoint ? pillWidthCompact : pillWidthRegular
      let d = max(0, min(gaugeMax, w - 2 * pill - 2 * clusterGap))
      return (d, pill, min(pillHeightMax, pillHeightRatio * d), d + 2 * pill + 2 * clusterGap)
    }
  }

  /// `gauge`: proportions of the primary object (fractions of its diameter D).
  enum Gauge {
    static let calibrationRadiusRatio: CGFloat = 0.445
    static let metalInsetRatio: CGFloat = 0.038
    static let lensDiameterRatio: CGFloat = 0.76
    /// The lens radius before any bounce: 0.38 D (spec §6 light recipe).
    static let lensRadiusRatio: CGFloat = 0.38
    static let readoutYRatio: CGFloat = 0.52
    static let unitsYRatio: CGFloat = 0.665
    static let meaningYRatio: CGFloat = 0.745
    static let meaningYAccessibilityRatio: CGFloat = 0.79
    static let phaseYRatio: CGFloat = 0.835
    static let readoutWidthRatio: CGFloat = 0.64
    static let tickerPivotYRatio: CGFloat = 0.38
    static let tickerLengthRatio: CGFloat = 0.235
    static let tickerAmplitudeDegrees: Double = 26
    /// Lens radius bounce bounds the starter accepts (`InstrumentLensSurface`).
    static let radiusScaleRange: ClosedRange<Double> = 0.92...1.09
  }

  // MARK: Materials (spec §6)

  /// The environment recipe: canvas + localised cyan wash + faint grid.
  enum Surroundings {
    static let washRadii: ClosedRange<CGFloat> = 5...620
    static let gridSpacing: CGFloat = 28
  }

  /// The opaque metal recipe (housing, recessed face, crown).
  enum Housing {
    struct Shadow: Sendable, Equatable {
      let opacity: Double
      let radius: CGFloat
      let y: CGFloat
    }
    static let housingShadow = Shadow(opacity: 0.8, radius: 22, y: 16)
    /// Outer rim stops of the housing (white, black, white): opacities along the 1.4 pt rim.
    static let housingRimStops: [Double] = [0.36, 0.025, 0, 0.15]
    static let recessedFaceStrokeOpacity = 0.07
    static let recessedFaceStroke: CGFloat = 0.6
    static let crownShadowResting = Shadow(opacity: 0.75, radius: 6, y: 5)
    static let crownShadowPressed = Shadow(opacity: 0.75, radius: 3, y: 2)
    static let crownKnurls = 40
  }

  // MARK: Motion, optics, detents (spec §13–§15)

  /// `motion` (current tuning; cadences are requested rates).
  enum Motion {
    static let gaugeHz = 60.0
    static let telemetryHz = 30.0
    static let reduceMotionHz = 10.0
    static let gravitySampleHz = 30.0
    static let gravityGain = 1.7
    static let gravityLowPassAlpha = 0.18
    static let detentMaxHz = 20.0
    static let fineDetentDegrees = 8.0
    static let coarseDetentDegrees = 20.0
    static let reversalHysteresisRatio = 0.18
    /// The crown's centre exclusion radius, pt (no angle there).
    static let crownCentreExclusion: CGFloat = 7
    /// Pill envelope: support ≤ 200 ms (≤ 0.8 × the event interval), attack ≤ 20 ms (≤ support / 4).
    static let pillSupportMax = 0.2
    static let pillAttackMax = 0.02
  }

  /// `optics` (current artistic cue; `LensRefraction` reads these).
  enum Optics {
    static let shiftDiameterRatio = 0.025
    static let shiftCap = 9.5
    static let achromaticRimStart = 0.82
    static let curvature = 0.32
    static let totalChannelSplitAt322 = 1.0
    static let totalChannelSplitCap = 1.2
    static let channelOffsetFractionOfTotal = 0.5
    static let chromaticInnerStart = 0.52
    static let chromaticPeakRadius = 0.82
    static let rimRadiusRatio = 0.985
    static let rimArcDegrees = 76.0
    /// Rim arc centre: −90° + 70° × tilt.x + 20° × tilt.y (enhanced tilt).
    static let rimAngleBase = -90.0
    static let rimAngleTiltX = 70.0
    static let rimAngleTiltY = 20.0
  }

  /// `hapticDetents` (Core Haptics transient intensity and sharpness).
  enum Haptic {
    struct Detent: Sendable, Equatable {
      let intensity: Double
      let sharpness: Double
    }
    static let fineUp = Detent(intensity: 0.78, sharpness: 0.95)
    static let fineDown = Detent(intensity: 0.82, sharpness: 0.2)
    static let semanticUp = Detent(intensity: 1, sharpness: 0.6)
    static let semanticDown = Detent(intensity: 1, sharpness: 0.05)
  }

  // MARK: Component recipes (spec §10–§12)

  enum Pill {
    static let horizontalPadding: CGFloat = 5
    static let verticalPadding: CGFloat = 10
    static let gap: CGFloat = 3
  }

  enum Tile {
    static let activeFillOpacity = 0.08
    static let activeBorderOpacity = 0.35
    static let idleFillOpacity = 0.025
    static let idleBorderOpacity = 0.06
  }
}
