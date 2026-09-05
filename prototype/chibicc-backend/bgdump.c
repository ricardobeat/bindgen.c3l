// [bindgen] AST dumper: preprocess + parse a C header and write a flat,
// line-oriented description of its declarations.
//
//   bgdump <header> [-I dir]... [-D name[=val]]...
//
// Line format, tab-separated, one record per line:
//
//   typedef  <name>  <type>
//   struct   <tag>   <size> <align>          followed by field lines
//   field    <name>  <type> <offset> <bitoff> <bitwidth>
//   union    <tag>   <size> <align>          followed by field lines
//   enum     <tag>   <underlying>            followed by econst lines
//   econst   <name>  <value>
//   func     <name>  <ret> <variadic>        followed by param lines
//   param    <name>  <type>
//   var      <name>  <type>
//   macro    <name>  <objlike> <params...>   then a body line
//   mbody    <tokens...>
//   end
//
// Types are printed in a C-like spelling the C3 side re-parses, the
// same shape libclang's getTypeSpelling produced.
#include "chibicc.h"

StringArray include_paths;
char *base_file;
int align_to(int n, int align) { return (n + align - 1) / align * align; }
bool file_exists(char *path) { struct stat st; return !stat(path, &st); }

static char *type_name(Type *ty);

static char *tag_of(Type *ty) {
  return ty->tag_tok ? strndup(ty->tag_tok->loc, ty->tag_tok->len) : NULL;
}

// The file a tag was declared in, so declarations pulled in from
// system headers can be skipped.
static char *tag_file(Type *ty) {
  return ty->tag_tok ? ty->tag_tok->filename : NULL;
}

// A C-like spelling of ty. Arrays and function pointers are printed in
// a prefix form the consumer can tokenize without C's declarator rules.
static char *type_name(Type *ty) {
  if (!ty)
    return "void";

  switch (ty->kind) {
  case TY_VOID:    return "void";
  case TY_BOOL:    return "_Bool";
  case TY_CHAR:    return ty->is_unsigned ? "unsigned char" : "char";
  case TY_SHORT:   return ty->is_unsigned ? "unsigned short" : "short";
  case TY_INT:     return ty->is_unsigned ? "unsigned int" : "int";
  case TY_LONG:    return ty->is_unsigned ? "unsigned long" : "long";
  case TY_FLOAT:   return "float";
  case TY_DOUBLE:  return "double";
  case TY_LDOUBLE: return "long double";
  case TY_PTR:     return format("%s*", type_name(ty->base));
  case TY_ARRAY:
    return ty->array_len < 0
      ? format("%s[]", type_name(ty->base))
      : format("%s[%d]", type_name(ty->base), ty->array_len);
  case TY_VLA:     return format("%s[]", type_name(ty->base));
  case TY_ENUM: {
    char *t = tag_of(ty);
    return t ? format("enum %s", t) : "int";
  }
  case TY_STRUCT: {
    char *t = tag_of(ty);
    return t ? format("struct %s", t) : "struct";
  }
  case TY_UNION: {
    char *t = tag_of(ty);
    return t ? format("union %s", t) : "union";
  }
  case TY_FUNC: {
    // fn(<ret>)(<p1>,<p2>,...)
    char *s = format("fn(%s)(", type_name(ty->return_ty));
    bool first = true;
    for (Type *p = ty->params; p; p = p->next) {
      s = format("%s%s%s", s, first ? "" : ",", type_name(p));
      first = false;
    }
    if (ty->is_variadic)
      s = format("%s%s...", s, first ? "" : ",");
    return format("%s)", s);
  }
  }
  return "int";
}

static void dump_fields(Type *ty) {
  for (Member *m = ty->members; m; m = m->next) {
    char *nm = m->name ? strndup(m->name->loc, m->name->len) : "";
    printf("field\t%s\t%s\t%d\t%d\t%d\n", nm, type_name(m->ty), m->offset,
           m->is_bitfield ? m->bit_offset : -1,
           m->is_bitfield ? m->bit_width : -1);
  }
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: bgdump <header> [-I dir]... [-D name[=val]]...\n");
    return 2;
  }
  char *path = argv[1];

  init_macros();
  for (int i = 2; i < argc; i++) {
    if (!strncmp(argv[i], "-I", 2)) {
      strarray_push(&include_paths, argv[i] + 2);
    } else if (!strncmp(argv[i], "-D", 2)) {
      char *d = strdup(argv[i] + 2);
      char *eq = strchr(d, '=');
      if (eq) { *eq = '\0'; define_macro(d, eq + 1); }
      else define_macro(d, "1");
    }
  }

  Token *tok = tokenize_file(path);
  if (!tok) { fprintf(stderr, "cannot open %s\n", path); return 1; }
  tok = preprocess(tok);
  Obj *prog = parse(tok);

  // Tags: structs, unions, enums declared in this header.
  int ntags = file_scope_tag_count();
  ScopeEntry *tags = calloc(ntags, sizeof(ScopeEntry));
  ntags = file_scope_tags(tags, ntags);

  for (int i = 0; i < ntags; i++) {
    Type *ty = tags[i].type_def;
    if (!ty) continue;
    char *f = tag_file(ty);
    if (!f || strcmp(f, path))
      continue; // declared in an included header
    if (ty->kind == TY_STRUCT) {
      printf("struct\t%s\t%d\t%d\n", tags[i].name, ty->size, ty->align);
      dump_fields(ty);
      printf("end\n");
    } else if (ty->kind == TY_UNION) {
      printf("union\t%s\t%d\t%d\n", tags[i].name, ty->size, ty->align);
      dump_fields(ty);
      printf("end\n");
    } else if (ty->kind == TY_ENUM) {
      printf("enum\t%s\t%s\n", tags[i].name, ty->is_unsigned ? "unsigned int" : "int");
      printf("end\n");
    }
  }

  // Typedefs and enum constants.
  int nvars = file_scope_typedef_count();
  ScopeEntry *vars = calloc(nvars, sizeof(ScopeEntry));
  nvars = file_scope_typedefs(vars, nvars);

  for (int i = 0; i < nvars; i++) {
    if (!vars[i].filename || strcmp(vars[i].filename, path))
      continue;
    if (vars[i].type_def)
      printf("typedef\t%s\t%s\n", vars[i].name, type_name(vars[i].type_def));
    else if (vars[i].enum_ty)
      printf("econst\t%s\t%lld\n", vars[i].name, (long long)vars[i].enum_val);
  }

  // Functions and global variables.
  for (Obj *o = prog; o; o = o->next) {
    if (!o->name || o->is_local) continue;
    if (o->tok && o->tok->filename && strcmp(o->tok->filename, path)) continue;

    if (o->is_function) {
      printf("func\t%s\t%s\t%d\n", o->name, type_name(o->ty->return_ty),
             o->ty->is_variadic ? 1 : 0);
      for (Type *p = o->ty->params; p; p = p->next) {
        char *nm = p->name ? strndup(p->name->loc, p->name->len) : "";
        printf("param\t%s\t%s\n", nm, type_name(p));
      }
      printf("end\n");
    } else {
      printf("var\t%s\t%s\n", o->name, type_name(o->ty));
    }
  }

  // Macros defined by this header.
  int nm = macro_count();
  MacroDef *defs = calloc(nm, sizeof(MacroDef));
  nm = macro_list(defs, nm);
  for (int i = 0; i < nm; i++) {
    MacroDef *m = &defs[i];
    if (!m->filename || strcmp(m->filename, path)) continue;
    printf("macro\t%s\t%d", m->name, m->is_objlike ? 1 : 0);
    for (int p = 0; p < m->param_count; p++)
      printf("\t%s", m->params[p]);
    printf("\n");
    printf("mbody");
    for (Token *t = m->body; t && t->kind != TK_EOF; t = t->next)
      printf("\t%.*s", t->len, t->loc);
    printf("\n");
  }
  return 0;
}
