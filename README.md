# iTruVoice

Centigram's TruVoice text-to-speech (the Microsoft Agent / Bonzi Buddy voice)
as an iOS app with system-wide voices, via
[OpenTV](https://github.com/RetroBunn/tv-decomp) — a portable-C decompilation
verified byte-for-byte against the 1997 binary.

Install the app and thirty-three voices appear for VoiceOver and Spoken
Content: eleven American English -- Peter, Sidney, Eager Eddie, Deep Douglas,
Biff, Grandpa Amos, Melvin, Alex, Wanda, Julia and Frank -- eleven Spanish --
Pedro, Jorge, Ricardo, Paco, Luis, Ezequiel, Rogelio, Carlos, Josefa, Isabel
and Francisco -- and eleven British English -- Nigel, Clive, Eager Edwin,
Deep Duncan, Rupert, Gramps Amos, Malcolm, Alistair, Fiona, Imogen and
Bernard.

British English is the same engine with stage 3 re-aimed at General British
vowel targets and the accent's phoneme substitutions applied, not a separate
recording: each British voice is an American speaker under a British name, and
the system files them under English (United Kingdom).

## Layout

- `Package.swift` / `xtool.yml` — the whole build. SwiftPM plus xtool, on
  Linux and on the Mac runner alike. No Xcode project, no XcodeGen.
- `Sources/iTruVoice` — the app: a test bench (text field, voice picker,
  Speak/Stop).
- `Sources/TruVoiceProvider` — the speech provider extension (an Audio Unit
  of type `ausp`, subtype `truv`).
- `Sources/TruVoiceKit` — the Swift bridge over the C engine, shared by both.
- `Vendor/upstream` — OpenTV pinned as a submodule (currently `8488e51`).
  Upstream keeps each language in its own tree now (`lang/enu`, `lang/spa`,
  `lang/jpn`, `lang/eng` for British English).
- `Vendor/generated` — `engine_struct.h` and `tvdata.s`, produced from the
  pinned upstream by `tools/regen_generated.sh`. The struct header is pure
  (byte-identical on every host; CI fails if the committed copy drifts). The
  data image is laid out with host object files, so its bytes differ between
  Linux and macOS: the committed copy is the Linux variant, and CI
  regenerates it for the Mac before building. Either way,
  `tools/corpus_check.py` proves the result speaks exactly the golden audio.
- `tools/corpus_check.py` + `tools/corpus.txt` + `tools/corpus_golden.txt` —
  the engine proof on every build: each corpus line must produce non-silent
  audio with exactly the recorded sample count. `tools/corpus_gb.txt` and its
  golden do the same on an en-GB synth.
- `tools/gb_check.py` — upstream's own `tests/gb_check.c` against the pinned
  engine: the accent reaches the formants, American is untouched, and the /r/
  rules hold. Its output is recorded, so a change is a diff to read.
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
