# chibicc backend spike — feasibility findings

Goal: replace libclang with a vendored chibicc so that using this
library does not require the user to install a compiler. Platform
headers that ship with the OS (the macOS SDK, /usr/include on Linux)
are considered available; libclang is not, because it must be
installed separately.

chibicc: MIT, 8.9k LOC, 7.3k without codegen.c. Builds clean on macOS
arm64 into a 207KB binary with no dependencies.

## Result

**All 20 stress libraries parse**, after ~470 lines of patches.

| stage | passes |
|---|---|
| unpatched chibicc, SDK headers | 3/20 |
| + `__builtin_va_list`, attribute skipping, `#warning` | 15/20 |
| + `__has_*`/`__is_target_*`, `__has_include`, ext asm, `__inline` | 19/20 |
| + implicit struct tags | **20/20** |

Struct layout was verified against clang, not assumed: size, alignment,
bitfield packing and union size all match for a self-referential
struct, a mixed bitfield struct and a union.

chibicc's own test suite goes 38 pass / 3 fail; those 3 (atomic,
pragma-once, tls) fail on unpatched upstream too.

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

## The rest of the patches

4. **`__has_*` family** — `__has_builtin`, `__has_feature`,
   `__has_attribute`, `__has_extension` and friends answer 0, which
   selects each header's portable fallback path. `__has_include` is
   resolved for real, since answering 0 for a header that exists
   changes which declarations we see.
5. **`__is_target_*`** — clang's target predicates, used by
   AvailabilityInternalLegacy.h. Same treatment as `__has_*`.
6. **GNU extended asm** — `asm("..." : outputs : inputs : clobbers)`.
   The clauses are skipped; we never generate code from a header.
   `__asm__` also had to become a keyword, since aliasing it to `asm`
   via a macro collides with its use as a symbol-rename attribute.
7. **`_FORTIFY_SOURCE=0`, `__GNUC__=4`** as built-in defines. The
   fortified string/stdio paths need `__builtin___*_chk` and the
   bounds-safety attributes; `__GNUC__` stops cdefs.h rejecting us.
8. **`__inline`** aliased to `inline` (only `__inline__` was).
9. **Implicit struct tags** — C++ lets a struct tag be used as a type
   name without the keyword, and cute_tiled.h relies on it *inside*
   the struct that declares the tag. Needed two changes: consult tags
   in `find_typedef` (only when the name is not bound as a variable,
   or `struct t {..}; int t;` breaks), and push the tag before parsing
   members so the self-reference resolves.

Two regressions were caught by chibicc's own tests and fixed: the
variable-vs-tag shadowing above, and an incomplete-type marker that
leaked past member parsing and suppressed struct layout.

## Macro introspection (resolved)

The open question from the first pass was macros: chibicc kept its
`Macro` struct private to preprocess.c, while the tool leans on
libclang's `CURSOR_MACRO_DEFINITION` for `#define` constants, which are
a large share of a real binding.

This is now exposed and verified. `chibicc.h` gains a `MacroDef` view
and three functions -- `macro_count`, `macro_list`, `macro_lookup` --
that read the post-preprocessing macro table without leaking the
internal representation.

Three details that mattered:

- **Tombstones.** `hashmap_delete` marks a bucket with a `TOMBSTONE`
  sentinel rather than clearing the key, so walking buckets naively
  resurrects `#undef`-ed macros. Added `hashmap_entry_live()` in
  hashmap.c, since the sentinel is private there.
- **Source location.** The macro table holds every macro from every
  transitively included system header (467 for cJSON). `Macro` now
  records the name token, so `MacroDef` carries `filename`/`line_no`
  and a caller can keep only the ones from the header it asked about
  -- 467 drops to 24 for cJSON.
- **Bodies are unexpanded.** `cJSON_SetBoolValue`'s body comes through
  referencing `cJSON_True`, not its expansion. That is what the current
  tool wants: `trans::tokensUnderCursor` does its own identifier
  translation over the raw token list.

Parity check against the current libclang output for cJSON.h: chibicc
reports all 21 macros the tool emits, plus `cJSON__h` (include guard),
`CJSON_CDECL` and `CJSON_STDCALL` (empty platform macros). Object-like
vs function-like, parameter lists and `__VA_ARGS__` all come through
correctly.

`dumpmacros.c` is a standalone probe that prints the table as JSON.

## What is NOT done

This spike stopped at "can chibicc parse these headers". Still unbuilt:

- the AST-dump pass (walk `Obj`/`Type`, emit JSON)
- the C3-side consumer replacing `bindgen.c3l/src/visitors.c3` and the
  92 `clang::*` entry points the tool currently uses
- Linux/Windows include-path defaults (currently hardcoded x86_64 Linux)

## Assessment

The semantic layer is a genuine fit: `Type.size`/`align`,
`Member.bit_offset`/`bit_width`, and the exported `const_expr` are
exactly the libclang facilities this tool depends on, and they are the
part a tree-sitter approach could not supply.

On extension coverage: this went better than expected. ~470 lines took
3/20 to 20/20, and most of it is mechanical (answer 0, skip tokens).
The caveat is that this is one SDK on one platform; Linux glibc and
Windows headers will surface their own set, and the patch is now large
enough that tracking upstream chibicc is not realistic. Upstream
tracking is explicitly not a goal here.

Recommendation: continue. The macro story checked out, which was the
main open risk. The remaining work is mechanical (AST dump + C3
consumer) rather than exploratory; the standing cost is extension
coverage, which is maintenance rather than a blocker.

If the eventual goal is porting chibicc to C3, the exposed surface --
`MacroDef`, `Type`, `Member`, `Obj`, `const_expr` -- is a reasonable
shape to port against, since it avoids the internal representations.
