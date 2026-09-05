#ifndef __STDARG_H
#define __STDARG_H

// [bindgen] Declaration-only stdarg. The binding generator never
// generates code, so the va_* macros need to type-check inside an
// inline function in a header but not do anything. Upstream chibicc's
// version expands va_start to __va_area__, which only exists inside a
// variadic function body being compiled.

typedef struct {
  unsigned int gp_offset;
  unsigned int fp_offset;
  void *overflow_arg_area;
  void *reg_save_area;
} __va_elem;

typedef __va_elem va_list[1];

#define va_start(ap, last) ((void)0)
#define va_end(ap)         ((void)0)
#define va_arg(ap, ty)     (*(ty *)0)
#define va_copy(dest, src) ((dest)[0] = (src)[0])

#define __GNUC_VA_LIST 1
typedef va_list __gnuc_va_list;

#endif
