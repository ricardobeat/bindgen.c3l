<*
 Translates the C type spellings emitted by the bgdump frontend into
 C3 type names.

 The frontend prints types in a prefix form so this side never has to
 implement C's declarator rules:

   int            int*          int[8]        int[]
   struct Foo     union Bar     enum Baz
   fn(<ret>)(<param>,...)       a function type
   fn(<ret>)(<param>,...)*      a pointer to one

 A trailing "*" always binds to the whole preceding type.
*>
module bgimpl::ctype;
import bgimpl::trans, bindgen::bg;
import std::io;


<*
 Translates one C type spelling to its C3 equivalent, applying the
 user's type callback to any named struct/union/enum or typedef.
 @return "C3 type name, allocated via alloc"
 @return? trans::NAME_IGNORED
*>
fn String? translate(
  Allocator alloc,
  String spelling,
  BGTransFn type_fn)
{
  String s = spelling.trim();
  if (s == "") return "void";

  // Pointer: strip one level and recurse. A pointer to a function
  // type is just the function type in C3, which has no separate
  // pointer form.
  if (s[^1] == '*') {
    String inner = s[..^2].trim();
    if (inner.starts_with("fn(")) return translate(alloc, inner, type_fn);

    String base = translate(alloc, inner, type_fn)!;
    return string::format(alloc, "%s*", base);
  }

  // Array: <elem>[N] or <elem>[]
  if (s[^1] == ']') {
    usz open = 0;
    bool found;
    foreach_r (usz i, c : s) {
      if (c == '[') { open = i; found = true; break; }
    }
    if (found) {
      String elem = translate(alloc, s[..open - 1], type_fn)!;
      String dim = s[open + 1 .. ^2];
      return dim == ""
        ? string::format(alloc, "%s*", elem)
        : string::format(alloc, "%s[%s]", elem, dim);
    }
  }

  // Function type: fn(<ret>)(<p1>,<p2>,...)
  if (s.starts_with("fn(")) return translateFn(alloc, s, type_fn);

  // A tagged record: the tag is the name the user's callback sees.
  String[3] tag_prefixes = { "struct ", "union ", "enum " };
  foreach (prefix : tag_prefixes) {
    if (s.starts_with(prefix)) {
      return trans::apply(s[prefix.len..], type_fn, alloc);
    }
  }

  // Builtin, or a typedef name the callback may rename.
  String? builtin = trans::basicType(s);
  if (try builtin) return builtin;

  return trans::apply(s, type_fn, alloc);
}


<*
 Translates a fn(<ret>)(<params>) spelling.
*>
fn String? translateFn(
  Allocator alloc,
  String s,
  BGTransFn type_fn)
{
  // Return type sits between the first "(" and its matching ")".
  usz i = 3;
  usz depth = 1;
  usz ret_end = 0;
  for (; i < s.len; i++) {
    if (s[i] == '(') depth++;
    if (s[i] == ')') {
      depth--;
      if (depth == 0) { ret_end = i; break; }
    }
  }
  if (!ret_end) return trans::NAME_IGNORED~;

  String ret = translate(alloc, s[3..ret_end - 1], type_fn)!;

  // Parameters follow, in the next parenthesised group.
  usz p_start = ret_end + 2;
  if (p_start > s.len) return trans::NAME_IGNORED~;
  String params = s[p_start..^2];

  DString out;
  out.init(alloc);
  out.appendf("fn %s(", ret);

  if (params.trim() != "") {
    depth = 0;
    usz start = 0;
    bool first = true;
    foreach (usz j, c : params) {
      if (c == '(') depth++;
      if (c == ')') depth--;
      if (c == ',' && depth == 0) {
        if (!first) out.append(", ");
        out.append(translateParam(alloc, params[start:j - start], type_fn)!);
        first = false;
        start = j + 1;
      }
    }
    if (!first) out.append(", ");
    out.append(translateParam(alloc, params[start..], type_fn)!);
  }

  out.append(")");
  return out.str_view();
}


<*
 One parameter of a function type. "..." passes through untouched.
*>
fn String? translateParam(Allocator alloc, String p, BGTransFn type_fn)
{
  String t = p.trim();
  if (t == "...") return "...";
  return translate(alloc, t, type_fn);
}
