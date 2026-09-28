# Dictionary audit: IBM TTS dictionary vs TruVoice

Source: the community profile of eigencrow/IBMTTSDictionaries (the "IBM TTS
Dictionaries" choice in the Eloquence NVDA add-on), as installed locally:
`enuroot.dic` (68,380 lines), `enumain.dic` (1,233), `enuabbr.dic` (84).
German files (`deu*`) are out of scope: TruVoice is an English-only engine.

Every claim below was measured against the vendored engine
(`Vendor/upstream`, pinned commit) with `text_to_phonemes` traces and
synthesised-audio hashes, not assumed. Probe harness and sweep scripts live
outside the repo (scratch); this directory keeps the generator and the method.

## Stage 1: respellings (enuabbr + enumain plain-English rows, 1,018)

For each `(word, respelling)`: `SAY word` vs `SAY respelling` audio hashes.

- Same audio (6: T-Mobile, Cas, Digi, read-only variants) -- nothing to do.
- Different audio (350) -- the respelling is the prescription:
  - Single-word respelling verifying **byte-identical** through
    `tvtts_add_lexicon` (speaking the key == speaking the respelling, same
    samples, same hash) -> `TruVoice.lexiconEntries` (15 keys: govt, avg,
    incl, jan, inorg, qty, esc, oceanog, cnet, xi, suu, kyi, uni, jos, vypr).
  - Everything else -> `dictionaryTable` (`Dictionary.generated.swift`,
    326 whole-word case-sensitive pairs), so the engine speaks the
    dictionary's audio exactly. This includes the 18 longer words where the
    lexicon renders slightly different audio than the natural word despite
    identical phonemes (boundary context -- e.g. "Sen" traces `Se1N@t3`
    both ways but the samples differ), plus hyphen/`!` keys the lexicon
    cannot match ("you-uns", "P!nk").
- Skipped deliberately:
  - 621 all-caps keys (roman numerals, initialisms): the front end spells
    all-caps letter by letter by SAPI-era convention, which is correct
    ("SUV", "FWIW"); no lexicon entry can reach that path anyway.
  - "Co" (the engine reads "Company", legitimate), "Rep" (valid word, sales
    rep), "Mar" (valid word, to mar), "Id"/"io"/"mm" (valid words) -- the
    engine's word reading is the safer default; the dictionary's expansion
    is context-specific.
  - Backtick/stress-code respellings ("mbox" -> "em `0 box") and IBM-phoneme
    rows -- not plain English, handled in stage 2 or not at all.

## Stage 2: stress triage (68,647 IBM-phoneme rows)

IBM `[.2bI.0le.1du]` parses to (syllables, primary): split `.`, each
syllable leads with 0/1/2. TruVoice traces parse with the engine's own
vowel inventory (`Phone_IsVowel`: `@|ObfUAEIyaeivowu3rg5k4c`); the vowel
before `1` is primary. 38,923 agree; 28,927 disagree; 825 unparseable.

Equal-syllable-count disagreements are fixable: the value is TruVoice's own
phones with `1` moved to IBM's primary -- IBM stress is the authority,
TruVoice segments are its best effort. Each is verified (lexicon-installed
trace shows `1` at IBM's primary, audio speaks) before landing in
`StressLexicon.generated.swift`. The engine caps the user lexicon at 5,000
entries (`0x1388` in `lexicon.c`), so 2-syllable words go first, then
3-syllable, to the cap: 4,866 kept (all 2,386 two-syllable disagreements
plus 2,480 three-syllable), 84 misses dropped (every one an accented key --
`tv_strupr` mangles non-ASCII, so the lookup never matches; a stress fix
cannot go through the text layer, which carries text, not phonemes).
Different-count disagreements (10,985: diphthong and syllabic-consonant
syllabification differs) are skipped: syllables cannot be aligned
reliably. With the 19 hand entries the installed total is 4,885, under
the 5,000 cap with headroom.

## Lessons for future engine work

- `tvtts_add_lexicon` returns -1 even on success (it branches on a void
  function's "value"). The proof of an entry is the audio/trace, not rc.
- Lexicon values must be engine phone strings with only `&`, `.` and
  whitespace stripped. `&`/`.` markers kept in a value speak wrong audio;
  everything else (`|`, `%`, `~`, stress digits) is phonemic and stays.
- Caps-run audio != spaced-letters audio even with identical phonemes
  (boundary tones): "FAQ" caps and "eff ay kew" trace the same but sound
  different. The dictionary's literal respelling is always the faithful
  route; caps uppercasing only where no prescription exists ("aidb").
- Spaced lone "A" reads as the article ("uh"); letter prescription for
  A-words must go through caps or the dictionary's own spelling ("aigh").
