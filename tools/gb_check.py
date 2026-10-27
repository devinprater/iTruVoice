#!/usr/bin/env python3
"""Upstream's British English proof, run against iTruVoice's pinned engine.

tests/gb_check.c in the pinned upstream asks the three questions the accent
has to answer: whether GB reaches the audio at all (the synth reports GB from
inside the audio callback, and the hashes move), whether American is untouched
by it, and whether the /r/ rules -- linking, intrusive and the refusals --
hold in the phoneme string. It is the oracle for src/engine/gb.c, so it is run
here rather than reimplemented.

Its output is recorded, not merely exit-checked: at the pinned commit
upstream's own test reports one failure, the phoneme string for "far off"
(`&Fr1R&o1F.` against a wanted `&Fr1R%oF.`), and upstream's own 64-bit build
produces the same line here. A golden keeps that visible and makes any change
-- a fix upstream or a regression of ours -- a diff somebody reads.

Usage: gb_check.py [--record]
"""
import argparse
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import corpus_check  # noqa: E402  same tree, same objects

UP = corpus_check.UP
GEN = corpus_check.GEN
EXPECTED = os.path.join(HERE, "gb_check_expected.txt")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--record", action="store_true")
    args = ap.parse_args()

    test_c = os.path.join(UP, "tests", "gb_check.c")
    if not os.path.isfile(test_c):
        print("no tests/gb_check.c in the pinned upstream", file=sys.stderr)
        sys.exit(1)

    workdir = tempfile.mkdtemp(prefix="itruvoice-gbcheck.")
    objs = corpus_check.build_objects(workdir)
    exe = os.path.join(workdir, "gb_check")
    subprocess.run(
        ["cc", "-O2", "-w", "-I", os.path.join(UP, "include"),
         "-I", os.path.join(UP, "src"),
         "-I", os.path.join(UP, "lang", "eng", "data"), "-I", GEN,
         "-o", exe, test_c] + objs + ["-lm"],
        check=True,
    )
    p = subprocess.run([exe], capture_output=True, text=True)
    lines = [ln.rstrip() for ln in p.stdout.splitlines()]
    if args.record:
        with open(EXPECTED, "w") as f:
            f.write("\n".join(lines) + "\n")
        print(f"recorded {len(lines)} lines -> {EXPECTED}")
        return
    with open(EXPECTED) as f:
        want = [ln.rstrip() for ln in f.read().splitlines()]
    if lines == want:
        print(f"gb_check OK: output matches {os.path.basename(EXPECTED)}")
        return
    print("gb_check DIFFERS from the recorded upstream output:")
    for a, b in zip(lines, want):
        if a != b:
            print(f"  got      {a}\n  recorded {b}")
    if len(lines) != len(want):
        print(f"  ({len(lines)} lines, recorded {len(want)})")
    print("Read the diff before re-recording: a change here is the accent moving.")
    sys.exit(1)


if __name__ == "__main__":
    main()
