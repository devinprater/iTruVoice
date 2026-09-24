# Notice on the engine data

The Swift code in this repository is MIT licensed (see LICENSE). The speech
itself is not ours.

The engine is OpenTV (https://github.com/RetroBunn/tv-decomp), a portable-C
decompilation of Centigram's TruVoice text-to-speech system, pinned as a
submodule at `Vendor/upstream`. Its code is MIT licensed.

Its voice data is not. The file `Vendor/generated/tvdata.s` is generated from
OpenTV's `data/en/engine.tvdata`, which holds Centigram's own tables: the
letter-to-sound rules, exception dictionary, phoneme inventory, formant and
prosody tables, and the ten voices' parameters. Quoting upstream's NOTICE:
"The MIT licence does not cover the contents of `data/`, and OpenTV is in no
position to license them to anyone."

The rights trail, as far as it is public: Centigram sold TruVoice to Lernout
& Hauspie in 1997; L&H went bankrupt in 2001 and ScanSoft bought the assets;
ScanSoft became Nuance in 2005. Where the rights sit now has not been
established. This app embeds those tables because the engine cannot speak
without its own numbers, and for no other reason.
