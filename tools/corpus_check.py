#!/usr/bin/env python3
"""The engine proof: every corpus line must speak, with golden sample counts.

Builds the pinned engine for the host, synthesizes each line of
tools/corpus.txt through the real library, and checks two things: the audio
is non-silent, and its length matches tools/corpus_golden.txt exactly. The
engine is deterministic given its data, so a count change means the code, the
generated files, or the data moved -- rebuild the golden deliberately with
--record after reading the diff, never blindly.

tools/corpus_gb.txt is the same proof for General British: those lines run on
an en-GB synth and match tools/corpus_gb_golden.txt. A separate file because a
British count differs from the American one by design. Upstream's own
tests/gb_check.c is the deeper proof (the accent reaches the formants, the
American path is untouched, and the /r/ rules hold); tools/gb_check.py runs it
against these same objects.

Usage: corpus_check.py [--record] [--workdir DIR]
"""
import argparse
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
UP = os.path.join(ROOT, "Vendor", "upstream")
GEN = os.path.join(ROOT, "Vendor", "generated")

# The English engine. Upstream reorganized its tree by language, so the
# Spanish and Japanese sources and data no longer live beside src/.
ENGINE_SRCS = sorted(
    os.path.join(UP, "src", "engine", f)
    for f in os.listdir(os.path.join(UP, "src", "engine"))
    if f.endswith(".c")
) + [
    # syn_hifi.c carries the resampled 16 kHz tables (g_synhifi_*) that
    # synth.c references; api.c carries tvtts_create and the speak entry
    # points. port/main.c is the upstream CLI and is NOT linked -- drv.c
    # below provides main.
    os.path.join(UP, "src", "syn_hifi.c"),
    os.path.join(UP, "src", "port", "api.c"),
    # sing.c carries the score compiler AND the text-pipeline pieces every
    # utterance runs through (tv_camel_split, tv_phone_commands), added
    # upstream 2026-10-01.
    os.path.join(UP, "src", "port", "sing.c"),
    os.path.join(UP, "src", "port", "tvtts.c"),
    os.path.join(UP, "src", "port", "msvcrt.c"),
    os.path.join(UP, "src", "port", "stubs.c"),
]

EN_INCLUDES = [os.path.join(UP, "src"), os.path.join(UP, "include"),
               os.path.join(UP, "lang", "eng", "data"), GEN]

# The language ports api.c names unconditionally: British English (wrappers
# over the American engine; src/engine/gb.c holds its targets) and Japanese
# (a front end below stage 3). Both must link, whether or not the app offers
# their voices -- iTruVoice offers British, not Japanese, whose 27 MB
# dictionary is loaded from disk and is not vendored.
GB_SRCS = sorted(
    os.path.join(UP, "lang", "eng", "port", f)
    for f in os.listdir(os.path.join(UP, "lang", "eng", "port"))
    if f.endswith(".c")
)
JA_SRCS = sorted(
    os.path.join(UP, "lang", "jpn", "port", f)
    for f in os.listdir(os.path.join(UP, "lang", "jpn", "port"))
    if f.endswith(".c")
)
JA_INCLUDES = [os.path.join(UP, "src"), os.path.join(UP, "include"),
               os.path.join(UP, "lang", "jpn", "port"), GEN]

# The Spanish engine, compiled es_-prefixed exactly like the regen script
# and the CTruVoiceES target do: its own include dir plus the generated
# rename header force-included. Object names prefixed: engine.c exists in
# both trees.
ES_SRCS = sorted(
    os.path.join(UP, "lang", "spa", sub, f)
    for sub in ("engine", "port")
    for f in os.listdir(os.path.join(UP, "lang", "spa", sub))
    if f.endswith(".c")
)
ES_INCLUDES = [os.path.join(UP, "lang", "spa", "engine"),
               os.path.join(UP, "src"), os.path.join(UP, "include"), GEN]

DRIVER = r"""
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "tvtts.h"
static int on_event(const tvtts_event *ev, void *user) {
    uint32_t *n = (uint32_t *)user;  /* n[0] = total samples, n[1] = nonzero chunks */
    if (ev->type == TVTTS_AUDIO) {
        n[0] += ev->count;
        for (uint32_t i = 0; i < ev->count; i++) {
            int16_t v = ev->samples[i];
            if (v < 0) v = -v;
            if (v > 100) { n[1] += 1; break; }
        }
    }
    return 0;
}
int main(int argc, char **argv) {
    /* argv: rate voice [language]; lines on stdin, counts on stdout.
     * With a language, the voice becomes that language's first: the
     * numbering runs across every language, so voice 0 on a British synth
     * is Peter, who is English, and tvtts_set_voice would switch the synth
     * to him -- exactly how a GB bug comes to look like "nothing
     * happened". */
    uint32_t rate = (uint32_t)atoi(argv[1]);
    int voice = atoi(argv[2]);
    const char *lang = argc > 3 ? argv[3] : "en";
    if (argc > 3) {
        int i, n = tvtts_voice_count();
        for (i = 0; i < n; i++) {
            const char *c = tvtts_voice_language(i);
            if (c != NULL && strcmp(c, lang) == 0) { voice = i; break; }
        }
    }
    tvtts_synth *s = tvtts_create_lang(rate, lang);
    if (!s) { printf("CREATE-FAILED\n"); return 1; }
    tvtts_set_voice(s, voice);
    char line[4096];
    while (fgets(line, sizeof line, stdin)) {
        size_t n = strlen(line);
        while (n > 0 && (line[n-1] == '\n' || line[n-1] == '\r')) line[--n] = 0;
        if (!n) continue;
        uint32_t c[2] = {0, 0};
        int rc = tvtts_speak_utf8(s, line, on_event, c);
        printf("%s\t%u\t%u\t%d\n", line, c[0], c[1], rc);
    }
    tvtts_destroy(s);
    return 0;
}
"""


def cc(args):
    subprocess.run(["cc", "-O2", "-w"] + args, check=True)


def compile_group(objs, objdir, sources, includes, prefix=""):
    for src in sources:
        obj = os.path.join(objdir, prefix + os.path.basename(src) + ".o")
        args = []
        for inc in includes:
            args += ["-I", inc]
        cc(args + ["-c", src, "-o", obj])
        objs.append(obj)


def build_objects(workdir):
    """Compile every translation unit the library needs; return the objects.

    Shared with tools/gb_check.py, so both proofs run against one build."""
    objdir = os.path.join(workdir, "obj")
    os.makedirs(objdir, exist_ok=True)
    objs = []
    compile_group(objs, objdir, ENGINE_SRCS, EN_INCLUDES)
    compile_group(objs, objdir, GB_SRCS, EN_INCLUDES, "gb_")
    compile_group(objs, objdir, JA_SRCS, JA_INCLUDES, "ja_")
    # The data image lives in the generated assembly.
    for asm in ("tvdata.s", "tvdata_es.s"):
        obj = os.path.join(objdir, asm.replace(".s", ".o"))
        cc(["-c", os.path.join(GEN, asm), "-o", obj])
        objs.append(obj)
    # Spanish: same objects the regen script feeds gen_data, plus its own
    # image. The rename header is generated and committed by regen.
    for src in ES_SRCS:
        obj = os.path.join(objdir, "es_" + os.path.basename(src) + ".o")
        cc(["-I", ES_INCLUDES[0], "-I", ES_INCLUDES[1], "-I", ES_INCLUDES[2],
            "-I", GEN, "-include", os.path.join(GEN, "es_rename.h"),
            "-c", src, "-o", obj])
        objs.append(obj)
    return objs


def build(workdir):
    objs = build_objects(workdir)
    drv = os.path.join(workdir, "drv.c")
    with open(drv, "w") as f:
        f.write(DRIVER)
    exe = os.path.join(workdir, "tvcheck")
    # -lm: the Japanese front end's pitch contour uses exp and log.
    cc(["-I", os.path.join(UP, "include"), "-o", exe, drv] + objs + ["-lm"])
    return exe


def run(exe, lines, rate="11025", voice="0", lang=None, env=None):
    argv = [exe, rate, voice]
    if lang:
        argv.append(lang)
    p = subprocess.run(argv, input="\n".join(lines) + "\n",
                       capture_output=True, text=True, check=True,
                       env=env)
    return p.stdout.splitlines()


def check_one(exe, corpus, golden, record, lang=None, voice="0", env=None):
    with open(os.path.join(HERE, corpus)) as f:
        lines = [ln.strip() for ln in f if ln.strip()]
    # (line, total samples, nonzero chunks, rc); nonzero chunks > 0 is audible.
    out = run(exe, lines, voice=voice, lang=lang, env=env)
    golden_path = os.path.join(HERE, golden)
    if record:
        with open(golden_path, "w") as f:
            f.write("\n".join(out) + "\n")
        print(f"recorded {len(out)} lines -> {golden_path}")
        return True
    with open(golden_path) as f:
        want = [ln.strip() for ln in f if ln.strip()]
    if out == want:
        print(f"{corpus} OK: {len(out)} lines, all golden")
        return True
    print(f"MISMATCH: {corpus}: {len(out)} produced, {len(want)} golden")
    for a, b in zip(out, want):
        if a != b:
            print(f"  got    {a}\n  golden {b}")
    if len(out) != len(want):
        print("  (different line counts)")
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--record", action="store_true")
    ap.add_argument("--workdir", default=None)
    args = ap.parse_args()

    workdir = args.workdir or tempfile.mkdtemp(prefix="itruvoice-corpus.")
    exe = build(workdir)
    ok = check_one(exe, "corpus.txt", "corpus_golden.txt", args.record)
    ok &= check_one(exe, "corpus_gb.txt", "corpus_gb_golden.txt", args.record,
                    lang="en-GB")
    # Japanese reads its dictionary from disk; pointing the engine at the
    # pinned one is what this run proves. Without it the kanji lines come out
    # short and the romaji line spells its letters, so the golden holds both.
    ja_env = dict(os.environ,
                  TVTTS_JA_DICT=os.path.join(UP, "lang", "jpn", "data", "jadic.bin"))
    ok &= check_one(exe, "corpus_ja.txt", "corpus_ja_golden.txt", args.record,
                    lang="ja", env=ja_env)
    if not ok:
        sys.exit(1)


if __name__ == "__main__":
    main()
