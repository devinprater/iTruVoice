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
    "upstream/src/port/tvtts.c",
    "upstream/src/port/msvcrt.c",
    "upstream/src/port/stubs.c",
    "generated/tvdata.s",
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
            dependencies: ["TruVoiceKit"]
        ),
        .target(
            name: "TruVoiceProvider",
            dependencies: ["TruVoiceKit"]
        ),
        .target(
            name: "TruVoiceKit",
            dependencies: ["CTruVoice"]
        ),
        .target(
            name: "CTruVoice",
            path: "Vendor",
            sources: engineSources,
            publicHeadersPath: "upstream/include",
            cSettings: [
                .headerSearchPath("upstream/src"),
                .headerSearchPath("generated"),
            ]
        ),
    ]
)
