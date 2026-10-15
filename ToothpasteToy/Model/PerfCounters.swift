// PerfCounters.swift — OWNER: integrator, frozen with the hub (was RHEO-FIX; Documentation/REDESIGN-OWNERSHIP.md).
//
// Per-frame performance counters for `-perfLog` (App/PerfLog.swift): the hub feeds every frame in `advance(dt:)`, and
// the recorder takes a one-second summary. Pure value type: no allocation per frame, nothing observed by SwiftUI.
//
// GPU time comes from `MPMStats.gpuMilliseconds`, the GPU time of the whole command buffer the solver was encoded into.
// Toothpaste Toy encodes the solver's substeps and every render pass (prepass, both scene passes, bloom, composite) into the
// frame's one command buffer, so it is solver + render together; LabKit offers no split. Each solver frame is counted
// once (by `MPMStats.frameIndex`; the stats arrive 1–2 frames late).

import Foundation
import LabKitMPM

struct ToothpastePerfCounters: Sendable {
  /// One second (or whatever span `take` covers) of frames.
  struct Sample: Sendable, Equatable {
    var seconds = 0.0
    var frames = 0
    var frameMillisecondsMean = 0.0
    var frameMillisecondsMax = 0.0
    var gpuMillisecondsMean = 0.0
    var gpuMillisecondsMax = 0.0
    var gpuFrames = 0
    var cpuAdvanceMillisecondsMean = 0.0
    var substepsMean = 0.0
    var substepsMax = 0
    var laggingFrames = 0
    var particles = 0

    var framesPerSecond: Double { seconds > 0 ? Double(frames) / seconds : 0 }
  }

  /// Off unless `-perfLog` (the hub then skips the clock reads too).
  var enabled = false
  private var current = Sample()
  private var lastStatsFrame = 0
  private var substepSum = 0
  private var statsFrames = 0
  private var cpuSum = 0.0

  mutating func frame(_ f: ToothpasteFrame, realDt: Double, cpuSeconds: Double) {
    guard enabled else { return }
    let dt = realDt.isFinite ? max(realDt, 0) : 0
    current.seconds += dt
    current.frames += 1
    current.frameMillisecondsMax = max(current.frameMillisecondsMax, dt * 1000)
    if cpuSeconds.isFinite { cpuSum += max(cpuSeconds, 0) }
    let s = f.stats
    if s.frameIndex != lastStatsFrame, s.frameIndex > 0 {
      lastStatsFrame = s.frameIndex
      if s.gpuMilliseconds.isFinite, s.gpuMilliseconds > 0 {
        current.gpuMillisecondsMean += s.gpuMilliseconds
        current.gpuMillisecondsMax = max(current.gpuMillisecondsMax, s.gpuMilliseconds)
        current.gpuFrames += 1
      }
      substepSum += s.substeps
      statsFrames += 1
      current.substepsMax = max(current.substepsMax, s.substeps)
      if s.lagging { current.laggingFrames += 1 }
    }
    current.particles = s.liveParticles
  }

  /// The summary since the last call, and a fresh start.
  mutating func take() -> Sample {
    var out = current
    if out.frames > 0 {
      out.frameMillisecondsMean = out.seconds / Double(out.frames) * 1000
      out.cpuAdvanceMillisecondsMean = cpuSum / Double(out.frames) * 1000
    }
    out.gpuMillisecondsMean = out.gpuFrames > 0 ? out.gpuMillisecondsMean / Double(out.gpuFrames) : 0
    out.substepsMean = statsFrames > 0 ? Double(substepSum) / Double(statsFrames) : 0
    current = Sample()
    current.particles = out.particles
    substepSum = 0
    statsFrames = 0
    cpuSum = 0
    return out
  }
}
