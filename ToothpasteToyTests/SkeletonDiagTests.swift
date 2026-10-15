// SkeletonDiagTests.swift — OWNER: integrator. Diagnostics printed to the test log (RHEO-DIAG lines); not judged.

import LabKitCore
import LabKitMPM
import Metal
import XCTest
import simd

@testable import ToothpasteToy

final class SkeletonDiagTests: XCTestCase {
  @MainActor func testPokeDiagnostics() throws {
    let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    let queue = try XCTUnwrap(device.makeCommandQueue())
    for fps in [120.0, 60.0, 15.0] {
      let model = ToothpasteModel(launch: ToothpasteLaunch.parse(["ToothpasteToy", "-noPersist", "-material", "oobleck", "-fakeTouch", "poke"]), device: device)
      model.canvasRegion = CGRect(x: 0, y: 59, width: 430, height: 612.3)
      let solver = try XCTUnwrap(model.resources.solver)
      let dt = 1 / fps
      let frames = Int(7 * fps)
      var next = 0.0
      for i in 0..<frames {
        model.advance(dt: dt)
        let cmd = try XCTUnwrap(queue.makeCommandBuffer())
        model.engine.encode(into: cmd)
        cmd.commit()
        cmd.waitUntilCompleted()
        let t = Double(i + 1) * dt
        if t >= next {
          next += 0.5
          let s = solver.stats
          let ys = solver.debugParticles().filter(\.enabled).map(\.position.y).sorted()
          let p95 = ys.isEmpty ? 0 : ys[Int(Double(ys.count - 1) * 0.95)]
          let f = model.latestFrame
          print(
            String(
              format: "RHEO-DIAG fps %.0f t %.1f sim %.2f lag %d sub %d J %.3f jam %.2f yld %.2f live %d p95y %.1f mm finger %@ ke %.2e nan %d ovf %d",
              fps, t, f.simTime, s.lagging ? 1 : 0, s.substeps, s.volumeRatio, s.jammedFraction, s.yieldedFraction,
              s.liveParticles, p95 * 1000, f.finger.map { String(format: "%.1f", $0.position.y * 1000) } ?? "-",
              s.kineticEnergy, s.nanCount, s.overflowCount))
        }
      }
    }
  }
}
