#!/bin/bash
# Put the Japanese dictionary where the app and its provider extension can
# find it.
#
#   tools/bundle_ja_dict.sh path/to/iTruVoice.app
#
# The engine reads jadic.bin from disk rather than carrying it in the binary:
# it is 27 MB, and an English-only utterance never opens it. TruVoiceKit's
# configureJapaneseDictionary sets TVTTS_JA_DICT to this file from the app
# bundle, and from the extension by walking up out of PlugIns.
#
# The file is not committed to this repository: it lives in the pinned upstream
# submodule and is copied in when the .app is packaged, then verified byte for
# byte. Without it Japanese still speaks kana, but drops every kanji and spells
# romaji out -- silently.
set -euo pipefail
APP="${1:?usage: bundle_ja_dict.sh <path to .app>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Vendor/upstream/lang/jpn/data/jadic.bin"
test -f "$SRC" || {
    echo "missing $SRC -- is Vendor/upstream checked out?" >&2
    exit 1
}
cp "$SRC" "$APP/jadic.bin"
cmp "$SRC" "$APP/jadic.bin"
echo "bundled jadic.bin: $(wc -c < "$APP/jadic.bin") bytes"
