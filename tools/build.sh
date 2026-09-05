#!/usr/bin/env sh
# Builds the bgdump frontend. No system compiler beyond the one used
# here; chibicc is vendored in full under tools/chibicc.
set -e
cd "$(dirname "$0")"
exec ${CC:-cc} -std=c11 -O2 -fno-common -Ichibicc -o bgdump \
  bgdump.c builtin_headers.c \
  chibicc/tokenize.c chibicc/preprocess.c chibicc/parse.c \
  chibicc/type.c chibicc/hashmap.c chibicc/strings.c chibicc/unicode.c
