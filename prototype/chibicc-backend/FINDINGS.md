# chibicc backend spike — feasibility findings

Goal: replace libclang with a vendored chibicc so that using this
library does not require the user to install a compiler. Platform
headers that ship with the OS (the macOS SDK, /usr/include on Linux)
are considered available; libclang is not, because it must be
installed separately.

chibicc: MIT, 8.9k LOC, 7.3k without codegen.c. Builds clean on macOS
arm64 into a 207KB binary with no dependencies.

## Result

**Promising. 15 of the 20 stress libraries parse, after 61 lines of
patches.** The remaining 5 fail on Apple-specific extensions, not on
anything structural.

| stage | passes |
|---|---|
| unpatched chibicc, SDK headers | 3/20 |
| + `__builtin_va_list`, attribute skipping, `#warning` | **15/20** |

Note the unpatched 3/20 is the honest baseline; an earlier 17/20
figure measured only preprocessing, which is not the hard part.

## The patches (`chibicc-bindgen.patch`, 61 added lines)

1. **`__builtin_va_list`** — registered in `is_typename` and modelled
   as `void*` in `declspec`. Reached transitively by anything that
   includes `<stdint.h>`, so this alone unblocked most headers.
2. **Attribute skipping** — `attribute_list` hard-errored on any
   attribute but `packed`/`aligned`. Added `skip_trailing_attrs`,
   called after `declarator()` in `function()` and
   `global_variable()`, plus a leading-position branch in `declspec`.
   Real headers use availability, deprecated, format, nonnull; none
   affect the emitted binding.
3. **`#warning`** — not implemented, and Apple's `sys/cdefs.h` uses it
   to reject non-clang compilers. Now consumed and ignored.

`-D__GNUC__=4 -D__GNUC_MINOR__=2` is still required so `cdefs.h` takes
its GNU path. That should become a built-in define.

## Remaining 5 failures

- `stb_image` — `__header_always_inline` in `_stdio.h`
- `json`, `stb_ds` — `__has_builtin` / `_Nullable` in `secure/_string.h`
- `stb_image_write` — `Availability.h`
- `cute_tiled` — genuinely C++, needs `-x c++` (fails under libclang too)

So 4 of 5 are Apple extension long-tail. Each is individually small;
the set is open-ended, which is the standing argument against small C
frontends.

## What is NOT done

This spike stopped at "can chibicc parse these headers". Still unbuilt:

- the AST-dump pass (walk `Obj`/`Type`, emit JSON)
- the C3-side consumer replacing `bindgen.c3l/src/visitors.c3` and the
  92 `clang::*` entry points the tool currently uses
- macro handling. chibicc's `Macro` struct is internal to
  preprocess.c and not exposed; the current tool leans on libclang's
  `CURSOR_MACRO_DEFINITION` + `tokenize` for `#define` constants,
  which is a large fraction of what it emits
- Linux/Windows include-path defaults (currently hardcoded x86_64 Linux)

## Assessment

The semantic layer is a genuine fit: `Type.size`/`align`,
`Member.bit_offset`/`bit_width`, and the exported `const_expr` are
exactly the libclang facilities this tool depends on, and they are the
part a tree-sitter approach could not supply.

The risk is unchanged from the outset but is now quantified: extension
coverage. 61 lines bought 12 headers; the next 4 will each cost their
own patch, and new SDK releases can add more. That is maintenance the
libclang backend does not carry.

Recommendation: worth continuing only if the macro story checks out.
That is the next thing to probe, because macro constants are a large
share of real bindings and chibicc does not currently expose them.
