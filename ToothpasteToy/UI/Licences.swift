// Licences.swift — OWNER: UI (Documentation/REDESIGN-OWNERSHIP.md).
//
// The third-party code inside Toothpaste Toy (through LabKit: PB-MPM, Box2D and, since 13 October 2026, Wave), credited in the info sheet's panel 09 with the full licence
// texts, as LabKit/THIRD_PARTY_NOTICES.md asks of every app that links it. Checked on 8 October 2026 against the
// vendored files: LabKit/Sources/CBox2D/LICENSE (SHA-256 68a3e676…74e43d2, as recorded in UPSTREAM.json) and
// LabKit/Sources/LabKitMPMTypes/LICENSE-PBMPM.md. The BSD licence forbids using EA's name to endorse the app, so the
// credit is a plain attribution.

import Foundation
import LabKitCore

struct ToothpasteLicence: Sendable, Identifiable {
  var id: String { name }
  let name: String
  let licence: String
  let summary: String
  let citation: Citation
  /// Verbatim licence text (not linted: it must not be changed).
  let text: String
}

enum ToothpasteLicences {
  static let box2d = ToothpasteLicence(
    name: "Box2D 3.1.1", licence: "MIT",
    summary: "Rigid bodies for the props, compiled unmodified into LabKit.",
    citation: Citation(
      "Box2D 3.1.1", publisher: "Erin Catto", url: URL(string: "https://github.com/erincatto/box2d")!, kind: .code,
      licence: "MIT", checked: "2026-10-08"),
    text: """
      MIT License

      Copyright (c) 2022 Erin Catto

      Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated \
      documentation files (the "Software"), to deal in the Software without restriction, including without limitation \
      the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and \
      to permit persons to whom the Software is furnished to do so, subject to the following conditions:

      The above copyright notice and this permission notice shall be included in all copies or substantial portions of \
      the Software.

      THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO \
      THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
      AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF \
      CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS \
      IN THE SOFTWARE.
      """)

  static let pbmpm = ToothpasteLicence(
    name: "PB-MPM", licence: "BSD-3-Clause",
    summary:
      "Electronic Arts SEED's position-based MPM. LabKit's GPU fluid solver is a Metal port of its compute shaders, modified for SI units and Toothpaste Toy's flow laws.",
    citation: Citation(
      "PB-MPM", publisher: "Electronic Arts SEED", url: URL(string: "https://github.com/electronicarts/pbmpm")!,
      kind: .code, licence: "BSD-3-Clause", checked: "2026-10-08"),
    text: """
      Copyright (c) 2024 Electronic Arts Inc. All rights reserved.

      Redistribution and use in source and binary forms, with or without modification, are permitted provided that \
      the following conditions are met:

      1. Redistributions of source code must retain the above copyright notice, this list of conditions and the \
      following disclaimer.
      2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the \
      following disclaimer in the documentation and/or other materials provided with the distribution.
      3. Neither the name of Electronic Arts, Inc. ("EA") nor the names of its contributors may be used to endorse or \
      promote products derived from this software without specific prior written permission.

      THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED \
      WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A \
      PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY \
      DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, \
      PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER \
      CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR \
      OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
      """)

  /// Wave 0.3.4 (vendored in LabKit, `Sources/Wave/LICENSE.md`, checked 13 October 2026).
  static let wave = ToothpasteLicence(
    name: "Wave 0.3.4", licence: "MIT",
    summary:
      "Janum Trivedi's spring animation engine, compiled unmodified into LabKit. It moves the glass lens, the crowns, the pills and the numbers; it never moves the paste.",
    citation: Citation(
      "Wave 0.3.4", publisher: "Janum Trivedi", url: URL(string: "https://github.com/jtrivedi/Wave")!, kind: .code,
      licence: "MIT", checked: "2026-10-13"),
    text: """
      Copyright (c) 2022 Janum Trivedi

      Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated \
      documentation files (the "Software"), to deal in the Software without restriction, including without limitation \
      the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and \
      to permit persons to whom the Software is furnished to do so, subject to the following conditions:

      The above copyright notice and this permission notice shall be included in all copies or substantial portions of \
      the Software.

      THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO \
      THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
      AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF \
      CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER \
      DEALINGS IN THE SOFTWARE.
      """)

  static let all: [ToothpasteLicence] = [pbmpm, box2d, wave]
}
