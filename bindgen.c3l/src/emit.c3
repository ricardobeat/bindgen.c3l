<*
 Walks the declarations read from the frontend dump and drives the
 writers, applying the user's translation and generation callbacks.

 This is the backend-specific half of the generator: everything below
 wter:: and valgen:: is shared with whatever frontend produced the
 declarations.
*>
module bgimpl::emit;
import bgimpl, bgimpl::cparse, bgimpl::ctype, bgimpl::trans,
       bgimpl::tparse, bgimpl::valgen, bgimpl::wter, bgimpl::err;
import bindgen::bg;
import std::collections::list, std::io;


<*
 Everything the emitter needs that is not a declaration.
*>
struct EmitCtx
{
  OutStream         out;
  WriteState        write_state;
  String            module_name;
  BGTransCallbacks  trans_fns;
  BGGenCallbacks    gen_fns;
  BGModuleWrap      prev_module_wrap;
  bool              no_verbose;
}


<*
 Emits C3 declarations for every entry in decls.
*>
fn void? emitAll(
  Allocator alloc,
  EmitCtx* ctx,
  List{CDecl}* decls)
{
  foreach (&d : decls) {
    switch (d.kind) {
      case TYPEDEF: emitTypedef(alloc, ctx, d)!;
      case STRUCT:  emitRecord(alloc, ctx, d, is_union: false)!;
      case UNION:   emitRecord(alloc, ctx, d, is_union: true)!;
      case ENUM:    emitEnum(alloc, ctx, d)!;
      case ECONST:  emitEnumConst(alloc, ctx, d)!;
      case FUNC:    emitFunc(alloc, ctx, d)!;
      case VAR:     emitVar(alloc, ctx, d)!;
      case MACRO:   emitMacro(alloc, ctx, d)!;
    }
  }
}


<*
 A typedef becomes an alias, or a function alias when it names a
 function type.
*>
fn void? emitTypedef(Allocator alloc, EmitCtx* ctx, CDecl* d) => @pool()
{
  String? name = trans::apply(d.name, ctx.trans_fns.type, tmem);
  if (catch name) {
    err::warn(ctx.no_verbose, "Alias '%s' is ignored", d.name);
    return;
  }

  String? under = ctype::translate(tmem, d.type, ctx.trans_fns.type);
  if (catch under) {
    err::warn(ctx.no_verbose,
      "Can't translate alias '%s' as its underlying type '%s' is ignored",
      d.name, d.type);
    return;
  }

  valgen::moduleWrap(ctx.out, &ctx.write_state, ctx.module_name, ctx.gen_fns,
    &ctx.prev_module_wrap, d.name);
  WriteAttrs attrs = valgen::getWriteAttrs(tmem, d.name, ctx.gen_fns);
  wter::typedefAlias(ctx.out, &ctx.write_state, name, under, attrs)!;
}


<*
 A struct or union. Members are converted to CFields first so the
 existing bitfield grouping in tparse can produce the C3 layout.
*>
fn void? emitRecord(Allocator alloc, EmitCtx* ctx, CDecl* d, bool is_union)
  => @pool()
{
  String? name = trans::apply(d.name, ctx.trans_fns.type, tmem);
  if (catch name) {
    err::warn(ctx.no_verbose, "Record '%s' is ignored", d.name);
    return;
  }

  CFields cfs;
  cfs.init(tmem);

  foreach (f : d.fields) {
    String? ftype = ctype::translate(tmem, f.type, ctx.trans_fns.type);
    if (catch ftype) {
      err::warn(ctx.no_verbose,
        "Can't translate field '%s' of '%s' as its type '%s' is ignored",
        f.name, d.name, f.type);
      return;
    }

    if (f.bit_width >= 0) {
      cfs.kinds.push(BIT);
      cfs.bit.push({ .type = ftype, .name = f.name, .width = (usz)f.bit_width });
    } else {
      cfs.kinds.push(NORMAL);
      cfs.norm.push({ .type = ftype, .name = f.name });
    }
  }

  C3Fields c3f = tparse::getC3Fields(tmem, cfs)!;

  valgen::moduleWrap(ctx.out, &ctx.write_state, ctx.module_name, ctx.gen_fns,
    &ctx.prev_module_wrap, d.name);
  WriteAttrs attrs = valgen::getWriteAttrs(tmem, d.name, ctx.gen_fns);

  if (is_union) {
    wter::unionDecl(ctx.out, &ctx.write_state, name, &c3f, attribs: attrs)!;
  } else {
    wter::structDecl(ctx.out, &ctx.write_state, name, &c3f, attribs: attrs)!;
  }
}


<*
 An enum becomes a distinct typedef over its underlying integer type;
 its constants are emitted separately as ECONST records.
*>
fn void? emitEnum(Allocator alloc, EmitCtx* ctx, CDecl* d) => @pool()
{
  String? name = trans::apply(d.name, ctx.trans_fns.type, tmem);
  if (catch name) {
    err::warn(ctx.no_verbose, "Enum '%s' is ignored", d.name);
    return;
  }

  String under = ctype::translate(tmem, d.type, ctx.trans_fns.type)!;

  valgen::moduleWrap(ctx.out, &ctx.write_state, ctx.module_name, ctx.gen_fns,
    &ctx.prev_module_wrap, d.name);
  WriteAttrs attrs = valgen::getWriteAttrs(tmem, d.name, ctx.gen_fns);
  wter::enumDecl(ctx.out, &ctx.write_state, name, under)!;
}


<*
 An enum constant. Anonymous-enum constants carry no enum name, so
 they are emitted without a cast; see the note in the writers.
*>
fn void? emitEnumConst(Allocator alloc, EmitCtx* ctx, CDecl* d) => @pool()
{
  String? name = trans::apply(d.name, ctx.trans_fns.constant, tmem);
  if (catch name) {
    err::warn(ctx.no_verbose, "Constant '%s' is ignored", d.name);
    return;
  }

  String val = valgen::apply(tmem, d.name, ctx.gen_fns.constant);
  if (val == "") val = string::tformat("%d", d.value);

  valgen::moduleWrap(ctx.out, &ctx.write_state, ctx.module_name, ctx.gen_fns,
    &ctx.prev_module_wrap, d.name);
  WriteAttrs attrs = valgen::getWriteAttrs(tmem, d.name, ctx.gen_fns);
  wter::constDecl(ctx.out, &ctx.write_state, "", name, val, attrs)!;
}


<*
 A function declaration.
*>
fn void? emitFunc(Allocator alloc, EmitCtx* ctx, CDecl* d) => @pool()
{
  String? name = trans::apply(d.name, ctx.trans_fns.func, tmem);
  if (catch name) {
    err::warn(ctx.no_verbose, "Function '%s' is ignored", d.name);
    return;
  }

  String? ret = ctype::translate(tmem, d.type, ctx.trans_fns.type);
  if (catch ret) {
    err::warn(ctx.no_verbose,
      "Can't translate function '%s' as its return type '%s' is ignored",
      d.name, d.type);
    return;
  }

  List{VarDecl} params;
  params.tinit(4);
  foreach (p : d.params) {
    String? ptype = ctype::translate(tmem, p.type, ctx.trans_fns.type);
    if (catch ptype) {
      err::warn(ctx.no_verbose,
        "Can't translate function '%s' as parameter type '%s' is ignored",
        d.name, p.type);
      return;
    }
    params.push({ .type = ptype, .name = p.name });
  }
  if (d.variadic) params.push({ .type = "...", .name = "" });

  valgen::moduleWrap(ctx.out, &ctx.write_state, ctx.module_name, ctx.gen_fns,
    &ctx.prev_module_wrap, d.name);
  WriteAttrs attrs = valgen::getWriteAttrs(tmem, d.name, ctx.gen_fns);
  wter::func(ctx.out, &ctx.write_state, params.array_view(), ret, d.name, name, attrs)!;
}


<*
 A global variable.
*>
fn void? emitVar(Allocator alloc, EmitCtx* ctx, CDecl* d) => @pool()
{
  String? name = trans::apply(d.name, ctx.trans_fns.variable, tmem);
  if (catch name) {
    err::warn(ctx.no_verbose, "Variable '%s' is ignored", d.name);
    return;
  }

  String? type = ctype::translate(tmem, d.type, ctx.trans_fns.type);
  if (catch type) {
    err::warn(ctx.no_verbose,
      "Can't translate variable '%s' as its type '%s' is ignored",
      d.name, d.type);
    return;
  }

  String val = valgen::apply(tmem, d.name, ctx.gen_fns.variable);

  valgen::moduleWrap(ctx.out, &ctx.write_state, ctx.module_name, ctx.gen_fns,
    &ctx.prev_module_wrap, d.name);
  WriteAttrs attrs = valgen::getWriteAttrs(tmem, d.name, ctx.gen_fns);
  wter::varDecl(ctx.out, &ctx.write_state, type, name, val, attrs)!;
}


<*
 An object-like macro becomes a constant; a function-like one becomes
 a C3 macro. A macro with an empty body carries no value and is
 skipped, as it usually marks a feature flag rather than a constant.
*>
fn void? emitMacro(Allocator alloc, EmitCtx* ctx, CDecl* d) => @pool()
{
  if (!d.objlike) {
    emitFuncMacro(alloc, ctx, d)!;
    return;
  }

  String? name = trans::apply(d.name, ctx.trans_fns.constant, tmem);
  if (catch name) {
    err::warn(ctx.no_verbose, "Constant '%s' is ignored", d.name);
    return;
  }

  String val = valgen::apply(tmem, d.name, ctx.gen_fns.constant);
  if (val == "") {
    if (d.tokens.size == 0) {
      err::warn(ctx.no_verbose, "Macro '%s' doesn't have value, skipping...", d.name);
      return;
    }
    String? body = macroBody(tmem, ctx, d);
    if (catch body) {
      err::warn(ctx.no_verbose,
        "Can't translate constant '%s' as its rhs comprises ignored name", d.name);
      return;
    }
    val = body;
  }

  valgen::moduleWrap(ctx.out, &ctx.write_state, ctx.module_name, ctx.gen_fns,
    &ctx.prev_module_wrap, d.name);
  WriteAttrs attrs = valgen::getWriteAttrs(tmem, d.name, ctx.gen_fns);
  wter::constDecl(ctx.out, &ctx.write_state, "", name, val, attrs)!;
}


<*
 A function-like macro.
*>
fn void? emitFuncMacro(Allocator alloc, EmitCtx* ctx, CDecl* d) => @pool()
{
  String? name = trans::apply(d.name, ctx.trans_fns.func_macro, tmem);
  if (catch name) {
    err::warn(ctx.no_verbose, "Functional macro '%s' is ignored", d.name);
    return;
  }

  List{String} params;
  params.tinit(4);
  foreach (p : d.params) params.push(p.name);

  String body = macroBody(tmem, ctx, d) ?? "";

  valgen::moduleWrap(ctx.out, &ctx.write_state, ctx.module_name, ctx.gen_fns,
    &ctx.prev_module_wrap, d.name);
  WriteAttrs attrs = valgen::getWriteAttrs(tmem, d.name, ctx.gen_fns);
  wter::funcMacro(ctx.out, &ctx.write_state, params.array_view(), name, body, attrs)!;
}


<*
 Renders a macro replacement list, routing identifiers through the
 constant callback so a renamed constant stays consistent.
 @return? trans::NAME_IGNORED
*>
fn String? macroBody(Allocator alloc, EmitCtx* ctx, CDecl* d)
{
  DString out;
  out.init(alloc);

  foreach (t : d.tokens) {
    if (t.len == 0) continue;

    // Identifiers may name another macro constant or a parameter.
    if (t[0].is_alpha() || t[0] == '_') {
      bool is_param;
      foreach (p : d.params) if (p.name == t) { is_param = true; break; }
      if (is_param) {
        out.appendf("#%s", t);
        continue;
      }
      out.append(trans::apply(t, ctx.trans_fns.constant, alloc)!);
      continue;
    }

    out.append(t);
  }

  return out.str_view();
}
