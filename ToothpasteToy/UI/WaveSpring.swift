// WaveSpring.swift — OWNER: UI (Documentation/REDESIGN-OWNERSHIP.md).
//
// The vendored Wave module (Janum Trivedi, 0.3.4, MIT) declares both a `Spring` class and a class named `Wave`, and
// SwiftUI has its own `Spring`: `Wave.Spring` would look inside the class, and a bare `Spring` is ambiguous in any file
// that imports SwiftUI too. This file imports Wave alone, so the alias below names Wave's spring unambiguously; every
// UI file uses `WaveSpring`.

import Wave

typealias WaveSpring = Spring
