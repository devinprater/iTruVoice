# iTruVoice

Centigram's TruVoice text-to-speech (the Microsoft Agent / Bonzi Buddy voice)
as an iOS app with system-wide voices, via
[OpenTV](https://github.com/RetroBunn/tv-decomp) — a portable-C decompilation
verified byte-for-byte against the 1997 binary.

Install the app and ten English voices appear for VoiceOver and Spoken
Content: Peter, Sidney, Eager Eddie, Deep Douglas, Biff, Grandpa Amos,
Melvin, Alex, Wanda and Julia.

## Layout

- `Package.swift` / `xtool.yml` — the whole build. SwiftPM plus xtool, on
  Linux and on the Mac runner alike. No Xcode project, no XcodeGen.
- `Sources/iTruVoice` — the app: a test bench (text field, voice picker,
  Speak/Stop).
- `Sources/TruVoiceProvider` — the speech provider extension (an Audio Unit
  of type `ausp`, subtype `truv`).
- `Sources/TruVoiceKit` — the Swift bridge over the C engine, shared by both.
- `Vendor/upstream` — OpenTV pinned as a submodule (currently `7954947`).
- `Vendor/generated` — `engine_struct.h` and `tvdata.s`, produced from the
  pinned upstream by `tools/regen_generated.sh`. The struct header is pure
  (byte-identical on every host; CI fails if the committed copy drifts). The
  data image is laid out with host object files, so its bytes differ between
  Linux and macOS: the committed copy is the Linux variant, and CI
  regenerates it for the Mac before building. Either way,
  `tools/corpus_check.py` proves the result speaks exactly the golden audio.
- `tools/corpus_check.py` + `tools/corpus.txt` + `tools/corpus_golden.txt` —
  the engine proof on every build: each corpus line must produce non-silent
  audio with exactly the recorded sample count.
- `tools/publish_release.sh` — publishes the `.ipa` by numeric release ID
  and verifies it by downloading it back and comparing bytes. Never trust a
  tag's embedded asset list; it goes stale.

## Building

```sh
xtool dev build        # device triple, arm64 Mach-O app
xtool dev build --ipa  # sideloadable .ipa
xtool dev              # install and launch on the attached iPhone
```

## Rights

Our code is MIT (LICENSE). The voice tables the engine speaks with are
Centigram's — see NOTICE.md.
