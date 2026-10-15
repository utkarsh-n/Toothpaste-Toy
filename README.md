# Toothpaste Toy (formerly Rheo)

> 13 October 2026: being redesigned as **Toothpaste Toy** (Metro Station design system, quantum-hologram look;
> `Documentation/REDESIGN.md`). The text below still describes the Rheo build until the UI area rewrites it.

A non-Newtonian toy for iPhone on iOS 27. A thin glass tank of fluid, drawn life-size on the iPhone 15 Pro Max
(71.2 × 101.4 mm, the width of the screen), that you poke, punch, stir, tilt, shake, shout at, heat, magnetise and slow
down. Thirteen materials share the tank: water, honey, ketchup, mayonnaise, toothpaste, oobleck, slime, Silly Putty,
yogurt, quicksand, MR fluid, paint and lava. A steel ball, a glass marble, a cork block and a die sink, float and
bounce in them.

The fluid is a real continuum simulation, not an animation: a 2D material-point (MPM) solver on the GPU runs one
elasto-viscoplastic law with each material's measured yield stress, viscosity, flow index, density, temperature
dependence and, for oobleck, the Wyart–Cates jamming law fitted to cornstarch. Hit the oobleck fast and it turns solid
under your finger; push slowly and your finger sinks.

The phone's sensors drive it:
- **Accelerometer and gyroscope:** gravity in the tank is the part of real gravity in the screen's plane, so tilting the
  phone tilts the fluid; a shake shakes it.
- **Magnetometer:** a real magnet near the phone stiffens MR fluid (off by default in the Simulator).
- **Microphone** (only once you raise Listen): sound can shake the floor, push gravity, turn the paddle, kick the
  surface or warm the tank.
- **Thermal state** (opt-in, `-thermalHeat`): a hot phone warms the fluid.

The stack is SwiftUI and Liquid Glass for the interface, Metal for the solver and the renderer, Core Motion, AVAudio
and Core Haptics for the sensors and feel, and Box2D (MIT, vendored) for the props. It is built on **LabKit**
(`../LabKit`), the shared toy engine: design system, sensors with Simulator fakes, haptics and a live synth, the Metal
render host, the Box2D wrapper, the GPU MPM solver and fluid renderer, and a CPU oracle that checks the solver. No
network, no analytics.

## Run

```zsh
cd "/path/to/developer/Documents/AI Stuff/Toothpaste Toy"
TT_BUILD_DIR=$TMPDIR/tt-me TT_SIM='iPhone 17 Pro' Tools/build.sh sim     # Debug, Simulator
TT_BUILD_DIR=$TMPDIR/tt-me Tools/build.sh device                         # Release, generic iOS (team YOUR_TEAM_ID)
TT_BUILD_DIR=$TMPDIR/tt-me TT_SIM='iPhone 17 Pro' Tools/build.sh test    # ToothpasteToyTests + ToothpasteToyUITests
```

`xcodebuild` hangs when it loads a project from this iCloud-synced folder, and the app depends on `../LabKit` by
relative path, so the script mirrors both folders side by side (`src/LabKit`, `src/ToothpasteToy`) into `TT_BUILD_DIR`,
runs `xcodegen` there and builds there. Give every parallel build its own directory. The old variable names
`RHEO_BUILD_DIR` / `RHEO_SIM` still work. The Simulator name must exist (`xcrun simctl list devices`); an iPhone
15 Pro Max simulator shows the tank life-size, any other phone fits it to the screen.

Install on the phone after a device build:

```zsh
xcrun devicectl device install app --device <device-id> "$TMPDIR/tt-me/dd/Build/Products/Release-iphoneos/ToothpasteToy.app"
```

The Simulator has no motion sensors: Rheo simulates a phone held upright (add `-simSway` to make it sway). Drag with
two fingers, or press the arrow keys, to tilt it.

## Playing with it

The screen is one tank. The glass top bar holds the telemetry card (η of the whole tank, γ̇ and σ at the probe) and
four buttons: **Material** (the shelf), **Experiments** (flask), **Layers** and **Info** (i). The five-page console
below is the tank's floor.

### Touch

- **Drag a finger through the fluid.** Your finger is a probe (its size is the Finger knob) that pushes with at most a
  fingertip's force, so a liquid barely notices it while jammed oobleck, set lava, Silly Putty or magnetised MR fluid
  stop it. The Rheometer reads the shear rate and stress at its leading edge.
- **Tap** for a poke: a short jab straight down. **Swipe fast** (over 0.8 m/s) for a punch: oobleck jams solid under it.
- **Two fingers:** pinch to zoom (×1 to ×4, display only); in the Simulator, drag sideways to tilt the phone.
- **Drag a prop** to move it; **drag the magnet marker** on the floor (Magnet knob above 0) to slide the
  magnet.
- **Keyboard:** arrows tilt, space pokes, + and − zoom, R refills, F freezes time. The tank has keyboard focus at launch.
- **VoiceOver:** the tank is one element with actions (Poke, Punch, Stir, Tilt left or right, Shake, Refill, Zoom in or
  out) and its state as the value.

### The shelf (Material)

A mode chip, then tiles:

| Mode | What a tile does |
|---|---|
| **Fill** | Refills the tank with that material (about 45 % full) |
| **Pour** | Picks the pour material: the next drag pours it in from your finger, so materials can share the tank |
| **Drop** | Prop tiles: a steel ball, a glass marble, a cork block, a die drop in at the top centre |
| **Scoop** | No tiles: the next drag takes fluid out under your finger |

### Experiments

Each refills the tank, restarts the clock and plays a short scripted demonstration; touch the tank to take over.

| Experiment | What you see |
|---|---|
| Punch the oobleck | A fast jab jams the oobleck under the finger, then it flows back |
| Slow and fast finger | A slow finger sinks through oobleck; a fast one is stopped short by the jam it makes |
| Oobleck monsters | A thin layer on a floor shaking at 17 g, 120 Hz. Real layers grow holes and fingers; this 2D one jams on every bounce |
| Ketchup won't pour | A mound holds on a tilted phone, then thins and slides when shaken |
| Toothpaste holds shape | A column and a ribbon stand; a slow finger pushes through |
| Mayonnaise on the Moon | A tall mound stands at 1/6 g, then slumps when gravity returns to 1 g |
| Honey, cold and warm | Honey poured at 4 °C piles up; warmed to 37 °C, the pile runs flat |
| Putty bounce and slump | A Silly Putty ball bounces off a fast poke and slumps over seconds |
| Slime puddle | A blob springs back, then spreads into a puddle |
| Quicksand: shake, sink | A glass marble rests on firm quicksand until a 3 g shake liquefies it |
| Magnet and MR fluid | A thin layer heaps over the magnet and stiffens; the heap follows the magnet along the floor |
| Paint levels | Brush marks flow out flat within seconds |
| Lava crust | 1170 °C basalt cools: the surface darkens into a crust over a flowing core |
| Two fluids | Honey over oobleck; the denser honey slowly sinks into it |

### Knobs

| Page | Knob | What it does |
|---|---|---|
| Fluid | Yield | Yield stress τ_y, 0.1–1000 Pa (detents: Ketchup 15, Mayonnaise 80, Toothpaste 150). Below it the fluid holds its shape |
| | Consistency | K in σ = τ_y + K·γ̇ⁿ, one range 0.001–10 000 Pa·sⁿ for every material (Water, Glycerol, Honey detents); oobleck's solvent viscosity |
| | Flow index | n, 0.2–1: below 1 it thins as you stir faster |
| | Packing | Starch volume fraction φ, 0.40–0.60 (oobleck only). Crowded enough, a hard hit jams it |
| World | Gravity | −1 to 3 g; its direction is your phone's tilt |
| | Heat | 0–90 °C (Fridge, Room, Body); with lava in the tank, the eruption temperature 1050–1200 °C |
| | Magnet | 0–500 mT, a virtual magnet under the floor (207 mT = a strong magnet 1 cm away). Drag its marker |
| | Time | ×0.05–2 simulation speed (Slow motion ×0.25) |
| Touch | Finger | Probe radius, 3–20 mm |
| | Stir | A paddle at the centre, 0–5 rev/s |
| | Shake | Peak acceleration of a vibrating floor, 0–27 g (Holes 10 g, Fingers 17 g) |
| | Rate | Floor frequency, 20–200 Hz |
| Signals | Listen | How hard sound shakes the tank. The first raise asks for the microphone |
| | Drives | What sound moves: Shake, Gravity, Stir, Kicks (a poke per beat) or Heat |
| | Gain | Microphone sensitivity ×0.25–8 |
| | Band | Which pitches drive the tank, 40–2000 Hz |
| View | Glow | Stress light: lights the fluid by how hard it is sheared |
| | Grain | Speckle that moves with the fluid |
| | Tracers | Dye lines that follow the flow |
| | Depth | Exaggerates the tank's thickness in the shading |
| Rheometer card | Memory | The elastic memory time λ = η/G (oobleck: how long a jam lasts) |
| | Rebuild | Structure rebuild time θ of thixotropic materials (ketchup, mayonnaise, yogurt, quicksand, paint) |

Double-tap a knob to reset it; long-press for fine control. The controls row has **Refill**, **Freeze time**, the
**Rheometer** and **Reset page**. The Fluid page dims the knobs that do nothing for the current material.

### The Rheometer and the info sheet

- **Rheometer** (the chart button): a strip over the console with the material's modelled flow curve σ(γ̇) on log-log
  axes, the other materials faint, published measurements as hollow rings and a live cursor at the probe. Pull it up
  for probe viscosity, stress and shear rate with provenance, the Memory and Rebuild knobs and the literature list.
  With no finger in the fluid the cursor sits, dimmed, at the most strongly sheared region.
- **Layers:** Show (Stress light, Dye lines, Particles, Rheometer cursor, Colour by shear rate, viscosity, stress,
  structure, jam, temperature or speed, with a legend), Feel (Haptics, Feel the fluid, Sound), Sensors (Use tilt, Use
  the magnetometer).
- **How Rheo works** (i): nine panels: what you're looking at, touch, what you're seeing, knobs, experiments, what's
  real and what's illustrative (with a real/tuned line per fluid), sensors in play, sound and feel, sources and
  licences.

### Launch arguments

| Argument | Effect |
|---|---|
| `-material <id>` | Start with this material: `waterLike honey ketchup mayonnaise toothpaste oobleck slime sillyPutty yogurt quicksand mrFluid paint lava` |
| `-experiment <id>` | Apply an experiment at launch: `punch slowfast monsters ketchup toothpaste moon honey putty slime quicksand magnet paint lava twofluids` |
| `-fakeTouch [poke\|stir\|punch\|slow]` | A scripted finger, looping every 4 s after 1.5 s |
| `-quality standard\|high\|bench` | Grid cell 2.0 / 1.6 / 1.1 mm (`high` steps down to `standard` after 3 s of lag) |
| `-noPersist`, `-ui-testing` | Neither load nor save settings (`-ui-testing` also means defaults) |
| `-thermalHeat` | The phone's thermal state warms the tank (off by default) |
| `-simSway`, `-fakeMic`, `-startMic`, `-fakeMagnet`, `-fakeShake`, `-fakeThermal n`, `-fakeLowPower` | LabKit's sensor fakes (Simulator and Debug builds) |
| `-fakeMicDenied` | The microphone reads as refused without asking iOS (Debug) |
| `-page <id>`, `-shelf`, `-rheometer`, `-large`, `-info`, `-infoPanel <01…09>`, `-expanded`, `-banner <kind>`, `-touched`, `-diagnostic <name>` | Open a page, the shelf, a sheet or a banner at launch (pictures and layout checks) |
| `-perfLog` | Once a second, a CSV row in `Documents/perf.csv` and an os_log line (fps, frame and GPU ms, substeps, thermal, quality) |
| `-autoTour` (`-tourShots`) | Cycles every material and experiment, 6 s each, for unattended device timing (`Documentation/DEVICE-RUN.md`) |
| `-snapshot`, `-uiTour [-tourOnly <prefix>]`, `-ax` | In-app pictures written to the app's tmp; `-tourOnly qa-` is the QA tour |

The full table, with what reads each argument, is `Documentation/SKELETON.md` §5.

## How it works

**Frame loop** (`Rheo/Model/RheoModel.swift`, the hub). `RheoModel` is LabKit's `LabRenderScene`. The render loop owns
time: once per drawn frame it calls `advance(dt:)`, which snapshots the knobs and hands a `FrameStep` to the engine;
the engine returns a `RheoFrame` (exactly what the solver gets, plus the probe, props, finger and events) that the
renderer and the feel read. `Rheo/Model/Interfaces.swift` is the contract between the four areas below.

**Physics** (`Rheo/Engine`, `Rheo/Model`).
- `RheoEngine.swift` builds each frame's `MPMFrameInput`: gravity (the screen-plane part of measured gravity × the
  Gravity knob, or the simulated phone), the phone's own acceleration for shakes, the vibrating floor, temperature,
  the virtual magnet and the magnetometer's field change, colliders (finger, stir paddle, props), pour emitters and
  scoop drains. It applies the knobs to the material rows, plays experiment scripts, keeps a substep budget (the
  world slows rather than skipping physics when the phone falls behind) and steps a finer quality down on lag or heat.
- The solver is LabKit's `MPMSolver`: PB-MPM's fused grid transfer (EA SEED, BSD-3, ported to Metal) with the
  elasto-viscoplastic law of `Documentation/research/rheology-models.md` §4 as a compliant constraint: yield stress,
  Herschel–Bulkley and Newtonian flow, Maxwell elasticity (slime, Silly Putty), Moore-type thixotropy (ketchup,
  mayonnaise, yogurt, quicksand, paint), Wyart–Cates shear jamming (oobleck), Arrhenius temperature dependence (honey,
  lava), Carlson's field-dependent yield and a Kelvin force (MR fluid), and Hele-Shaw drag for the 10 mm gap. Grid
  cells are 2 mm, 2 × 2 particles per cell, about 3,300 particles at the default fill.
- `TouchTools.swift`: the force-limited finger, tap and swipe detection, pour, scoop, prop and magnet drags, scripted
  fingers. `Props.swift`: Box2D props coupled to the fluid through the solver's per-body impulses, with added mass and a
  drag that follows the flow curve (a steel ball jams oobleck's surface, is held about 0.4 s, then sinks).
  `ProbeScanner.swift` finds the most strongly sheared region when no finger is down. `Stimuli.swift`: the mic routes,
  the magnetometer's dead zone, the substep budget, the vibrating floor's log.
- `Materials.swift`: the 13 materials (LabKit's `ContinuumPresets`, copy, looks, honesty lines, citations) and the
  Rheometer's modelled flow curves, the steady state of the same law. `Knobs.swift`: the 22 knob specs and how each
  maps onto the material. `Experiments.swift`: the 14 experiments and their scripts.

**Rendering** (`Rheo/Render`, LabKit's `MPMSurfaceRenderer`).
1. Compute: the solver's substeps, then a half-resolution splat of the particles into thickness, normal and material
   fields, blurred into a smooth surface (`encodePrepass`).
2. Pass 1: the stage, the tank's lit back wall with its millimetre ruler and grid, props behind the fluid.
3. That pass is copied into a mipmapped texture, so the fluid can refract it.
4. Pass 2: the fluid's full-resolution shade (`encodeShade`): clear fluids (water, honey, slime) are lit from behind
   through the refracted wall and tinted by Beer–Lambert absorption; milky ones are brighter under the free surface;
   a meniscus, clear-coat highlights, jam matte for oobleck, an oily sheen for MR fluid, blackbody glow and a crust for
   lava; stress light, dye and grain on top. Then props in front, the front glass, the finger ring, the rheometer
   cursor, the magnet marker and the floor ripple.
5. LabKit's bloom and EDR composite.

**Feel** (`Rheo/Feedback`). `FeelMap.swift` turns each frame into a haptic hum (intensity from the stress at the probe,
sharpness from the solid fraction and finger speed) and transients (yield, jam crack, pinch-off, prop hits, pokes).
`GloopKernel.swift` is a live synth voice: a body pitch set by the fluid's thickness (thick fluids sound low), drag
noise, bubbles, squelches, grain clicks, splashes and the floor's hum. `Microphone.swift` gates the microphone (asked
for only on the first raise of Listen) and band-filters it. `RheoFeel.swift` wires it to LabKit's `LabFeedback`, with
the bed ducked while the microphone listens and a self-sound window so Rheo's own sounds do not drive the tank.

**Interface** (`Rheo/UI`, `Rheo/App`). `RheoScreen.swift` is the one screen: the tank region (`CanvasRegion`), the top
bar (`TopBar.swift`), the shelf (`MaterialShelf.swift`), the stage tags and banners (`StatusFeed.swift`), the console,
the Rheometer (`RheometerSheet.swift`) and the info sheet (`InfoSheetContent.swift`, copy in `RheoCopy.swift`).
`App/PerfLog.swift` is the `-perfLog` recorder and `-autoTour`; `App/Snapshot.swift` and `App/QATour.swift` take the
in-app pictures.

**Tests.** `RheoTests` (hosted in the app): `PhysTests` (38: every material's signature behaviour on the GPU solver,
experiments, props, touch, knobs), `FeelTests` (23, including the real audio thread), `RenderTests` (3: looks, edge
sharpness, cost), `RheoSmokeTests` (6), `UITests` (14: layout maths and copy lint), `SkeletonDiagTests` (1).
`RheoUITests` (11 XCUITests with real taps, drags and keys).

## What is real, what is tuned, what is illustrative

- **Real:** the materials' yield stresses, viscosities, flow indices, densities and temperature laws come from
  measurements and the literature (sources in the info sheet's panel 09 and `Documentation/research/rheology-models.md`
  §6). Gravity is the measured one, and the Moon and Jupiter detents use true values. Oobleck's jamming law and packing
  fractions are Han et al.'s fit to cornstarch; MR fluid's yield follows a commercial fluid's curve (Carlson).
- **Real, with a 2D caveat:** the tank is a thin slice. Everything moves in the plane of the screen, and the glass faces
  add a Hele-Shaw drag like a 10 mm cell. Honey folds instead of coiling, threads tear instead of pinching into drops,
  and oobleck's jammed front is a slice of a 3D one.
- **Tuned (softened) so it runs on a phone:** sound speed (a few metres per second instead of 1.5 km/s, so a slight
  squash and a softer bounce), the jammed oobleck's stiffness (far softer than real; a jam lets go in about 0.15 s), Silly
  Putty's stiffness (28× lower, so it creeps 28× faster), MR fluid's field yield (capped at 1.5 kPa against about
  50 kPa), lava's cooling (about 100× faster), props' added mass (they move slower than real). Grid cells are 2 mm, so
  anything thinner than about 5 mm is smoothed.
- **Not reproduced, and the app says so:** a vibrated oobleck layer's persistent holes and fingers (Merkt 2004): this
  2D layer jams on every bounce. MR fluid's spikes: a thin layer heaps over the magnet, a deep pool stays flat, and no
  spikes form. Quicksand's water–sand separation. Mayonnaise splitting when heated. Real basalt stiffening below 900 °C.
- **Illustrative:** glow (stress light), grain, depth shading, dye lines, the lava crust's crack pattern and the pinch
  zoom are display choices. The vibrating floor is simulated (the phone cannot shake at 10 g). η, σ and γ̇ are read
  from the simulation at the probe: modelled, not measured. Every number in the interface carries its provenance word.
- **Life-size** only on the iPhone 15 Pro Max (and the models in LabKit's millimetres-per-point table): elsewhere the
  tank is fitted and the tag shows the scale.

## Privacy

Rheo has no network code, no accounts and no analytics. The microphone is off until you raise Listen; iOS asks then,
and the sound is analysed in a ring buffer that is constantly overwritten: nothing is recorded or kept. Motion, the
magnetometer and the thermal state are read on the phone and never stored. Rheo saves only the material, the shelf
mode and the Layers settings (`Rheo.settings`) and the haptics and sound preferences in its own UserDefaults. With
`-perfLog` it writes timing numbers to its own Documents folder. Source links in the info sheet open in Safari only when
you tap them.

## Verification

`VERIFICATION.md` (builds, every test suite with counts, the physics checks with numbers, the screenshots looked at,
known limits and what still needs the device). The design and research behind it: `Documentation/RESEARCH.md`,
`Documentation/ARCHITECTURE.md`, `Documentation/SKELETON.md`. The device measurement recipe:
`Documentation/DEVICE-RUN.md`.


## Public snapshot

See [PUBLICATION.md](PUBLICATION.md) for publication exclusions and setup requirements.
