#!/bin/bash
# Regenerate Vendor/generated from the pinned upstream. Run deliberately when
# the submodule pin moves, then commit the result: device builds never run
# codegen.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UP="$ROOT/Vendor/upstream"
GEN="$ROOT/Vendor/generated"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

python3 "$UP/tools/gen_struct.py" "$UP/src/engine.fields" "$GEN/engine_struct.h"

gcc -O2 -w -I"$UP/src" -I"$UP/include" -I"$GEN" -c "$UP"/src/engine/*.c \
  "$UP"/src/port/tvtts.c "$UP"/src/port/msvcrt.c "$UP"/src/port/stubs.c \
  --output-dir="$TMP" 2>/dev/null || {
  # Older gcc has no --output-dir: compile file by file.
  for f in "$UP"/src/engine/*.c "$UP"/src/port/tvtts.c \
           "$UP"/src/port/msvcrt.c "$UP"/src/port/stubs.c; do
    n=$(basename "$f" .c)
    gcc -O2 -w -I"$UP/src" -I"$UP/include" -I"$GEN" -c "$f" -o "$TMP/$n.o"
  done
}
# The assembly is committed, translated to what Apple clang assembles
# (tools/macho_asm.py): the ELF section line and bare symbol names need it.
# N.B. the image must stay ONE packed file in gen_data's order: the engine
# reads past the end of some tables into the next (see tv_ref.h), so
# splitting it per symbol or reordering would move what those overreads land
# on. macho_asm.py adds labels only; it moves no byte.
python3 "$UP/tools/gen_data.py" "$UP/data/en/engine.tvdata" "$UP/src" \
  "$GEN/tvdata.s" "$TMP"/*.o
python3 "$ROOT/tools/macho_asm.py" "$GEN/tvdata.s"
echo "regenerated: $(ls -la "$GEN")"
