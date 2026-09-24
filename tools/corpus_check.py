#!/usr/bin/env python3
"""The engine proof: every corpus line must speak, with golden sample counts.

Builds the pinned engine for the host, synthesizes each line of
tools/corpus.txt through the real library, and checks two things: the audio
is non-silent, and its length matches tools/corpus_golden.txt exactly. The
engine is deterministic given its data, so a count change means the code, the
generated files, or the data moved -- rebuild the golden deliberately with
--record after reading the diff, never blindly.

Usage: corpus_check.py [--record] [--workdir DIR]
"""
import argparse
import os
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
UP = os.path.join(ROOT, "Vendor", "upstream")
GEN = os.path.join(ROOT, "Vendor", "generated")

ENGINE_SRCS = sorted(
    os.path.join(UP, "src", "engine", f)
    for f in os.listdir(os.path.join(UP, "src", "engine"))
    if f.endswith(".c")
) + [
    os.path.join(UP, "src", "port", "tvtts.c"),
    os.path.join(UP, "src", "port", "msvcrt.c"),
    os.path.join(UP, "src", "port", "stubs.c"),
]

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
    /* argv: rate voice_index ; lines on stdin, counts on stdout */
    uint32_t rate = (uint32_t)atoi(argv[1]);
    int voice = atoi(argv[2]);
    tvtts_synth *s = tvtts_create(rate);
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


def build(workdir):
    objdir = os.path.join(workdir, "obj")
    os.makedirs(objdir, exist_ok=True)
    objs = []
    for src in ENGINE_SRCS:
        obj = os.path.join(objdir, os.path.basename(src) + ".o")
        subprocess.run(
            ["cc", "-O2", "-w", "-I", os.path.join(UP, "src"),
             "-I", os.path.join(UP, "include"), "-I", GEN,
             "-c", src, "-o", obj],
            check=True,
        )
        objs.append(obj)
    # The data image lives in the generated assembly.
    subprocess.run(["cc", "-w", "-c", os.path.join(GEN, "tvdata.s"),
                    "-o", os.path.join(objdir, "tvdata.o")], check=True)
    objs.append(os.path.join(objdir, "tvdata.o"))
    drv = os.path.join(workdir, "drv.c")
    with open(drv, "w") as f:
        f.write(DRIVER)
    exe = os.path.join(workdir, "tvcheck")
    subprocess.run(["cc", "-O2", "-w", "-I", os.path.join(UP, "include"),
                    "-o", exe, drv] + objs, check=True)
    return exe


def run(exe, lines, rate="11025", voice="0"):
    p = subprocess.run([exe, rate, voice], input="\n".join(lines) + "\n",
                       capture_output=True, text=True, check=True)
    return p.stdout.splitlines()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--record", action="store_true")
    ap.add_argument("--workdir", default=None)
    args = ap.parse_args()

    with open(os.path.join(HERE, "corpus.txt")) as f:
        lines = [ln.strip() for ln in f if ln.strip()]

    workdir = args.workdir or tempfile.mkdtemp(prefix="itruvoice-corpus.")
    exe = build(workdir)
    # (line, total samples, nonzero chunks, rc); nonzero chunks > 0 means audible.
    out = run(exe, lines)
    golden_path = os.path.join(HERE, "corpus_golden.txt")
    if args.record:
        with open(golden_path, "w") as f:
            f.write("\n".join(out) + "\n")
        print(f"recorded {len(out)} lines -> {golden_path}")
        return

    with open(golden_path) as f:
        golden = [ln.strip() for ln in f if ln.strip()]
    if out == golden:
        print(f"corpus OK: {len(out)} lines, all golden")
        return
    print(f"MISMATCH: {len(out)} produced, {len(golden)} golden")
    for a, b in zip(out, golden):
        if a != b:
            print(f"  got    {a}\n  golden {b}")
    if len(out) != len(golden):
        print("  (different line counts)")
    sys.exit(1)


if __name__ == "__main__":
    main()
