// Scenes.swift — OWNER: PLAY (REDESIGN.md §5.1; Documentation/REDESIGN-OWNERSHIP.md).
//
// What a fresh chamber holds. Toothpaste (the hero) opens on a short striped ribbon already folded into a small stack
// on the floor, with a peak where it was torn off, under the parked nozzle: squeeze and the new ribbon lands on it.
// The other pastes keep the pool a Fill always gave them (oobleck needs depth to jam under a punch, MR fluid to heap
// over the magnet), so their experiments and tests are unchanged.
//
// The ribbon is filled as quadrilaterals along its centreline, each dyed across its own width (`MPMSolver.fill(polygon:
// …stripes:across:)` with `across` = the centreline's left normal, the emitter's convention), so the three stripes follow
// the folds: band 1 on the ribbon's right-hand side all the way along, as if the nozzle had laid it.

import CoreGraphics
import Foundation
import simd
import LabKitMPM

enum ToothpasteScenes {
  /// How a fresh chamber of `id` starts.
  enum Start: Equatable {
    /// A pool `fraction` of the tank deep (the Rheo fill).
    case pool(fraction: Double)
    /// The folded starting ribbon.
    case coil
  }

  static func start(for id: MaterialID) -> Start {
    id == "toothpaste" ? .coil : .pool(fraction: 0.45)
  }

  /// The starting coil's ribbon: width (as laid, a little flatter than the 8 mm bore), fold length and layers.
  static let ribbonWidth = 0.0075
  static let foldLength = 0.018
  static let layers = 3

  /// The ribbon's centreline: back and forth in `layers` folds stacked on the floor, centred on `centreX`, ending in a
  /// short upward tail at the middle of the top fold (where the tube tore it off).
  static func coilPath(centreX: Double, width w: Double = ribbonWidth, fold: Double = foldLength, layers: Int = layers)
    -> [SIMD2<Double>]
  {
    var path: [SIMD2<Double>] = []
    let left = centreX - fold / 2, right = centreX + fold / 2
    let arcSteps = 10
    for k in 0..<layers {
      let y = w / 2 + Double(k) * w
      let rightward = k % 2 == 0
      let last = k == layers - 1
      let from = rightward ? left : right
      let to = last ? centreX : (rightward ? right : left)
      if path.isEmpty { path.append(SIMD2(from, y)) }
      path.append(SIMD2(to, y))
      if last { break }
      // A U-turn up to the next fold: a half circle of radius w/2 around the fold's end.
      let c = SIMD2(to, y + w / 2)
      for i in 1...arcSteps {
        let a = -Double.pi / 2 + Double.pi * Double(i) / Double(arcSteps)
        let p = SIMD2(c.x + (rightward ? 1 : -1) * w / 2 * cos(a), c.y + w / 2 * sin(a))
        path.append(p)
      }
    }
    // The tail: a quarter turn up out of the top fold, then a short stub.
    let top = path[path.count - 1]
    let dir: Double = layers % 2 == 1 ? 1 : -1   // the top fold runs rightward when the layer count is odd
    let c = SIMD2(top.x, top.y + w / 2)
    for i in 1...6 {
      let a = -Double.pi / 2 + Double.pi / 2 * Double(i) / 6
      path.append(SIMD2(c.x + dir * w / 2 * cos(a), c.y + w / 2 * sin(a)))
    }
    let end = path[path.count - 1]
    path.append(end + SIMD2(0, 0.6 * w))
    return path
  }

  /// Quadrilaterals along `path` (width `w`, mitred at the joints) with the left normal of each segment as `across`.
  /// `taper`: the last `taper` metres narrow to a point (a torn-off peak).
  static func ribbon(_ path: [SIMD2<Double>], width w: Double, taper: Double = 0)
    -> [(polygon: [SIMD2<Double>], across: SIMD2<Double>)]
  {
    guard path.count >= 2 else { return [] }
    func normal(_ d: SIMD2<Double>) -> SIMD2<Double> {
      let l = simd_length(d)
      return l > 1e-12 ? SIMD2(-d.y, d.x) / l : SIMD2(0, 1)
    }
    var lengths = [0.0]
    for i in 1..<path.count { lengths.append(lengths[i - 1] + simd_distance(path[i], path[i - 1])) }
    let total = lengths.last ?? 0
    var offsets: [SIMD2<Double>] = []
    for i in 0..<path.count {
      let a = i > 0 ? normal(path[i] - path[i - 1]) : nil
      let b = i + 1 < path.count ? normal(path[i + 1] - path[i]) : nil
      var n = (a ?? b!) + (b ?? a!)
      n = simd_length(n) > 1e-9 ? simd_normalize(n) : (a ?? b!)
      // Mitre: keep the offset's projection on each segment normal at w/2 (bounded at sharp joints).
      let cosHalf = max(simd_dot(n, a ?? n), 0.5)
      var half = w / 2 / cosHalf
      if taper > 0 { half *= min(max((total - lengths[i]) / taper, 0), 1) }
      offsets.append(n * half)
    }
    var out: [(polygon: [SIMD2<Double>], across: SIMD2<Double>)] = []
    for i in 0..<(path.count - 1) {
      let n = normal(path[i + 1] - path[i])
      let quad = [path[i] - offsets[i], path[i + 1] - offsets[i + 1], path[i + 1] + offsets[i + 1], path[i] + offsets[i]]
      out.append((quad, n))
    }
    return out
  }
}
