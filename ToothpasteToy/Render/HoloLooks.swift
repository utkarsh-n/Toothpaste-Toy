// HoloLooks.swift — OWNER: HOLO (Documentation/REDESIGN-OWNERSHIP.md §3).
//
// The quantum-hologram identity of every paste (REDESIGN.md §2), keyed by `MaterialID`, and the hologram's palette in
// linear light. Colours come from the Metro tokens (`Metro.Colour`, MetroTokens.swift): cyan = flow and shear (the
// continuous signal), amber = stress events and jamming, violet / magenta = structure and the second signal family. The
// app icon's aqua gel and hot-pink metal (REDESIGN.md §9) are echoed by toothpaste's body and its third stripe, which
// Metro's cyan and spectrum-depth magenta already carry. A visual style: the physics reads none of this.

import LabKitMPM
import simd

/// The hologram's colours, linear (Metro's canonical sRGB doubles decoded once).
enum HoloPalette {
  static let cyan = Metro.Colour.instrumentCyan.linear
  static let amber = Metro.Colour.instrumentAmber.linear
  static let violet = Metro.Colour.spectrum.linear
  static let magenta = Metro.Colour.spectrumDepth.linear
  static let blue = Metro.Colour.waveDepth.linear
  static let wave = Metro.Colour.wave.linear
  static let ink = Metro.Colour.displayInk.linear
  static let secondaryInk = Metro.Colour.secondaryInk.linear
  /// The icon's aqua gel (a greener cyan) and the white core of toothpaste's stripes.
  static let aqua = SIMD3<Float>(0.045, 0.86, 0.66)
  static let core = SIMD3<Float>(0.80, 0.95, 1.0)
  /// Toothpaste's third stripe: Metro violet three parts to one of spectrum-depth magenta, lifted to the others' light.
  static let stripeViolet = (violet * 0.75 + magenta * 0.25) * 1.35
  /// Thin-film fringes: cyan → blue → violet → magenta (Metro's two signal families around the hue circle).
  static let iris = (cyan, blue, violet, magenta)
  /// Housing metal (Metro metal recipe).
  static let housing = Metro.Colour.gaugeHousing.linear
  static let metalLight = Metro.Colour.metalLight.linear
  static let metalDark = Metro.Colour.metalDark.linear
  static let canvas = Metro.Colour.canvas.linear
}

/// Per-material hologram looks and stripe colours.
enum HoloLooks {
  /// Toothpaste's three stripes across the nozzle (REDESIGN.md §2): cyan · white core · violet (bands 1…3; more stripes
  /// repeat). Light colours: the white core is the brightest (a white only reads as light, not grey, when it outshines
  /// its saturated neighbours); violet leans a little toward Metro's magenta and is lifted to match cyan.
  static let stripeColours = (HoloPalette.cyan * 1.05, HoloPalette.core * 1.6, HoloPalette.stripeViolet)
  /// How brightly the bands glow in the body (share of their light colour) and the projector's scanlines.
  static let bandGain: Float = 0.5
  static let scanlinePeriod: Float = 0.00045
  static let scanlineDepth: Float = 0.2

  /// The look for a material id (`MaterialInfo.id`); unknown ids get a neutral cyan hologram.
  static func look(_ id: MaterialID) -> FluidHoloLook {
    switch id {
    case "toothpaste":
      // Aqua gel: a luminous translucent body, crisp cyan-white rim, fine fringes; the stripes carry the colour.
      return FluidHoloLook(
        body: SIMD3(0.020, 0.30, 0.25), translucency: 0.55, rim: SIMD3(0.55, 1.0, 0.95), rimWidth: 0.0006,
        fringePeriod: 0.00049, fringe: 0.55, fringeHue: 0.0, fringeDrift: 5, cloud: 0.45, cloudRadius: 0.12,
        cloudRate: 1.4, jamLight: 0.4, shearLight: 1)
    case "waterLike":
      // Barely there: a clear blue film, a bright edge and a sparkle of points.
      return FluidHoloLook(
        body: SIMD3(0.010, 0.10, 0.26), translucency: 0.92, rim: SIMD3(0.45, 0.85, 1.0), rimWidth: 0.0004,
        fringePeriod: 0.00072, fringe: 0.35, fringeHue: 0.15, fringeDrift: 8, cloud: 0.59, cloudRadius: 0.10,
        cloudRate: 2.6, shearLight: 1)
    case "honey":
      // Amber glass: deep where thick, gold rim, slow shimmer.
      return FluidHoloLook(
        body: SIMD3(0.24, 0.085, 0.006), translucency: 0.72, rim: SIMD3(1.0, 0.62, 0.18), rimWidth: 0.0007,
        fringePeriod: 0.00081, fringe: 0.45, fringeHue: 0.62, fringeDrift: 3, cloud: 0.31, cloudRadius: 0.12,
        cloudRate: 0.7, shearLight: 0.5)
    case "ketchup":
      // Crimson light, satin, a warmer magenta rim.
      return FluidHoloLook(
        body: SIMD3(0.24, 0.010, 0.030), translucency: 0.50, rim: SIMD3(1.0, 0.25, 0.42), rimWidth: 0.0006,
        fringePeriod: 0.00054, fringe: 0.45, fringeHue: 0.70, fringeDrift: 4, cloud: 0.36, cloudRadius: 0.12,
        cloudRate: 1.2, shearLight: 0.9)
    case "mayonnaise":
      // Cream-white, dense: holds peaks, a soft gold-white rim.
      return FluidHoloLook(
        body: SIMD3(0.20, 0.18, 0.11), translucency: 0.40, rim: SIMD3(1.0, 0.93, 0.72), rimWidth: 0.0006,
        fringePeriod: 0.00054, fringe: 0.45, fringeHue: 0.30, fringeDrift: 4, cloud: 0.42, cloudRadius: 0.13,
        cloudRate: 1.0, shearLight: 0.7)
    case "oobleck":
      // Milky-white quantum foam: a brighter, denser cloud; flashes amber where it jams.
      return FluidHoloLook(
        body: SIMD3(0.20, 0.22, 0.24), translucency: 0.45, rim: SIMD3(0.88, 0.95, 1.0), rimWidth: 0.0005,
        fringePeriod: 0.00054, fringe: 0.30, fringeHue: 0.05, fringeDrift: 6, cloud: 0.30, cloudRadius: 0.10,
        cloudRate: 2.2, jamLight: 1, foam: 1, shearLight: 0.8)
    case "slime":
      // Translucent borax blue, glossy rim, deep-blue fringes.
      return FluidHoloLook(
        body: SIMD3(0.012, 0.07, 0.40), translucency: 0.75, rim: SIMD3(0.35, 0.65, 1.0), rimWidth: 0.0006,
        fringePeriod: 0.00063, fringe: 0.55, fringeHue: 0.25, fringeDrift: 6, cloud: 0.39, cloudRadius: 0.12,
        cloudRate: 1.1, shearLight: 0.9)
    case "sillyPutty":
      // Pastel violet: structure (violet) shows strongly.
      return FluidHoloLook(
        body: SIMD3(0.24, 0.09, 0.30), translucency: 0.40, rim: SIMD3(0.85, 0.55, 1.0), rimWidth: 0.0007,
        fringePeriod: 0.00059, fringe: 0.50, fringeHue: 0.50, fringeDrift: 4, cloud: 0.34, cloudRadius: 0.12,
        cloudRate: 0.9, shearLight: 0.7)
    case "yogurt":
      // Soft white, quiet fringes.
      return FluidHoloLook(
        body: SIMD3(0.17, 0.18, 0.19), translucency: 0.45, rim: SIMD3(0.90, 0.96, 1.0), rimWidth: 0.0006,
        fringePeriod: 0.00063, fringe: 0.25, fringeHue: 0.10, fringeDrift: 4, cloud: 0.36, cloudRadius: 0.12,
        cloudRate: 1.0, shearLight: 0.7)
    case "quicksand":
      // Sandy gold: the cloud is the grain (bigger, brighter points), dry and pale where it locks.
      return FluidHoloLook(
        body: SIMD3(0.16, 0.10, 0.035), translucency: 0.50, rim: SIMD3(1.0, 0.78, 0.45), rimWidth: 0.0005,
        fringePeriod: 0.00045, fringe: 0.20, fringeHue: 0.60, fringeDrift: 3, cloud: 0.55, cloudRadius: 0.15,
        cloudRate: 0.6, jamLight: 0.6, shearLight: 0.8)
    case "mrFluid":
      // Metallic violet with magnetic field lines; a silver-violet rim.
      return FluidHoloLook(
        body: SIMD3(0.07, 0.035, 0.16), translucency: 0.30, rim: SIMD3(0.78, 0.70, 1.0), rimWidth: 0.0006,
        fringePeriod: 0.00040, fringe: 0.60, fringeHue: 0.55, fringeDrift: 7, cloud: 0.28, cloudRadius: 0.11,
        cloudRate: 1.6, fieldLines: 1, shearLight: 0.6)
    case "paint":
      // Phosphor green (the icon's matrix mesh), a glossy rim.
      return FluidHoloLook(
        body: SIMD3(0.020, 0.28, 0.07), translucency: 0.40, rim: SIMD3(0.45, 1.0, 0.60), rimWidth: 0.0006,
        fringePeriod: 0.00054, fringe: 0.40, fringeHue: 0.0, fringeDrift: 5, cloud: 0.34, cloudRadius: 0.12,
        cloudRate: 1.2, shearLight: 0.8)
    case "lava":
      // Dark crust lit from within: the temperature glow is the light; amber-white where molten.
      return FluidHoloLook(
        body: SIMD3(0.05, 0.010, 0.004), translucency: 0.30, rim: SIMD3(1.0, 0.50, 0.15), rimWidth: 0.0006,
        fringePeriod: 0.00063, fringe: 0.15, fringeHue: 0.65, fringeDrift: 2, cloud: 0.25, cloudRadius: 0.12,
        cloudRate: 0.5, heatGlow: 1, shearLight: 0.3)
    default:
      return .standard
    }
  }
}
