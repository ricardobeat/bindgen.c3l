// [bindgen] Standalone probe: preprocess a header and dump its macro
// table, to verify the macro_* API exposes what a binding generator
// needs. Not part of chibicc proper.
#include "chibicc.h"

// Normally provided by main.c, which we do not link.
StringArray include_paths;
char *base_file;

int align_to(int n, int align) {
  return (n + align - 1) / align * align;
}

bool file_exists(char *path) {
  struct stat st;
  return !stat(path, &st);
}

static void print_escaped(char *s, int len) {
  for (int i = 0; i < len; i++) {
    char c = s[i];
    if (c == '"' || c == '\\') printf("\\%c", c);
    else if (c == '\n') printf("\\n");
    else putchar(c);
  }
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: dumpmacros <header> [-I dir]...\n");
    return 2;
  }

  init_macros();
  for (int i = 2; i < argc; i++)
    if (!strncmp(argv[i], "-I", 2))
      strarray_push(&include_paths, argv[i] + 2);

  Token *tok = tokenize_file(argv[1]);
  if (!tok) { fprintf(stderr, "cannot open %s\n", argv[1]); return 1; }
  preprocess(tok);

  int n = macro_count();
  MacroDef *defs = calloc(n, sizeof(MacroDef));
  n = macro_list(defs, n);

  // Only macros defined in the file we were asked about; the table
  // also holds every macro from transitively included system headers.
  char *want = argv[1];

  printf("[\n");
  bool first_out = true;
  for (int i = 0; i < n; i++) {
    MacroDef *m = &defs[i];
    if (!m->filename || strcmp(m->filename, want))
      continue;
    if (!first_out) printf(",\n");
    first_out = false;
    printf("  {\"name\":\"%s\",\"objlike\":%s,\"builtin\":%s,\"params\":[",
           m->name, m->is_objlike ? "true" : "false",
           m->is_builtin ? "true" : "false");
    for (int p = 0; p < m->param_count; p++)
      printf("%s\"%s\"", p ? "," : "", m->params[p]);
    printf("]");
    if (m->va_args_name)
      printf(",\"va_args\":\"%s\"", m->va_args_name);
    printf(",\"body\":\"");
    for (Token *t = m->body; t && t->kind != TK_EOF; t = t->next) {
      if (t != m->body) putchar(' ');
      print_escaped(t->loc, t->len);
    }
    printf("\"}");
  }
  printf("\n]\n");
  return 0;
}
