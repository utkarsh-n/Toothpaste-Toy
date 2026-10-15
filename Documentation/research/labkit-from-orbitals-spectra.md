# LabKit design system and UX spec: Orbitals, Tether and spectra-lab, reconciled with Gyre

**Purpose.** This is the single merged design system for **LabKit**, the shared Swift package behind Utkarsh's iOS 27 toy apps, and its first consumer, **Rheo** ("Non-Newtonian Toy"). The look is "glass over phosphor": Gyre's Liquid Glass chrome floating over a dark stage, with Orbitals' monospaced phosphor instrument surfaces (readouts, numbered panels, plots). The spec covers tokens with exact values, a per-app accent mechanism, a component catalogue with Swift APIs, accessibility rules, the haptics and sound policy, copy rules, and every contradiction between the source apps with the pick for LabKit.

**Companion notes (same folder).**
- `labkit-from-gyre.md` defines the package layout, `ParamSpec`/`ParamStore`, modulation, sensors, `HapticEngine`, `SynthHost` and the render host. This note **adopts its module split and type names** and only adds or overrides where Orbitals, Tether or spectra-lab say something different. Section 1 lists every override.
- `rheology-models.md` is the physics source for every Rheo number quoted in copy examples here.
- `toolchain-checks.md` §6 verified the Liquid Glass APIs (`Glass`, `glassEffect`, `GlassEffectContainer`, `.pickerStyle(.tabs)`, glass button styles) against the iOS 27 SDK. They are not re-verified here.

**Checked on:** 3 October 2026. Xcode-beta (27A5194q), Swift 6.4, `iPhoneOS27.0.sdk` / `iPhoneSimulator27.0.sdk`, XcodeGen 2.46, simulator iPhone 17 Pro (iOS 27.0).

**Read for this note.**
- `Spectra/Docs/research/design-orbitals.md` and `design-house-rules.md` (in full), then confirmed against source.
- Orbitals (git `385f88f`): `UI/OrbitTheme.swift`, `UI/GlassControls.swift`, `UI/InstrumentControlSheet.swift`, `Services/OrbitalHaptics.swift` (all in full); `UI/TelemetryView.swift:95-190` (field notes); targeted reads of `ControlsView.swift`, `DashboardView.swift`, `MotionControls.swift`; `project.yml` usage strings.
- Tether (git `c9108ec`): `UI/TetherTheme.swift` (in full), `UI/MethodologyView.swift:85-98`.
- spectra-lab: `README.md`, `public/spectra.css`, `public/index.html`, `src/ui/{app,controls,draw,feedback,notes,fieldview}.js`, `src/core/{presets,state}.js`, `src/core/spectrum.js` (formatting), and a grep of `src/instruments/*.js` for labels, hints, badges and detents.
- Gyre: `UI/InfoSheet.swift` (in full), targeted reads of `UI/GlassKnob.swift`, `UI/TopBar.swift`, `Feedback/Haptics.swift`, `Model/GyroModel.swift:156-157, 263-266, 670-695`, `Sensors/MicListener.swift:11-16`, `project.yml:26-29`. Gyre tokens otherwise come from `labkit-from-gyre.md` §4, which re-read them.
- **Continuation pass (same day).** Re-checked §0–§3 against the sources above, line by line where a line is cited. Read in full this pass: `Orbitals/Services/OrbitalHaptics.swift`, `Gyre/Feedback/Haptics.swift`, `spectra-lab/src/ui/feedback.js`, `Tether/UI/TetherTheme.swift`, `design-house-rules.md`, and the prototype **LabKitProto** (`$P` = `/private/tmp/claude-501/-Users-utkarsh-Documents-AI-Stuff/b53a2b83-9308-4477-a9dd-fedd258cad75/scratchpad/seeds/LabKitProto`). From the prototype: `Package.swift`, `Sources/LabKitUI/{Theme,GlassKnob,Console,Chrome}.swift`, `Sources/LabKitCore/Params.swift`, and `Sources/LabKitFeedback/{Haptics,Synth,AudioRoute}.swift`. Targeted reads: `GyroModel.swift:640-720, 795-822`, Gyre `ContentView.swift:50-62`, `Console.swift:260-356`, `OrbitalsApp.swift`, `ControlsView.swift:85-115`, `spectra-lab/src/{core/state.js:36, ui/controls.js:150-195, ui/app.js:20-30, 50-80, 165-185}`, `rheology-models.md` §1, §3.3–§3.8, and `AVAudioSession.h:181-215` (iPhoneOS27.0 SDK).
- **Citation corrections from that pass.** Gyre's hum law is at `GyroModel.swift:683-698`, not 680-691. Its onset-ignore calls are at `:660` and `:819`, not 653 and 812. Its crackle is at `:712-718`. Every other line cited in §0–§3 matched the source.

**Nothing in Orbitals, Tether, spectra-lab, Spectra, Gyre or any other project was modified.**

**Scratch artefacts** (`$S` = `/private/tmp/claude-501/-Users-utkarsh-Documents-AI-Stuff/b53a2b83-9308-4477-a9dd-fedd258cad75/scratchpad/labkit-ui`):

| Artefact | What it is |
|---|---|
| `$S/Package.swift`, `$S/Sources/LabKitCore/*.swift` | A Swift 6, iOS 27 / macOS 27 package. `LabKitCore` holds the tokens as values (`LabRGB`, `LabGround`, `LabSemantic`, `LabPalette`), `KnobSpec`, `LabFormat`, `PlotAxis`/`PlotSeries`, `Provenance`, `Citation`, `ExperimentEffects`, `Experiment`. |
| `$S/Sources/LabKitUI/*.swift` | `defaultIsolation(MainActor)`. `Theme` (fonts, metrics, motion), `Panels` (`InstrumentPanel`, `Readout`, `ReadoutGrid`, `ProvenanceBadge`, `Eyebrow`), `GlassKnob` (+ `PrecisionSlider`, `KnobArc`, `KnobReadout`, `KnobPrecisionTray`), `Console` (`KnobConsole`, `KnobGrid`, `PrimaryAction`, `CircleAction`), `TopBar` (`TopBar`, `ToolbarGlyph`, `TelemetryCard`, `LabBanner`), `InfoSheet` (`InfoSheet`, `FieldNote`, `LegendRow`, `SourceLink`, `ProvenanceLegend`, `FeedbackSettings`, `PermissionGate`), `LabPlot` (+ Audio Graph descriptor), `LabHaptics`. About 3,200 lines in all. |
| `$S/Sources/LabKitUI/Chips.swift` | Added in the continuation pass: `GlassToggle`, `ChoiceChips` and `GlassTile` as specified in §3.6, including the measured tile-tint fix (§4.5). |
| `$S/Tests/LabKitCoreTests` | 13 XCTests: contrast of every text token on every ground, parameter/data hue separation, linear conversions, knob mapping and nudges, formats, log-axis ticks, gap handling, the experiment-effects sentence. **All pass** (`swift test`, re-run after the palette change in the continuation pass). |
| `$S/Gallery/` | An XcodeGen app (Swift 6, strict concurrency complete). Launch arguments: none for the Rheo-style stage (`-expanded`, `-info`, `-large` vary it); **`-rheo`** for the §9 layout (`-page <fluid\|world\|touch\|signals\|view>`, `-shelf`, `-rheometer`, `-large`), which prints every named frame as `FRAME name x y w h`; **`-components`** for the component catalogue. Builds clean (`** BUILD SUCCEEDED **`, `$S/build-4.log`). |
| `$S/shots/*.png` | Simulator screenshots. Earlier pass (iPhone 17 Pro): `stage-final.png`, `info-large-2.png`, `stage-axxxl-2.png` and `v2-stage-axxxl.png` (Accessibility XXXL). Continuation pass (iPhone 15 Pro Max): `components-15pm.png` (the component gallery), `rheo-15pm-fluid.png`, `rheo-15pm-shelf-rheometer.png`, `rheo-15pm-strip.png`, `rheo-15pm-rheometer-large.png` and `rheo-15pm-axxxl.png` (§9, §10). |
| `$S/frames-*.txt` | The frame logs behind §9's sizes. |
| `$S/contrast.py`, `$S/hues.py`, `$S/palette_check.py`, `$S/rheo_final.py`, `$S/rheo_pages5_hand.py` | WCAG contrast and OKLab hue-distance calculations behind §2. `rheo_pages5_hand.py` checks the five-page Rheo palette (§2.4) and prints `ALL RULES PASS`. |
| `$S/isolation-probe/` | A SwiftPM probe that reproduces the Core Haptics handler isolation hazard (§5.7). |

The scratch code predates the reconciliation with `labkit-from-gyre.md` and with LabKitProto, so a few type names differ from the names this spec settles on. §1.2 gives the scratch rename map; §1.3 gives the prototype reconciliation.

---

## 0. TL;DR (decisions)

1. **Three layers, three materials.** The **stage** is a full-bleed Metal view on a near-black ground (Gyre: pure black). **Instrument surfaces** (numbered panels, readouts, plots, field notes) are opaque phosphor panels: never glass, always monospaced labels (Orbitals). **Chrome** (knobs, buttons, top bar, telemetry card, banners, menus) is Liquid Glass: glass only for controls and navigation, never for data (Orbitals README rule, Gyre practice).
2. **Tokens live in `LabKitCore` as values** (`LabColor`, gamma-encoded sRGB, exactly the numbers the apps pass to `Color(red:green:blue:)`), with `.linearSRGB` / `.linearDisplayP3` for Metal. `LabKitUI` adds `Color` adapters and the environment. A renderer never reuses the encoded numbers directly. Gyre's info-sheet legend does: it passes the renderer's linear `HoloPalette` values to `Color(red:green:blue:)` (`InfoSheet.swift:108-113`), so its swatches are darker than the lines they label (§8, row 23).
3. **Per-app identity = one `LabPalette`**: a ground (phosphor, abyss or night), **one signature accent**, parameter hues keyed by `ParamID`, and data hues keyed by series id. Semantic colours (live/measured phosphor, modelled amber, simulated orange, warning coral, forecast cyan) are **fixed across all apps**. The shared physical quantities keep their Gyre hue in every app: Gravity amber, Time violet, Magnet green, plus Listen, Drives, Gain and Scope.
4. **Rheo palette** (computed, §2.4): ground **abyss** (Gyre's), signature **(1.00, 0.35, 0.65)** "slime pink", with signatureDeep (0.790, 0.270, 0.510) for system-drawn fills. Rheo has 22 knobs on five console pages (Fluid, World, Touch, Signals, View) plus two Rheometer card knobs. Page-mates sit ≥ 0.115 OKLab apart, every parameter hue sits ≥ 0.107 from every fluid data hue, the signature sits ≥ 0.138 from every parameter hue, and every parameter hue reads ≥ 7.0:1 on the panel. `rheo_pages5_hand.py` prints `ALL RULES PASS`. The earlier proposal (1.00, 0.48, 0.70) sat 0.081 from Gyre's Drives hue, and its Memory knob reused Drives' hue exactly (distance 0.000); both are fixed.
5. **Type: the surface decides the design.** Opaque instrument surfaces use `design: .monospaced` (Orbitals, spectra-lab). Glass chrome uses SF Pro with `.monospacedDigit()` (Gyre). In the gallery, monospaced telemetry truncated the card. Quantity symbols (η, γ̇, σ, τ, g, B, T) are **serif italic** (ISO 80000-1) and are never case-transformed. Uppercasing turns η into Η and µ into Μ; spectra-lab's `text-transform: uppercase` already does this to "λ wavelength" (`spectra.css:89`).
6. **One `GlassKnob`, two styles.** `.compact` is the Gyre console knob (84 pt dial, 60 pt glass puck, 230 pt travel, 24 haptic ticks, labelled detents with 0.02 capture, rotary switches, double-tap reset). `.card` is the Orbitals dial card (104 pt dial, 31-tick scale, serif symbol, descriptor, big reading, linear slider). **Both** get Orbitals' keyboard arrows with `@FocusState`, VoiceOver adjustable action, feedback only on real value changes and `@ScaledMetric`. Precision on `.compact` is a long-press **precision tray** (slider plus ± steps), so the console keeps Gyre's height. `labkit-from-gyre.md` §4.5 had declined the slider for that reason. The initialiser keeps the prototype's labelled form, `GlassKnob(spec:value:style:onActive:onPrecision:)` (§1.3).
7. **Haptics: causal by default, continuous by opt-in** (§5). Transients always answer something the user did (Orbitals). The continuous "Feel" channel (Gyre's hum) is a separate, user-toggleable channel. By default it plays only while a cause is live (a finger in the fluid, a shake, a loud room, a moving magnet), and it fades out within 1 s once the cause has been gone for 8 s. Gyre keeps its always-on rotor hum by opting into `.ambient`. One Strength slider (0.2…1, default 0.85) scales both. Everything stops when the app is backgrounded or inactive. The hum also stops while paused, in Low Power Mode, and at thermal state ≥ `.serious`. **For Rheo, the goo's resistance is felt as the hum**: intensity is log-mapped from the stress at the finger (I = 0.15·log₁₀(1 + σ̃/0.1 Pa)), and sharpness rises with the unyielded or jammed fraction around the finger. Water is silent, honey and mayonnaise feel firm and dull (I ≈ 0.46), and jammed oobleck gives a hard, crisp knock (I ≈ 0.76) (§5.3).
8. **Sound: paired cues plus an optional bed** (§6). Each sound cue has a haptic twin of the same semantic class (spectra-lab `detent(kind)`). The sound bed is one continuous voice mapped log-to-pitch from the hero quantity (Rheo: viscosity). **Sound is on by default, persisted, and follows the ring/silent switch** (`.ambient`). With the mic live, synth output is ducked and cues open a 0.2 s onset-ignore window, so Rheo cannot drive its own oobleck monsters. Echo-cancelled input is a runtime check (`isEchoCancelledInputAvailable`), never an assumption.
9. **Provenance is a five-word vocabulary**, shown as word badges, never as colour alone: **measured** (phosphor), **modelled** (amber), **live** (phosphor, the word differs), **simulated** (orange), **illustrative** (muted, dashed outline). It generalises spectra-lab's `table`/`model` badges and Gyre's orange "simulated" rows.
10. **Experiments are data**: title ≤ 22 characters, subtitle with numbers, note, symbol, parameters, effects (an `OptionSet` that writes its own disclosure sentence), sources (`Citation` with a checked date), and provenance. Identity is **derived** by value equality, never stored (Orbitals). Applying one plays `success()` and shows a 6.5 s banner with the note (spectra-lab toast).
11. **Plots**: pure-maths `PlotAxis` (log10 or linear, decade or 1-2-5 ticks, gap-preserving series) in Core. `LabPlot` draws on a SwiftUI `Canvas` at 10 Hz with spectra-lab's glow line (a 3.2× stroke at 0.22 alpha under the core). It carries an `AXChartDescriptor` (Audio Graphs), with log scale where the plot is logarithmic. The rheometer flow curve is log-log σ(γ̇) with dashed iso-viscosity guides (slope 1).
12. **Accessibility** (§4): every control has a label, value, hint, adjustable action, keyboard path and identifier. **Chrome over the stage stops growing at `.accessibility1`** and offers the Large Content Viewer instead. Sheets and panels are never capped. Reduce Motion nils every animation and swaps blur/scale transitions for opacity. Increase Contrast raises hairlines from 0.07 to 0.22. Differentiate Without Colour dashes plot series. **Every text token reaches ≥ 5.35:1 on every ground (verified)**. White text on a prominent signature fill fails everywhere (1.40–2.98:1), so LabKit computes `onSignature`. Measured on the 15 Pro Max simulator: a selected glass tile tinted with a light data hue at Gyre's 0.45 left its white label at 4.25:1, and the 0.30 rule lifts it to 6.7:1 (§4.5).
13. **Copy is British** (Subtext and Cipher, the newest apps) (§7). Usage strings follow "*App* *verb*s … so it can …" plus a privacy sentence. Rheo needs exactly one: the microphone. Every simplification is stated, every number has a provenance word, every experiment names its side effects, and copy names UI by its live label (Gyre's info sheet still says "the Sound page", which no longer exists).
14. **The prototype is the starting code** (§1.3). LabKitProto's names win where it already has them: `ParamSpec(_ id:…)`, `GlassKnob(spec:…)`, `ConsolePage` as a struct, `KnobGrid(_ ids:store:…)`, `LabTopBar(card:actions:)`, `HapticTap` and `HapticEngine`. This spec changes 20 things in it, listed with reasons. The biggest are: `symbol` → `icon`; `ParamFormat` instead of closures; lower-bound quantisation; knob focus as one `KnobFocus` binding; palette-driven tints instead of `LabTheme` colour constants; and an engine that stops when the app is inactive and auto-shuts down.
15. **Rheo's screen** (§9, measured on an iPhone 15 Pro Max simulator, 430 × 932 pt). The full-bleed Metal tank fills x 0–430, y 59–671 and is drawn **life-size** (1 pt = 0.166 mm, so the tank is 71 × 101 mm). Over its headspace floats a glass top bar (y 65–120): a telemetry card, plus Material, Experiments, Layers and Info. The console underneath is 227 pt tall: a five-page `.tabs` picker (31 pt), one row of four knobs (120 pt) and a 50 pt controls row with Refill, Freeze, Rheometer and Reset. The Rheometer is a sheet whose small detent, `.height(231)`, lands exactly on the console (top edge at y 668.9 against the console's 671.3), so the fluid is never covered. Its large detent adds the full flow curve and the Memory and Rebuild card knobs.

---

## 1. How this reconciles with `labkit-from-gyre.md`

### 1.1 What this note adopts unchanged from the Gyre note
- Package layout and products: `LabKitCore`, `LabKitSensors`, `LabKitFeedback`, `LabKitUI` (with `defaultIsolation(MainActor)`), `LabKitRender`, `LabKitShaderTypes`, `labkit-physcheck`; `// swift-tools-version: 6.4`.
- `ParamID`, `ParamSpec`, `ParamValues`, `ParamStore`, `Detent`, `ParamScale`. Modulation (`ModRoute` and related types), `LabEnvironment`, `MotionSource`, `MicListener`, `SynthHost`, `AudioRoute`, `LabRenderHost`, `LabRenderScene`, `LineBatch`, `PostChain`.
- Component names: `GlassKnob`, `KnobArc`, `KnobConsole`, `KnobGrid`, `KnobReadout`, `LevelMeter`, `GlassTile`, `ProminentGlassButton`, `CircleGlassButton`, `LabTopBar`, `ToolbarGlyph`, `TelemetryCard`, `TelemetryRow`, `StatusBanner`, `LabInfoSheet`, `LegendRow`, `CanvasRegion`, `.labChrome()`.
- Haptics injected with `@Environment(\.labHaptics)` (`HapticEngine?`).
- All Gyre token values in its §4.

### 1.2 What this note adds or overrides

| Topic | Gyre note | This note | Why |
|---|---|---|---|
| Colour type | `LabColor(r,g,b)` | Keep the name `LabColor`. Specify it as **gamma-encoded sRGB**, and add `init(hex:)`, `linearSRGB`, `linearDisplayP3`, `luminance`, `contrast(against:)`, `over(_:alpha:)`, `oklab`, `perceptualDistance(to:)` | Contrast and hue-distance checks run as unit tests; Metal needs linear values |
| Where a knob's tint comes from | `ParamSpec.tint: LabColor` (required) | `ParamSpec.tint: LabColor?` (an override). The default resolves through `palette.parameterHues[id]`, then `LabPalette.sharedHues[id]`, then the signature | Enforces the cross-app hue rule in one table; the palette is testable |
| Quantity glyph | `glyph: String?` | Keep `glyph` (serif-italic quantity symbol) and add `glyphSpoken` ("eta") and `descriptor` (one short line for card knobs) | Orbitals `symbolName` (`GlassControls.swift:7, 41`) and `descriptor` (`:8, 43-50`) |
| `ParamSpec.symbol` | SF Symbol name (Gyre `KnobSpec.symbol`) | Rename to **`icon`** | "symbol" means a quantity symbol in Orbitals (`GlassControls.swift:6`) and an SF Symbol in Gyre; one name each removes the ambiguity |
| Format | `format: @Sendable (Double) -> String` | `format: ParamFormat`, an enum of named formats (`number`, `multiplier`, `percent`, `si`, `labels`, `off(threshold:word:then:)`) plus `.custom(@Sendable (Double) -> String)` | The named cases are unit-testable and give one formatting style across apps; `.custom` keeps the escape hatch |
| Quantisation anchor | Gyre `value(at:)` rounds to multiples of `step` from **zero** | Round from the **lower bound** (Orbitals `quantized`, `GlassControls.swift:365-370`) | For a range such as 0.25…3 with step 0.1, zero-anchored steps never reach either end |
| Provenance | none | `ParamSpec.provenance: Provenance` (default `.modelled`) | Feeds the info sheet's badges |
| Linear slider | "not adopted; it would cost console height" (§4.5) | Kept: on `.card` knobs (sheets), and on `.compact` knobs as a long-press precision tray | Orbitals' "every gesture has three alternatives" rule (`design-orbitals.md`, principle 4) with no cost to console height |
| Haptic vocabulary | `HapticTap` constants from Gyre only | Merged Orbitals + Gyre table, with one shared admission clock (§5.4) | Orbitals rate-limits through one clock (`OrbitalHaptics.swift:21, 64-70`) |
| `isAutoShutdownEnabled` | `false` (Gyre `Haptics.swift:23`) | `true` (Orbitals `OrbitalHaptics.swift:135`), because the hum is causal and idles most of the time | Power; inferred, see §5.6 |
| Hum policy | always on while the rotor spins | `HumPolicy.causal(maxIdle: 8)` by default; Gyre opts into `.ambient` | §5 |
| New components | — | `InstrumentPanel`, `Readout`, `ReadoutGrid`, `ProvenanceBadge`, `Eyebrow`, `KnobPrecisionTray`, `ChoiceChips`, `GlassToggle`, `FieldNote`, `SourceLink`, `ProvenanceLegend`, `FeedbackSettings`, `PermissionGate`, `ExperimentMenu`, `ClockReadout`, `LabPlot` (+ `PlotAxis`, `PlotSeries`, `PlotGuide`), `LabFormat` | Orbitals, Tether and spectra-lab patterns |

**Scratch → final rename map:**
- `LabRGB` → `LabColor`
- `KnobSpec` → `ParamSpec`
- `KnobDetent` → `Detent`
- `KnobFormat` → `ParamFormat`
- `LabHaptics` → `HapticEngine`, and `.Pulse` → `HapticTap` constants
- `TopBar` → `LabTopBar`
- `LabBanner` → `StatusBanner`
- `InfoSheet` → `LabInfoSheet`
- `PrimaryAction` → `ProminentGlassButton`
- `CircleAction` → `CircleGlassButton`

### 1.3 Reconciliation with LabKitProto (the code LabKit starts from)

LabKitProto (`$P`, Gyre-derived, Swift 6.4, `// swift-tools-version: 6.4`, `defaultIsolation(MainActor)` on `LabKitUI`) is the seed package. **Rule: where the prototype already names a thing, the prototype's name wins**, unless a row below gives a reason to change it. "Same" means this spec adopts it as written. Every "Change" is a deliberate edit to the prototype, and the reason comes from Orbitals, Tether, spectra-lab or a measurement.

**Adopted unchanged** (the prototype already matches the spec):
- the module split and products (`$P/Package.swift:8-31`);
- `ParamID` (string-backed, `ExpressibleByStringLiteral`; `Params.swift:7-13`);
- `ParamScale`, `ParamValues` and `ParamStore` (`@MainActor @Observable`, `snapshot()` once per frame; `Params.swift:36, 126-176`);
- `Detent(_ value, _ label)` (`:27-34`);
- `KnobArc` (`nonisolated`, `GlassKnob.swift:182-216`);
- `KnobReadout(spec:value:)` (`Console.swift:119-156`);
- `LevelMeter(level:active:label:)` (`:159-186`);
- `CanvasRegion(label:value:hint:actions:onFrame:onTouch:onMagnify:)` (`Chrome.swift:221-277`);
- `LegendRow(_ colour, _ glyph, _ text)` (`:171-184`);
- `@Environment(\.labHaptics)` as `HapticEngine?` (`Theme.swift:126-129`);
- `SynthControls`, `SynthKernel`, `SynthHost` and `RotorHumKernel` (`Synth.swift`);
- `AudioRoute.apply()` and `observeInterruptions` (`AudioRoute.swift`);
- the `@Sendable` + `nonisolated static func wire(...)` handler pattern (`Haptics.swift:73-82`), which is the §5.7 rule.

**Changes to the prototype:**

| # | Prototype (file:line) | This spec | Why |
|---|---|---|---|
| 1 | `LabColor` is r, g, b only (`Params.swift:17-24`); `LabColor.color` in UI (`Theme.swift:6-8`) | Same name. Add `Codable`, `init(hex:)`, `linearSRGB`, `linearDisplayP3`, `luminance`, `contrast(against:)`, `over(_:alpha:)`, `oklab`, `perceptualDistance(to:)`. Keep `.color` and add `Color(_:opacity:)` built with `Color(.sRGB, …)` | Contrast and hue rules become unit tests (§2.4). Metal needs linear values |
| 2 | `ParamSpec.symbol` = SF Symbol (`Params.swift:44`) | Rename to **`icon`** | "Symbol" means the quantity symbol (κ, η) in Orbitals (`GlassControls.swift:6`) |
| 3 | `tint: LabColor`, required (`:45`) | `tint: LabColor?`. `nil` resolves through `palette.hue(for: id)` | One palette table enforces the cross-app hue rules |
| 4 | `glyph: String?` (`:59`) | Same, plus `glyphSpoken: String` and `descriptor: String`. A glyph may use `_` for one subscript ("τ_y"), rendered by `QuantitySymbol` | VoiceOver ("tau y"); Orbitals card descriptor (`GlassControls.swift:8, 43-50`) |
| 5 | `format: @Sendable (Double) -> String` plus static helpers `labels`, `percentOrOff`, `percent` (`:60, 114-122`) | `format: ParamFormat` (§3.3), with `.custom` as the escape hatch | Named formats are `Hashable`, testable and consistent across apps. The scratch `KnobFormat` passes its tests |
| 6 | `value(at:)` quantises from zero, `(v/step).rounded()*step` (`:100`) | Quantise from the lower bound | With 0.25…3 and step 0.1, zero-anchored steps never reach 0.25 (Orbitals `quantized`, `GlassControls.swift:365-370`) |
| 7 | — | Add `provenance: Provenance` (default `.modelled`), `capture(near:radius:)`, `nudged(_:by:coarse:)` and `accessibilityValue(_:)` | §3.3 |
| 8 | `ParamStore.register` keeps an old value when a spec is re-registered (`:149-155`) | Re-registering clamps the stored value into the new range (`values[id] = s.clamp(values[id] ?? s.defaultValue)`) | Rheo swaps a material's Heat range (lava runs at about 1100 °C, kitchen fluids at 0–90 °C). An unclamped value would sit outside the knob |
| 9 | `LabTheme` holds Gyre colour constants: `primaryAction`, `liveGreen`, `phosphor`, `selectedTile`, `timeChip`, `telemetryIcon`, `simulatedFlag` (`Theme.swift:14-27`) | Delete the colour constants. Colours come from `@Environment(\.labPalette)`: `primaryAction` → `signature` (label `onSignature`); `liveGreen`, `phosphor` → `LabSemantic.live`; `selectedTile` → the tile's data hue; `timeChip` → `hue(for: "time")`; `telemetryIcon` → `signature`; `simulatedFlag` → `LabSemantic.simulated`; `secondaryLabel` → white × `tertiaryAlpha` | Per-app identity is one `LabPalette` (§2.4). Gyre's primary tint (0.2, 0.62, 0.85) has 2.98:1 under white |
| 10 | `LabTheme.Font`, `.Spacing`, `.Motion`, `.Knob` (`Theme.swift:36-123`) | Split into `LabFont`, `LabMetrics` (with `LabMetrics.Knob`) and `LabMotion` (with `gated` / `.labAnimation`). Values are unchanged except `minControlHeight` 36 → `minHit` 44 for hit areas (glyph frames stay 36) | Orbitals' 44 pt targets. Reduce Motion gating everywhere (§4.4) |
| 11 | `.labChrome()` = black, dark, status bar and overlays hidden (`Theme.swift:133-139`) | `.labChrome(_ palette: LabPalette)` = `.labPalette(palette)` + `ground.stage` background + `.statusBarHidden()` + `.persistentSystemOverlays(.hidden)` | One root modifier installs the palette, the tint and the dark scheme |
| 12 | `GlassKnob(spec:value:onActive:)` (`GlassKnob.swift:23`) | `GlassKnob(spec:value:style:onActive:onPrecision:)`. Label kept | §3.4: `.card` style, precision tray, boundary latch, release haptic, long press, Shift-coarse keys, `accessibilityValue` with the detent, Reduce Motion scale gate, Large Content Viewer, identifiers |
| 13 | Nudge = 1/20 of the sweep (or ±1 for switches); plays `knobReset` for switches and `knobNudge` (0.4, 0.8) otherwise (`GlassKnob.swift:169-177`) | `spec.nudged(_:by:coarse:)`: step-aware, stops on labelled detents, `.boundary` at the limits; `selection()` under VoiceOver, `.tick` from the keyboard | §3.3 nudge table; Orbitals `GlassControls.swift:198-214` |
| 14 | `ConsolePage(id, title)` struct; `KnobConsole(pages:page:open:store:activeKnob:content:controls:)` (`Console.swift:6-74`) | Keep the struct and add `knobs: [ParamID]`, so the default page content is `KnobGrid(page.knobs)`. Replace `activeKnob: Binding<ParamID?>` with `focus: Binding<KnobFocus>` (`.none / .held(id) / .precision(id)`). `open` becomes optional (`Binding<Bool>?`): `nil` means no fold button. Add `uniformHeight: Bool = true` (every page reserves the tallest page's rows) and `pickerMaxWidth: CGFloat = 320`. **Drop the scratch `ConsolePage` protocol and `KnobSlot`** | The prototype's data-driven pages are simpler than the scratch generic. One focus value cannot show a readout and a tray at once. A fixed console height keeps Rheo's tank floor still (§9) |
| 15 | One `GlassEffectContainer(spacing: 18)` around the page *and* the controls row (`Console.swift:42-64`) | Two containers, one per part | Measured: at AX XXXL, pucks scrolled under the buttons merged into their glass (§3.7) |
| 16 | `GlassTile(title:symbol:subtitle:selected:tint:action:)` with default tint `selectedTile` (`:189-230`) | `GlassTile(title:icon:subtitle:selected:hue:action:)`. Layout unchanged (icon over title, subtitle as the hint). Icon in the hue when unselected, white when selected. Selected tint 0.45, or **0.30 when the hue's luminance is above 0.5** | The data hue names the material. Measured contrast fix (§4.5) |
| 17 | `ProminentGlassButton(_:symbol:action:)` tinted `primaryAction`; `CircleGlassButton(symbol:label:action:)` (`:234-277`) | `ProminentGlassButton(_ title:, icon:, iconOnly: = false, action:)`, tinted `signature` with an `onSignature` label, icon-only at accessibility sizes, plays `.tap`. `CircleGlassButton(_ label:, icon:, tap: = .soft, action:)` with a 44 pt hit area | §3.7 |
| 18 | `LabTopBar(card:actions:)` with one fixed `HStack` (`Chrome.swift:7-26`); `ToolbarGlyph(_ symbol)` (`:29-38`); `TelemetryRow(_ title, _ value, symbol:)` (`:40-50`); `TelemetryCard(expanded:rows:simulatedNote:headline:)` (`:54-102`); `StatusBanner(_:symbol:)` (`:105-123`) | Keep `LabTopBar(card:actions:)` and add the `ViewThatFits` reflow and the `.accessibility1` cap. `ToolbarGlyph(_ icon:, title:)`, where the title feeds the label and the Large Content Viewer. `TelemetryRow(_ title:, icon:, value:, provenance:)`. Keep the `TelemetryCard` `@ViewBuilder` headline and add a standard `TelemetryHeadline(icon:spins:headline:subline:chip:)`; simulated values are coloured by **provenance**, not by a separate note alone. `StatusBanner(_ text:, icon: = "info.circle")` posts a VoiceOver announcement | Measured AX XXXL overflow (§3.8). Provenance words (§3.10) |
| 19 | `LabInfoSheet(title:content:)` with a `List` and no drag indicator; `InfoRow`, `SensorRow`, `KnobDetailRows` (`:127-216`) | `LabInfoSheet(title:startLarge:content:)`: a `ScrollView` of `InstrumentPanel`s on `ground.background`, with a drag indicator. `InfoRow` → `FieldNote` (adds an optional provenance badge). `SensorRow` → `TelemetryRow` inside panel 07. `KnobDetailRows` stays, with glyph, badge and detents added | §3.9 fixed section order |
| 20 | `HapticEngine`: `isAutoShutdownEnabled = false`; no app-state check; a new player per transient; no UIKit fallback; no `selection()` or `success()`; Gyre's `knob…` tap names (`Haptics.swift:21-37, 61-71, 146-165`) | §5: auto-shutdown on; `canPlay` requires `.active`; cached players; UIKit fallback; `selection()` and `success()`; a `humEnabled` Feel toggle with `HumPolicy` and `noteCause()`; Low Power and thermal gating; per-tap `minGap` values; semantic tap names with the Gyre names kept as deprecated aliases (§5.4) | Orbitals `OrbitalHaptics.swift` |

That is **20 changes**. Each is small; none alters a Gyre token value except #9's primary-button colours and #10's 44 pt hit area. Gyre therefore looks the same when ported, with two exceptions. Its prominent buttons ("Relaunch", "Place", Gyre `Console.swift:179, 206`) turn the AccentColor cyan with a dark `onSignature` label. Its secondary circles gain 44 pt hit areas.

---

## 2. Tokens: "glass over phosphor"

### 2.1 The layer model (read this first)

| Layer | What lives there | Material | Type design | Colour family |
|---|---|---|---|---|
| **Stage** | Metal canvas: the fluid tank, the gyroscope, the wave scope | Opaque, full-bleed; ground `stage` | Canvas labels only (`LabCanvasLabel`, monospaced, uppercase, tracking 0.6) | App data hues and the renderer palette (linear) |
| **Instrument surfaces** | `InstrumentPanel`, `Readout`, `LabPlot`, field notes, coordinate tables | **Opaque** `panel` fill + white hairline 0.07; plots on `plot` | `design: .monospaced` for labels, numbers and panel headers; body text in SF Pro | Semantic colours (amber values, phosphor live) + muted/dim greys |
| **Chrome** | Knobs, console, buttons, chips, top bar, telemetry card, banners, menus, sheets' toolbars | **Liquid Glass** (`glassEffect`, `.glass`, `.glassProminent`) inside `GlassEffectContainer` | SF Pro; `.monospacedDigit()` on numbers | Signature (primary and selected only), parameter hues (knobs), white |

Rules:
1. **Glass is never a data surface.** Plots and readout panels are opaque so that numbers keep fixed contrast (Orbitals README; `OrbitTheme.swift:38-39` uses a solid panel). A readout that must float over the stage goes in the `TelemetryCard`, which is glass and is therefore treated as chrome: SF Pro digits, not monospaced.
2. **Selected or primary state = signature.** Everything else in chrome is white on glass (Gyre `CircleGlassButton` glyphs; Orbitals tints secondary buttons phosphor, `InstrumentControlSheet.swift:100`, a contradiction resolved in §8).
3. **Parameter hue = which knob.** A knob, its readout card, its info-sheet entry and its modulation route all use one hue. Parameter hues never colour data (Orbitals comment, `OrbitTheme.swift:15`).
4. **Data hue = which thing.** A fluid, a channel or a source keeps its hue everywhere: in the tank, in the plot legend, in chips. Data hues never colour knobs.

### 2.2 Grounds

Each app picks one ground. Values are gamma-encoded sRGB in 0…1.

| Token | **phosphor** (Orbitals, spectra-lab) | **abyss** (Gyre, Rheo) | **night** (Tether) |
|---|---|---|---|
| `stage` | (0.025, 0.045, 0.040) `OrbitTheme.swift:4` | **(0, 0, 0)** Gyre `ContentView.swift:42` | (0.025, 0.031, 0.065) `TetherTheme.swift:4` |
| `background` (sheets, launch) | (0.025, 0.045, 0.040) `OrbitTheme.swift:4`; = spectra `--bg` #060b0a | (0.006, 0.012, 0.030) Gyre `LaunchBackground` asset | (0.025, 0.031, 0.065) |
| `panel` | (0.065, 0.095, 0.083) `OrbitTheme.swift:5`; ≈ spectra `--panel` #111814 | (0.050, 0.060, 0.090) *proposal* | (0.065, 0.073, 0.130) `TetherTheme.swift:5` |
| `plot` | #040807 = (0.016, 0.031, 0.027) `spectra.css:6`, `draw.js:3` | (0.008, 0.014, 0.032) *proposal* | (0.015, 0.020, 0.045) *proposal* |
| `muted` (secondary text, panel titles, axis labels) | (0.61, 0.71, 0.65) `OrbitTheme.swift:12`; = spectra `--muted` #9cb5a6 | (0.62, 0.68, 0.78) *proposal* | (0.64, 0.65, 0.80) *proposal* |
| `dim` (tertiary, minor tick labels, hints) | #7e978a = (0.494, 0.592, 0.541) `spectra.css:12` | (0.50, 0.56, 0.66) *proposal* | (0.52, 0.53, 0.68) *proposal* |
| `hairlineAlpha` | 0.07 `OrbitTheme.swift:39`, `spectra.css:7` | 0.07 | 0.07 (Tether strokes with `accent × 0.16`, `TetherTheme.swift:18`; LabKit uses white 0.07 everywhere) |

Proposals follow two rules. Each proposed grey keeps the ground's hue cast: green for phosphor, blue for abyss, violet for night. Each proposal also meets the contrast floor below.

### 2.3 Semantic colours (identical in every app)

| Token | Value | Meaning | Source |
|---|---|---|---|
| `live` | (0.40, 0.96, 0.56) | RUN, live signal, level meter, **measured** and **live** provenance, canvas tags | `OrbitTheme.phosphor` `:6`; spectra `--phosphor` #66f58f; spectra `.badge.table` `spectra.css:96` |
| `value` | (1.00, 0.75, 0.37) | Default readout number, HOLD, **modelled** provenance, experiment menu | `OrbitTheme.amber` `:7`; spectra `--amber` #ffbf5e; `.badge.model` `:97` |
| `forecast` | (0.57, 0.89, 1.00) | Predicted paths, forecasts, "what if" overlays | `OrbitTheme.cyan` `:8` |
| `warning` | #ff8f6b = (1.00, 0.561, 0.420) | Limits, hard stops, failures, thresholds (Rheo: the jamming threshold, a yield line being crossed) | spectra `--ionizing` `spectra.css:20` |
| `simulated` | (1.00, 0.624, 0.039) | Values standing in for a sensor | Gyre `.orange` at `TopBar.swift:147` (systemOrange, dark appearance) |
| `ink` | white | Primary text on any ground | — |
| `bodyAlpha` | 0.85 | Field-note body | `TelemetryView.swift:181` |
| `secondaryAlpha` | 0.75 | Knob descriptor | `GlassControls.swift:46` |
| `tertiaryAlpha` | 0.62 | Compact knob title | Gyre `GlassKnob.swift:28` |

**Contrast floor (verified, `$S/Tests` `testTextContrastOnAllGrounds` + `contrast.py`).** Every token above, used as text, reaches **≥ 4.5:1 on `stage`, `background`, `panel` and `plot` of all three grounds**. The weakest pairs are `dim` on the night panel at 5.35:1 and `dim` on the phosphor panel at 5.73:1. `tertiary` white 0.62 is ≥ 7.45:1 everywhere.

| On → | phosphor bg | phosphor panel | black | plot #040807 |
|---|---|---|---|---|
| white 0.85 | 14.18 | 13.14 | 14.84 | 14.38 |
| white 0.62 | 7.74 | 7.45 | 7.85 | 7.77 |
| muted | 9.00 | 8.20 | 9.57 | 9.17 |
| dim | 6.29 | 5.73 | 6.68 | 6.41 |
| live | 14.11 | 12.86 | 15.00 | 14.38 |
| value | 12.13 | 11.05 | 12.89 | 12.36 |
| warning | 8.84 | 8.05 | 9.39 | 9.01 |

**Filled surfaces fail with white text.** Measured white-on-fill contrast:
- phosphor 1.40:1 (this is Orbitals' `.glassProminent` Play button);
- amber 1.63:1;
- Gyre's prominent tint (0.2, 0.62, 0.85) 2.98:1;
- Rheo signature 2.90:1;
- Tether violet 2.50:1.

Hence two derived tokens:
- `onSignature`: the label colour for prominent buttons and selected chips. It is white when white reaches 4.5:1 on the fill, otherwise the ground's `background`. Ground text on the fill measures 6.6–14.1:1.
- `signatureDeep`: the signature darkened in linear light, hue kept, until white reaches 4.5:1 (target luminance 0.1833). It is the tint for **system-drawn** fills whose glyph colour LabKit can't set: iOS 27 draws the toolbar `confirmationAction` "Done" as a filled tint circle with a white checkmark, visible in `$S/shots/info-large-2.png`, and `Toggle` tracks.

### 2.4 Per-app accent mechanism

```swift
// LabKitCore
public struct LabColor: Sendable, Hashable, Codable {           // gamma-encoded sRGB, 0…1
  public var r, g, b: Double
  public init(_ r: Double, _ g: Double, _ b: Double)
  public init(hex: String)                                        // "#RRGGBB" (spectra-lab tokens)
  public var linearSRGB: SIMD3<Float> { get }                     // IEC 61966-2-1 EOTF
  public var linearDisplayP3: SIMD3<Float> { get }                // matrix below
  public var luminance: Double { get }                            // WCAG 2.x
  public func contrast(against: LabColor) -> Double               // (L1+0.05)/(L2+0.05)
  public func over(_ ground: LabColor, alpha: Double) -> LabColor // SwiftUI opacity compositing
  public var oklab: SIMD3<Double> { get }                         // Ottosson 2020
  public func perceptualDistance(to: LabColor) -> Double          // Euclidean OKLab
  public static let white, black: LabColor
}

public struct LabGround: Sendable, Hashable, Codable {
  public var name: String
  public var stage, background, panel, plot, muted, dim: LabColor
  public var hairlineAlpha: Double
  public static let phosphor, abyss, night: LabGround
}

public enum LabSemantic {                                          // nonisolated
  public static let live, value, forecast, warning, simulated, ink: LabColor
  public static let bodyAlpha = 0.85, secondaryAlpha = 0.75, tertiaryAlpha = 0.62
}

public struct DataHue: Sendable, Hashable, Identifiable { public var id: String; public var name: String; public var colour: LabColor }

public struct LabPalette: Sendable, Hashable {
  public var app: String
  public var ground: LabGround
  public var signature: LabColor                     // global .tint, AccentColor asset, panel numbers, primary action
  public var parameterHues: [ParamID: LabColor]      // app-specific knobs
  public var dataHues: [DataHue]                     // ordered: legend order
  public var onSignature: LabColor { get }           // label on signature fills
  public var signatureDeep: LabColor { get }         // tint for system-drawn filled controls
  public func hue(for id: ParamID) -> LabColor       // parameterHues[id] ?? Self.sharedHues[id] ?? signature
  public func data(_ id: String) -> LabColor
  /// Quantities that mean the same thing in every app keep one hue (Gyre Knobs.swift tints).
  public static let sharedHues: [ParamID: LabColor] = [
    "gravity": LabColor(1.00, 0.70, 0.28), "time": LabColor(0.72, 0.55, 1.00),
    "magnet":  LabColor(0.55, 1.00, 0.45), "listen": LabColor(0.35, 1.00, 0.60),
    "drives":  LabColor(1.00, 0.62, 0.85), "gain":  LabColor(0.45, 0.85, 1.00),
    "scope":   LabColor(0.40, 1.00, 0.55), "air":   LabColor(0.55, 0.75, 1.00),
  ]
  public static let orbitals, gyre, tether, rheo: LabPalette
}
```

```swift
// LabKitUI
extension Color { public init(_ c: LabColor, opacity: Double = 1) }   // Color(.sRGB, red:green:blue:opacity:)
extension EnvironmentValues { @Entry public var labPalette: LabPalette = .orbitals }
extension View {
  /// Root of every app: palette + forced dark + signature tint (OrbitalsApp; TetherApp .tint(violet)).
  public func labPalette(_ p: LabPalette) -> some View {
    environment(\.labPalette, p).preferredColorScheme(.dark).tint(Color(p.signature))
  }
}
```

The signature must also exist as the `AccentColor` asset, and the ground's `background` as the `LaunchBackground` asset. A widget or Live Activity must read the asset, not the Swift constant, because WidgetKit archiving drops programmatic dynamic colours (house rule 10).

**Palette rules (enforced by tests):**

| Rule | Threshold | Test |
|---|---|---|
| Signature, every parameter hue, `live`, `value`, `warning` as text on `panel` | ≥ 4.5:1 | `testSignatureAndParameterHuesReadOnPanels` |
| Data hues on `panel` (graphical objects, WCAG 1.4.11) | ≥ 3:1 | same |
| Parameter hue vs data hue, same app | OKLab ≥ 0.10 | `testParameterAndDataHuesAreDistinct` |
| Parameter hues on the **same console page or sheet** | OKLab ≥ 0.08 (aim ≥ 0.12) | to add: the palette needs page groups, which `ConsolePage.knobs` (§1.3 #14) provides; script `rheo_pages5_hand.py` |
| Signature vs every parameter hue | OKLab ≥ 0.10 | to add |
| `onSignature` on signature | ≥ 4.5:1 | yes |
| White on `signatureDeep` | ≥ 4.5:1 (4.49 tolerance) | yes |

Gyre fails the same-page rule against itself. Listen (0.35, 1.0, 0.6) and Scope (0.4, 1.0, 0.55) are 0.015 apart and share the Signals page; Magnet and Scope are 0.033 apart. Titles and icons still tell them apart, so this is not a blocker. It does mean the shared-hue table is a **convention for identity across apps**, not a guarantee of distinctness. LabKit's rule applies to new palettes.

**The four palettes** (signature; parameter hues; data hues):

| App | Ground | Signature | Parameter hues | Data hues |
|---|---|---|---|---|
| Orbitals | phosphor | live (0.40, 0.96, 0.56) | κ speed (1, 0.69, 0.30) · α amplitude (0.38, 0.70, 1) · ν frequency (0.35, 0.94, 0.69) · φ phase (0.78, 0.60, 1) (`OrbitTheme.swift:16-19`) | Cyan (0.10, 0.93, 1) · Magenta (1, 0.18, 0.78) · Yellow (1, 0.91, 0.18) (`:9-11`) |
| Spectra (for the native port) | phosphor | live | λ follows the wave colour · E₀ #61b3ff · θ mint #59f0b0 · δ rose #ff8fb8 · φ violet #c799ff · T, N amber (`controls.js:131-137`) | Sources A/B/C #66f58f, #ff8fb8, #8fd3ff (`draw.js:7`); E #61b3ff, B #ff5c7a, S #ffbf5e |
| Gyre | abyss | (0.38, 0.88, 1.00) `AccentColor` | the 17 knob tints (`labkit-from-gyre.md` §4.1) | HoloPalette (linear) |
| Tether | night | violet (0.67, 0.58, 1) | — | Utkarsh mint (0.50, 1, 0.83) · partner rose (1, 0.62, 0.78) |
| **Rheo** | abyss | **(1.00, 0.35, 0.65)**; deep (0.790, 0.270, 0.510) | see below | see below |

Spectra has two parameter hues that collide with its own data hues: δ rose #ff8fb8 equals source B #ff8fb8, and E₀ #61b3ff equals the E-field trace. That breaks the Orbitals rule. Flag it to the Spectra port.

**Rheo parameter hues by console page** (`$S/rheo_pages5_hand.py`, which prints `ALL RULES PASS`; minimum same-page OKLab distance in brackets; every hue reads ≥ 7.03:1 on the abyss panel). §9 gives each knob's range and detents.

| Page | Knob (ParamID) | Glyph | Hue | Hue source |
|---|---|---|---|---|
| **Fluid** [0.134] | Yield (`yield`) | τ_y | (0.30, 1.00, 0.82) | Gyre Inertia |
| | Consistency (`consistency`) | K | (0.36, 0.86, 1.00) | Gyre Motor |
| | Flow index (`index`) | n | (0.78, 0.60, 1.00) | Orbitals φ |
| | Packing (`packing`, Wyart–Cates φ) | φ | (1.00, 0.86, 0.35) | the earlier Memory gold, moved |
| **World** [0.120] | Gravity (`gravity`) | g | (1.00, 0.70, 0.28) | shared |
| | Heat (`heat`) | T | (1.00, 0.50, 0.30) | Gyre Friction |
| | Magnet (`magnet`) | B | (0.55, 1.00, 0.45) | shared |
| | Time (`time`) | — | (0.72, 0.55, 1.00) | shared |
| **Touch** [0.172] | Finger (`finger`, probe radius) | r | (0.55, 0.90, 1.00) | new ("ice"); (0.75, 0.90, 1) sat 0.077 from oobleck white |
| | Stir (`stir`) | ω | (0.82, 0.95, 0.40) | new ("lime") |
| | Shake (`shake`, vibrating floor) | a | (0.62, 0.62, 1.00) | earlier pass |
| | Rate (`rate`, floor frequency) | f | (1.00, 0.74, 0.58) | new ("peach") |
| **Signals** [0.115] | Listen (`listen`) | — | (0.35, 1.00, 0.60) | shared |
| | Drives (`drives`, rotary switch) | — | (1.00, 0.62, 0.85) | shared |
| | Gain (`gain`) | — | (0.45, 0.85, 1.00) | shared |
| | Band (`band`, mic band centre) | f | (0.85, 0.80, 1.00) | new ("lilac"); gold would have duplicated Packing exactly |
| **View** [0.186] | Glow (`glow`, stress light) | — | (0.25, 0.95, 1.00) | new ("aqua") |
| | Grain (`grain`, particles) | — | (0.95, 0.55, 1.00) | new ("orchid"); (0.95, 0.85, 0.60) sat 0.080 from oobleck |
| | Tracers (`tracers`, dye lines) | — | (0.72, 1.00, 0.25) | new ("chartreuse") |
| | Depth (`depth`, shading) | — | (0.45, 0.60, 1.00) | new ("cobalt") |
| **Rheometer cards** [0.301; 0.132 with the Fluid knobs in the same sheet] | Memory (`memory`, relaxation time) | λ | (1.00, 0.60, 0.50) | new ("coral"); lavender sat 0.078 from Flow index |
| | Rebuild (`rebuild`, thixotropic build-up time) | θ | (0.60, 1.00, 0.35) | new ("spring") |

Scripted searches that maximise distance push hues to the gamut edges, giving pure green (0, 0.95, 0) and magenta (1, 0.25, 1). They also drift to near-floor contrast (4.5:1 muds). Every new hue was therefore **hand-picked inside the Gyre knob family** (OKLab L 0.70–0.92, chroma ≥ 0.07) and then checked. **Cross-page near-duplicates remain** and are allowed: Consistency and Gain are 0.017 apart, Magnet and Rebuild 0.022, Tracers and Rebuild 0.031. These pairs never share a page or a sheet, and their titles and icons differ. A test should list them so a new knob does not quietly add a same-page clash.

**Rheo data hues** (fluid identity; parameter-vs-data minimum 0.107, data-vs-data minimum 0.132; contrast on panel in brackets):

| Fluid | Colour |
|---|---|
| Oobleck (cornstarch white) | (0.93, 0.92, 0.86) [15.9] |
| Ketchup | (0.92, 0.22, 0.20) [4.67] |
| Slime (borax blue) | (0.15, 0.40, 1.00) [4.03]. Green is taken by Magnet and Listen. |
| Honey (the Newtonian control) | (0.75, 0.45, 0.10) [5.17]. Bright amber is taken by Gravity and by "modelled". |
| MR fluid (iron grey) | (0.60, 0.62, 0.72) [7.22] |

Further fluids (toothpaste, mayonnaise, yogurt, quicksand, silly putty, paint) must pass the same script before shipping. The tank's rendered fluid colour is its data hue, converted to linear in the renderer. Variation by state (shear-lit, jammed, magnetised) belongs to the shader as lightness and specular changes, never a hue swap, so the legend stays true.

Metal conversion (sRGB D65 → Display P3 D65, both linear; computed from the primaries in `contrast.py`):
```
| 0.822462  0.177538  0        |
| 0.033194  0.966806  0        |
| 0.017083  0.072397  0.910520 |
```

### 2.5 Typography

All styles are Dynamic Type text styles. Fixed sizes are allowed only for canvas labels, through `@ScaledMetric` with a cap.

| Role (`LabFont`) | Font | Case / tracking | Colour | Source |
|---|---|---|---|---|
| `eyebrow` | `.system(.caption2, design: .monospaced)` | UPPER, 2; after a 5×5 signature `Circle` | muted | `DashboardView.swift:95-97` |
| `panelHeader` | `.system(.caption, design: .monospaced).weight(.medium)` | number in signature; title UPPER, 2 | muted | `OrbitTheme.swift:28-34` |
| `readoutLabel` | `.system(.caption2, design: .monospaced)` | UPPER word, **symbol kept as typed** | muted | `OrbitTheme.swift:49` |
| `readoutValue` | `.system(.callout, design: .monospaced).weight(.medium)` + `.monospacedDigit()` + `.contentTransition(.numericText())` | — | `value` (amber) or a data hue | `OrbitTheme.swift:51-53` |
| `readoutDetail` | `.system(.caption2, design: .monospaced)` | — | dim | spectra `.readout .s` `spectra.css:91` |
| `knobTitle` (compact) | `.caption2.weight(.semibold)` | UPPER, 0.6 | white 0.62 | Gyre `GlassKnob.swift:24-28` |
| `knobValue` (compact) | `.caption.weight(.medium).monospacedDigit()`, `.numericText(value:)` | — | white | Gyre |
| `cardTitle` | `.subheadline.weight(.semibold)` | sentence | parameter hue | `GlassControls.swift:35-37` |
| `quantitySymbol` | `.system(.title3, design: .serif).weight(.semibold).italic()` | never transformed | parameter hue | Orbitals `:31` is upright; italic per ISO 80000-1 |
| `dialReading` | `.system(.title3, design: .monospaced).weight(.semibold)`, `lineLimit(1)`, `minimumScaleFactor(0.7)` | — | parameter hue | `GlassControls.swift:88-94` |
| `telemetryHeadline` / `Subline` | `.subheadline.weight(.semibold).monospacedDigit()` / `.caption.monospacedDigit()` | — | white / secondary | Gyre `TopBar.swift:111-117` |
| `button` | `.subheadline.weight(.semibold)` | sentence | — | both |
| `toolbarIcon` | `.body.weight(.semibold)` in 42×44 | — | white | Gyre |
| `legendGlyph` | `.system(.headline, design: .serif).italic()`, width 22 | — | data or renderer hue | Gyre `InfoSheet.swift:111-113` |
| `body` (info sheet) | `.callout`; field-note body `.subheadline` | sentence | white 0.85 | Gyre `:14`; Orbitals `TelemetryView.swift:181` |
| `caption` | `.caption` | sentence | muted | Orbitals, under every control group |
| `hint` | `.footnote` | sentence | secondary | Gyre readout hint |
| `canvasLabel` | `.system(size: min(scaled 9, 14), weight: .medium, design: .monospaced)` | UPPER, 0.6 | live × 0.8 or muted | Orbitals 9 pt fixed; spectra `.tag` 10 px, `.hint` 9.5 px |

Number formatting (`LabFormat`, Core; locale-independent because readouts are instruments and parity vectors compare strings):
- `fixed(v, precision:)`: clamp to 0…6 fraction digits (Orbitals `GlassControls.swift:372-376`). Never show "−0.00". Use U+2212 for negatives.
- `sig3(x)`: ≥ 100 → 0 dp; ≥ 10 → 1 dp; ≥ 1 → 2 dp; else 3 significant figures (spectra `spectrum.js` `sig3`).
- `scientific(v, unit:, digits: 2)`: "1.23×10⁻⁴ s" (spectra `sci`).
- `engineering(v, unit:)`: SI prefix with sig3, "12.4 mPa·s", "2.45 GHz"; falls back to scientific outside 10⁻¹⁵…10²¹.
- `powerOfTen(k)`: "10⁻³", for log axes.
- Units: a normal space between number and unit; a middle dot inside compound units (Pa·s, Pa·sⁿ); superscript exponents (s⁻¹); multiplier prefix "×0.25"; percent without a space ("46%"); degrees Celsius "20 °C" (SI space). The universal separator is " · " (Orbitals).

### 2.6 Shape, spacing and size

| Token (`LabMetrics`) | Value | Source |
|---|---|---|
| `visualizationRadius` | 28 | `VisualizationPanel` |
| `panelRadius` | 26 | `OrbitTheme.swift:38`; Tether `Surface` 26; spectra `.panel` 26px |
| `glassCardRadius` | 22 | Gyre cards and readouts; Orbitals AR card |
| `knobCardRadius`, `canvasRadius` | 20 | `GlassControls.swift:113` |
| `tileRadius` | 18 | Gyre tiles; Subtext cards |
| `chipRadius` | 14 | Orbitals motion chips |
| `gutter` / `gutterWide` | 16 / 26 (wide when width > 850) | `design-orbitals.md` spacing |
| `wideBreakpoint` | 850 (60% stage column + 400 pt side column) | Orbitals; spectra uses 980 px |
| `sectionSpacing` / `columnSpacing` | 22 / 18 | Orbitals |
| `panelPadding` / `panelSpacing` | 20 / 18 | `OrbitTheme.swift:27, 37` |
| `minHit` | **44** | Orbitals sliders, toggles, chips, menus; Gyre used 36 |
| `glyphFrame` | 36 (glass circle glyph frame inside a 44 hit area) | Gyre circle buttons |
| `toolbarIcon` | 42 × 44 | Gyre |
| Console | outer `VStack` 12, page `VStack` 10, `Grid(h: 2, v: 10)`, controls `HStack` 10, picker `maxWidth` 320, readout `offset(y: -78)`, tray `offset(y: -128)` | Gyre `Console.swift` |
| Top bar | `.padding(.horizontal, 16).padding(.top, 6)`; `GlassEffectContainer(spacing: 12)` | Gyre |
| Telemetry card | padding 14 × 11; grid 14 × 6 | Gyre |
| Knob (compact) | frame 84, arc radius 40, puck 60, detent dot 3 at r − 1 | Gyre §4.5 |
| Knob (card) | dial 104, arc 84, puck 70, card padding h 8 / v 14 | `GlassControls.swift:53, 151, 168, 111-112` |
| `stageChromeTypeCap` | `DynamicTypeSize.accessibility1` | §4 (measured) |

### 2.7 Motion

Every animation goes through `LabMotion.gated(_:reduceMotion:)` or `.labAnimation(_:value:)`, which returns `nil` under Reduce Motion (Orbitals, `GlassControls.swift:119`).

| Token | Value | Use | Source |
|---|---|---|---|
| `select` | `.smooth(duration: 0.25)` | view and tab selection, scroll-to | Orbitals |
| `action` | `.smooth(duration: 0.2)` | button actions, chip selection | Orbitals `GlassControls.swift:339` |
| `grabCard` | `.smooth(duration: 0.14)` | card-knob stroke and scale on grab | Orbitals `:119` |
| `grab` | `.spring(duration: 0.25, bounce: 0.4)` | compact puck scale 1.07 | Gyre |
| `page` | `.spring(duration: 0.35, bounce: 0.2)` | console page change | Gyre |
| `readout` | `.spring(duration: 0.3, bounce: 0.25)` | knob readout card | Gyre |
| `expand` | `.spring(duration: 0.4, bounce: 0.25)` | telemetry card | Gyre |
| `fold` | `.spring(duration: 0.45, bounce: 0.2)` | console fold, AR | Gyre |
| `reset` | `.smooth(duration: 0.5)` | knob or page reset | Gyre |
| `experiment` | `.smooth(duration: 0.6)` | applying an experiment | Gyre |

Transitions:
- pages use `.blurReplace`;
- the console deck uses `.blurReplace.combined(with: .scale(0.9, anchor: .bottom))`;
- the readout uses `.opacity` + scale 0.92.

Under Reduce Motion every transition becomes `.opacity`, `symbolEffectsRemoved(true)` applies, and `.transaction { $0.animation = nil }` is set on buttons (Orbitals `GlassControls.swift:355-356`). `Transition` and `AnyTransition` are distinct types: wrap with `AnyTransition(.blurReplace)` when branching (compiled in `$S/Sources/LabKitUI/Console.swift`).

Live numbers use `.contentTransition(.numericText(value:))`. Toggled icons use `.contentTransition(.symbolEffect(.replace))`.

### 2.8 Material policy (Liquid Glass)

| Element | API | Tint |
|---|---|---|
| Knob puck | `.glassEffect(.regular.tint(hue.opacity(held ? 0.32 : 0.10)).interactive(), in: .circle)` (Gyre). Card knobs use `0.22` (Orbitals `:169`) | parameter hue |
| Primary action | `.buttonStyle(.glassProminent)` + `.tint(signature)` + label `onSignature` | signature |
| Secondary action | `.buttonStyle(.glass)`, glyph white | none |
| Toolbar group | `HStack` in `.glassEffect(.regular.interactive(), in: .capsule)` | none |
| Telemetry, readout card, banner | `.glassEffect(.regular, in: .rect(cornerRadius: 22))` / `.capsule` | none |
| Chips (choice) | `.glassEffect(.regular.tint(dataHue.opacity(0.12)).interactive(), in: .rect(cornerRadius: 14))`; selected chips use a filled data hue with `onFill` text | data hue |
| Grouped controls | `GlassEffectContainer(spacing:)`: console 18, top bar 12, reset bar 12, tile shelf 4 | — |
| Panels, plots, sheets' content | **not glass**: opaque `panel` / `plot` / `background` | — |

---

## 3. Component catalogue

Conventions:
- Every view is `public` in `LabKitUI` (`defaultIsolation(MainActor)`) and reads `@Environment(\.labPalette)` and `@Environment(\.labHaptics)`.
- Every interactive view has an `accessibilityIdentifier` from the scheme in §4.7.
- "Source" lists what each part merges. The scratch implementation in `$S/Sources/LabKitUI` compiles and renders (§10).

### 3.1 `InstrumentPanel`: the numbered phosphor card

```swift
public struct InstrumentPanel<Content: View, Accessory: View>: View {
  public init(_ number: String, _ title: String, caption: String? = nil,
              @ViewBuilder accessory: () -> Accessory = { EmptyView() },
              @ViewBuilder content: () -> Content)
}
```

| Part | Spec | Source |
|---|---|---|
| Container | `VStack(alignment: .leading, spacing: 18)`, `.padding(20)`, `panel` fill in `.rect(cornerRadius: 26)`, white hairline `hairlineAlpha` (0.22 under Increase Contrast) | `OrbitTheme.swift:22-41` |
| Header | `HStack(spacing: 8)`: number in signature, `title.uppercased()` with tracking 2, `Spacer`, accessory slot (Align, Expand, a provenance badge); font `panelHeader`, colour muted | Orbitals + `VisualizationPanel` header |
| Header accessibility | one element, `.isHeader`, label "\(title), panel \(number)" | new: Orbitals' header is unlabelled |
| Caption | muted `.caption` sentence after the content. Every panel ends with one (Orbitals habit) | Orbitals |
| Numbering | `"01"…"09"` for ordered sections; a symbolic code for a quantity group (`"XYZW"`, `"T"`, Rheo `"η"` or `"σ·γ̇"`) | `design-orbitals.md` |

Tether's `Surface` is the same card with a gradient fill and an accent stroke at 0.16 (`TetherTheme.swift:12-20`). LabKit uses the Orbitals form: solid fill and white hairline. One card style makes every app's panels read the same.

### 3.2 `Readout`, `ReadoutGrid`, `ProvenanceBadge`

```swift
public struct Readout: View {
  public init(_ title: String, symbol: String = "", value: String, detail: String? = nil,
              colour: LabColor? = nil, provenance: Provenance? = nil, spokenValue: String? = nil)
}
public struct ReadoutGrid<Content: View>: View { public init(columns: Int? = nil, @ViewBuilder content: () -> Content) }   // nil = adaptive
public struct ProvenanceBadge: View { public init(_ provenance: Provenance) }
```

- **Readout layout:** `VStack(alignment: .leading, spacing: 5)`.
  - Label row: an optional serif-italic `symbol` in muted `.caption`, then the UPPERCASE word in `readoutLabel`. Only the word is uppercased.
  - Value: `readoutValue` in `value` amber by default (Orbitals `OrbitTheme.swift:46`), or the series' data hue. spectra-lab colours each readout by quantity (`app.js:143-148`).
  - Footer, only when present: provenance badge, then the detail line in dim. The badge goes on **its own line under the value**. Beside a 96 pt title it wrapped into syllables in the gallery.
- **Readout accessibility:** `.accessibilityElement(children: .ignore)`, label = title, value = `[spokenValue ?? value, detail, provenance.badge].joined(", ")`. Use `spokenValue` whenever the visible string has superscripts or symbols VoiceOver mangles ("3.20 s⁻¹" → "3.2 per second").
- **ReadoutGrid:** `LazyVGrid` with `.adaptive(minimum: 132)`, or 220 at accessibility sizes, spacing 10. spectra-lab `.readouts` uses auto-fit with a 96 px minimum (`spectra.css:87`). `columns:` fixes the count; the Rheometer's large detent uses 3, and its strip uses a single column (§9).
  - **Cells align to the top** (`alignment: .topLeading`). Measured: in a default `Grid` row, a readout carrying a badge is taller and the row centres its neighbours, so the labels no longer share a baseline (`$S/shots/rheo-15pm-rheometer-large.png`).
- **ProvenanceBadge:** the word in UPPERCASE `.caption2` monospaced, tracking 1, in the provenance tint. It is `lineLimit(1).fixedSize()`, and any row of several badges (`ProvenanceLegend`) is a wrapping flow layout. Measured: five badges in one `HStack` across a 366 pt panel hyphenated "MEA-SURED" and "ILLUSTRA-TIVE" onto two lines (`$S/shots/components-15pm.png`). Hairline capsule at 0.45 of the tint, **dashed [3, 2] for `illustrative`**, padding 6 × 2. It is a single accessibility element: label = the word, hint = `Provenance.explanation`. spectra `.badge` uses `border-radius 8px`, 9.5 px, letter-spacing 1 (`spectra.css:95-98`).
- **Refresh rate:** readouts update at **10 Hz**, never per frame (Orbitals `refreshReadouts`, Gyre telemetry throttle, spectra `slowTick`).

### 3.3 `ParamSpec`: range, mapping, quantisation, detents

This is `labkit-from-gyre.md` §3.1's `ParamSpec` (LabKitProto `Params.swift:40-123`) with the §1.2 and §1.3 overrides. The initialiser keeps the prototype's order, `ParamSpec(_ id:, title:, icon:, …)`. Compiled as `KnobSpec` in `$S/Sources/LabKitCore/KnobSpec.swift` and tested.

```swift
public struct Detent: Sendable, Hashable, Codable { public var value: Double; public var label: String }

public enum ParamFormat: Sendable {
  case number(precision: Int, unit: String)          // "1.23 g"; precision clamped 0…6
  case multiplier(precision: Int)                     // "×0.25"
  case percent                                        // "46%" of 0…1
  case si(unit: String)                               // "12.4 mPa·s"
  case labels([String])                               // rotary-switch position names
  indirect case off(threshold: Double, word: String, then: ParamFormat)   // "Off" at or below threshold
  case custom(@Sendable (Double) -> String)
  public func string(_ v: Double) -> String
}

public struct ParamSpec: Identifiable, Sendable {
  public var id: ParamID
  public var title: String                 // sentence case, one or two words ("Flow index")
  public var glyph: String?                // quantity symbol, serif italic ("n", "τ_y", "λ"); one "_" marks a subscript
  public var glyphSpoken: String           // VoiceOver ("tau y", "lambda")
  public var icon: String                  // SF Symbol for the puck, readout card and info sheet (prototype: `symbol`)
  public var tint: LabColor?               // override; normally resolved by the palette
  public var range: ClosedRange<Double>
  public var defaultValue: Double
  public var scale: ParamScale             // .linear | .logarithmic (lower bound > 0)
  public var origin: Double?               // bipolar knobs light from here (Gravity −1…3 → 0)
  public var detents: [Detent]
  public var step: Double                  // 0 = continuous; ≥ 1 with an integer range = rotary switch
  public var format: ParamFormat
  public var hint: String                  // ≤ 110 characters, shown while turning
  public var descriptor: String            // ≤ 36 characters, under the title on card knobs
  public var detail: String                // a paragraph for the info sheet
  public var provenance: Provenance

  public var isSwitch: Bool                               // step >= 1
  public var switchCount: Int
  public func position(of value: Double) -> Double        // non-finite → 0; log: log(v/lo)/log(hi/lo)
  public func value(at position: Double) -> Double        // inverse, then quantised
  public func quantised(_ v: Double) -> Double            // lo + round((v−lo)/step)·step, clamped; non-finite → lo
  public var originPosition: Double
  public func detent(at value: Double) -> Detent?         // |Δposition| < 0.004 (Gyre Knobs.swift:97-99)
  public func capture(near position: Double, radius: Double = 0.02) -> Detent?   // Gyre GlassKnob.swift:120
  public func nudged(_ value: Double, by direction: Int, coarse: Bool = false) -> Double
  public func accessibilityValue(_ value: Double) -> String   // "1.00 g, Earth"
}
```

Nudge rule (one VoiceOver swipe, arrow key or ± step):

| Spec | One nudge | Shift-arrow |
|---|---|---|
| Switch | ±1 position | ±5, clamped |
| `step > 0` and range/step ≤ 100 | ±1 step (Orbitals `nudge`, `GlassControls.swift:205-214`) | ±5 steps |
| Otherwise | ±1/20 of the sweep in position space (Gyre `GlassKnob.swift:154`), so a log knob moves by a constant ratio: ×10^(decades/20) | ±1/4 of the sweep |

A nudge **stops on any labelled detent it would cross**, so VoiceOver users land on "Earth" and "Moon". A nudge at a limit plays `boundary` and leaves the value unchanged.

Verified in `KnobTests`:
- 5-decade log Consistency: `position(of: 1) = 0.6`, one nudge = ×1.778.
- Gravity: 0.9 → 1.0 stops at Earth; 0 → 0.166 lands on Moon.
- `accessibilityValue(1) = "1.00 g, Earth"`; −0.5 reads "−0.50 g" with U+2212.

### 3.4 `GlassKnob`: the rotary control

```swift
public struct GlassKnob: View {
  public enum Style: Sendable { case compact, card }
  public init(spec: ParamSpec, value: Binding<Double>, style: Style = .compact,
              onActive: @escaping (Bool) -> Void = { _ in },     // grab/release → floating KnobReadout
              onPrecision: @escaping () -> Void = {})             // long press / "Fine control" action
}
```

**Geometry.**

| | `.compact` (console; Gyre) | `.card` (sheets, panels; Orbitals) |
|---|---|---|
| Dial | 84 × 84 frame, arc 84 (radius 40), track white 0.1 / width 3 | 104 × 104 with a **31-tick scale** (index 0…30 at −135° + 9°·i; every 5th major, outer r − 2, inner −7 / −3, widths 1.6 / 1; lit at 0.8 when i/30 ≤ position, else 0.22), arc 84 |
| Value arc | from `originPosition` to `position`, width 3, round caps, `.shadow(hue × 0.8, radius 4)` | same |
| Detent dots | 3 × 3 at r − 1; white 0.45, or 1.0 when active | same |
| Puck | 60, `icon` at 0.27 × puck, semibold, white 0.9, `.symbolEffect(.bounce, value: bump)` on detent and switch hits; pointer capsule 3.5 × puck/6 with `.shadow(hue, 3)`; glass tint 0.10 → 0.32 held; scale 1.07 held | 70, same contents |
| Labels | under the dial: title (`knobTitle`), value (`knobValue`); both `accessibilityHidden` | above: glyph + title in hue; descriptor (white 0.75, `@ScaledMetric(relativeTo: .caption)` min height 36); below: `dialReading` in hue; then `PrecisionSlider` (not for switches) |
| Card | none | hue × 0.055 fill, radius 20, stroke hue × 0.22, or × 0.58 while dragging |
| Disabled | opacity 0.55 (Gyre dimmed knobs) | same |
| Large Content Viewer | `Label("\(title) \(value)", systemImage: icon)` | — |

**Interaction** (both styles share one implementation):

1. `DragGesture(minimumDistance: 2)` with `@GestureState dragging`.
   - The first change captures `startPosition`, the last tick and the current detent, sets `focused = true` (`@FocusState`), calls `onActive(true)` and plays `.grab`.
   - Movement: `p = start + (dx − dy) / 230`, clamped to 0…1. Up or right increases. 230 pt is Gyre's full travel (`GlassKnob.swift:108`); Orbitals uses 240 pt in value space (`:184`).
2. **End stops:** play `.boundary` once when the raw position first passes 0 or 1 (`atLimit` latch).
3. **Switch** (`step ≥ 1`): `value = spec.value(at: p)`. On change, play `.switchClick` (or system `selection()` when VoiceOver is on) and bump the symbol.
4. **Detent capture:** if `spec.capture(near: p)` finds a detent, snap the value to it and play `.detent` once per entry.
5. **Continuous:** `next = spec.value(at: p)`. Write only if `next != value` (**feedback only for real changes**, Orbitals `setValue`, `:194-203`). Play `.tick` when `Int(p × 24)` changes (Gyre `:146`), or `selection()` when VoiceOver is on (Orbitals `:198-202`).
6. `.onChange(of: dragging) { if !$0 { finish() } }` releases even when a scroll view or system gesture cancels the drag (Orbitals `:120-123`). `finish()` plays `.release` and calls `onActive(false)`. `.onDisappear` clears `startPosition`.
7. **Double-tap** resets to `defaultValue` with `LabMotion.reset` and plays `.reset` (Gyre).
8. **Long press** (0.4 s, max distance 4) calls `onPrecision()` and plays `.grab`.
9. **Keyboard:** `.focusable()`, `.focused($focused)`, `.onKeyPress(keys: [.upArrow, .rightArrow, .downArrow, .leftArrow])`, so ↑/→ increase and ↓/← decrease. Shift gives a coarse step (§3.3). Return `.handled`.
10. **VoiceOver:** `.accessibilityElement(children: .ignore)`.
    - label: "\(title), \(glyphSpoken)" or the title alone;
    - value: `spec.accessibilityValue(value)`;
    - hint: "\(hint) Swipe up or down to adjust.";
    - `.accessibilityAdjustableAction` → `nudge(±1)`;
    - named actions "Reset to default" and "Fine control".
11. Identifier `knob-<id>`; its slider is `knob-<id>-slider`; its tray is `knob-<id>-precision`.

**`PrecisionSlider`.** A native `Slider` over **position space** (0…1), so log knobs give each decade equal travel. It quantises through the spec and plays feedback only on real changes. `onEditingChanged` plays `.grab` / `.release`. It has `.frame(minHeight: 44)`, label "\(title), linear control" (Orbitals `:106`) and the same value string.

**`KnobReadout`** (floating card while held; Gyre `Console.swift:319-353`):
- top row: icon in hue, glyph, title (`.headline`), `Spacer`, the active detent label (`.caption.weight(.semibold)` in hue), and the value (`.headline.monospacedDigit()`, Gyre `Console.swift:337`: the card is glass chrome, so SF Pro digits, not monospaced);
- below it, the hint in `.footnote` secondary;
- padding 16 × 12, `maxWidth: 420`, glass radius 22;
- `accessibilityHidden(true)`, because the knob already speaks.

**`KnobPrecisionTray`** (long press on a compact knob):
- the readout card made interactive: `Label(title, icon)` and the value;
- `[−] PrecisionSlider [+]`, with ± as 30 pt glass circles labelled "Decrease \(title)" / "Increase \(title)" that nudge;
- the hint and a "Done" `.glass` button;
- `maxWidth: 460`, offset −128 above the console, `.accessibilityElement(children: .contain)`.

### 3.5 Rotary switch

A rotary switch is a `ParamSpec` with `step ≥ 1`, an integer range and `format: .labels([...])`.
- It clicks on every position (`.switchClick`, intensity 0.9, sharpness 0.35).
- VoiceOver reads the label ("Stir").
- The arc lights from `origin`. Every position is a detent dot.
- It has no slider and no tray.

When to use which control:

| Choice | Control |
|---|---|
| A mode of the *instrument* that the user will sweep through (Drives: Shake / Gravity / Stir / Kicks / Heat) | rotary switch on the console |
| A *thing* to pick (material, sample, instrument view) | `ChoiceChips` or `GlassTile` shelf |
| 2–5 mutually exclusive *views* | segmented `Picker` or `.pickerStyle(.tabs)` |
| A named starting point | `ExperimentMenu` (§3.11) |

Orbitals replaced a Menu with explicit chips because the menu hid the active mode (build-5 note, `design-orbitals.md`). The same reasoning keeps materials as chips or tiles, not a menu.

### 3.6 `GlassToggle`, `ChoiceChips`, `GlassTile`

```swift
public struct GlassToggle: View {             // Orbitals GlassControls.swift:289-313
  public init(_ title: String, isOn: Binding<Bool>, icon: String, note: String? = nil)
}
public struct ChoiceChips<ID: Hashable & Sendable>: View {
  public struct Item: Identifiable, Sendable { public var id: ID; var title: String; var icon: String?; var hue: LabColor? }
  public init(_ items: [Item], selection: Binding<ID>, columns: Int = 3, identifierPrefix: String)
}
public struct GlassTile: View {               // Gyre ObjectTile, Console.swift:264-293; LabKitProto Console.swift:189-230
  public init(title: String, icon: String, subtitle: String, selected: Bool, hue: LabColor, action: @escaping () -> Void)
}
```

- **GlassToggle:**
  - a native `Toggle` with `Label(title, systemImage:)`, `.symbolRenderingMode(.hierarchical)` and an optional muted `.caption` note underneath (spectra `.toggle-row small`);
  - tint `signatureDeep`, so the white thumb track reads;
  - `minHeight 44`; `selection()` haptic only on a real change.
  - Blockdown replaced `Toggle` with a whole-row button because "the stock control's small hit target proved unreliable" (`design-house-rules.md` §2). LabKit makes the **whole row** the hit target with `.contentShape(.rect)`, `.onTapGesture { isOn.toggle() }`, `.accessibilityAddTraits(.isToggle)` and `.accessibilityValue(isOn ? "On" : "Off")`, and keeps the system switch as the visual.
- **ChoiceChips:**
  - a `LazyVGrid` of `columns` flexible items (1 at accessibility sizes), spacing 6, row spacing 7 (Orbitals `MotionControls.swift:130`);
  - chip `minHeight 44`, radius 14, glass tinted hue × 0.12, stroke hue × 0.8 when selected and × 0.18 otherwise;
  - selected fill is the data hue with `onFill` text; unselected is white 0.07 with white 0.85 text;
  - `.isSelected` trait, `selection()` haptic, identifier `<prefix>-<id>`;
  - **a live explanation line under the grid** that changes with the selection and catches limiting cases (Orbitals `motion-mode-description`; spectra `kindNote`, `controls.js:118-125`).
- **GlassTile:** for Rheo's material shelf. Implemented in `$S/Sources/LabKitUI/Chips.swift` and shown in `$S/shots/components-15pm.png` and `rheo-15pm-strip.png`.
  - Layout as Gyre and the prototype: the icon (`.title3`, 26 pt frame) over the title (`.caption2.weight(.semibold)`, one line, `minimumScaleFactor(0.8)`). The subtitle is the accessibility **hint**, not visible text. Frame `minWidth 76`, `minHeight 62`, radius 18. Traits `.isButton` plus `.isSelected` when chosen.
  - Colour: the icon is drawn in the data hue when unselected (graphic contrast ≥ 3:1 on dark glass) and in white when selected. The selected glass tint is the hue at **0.45** (Gyre `selectedTile` × 0.45), or at **0.30 when the hue's luminance is above 0.5**. Measured on the 15 Pro Max simulator: oobleck white at 0.45 left the white label at 4.25:1 on a (124, 123, 116) tile; at 0.30 it measures 6.7:1.
  - Shelf: `GlassEffectContainer(spacing: 4)` and `HStack(spacing: 8)` in a horizontal `ScrollView` with `.scrollIndicators(.hidden)`; `scrollTo(selected, anchor: .center)` on appear and on change (Orbitals view tabs). At 398 pt wide it shows 4.8 tiles, and the cut-off fifth tile tells the user it scrolls.

### 3.7 `KnobConsole`, `KnobGrid`, controls row

The API is LabKitProto's (`Console.swift:6-116`) with the §1.3 #14 changes. The scratch gallery's generic `ConsolePage` protocol and `KnobSlot` are dropped.

```swift
public struct ConsolePage: Identifiable, Hashable, Sendable {      // prototype struct
  public let id: String
  public let title: String                                          // one word: "Fluid"
  public var knobs: [ParamID]                                       // new: default content is KnobGrid(knobs)
  public init(_ id: String, title: String, knobs: [ParamID] = [])
}
public enum KnobFocus: Equatable, Sendable { case none, held(ParamID), precision(ParamID) }

public struct KnobConsole<Page: View, Controls: View>: View {
  public init(pages: [ConsolePage], page: Binding<String>, store: ParamStore, focus: Binding<KnobFocus>,
              open: Binding<Bool>? = nil,            // nil: no fold button (Rheo, §9)
              uniformHeight: Bool = true,            // every page reserves the tallest page's rows
              pickerMaxWidth: CGFloat = 320,
              @ViewBuilder content: @escaping (ConsolePage) -> Page,
              @ViewBuilder controls: @escaping () -> Controls)
}
extension KnobConsole where Page == KnobGrid {      // the common case: every page is its knobs
  public init(pages: [ConsolePage], page: Binding<String>, store: ParamStore, focus: Binding<KnobFocus>,
              open: Binding<Bool>? = nil, uniformHeight: Bool = true, pickerMaxWidth: CGFloat = 320,
              @ViewBuilder controls: @escaping () -> Controls)
}
public struct KnobGrid: View {
  public init(_ ids: [ParamID], store: ParamStore, focus: Binding<KnobFocus>, columns: Int = 4, dimmed: Set<ParamID> = [])
}
public struct ProminentGlassButton: View { public init(_ title: String, icon: String, iconOnly: Bool = false, action: @escaping () -> Void) }
public struct CircleGlassButton: View { public init(_ label: String, icon: String, tap: HapticTap = .soft, action: @escaping () -> Void) }
```

`KnobGrid` wires each knob's `onActive` to `focus = .held(id)` and `onPrecision` to `focus = .precision(id)`. Apps never wire those callbacks by hand. A custom page (Gyre's Object page, with its tile shelf and level meter) passes its own `content`. `dimmed` knobs (opacity 0.55, prototype `Console.swift:97`) are knobs that do nothing for the current material, such as Rheo's Packing on honey.

Layout (Gyre `Console.swift:13-58` + changes):
1. `VStack(spacing: 12)`. When `open` (or always, when `open` is `nil`):
   - a page picker: `Picker("Knobs", selection: $page.animation(page))` with `.pickerStyle(.tabs)`, `maxWidth: pickerMaxWidth`, identifier `console-pages`, `selection()` on change, hidden when there is one page (Gyre note). **Measured:** five one-word pages ("Fluid World Touch Signals View") fit in 320 pt, and the picker is 31 pt tall (`$S/frames-rheo.txt`). They still fit with the type capped at `.accessibility1`;
   - the page content: `KnobGrid` rows of **4** (2 at accessibility sizes), `Grid(horizontalSpacing: 2, verticalSpacing: 10)`, `.id(page)` + blur-replace. One row measures 119.7 pt.
   - With `uniformHeight`, the page area is `rows(max over pages) × rowHeight`, so switching pages never moves anything above the console. Gyre's pages differ in height and its canvas resizes. That is harmless for a bubble, but it would move a fluid tank's floor.
2. The **controls row** is always visible: `HStack(spacing: 10)` = `[ProminentGlassButton primary] [CircleGlassButton pause/resume] [app slot] Spacer [CircleGlassButton reset page] [fold button "Knobs" with chevron, only when open ≠ nil]`. It measures **50 pt** tall: glass circles render 50 pt around their 36 pt glyph frame.
   - "Reset page" resets only the visible page's knobs, and its accessibility label names the page ("Reset fluid knobs"). This is Orbitals' scoped-reset rule: each reset says what it preserves.
3. The floating `KnobReadout` sits at `offset(y: -78)` for `.held`, or the `KnobPrecisionTray` at `offset(y: -128)` for `.precision`, as a top overlay.
4. `.dynamicTypeSize(...LabMetrics.stageChromeTypeCap)`.

**Measured defect and fix.** At Accessibility XXXL (`$S/shots/stage-axxxl-2.png`), the page `ScrollView` and the controls row shared one `GlassEffectContainer(spacing: 18)`. Pucks scrolled under the buttons **merged into their glass shapes**: the puck and the button fused into one blob. Fix: give the knob page and the controls row **separate `GlassEffectContainer`s**, and put the `ScrollView` inside the page's container with `.scrollClipDisabled(false)` and `.contentMargins(.bottom, 8)`. The prototype still has the single container (§1.3 #15). §10 records the re-test.

`ProminentGlassButton`:
- `.glassProminent`, tinted signature, label colour `onSignature`, `button` font;
- `lineLimit(1).fixedSize()`, `minHeight 36`, `.contentTransition(.symbolEffect(.replace))`;
- **icon-only at accessibility sizes**, the same rule as Orbitals' transport (`DashboardView.swift:179`), with the Large Content Viewer showing the full label;
- plays `.tap`, then runs the action under `LabMotion.action`.

`CircleGlassButton`:
- `.glass` with `.buttonBorderShape(.circle)`, a white glyph in a 36 × 36 frame, a 44 × 44 hit area and `.contentShape(.circle)`. It renders 50 × 50 pt (measured);
- a configurable tap haptic (default `.soft`).

### 3.8 `LabTopBar`, `ToolbarGlyph`, `TelemetryCard`, `StatusBanner`, `ClockReadout`

```swift
public struct LabTopBar<Card: View, Actions: View>: View { public init(@ViewBuilder card: () -> Card, @ViewBuilder actions: () -> Actions) }  // prototype labels
public struct ToolbarGlyph: View { public init(_ icon: String, title: String) }        // 42 × 44, Large Content Viewer
public struct TelemetryRow: Identifiable, Sendable, Hashable {
  public init(_ title: String, icon: String, value: String, provenance: Provenance)
}
public struct TelemetryCard<Headline: View>: View {                                       // prototype: view-builder headline
  public init(expanded: Binding<Bool>, rows: [TelemetryRow], simulatedNote: String? = nil,
              @ViewBuilder headline: () -> Headline)
}
public struct TelemetryHeadline: View {                                                   // the standard headline
  public init(icon: String, spins: Bool = false, headline: String, subline: String, chip: String? = nil)
}
public struct StatusBanner: View { public init(_ text: String, icon: String = "info.circle") }
public struct ClockReadout: View { public init(running: Bool, time: String) }
```

- **Top bar** (Gyre `TopBar.swift:5-41`):
  - `GlassEffectContainer(spacing: 12)` holding a `ViewThatFits(in: .horizontal)`: first `HStack(alignment: .top, spacing: 10) { card; Spacer; group }`, then a fallback `VStack(alignment: .trailing, spacing: 8) { group; card }`.
  - The fallback is new. At Accessibility XXXL, Gyre's row runs off-screen; with it, the icon group moves above the card (verified, `stage-axxxl-2.png`).
  - The group is `HStack(spacing: 0)` of `ToolbarGlyph`s and `Menu`s in one `.glassEffect(.regular.interactive(), in: .capsule)`, `.fixedSize()`.
  - Capped at `.accessibility1`.
- **Item order** (merging Orbitals' persistent Dials button, Tether's info left and settings right, and Gyre's single capsule):

  | Position | Item |
  |---|---|
  | 1 | AR or "Show in your room" (if any), or the app's **thing picker** (Rheo: Material, a glyph showing the current material's icon in its data hue, which toggles the tile shelf; §9) |
  | 2 | Experiments (`flask.fill` Menu) |
  | 3 | Layers and feedback (`square.3.layers.3d` Menu: Show / Feel / Sensors toggles) |
  | 4 | Info (`info`) → `LabInfoSheet` |

  Four 42 pt glyphs plus 4 pt capsule padding each side make the group 176 pt wide. On a 430 pt screen with 16 pt margins and a 10 pt gap, that leaves **212 pt for the telemetry card**; the collapsed card measured 173 × 55.3 pt.

  The **console is always on screen**, so Orbitals' "Dials button top-left on every surface" becomes "the console is never more than one tap away". The fold button stays in the same corner in every state.
- Menus use the Gyre pattern (`TopBar.swift:43-94`):
  - `Section("…")` with two-line buttons `Button { Label(title, systemImage:); Text(subtitle) }`;
  - `Toggle(isOn:) { Label; Text(subtitle) }`;
  - `.disabled(!available)` for missing sensors;
  - a tap haptic via `.simultaneousGesture(TapGesture().onEnded { haptics.play(.tap) })` (Orbitals, on every Menu).
- **Telemetry card** (Gyre `TopBar.swift:97-184`):
  - collapsed: icon in signature (spins with `.rotate.byLayer` while the simulation runs, unless Reduce Motion), a headline with the hero quantity ("η 12.4 Pa·s"), and a subline with two secondary quantities joined by " · ";
  - a time chip ("×0.25", `ParamFormat.multiplier`) in the Time hue × 0.35 capsule whenever time ≠ 1;
  - tap expands to a `Grid` of `TelemetryRow`s. Rows with `.simulated` provenance render their value in `simulated` orange, and an orange `simulatedNote` explains how to drive the stand-in ("Simulated motion. Drag in the tank with two fingers to tilt."; Gyre drags outside its bubble, but Rheo's tank fills the screen);
  - glass radius 22; `.accessibilityElement(children: .combine)`, `.isButton`, hint "Shows/Hides sensor readings", identifier `telemetry-card`; plays `.soft`.
- **StatusBanner:**
  - a glass capsule with `.footnote.weight(.medium)`, padding 14 × 10, `.updatesFrequently`;
  - used for sensor status, post-experiment notes (6.5 s, spectra `app.js:58-64`) and AR coaching;
  - the same text is posted with `AccessibilityNotification.Announcement(text).post()` when it changes.
- **ClockReadout** (Orbitals `DashboardView.swift:239-250`):
  - "RUN" in live phosphor or "HOLD" in amber, `.caption2` monospaced, over the time (`.caption` monospaced digits, amber);
  - one element labelled "Simulation running|paused, <time>";
  - Rheo shows simulated time only in the telemetry chip, but apps with a transport use this.

### 3.9 `LabInfoSheet`, field notes, sources, settings

```swift
public struct LabInfoSheet<Content: View>: View { public init(title: String, startLarge: Bool = false, @ViewBuilder content: () -> Content) }
public struct FieldNote: View { public init(_ title: String, _ text: String, provenance: Provenance? = nil) }
public struct LegendRow: View { public init(_ colour: LabColor, glyph: String, _ text: String) }
public struct SourceLink: View { public init(_ citation: Citation) }
public struct ProvenanceLegend: View { public init() }
public struct FeedbackSettings: View {
  public init(haptics: Binding<Bool>, strength: Binding<Double>, feel: Binding<Bool>, sound: Binding<Bool>,
              feelExplanation: String, soundExplanation: String)
}
public struct PermissionGate: View { public init(_ title: String, icon: String, message: String, canOpenSettings: Bool) }
```

**Presentation** merges Gyre's sheet with Orbitals' sheet body:
- `NavigationStack`, inline title "How \(App) works" (Tether's "How Tether works");
- `.confirmationAction` "Done" with `systemImage: "checkmark"`, tinted `signatureDeep`, plays `.tap`;
- `.presentationDetents([.medium, .large], selection:)`, opening at `.medium`;
- `.presentationBackgroundInteraction(.enabled(upThrough: .medium))` (Gyre `InfoSheet.swift:93-94`), so **the simulation stays live and touchable above the half sheet**;
- `.presentationDragIndicator(.visible)` (Orbitals `InstrumentControlSheet.swift:58`);
- body: a `ScrollView` of `InstrumentPanel`s, `VStack(spacing: 20)`, `.padding(16)`, `maxWidth 760`, background `ground.background`, body font `.callout` at white 0.85.

Orbitals uses numbered panels (`TelemetryView.swift:100-180`); Gyre uses a `List` of sections. LabKit picks panels: they carry the phosphor identity and readouts.

**Fixed section order** (so every app's sheet reads the same):

| # | Panel | Contents | Source pattern |
|---|---|---|---|
| 01 | *What you're looking at* | One paragraph: the toy in one breath. Then the hero instrument, e.g. Rheo's flow curve `LabPlot` with live readouts. | Gyre intro; Orbitals 01 |
| 02 | *Touch* | One `FieldNote` per gesture: poke, stir, tilt, shake, shout, double-tap a knob. | Gyre "Touch" |
| 03 | *What you're seeing* | `LegendRow`s, one per colour on the stage, swatches from the **same token** the renderer converts | Gyre "What you're seeing" |
| 04 | *Knobs* | One entry per `ParamSpec`: icon, title in hue, glyph, provenance badge, `detail`, detents listed | Gyre "Knobs"; Orbitals 05 "Reading the dials" |
| 05 | *Experiments* | Each experiment: title · subtitle, summary, source links | Orbitals 06 "Harmonic starters" |
| 06 | *What's real and what's illustrative* | `ProvenanceLegend`, then a plain paragraph naming every display choice (time scale, exaggerated depth, symbolic directions) | spectra notes "What's real and what's illustrative"; Tether "What is calculated—and what is interpreted" |
| 07 | *Sensors in play* | `TelemetryRow`s with live or simulated values, plus opt-in sensor toggles (barometer) and `PermissionGate` where denied | Gyre "Sensors in play" |
| 08 | *Sound & feel* | `FeedbackSettings` | Orbitals 05 "Physical feedback"; Gyre Layers › Feel; spectra 04 "Feedback" |
| 09 | *Sources & licences* | `SourceLink`s: papers, datasets, open-source code with licence, each with a checked date. Ends with the method footnote ("The physics is …") and the privacy sentence. | Tether "Read the sources"; Gyre method footnote; house rule 5 privacy |

- **FieldNote:** the title in signature, `.fontWeight(.medium)`, an optional badge, then the paragraph; one combined element (Orbitals `note()`, `TelemetryView.swift:184-189`).
- **SourceLink:**
  - a `Link` row: `citation.label` ("Publisher · Title") in `.subheadline`, an optional "Licence: MIT" `.caption` muted line, `Spacer`, and `arrow.up.right` `.caption`, all at `minHeight 44`;
  - tint signature, hint "Opens in Safari";
  - this is Tether `MethodologyView.swift:85-98` plus the licence line.
- **FeedbackSettings:**
  - Haptics toggle with the note "Taps, knob detents and end stops. Haptics need supported hardware and follow device settings.", adapted from Orbitals `ControlsView.swift:111`;
  - Strength slider 0.2…1, step 0.05, value as amber monospaced "0.85", accessibility value "85 percent"; it plays `.detent` on release so the user feels the new strength;
  - "Feel a detent" `.glass` button that plays `.boundary` (Orbitals `:107-108`);
  - "Feel the simulation" toggle with the app's explanation;
  - "Sound" toggle with the app's explanation;
  - strength and the feel toggle are disabled while haptics are off (Orbitals disables Intensity).
- **PermissionGate:**
  - a `ContentUnavailableView` with a label, the message and an "Open Settings" `.glassProminent` button (`UIApplication.openSettingsURLString`, identifier `permission-open-settings`), from Orbitals `OrbitARScreen`;
  - the message always says what keeps working ("Rheo keeps simulating with the knobs.").

### 3.10 Provenance and citations

```swift
public enum Provenance: String, Sendable, Hashable, Codable, CaseIterable {
  case measured, modelled, live, simulated, illustrative
  public var badge: String          // the word, lowercase
  public var explanation: String    // one line, below
  public var tint: LabColor         // measured, live → LabSemantic.live; modelled → value; simulated → simulated; illustrative → ground.muted (dashed)
}
public struct Citation: Sendable, Hashable, Codable, Identifiable {
  public enum Kind: String, Sendable, Hashable, Codable { case paper, dataset, datasheet, textbook, standard, web, code }
  public init(_ title: String, publisher: String, url: URL, kind: Kind, licence: String = "", checked: String)
  public var label: String          // "Publisher · Title" (Orbitals HarmonicPreset sourceTitle)
}
```

| Word | Explanation (shown in the legend and as the badge hint) | Rheo examples |
|---|---|---|
| measured | "Interpolated from published measurements." | honey viscosity vs temperature; literature flow-curve points drawn as hollow markers |
| modelled | "Calculated from a physical model. Trust its shape more than its third digit." (the second sentence is spectra-lab's, `notes.js:6`) | η, σ and γ̇ readouts; every simulated fluid |
| live | "Read from this phone's sensors as you watch." | tilt (gravity direction), shake, magnetometer µT, mic level |
| simulated | "A stand-in for a sensor this device doesn't have or hasn't allowed." | Simulator tilt, `-fakeMic`, a denied mic |
| illustrative | "A display choice to make the effect visible, not a measured quantity." | time scale, tank depth exaggeration, MR field-line directions, "oobleck monster" amplitude gain |

spectra-lab's `table` maps to measured and `model` to modelled. Gyre has only "simulated" in orange. Tether's "calculated vs interpreted" maps to modelled vs illustrative.

The word is mandatory; colour only reinforces it (WCAG 1.4.1).

### 3.11 Experiments (presets) and `ExperimentMenu`

```swift
public struct ExperimentEffects: OptionSet, Sendable, Hashable, Codable {
  public static let refillsTank, restartsClock, clearsHistory, resetsCamera, resumesPlay, switchesView: ExperimentEffects
  public var sentence: String       // "Each experiment refills the tank, restarts the clock and starts playing."
}
public struct Experiment: Sendable, Identifiable {
  public var id: String
  public var title: String          // sentence case, ≤ 22 characters ("Oobleck punch")
  public var subtitle: String       // ≤ 48 characters, numbers welcome ("Hit it hard and it holds")
  public var icon: String
  public var note: String           // 1–2 sentences, shown in a 6.5 s banner after applying, and in the info sheet
  public var values: [ParamID: Double]   // a preset is just values (Gyre note); unspecified ids keep their value
  public var material: String?      // data-hue id, if the experiment selects one
  public var effects: ExperimentEffects
  public var sources: [Citation]
  public var provenance: Provenance
  public static func matching(_ values: ParamValues, material: String?, in all: [Experiment]) -> Experiment?
}
public struct ExperimentMenu: View {
  public init(_ experiments: [Experiment], current: Experiment?, apply: @escaping (Experiment) -> Void)
}
```

- **Derived identity:** the menu label shows `matching(...)`'s title or the generic "Experiments". Editing any knob after applying therefore reverts the label (Orbitals `currentHarmonic`). Nothing stores "the current preset".
- **Menu** (a `ToolbarGlyph("flask.fill")` label in the top bar):
  - `Section("Experiments · \(effects.sentence)")` with two-line items `Label(title, icon)` + `Text(subtitle)`;
  - the subtitle carries a number or the action to take ("100 MHz · 3.00 m"; "Play a loud bass note");
  - spectra field trips show `name · detail` and a `note` toast (`presets.js`, `app.js:65-73`);
  - Gyre experiments have title, subtitle and symbol (`Knobs.swift:283-349`).
- **Apply:**
  - `withAnimation(LabMotion.experiment) { store.apply(values) }`, select `material`, honour `effects`;
  - `haptics.success()`, plus Gyre's ramp when the experiment winds something up;
  - show `StatusBanner(note)` for 6.5 s;
  - announce `"\(title). \(note)"` to VoiceOver.
- **Honesty:** the effects sentence is generated, so the copy can't drift from the behaviour. Orbitals writes it by hand: "Starters set A, B & C and begin a fresh recording." Every experiment with a real-world claim carries at least one `Citation`.

### 3.12 Plot primitives

```swift
// LabKitCore
public struct PlotTick: Sendable, Hashable { public var value: Double; public var position: Double; public var isMajor: Bool; public var label: String? }
public struct PlotAxis: Sendable, Hashable {
  public enum Scale: Sendable, Hashable { case linear, log10 }
  public init(title: String, symbol: String = "", unit: String = "", domain: ClosedRange<Double>, scale: Scale = .linear)
  public func caption(long: Bool = false) -> String           // "γ̇ (s⁻¹)" / "Shear rate γ̇ (s⁻¹)"
  public func position(_ v: Double) -> Double?                 // nil for non-finite, or ≤ 0 on log
  public func value(at p: Double) -> Double
  public var decades: Double
  public func ticks(length: Double, minSpacing: Double = 36) -> [PlotTick]
  public static func decadeLabel(_ k: Int) -> String           // "0.01" "0.1" "1" "10" "100" "1000", else "10ᵏ"
}
public struct PlotSeries: Sendable, Identifiable {
  public enum Style: Sendable, Hashable { case line(width: Double, glow: Double, dash: [Double]); case markers(diameter: Double, hollow: Bool) }
  public init(id: String, label: String, colour: LabColor, points: [SIMD2<Double>], style: Style, provenance: Provenance)
  public func runs(x: PlotAxis, y: PlotAxis) -> [[SIMD2<Double>]]   // split at gaps; gaps are never bridged
}
// LabKitUI
public enum PlotGuide: Sendable, Hashable {
  case powerLaw(prefactor: Double, exponent: Double, label: String)   // straight on log-log
  case vertical(x: Double, label: String), horizontal(y: Double, label: String)
}
public struct LabPlot: View {
  public init(title: String, x: PlotAxis, y: PlotAxis, series: [PlotSeries], guides: [PlotGuide] = [],
              cursor: SIMD2<Double>? = nil, summary: String)
}
```

**Tick rules** (verified in `AxisTests`):
- **Log axis:** a major tick at every decade. When decades are crowded, label every n-th decade, keeping at least `minSpacing` (36 pt) between labels. Minor ticks at 2…9 × 10ᵏ appear only when every decade is labelled and a decade is ≥ 2 × `minSpacing` long. Tested cases:
  - 6 decades in 300 pt: 7 majors, no minors;
  - 600 pt: 48 minors;
  - 120 pt: every second decade.
- **Linear axis:** a 1-2-5 step giving at most `length / minSpacing` labels. 0…90 °C in 300 pt gives 0, 20, 40, 60, 80.
- **Labels:** decimal for |k| ≤ 3 ("0.01" … "1000"), else "10ᵏ" with superscripts. This is a pragmatic mix: spectra's tuner prints "10ⁿ" throughout (`tuner.js:102`).

**Drawing (`LabPlot` on a SwiftUI `Canvas`):**
- **Insets:** leading 44, bottom 30, top 10, trailing 12. Fill `plot`.
- **Grid:** live × 0.06, or × 0.16 under Increase Contrast (spectra `THEME.grid` `rgba(102,245,143,0.06)`). Majors 1 pt, minors 0.5 pt. The axis frame is muted × 0.35 (spectra `THEME.axis`), left and bottom only.
- **Tick labels:** `@ScaledMetric(relativeTo: .caption2)` 9.5, capped at 13, monospaced, muted. x labels go 9 pt below the axis, y labels 5 pt left of it.
- **Axis captions:** "γ̇ (s⁻¹)" at the bottom right and "σ (Pa)" inside the top left (spectra `lab.js` `data-ylabel` tag).
- **Clip:** everything below is clipped to the plot rectangle.
- **Lines:** spectra `glowLine`: an under-stroke 3.2 × width at `glow` alpha (0.22), then the core stroke, round caps and joins (`draw.js:34-49`).
- **Markers:** hollow 1.5 pt rings for measured points; filled dots with a 0.22 halo for live points.
- **Guides:** dashed [4, 3] in dim × 0.8, labelled at their end in dim. **Labels are culled on collision.** Each guide label tries its line's exit point and then 25 % and 50 % back along the line. If its rectangle still overlaps a label already drawn or a series' last 10 % of points, it is dropped (the summary still names the guides). Measured: in the 223 × 131 pt strip plot, "100 Pa·s" and "1 Pa·s" overprinted each other at the top-right corner (`$S/shots/rheo-15pm-strip.png`).
- **Cursor** (the live state): signature ring 14 pt, a 0.18 halo, a white core.
- **Frame:** `clipShape(.rect(cornerRadius: 20))` and a stroke live × 0.2 (Orbitals canvas frame `phosphor.opacity(0.2)`).
- **Redraw at 10 Hz** with the readouts. For a plot that must animate at 60–120 Hz, use the Metal phosphor capsule renderer (`design-orbitals.md` §(d)) through `LabKitRender`'s `LineBatch`.

**Accessibility:**
- one element; label = title; value = `summary`, a sentence written by the app that states the shape ("Oobleck stiffens above 10 per second. Ketchup has a 30 pascal yield stress and thins. Honey is a straight Newtonian line.");
- `.accessibilityChartDescriptor(LabPlotDescriptor)` builds an `AXChartDescriptor` with `AXNumericDataAxisDescriptor` per axis and `scaleType = .log10` on log axes (`AXAudiograph.h:56`). Its gridlines are the major ticks, its series named "\(label), \(provenance)", and its value descriptions use `LabFormat.engineering`. VoiceOver's Audio Graph then plays the curve.
- Under **Differentiate Without Colour**, line series after the first get dash patterns `[6,3]`, `[2,3]`, `[8,3,2,3]`, and markers stay hollow or filled by provenance.

**Rheo's rheometer flow curve (the hero plot):**

| | Value |
|---|---|
| x | `PlotAxis(title: "Shear rate", symbol: "γ̇", unit: "s⁻¹", domain: 0.01...1000, scale: .log10)` |
| y | `PlotAxis(title: "Stress", symbol: "σ", unit: "Pa", domain: 0.01...10_000, scale: .log10)` |
| Alternative y (viscosity curve) | `PlotAxis(title: "Viscosity", symbol: "η", unit: "Pa·s", domain: 1e-3...1e5, scale: .log10)`. On η(γ̇), shear-thinning slopes down, thickening slopes up, Newtonian is flat; offer a "σ / η" segmented switch |
| Series | one modelled line per fluid in its data hue, width 2, glow 0.22; literature points as hollow markers with `.measured` and a `Citation` |
| Guides | `.powerLaw(prefactor: η, exponent: 1)` for η = 0.01, 1, 100 Pa·s, labelled "η 0.01 Pa·s", "1 Pa·s", "100 Pa·s". A Newtonian fluid lies along one; a yield stress shows as a horizontal floor (`.horizontal(y: τ_y, label: "τ_y")`) |
| Cursor | the tank's current (γ̇, σ) at the probe, the finger or the strongest-sheared region |
| Summary | regenerated when the material changes, not per frame |

The gallery renders this (`$S/shots/info-large-2.png`): three fluids, four literature points, three iso-viscosity guides and the cursor, with `Readout`s for η, σ, γ̇ and T below.

### 3.13 Canvas region, stage labels, gestures

The full spec is in `labkit-from-gyre.md` §3.4 (`CanvasRegion`). Additions from Orbitals and spectra-lab:
- **Stage tags:** `LabCanvasLabel` UPPERCASE monospaced in the corners, e.g. "THIN TANK · OOBLECK" top-left and the scale or medium top-right (spectra `.tag`, `spectra.css:79`).
- **Gesture hint:** one line in dim: "Poke · stir · tilt · shout" (spectra `.hint`, `:80`; Orbitals "Drag to rotate · Two fingers to move · Pinch to zoom"). It is hidden in compact vertical size. **In a fluid tank it never sits at the floor**, because the fluid pools there under gravity. Measured: the dim hint drawn over the oobleck fill was unreadable (`$S/shots/rheo-15pm-fluid.png`). Rheo draws it in the headspace, 20 pt under the stage tags. It fades after the first touch in the tank and returns after 30 s idle. Any canvas label that can land on the fluid gets a 0.6-alpha `ground.stage` capsule behind it.
- **Canvas accessibility** (Orbitals and Tether):
  - label = what it is ("Fluid tank, oobleck");
  - value = state in words ("Resting. Viscosity 12.4 pascal seconds.");
  - `.accessibilityAdjustableAction` for the main continuous gesture (Rheo: stir speed);
  - named actions for every gesture: "Poke", "Stir", "Shake", "Tilt left", "Tilt right", "Refill", "Reset view";
  - keyboard: arrows tilt, space pokes.
- **One renderer at a time;** offscreen, paused or background costs nothing; 30 fps on Low Power Mode or thermal ≥ serious (Orbitals `preferredFrameRate`; Gyre 60 fps in Low Power; spectra 30 fps when battery < 20%, `app.js:247`).


---

## 4. Accessibility, Dynamic Type and Reduce Motion rules

Orbitals and Tether set the bar (`design-house-rules.md` §4, "Accessibility depth"). Gyre speaks its knobs to VoiceOver, but it has no keyboard path, no Dynamic Type handling for its chrome and no Large Content Viewer. LabKit builds the Orbitals and Tether level into its components, so an app gets it by using them. Each rule below is tagged **[V]** (verified in the gallery or by test this session), **[S]** (read in a source app) or **[P]** (proposal).

### 4.1 Every action has three routes [S]
Every gesture has three routes: direct manipulation, VoiceOver (an adjustable action or named actions), and a hardware keyboard (Orbitals principle 4, `design-orbitals.md`).

| Control | Touch | VoiceOver | Keyboard |
|---|---|---|---|
| `GlassKnob` | drag, double-tap reset, long-press precision | adjustable (swipe up/down) + "Reset to default" + "Fine control" | ↑→ / ↓← when focused; Shift for a coarse step |
| Precision slider / tray | slide; ± buttons | the native slider is adjustable; ± are buttons | native |
| Canvas / tank | poke, stir, pinch; tilt and shake the phone | adjustable (stir speed) + named actions for every gesture | arrows tilt, space pokes, +/− zoom |
| Console page picker | tabs | picker | ←/→ when focused |
| Material shelf, chips | tap | buttons with `.isSelected` | Tab / arrows (native focus) |
| Play / Freeze | button | button | space (Orbitals `DashboardView.swift:84`) |
| Sheets (Info, Rheometer) | swipe down | "Done" (`confirmationAction`) or the drag indicator's action | Escape |

Tilt and shake are never the only way in. Every motion stimulus also has a knob or a named action (Gravity, Shake, "Tilt left"), so someone who cannot move the phone loses nothing. Sound never carries information that is not also shown, and haptics never carry information that is not also shown or spoken.

### 4.2 VoiceOver labelling rules
1. **Label = what it is; value = what it reads; hint = what it does**, plus how to adjust it. The knob hint is "\(hint) Swipe up or down to adjust." Orbitals' hint adds "Drag the dial up or right to increase." LabKit drops that sentence, because it describes a visual gesture to someone using VoiceOver. [S]
2. Quantity symbols get a spoken name (`glyphSpoken`), so the label reads "Viscosity, eta". The glyph text is `accessibilityHidden`. [P]
3. Values with superscripts or symbols are spoken in words (`spokenValue`): "3.2 per second", "12.4 pascal seconds", "1.23 times 10 to the minus 4 seconds". `LabFormat` gets a `spoken(_:unit:)` companion for each format. Superscript exponents become "to the minus n", "·" becomes a space, "×" becomes "times", U+2212 becomes "minus" and "°C" becomes "degrees Celsius". [P]
4. A detent is announced with the value: "1.00 g, Earth" (`ParamSpec.accessibilityValue`; verified by `KnobTests`). [V]
5. When a component's parts are read together, it combines them into one element: `Readout`, `FieldNote`, `ClockReadout`, `TelemetryCard`, `ProvenanceBadge` (hint = the explanation) and the `InstrumentPanel` header (`.isHeader`). [S]
6. Decorative symbols and the card knob's big reading are `accessibilityHidden`; the dial already speaks. [S]
7. Status changes post `AccessibilityNotification.Announcement`: an experiment was applied, a sensor went live or simulated, the mic was denied, a material changed ("Ketchup. Thins when you shake it."). `StatusBanner` also carries `.updatesFrequently`. [P]
8. Under VoiceOver, haptic steps use the system `selection()` instead of custom ticks (Orbitals `GlassControls.swift:198-202`). [S]
9. **Testability through accessibility values** (Orbitals principle 11). The canvas value is a parseable sentence: "Oobleck. Tilt 12 degrees. Viscosity 12.4 pascal seconds. Shear rate 3.2 per second." UI tests read state from it, and every control has a stable `accessibilityIdentifier` (§4.7). [P]

### 4.3 Dynamic Type

| Surface | Rule | Evidence |
|---|---|---|
| Sheets, panels, field notes, settings, the Rheometer at its large detent | **Never capped.** Grids collapse to one column at `isAccessibilitySize`. `ViewThatFits` stacks title-and-value rows. `@ScaledMetric(relativeTo: .caption)` sets descriptor minimum heights (36) | Orbitals `MotionControls.swift:41, 130`, `GlassControls.swift:21, 238-248` [S] |
| Chrome over the stage (top bar, telemetry card, console, banners, the Rheometer strip) | **Capped at `.accessibility1`** with `.dynamicTypeSize(...LabMetrics.stageChromeTypeCap)`. Every capped glyph, button and knob gets `.accessibilityShowsLargeContentViewer`, so a long press shows the big label, as in the system tab bar | Uncapped Gyre-style chrome at AX XXXL left no stage visible and ran the top bar off-screen (`$S/shots/stage-axxxl.png`) [V] |
| Console at accessibility sizes | Knob rows go from 4 to 2; the page scrolls (`maxHeight: 320`); the primary button turns icon-only | Measured on the 15 Pro Max at AX XXXL: the console grows from 226.7 to 419.5 pt and the knob area from 119.7 to 294.7 pt. The five-tab picker still fits in 320 pt (`$S/shots/rheo-15pm-axxxl.png`) [V] |
| Top bar at accessibility sizes | `ViewThatFits`: the icon group moves above the telemetry card | Measured: 55.3 → 131.3 pt tall, card 261 × 79 pt [V] |
| The tank under accessibility sizes | The tank's **physical size is fixed** (§9.2); the camera fits it into the smaller region. At AX XXXL the region shrinks from 612.3 to 419.5 pt, so the tank draws at 0.685 scale with stage bars at the sides | measured region [V]; the scale rule is [P] |
| Reset bars and footers | `HStack` → `VStack` at accessibility sizes; labels wrap with `.fixedSize(horizontal: false, vertical: true)` | Orbitals `InstrumentControlSheet.swift:39-49, 96` [S] |
| Badges and short tokens | `lineLimit(1).fixedSize()`; rows of badges use a wrapping flow layout | Measured hyphenation in an `HStack` (§3.2) [V] |
| Canvas labels | `@ScaledMetric(relativeTo: .caption2) 9`, capped at 14 pt | Orbitals used a fixed 9 pt [S] |
| Numbers | `lineLimit(1)` + `minimumScaleFactor(0.7)` (readouts 0.7, compact titles 0.8) | Orbitals `GlassControls.swift:93-94`; Gyre [S] |

UI tests must launch once with `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` and assert that every control's frame lies inside `app.frame` (Orbitals UI tests). The gallery does the same with `-rheo` and logs frames (§10).

### 4.4 Reduce Motion
Read `@Environment(\.accessibilityReduceMotion)` in every view that animates. The model mirrors it, because the renderer needs it too.
1. Every SwiftUI animation goes through `LabMotion.gated` or `.labAnimation`, so it is `nil` under Reduce Motion. [V] (compiled in scratch)
2. Transitions become `.opacity`. Use `.symbolEffectsRemoved(true)` and `.transaction { $0.animation = nil }` on buttons (Orbitals `GlassControls.swift:355-356`). Wrap `.blurReplace` as `AnyTransition(.blurReplace)` when branching. [V]
3. Continuous symbol effects, such as the spinning telemetry icon, are inactive. [P]
4. The puck does not scale on grab (1.07 → 1.0). [P]
5. **Renderer:** Gyre parks its scan band, sets flicker to 1, removes scanlines and ripples, and lets the wobble decay (`labkit-from-gyre.md` §4.4). `LabFrameUniforms` carries a `reduceMotion` lane that every app shader must honour. Orbitals reserved that lane but never used it (`appearance.y`). For Rheo there is no camera shake on impacts and no ripple rings on pokes. **The fluid still moves**, because it is the content, not decoration. [P]
6. spectra-lab starts paused when `prefers-reduced-motion` is set (`app.js:26`). LabKit does **not** auto-pause, because the simulation is the content. Apps may offer a "Start paused" setting. [S → pick]

### 4.5 Contrast and colour
1. Text tokens reach ≥ 4.5:1 and data hues and graphical objects ≥ 3:1 (verified, §2.3). Every Rheo knob hue reaches ≥ 7.03:1 on the panel (§2.4). [V]
2. **Filled and tinted selections compute their label colour.** Measured on the 15 Pro Max simulator from screenshot pixels [V]:
   - a selected oobleck chip (fill (237, 235, 219)) with the `onFill` label (the ground background) measures 17.2:1; white would be 1.2:1;
   - unselected chips (white 0.85 on hue-tinted glass) measure 7.3:1 (ketchup) and 7.6:1 (slime);
   - a selected `GlassTile` with oobleck white at Gyre's 0.45 tint measured **4.25:1**. With the 0.30 rule for hues whose luminance is above 0.5, it measures **6.7:1** (§3.6).
3. **Increase Contrast** (`@Environment(\.colorSchemeContrast) == .increased`) [P]:
   - panel hairlines 0.07 → 0.22;
   - plot grid 0.06 → 0.16;
   - glass tints +0.1;
   - the dashed `illustrative` outline turns solid at 0.8 (the word is still there).
4. **Differentiate Without Colour** (`accessibilityDifferentiateWithoutColor`) [P]:
   - plot series get dash patterns;
   - selected chips gain a checkmark (implemented in `Chips.swift`);
   - provenance is always a word anyway;
   - simulated telemetry values gain a trailing "(simulated)".
5. Colour is never the only carrier of meaning (WCAG 1.4.1). [P]
6. **Smart Invert:** put `.accessibilityIgnoresInvertColors()` on the Metal stage and on plots. An inverted phosphor plot is unreadable. [P]
7. **Labels over the fluid:** a canvas label must not land where the fluid pools, or it needs a backing capsule (measured, §3.13). [V]

### 4.6 Touch targets and hit areas [V]
- **44 × 44 pt minimum** for every control (Orbitals). Gyre's 36 pt circles keep their 36 pt glyph frame inside a 44 pt `contentShape`; they render at 50 pt in glass.
- Toggles are whole-row targets (Blockdown); see `GlassToggle` in `Chips.swift`.
- Compact knobs are 84 pt; their column is 101.5 pt wide in a 406 pt console.
- Chips have `minHeight: 44`; tiles are 76 × 62 pt.
- In the tank, the finger probe has a minimum radius of 3 mm (18 pt at life size, §9.2). A pinch zoom never shrinks the probe below that on screen.

### 4.7 Identifier scheme (UI tests)

| Element | Identifier |
|---|---|
| Knob / its linear slider / its precision tray | `knob-<paramID>` / `knob-<paramID>-slider` / `knob-<paramID>-precision` |
| Console page picker / a page | `console-pages` / `console-page-<page>` |
| Fold button (apps that fold) | `console-fold` |
| Primary action / play-pause / reset page | `action-primary` / `action-play` / `action-reset-page` |
| Rheo's Rheometer button and sheet | `action-rheometer` / `rheometer` |
| Top bar items | `topbar-material` (or `topbar-ar`), `topbar-experiments`, `topbar-layers`, `topbar-info` |
| Telemetry card | `telemetry-card` |
| Canvas | `stage-canvas` |
| Material shelf / a material tile or chip | `material-shelf` / `material-<id>` |
| Experiments | `experiment-<id>` |
| Info sheet scroll and Done | `info-scroll`, `info-done` |
| Plot / readout | `plot-<id>` / `readout-<id>` |
| Permission button | `permission-open-settings` |

Every app also takes a `-ui-testing` launch argument: defaults, paused, deterministic fakes (Orbitals). The fakes sit inside `#if DEBUG`, except `-ui-testing` itself (`design-house-rules.md` §4, "Launch-argument gating").

---

## 5. Haptics policy

### 5.1 The sources disagree (all [S], line-checked this pass)

| | Orbitals `OrbitalHaptics` | Gyre `Haptics` + `GyroModel` | spectra-lab `Feedback` | Tether |
|---|---|---|---|---|
| Philosophy | "Short, causal feedback. **Nothing runs continuously with the simulation clock.**" (`OrbitalHaptics.swift:4`) | A continuous hum is "the rotor you'd feel in your hand" (`Haptics.swift:5-6`) | Detents and events only | Copies Orbitals |
| Continuous channel | never | always, while the rotor spins and the app is not paused (`GyroModel.swift:683-698`) | never (no web API) | never |
| Hum law | — | intensity = (spin > 0.003 ? 0.1 + 0.34·√spin : 0)·(1 + 0.6·nod) + 0.55·strain, ×0.35 for a placed AR bubble; sharpness = 0.12 + 0.65·spin + 0.2·strain (`:692-698`); stops below 0.02; ≤ 40 parameter sends per second (`Haptics.swift:55-91`) | — | — |
| User control | `enabled` + `strength` 0.2…1, step 0.05, default 0.85, labelled "Intensity", plus a "Feel a detent" button that plays `boundary()` (`OrbitalHaptics.swift:9-12`; `ControlsView.swift:101-111`) | a "Haptics" toggle in Layers › Feel (`TopBar.swift:80-82`); no strength | "Haptics" toggle and "Haptic strength" 0…1, default 0.7; the slider plays a band detent on every change (`state.js:36`; `controls.js:159-161`) | `Toggle("Tactile feedback")`, `UserDefaults` key `"haptics"` |
| Rate limit | one shared admission clock (`:21, 64-70`): tap 0.028 s; selection, begin and release 0.035; drag detents 0.045 (deduplicated to 72 per range, `:93-102`); success 0.06; boundary 0.09 | one shared `lastTransient` with a per-call `minGap`, which is 0 except for string pulls (0.03, `GyroModel.swift:801-802`) and radio hits (0.1, `:623`) | 35 ms for all haptics; ticks ≥ 45 ms apart (`feedback.js:84, 98`) | as Orbitals |
| Lifecycle | `didEnterBackground` observer (`:47-56`), and `stop()` on any `scenePhase != .active` (`OrbitalsApp.swift:13-18`); `canPlay` requires `.active` (`:58-60`) | `model.stop()` on `.background` only (`ContentView.swift:54-59`) | — | stops when not active |
| Engine | `playsHapticsOnly`; `isAutoShutdownEnabled = true` (`:134-135`); players cached per pulse (`:19, 160-174`); UIKit `.rigid` fallback (`:188`) | `playsHapticsOnly`; `isAutoShutdownEnabled = false` (`Haptics.swift:22-23`); a new player per transient | `navigator.vibrate`, or one system tick from a hidden `<input switch>` on iOS Safari 18+ (`feedback.js:19-30, 88-91`) | Orbitals |
| VoiceOver | system `selection()` replaces detents (`GlassControls.swift:198-202`) | a custom nudge tap (0.4, 0.8) (`GlassKnob.swift:155`) | — | — |
| Self-trigger guard | — | after its own kicks and pokes, mic onsets are ignored for 0.2 s (`GyroModel.swift:660, 819`) | — | — |

### 5.2 Pick: two channels, both causal

**Channel 1: Feedback (transients).** On unless the user turns Haptics off. Each transient answers something the user did (Orbitals): a tap, grab, tick, detent, end stop, release, reset, success, or a poke on the simulated world.

**Channel 2: Feel (the continuous hum).** On by default, with its own toggle, "Feel the simulation". (Rheo labels it "Feel the fluid".)
- It renders a physical sensation of the simulation: Gyre's rotor torque, or Rheo's fluid pushing back on your finger, a shake's slosh, the magnet's pull.
- **`HumPolicy.causal(maxIdle: 8)`** is the default. The hum target is the simulation's wish only while `noteCause()` has been called in the last 8 s; otherwise the target is 0. Causes are:
  - a finger in the fluid;
  - |user acceleration| above 0.15 g (shake);
  - the mic envelope above its gate while Listen > 0;
  - a magnetometer step |ΔB| > 5 µT within 0.5 s.
- The level follows the target with a first-order lag, `hum += (target − hum)(1 − e^(−Δt/0.25 s))`. It stops below 0.02 (Gyre's threshold), so a hum at full level fades out in 0.25·ln 50 ≈ 0.98 s. *The 0.25 s lag and the 8 s idle are LabKit proposals (scratch `LabHaptics.swift:134-168`), not Gyre values.*
- **`HumPolicy.ambient`** plays whenever the simulation asks. Gyre opts in, because a spinning rotor in the hand is felt even when nothing else moves.

**Why this reconciles the two apps.** Orbitals forbids a hum that runs *with the simulation clock*: a buzz that ticks along with time is noise. Gyre's hum is a *sensation of a cause*: you feel the rotor because it is in your hand. The causal policy keeps Gyre's content and Orbitals' discipline. **There is never a hum without a visible cause**: whenever the hum plays, something on screen is moving because of the same cause.

**Rules for both channels:**
1. **Strength** is one slider: 0.2…1, step 0.05, **default 0.85** (Orbitals), labelled **"Strength"**. Orbitals' word "Intensity" collides with Core Haptics' own parameter and with physics copy. The slider multiplies every transient (`hapticIntensityControl` = strength on cached players; the UIKit fallback uses strength × tap intensity) and the hum level. spectra-lab's 0…1 range allows 0, which is "off" by another name; LabKit keeps the toggle for off. Releasing the slider plays `.detent`, so the user feels the new strength. spectra-lab plays on every change, which floods the rate limiter. [P]
2. **Stop everything** on `didEnterBackground` and on any `scenePhase != .active` (Orbitals; Gyre stops only on `.background`). **Stop the hum only** when paused, in Low Power Mode, and at thermal state ≥ `.serious`. Transients stay in those cases: knobs still work while paused, and a transient costs nothing.
3. `canPlay` = `enabled && strength > 0 && applicationState == .active` (Orbitals `:58-60`).
4. **One shared admission clock** for transients (Orbitals `admit(interval:)`; the prototype's `lastTransient` is already shared). A burst coalesces instead of queuing. Hum parameter sends are throttled separately to ≤ 40 Hz (Gyre).
5. **VoiceOver:** steps use system `selection()`. The hum stays, because it carries the simulation's state, but at strength × 0.6. [P]
6. **Self-trigger guard:** every poke, kick or cue the app plays itself opens a 0.2 s window in which mic onsets are ignored (Gyre; `MicListener.ignoreOnsets(for:)` in the prototype).
7. **Persistence:** `UserDefaults` keys `"<App>.haptics"`, `"<App>.hapticStrength"`, `"<App>.feel"`, `"<App>.sound"` (Tether persists `"haptics"`; Gyre persists nothing).
8. **Where the settings live:** the quick toggles (Haptics, Feel, Sound) sit in the Layers menu's "Feel" section, as in Gyre (`TopBar.swift:80-82`), so live controls stay on the main surface (house rule 6). The full `FeedbackSettings`, with Strength and "Feel a detent", sits in the info sheet's panel 08.

### 5.3 Rheo: feeling the goo resist your finger

The finger in the tank is **kinematic**: the probe follows the touch exactly, and a glass screen cannot push back. The only force feedback is therefore the hum. LabKit maps the quantity the user is actually fighting, **the stress at the finger**, onto it. Stress spans six decades across Rheo's materials (water about 0.01 Pa, jammed oobleck about 10 kPa), and perceived vibration magnitude is roughly logarithmic, so the map is logarithmic.

**Per frame** (main actor, after the solver's substeps; *proposal*, constants to tune on device):

1. Probe statistics, from a GPU reduction read back one frame late (about 17 ms of extra latency, accepted). The reduction runs over particles within 1.5 r_f of the finger centre, where r_f is the Finger knob, default 8 mm:
   - σ̄ = mean equivalent shear stress τ̄_p (Pa), the 2D von Mises (= Tresca) value from the return map (`rheology-models.md` §1, item 4);
   - s_f = the fraction of those particles that are unyielded (τ̄_p < τ_y) or jammed (Wyart–Cates contact fraction past jamming), 0…1;
   - v_f = the finger speed (m/s).
2. Smooth against particle noise: σ̃ ← σ̃ + (σ̄ − σ̃)(1 − e^(−Δt/0.03 s)).
3. **Intensity** I = clamp(0.15·log₁₀(1 + σ̃ / 0.1 Pa), 0, 1). It saturates at σ̃ ≈ 460 kPa.
4. **Sharpness** S = clamp(0.15 + 0.70·s_f + 0.15·min(1, v_f / 0.5 m/s), 0, 1). Viscous liquids feel dull, and yielded-solid and jammed regions feel crisp.
5. `haptics.noteCause()`, then `haptics.updateHum(intensity: I, sharpness: S)`. The engine multiplies by strength.
6. With no finger in the tank: I = 0.10·√min(1, E_k / E_ref), S = 0.2, where E_k is the tank's kinetic energy per unit depth and E_ref = ½ ρ A_fill (0.1 m/s)². You feel the slosh settle after a shake. The causal idle (8 s) then ends it.

**What the map gives** (computed [C]; finger at 0.1 m/s with r_f = 8 mm, so a shear-rate scale of v/r ≈ 12.5 s⁻¹; material numbers from `rheology-models.md` §3.1, §3.3, §3.4.2 and §3.8):

| Material, situation | σ̃ (Pa) | I | S | Feels like |
|---|---|---|---|---|
| Water, 1.0 mPa·s | 0.0125 | 0.008 (below 0.02: silent) | — | nothing, which is honest |
| Glycerol, 1.41 Pa·s at 20 °C | 17.7 | 0.34 | 0.18 | a soft, dull drag |
| Honey, about 10 Pa·s (assumed) | 125 | 0.47 | 0.18 | a firm, dull drag |
| Ketchup (HB: τ_y 15 Pa, k 12 Pa·sⁿ, n 0.25) | 37.6 | 0.39 | about 0.4 | lighter than honey once moving |
| Mayonnaise (τ_y 85 Pa, k 20 Pa·sⁿ, n 0.22) | 120 | 0.46 | about 0.53 (s_f ≈ 0.5) | as strong as honey, but crisper: it holds around the finger |
| Oobleck, slow drag | about 10 | 0.30 | 0.2 | soft |
| Oobleck, punch at 1 m/s, φ 0.52 (Σ = ρ k U₀² = 11.4 kPa) | 11 400 | **0.76** | **1.0** | a hard knock: "it holds" |
| MR fluid with a magnet 1 cm away (τ_y 36.4 kPa) | 36 400 | 0.83 | about 0.8 | nearly rigid |

**Events** (transients, on top of the hum):

| Event | Haptic | Rule |
|---|---|---|
| Stress at the finger crosses τ_y upward (toothpaste starts to flow) | `.detent` | re-arms when σ̃ < 0.8 τ_y, so it cannot chatter |
| Jam onset (oobleck punch) | `transient(0.9 + 0.1·jamFraction, 0.85)` | once per onset; the hum sharpness then holds near 1 while jammed |
| Unjam (it liquefies under the finger) | `.release` | once |
| Granular jamming texture | `transient(0.30…0.55, 0.95, minGap: 0.025)` at a Poisson rate = min(40 s⁻¹, 200 × jammed-fraction change per second) | Gyre's crackle style |
| MR fluid near the magnet | Gyre's crackle law: above 120 µT, rate min((B − 100)/30, 30) s⁻¹ with 0.3…1.7 × jitter; intensity 0.35 + 0.4·depth, sharpness 1 (`GyroModel.swift:712-718`; prototype `crackle(fieldMicroTesla:depth:clock:)`) | |
| A droplet pinches off | `transient(0.4, 0.3)` | `minGap` 0.05 |
| Mic-driven "oobleck monster" burst (Listen > 0) | `.ripple` per onset | gated by the 0.2 s self-trigger window |
| Refill | `ramp(duration: 0.55)` | Gyre's spin-up, reused as a pour |

The simulator reports `supportsHaptics == false` (`toolchain-checks.md` §6). **Every number in this section can only be judged on the iPhone 15 Pro Max**, so §10 lists it as unverified.

### 5.4 Vocabulary (`HapticTap` constants)

`minGap` is the minimum time since the last admitted transient of any kind (one shared clock). Taps already deduplicated by state (entering a detent, a new switch position, a double-tap) get 0, so they are never dropped. Taps from a continuous stream get ≥ 0.045 s.

| Constant | Prototype name (kept as a deprecated alias) | I | S | minGap (s) | Use | Source |
|---|---|---|---|---|---|---|
| `.tap` | — (new) | 0.64 | 0.50 | 0.028 | every button and menu open | Orbitals `.touch` (`:30, 39, 73`) |
| `.grab` | `knobGrab` | 0.45 | 0.70 | 0.035 | knob grab, tray open, slider begin | Gyre `GlassKnob.swift:106` |
| `.tick` | `knobTick` | 0.32 | 0.90 | 0.045 | 24 per sweep; keyboard nudges | Gyre `:133`; interval from Orbitals `:100` |
| `.detent` | `knobDetent` | 0.90 | 0.30 | 0 | entering a labelled detent; Rheo's yield crossing | Gyre `:125` |
| `.switchClick` | `knobSwitch` | 0.90 | 0.35 | 0 | a rotary switch position | Gyre `:114` |
| `.release` | — (new) | 0.34 | 0.38 | 0.035 | knob or slider release; unjam | Orbitals `.release` |
| `.boundary` | — (new) | 0.95 | 0.64 | 0.090 | end stop, failed action, "Feel a detent" | Orbitals `.boundary` |
| `.reset` | `knobReset`, `modeChange` (0.6, 0.5) | 0.70 | 0.40 | 0 | double-tap reset, page reset | Gyre `:89`; `GyroModel.swift:298` |
| `.soft` | `fold` (0.4, 0.5), `expand` (0.35, 0.6), `toggle` (0.5, 0.6) | 0.40 | 0.55 | 0.035 | fold, expand, pause, chrome toggles | Gyre `Console.swift:249`, `TopBar.swift:161`, `GyroModel.swift:313` |
| `.select` | `select` | 0.70 | 0.55 | 0 | a material or object tile chosen | `GyroModel.swift:287` |
| `.place` | `place` | 0.85 | 0.35 | 0 | AR placement | `GyroModel.swift:333` |
| `.poke` | `poke` | 0.90 | 0.45 | 0.050 | touching the simulated world | `GyroModel.swift:818` |
| `.ripple` | `ripple` | 0.75 | 0.50 | 0.050 | a sound-driven kick | `GyroModel.swift:676` |
| — | `knobNudge` (0.4, 0.8) | removed | | | VoiceOver uses `selection()`; the keyboard uses `.tick` | `GlassKnob.swift:155` |
| `selection()` | — (new) | system | | 0.035 | pickers, chips, toggles, VoiceOver steps | Orbitals |
| `success()` | — (new) | system `.success` | | 0.06 | experiment applied, reset all | Orbitals |
| `ramp(duration:from:to:click:)` | same | continuous 0.9 / 0.3 with curves 0.1→1 and −0.3→0.4, then a click (1, 0.9) at duration + 0.01 | | — | winding up; Rheo's Refill pour | Gyre `Haptics.swift:113-142` |
| `transient(intensity:sharpness:minGap:)`, `crackle(...)` | same | free | | 0.03 default | crackle, granular texture | Gyre |

Gyre's merged `.soft` changes its fold, expand and toggle feel by at most 0.1 intensity. A Gyre port that wants the exact values keeps them as app-level `HapticTap`s. The prototype's line comments cite `GyroModel.swift` about 7 lines low (poke `:811`, ripple `:669`, crackle `:705-711`); the current lines are `:818`, `:676` and `:712-718`.

### 5.5 Lifecycle wiring (copy this)

```swift
// App root (OrbitalsApp pattern, LabKit form)
.onChange(of: scenePhase) { _, phase in
  model.setActive(phase == .active)            // pauses the sim clock, sensors and synth
  if phase != .active { haptics.stop(); model.save() }
}
// HapticEngine.init: one observer for its lifetime, no timers (OrbitalHaptics.swift:47-56)
NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) {
  @Sendable [weak self] _ in Task { @MainActor in self?.stop() }
}
// Per frame, from LabRenderScene.advance(dt:)
if causeIsLive { haptics.noteCause() }
haptics.updateHum(intensity: wish.intensity, sharpness: wish.sharpness)   // policy, fade and ≤ 40 Hz inside
```

### 5.6 Engine settings (changes to the prototype's `HapticEngine`, §1.3 #20)
- `playsHapticsOnly = true` (both apps).
- **`isAutoShutdownEnabled = true`** (Orbitals). Gyre sets `false` because its hum is near-constant; under the causal policy the engine idles most of the time, and auto-shutdown saves power. The stopped handler marks the engine not running, and the next play calls `start()`. *Inferred*: restart latency on the 15 Pro Max is unmeasured. If the first tick after idle feels late, call `engine.start()` on knob grab or touch-down, before the first tick.
- Cache one player per `HapticTap`, plus one per sharpness bucket (0…10) for free transients (Orbitals `players[pulse]`; scratch `LabHaptics.swift`). Apply strength with `hapticIntensityControl`. Recreate the players on `resetHandler`.
- Without Core Haptics, or after an error, fall back to `UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: strength × tap.intensity)` (Orbitals `:188`).
- Hum gating: `ProcessInfo.isLowPowerModeEnabled` or `thermalState ≥ .serious` stops the hum (scratch `LabHaptics.constrained`). Observe `NSProcessInfoPowerStateDidChange` and `thermalStateDidChangeNotification` so the hum stops at once, not on its next frame.

### 5.7 Swift 6 hazard: Core Haptics handlers (verified in the earlier pass)

The probe `$S/isolation-probe` reproduces the shape of `CHHapticEngine.stoppedHandler`: an un-annotated Objective-C block property called on an internal queue. The closure is formed inside a `@MainActor` class, as in `OrbitalHaptics.swift:136-145`.

| Variant | Compiles? | Runtime |
|---|---|---|
| Orbitals as written: `{ [weak self] _ in Task { @MainActor … } }` | yes | fine, because it only hops |
| The same closure touching `self.running` **synchronously** (`ProbeInferredSync`) | **yes, with no diagnostic** | runs **off the main thread** (`Thread.isMainThread == false`) with no isolation trap: a silent data race |
| `{ @Sendable [weak self] _ in self?.running = false }` (`ProbeSync`) | **error**: "main actor-isolated property 'running' can not be mutated from a Sendable closure" | — |
| `{ @Sendable [weak self] _ in Task { @MainActor … } }` | yes | fine |

Rule: **every Core Haptics, AVAudio and CoreMotion handler closure in LabKit is written `{ @Sendable … }`**, so the compiler forbids synchronous main-actor access. The prototype already does this (`Haptics.swift:73-82`). Orbitals' code is correct only because nobody has edited it to touch state directly.

---

## 6. Sound: patterns from spectra-lab, merged with Gyre

### 6.1 What spectra-lab does [S] (`src/ui/feedback.js` in full, `controls.js:159-189`, `app.js:174-181`)

1. **Two layers.** The **hum** is one continuous sine voice per enabled source, at a pitch mapped from its real frequency. The **cues** are short blips for events.
2. **Pitch mapping (log → octaves).** `pitchFor(f) = 110 · 2^(4·(log10 f − 5.5)/(21.5 − 5.5))` Hz (`feedback.js:8-9`), mapping 16 decades (about 300 kHz to 3×10²¹ Hz) onto 4 octaves above A2. The code comment (`:4`) and the README (`:30`) both say "15 decades"; the constants span 16.
3. **Voice levels.** Hum gain is `0.05 / max(1, n)` per voice (sum-normalised), with master gain 0.9 (`:41`). Frequency glides with `setTargetAtTime(…, τ = 0.03 s)` and gain with τ = 0.06 s (`:60-61`), so changes never click. The hum is silent when paused or when sound is off; tones update at 10 Hz from `slowTick` (`app.js:179-180`).
4. **Cues** (`detent(kind)`, `feedback.js:96-105`). Each blip is a triangle oscillator unless noted, with an exponential pitch drop to 0.6× and a gain decay to 10⁻⁴ over its duration (`:65-77`). **Every cue is paired with a haptic of the same class.**

   | Kind | Sound | Haptic (ms) | Use |
   |---|---|---|---|
   | `tick` | 2200 Hz, 12 ms, gain 0.025; ≥ 45 ms apart | 4 | a quantised dial step |
   | `band` | 1400 Hz, 35 ms, 0.08 | 10 | a band edge crossed (a labelled detent) |
   | `ionizing` | 95 Hz **sine** 160 ms 0.22 + 1800 Hz 30 ms 0.07 | [18, 40, 18] | a hard physical threshold |
   | `resonance` | 220 Hz **sine**, 250 ms, 0.12 | 24 | crossing a specimen's resonance |
   | `action` | 900 Hz, 30 ms, 0.05 | 8 | any button |

5. **Off by default** (`state.js:36`: `feedback: { sound: false, haptics: true, strength: 0.7 }`). Browsers allow audio only after a user gesture, so turning Sound on calls `unlock()` and plays an `action` cue (`controls.js:159`). Haptic durations scale by `0.4 + 0.6·strength` (`feedback.js:86`).
6. Settings copy (`controls.js:186-188`): "Each source hums at a pitch set by its frequency; band edges click." and "Detents at band edges, a firm stop at the ionizing line." When the device cannot vibrate: "This browser can't vibrate. The native app uses Core Haptics."

### 6.2 What Gyre and the prototype do [S]
- Sound is **on by default** (`soundOn = true`, `GyroModel.swift:156`) and is not persisted. The "Rotor sound" toggle sits in Layers › Feel (`TopBar.swift:81`).
- The rotor hum synth runs only while `soundOn` and the model runs (`GyroModel.swift:249, 710`), and stops with the model (`:266`). Its controls are set per frame (`:700-709`): level = min(1, spin^0.6·1.15), hiss, whoosh, wobble, vibrato and pan. The prototype lifts the kernel verbatim as `RotorHumKernel`. Its control slots are `Atomic<UInt64>` bit patterns, because Gyre's plain Doubles are a data race under Swift 6 (`$P/Sources/LabKitFeedback/Synth.swift:7-24`).
- The audio session is `.ambient` with `.mixWithOthers` while the mic is off, which **respects the ring/silent switch**. With the mic on it becomes `.playAndRecord` + `.measurement` (`MicListener.swift:11-16`; prototype `AudioRoute.apply()`), which **plays through the silent switch**.
- The prototype also handles iOS 27's replacement interruption notifications (`AudioRoute.swift:22-36`), which Gyre does not.

### 6.3 LabKit sound policy (pick)
1. **Two layers**, as in spectra-lab:
   - **Sound bed**: at most one continuous voice per app, a `SynthKernel` driven by the hero quantity;
   - **Cues**: `SonicCue` events, each paired with a `HapticTap`.
2. **Default on, following the ring/silent switch** (`.ambient`), like Gyre. In these toys sound is content, and the silent switch is the user's global "off". spectra-lab's off-by-default was a browser constraint. **Persist** the toggle (`"<App>.sound"`); Gyre does not.
3. **Silence rules.** The bed is silent when:
   - the simulation is paused or the app is not active;
   - nothing is moving (bed level ∝ activity, with the hum's 0.25 s lag);
   - Low Power Mode is on (the bed only; cues stay).
4. **With the mic live** (`.playAndRecord`, which ignores the silent switch):
   - duck the bed to × 0.3;
   - suppress cues whose fundamental falls inside the mic band the app listens to (Rheo's Band knob ± 1 octave);
   - open the 0.2 s onset-ignore window after every cue, so Rheo's own sound cannot drive its oobleck monsters.
   - **Echo-cancelled input is a runtime option, never an assumption.** `setPrefersEchoCancelledInput(_:)` is iOS 18.2+, "only available on certain 2024 or later iPhone models", and valid only with `.playAndRecord` + `.default` mode or `.multiRoute` + `.dualRoute` (`AVAudioSession.h:181-203`, iPhoneOS27.0 SDK; verified). Query `isEchoCancelledInputAvailable` (`:215`). The 15 Pro Max (2023) is very likely excluded (*inferred* from the header text), and Gyre's `.measurement` mode is not one of the valid configurations anyway.
5. **Mapping helper** in Core: `public func logPitch(_ x: Double, domain: ClosedRange<Double>, base: Double = 110, octaves: Double = 4, inverted: Bool = false) -> Double` = `base · 2^(±octaves·(log10 x − log10 lo)/(log10 hi − log10 lo))`. This is spectra-lab's formula with the domain made explicit.
6. **Cue table**: spectra-lab's values as the default `SonicCue` set; apps may retune them.

   | `SonicCue` | Sound | Paired `HapticTap` |
   |---|---|---|
   | `.tick` | 2200 Hz triangle, 12 ms, 0.025 | `.tick` |
   | `.detent` | 1400 Hz triangle, 35 ms, 0.08 | `.detent` |
   | `.threshold` | 95 Hz sine 160 ms 0.22 + 1800 Hz 30 ms 0.07 | `.boundary` |
   | `.resonance` | 220 Hz sine, 250 ms, 0.12 | `.poke` |
   | `.action` | 900 Hz triangle, 30 ms, 0.05 | `.tap` |

7. **Phone-speaker floor.** The built-in speaker reproduces little below about 200–300 Hz (*inferred*, not measured here). spectra-lab's 110 Hz sine and the 95 Hz `.threshold` thump will be mostly inaudible on the phone. LabKit voices below 300 Hz therefore carry harmonics (Gyre's rotor hum adds 2nd and 3rd blade harmonics, `$P/Sources/LabKitFeedback/Synth.swift:158-160`), and `.threshold` keeps its 1800 Hz click as the audible part. Check on the device (§10).
8. **Rheo bed: the "gloop" voice** (*proposal*).
   - Pitch f = 880 · 2^(−3·p) Hz, where p = (log₁₀ η − log₁₀ 10⁻³)/(log₁₀ 10⁵ − log₁₀ 10⁻³) is the position of the tank's mean viscosity on 1 mPa·s…100 kPa·s. Water sings at 880 Hz and a near-solid hums at 110 Hz: thicker sounds lower.
   - Timbre: a band-limited sawtooth through a 2-pole low-pass whose cutoff tracks 4 f, so low notes keep audible harmonics on the speaker.
   - Level = 0.2 × activity (Gyre's × 0.2 output stage), with activity = √min(1, E_k / E_ref) as in §5.3.
   - Squelch: band-passed noise bursts (centre 600–1500 Hz, 40 ms) on topology changes (a droplet pinch-off, a jammed crack), at most 8 per second.
   - Granular clicks follow the same Poisson rate as the haptic texture in §5.3.
   - Settings copy (§7.5): "The fluid gloops at a pitch set by its thickness: thick fluids sound low. Follows the silent switch."
9. Sound never carries information that is not also visible (§4.1).

---

## 7. Copy and voice rules

### 7.1 Spelling: British, everywhere a person reads it
- **Pick: British English** for every user-visible string, usage string, info-sheet paragraph, README and note. Subtext and Cipher, the newest apps, are British ("analysed", "recognises"; house rules §2). Tether and Orbitals are American ("visualizations", `Orbitals/project.yml:27`). Gyre is mixed: the label says "Harmonic center" (`TopBar.swift:67`) while its own description says "the bubble's centre" (`InfoSheet.swift:37`).
- Word list: colour, centre, metre (unit) and meter (instrument: "level meter"), analyse, recognise, visualise, behaviour, modelled, labelled, travelled, licence (noun) and license (verb), grey, mould, sceptical, fibre, sulfur (IUPAC spelling, the one exception), program (software), yogurt (Oxford accepts it; it is the user's word).
- **Code identifiers stay American where Apple's API is** (`Color`, `.center`, `.foregroundStyle`). LabKit's own API uses British words where it coins them (`colour:` labels, `LabColor` type name kept from the Gyre note). Strings shown to people are always British.
- **Avoid the cornstarch/cornflour split.** The UI says **"oobleck"** everywhere: the material, "Oobleck punch", "Oobleck monsters". The info sheet's first mention reads "oobleck: cornflour (cornstarch) and water". The literature term "cornstarch monsters" (Merkt et al. 2004) appears only inside a citation.

### 7.2 Numbers, units and symbols
- Follow `LabFormat` (§2.5): a normal space between number and unit ("12.4 Pa·s", "20 °C"); a middle dot inside compound units; superscript exponents ("s⁻¹"); U+2212 for minus; "×0.25" for multipliers; "46%" without a space; the separator " · ".
- Ranges use an en dash with the unit once: "10–40 °C". Write "about 10 kPa", never "~10 kPa", in prose.
- Quantity symbols are serif italic and never case-transformed (§2.5). In UPPERCASE labels only the word is uppercased: "η VISCOSITY", not "Η VISCOSITY".
- Spoken forms per §4.2 rule 3.

### 7.3 Voice
- Second person, present tense, concrete physical verbs: poke, stir, tilt, shake, shout, punch, pour.
- No "we", no "simply" or "just", no exclamation marks, no "magic". Numbers beat adjectives in subtitles: "Shake 12 g at 120 Hz", not "Shake it really hard".
- Sentence case for titles and buttons. Console page titles are one word; knob titles one or two; experiment titles ≤ 22 characters; subtitles ≤ 48 characters; knob hints ≤ 110 characters; descriptors ≤ 36 characters (§3.3, §3.11).
- Field notes follow one pattern: **what you do → what happens → why, in one sentence of physics → the caveat.** For example: "Punch the oobleck. It holds like a solid, then flows again once your finger stops. The starch grains jam into a solid front that grows faster than your finger moves. The real front is 3D; this tank is a thin slice."
- Status lines are a symbol plus one human sentence (Subtext's pattern, house rule 13): "Listening", "Simulated motion. Drag in the tank with two fingers to tilt."

### 7.4 Permissions and usage strings
- **Voice** (house rule 4): `"<App> <verb>s … so it can <benefit>."` followed by a privacy sentence. Use plain words, the app's name as the subject, no "we", no "in order to".
- **Timing** (house rule 3): just in time, on the tap that needs it, never at launch. Rheo asks for the microphone the first time Listen is turned above 0 or the mic toggle is switched on.
- **Rheo needs exactly one usage string.** Device motion and the magnetometer through `CMMotionManager` need none; only altimeter, pedometer and activity APIs do (`CMAltimeter.h:57`, house rules §5). Rheo does not use them.

  > `NSMicrophoneUsageDescription`: "Rheo listens to the room so sound can shake the fluid, the way a speaker shakes a tray of oobleck. Nothing is recorded or kept."

  "Nothing is recorded or kept" is Gyre's sentence (`Gyre/project.yml:29`), and it is true of the prototype's microphone: a 16 384-sample ring, constantly overwritten and zeroed on stop (`$P/Sources/LabKitSensors/MicListener.swift`).
- **Denied**: `PermissionGate` (§3.9) with the message "Rheo can't hear the room. Allow the microphone in Settings to let sound shake the fluid. Everything else keeps working." and an "Open Settings" button.

### 7.5 Honesty and provenance (the house rule that matters most)
1. **Every number has a provenance word** (§3.10): measured, modelled, live, simulated or illustrative. Colour only reinforces the word.
2. **State every simplification where it matters**, in the info sheet's panel 06 "What's real and what's illustrative" (spectra-lab's title, `notes.js:23`). For Rheo:
   - "The tank is a thin slice, 3 mm deep, so the fluid moves in 2D." The 3 mm gap is a solver decision; quote the solver note's value.
   - "Time runs at the speed shown in the corner."
   - "The tank is drawn life-size." (§9.2)
   - "Depth shading, glow and dye lines are display choices."
   - "The vibrating floor is simulated. Your phone can't shake at 10 g."
3. **Name every side effect**: an experiment's subtitle or banner says what it resets, using the generated `ExperimentEffects.sentence` (§3.11). Orbitals: "Presets restart the simulation and recorded history." (`ControlsView.swift:98`).
4. **Cite every real-world claim** with a `Citation` carrying a checked date, in panel 09. A claim the solver has not reproduced is worded as the real phenomenon, not as a feature. For example: "Real oobleck forms holes that persist on a speaker (Merkt et al. 2004). This tank may or may not; it is a 2D slice." (`rheology-models.md` §3.4.3 marks the 2D outcome untested.)
5. **Name UI by its live label, generated from the specs**: `"Turn up \(spec(.listen).title) on the \(page(.signals).title) page"`, never a hard-coded "Sound page". Gyre's info sheet still says "the Sound page" (`InfoSheet.swift:41`), but its pages are Physics, Signals and Object (`Console.swift:4-6`). LabKit adds a `CopyLintTests` unit test. It scans the info-sheet and experiment strings for capitalised page and knob names that are not registered, and for American spellings from §7.1's list.
6. **Spoken copy is written, not derived**: `spokenValue` and `glyphSpoken` exist so VoiceOver never reads "s superscript minus one".

### 7.6 Rheo copy examples (ready to use)

| Where | Copy |
|---|---|
| Canvas tags | "THIN TANK · OOBLECK" (top-left); "LIFE-SIZE" (top-right; "×2" while zoomed) |
| Gesture hint | "Poke · stir · tilt · shout" |
| Yield hint | "Stress needed before it flows at all. Below it, the fluid holds its shape." |
| Packing hint | "How crowded the starch grains are. Crowded enough, a hard hit jams it solid." |
| Shake hint | "Peak acceleration of a vibrating floor, like a speaker under a tray." |
| Experiment | "Oobleck punch" · "Hit it hard and it holds" · banner: "Punch fast: the grains jam into a solid. Stop, and it flows again." |
| Experiment | "Oobleck monsters" · "Shake 12 g at 120 Hz" · banner: "Above about 10 g, poke a hole and it may stay open." |
| Experiment | "Honey vs ketchup" · "Same pour, different flow" |
| Experiments section | "Experiments · each refills the tank and restarts the clock." (generated) |
| Feel toggle note | "A buzz while your finger is in the fluid, stronger and sharper as it resists." |
| Sound toggle note | "The fluid gloops at a pitch set by its thickness: thick fluids sound low. Follows the silent switch." |
| Simulated note | "Simulated motion. Drag in the tank with two fingers to tilt." |
| Mic denied | "Rheo can't hear the room. Allow the microphone in Settings to let sound shake the fluid. Everything else keeps working." |
| Provenance: modelled | "Calculated from a physical model. Trust its shape more than its third digit." |

---

## 8. Contradictions between the sources, and the pick for LabKit

Rows are grouped by area. "Pick" is binding for LabKit; "Why" names the deciding source or measurement.

| # | Topic | Orbitals | Gyre (and LabKitProto) | Tether / spectra-lab / others | **LabKit pick** | Why |
|---|---|---|---|---|---|---|
| 1 | Ground | phosphor green-black (0.025, 0.045, 0.040) | pure black stage | Tether night violet; spectra = Orbitals | One `LabGround` per app; Rheo uses abyss | Identity per app, shared rules (§2.2) |
| 2 | Where the accent goes | phosphor on primary *and* secondary glass buttons (`InstrumentControlSheet.swift:100`) | secondary glass white; primary (0.2, 0.62, 0.85) | Tether violet on every pill | **Signature only for primary and selected**; secondary is white on glass | One meaning per colour (§2.1 rule 2) |
| 3 | Label on a prominent fill | white on phosphor, **1.40:1** | white on (0.2, 0.62, 0.85), **2.98:1** | — | Computed `onSignature`; `signatureDeep` for system-drawn fills | WCAG 1.4.3 (§2.3) |
| 4 | Panel style | solid `panel` + white hairline 0.07 | `List` sections | Tether gradient + accent stroke 0.16 | Orbitals | Readouts need a fixed-contrast ground |
| 5 | Type on surfaces | monospaced panels and readouts | SF Pro + `.monospacedDigit()` | spectra monospaced readouts | **By surface**: monospaced on opaque instruments, SF Pro digits on glass | Gallery: monospaced truncated the telemetry card (§2.5) |
| 6 | Knob | card dial 104 pt, 31 ticks, slider, 240 pt travel in *value* space | compact 84 pt, 230 pt travel in *position* space, labelled detents, switches | — | One `GlassKnob`, two styles, 230 pt in position space | Log knobs need position space (§3.4) |
| 7 | Quantisation anchor | lower bound | zero (`Params.swift:100`) | — | Lower bound | Ranges like 0.25…3 (§1.3 #6) |
| 8 | Precision control | linear slider under every dial | none (console height) | — | Slider on `.card`; long-press tray on `.compact` | Three routes without console height (§3.4) |
| 9 | Value format | `precision + unit` | closures | spectra `sig3`, `sci` | `ParamFormat` + `LabFormat` | Testable and consistent (§1.3 #5) |
| 10 | Continuous haptics | never | always while spinning | spectra never | **Causal** by default; `.ambient` opt-in | §5.2 |
| 11 | Haptic strength | 0.2…1, default 0.85, "Intensity" | none | spectra 0…1, default 0.7 | 0.2…1, default 0.85, "Strength" | Orbitals values; the toggle is the off switch |
| 12 | When haptics stop | any non-active scene phase | `.background` only | Tether non-active | Any non-active phase, plus a background observer | Inactive is not foreground (§5.2 rule 2) |
| 13 | Engine auto-shutdown | true | false | — | true | Causal hum idles (§5.6) |
| 14 | Haptics under VoiceOver | `selection()` | custom nudge tap | — | `selection()` | Platform convention |
| 15 | Sound default | — | on, not persisted | spectra off (browser rule) | On, persisted, follows the silent switch | §6.3 |
| 16 | Info presentation | numbered panels in sheets | `List` sheet, medium/large, background interaction | Tether `Surface` cards in a full-height sheet | Numbered `InstrumentPanel`s in a medium/large sheet with background interaction | Phosphor identity + a live stage (§3.9) |
| 17 | Feedback settings location | "Physical feedback" panel in the controls sheet | Layers › Feel toggles | Tether Settings "Feel"; spectra "04 Feedback" | Toggles in Layers › Feel; strength and "Feel a detent" in info panel 08 | House rule 6 (live controls on the surface) |
| 18 | Presets | "Experiment preset" menu, restarts the simulation and history | "Experiments" menu, values only | spectra "Field trips" restart the clock, toast note | "Experiments", derived identity, generated effects sentence, 6.5 s banner | §3.11 |
| 19 | Choosing a mode or thing | explicit chips (a menu hid the active mode) | tiles; menus | spectra chips | Chips or tiles for things; rotary switch for instrument modes; menus only for one-shot actions | Orbitals build-5 lesson (§3.5) |
| 20 | Rheo's Material in the top bar | — | — | the brief puts Material in the top bar | A top-bar **glyph showing the current material's icon in its data hue**, which drops a tile shelf, not a menu | Keeps #19: the active material is always visible (glyph + canvas tag + telemetry) |
| 21 | Persistent access to controls | "Dials" button top-left on every surface | console always on screen, with fold | — | Console always on screen; **Rheo omits the fold** | The tank floor must not move under the fluid (§9.3) |
| 22 | Minimum hit area | 44 pt | 36 pt | spectra 44 px glass buttons, 40 px chips (`spectra.css:38, 61`) | 44 pt (36 pt glyph frames inside) | HIG, Orbitals (§4.6) |
| 23 | Legend swatch colour | — | renderer's linear `HoloPalette` passed to `Color(red:…)` (`InfoSheet.swift:108-113`), so swatches are darker than the lines | — | Legend and renderer read the **same encoded token**; the renderer converts it to linear | One source of truth (§2.4) |
| 24 | Hairlines | white 0.07 | — | Tether accent × 0.16 | white 0.07, or 0.22 under Increase Contrast | Neutral chrome |
| 25 | Dynamic Type for chrome over the stage | sheets uncapped | uncapped, which breaks at AX XXXL | — | Cap at `.accessibility1` + Large Content Viewer; sheets uncapped | Measured (§4.3) |
| 26 | Reduce Motion | nils animations, removes symbol effects | parks shader effects | spectra auto-pauses | Nil animations + shader lane; **never auto-pause** | The simulation is the content (§4.4) |
| 27 | Canvas labels | fixed 9 pt | — | spectra 9.5–10 px | `@ScaledMetric` 9, capped at 14; never over the fluid | §3.13, measured |
| 28 | Spelling | American | mixed ("center" label, "centre" body) | Subtext, Cipher British; Tether American | **British** | Newest apps; §7.1 |
| 29 | Provenance vocabulary | — | orange "simulated" rows | spectra `table`/`model`; Tether "calculated vs interpreted" | Five words: measured, modelled, live, simulated, illustrative | §3.10 |
| 30 | Shear thickening in the knob set | — | — | the scratch gallery's Flow index ran 0.2…2 with a "Shear-thickening" detent; `rheology-models.md` §1 item 3 restricts **n ≤ 1** | Flow index 0.2…1; thickening comes from the **Packing** knob (Wyart–Cates φ) | The physics note wins: n > 1 is not how the solver thickens |
| 31 | Console API | — | prototype: `ConsolePage` struct + `activeKnob` binding | scratch: `ConsolePage` protocol + `KnobSlot` | Prototype struct + `knobs`, one `KnobFocus` binding | Simpler; the prototype is the starting code (§1.3 #14) |
| 32 | Console height across pages | — | varies by page (the canvas resizes) | — | `uniformHeight` by default | A fixed tank floor (§3.7) |
| 33 | Multiplier style | — | both "×%.2f" (`Knobs.swift:121, 163`) and "%.2f×" (`:180`) | the scratch gallery's chip used "0.25×" | **"×0.25"** everywhere (`ParamFormat.multiplier`) | One format (§2.5) |

**Prototype versus this spec.** Every difference is listed once, in §1.3, so it is not repeated here.

---

## 9. Rheo's screen: a concrete layout from these components

**Device:** iPhone 15 Pro Max (A17 Pro), portrait only, iPhone only (house rules §4: device family). 430 × 932 pt at @3x (1290 × 2796 px, 460 ppi). **Measured** in the gallery on an iPhone 15 Pro Max simulator running iOS 27.0 (`-rheo`, `$S/frames-*.txt`): safe-area insets are top **59**, bottom **34**. Every size below is measured unless marked *proposal*.

### 9.1 Wireframe (y in pt, portrait)

```
y   0 ┌──────────────────────────────────────────────┐  Metal view: full-bleed 430 × 932, ignoresSafeArea
      │            (Dynamic Island; status bar hidden by .labChrome)
y  59 ├──────────────────────────────────────────────┤  tank ceiling = safe-area top
y  65 │ ╭ η 12.4 Pa·s ─────────╮  ╭hand flask lyr i╮ │  LabTopBar (glass), x 16–414, h 55.3
      │ │ γ̇ 3.20 s⁻¹ · σ 39.7 Pa│  ╰───────────────╯ │   telemetry card 173 × 55.3; group 176 × 44
y 120 │ ╰───────────────────────╯                     │
y 128 │ [Oobleck][Ketchup][Slime][Honey][MR flu…  ⟩   │  material shelf (on demand): h 66, tiles 76 × 62
      │ THIN TANK · OOBLECK                LIFE-SIZE  │  stage tags (headspace)
      │          Poke · stir · tilt · shout           │  gesture hint (headspace, fades on first touch)
      │                                               │
      │            ~ ~ ~ free surface ~ ~ ~           │  THE TANK: x 0–430, y 59–671.3
      │ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ │  430 × 612.3 pt = 71.2 × 101.4 mm, life-size
      │ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ fluid (data hue) ▓▓▓▓▓▓▓▓▓▓▓▓ │
y 671 ├───────────── tank floor (hairline) ───────────┤  ═ console top; the Rheometer strip's top edge lands here
      │        ╭ Fluid │World│Touch│Signals│View ╮    │  .tabs picker, x 55–375 (320) × 31
y 712 │   ◯         ◯          ◯          ◯           │  one row of 4 compact knobs, 406 × 119.7
      │  YIELD   CONSISTENCY  FLOW INDEX  PACKING     │  (columns 101.5 pt; dial 84)
      │  None    13.6 mPa·sⁿ    1.00       0.517      │
y 844 │ (▲ Refill) (pause) (chart)              (↺)   │  controls row 406 × 50: Refill 94, circles 50
y 894 │                                               │  4 pt bottom padding
y 898 ├──────────────────────────────────────────────┤  safe-area bottom (home indicator), 34 pt
y 932 └──────────────────────────────────────────────┘
```

Screenshots: `$S/shots/rheo-15pm-fluid.png` (this layout on the Fluid page), `rheo-15pm-strip.png` (World page, shelf open, Rheometer strip up), `rheo-15pm-rheometer-large.png`, `rheo-15pm-axxxl.png` (Signals page at Accessibility XXXL) and `components-15pm.png` (the component gallery). The gallery leaves the status bar visible, so the shots show the clock. The app hides it.

### 9.2 The tank: full-bleed, life-size

- The **Metal view** covers the whole screen (`LabRenderHost(...).ignoresSafeArea()`). Outside the tank it draws the abyss stage and the tank's glass-wall vignette, so Liquid Glass chrome refracts the stage beneath it.
- The **tank interior** is the `CanvasRegion`: x 0–430 (wall to wall, at the screen edges) and y 59–671.3. Its top is the safe-area top; its floor is the console's top edge. The 15 Pro Max's rounded display corners (about 55 pt) lie above y 55 and below y 877, so the visible tank is a true rectangle. [measured frames; the corner figure is *inferred*]
- **Life-size** (*proposal*). On the 15 Pro Max, 1 pt = 3 px at 460 ppi = **0.16565 mm**, so the tank is **71.2 × 101.4 mm**. The default fingertip probe of 8 mm radius is 48 pt in radius (97 pt across), about the size of a finger pad. Yield lengths become visible at true size: mayonnaise's ℓ_y = τ_y/(ρg) = 8.9 mm is 54 pt, and toothpaste's 11.3 mm is 68 pt (`rheology-models.md` §3.3). iOS has no public physical-ppi API, so `LabMetrics.millimetresPerPoint` comes from a model-identifier table (`iPhone16,2` → 0.16565). On an unknown device the tag "LIFE-SIZE" is hidden and the scale is a plain fit.
- **Simulation domain**: the physical tank is fixed in millimetres, and the camera fits it into the canvas region, letterboxing if the region shrinks (accessibility sizes, §9.8). Cell counts: at Δx = 1.5 mm (`rheology-models.md` §1 item 6) the grid is 47 × 68 = 3 196 cells; at Δx = 0.75 mm it is 95 × 135 = 12 825. With 4 particles per cell and a 45 % fill, that is about 5.8 k or 23 k particles, both inside the 50 k budget of `rheology-models.md` §1 item 7. *The solver note owns Δx and the gap; these are the screen's constraints on it.*
- **Gravity** in the tank is the device gravity's screen-plane components (`MotionSource`) times the Gravity knob. *Proposal*: the out-of-plane component is left to the Hele-Shaw wall-friction model in the solver note.
- **Canvas labels:** tags in the headspace, 14 pt under the top bar (20 pt under the shelf when it is open). The gesture hint goes 20 pt under the tags, never at the floor (measured defect, §3.13).

### 9.3 Why the console never moves, and has no fold
The tank floor is the console's top edge. If that edge moved, the floor would move under the fluid; every pool would fall or be squashed. So:
1. `KnobConsole(… open: nil, uniformHeight: true)`: no fold button, and every page is exactly one row of four knobs, so the console is a constant **226.7 pt** (picker 31 + 10 + row 119.7 + 12 + controls 50 + 4 padding).
2. The Rheometer opens as a sheet *over* the console (§9.6), not by resizing anything.
3. At accessibility sizes the console grows once, on launch or on a size-category change. The tank is then refitted, with the physical size unchanged, while the simulation is paused for that frame.

### 9.4 Top bar
`LabTopBar(card:actions:)`, `.padding(.horizontal, 16).padding(.top, 6)`: x 16–414, y 65–120.3.

- **Telemetry card** (173 × 55.3 pt collapsed): `TelemetryHeadline(icon: "drop.fill", spins: running, headline: "η 12.4 Pa·s", subline: "γ̇ 3.20 s⁻¹ · σ 39.7 Pa", chip: timeScale ≠ 1 ? "×0.25" : nil)`. The headline is the tank's mean viscosity; the subline gives the probe's (or strongest-sheared region's) shear rate and stress. Both update at 10 Hz. Tapping it expands rows with provenance:
  - Tilt "12° from level" (`live`, or `simulated` in the Simulator);
  - Shake "0.04 g" (`live`);
  - Magnetometer "48 µT" (`live`);
  - Microphone "−32 dBFS" or "off" (`live`).

  The simulated note reads "Simulated motion. Drag in the tank with two fingers to tilt."
- **Action group** (176 × 44 pt, four `ToolbarGlyph`s of 42 × 44 plus 4 pt capsule padding each side):

  | # | Glyph | Item | Behaviour |
  |---|---|---|---|
  | 1 | the current material's icon, **in its data hue** | Material | toggles the tile shelf. Label "Material, Oobleck"; identifier `topbar-material` |
  | 2 | `flask.fill` | Experiments | `ExperimentMenu`. Section header "Experiments · each refills the tank and restarts the clock." |
  | 3 | `square.3.layers.3d` | Layers | Menu sections: **Show** (Stress light, Dye lines, Particles, Rheometer cursor); **Feel** (Haptics, Feel the fluid, Sound); **Sensors** (Use tilt, Use the magnetometer) |
  | 4 | `info` | How Rheo works | `LabInfoSheet` (§9.9) |

- **Material shelf**: an on-demand row under the top bar, x 16–414, y 128.3, height 66. `GlassTile`s are 76 × 62 pt with spacing 8, so 4.8 are visible and the row scrolls. Tiles are icon-over-title in the data hue (§3.6), and each subtitle is its hint ("Thins when you shake it"). Choosing a tile plays `.select`, re-registers the material's specs (§1.3 #8), refills the tank, closes the shelf after 0.6 s, and posts "Ketchup. Thins when you shake it." The shelf is chrome over air (headspace), so it never hides fluid.

### 9.5 Console pages: the 20 knobs

Hues are in §2.4. Every knob is `.compact`. Defaults come from the selected material; the values below are the oobleck defaults where they matter. "Dimmed" means opacity 0.55 for materials where the knob does nothing (`KnobGrid(dimmed:)`).

| Page | Knob | Glyph | Range, scale | Detents | Format | Provenance | Notes |
|---|---|---|---|---|---|---|---|
| **Fluid** | Yield | τ_y | 0.1–1000 Pa, log | Ketchup 15, Mayonnaise 85, Toothpaste 150 | "None" at the bottom, else SI Pa | modelled | values from `rheology-models.md` §3.3 |
| | Consistency | K | 0.001–1000 Pa·sⁿ, log | Water 0.001, Glycerol 1.414 | SI Pa·sⁿ | modelled | glycerol at 20 °C, §3.1 |
| | Flow index | n | 0.2–1, step 0.01 | Ketchup 0.25, Newtonian 1 | 2 dp | modelled | **n ≤ 1** (§8 #30) |
| | Packing | φ | 0.40–0.60, step 0.001 | 1 : 1 0.465, Oobleck 0.517, Jammed 0.581 | 3 dp | modelled | Han scale, §3.4.1; dimmed for non-suspensions |
| **World** | Gravity | g | −1…3 g, origin 0, step 0.01 | Zero-g 0, Moon 0.166, Earth 1, Jupiter 2.53 | 2 dp g | live (direction) | |
| | Heat | T | 0–90 °C, step 1 | Fridge 4, Room 20, Body 37 | 0 dp °C | modelled | lava re-registers 1050–1200 °C |
| | Magnet | B | 0–500 mT, step 1 | Off 0, "1 cm away" 207 | "Off", else mT | modelled | §3.8 table; dimmed unless MR fluid |
| | Time | — | ×0.05–×2, log | Slow motion 0.25, Real time 1 | ×2 dp | illustrative | the telemetry chip shows it when ≠ 1 |
| **Touch** | Finger | r | 3–20 mm, step 0.5 | Fingertip 8 | 1 dp mm | modelled | probe radius; minimum 18 pt on screen |
| | Stir | ω | 0–5 rev/s, step 0.05 | Off 0 | "Off", else rev/s | modelled | a paddle at the tank's centre |
| | Shake | a | 0–27 g, step 0.1 | Off 0, Holes 10, Fingers 17 | "Off", else 1 dp g | **simulated** | vibrating floor; thresholds from Merkt et al. 2004, §3.4.3 |
| | Rate | f | 20–200 Hz, log | 50 Hz, Monsters 120 | 0 dp Hz | modelled | |
| **Signals** | Listen | — | 0–1 | Off 0 | "Off", else % | live | how hard sound shakes the tank; the first raise asks for the mic |
| | Drives | — | switch, 5 positions | Shake · Gravity · Stir · Kicks · Heat | labels | — | what the mic modulates |
| | Gain | — | ×0.25–×8, log | Unity 1 | ×2 dp | live | mic sensitivity |
| | Band | f | 40–2000 Hz, log | Bass 80, Voice 300 | SI Hz | live | centre of the mic band that drives the tank |
| **View** | Glow | — | 0–1 | Off 0 | "Off", else % | illustrative | lights the fluid by its shear rate |
| | Grain | — | 0–1 | Off 0 | "Off", else % | illustrative | shows the particles |
| | Tracers | — | 0–1 | Off 0 | "Off", else % | illustrative | dye lines advected with the flow |
| | Depth | — | 0–1 | — | % | illustrative | exaggerates the gap in the shading |

### 9.6 Controls row and the Rheometer

**Controls row** (y 844–894, 406 × 50), from left: `ProminentGlassButton("Refill", icon: "drop.triangle.fill")` (94 pt, `.ramp(0.55)` haptic); `CircleGlassButton("Freeze time" / "Resume", icon: pause.fill / play.fill)`; `CircleGlassButton("Rheometer", icon: "chart.xyaxis.line")`; `Spacer`; `CircleGlassButton("Reset fluid knobs", icon: "arrow.counterclockwise", tap: .reset)`. Identifiers: `action-primary`, `action-play`, `action-rheometer`, `action-reset-page`.

**Rheometer sheet** (identifier `rheometer`):
- `.presentationDetents([strip, .large], selection:)` with `strip = .height(231)`; `.presentationBackgroundInteraction(.enabled(upThrough: strip))`; `.presentationDragIndicator(.visible)`.
- **Measured rule:** on the 15 Pro Max a `.height(h)` sheet's top edge sits at y = 902.4 − h. So `h = 231` puts it at y 668.9, on the console's top edge (671.3), and **no fluid is covered**. The first try, `.height(300)`, covered the tank's bottom 69 pt, exactly where the fluid pools (`$S/shots/rheo-15pm-shelf-rheometer.png`). Apps must compute h from the console's measured frame (`onGeometryChange`) as h = 902.4 − consoleTop, not hard-code it. The 902.4 offset is a simulator measurement for this device class.
- **Strip** (the sheet card is 414 × 222.4 at x 8): `InstrumentPanel("σ·γ̇", "Rheometer", accessory: σ/η segmented picker, 88 pt)` containing:
  - a `LabPlot` of **223 × 131 pt**, log-log σ(γ̇) on 0.01–1000 s⁻¹ × 0.01–10⁴ Pa. Labels land every second decade (`minSpacing` 36). It shows the current material's modelled curve, the other materials faint at 0.35, three iso-viscosity guides (with label culling, §3.12), and the live cursor at the probe's (γ̇, σ);
  - a **readout card**: a single-column `ReadoutGrid(columns: 1)`, 86 pt wide: η (amber, `modelled`), σ (amber) and γ̇ (signature, the cursor's colour). Badges are hidden in the strip and shown at the large detent.
- **Large** (full height from y 59): the same panel with a 374 × 220 plot and the three readouts in one top-aligned row. Then a second `InstrumentPanel("λ·θ", "Fluid memory")` with `.card` knobs for **Memory λ** (0.001–10 s, log, detent "Slime" 0.402 s from `rheology-models.md` §3.5) and **Rebuild θ** (0.1–300 s, log; its 30 s detent is a placeholder until sourced). Then literature points as hollow `measured` markers with their `Citation`s.
- The η view swaps the y axis to `PlotAxis("Viscosity", "η", "Pa·s", 1e-3...1e5, .log10)` (§3.12): shear-thinning slopes down, Newtonian is flat, and DST turns up.
- Updates at 10 Hz. The VoiceOver summary is regenerated per material, not per frame.

### 9.7 Gestures in the tank

| Gesture | Effect | Haptic |
|---|---|---|
| One-finger drag | the finger probe (radius = Finger knob) moves through the fluid: poke, stir, punch (speed is your finger's) | the §5.3 hum and events |
| Quick tap | a poke impulse at that point | `.poke` |
| Pinch | zoom 1–4× around the pinch (illustrative; tag "×2") | — |
| Two-finger drag | simulated tilt, used only when device motion is unavailable (the Simulator) | — |
| Shake the phone | live slosh (user acceleration) | hum while sloshing |
| Sound (Listen > 0) | vibrating floor driven by the mic band | `.ripple` on onsets |

Canvas accessibility (`CanvasRegion`, identifier `stage-canvas`):
- label: "Fluid tank, oobleck";
- value: the §4.2 rule 9 sentence;
- adjustable: stir speed;
- named actions: "Poke centre", "Punch", "Stir", "Tilt left", "Tilt right", "Shake", "Refill", "Zoom in", "Zoom out";
- keyboard: arrows tilt, space pokes, +/− zoom.

### 9.8 At accessibility sizes (measured at AX XXXL, chrome capped at `.accessibility1`)
- The top bar reflows (`ViewThatFits`): the group sits above the card, and the bar grows from 55.3 to **131.3 pt**. The card measures 261 × 79.
- The console's knob area becomes two rows of two (294.7 pt). The console grows to **419.5 pt**, and the tank region shrinks to 430 × **419.5**.
- The life-size tank no longer fits, so it draws at 0.685 scale with the "LIFE-SIZE" tag replaced by "×0.69".
- The five-tab picker still fits in 320 pt. The Refill button goes icon-only.
- The Rheometer strip detent is recomputed from the new console top: h = 902.4 − 478.5 ≈ 424 pt. The strip is stage chrome, so its type stays capped at `.accessibility1`; the large detent is an ordinary sheet and is uncapped.

### 9.9 Rheo's info sheet ("How Rheo works", §3.9 order)
01 *What you're looking at*: "A thin tank of fluid, drawn life-size. Poke it, tilt your phone, shout at it." Then the flow curve with every material.
02 *Touch*: field notes for poke, punch, stir, tilt, shake, shout, and double-tap a knob.
03 *What you're seeing*: legend rows for each fluid's data hue, stress light, dye lines and the cursor.
04 *Knobs*: generated from the specs, page by page.
05 *Experiments*: titles, subtitles and sources.
06 *What's real and what's illustrative*: the §7.5 list.
07 *Sensors in play*: tilt, shake, magnetometer and microphone rows, plus a `PermissionGate` if the mic is denied.
08 *Sound & feel*: `FeedbackSettings`.
09 *Sources & licences*: the papers in `rheology-models.md`, PB-MPM (BSD-3), Box2D v3.1.1 (MIT), each with its checked date. It ends with "The physics is position-based MPM on the GPU …" and the privacy sentence.

### 9.10 SwiftUI skeleton (final LabKit names)

```swift
struct RheoScreen: View {
  @Bindable var model: RheoModel                          // @MainActor @Observable; owns ParamStore, solver, sensors
  @State private var page = "fluid"
  @State private var focus = KnobFocus.none
  @State private var shelf = false
  @State private var rheometer = false
  @State private var consoleTop: CGFloat = 671.3

  var body: some View {
    VStack(spacing: 0) {
      CanvasRegion(label: model.canvasLabel, value: model.canvasValue, hint: "Drag to poke and stir.",
                   actions: model.canvasActions, onFrame: model.setTankRegion,
                   onTouch: model.touch, onMagnify: model.zoom)
        .overlay(alignment: .top) {
          VStack(spacing: 8) {
            LabTopBar { TelemetryCard(expanded: $model.telemetryOpen, rows: model.telemetryRows,
                                      simulatedNote: model.simulatedNote) { TelemetryHeadline(/* η, γ̇ · σ, time chip */) } }
            actions: { MaterialGlyph(model.material) { shelf.toggle() }; ExperimentMenu(/* … */); LayersMenu(model); InfoButton() }
            if shelf { MaterialShelf(model.materials, selection: $model.materialID) }
          }
          .padding(.horizontal, 16).padding(.top, 6)
        }
      KnobConsole(pages: RheoPages.all, page: $page, store: model.params, focus: $focus) {   // open: nil → no fold
        ProminentGlassButton("Refill", icon: "drop.triangle.fill") { model.refill() }
        CircleGlassButton(model.paused ? "Resume" : "Freeze time", icon: model.paused ? "play.fill" : "pause.fill") { model.paused.toggle() }
        CircleGlassButton("Rheometer", icon: "chart.xyaxis.line") { rheometer = true }
        Spacer(minLength: 0)
        CircleGlassButton("Reset \(page) knobs", icon: "arrow.counterclockwise", tap: .reset) { model.resetPage(page) }
      }
      .padding(.horizontal, 12).padding(.bottom, 4)
      .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { consoleTop = $0 }
    }
    .background { LabRenderHost(scene: model.renderScene).ignoresSafeArea() }
    .labChrome(.rheo)
    .sheet(isPresented: $rheometer) {
      RheometerSheet(model: model)
        .presentationDetents([.height(902.4 - consoleTop), .large])   // see §9.6: measured offset
    }
  }
}
```

---

## 10. Verification log (continuation pass, 3 October 2026)

**Built and run** (all in `$S`, outside iCloud):

| Step | Command | Result |
|---|---|---|
| Simulator | `xcrun simctl create "LabKit 15 Pro Max" com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro-Max com.apple.CoreSimulator.SimRuntime.iOS-27-0` | `96394560-C40C-4E4F-A29B-20B18C50C09A`, booted |
| Gallery build | `cd Gallery && xcodegen generate`, then `xcodebuild -project Gallery/LabKitGallery.xcodeproj -scheme LabKitGallery -destination 'platform=iOS Simulator,id=96394560-…' -derivedDataPath dd-gallery build` | `** BUILD SUCCEEDED **` (`build-1.log` unchanged sources; `build-4.log` final). Swift 6, strict concurrency complete. The first attempt with the new modes failed on a missing `LabSemantic.simulated`, which was then added as specified in §2.3 (`build-2.log`) |
| Core tests | `swift test` | 13 XCTests, 0 failures, after the five-page palette change |
| Palette | `python3 rheo_pages5_hand.py` | `ALL RULES PASS` |
| Frames | `xcrun simctl launch --console-pty --terminate-running-process <udid> com.utkarsh.labkitgallery -rheo …` | `FRAME`/`SAFE` lines in `frames-*.txt`. `--stdout=<file>` wrote nothing in this sandbox; use `--console-pty` |
| Shots | `xcrun simctl io <udid> screenshot shots/<name>.png` | 1290 × 2796 px PNGs |

**Measured and now in the spec:**

| Finding | Value | Section |
|---|---|---|
| Safe area, 15 Pro Max portrait | top 59, bottom 34 | §9 |
| Tank region with a one-row console | 430 × 612.3 pt (y 59–671.3) | §9.1 |
| Console / picker / knob row / controls row | 226.7 / 31 / 119.7 / 50 pt | §3.7, §9.3 |
| Five tabs in a 320 pt `.tabs` picker | fit, at default and `.accessibility1` | §3.7 |
| Top bar / telemetry card | 398 × 55.3 / 173 × 55.3 pt | §3.8 |
| Sheet top for `.height(h)` | y = 902.4 − h; h = 231 lands on the console | §9.6 |
| AX XXXL | top bar 131.3; console 419.5; tank 430 × 419.5 | §4.3, §9.8 |
| Selected light-hue tile | 4.25:1 at tint 0.45 → 6.7:1 at 0.30 | §3.6, §4.5 |
| Chip labels | unselected 7.3–7.6:1; selected oobleck with `onFill` 17.2:1 | §4.5 |

**Defects found by looking, and where each is handled:**
1. The gesture hint at the tank floor is unreadable over the fluid. Rule in §3.13: the hint goes in the headspace. *Not yet changed in the gallery*, so the shots still show it.
2. Provenance badges hyphenate in an `HStack`. Rule in §3.2: `fixedSize` plus a flow layout. Not changed in scratch.
3. Readouts in a `Grid` row misalign when one carries a badge. Rule in §3.2: top alignment.
4. Guide labels collide in a small plot. Rule in §3.12: cull on collision.
5. The selected light-hue tile failed contrast. **Fixed** in `Chips.swift` and re-measured.
6. A `.height(300)` Rheometer covered the fluid. **Fixed** with the strip detent and re-measured.
7. From the earlier pass: at AX XXXL, pucks merged into the controls row's glass under one shared container. Fixed with two containers; `$S/shots/v2-stage-axxxl.png` shows the pucks clipped by the page's scroll view and no longer fused with the buttons. **The prototype still has the single container** (§1.3 #15).

**Not verified (device-only or not attempted):**
- Every haptic value and the §5.3 feel map. The simulator has no haptics (`supportsHaptics == false`).
- The sound bed, the cue audibility on the phone speaker (§6.3 rule 7), and echo cancellation on the 15 Pro Max.
- Core Haptics restart latency with auto-shutdown on (§5.6).
- VoiceOver flows, Large Content Viewer long presses, keyboard focus, and the Increase Contrast and Differentiate Without Colour branches. They compile but were not exercised.
- The life-size claim on the physical device (it rests on Apple's published 460 ppi), and the 902.4 pt sheet offset on hardware.
- `CopyLintTests`, `KnobFocus`, `uniformHeight`, the tile shelf auto-close and the material re-registration clamp exist only in this spec, not in scratch code.
