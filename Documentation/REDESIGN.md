# Toothpaste Toy: redesign brief (Metro Station × quantum hologram)

Date: 13 October 2026. Status: **binding for the redesign**. Supersedes the visual/UX parts of `ARCHITECTURE.md` §6 and `research/labkit-from-orbitals-spectra.md` §9 for this app. Physics, LabKit engine, tests and honesty rules stay.

The user's verdict on the Rheo build: "lame af". His direction: **redesign with the Metro Station design system, rename to "Toothpaste Toy", but in a quantum hologram.**

Metro Station skill (read it first, then the spec sections it routes you to):
`/path/to/developer/Documents/AI Stuff/Metro Station/Skills/metro-station-design-system/SKILL.md`, `references/design-system-spec.md`, `references/swiftui-integration.md`, `assets/design-tokens.json`, `assets/visual-reference.png`, `assets/swiftui-starter/*` (copy the starter into the app target, as the skill says; adapt, don't fork blindly). A real adopter to learn from: `AI Stuff/Metro Station/App` (the source app) and `AI Stuff/AssemblerToy` (a toy that adopted it).

## 1. Identity

- Name: **Toothpaste Toy** (display name), project/target/module `ToothpasteToy`, bundle `com.utkarsh.toothpastetoy`, folder `AI Stuff/Toothpaste Toy`. Internal `Rheo*` type names become `Toothpaste*` (but `Rheometer`, `rheology` stay: they are words, not the brand).
- Toothpaste is the hero and the default material. The other 12 fluids stay as a secondary "Other pastes" lineup (oobleck, ketchup, honey, …) so nothing built is thrown away.
- One-line pitch: *a quantum hologram of toothpaste you can squeeze, poke, stack, tilt and shake — real yield-stress physics, rendered as light.*

## 2. The primary object: the holo chamber (Metro "one meaningful primary object")

- A **precise opaque metal instrument housing** (Metro metal recipe: gauge housing #070A0E, metal light/dark, 40 knurls feel, fine directional light, housing shadow) framing a **projection volume** — the tank, still life-size where it fits.
- At the bottom: a **projector emitter** (thin metal lip with a cyan light slit) casting a faint light cone up into the volume. At the top: the **tube nozzle** (metal, knurled cap) from which paste is squeezed.
- Inside: **the paste is a quantum hologram**, not opaque goo:
  - luminous translucent body with a bright Fresnel rim (silhouette reads instantly);
  - **holographic interference fringes / thin-film iridescence** across the body whose hue shifts with device tilt (like a real hologram sticker), bounded per Metro §13–14 (subtle, diagonal chromatic detail, no broad moving fill);
  - **scanlines** and a fine voxel/particle grain (the MPM particles shown as a probability cloud — each particle a faint point whose brightness flickers with its own phase: "quantum shimmer", bounded and honest);
  - **superposition ghosts**: when paste moves fast, 2–3 faint, time-delayed echoes of the surface trail it (violet/magenta), fading within ~0.2 s;
  - **Metro semantic colour on the physics**: cyan = flowing/shear (continuous signal), amber = stress events and jamming/yield flashes (events/emphasis), violet/magenta = structure/memory (second signal family). Toothpaste's classic **three stripes** become three holographic bands (white core + cyan + violet), carried by per-particle dye so the stripes stretch, fold and coil with the flow.
  - other materials keep identity through tint + fringe pattern (honey amber glass, oobleck milky-white quantum foam that flashes amber when it jams, MR fluid metallic violet with field lines, lava amber-white emission).
- Depth and parallax: the back of the chamber is a faint technical grid (Metro environment) that sits at a different depth from the hologram; tilt shifts them against each other (world-anchored, Gyre-style), but **readouts and controls never move** (Metro contract 1).
- Bloom/EDR: tasteful; highlights only.

## 3. The lens (Metro's isolated native glass lens = your finger)

- Metro's **isolated clear Liquid Glass lens** (constant 0.48 opacity, centred radius, faint moving rim arc, `LensRefraction` + `InstrumentLensOptics.metal`) becomes the **probe**: a glass disc you drag through the hologram to poke, stir and cut the paste. It refracts the hologram under it (decorative layer only), and its radius may bounce on a yield/jam event (domain-driven, optional).
- A fixed readout beside/under the lens frame shows the local shear rate, stress and state word ("holding", "yielding", "flowing", "jammed") — never filtered by optics.

## 4. Controls and channels (Metro components, smallest useful set)

- **Squeeze** — the signature control: a large tactile **crown** (Metro §10) at the nozzle: turn/hold to extrude; its angular speed sets the extrusion rate (mm/s), with detents; plus a **floating action** "Squeeze" press-and-hold button as the accessible alternative. Releasing stops the ribbon (it tears off at the nozzle according to the paste's yield stress).
- **Environment crowns / Steppers** (pick per Metro: fine continuous → crown; whole-number or named → native Stepper):
  Gravity (detents Zero-g · Moon · Mars · Earth · Jupiter), Heat (°C), Time (×0.05–×2 with Slow motion detent), Stripe count or Nozzle size (Stepper, whole numbers), Material (named Stepper or event tiles).
- **Vertical signal pills** (Metro §11) for the three channels: Shear γ̇ (cyan), Stress σ (amber), Structure λ / Jam (violet). Constant outlines; interior energy changes.
- **Telemetry row** (Metro §12): rounded numerals for the live value (e.g. yield stress τ_y "150 Pa", viscosity η), monospaced unit labels, occasional serif meaning ("holds its shape", "flows like a liquid").
- **Event tiles**: yield events, jam events, tear-offs — amber attack/decay.
- **Floating action group** (Metro §12): Squeeze (hold), Refill/Clean, Freeze, Rheometer, Info. Native Liquid Glass.
- The previous 5-page × 4-knob console is retired. Keep a "More" sheet (Metro "settings and explanations": quiet content panels) for the remaining parameters (Shake/Rate, Mic Listen/Drives, Magnet, View options, Haptics/Sound, the Rheometer flow curve, How it works).

## 5. Play (what makes it a toy, not a lecture)

1. Open the app → a fresh chamber, a short striped ribbon already coiled on the floor, nozzle ready.
2. **Squeeze** → a striped holographic ribbon extrudes, falls, folds and **stacks into a coil that holds its shape** (Bingham yield stress — the whole point of toothpaste). Squeeze faster → thicker, flatter, it starts to slump.
3. **Drag the lens** → cut the ribbon, poke dents that stay (yield stress), smear it.
4. **Tilt the phone** → the pile leans but doesn't flow until you tilt past the yield angle; then it slides.
5. **Shake** → it jiggles elastically below yield, then breaks into flow.
6. **Gravity → Moon** → taller towers; **Jupiter** → they slump. **Heat** → runnier.
7. **Other pastes** → same chamber, other personalities (oobleck jams under the lens and flashes amber; honey drips through the stripes; ketchup thins when shaken).
8. Ideas welcome if cheap and honest: a "squeeze from the bottom" tube mode, writing your name in paste, a stack-height score.

## 6. Honesty (unchanged rules)

The physics is classical (2D elasto-viscoplastic MPM, LabKit). "Quantum hologram" is a **visual style**: the info sheet must say so plainly ("The paste obeys real yield-stress physics. The quantum shimmer, ghosts and fringes are a hologram look, not quantum mechanics."). Keep provenance of material values. British spelling.

## 7. Engineering constraints

- Keep the frozen engine/model architecture (render loop owns time; LabKit MPM/Rigid/Feedback/Sensors). Replace UI and rendering style; extend the engine for the nozzle emitter + stripe dye.
- Metro contracts: fixed foreground; touch ownership (a control owns its full touch); accessible alternatives; feedback once per accepted event; constant pill outlines; whole-number formatting where whole.
- Performance on the iPhone 15 Pro Max (see `DEVICE-RUN-1.md`): keep total GPU ≤ ~7 ms at 120 Hz for toothpaste; the hologram passes must be cheap (target ≤ 1.5 ms); the oobleck budget issue and the 66 ms material-switch hitch must be fixed; idle timer disabled during `-autoTour`.
- Simulator + headless offscreen pictures for checks; never build inside iCloud (mirror with `Tools/build.sh`).

## 8. Cross-area contracts (fixed before the parallel work starts)

- **Stripe dye**: `MPMParticle.flags` bits 8–11 carry a dye band (0 = none, 1–7 = band index). `MPMEmitter` gains `stripes: Int` (0 = plain); the emit kernel assigns the band from the particle's lateral offset across the nozzle (equal-width bands). `MPMSolver.fill(…)` gains an optional `stripes:` for the starting ribbon. The renderer reads `(flags >> 8) & 0xF`.
- **Lens**: the hub exposes `lens: LensState` (centre in tank metres, radius in metres, active, velocity) written by the UI's glass lens control and by canvas drags; the engine uses it as the kinematic probe collider; the renderer refracts the hologram under it.
- **Squeeze**: the hub exposes `squeeze: SqueezeState` (rate mm/s ≥ 0, nozzle diameter mm, stripes, material) written by the crown/button; the engine turns it into an emitter at the nozzle and tears the ribbon off on release.
- **Channels for the pills and tiles**: the hub publishes (10 Hz telemetry plus a lock-free per-frame snapshot for drawing) `shearChannel`, `stressChannel`, `structureChannel` (0…1 normalised with SI values alongside) and an `events` feed (yield, jam, tear-off, impact) with time stamps.

## 9. App icon (final, integrator-owned — do not redraw)

The user's brief (13 Oct 2026): **"aqua gel with hot pink metallic streak on a matrix glowing mesh"**. Done by the integrator in
`Tools/make-icon.swift` → `ToothpasteToy/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` (copy in
`Documentation/screenshots/tt-icon.png`): a translucent aqua gel ribbon (refraction, Beer–Lambert absorption, Fresnel rim,
glossy highlights) carrying a brushed hot-pink metallic streak, floating over a Matrix-green glowing perspective mesh with
code rain. The UI area must not change the icon or the script; the in-app palette may echo it (aqua gel, hot-pink metal,
matrix green) where Metro's semantic colours allow.

## 10. "We drop no packets" (the user, 13 Oct 2026) — binding acceptance

- **Zero dropped frames on the iPhone 15 Pro Max at 120 Hz** across the full `-autoTour` (every material, every
  experiment, every material switch, squeezing, lens drags): no frame over 8.33 ms in `perf.csv`'s `frame_ms_max`, no
  `lagging_frames`, and the Metal System Trace shows no missed presents. The 66 ms material-switch hitch, oobleck's
  8–10 ms GPU and any first-use shader compile hitch must be gone (precompile pipelines at launch; reseed without a
  blocking GPU round trip). Thermal: hold this for ≥ 10 minutes at Nominal/Fair. If a material truly cannot fit,
  degrade its quality step automatically *before* a frame drops, never after, and log it.
- **Zero lost work.** LabKit and Toothpaste Toy are now git repositories (databases outside iCloud:
  `~/Developer/git/LabKit.git`, `~/Developer/git/ToothpasteToy.git`). The integrator snapshots both every 15 minutes.
  Agents: do not commit, rebase, reset or checkout; just keep your progress log current.
- **Zero dropped input:** every touch that starts on a control is owned by it for the whole sequence (Metro touch
  contract); every squeeze, poke and drag reaches the engine on the next frame (log any input applied late).

## 11. Device finding that sets HOLO's priority (device lab run 2, 13 Oct 2026; details in progress-devlab.md / DEVICE-RUN-2.md)

On the iPhone 15 Pro Max the frame is **render-bound, not physics-bound**: toothpaste 7.2 ms GPU at Nominal, of which
rendering is ~82 % (front pass 4.2 ms, fields 2.3 ms, behind pass 1.15 ms + behind copy 1.1 ms, post 1.4 ms) versus the
MPM solver ~2.2 ms; the system compositor adds ~2.5 ms per frame; thermal reached Serious and the app fell back to 60 fps.
To meet §10 (zero dropped frames at 120 Hz for ≥ 10 min) HOLO must cut render cost to ≲ 2.5 ms total: half-resolution
(or quarter) hologram fields with a single full-res composite, no full-screen behind copy when nothing refracts (or a
cheap downsampled one), merge passes, avoid full-screen overdraw, keep SwiftUI glass layers over the Metal view to the
minimum the Metro design needs (each glass layer costs compositor time), and measure on the device lab's next run.
