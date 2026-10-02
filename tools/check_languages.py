#!/usr/bin/env python3
"""Latch: fail when the pinned engine carries a language iTruVoice ignores.

Upstream promotes languages gradually -- Japanese arrived as an
engine-level frame API with no language entry, Spanish grew a voice,
English grew Frank. Any of those reaching production means new voices the
app never lists, so this check pins the production language list (code +
voice count, in tools/languages_expected.txt) against the built engine and
fails with the wiring checklist when they differ. Re-pin deliberately with
--record only after every item on the checklist is done, never to silence it.

Usage: check_languages.py [--record] [--expected PATH]
"""
import argparse
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import corpus_check  # noqa: E402 -- reuse ENGINE_SRCS/ES_SRCS, UP, GEN

DRIVER = r"""
#include <stdio.h>
#include <string.h>
#include "tvtts.h"
int main(void) {
    int nl = tvtts_language_count();
    int total = tvtts_voice_count();
    int i, v;
    printf("languages %d\n", nl);
    for (i = 0; i < nl; i++) {
        const char *code = tvtts_language(i);
        int c = 0;
        for (v = 0; v < total; v++) {
            const char *l = tvtts_voice_language(v);
            if (l != NULL && code != NULL && strcmp(l, code) == 0)
                c++;
        }
        printf("%s %d\n", code != NULL ? code : "?", c);
    }
    return 0;
}
"""

CHECKLIST = """\
A new production language (or new voices) is in the pinned engine.
Wire it into the app before re-pinning with --record:
  1. Vendor/generated: run tools/regen_generated.sh (new tvdata image,
     rename header, struct header) and commit the result.
  2. Package.swift: new C target + explicit .c list for the language,
     mirroring CTruVoiceES (own target: the rename force-include must not
     touch the other engines; two targets cannot share one
     publicHeadersPath; list .c files explicitly, directories also hold
     non-sources SwiftPM would hand to clang).
  3. tools/corpus_check.py: compile the new language's sources (ES_SRCS
     pattern) so the proof covers it.
  4. tools/corpus.txt: add a line in the new language; re-record the
     golden deliberately after reading the diff.
  5. Sources/TruVoiceKit: extend voiceNames in engine order, the
     language mapping, and VoiceCatalog (locale tag like es-ES;
     identifiers are voice names, so a renumber needs no migration).
  6. Provider + app: new voices appear automatically through
     VoiceCatalog.all; check sample text and any locale-gated UI.
  7. README voice paragraph and a ReleaseNotes entry.
"""


def build(workdir):
    objdir = os.path.join(workdir, "obj")
    os.makedirs(objdir, exist_ok=True)
    objs = []
    for src in corpus_check.ENGINE_SRCS:
        obj = os.path.join(objdir, os.path.basename(src) + ".o")
        subprocess.run(
            ["cc", "-O2", "-w", "-I", os.path.join(corpus_check.UP, "src"),
             "-I", os.path.join(corpus_check.UP, "include"),
             "-I", corpus_check.GEN, "-c", src, "-o", obj],
            check=True,
        )
        objs.append(obj)
    subprocess.run(["cc", "-w", "-c",
                    os.path.join(corpus_check.GEN, "tvdata.s"),
                    "-o", os.path.join(objdir, "tvdata.o")], check=True)
    objs.append(os.path.join(objdir, "tvdata.o"))
    for src in corpus_check.ES_SRCS:
        obj = os.path.join(objdir, "es_" + os.path.basename(src) + ".o")
        subprocess.run(
            ["cc", "-O2", "-w", "-I", os.path.join(corpus_check.UP, "es"),
             "-I", os.path.join(corpus_check.UP, "src"),
             "-I", os.path.join(corpus_check.UP, "include"),
             "-I", corpus_check.GEN,
             "-include", os.path.join(corpus_check.GEN, "es_rename.h"),
             "-c", src, "-o", obj],
            check=True,
        )
        objs.append(obj)
    subprocess.run(["cc", "-w", "-c",
                    os.path.join(corpus_check.GEN, "tvdata_es.s"),
                    "-o", os.path.join(objdir, "tvdata_es.o")], check=True)
    objs.append(os.path.join(objdir, "tvdata_es.o"))
    drv = os.path.join(workdir, "drv.c")
    with open(drv, "w") as f:
        f.write(DRIVER)
    exe = os.path.join(workdir, "langcheck")
    subprocess.run(["cc", "-O2", "-w",
                    "-I", os.path.join(corpus_check.UP, "include"),
                    "-o", exe, drv] + objs, check=True)
    return exe


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--record", action="store_true")
    ap.add_argument("--expected",
                    default=os.path.join(HERE, "languages_expected.txt"))
    args = ap.parse_args()

    workdir = tempfile.mkdtemp(prefix="itruvoice-langcheck.")
    exe = build(workdir)
    p = subprocess.run([exe], capture_output=True, text=True, check=True)
    lines = [ln.strip() for ln in p.stdout.splitlines() if ln.strip()]
    # First line is "languages N"; the rest are "code count".
    actual = [ln for ln in lines[1:] if len(ln.split()) == 2]

    if args.record:
        with open(args.expected, "w") as f:
            f.write("# Managed by tools/check_languages.py --record.\n")
            f.write("# Format: \"<two-letter code> <voice count>\".\n")
            f.write("\n".join(actual) + "\n")
        print(f"recorded {len(actual)} languages -> {args.expected}")
        return

    with open(args.expected) as f:
        expected = [ln.strip() for ln in f
                    if ln.strip() and not ln.strip().startswith("#")]
    if actual == expected:
        print(f"languages OK: {', '.join(actual)}")
        return
    print(f"MISMATCH: engine has {actual}, expected {expected}")
    print(CHECKLIST)
    sys.exit(1)


if __name__ == "__main__":
    main()
