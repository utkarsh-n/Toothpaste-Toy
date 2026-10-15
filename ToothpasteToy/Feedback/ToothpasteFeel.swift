// ToothpasteFeel.swift — OWNER: PLAY (was FEEL; Documentation/REDESIGN-OWNERSHIP.md).
//
// `ToothpasteFeeling`: applies the feel map (FeelMap.swift) every frame to LabKit's `LabFeedback` — the causal haptic hum,
// transients, the gloop voice (GloopKernel.swift) and its bed gate — and runs the microphone's lifecycle:
// just-in-time permission on the first raise of Listen, release when Listen returns to 0 (Microphone.swift), the
// self-trigger window after every sound or haptic Toothpaste Toy makes itself, iOS 27 interruptions (`AudioRoute`), route
// changes (a headset's microphone needs a new tap) and media-services resets.
//
// What LabKit already does and this file relies on: Strength, the Haptics and "Feel the fluid" toggles, the shared
// transient admission clock, the hum's causal 8 s idle, 0.25 s lag, ≤ 40 sends per second and its stop rules
// (HapticEngine); the persisted Sound toggle and `.ambient` (follows the ring/silent switch) (LabFeedback). The voice's
// gain is Toothpaste Toy's own (`ToothpasteBedMix`): LabFeedback's bed gain would duck or silence the one-shot gloop events with the
// continuous layers, so the × 0.3 duck with the mic live and the silence in Low Power Mode or while frozen are applied
// to the continuous layers only, and squelches, cracks and splashes keep their level, like cues.
//
// Microphone: never touched at launch (the hub builds `MicListener` but nothing starts it) unless `-startMic`; the
// first raise of Listen above 0 starts it, which asks iOS for permission just then. `-fakeMicDenied` (DEBUG) makes the
// listener report a refusal without asking, for the UI's denied flow in tests.
//
// STATUS: haptics cannot be felt in the Simulator (`supportsHaptics == false`); every constant is a proposal to tune
// on the iPhone 15 Pro Max. The map, the voice and the microphone gate are tested headlessly in FeelTests.

import AVFoundation
import Foundation
import simd
import LabKitCore
import LabKitFeedback
import LabKitSensors

@MainActor final class ToothpasteFeel: ToothpasteFeeling {
  private let r: ToothpasteResources
  private var feedback: LabFeedback { r.feedback }
  private var mapper = FeelMapper()
  private var driver = GloopDriver()
  private var gate: MicGate
  private var clock = 0.0
  private var active = false
  private var synthSuspended = false
  private var observers: [NSObjectProtocol] = []

  /// The latest mapping (tests and diagnostics).
  private(set) var lastOutput = FeelOutput()
  /// The voice's gains (tests and diagnostics).
  private(set) var bedMix = ToothpasteBedMix()
  private var lowPower = DeviceConditions.current.lowPower
  private var lowPowerCheck = Throttle(interval: 0.5)
  /// `-fakeMicDenied` (DEBUG builds): the microphone reads as refused, and raising Listen asks nothing.
  private let fakeDenied = LaunchOptions.isDebugBuild && LaunchOptions.has("-fakeMicDenied")
  /// The microphone found refused with Listen up (the UI shows the PermissionGate each time; Microphone.swift).
  private var denials = MicDenialWatch()
  var deniedRaises: Int { denials.count }

  init(resources: ToothpasteResources) {
    r = resources
    gate = MicGate(keepAlive: LaunchOptions.startMicRequested)
    let mic = resources.mic
    resources.feedback.onSelfSound = { seconds in mic.ignoreOnsets(for: seconds) }
    #if os(iOS)
    observers = AudioRoute.observeInterruptions(
      inactive: { [weak self] in self?.audioBecameInactive() },
      resume: { [weak self] in self?.audioMayResume() })
    observers.append(Self.observeRouteChanges { [weak self] reason in self?.routeChanged(reason) })
    observers.append(AudioRoute.observeMediaReset { [weak self] in self?.mediaServicesReset() })
    #endif
  }

  isolated deinit {
    for o in observers { NotificationCenter.default.removeObserver(o) }
  }

  // MARK: ToothpasteFeeling

  var micState: MicState { fakeDenied ? .denied : r.mic.state }

  func setActive(_ isActive: Bool) {
    active = isActive
    feedback.setActive(isActive)
    if isActive {
      if LaunchOptions.startMicRequested { requestMicrophone() }
    } else {
      r.mic.stop()
      gate.stopped()
      mapper.reset()
      synthSuspended = false
    }
  }

  func setPaused(_ paused: Bool) { feedback.paused = paused }

  func requestMicrophone() {
    if gate.request(state: effectiveMicState) == .start { startMicrophone() }
  }

  func update(frame f: ToothpasteFrame, dt: Double) {
    clock += max(dt, 0)
    let p = f.params

    // Microphone: just in time on the first raise of Listen; released 2 s after it returns to 0.
    denials.step(listen: p[.listen], state: effectiveMicState)
    switch gate.step(listen: p[.listen], state: effectiveMicState, now: clock) {
    case .start: startMicrophone()
    case .stop: r.mic.stop()
    case .none: break
    }
    // LabFeedback is @Observable: write only on change, so nothing observing it is invalidated every frame.
    let micLive = r.mic.isLive
    if feedback.micLive != micLive { feedback.micLive = micLive }
    let band = ToothpasteMicBand.range(p[.band])
    if feedback.micBand != band { feedback.micBand = band }

    if lowPowerCheck.ready(at: clock) { lowPower = DeviceConditions.current.lowPower }
    bedMix.step(
      running: f.simDt > 0, sound: feedback.sound, active: active, paused: feedback.paused, lowPower: lowPower,
      micLive: micLive, dt: dt)
    var signals = FeelSignals.make(
      frame: f, dt: dt, catalog: r.catalog, gap: r.solver?.domain.heleShawGap ?? 0.01, micLive: micLive)
    signals.bedScale = bedMix.bedScale
    let out = mapper.step(signals)
    lastOutput = out
    apply(out, dt: dt)
  }

  // MARK: Output

  private func apply(_ out: FeelOutput, dt: Double) {
    if out.cause { feedback.noteCause() }
    feedback.updateHum(out.hum)
    let haptics = feedback.haptics
    for h in out.haptics {
      switch h {
      case .tap(let tap): haptics.play(tap)
      case .event(let e): haptics.play(e)
      case .transient(let i, let s, let gap): haptics.transient(intensity: Float(i), sharpness: Float(s), minGap: gap)
      case .ramp(let duration): haptics.ramp(duration: duration)
      case .crackle(let field, let depth): haptics.crackle(fieldMicroTesla: field, depth: depth, clock: clock)
      }
    }
    // Our own clicks, knocks and splashes must not drive the oobleck monsters.
    if out.selfSound, r.mic.isLive { r.mic.ignoreOnsets(for: SoundPolicy.selfSoundWindow) }
    if let synth = feedback.synth {
      driver.write(out, to: synth.controls, triggers: synth.running, bedScale: bedMix.bedScale)
      // The continuous layers carry the policy's duck and silences (FeelSignals.bedScale); the host gain only follows
      // Sound and the app being active, so the one-shot events keep their level (ToothpasteBedMix).
      let gain = Float(bedMix.hostGain)
      if synth.bedGain != gain { synth.bedGain = gain }
    }
  }

  // MARK: Microphone

  /// The listener's state, with a denial the user has since lifted in Settings reported as `.off` (MicListener keeps
  /// `.denied` until its next start, which then succeeds).
  private var effectiveMicState: MicState {
    if fakeDenied { return .denied }
    let s = r.mic.state
    return s == .denied && r.mic.permission == .granted ? .off : s
  }

  private func startMicrophone() {
    let mic = r.mic
    guard !fakeDenied, mic.state != .on, mic.state != .starting else { return }
    Task { @MainActor in _ = await mic.start() }
  }

  // MARK: Audio session events

  /// A call, Siri or another app took the session: stop listening and pause the voice.
  private func audioBecameInactive() {
    r.mic.suspend()
    if let synth = feedback.synth, synth.running {
      synth.stop()
      synthSuspended = true
    }
  }

  /// The system recommends resuming.
  private func audioMayResume() {
    if synthSuspended {
      synthSuspended = false
      if active, feedback.sound { feedback.synth?.start() }
    }
    let mic = r.mic
    Task { @MainActor in await mic.resume() }
  }

  /// A headset arrived or left: the input format may have changed, so the tap is rebuilt. (The voice's engine
  /// restarts itself on its configuration change, in SynthHost.)
  private func routeChanged(_ reason: UInt) {
    #if os(iOS)
    let device = reason == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue
      || reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
    guard device, r.mic.isLive else { return }
    let mic = r.mic
    mic.suspend()
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(300))
      await mic.resume()
    }
    #endif
  }

  /// mediaserverd restarted: every engine must start again (AudioRoute has re-applied the session).
  private func mediaServicesReset() {
    if let synth = feedback.synth {
      synth.stop()
      if active, feedback.sound { synth.start() }
    }
    guard r.mic.isLive else { return }
    let mic = r.mic
    mic.suspend()
    Task { @MainActor in await mic.resume() }
  }

  #if os(iOS)
  /// Built outside the main actor: the observer block is `@Sendable` and only hops (Swift 6 rule, §5.7).
  private nonisolated static func observeRouteChanges(
    _ handler: @escaping @MainActor @Sendable (UInt) -> Void
  ) -> NSObjectProtocol {
    NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
    ) { @Sendable note in
      let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue ?? 0
      Task { @MainActor in handler(reason) }
    }
  }
  #endif
}
