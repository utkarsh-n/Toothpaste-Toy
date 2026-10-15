// PerfLog.swift — OWNER: UI (was RHEO-FIX; Documentation/REDESIGN-OWNERSHIP.md).
//
// Unattended device measurement (SKELETON.md §5):
//   -perfLog     once a second, one CSV row in Documents/perf.csv (the previous run's file is kept as
//                perf-previous.csv) and one os_log line (subsystem com.utkarsh.toothpastetoy, category Perf): frames per second,
//                frame time (mean and worst), GPU time per solver frame (solver + render: one command buffer holds both),
//                CPU time of the simulation's advance, substeps (mean and most), iterations, lagging frames, the solver's
//                quality (cell size, substep cap), the thermal state, Low Power Mode, live particles, the material and
//                the auto-tour step. Documents is shared with the Files app (UIFileSharingEnabled).
//   -autoTour    cycles through every material (Fill, two pokes) and then every experiment, 6 s each, forever; each
//                step is logged (category Perf) and named in the CSV's `step` column. Listen stays at 0 (an
//                experiment that raises it would bring up the microphone prompt and stall the run) unless -fakeMic or
//                -startMic. The idle timer is off while it runs (the phone would lock and suspend the app).
//   -tourShots   with -autoTour: an in-app capture of the screen 5 s into each step, Documents/tour-NN-<step>.png (the
//                capture costs a frame or two: leave it off for timing runs).
//
// Read the log live: `log stream --predicate 'subsystem == "com.utkarsh.toothpastetoy" && category == "Perf"'` (Mac, the
// simulator) or Console.app with the phone attached; copy the CSV with Finder (the phone's Files tab) or
// `xcrun devicectl device copy from --device <id> --domain-type appDataContainer --domain-identifier com.utkarsh.toothpastetoy
// --source Documents/perf.csv --destination perf.csv`.

import Foundation
import LabKitCore
import LabKitMPM
import LabKitSensors
import OSLog
import UIKit

@MainActor final class ToothpastePerfSession {
  static let logger = Logger(subsystem: "com.utkarsh.toothpastetoy", category: "Perf")
  static let header =
    "t_s,fps,frame_ms_mean,frame_ms_max,gpu_ms_mean,gpu_ms_max,gpu_frames,cpu_advance_ms_mean,substeps_mean,substeps_max,"
    + "iterations,lagging_frames,cell_mm,max_substeps,thermal,low_power,particles,material,step"
  /// Seconds per auto-tour step.
  static let tourDwell = 6.0

  private let model: ToothpasteModel
  private var file: FileHandle?
  private var started = 0.0
  private var step = "-"
  private var tasks: [Task<Void, Never>] = []

  init(model: ToothpasteModel) {
    self.model = model
  }

  /// Starts what the launch arguments ask for (nothing without -perfLog or -autoTour).
  func start(perfLog: Bool = LaunchOptions.has("-perfLog"), autoTour: Bool = LaunchOptions.has("-autoTour"),
             shots: Bool = LaunchOptions.has("-tourShots")) {
    if perfLog {
      model.perf.enabled = true
      _ = model.perf.take()
      openFile()
      started = ProcessInfo.processInfo.systemUptime
      tasks.append(Task { @MainActor [weak self] in
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(1))
          self?.record()
        }
      })
      Self.logger.info("perfLog: recording to Documents/perf.csv")
    }
    if autoTour {
      // Unattended: the phone must not auto-lock (device run 1 stopped logging at 40 s when it did).
      UIApplication.shared.isIdleTimerDisabled = true
      tasks.append(Task { @MainActor [weak self] in await self?.tour(shots: shots) })
    }
  }

  func stop() {
    UIApplication.shared.isIdleTimerDisabled = false
    for t in tasks { t.cancel() }
    tasks.removeAll()
    try? file?.close()
    file = nil
    model.perf.enabled = false
  }

  // MARK: The log

  static var documents: URL { URL.documentsDirectory }

  private func openFile() {
    let fm = FileManager.default
    let url = Self.documents.appending(path: "perf.csv")
    let previous = Self.documents.appending(path: "perf-previous.csv")
    if fm.fileExists(atPath: url.path) {
      try? fm.removeItem(at: previous)
      try? fm.moveItem(at: url, to: previous)
    }
    let info = ProcessInfo.processInfo
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    let preamble = "# Toothpaste Toy -perfLog, \(Self.machine()), iOS \(info.operatingSystemVersionString), build \(build), "
      + "\(Date().formatted(.iso8601))\n\(Self.header)\n"
    fm.createFile(atPath: url.path, contents: Data(preamble.utf8))
    file = try? FileHandle(forWritingTo: url)
    _ = try? file?.seekToEnd()
  }

  private func record() {
    let s = model.perf.take()
    guard s.frames > 0 else { return }
    let q = model.resources.solver?.quality
    let conditions = DeviceConditions.current
    let row = Self.row(
      s, time: ProcessInfo.processInfo.systemUptime - started, iterations: q?.iterations ?? 0,
      cellMillimetres: (q?.cellSize ?? 0) * 1000, maxSubsteps: q?.maxSubsteps ?? 0, thermal: conditions.thermal.label,
      lowPower: conditions.lowPower, material: model.materialID, step: step)
    if let file { try? file.write(contentsOf: Data((row + "\n").utf8)) }
    Self.logger.info("\(row, privacy: .public)")
  }

  /// One CSV row (fields in `header` order).
  static func row(
    _ s: ToothpastePerfCounters.Sample, time: Double, iterations: Int, cellMillimetres: Double, maxSubsteps: Int,
    thermal: String, lowPower: Bool, material: String, step: String
  ) -> String {
    func f(_ v: Double, _ p: Int = 2) -> String { String(format: "%.\(p)f", v.isFinite ? v : 0) }
    return [
      f(time, 1), f(s.framesPerSecond, 1), f(s.frameMillisecondsMean), f(s.frameMillisecondsMax), f(s.gpuMillisecondsMean),
      f(s.gpuMillisecondsMax), "\(s.gpuFrames)", f(s.cpuAdvanceMillisecondsMean, 3), f(s.substepsMean, 1),
      "\(s.substepsMax)", "\(iterations)", "\(s.laggingFrames)", f(cellMillimetres), "\(maxSubsteps)", thermal,
      lowPower ? "1" : "0", "\(s.particles)", material, step.replacingOccurrences(of: ",", with: ";"),
    ].joined(separator: ",")
  }

  static func machine() -> String {
    var u = utsname()
    uname(&u)
    return withUnsafeBytes(of: &u.machine) { raw in
      String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
    }
  }

  // MARK: The auto tour

  /// Every material, then every experiment, `tourDwell` seconds each, forever.
  private func tour(shots: Bool) async {
    try? await Task.sleep(for: .seconds(2))
    var n = 0
    while !Task.isCancelled {
      for m in model.catalog.materials {
        n += 1
        begin("material \(m.id)", n)
        model.shelfMode = .fill
        model.perform(.fill(m.id))
        await dwell(n: n, name: "material-\(m.id)", shots: shots) { [model] in
          // Two pokes so the solver works for part of the step.
          let tank = model.engine.tankSize
          model.perform(.poke(SIMD2(tank.x * 0.35, tank.y * 0.2)))
        }
        if Task.isCancelled { return }
      }
      for e in model.catalog.experiments {
        n += 1
        begin("experiment \(e.id)", n)
        model.apply(e)
        // Unattended: an experiment that raises Listen (Oobleck monsters) would put up iOS's microphone prompt on a
        // phone that was never asked, and the app pauses behind it for the rest of the run. Listen stays off.
        if model.params[.listen] > MicGate.listenOn, !LaunchOptions.has("-fakeMic"), !LaunchOptions.has("-startMic") {
          model.params[.listen] = 0
          Self.logger.info("autoTour: Listen kept off (no microphone prompt during an unattended run)")
        }
        await dwell(n: n, name: "experiment-\(e.id)", shots: shots, during: nil)
        if Task.isCancelled { return }
      }
    }
  }

  private func begin(_ name: String, _ n: Int) {
    step = name
    Self.logger.info("autoTour step \(n, privacy: .public): \(name, privacy: .public)")
  }

  private func dwell(n: Int, name: String, shots: Bool, during: (@MainActor () -> Void)?) async {
    let start = ContinuousClock.now
    var poked = 0
    var shot = false
    while !Task.isCancelled {
      let d = ContinuousClock.now - start
      let t = Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18
      if let during, poked < 2, t >= 1.5 + 2 * Double(poked) {
        during()
        poked += 1
      }
      if t >= Self.tourDwell { break }
      if shots, !shot, t >= 5 {
        shot = true
        ToothpasteSnapshot.capture(name: String(format: "%02d-%@", n, name), directory: Self.documents, prefix: "tour-")
      }
      try? await Task.sleep(for: .milliseconds(250))
    }
  }
}
