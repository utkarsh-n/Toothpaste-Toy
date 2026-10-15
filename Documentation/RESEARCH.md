# Research notes: index

The notes written before LabKit and Rheo were built (3 October 2026), in `Documentation/research/`. `ARCHITECTURE.md`
§0 ranks them by authority where they overlap. Tags inside them: **[V]** verified in that session, **[I]** inferred,
**[S]** from a sibling note or a source project's own evidence.

| Note | One line |
|---|---|
| [`rheology-models.md`](research/rheology-models.md) | The physics bible: every material class with equations, units and literature values; the one unified elasto-viscoplastic update both solvers run; the presets (§6), verification cases V1–V14 (§7) and the honesty notes (§8) the app's copy follows. |
| [`mpm-metal.md`](research/mpm-metal.md) | How PB-MPM's fused GPU grid transfer was ported to Metal for a 2D tank with the rheology above: kernels, fixed point, the substep rule Π ≤ 0.07, colliders and impulses, Simulator fallbacks, and the 2.5D fluid surface renderer. |
| [`oss-engine-survey.md`](research/oss-engine-survey.md) | Which open-source engine to build on, and why (revision 2): explicit MLS-MPM with PB-MPM's GPU infrastructure and grid-volume correction, Box2D for props; licences and real-gravity substep costs. |
| [`oss-integration-lessons.md`](research/oss-integration-lessons.md) | Lessons from Powder Modernization and Nano on vendoring (Box2D v3.1.1 with provenance files), threading under Swift 6 and Metal particle rendering, re-verified with probe packages. |
| [`labkit-from-gyre.md`](research/labkit-from-gyre.md) | The LabKit extraction spec from Gyre: package layout, parameters and modulation, sensors with Simulator fakes, haptics and the synth host, the render host and frame loop, Swift 6 concurrency rules. |
| [`labkit-from-orbitals-spectra.md`](research/labkit-from-orbitals-spectra.md) | LabKit's design system and UX ("glass over phosphor"), merged from Orbitals, Tether, spectra-lab and Gyre: tokens, components, haptics and sound policy, copy rules, and Rheo's screen (§9). |
| [`toolchain-checks.md`](research/toolchain-checks.md) | Build facts checked with a throwaway prototype on Xcode 27 beta, iOS 27 SDK and Swift 6.4: SwiftPM with Metal (`TOOLCHAINS=metal`), XcodeGen, Liquid Glass API spellings, Simulator GPU limits. |

## What came after

| Document | What it is |
|---|---|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | The binding contract between the LabKit and Rheo work packages (3 October 2026). |
| [`SKELETON.md`](SKELETON.md) | Rheo's walking skeleton: the frozen interfaces, file ownership, launch arguments, build and test commands, and the RHEO-FIX changes. |
| `progress-{phys,render,ui,feel}.md` | The four Rheo areas' logs (wave 2), each with an independent verifier's section. |
| [`progress-lkfix.md`](progress-lkfix.md), [`progress-rfix.md`](progress-rfix.md) | Wave 3: LabKit fixes (foam, MR heaping, lava band, allocations, audio reset) and Rheo fixes (mic gate, XCUITests, perf log). |
| [`progress-qa.md`](progress-qa.md) | The final QA and integration pass: every check re-run, the on-screen tour, the docs. |
| [`DEVICE-RUN-1.md`](DEVICE-RUN-1.md), [`DEVICE-RUN.md`](DEVICE-RUN.md) | The first measurement on the iPhone 15 Pro Max, and the recipe to repeat it. |
| `../../LabKit/Documentation/VERIFICATION-GPU.md`, `VERIFICATION-MPM.md` | The GPU solver's and the CPU oracle's checks, with numbers. |
