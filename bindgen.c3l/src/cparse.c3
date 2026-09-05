<*
 The module reads the flat declaration dump produced by the bundled
 chibicc frontend (tools/bgdump) and turns it back into the CDecl
 values the translators consume.

 The dump is tab-separated, one record per line. Records that own a
 list of children are followed by those children and closed by "end":

   typedef <name> <type>
   struct  <tag>  <size> <align>   field... end
   union   <tag>  <size> <align>   field... end
   enum    <tag>  <underlying>     end
   field   <name> <type> <offset> <bitoffset> <bitwidth>
   econst  <name> <value>
   func    <name> <ret> <variadic> param... end
   param   <name> <type>
   var     <name> <type>
   macro   <name> <objlike> <param>...
   mbody   <token>...

 A bitoffset/bitwidth of -1 means the field is not a bitfield.
*>
module bgimpl::cparse;
import bgimpl;
import std::collections::list, std::io;

faultdef MALFORMED_RECORD;


<*
 One declaration read from the dump, in source order.
*>
struct CDecl
{
  CDeclKind         kind;
  String            name;
  String            type;      // typedef target, field/var type, fn return
  long              value;     // enum constant value
  bool              variadic;  // functions
  bool              objlike;   // macros
  List{VarDecl}     params;    // function params, macro params
  List{CField}      fields;    // struct/union members
  List{String}      tokens;    // macro replacement list
}

enum CDeclKind : char
{
  TYPEDEF,
  STRUCT,
  UNION,
  ENUM,
  ECONST,
  FUNC,
  VAR,
  MACRO,
}


<*
 A struct or union member. Bit offset and width are -1 when the member
 is not a bitfield.
*>
struct CField
{
  String  name;
  String  type;
  int     offset;
  int     bit_offset;
  int     bit_width;
}


<*
 Splits a dump line on tabs. The returned slices point into line.
*>
fn String[] splitRecord(Allocator alloc, String line)
{
  List{String} out;
  out.init(alloc, 8);

  usz start = 0;
  foreach (usz i, c : line) {
    if (c == '\t') {
      out.push(line[start:i - start]);
      start = i + 1;
    }
  }
  out.push(line[start..]);

  return out.to_array(alloc);
}


<*
 Reads a whole dump into a list of declarations, in the order the
 frontend emitted them.
 @return "List of CDecl, allocated via alloc"
*>
fn List{CDecl}? parseDump(Allocator alloc, String dump)
{
  List{CDecl} decls;
  decls.init(alloc, 64);

  CDecl* open;

  foreach (line : dump.tsplit("\n")) {
    if (line == "") continue;

    String[] f = splitRecord(alloc, line);
    String tag = f[0];

    if (tag == "end") {
      open = null;
      continue;
    }

    // Child records extend the declaration still open.
    if (tag == "field") {
      if (!open || f.len < 6) return MALFORMED_RECORD~;
      open.fields.push({
        .name       = f[1].copy(alloc),
        .type       = f[2].copy(alloc),
        .offset     = f[3].to_int() ?? 0,
        .bit_offset = f[4].to_int() ?? -1,
        .bit_width  = f[5].to_int() ?? -1,
      });
      continue;
    }

    if (tag == "param") {
      if (!open || f.len < 3) return MALFORMED_RECORD~;
      open.params.push({ .name = f[1].copy(alloc), .type = f[2].copy(alloc) });
      continue;
    }

    if (tag == "mbody") {
      if (!open) return MALFORMED_RECORD~;
      foreach (t : f[1..]) open.tokens.push(t.copy(alloc));
      continue;
    }

    // Otherwise this record starts a new declaration.
    CDecl d;
    d.params.init(alloc, 4);
    d.fields.init(alloc, 8);
    d.tokens.init(alloc, 8);
    if (f.len < 2) return MALFORMED_RECORD~;
    d.name = f[1].copy(alloc);

    switch (tag) {
      case "typedef":
        if (f.len < 3) return MALFORMED_RECORD~;
        d.kind = TYPEDEF;
        d.type = f[2].copy(alloc);
      case "struct":
        d.kind = STRUCT;
      case "union":
        d.kind = UNION;
      case "enum":
        if (f.len < 3) return MALFORMED_RECORD~;
        d.kind = ENUM;
        d.type = f[2].copy(alloc);
      case "econst":
        if (f.len < 3) return MALFORMED_RECORD~;
        d.kind = ECONST;
        d.value = f[2].to_long() ?? 0;
      case "func":
        if (f.len < 4) return MALFORMED_RECORD~;
        d.kind = FUNC;
        d.type = f[2].copy(alloc);
        d.variadic = f[3] == "1";
      case "var":
        if (f.len < 3) return MALFORMED_RECORD~;
        d.kind = VAR;
        d.type = f[2].copy(alloc);
      case "macro":
        if (f.len < 3) return MALFORMED_RECORD~;
        d.kind = MACRO;
        d.objlike = f[2] == "1";
        foreach (p : f[3..]) d.params.push({ .name = p.copy(alloc), .type = "" });
      default:
        return MALFORMED_RECORD~;
    }

    decls.push(d);
    open = decls.get_ref(decls.size - 1);
  }

  return decls;
}
