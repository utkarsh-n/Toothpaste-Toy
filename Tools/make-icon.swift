// make-icon.swift — OWNER: integrator (the user's brief, 13 Oct 2026: "aqua gel with hot pink metallic streak on a matrix
// glowing mesh").
//
// Draws Toothpaste Toy's 1024 × 1024 app icon, pixel by pixel, as a small ray-free "shader":
//   • a Matrix-green glowing wire mesh: a perspective floor grid that ripples gently towards a horizon, with faint
//     falling code-rain columns above it;
//   • a dollop of aqua gel toothpaste sitting on the mesh: a three-tier swirl shaded as a translucent gel (pillow
//     profile → normals, refraction of the mesh behind it, Beer–Lambert aqua absorption, light scattered under the
//     surface, a sharp key highlight and a cool Fresnel rim);
//   • a hot-pink metallic streak swirling through the gel (raised, anisotropic metal sheen, dark magenta in shadow);
//   • the gel's aqua and pink glow bleeding onto the mesh around it.
// 2 × 2 supersampling; Display P3; no alpha (App Store rule).
//
//   cd "$TMPDIR" && cp ".../Toothpaste Toy/Tools/make-icon.swift" . && swiftc -O make-icon.swift -o make-icon && ./make-icon icon.png
//   cp "$TMPDIR/icon.png" ".../Toothpaste Toy/ToothpasteToy/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
//
// Optional second argument: a size in pixels for quick previews (default 1024). Run it outside iCloud.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Small maths

struct V2 {
  var x, y: Double
  init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
  static func + (a: V2, b: V2) -> V2 { V2(a.x + b.x, a.y + b.y) }
  static func - (a: V2, b: V2) -> V2 { V2(a.x - b.x, a.y - b.y) }
  static func * (a: V2, s: Double) -> V2 { V2(a.x * s, a.y * s) }
  func dot(_ b: V2) -> Double { x * b.x + y * b.y }
  var length: Double { (x * x + y * y).squareRoot() }
}

struct V3 {
  var x, y, z: Double
  init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
  static func + (a: V3, b: V3) -> V3 { V3(a.x + b.x, a.y + b.y, a.z + b.z) }
  static func - (a: V3, b: V3) -> V3 { V3(a.x - b.x, a.y - b.y, a.z - b.z) }
  static func * (a: V3, s: Double) -> V3 { V3(a.x * s, a.y * s, a.z * s) }
  static func * (a: V3, b: V3) -> V3 { V3(a.x * b.x, a.y * b.y, a.z * b.z) }
  func dot(_ b: V3) -> Double { x * b.x + y * b.y + z * b.z }
  var normalised: V3 { let l = max((x * x + y * y + z * z).squareRoot(), 1e-12); return V3(x / l, y / l, z / l) }
}

@inline(__always) func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
@inline(__always) func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
@inline(__always) func mix(_ a: V3, _ b: V3, _ t: Double) -> V3 { a + (b - a) * t }
@inline(__always) func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
  let t = clamp01((x - e0) / (e1 - e0)); return t * t * (3 - 2 * t)
}
/// Polynomial smooth minimum (Inigo Quilez): blends two signed distances with radius k.
@inline(__always) func smin(_ a: Double, _ b: Double, _ k: Double) -> Double {
  let h = clamp01(0.5 + 0.5 * (b - a) / k); return mix(b, a, h) - k * h * (1 - h)
}
@inline(__always) func hash(_ x: Double) -> Double { let s = sin(x * 127.1) * 43758.5453; return s - floor(s) }

// MARK: - Palette (Display P3, linear-ish working values)

let matrixGreen = V3(0.10, 1.00, 0.42)
let matrixCore = V3(0.75, 1.00, 0.82)
let aquaDeep = V3(0.00, 0.33, 0.40)
let aqua = V3(0.10, 0.90, 0.86)
let aquaBright = V3(0.62, 1.00, 0.97)
let pinkHot = V3(1.00, 0.16, 0.62)
let pinkDark = V3(0.42, 0.02, 0.24)
let pinkSheen = V3(1.00, 0.78, 0.92)

// Coordinates: u, v in [-1, 1], y up, icon centre at the origin.

// MARK: - The matrix mesh (background)

let horizon = 0.06          // screen y of the horizon line
let camHeight = 0.55        // world height of the eye above the floor

/// World floor coordinates for a screen point below the horizon.
func floorPoint(_ u: Double, _ v: Double) -> (x: Double, z: Double)? {
  let dy = horizon - v
  guard dy > 1e-4 else { return nil }
  let z = camHeight / dy
  return (u * z, z)
}

/// Glow of one family of grid lines at coordinate c with spacing s, given the coordinate's screen derivative.
func gridLine(_ c: Double, spacing s: Double, derivative d: Double) -> Double {
  let f = c / s
  let dist = abs(f - (f).rounded()) * s           // world distance to the nearest line
  let px = dist / max(d, 1e-9)                    // in pixels
  let core = exp(-px * px / 1.1)
  let halo = exp(-px / 6.0) * 0.22
  return core + halo
}

func meshColour(_ u: Double, _ v: Double, pixel: Double) -> V3 {
  // Base: near-black with a faint green-blue haze, deepest at the corners.
  let r2 = u * u + (v + 0.1) * (v + 0.1)
  var col = mix(V3(0.004, 0.018, 0.012), V3(0.0, 0.002, 0.003), clamp01(r2 * 0.6))
  // Horizon glow band.
  col = col + matrixGreen * (0.07 * exp(-abs(v - horizon) * 18))

  if let p = floorPoint(u, v) {
    // Gentle ripple of the mesh, so it reads as a glowing wire surface rather than flat tiles.
    let rippleX = p.x + 0.05 * sin(p.z * 2.1)
    let rippleZ = p.z + 0.04 * sin(p.x * 3.0 + p.z * 0.7)
    // Screen derivatives by finite difference (one pixel).
    let pu = floorPoint(u + pixel, v), pv = floorPoint(u, v - pixel)
    let dx = max(abs((pu?.x ?? p.x) - p.x), abs((pv?.x ?? p.x) - p.x)) + 1e-6
    let dz = max(abs((pu?.z ?? p.z) - p.z), abs((pv?.z ?? p.z) - p.z)) + 1e-6
    let spacing = 0.32
    let lines = gridLine(rippleX, spacing: spacing, derivative: dx) + gridLine(rippleZ, spacing: spacing, derivative: dz)
    // Nodes at intersections sparkle.
    let fx = rippleX / spacing, fz = rippleZ / spacing
    let node = exp(-(pow((fx - fx.rounded()) * spacing / dx, 2) + pow((fz - fz.rounded()) * spacing / dz, 2)) / 3.0)
    let fade = exp(-(p.z - camHeight / (horizon + 1)) * 0.11)    // far lines fade into the haze
    let near = smoothstep(0.0, 0.05, horizon - v)
    let glow = min(lines, 2.2) * fade * near
    col = col + matrixGreen * (glow * 0.62) + matrixCore * (pow(min(lines, 1.6), 3) * 0.10 * fade + node * 0.55 * fade * near)
  } else {
    // Above the horizon: falling code rain, faint columns of short glowing dashes with fading tails.
    let columns = 34.0
    let colIndex = ((u + 1) * 0.5 * columns).rounded(.down)
    let cx = (colIndex + 0.5) / columns * 2 - 1
    let px = abs(u - cx) / pixel
    if px < 6 {
      let speed = 0.6 + hash(colIndex) * 1.4
      let phase = hash(colIndex + 31.7) * 10
      let headY = 1.05 - fmod(phase * speed, 1.6)
      let along = (headY - v)                          // > 0 below the head (the tail)
      let tail = along > 0 ? exp(-along * 3.2) : exp(along * 60)
      let dash = 0.55 + 0.45 * smoothstep(0.35, 0.65, abs(sin(v * 140 + colIndex * 3.1)))
      let w = exp(-px * px / 2.2)
      let strength = (0.20 + 0.55 * hash(colIndex + 7.3)) * smoothstep(horizon, horizon + 0.25, v)
      col = col + matrixGreen * (w * tail * dash * strength) + matrixCore * (w * exp(-abs(along) * 90) * strength * 0.9)
    }
  }
  return col
}

// MARK: - The gel ribbon (a squeezed tube of gel with a curl, distance to a centre curve)

/// Dense samples of the ribbon's centre line: a gentle S-wave squeezed left to right, ending in a curl that rises.
let spine: [V2] = {
  // One bold S-swoosh from lower left to upper right, its tip lifting like freshly squeezed gel.
  var pts: [V2] = []
  let n = 500
  for i in 0...n {
    let t = Double(i) / Double(n)
    let x = -0.74 + t * 1.42
    let y = -0.40 + t * 0.50 + 0.17 * sin(t * .pi * 1.9 + 0.25) + 0.10 * pow(t, 6)
    pts.append(V2(x, y))
  }
  return pts
}()

/// Tube radius along the ribbon: a rounded squeeze start, a fat body, a soft tapering tip.
@inline(__always) func ribbonRadius(_ s: Double) -> Double {
  let start = smoothstep(0.0, 0.10, s)
  let end = 1 - smoothstep(0.70, 1.0, s) * 0.62
  return 0.165 * (0.45 + 0.55 * start) * end
}

struct RibbonHit { var d: Double; var s: Double; var tangent: V2; var side: Double; var inside: Bool; var radius: Double }

/// Nearest point on the spine (the swoosh never overlaps itself).
func ribbon(_ p: V2) -> RibbonHit {
  var best = RibbonHit(d: 1e9, s: 0, tangent: V2(1, 0), side: 1, inside: false, radius: 0.1)
  let n = spine.count - 1
  var i = 0
  while i < n {
    let a = spine[i], b = spine[i + 1]
    let ab = b - a, ap = p - a
    let t = clamp01(ap.dot(ab) / max(ab.dot(ab), 1e-12))
    let q = a + ab * t
    let d = (p - q).length
    let s = (Double(i) + t) / Double(n)
    let r = ribbonRadius(s)
    let inside = d < r
    if d < best.d {
      let tan = ab * (1 / max(ab.length, 1e-12))
      let cross = tan.x * (p.y - q.y) - tan.y * (p.x - q.x)
      best = RibbonHit(d: d, s: s, tangent: tan, side: cross >= 0 ? 1 : -1, inside: inside, radius: r)
    }
    i += 1
  }
  return best
}

// MARK: - Shading

let keyLight = V3(-0.45, 0.72, 0.53).normalised
let fillLight = V3(0.70, -0.20, 0.68).normalised
let viewDir = V3(0, 0, 1)

/// A cheap environment for the metal: the matrix mesh below the horizon, dark sky above, by reflected direction.
func environment(_ r: V3) -> V3 {
  if r.y < -0.05 {
    let k = clamp01(-r.y)
    let lines = pow(abs(sin(r.x * 22)), 40) + pow(abs(sin((1 / max(k, 0.05)) * 3.0)), 40)
    return V3(0.01, 0.05, 0.03) + matrixGreen * (lines * 0.35 * k)
  }
  return V3(0.02, 0.03, 0.04) + V3(1, 0.9, 0.95) * pow(clamp01(r.dot(keyLight)), 30) * 1.4
}

func shade(_ u: Double, _ v: Double, pixel: Double) -> V3 {
  let p = V2(u, v)
  let hit = ribbon(p)
  let sdf = hit.d - hit.radius
  var background = meshColour(u, v, pixel: pixel)

  // The gel lights the mesh around and below it: aqua bloom, strongest straight down onto the floor.
  let bloom = exp(-max(sdf, 0) * 9.0)
  let below = exp(-max(sdf, 0) * 4.0) * smoothstep(0.1, -0.5, v)
  background = background + aqua * (0.22 * bloom + 0.14 * below) + pinkHot * (0.05 * bloom)

  let coverage = clamp01(0.5 - sdf / (pixel * 1.2))
  if coverage <= 0 { return background }

  // Tube cross-section: a = signed position across the tube in [-1, 1]; the surface normal of a cylinder.
  let a = min(hit.d / max(hit.radius, 1e-9), 1) * hit.side
  let side = V2(-hit.tangent.y, hit.tangent.x)
  let nz = (max(1 - a * a, 0)).squareRoot()
  // Squash the cross-section a little (a squeezed ribbon is flatter than a cylinder).
  let n = V3(side.x * a, side.y * a, nz * 1.25).normalised
  let thickness = nz                                 // 0 at the silhouette, 1 down the middle

  // --- Gel body ---
  let bend = 0.06 + 0.12 * thickness
  let behind = meshColour(u - n.x * bend, v - n.y * bend, pixel: pixel * 7)
  let absorb = V3(3.0, 0.22, 0.34) * (0.5 + thickness * 1.3)
  let transmit = V3(exp(-absorb.x), exp(-absorb.y), exp(-absorb.z))
  var gel = behind * transmit * 0.9
  gel = gel + mix(aquaDeep, aqua, 0.25 + 0.70 * thickness) * (0.55 + 0.35 * max(n.dot(fillLight), 0))
  gel = gel + aquaBright * (0.10 * pow(thickness, 4))     // bright core where the gel is deepest
  let fresnel = pow(1 - max(n.dot(viewDir), 0), 3.2)
  gel = gel + aquaBright * (fresnel * 1.05)
  let hk = (keyLight + viewDir).normalised
  let spec = pow(max(n.dot(hk), 0), 220) * 2.2 + pow(max(n.dot(hk), 0), 24) * 0.20
  gel = gel + V3(1, 1, 1) * spec
  // A long glossy highlight down the tube (anisotropic, like light on a squeezed gel ribbon).
  let lineHighlight = exp(-pow(a + 0.62, 2) / 0.006) * smoothstep(0.05, 0.2, hit.s) * (1 - smoothstep(0.85, 1.0, hit.s))
  gel = gel + V3(0.85, 1.0, 1.0) * (lineHighlight * 0.9)

  // --- Hot-pink metallic stripe spiralling round the tube ---
  // Position of the stripe across the tube follows a helix; the phase tells front (cos > 0) from back.
  let stripeA = 0.10 + 0.38 * sin(hit.s * .pi * 1.3 + 0.4)       // the streak drifts across the tube: a slow twist
  let front = true
  let stripeHalf = 0.30 * (0.55 + 0.45 * smoothstep(0.0, 0.18, hit.s)) * (1 - 0.45 * smoothstep(0.75, 1.0, hit.s))
  let distA = abs(a - stripeA)
  let stripeMask = clamp01(0.5 - (distA - stripeHalf) * hit.radius / (pixel * 1.2))
  var col = gel
  if stripeMask > 0 {
    if front {
      // Raised metal band: its own normal leans across the band.
      let across = (a - stripeA) / max(stripeHalf, 1e-6)
      let bandN = V3(n.x + side.x * across * 0.55, n.y + side.y * across * 0.55, n.z).normalised
      let r = (viewDir * -1) + bandN * (2 * bandN.dot(viewDir))     // reflected view ray
      let env = environment(V3(r.x, r.y, r.z))
      let ndl = max(bandN.dot(keyLight), 0)
      let hk2 = pow(max(bandN.dot(hk), 0), 90) * 2.0 + pow(max(bandN.dot(hk), 0), 14) * 0.35
      // Metallic: tinted reflection + coloured specular (no white diffuse), dark magenta in shadow.
      var metal = mix(pinkDark, pinkHot, 0.20 + 0.80 * ndl) * 0.85
      metal = metal + env * pinkHot * 1.6
      metal = metal + mix(pinkHot, pinkSheen, 0.6) * hk2
      // Brushed micro-glints running along the stripe.
      // Brushed metal: fine streaks running ALONG the stripe (vary across it), and a hot specular ridge near its top edge.
      let brush = 0.5 + 0.5 * sin(across * 38 + sin(hit.s * 9) * 2)
      metal = metal * (0.88 + 0.24 * brush)
      let ridge = exp(-pow(across + 0.45, 2) / 0.02) * (0.35 + 0.65 * ndl)
      metal = metal + pinkSheen * (ridge * 1.25)
      let underside = smoothstep(0.2, 1.0, across) * 0.45
      metal = metal * (1 - underside)
      // A thin bright edge where the band meets the gel.
      let edge = smoothstep(0.65, 1.0, abs(across)) * 0.35
      metal = metal + aquaBright * edge
      col = mix(col, metal, stripeMask * 0.98)
    } else {
      // The back half of the stripe, seen through the gel: dimmer, aqua-tinted, slightly blurred by refraction.
      let back = mix(pinkHot * 0.55, pinkHot * V3(0.6, 0.9, 0.9), 0.4) * (0.55 + 0.45 * thickness)
      col = mix(col, col * 0.55 + back * 0.60, stripeMask * 0.85)
    }
  }
  // The gel's skin over everything: rim and glints stay on top of the stripe.
  col = col + aquaBright * (fresnel * 0.25) + V3(1, 1, 1) * (pow(max(n.dot(hk), 0), 400) * 1.2)

  return mix(background, col, coverage)
}

// MARK: - Render

func render(size: Int) -> CGImage {
  var buffer = [UInt8](repeating: 255, count: size * size * 4)
  let pixel = 2.0 / Double(size)
  let samples: [(Double, Double)] = [(-0.25, -0.25), (0.25, -0.25), (-0.25, 0.25), (0.25, 0.25)]
  DispatchQueue.concurrentPerform(iterations: size) { row in
    var line = [UInt8](repeating: 255, count: size * 4)
    for col in 0..<size {
      var acc = V3(0, 0, 0)
      for s in samples {
        let u = (Double(col) + 0.5 + s.0) * pixel - 1
        let v = 1 - (Double(row) + 0.5 + s.1) * pixel
        acc = acc + shade(u, v, pixel: pixel)
      }
      acc = acc * 0.25
      // Vignette and a soft filmic curve so highlights roll off instead of clipping.
      let u0 = (Double(col) + 0.5) * pixel - 1, v0 = 1 - (Double(row) + 0.5) * pixel
      let vig = 1 - 0.30 * clamp01((u0 * u0 + v0 * v0) * 0.5)
      let mapped = V3(acc.x * vig, acc.y * vig, acc.z * vig)
      func tone(_ x: Double) -> Double { let y = 1 - exp(-max(x, 0) * 1.25); return pow(clamp01(y), 1 / 1.25) }
      let i = col * 4
      line[i] = UInt8(clamp01(tone(mapped.x)) * 255 + 0.5)
      line[i + 1] = UInt8(clamp01(tone(mapped.y)) * 255 + 0.5)
      line[i + 2] = UInt8(clamp01(tone(mapped.z)) * 255 + 0.5)
      line[i + 3] = 255
    }
    line.withUnsafeBufferPointer { src in
      buffer.withUnsafeMutableBufferPointer { dst in
        _ = memcpy(dst.baseAddress! + row * size * 4, src.baseAddress!, size * 4)
      }
    }
  }
  let space = CGColorSpace(name: CGColorSpace.displayP3)!
  let provider = CGDataProvider(data: Data(buffer) as CFData)!
  return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4, space: space,
                 bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                 provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "icon.png"
let size = args.count > 2 ? Int(args[2]) ?? 1024 : 1024
let image = render(size: size)
let url = URL(fileURLWithPath: outPath) as CFURL
let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(outPath)") }
print("wrote \(outPath) (\(size) × \(size))")
