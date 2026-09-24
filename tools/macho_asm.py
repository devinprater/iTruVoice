#!/usr/bin/env python3
"""Make gen_data's assembly palatable to Apple clang (Mach-O, arm64).

gen_data.py emits ELF-flavored assembly: a `.section .data` line Apple
rejects, and bare symbol names. On Mach-O the C compiler decorates every
symbol with a leading underscore, so `g_tab_5418:` in the data file does not
satisfy the `_g_tab_5418` that frame.c asks for. (The main blob already gets
both spellings from gen_data; the 300+ table symbols do not.)

This rewrites the generated file in place:
  1. `.section .data` -> `.data` (same thing on Mach-O: __DATA,__data).
  2. Every `.globl NAME` with no leading underscore gains `.globl _NAME`.
  3. Every `NAME:` label with no leading underscore gains a `_NAME:` alias
     on the next line, unless that alias already exists.

Everything else -- bytes, order, alignment -- is untouched, so the linked
image is identical to the ELF one symbol for symbol.
"""
import re
import sys

path = sys.argv[1]
with open(path) as f:
    lines = f.read().splitlines(keepends=True)

existing_labels = set()
for line in lines:
    m = re.match(r"^([A-Za-z_.][\w$.]*):", line)
    if m:
        existing_labels.add(m.group(1))

out = []
for line in lines:
    stripped = line.strip()
    if stripped == ".section .data":
        out.append(line.replace(".section .data", ".data"))
        continue
    m = re.match(r"^(\s*)\.globl\s+([A-Za-z][\w$.]*)$", line.rstrip("\n"))
    if m and not m.group(2).startswith("_"):
        indent, name = m.group(1), m.group(2)
        out.append(line)
        out.append(f"{indent}.globl _{name}\n")
        continue
    m = re.match(r"^([A-Za-z][\w$.]*):(.*)$", line.rstrip("\n"))
    if m and f"_{m.group(1)}" not in existing_labels:
        out.append(line)
        out.append(f"_{m.group(1)}:{m.group(2)}\n")
        existing_labels.add(f"_{m.group(1)}")
        continue
    out.append(line)

with open(path, "w") as f:
    f.writelines(out)
print(f"mach-o fixups applied to {path}")
