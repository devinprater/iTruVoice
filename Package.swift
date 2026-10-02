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
    // voices.c carries OpenTV's own extra voices (Frank); sing.c the
    // score compiler and singing entry points (added upstream 2026-10-01).
    "upstream/src/engine/voices.c",
    // syn_hifi.c carries the resampled 16 kHz tables; api.c carries
    // tvtts_create and the speak entry points (added upstream 2026-09).
    "upstream/src/syn_hifi.c",
    "upstream/src/port/api.c",
    "upstream/src/port/sing.c",
    "upstream/src/port/tvtts.c",
    "upstream/src/port/msvcrt.c",
    "upstream/src/port/stubs.c",
    "generated/tvdata.s",
]

// The Spanish engine: same library, every name es_-prefixed. The rename
// header (Vendor/generated/es_rename.h) must be force-included into exactly
// these translation units -- a global -include would rename the English
// Engine_Feed too, which is why Spanish is its own target. Explicit file
// list: the directories also hold non-sources (engine.fields) that SwiftPM's
// expansion hands to clang as C, which fails the build.
let spanishSources = [
    "upstream/es/adjust.c",
    "upstream/es/bittab.c",
    "upstream/es/cluster.c",
    "upstream/es/contour.c",
    "upstream/es/control.c",
    "upstream/es/engine.c",
    "upstream/es/escape.c",
    "upstream/es/flush.c",
    "upstream/es/generate.c",
    "upstream/es/input.c",
    "upstream/es/interp.c",
    "upstream/es/list.c",
    "upstream/es/node.c",
    "upstream/es/number.c",
    "upstream/es/params.c",
    "upstream/es/phone.c",
    "upstream/es/preformat.c",
    "upstream/es/prosody.c",
    "upstream/es/reset.c",
    "upstream/es/ring.c",
    "upstream/es/rule.c",
    "upstream/es/segment.c",
    "upstream/es/stage.c",
    "upstream/es/stage0.c",
    "upstream/es/stage1.c",
    "upstream/es/stage2.c",
    "upstream/es/stage3.c",
    "upstream/es/stage3seg.c",
    "upstream/es/stage4.c",
    "upstream/es/synth.c",
    "upstream/es/tables.c",
    "upstream/es/textin.c",
    "upstream/es/track.c",
    "upstream/es/util.c",
    // voices.c carries OpenTV's own extra Spanish voices (Fransisco,
    // added upstream 2026-10-01).
    "upstream/es/voices.c",
    "upstream/es_port/msvcrt_es.c",
    "upstream/es_port/tvtts_es.c",
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
            publicHeadersPath: "es_include",
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
