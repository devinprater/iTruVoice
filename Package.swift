// swift-tools-version: 6.0

import PackageDescription

let engineSources = [
    "upstream/src/engine/control.c",
    "upstream/src/engine/dict.c",
    "upstream/src/engine/engine.c",
    "upstream/src/engine/feed.c",
    "upstream/src/engine/frame.c",
    "upstream/src/engine/generate.c",
    "upstream/src/engine/input.c",
    "upstream/src/engine/layout.c",
    "upstream/src/engine/lexicon.c",
    "upstream/src/engine/lts.c",
    "upstream/src/engine/node.c",
    "upstream/src/engine/output.c",
    "upstream/src/engine/phonetic.c",
    "upstream/src/engine/preformat.c",
    "upstream/src/engine/ring.c",
    "upstream/src/engine/sapi.c",
    "upstream/src/engine/stage0.c",
    "upstream/src/engine/stage1.c",
    "upstream/src/engine/stage2.c",
    "upstream/src/engine/stage3.c",
    "upstream/src/engine/stages.c",
    "upstream/src/engine/synth.c",
    "upstream/src/engine/textin.c",
    "upstream/src/engine/track.c",
    "upstream/src/engine/volume.c",
    "upstream/src/engine/vowel.c",
    // syn_hifi.c carries the resampled 16 kHz tables; api.c carries
    // tvtts_create and the speak entry points (added upstream 2026-09).
    "upstream/src/syn_hifi.c",
    "upstream/src/port/api.c",
    "upstream/src/port/tvtts.c",
    "upstream/src/port/msvcrt.c",
    "upstream/src/port/stubs.c",
    "generated/tvdata.s",
]

// The Spanish engine: same library, every name es_-prefixed. The rename
// header (Vendor/generated/es_rename.h) must be force-included into exactly
// these translation units -- a global -include would rename the English
// Engine_Feed too, which is why Spanish is its own target. Directory
// entries expand to their .c files; headers ride along untouched.
let spanishSources = [
    "upstream/es",
    "upstream/es_port",
    "generated/tvdata_es.s",
]

let package = Package(
    name: "iTruVoice",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        // The main app. xtool packages this library product as the .app.
        .library(
            name: "iTruVoice",
            targets: ["iTruVoice"]
        ),
        // The system-wide speech provider extension (an Audio Unit).
        .library(
            name: "TruVoiceProvider",
            targets: ["TruVoiceProvider"]
        ),
    ],
    targets: [
        .target(
            name: "iTruVoice",
            dependencies: ["TruVoiceKit", "TruVoiceCore"]
        ),
        .target(
            name: "TruVoiceProvider",
            dependencies: ["TruVoiceKit", "TruVoiceCore"]
        ),
        .target(
            name: "TruVoiceKit",
            dependencies: ["TruVoiceCore", "CTruVoice"]
        ),
        // The SSML and parameter layers, dependency-free on purpose: the
        // tests build this target alone, so they never touch the C engine or
        // its assembly data image (which SwiftPM's Linux driver cannot
        // compile, and which device builds assemble with Apple clang).
        .target(
            name: "TruVoiceCore",
            dependencies: []
        ),
        .testTarget(
            name: "TruVoiceKitTests",
            dependencies: ["TruVoiceCore"]
        ),
        // The executable check harness. `swift run CoreChecks` builds only
        // this and TruVoiceCore, on Linux and macOS alike; `swift test`
        // would build the whole package including the C engine, whose data
        // image SwiftPM's Linux driver cannot assemble.
        .executableTarget(
            name: "CoreChecks",
            dependencies: ["TruVoiceCore"]
        ),
        .target(
            name: "CTruVoice",
            dependencies: ["CTruVoiceES"],
            path: "Vendor",
            sources: engineSources,
            publicHeadersPath: "upstream/include",
            cSettings: [
                .headerSearchPath("upstream/src"),
                .headerSearchPath("generated"),
            ]
        ),
        // The Spanish engine, linked into the same library. Own target so
        // the rename force-include touches only its files. unsafeFlags is
        // fine here: this package is built directly (never taken as a
        // dependency), and -include resolves es_rename.h through the
        // generated/ search path below, the same lookup the Linux and
        // Xcode drivers both perform.
        .target(
            name: "CTruVoiceES",
            path: "Vendor",
            sources: spanishSources,
            publicHeadersPath: "upstream/include",
            cSettings: [
                .headerSearchPath("upstream/es"),
                .headerSearchPath("upstream/src"),
                .headerSearchPath("upstream/include"),
                .headerSearchPath("generated"),
                .unsafeFlags(["-include", "es_rename.h"]),
            ]
        ),
    ]
)
