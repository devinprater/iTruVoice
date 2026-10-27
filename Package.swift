// swift-tools-version: 6.0

import PackageDescription

let engineSources = [
    "upstream/src/engine/control.c",
    "upstream/src/engine/dict.c",
    "upstream/src/engine/engine.c",
    "upstream/src/engine/feed.c",
    "upstream/src/engine/frame.c",
    // gb.c holds General British's vowel targets and stage-1 substitutions;
    // the en-GB row in upstream/src/port/api.c calls into it.
    "upstream/src/engine/gb.c",
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

// The two language ports that ride on the English engine. General British
// only wraps the American entry points with stage 3's vowel targets re-aimed
// (upstream/lang/eng/port, plus src/engine/gb.c above); Japanese is a front
// end that drives the synthesiser below stage 3. Both are here because
// upstream/src/port/api.c carries their rows unconditionally -- api.c names
// every language the library has, so the link needs all of them. iTruVoice
// offers the English, Spanish and British voices only: Japanese needs the
// 27 MB dictionary upstream loads from disk at runtime, which is not vendored.
let languageSources = [
    "upstream/lang/eng/port/tvtts_engb.c",
    "upstream/lang/jpn/port/ja_devoice_tab.c",
    "upstream/lang/jpn/port/ja_dict.c",
    "upstream/lang/jpn/port/ja_digit.c",
    "upstream/lang/jpn/port/ja_frame.c",
    "upstream/lang/jpn/port/ja_front.c",
    "upstream/lang/jpn/port/ja_g2p.c",
    "upstream/lang/jpn/port/ja_g2p_tab.c",
    "upstream/lang/jpn/port/ja_mora.c",
    "upstream/lang/jpn/port/ja_njd.c",
    "upstream/lang/jpn/port/ja_ojt.c",
    "upstream/lang/jpn/port/ja_pitch.c",
    "upstream/lang/jpn/port/ja_tables.c",
    "upstream/lang/jpn/port/ja_voice.c",
    "upstream/lang/jpn/port/tvtts_ja.c",
]

// The Spanish engine: same library, every name es_-prefixed. The rename
// header (Vendor/generated/es_rename.h) must be force-included into exactly
// these translation units -- a global -include would rename the English
// Engine_Feed too, which is why Spanish is its own target. Explicit file
// list: the directories also hold non-sources (engine.fields) that SwiftPM's
// expansion hands to clang as C, which fails the build.
let spanishSources = [
    "upstream/lang/spa/engine/adjust.c",
    "upstream/lang/spa/engine/bittab.c",
    "upstream/lang/spa/engine/cluster.c",
    "upstream/lang/spa/engine/contour.c",
    "upstream/lang/spa/engine/control.c",
    "upstream/lang/spa/engine/engine.c",
    "upstream/lang/spa/engine/escape.c",
    "upstream/lang/spa/engine/flush.c",
    "upstream/lang/spa/engine/generate.c",
    "upstream/lang/spa/engine/input.c",
    "upstream/lang/spa/engine/interp.c",
    "upstream/lang/spa/engine/list.c",
    "upstream/lang/spa/engine/node.c",
    "upstream/lang/spa/engine/number.c",
    "upstream/lang/spa/engine/params.c",
    "upstream/lang/spa/engine/phone.c",
    "upstream/lang/spa/engine/preformat.c",
    "upstream/lang/spa/engine/prosody.c",
    "upstream/lang/spa/engine/reset.c",
    "upstream/lang/spa/engine/ring.c",
    "upstream/lang/spa/engine/rule.c",
    "upstream/lang/spa/engine/segment.c",
    "upstream/lang/spa/engine/stage.c",
    "upstream/lang/spa/engine/stage0.c",
    "upstream/lang/spa/engine/stage1.c",
    "upstream/lang/spa/engine/stage2.c",
    "upstream/lang/spa/engine/stage3.c",
    "upstream/lang/spa/engine/stage3seg.c",
    "upstream/lang/spa/engine/stage4.c",
    "upstream/lang/spa/engine/synth.c",
    "upstream/lang/spa/engine/tables.c",
    "upstream/lang/spa/engine/textin.c",
    "upstream/lang/spa/engine/track.c",
    "upstream/lang/spa/engine/util.c",
    // voices.c carries OpenTV's own extra Spanish voices (Fransisco,
    // added upstream 2026-10-01).
    "upstream/lang/spa/engine/voices.c",
    "upstream/lang/spa/port/msvcrt_es.c",
    "upstream/lang/spa/port/tvtts_es.c",
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
            sources: engineSources + languageSources,
            publicHeadersPath: "upstream/include",
            cSettings: [
                .headerSearchPath("upstream/src"),
                // gb.c includes gb_vowels.h and gb_lexicon.h; the Japanese
                // front end includes ja.h and friends from its own port dir.
                .headerSearchPath("upstream/lang/eng/data"),
                .headerSearchPath("upstream/lang/jpn/port"),
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
                .headerSearchPath("upstream/lang/spa/engine"),
                .headerSearchPath("upstream/src"),
                .headerSearchPath("upstream/include"),
                .headerSearchPath("generated"),
                .unsafeFlags(["-include", "es_rename.h"]),
            ]
        ),
    ]
)
