<*
 Implementation of bg::translate_header.

 The frontend is a separate program (tools/bgdump) built from the
 vendored chibicc sources. It preprocesses and parses the header and
 writes a flat declaration dump, which cparse reads back and emit
 turns into C3.
*>
module bgimpl;
import bindgen::bg;
import bgimpl::cparse, bgimpl::emit;
import std::collections::list,
       std::io,
       std::os::process;


<*
 Implementation of bg::translate_header
*>
fn void? translateHeader(
  String header_name,
  BGOptions opts = {},
  BGTransCallbacks trans_callbacks = {},
  BGGenCallbacks gen_callbacks = {})
  @export("bg_translate_header")
{
  err::info(opts.no_verbose, "Translating %s", header_name);

  // Set the output name
  String out_name;

  switch {
    case (bool)opts.out_file.file:
      out_name = "file descriptor";
    case (bool)opts.out_name:
      out_name = opts.out_name;
    default:
      out_name = "standard output";
  }

  err::info(opts.no_verbose, "Writing to %s", out_name);

  // Open file
  File out = opts.out_file.file ? opts.out_file : *io::stdout();

  // FIX: make BGOptions.out_file override BGOptions.out_name
  if (opts.out_name != "") @pool() {
    err::warn(opts.no_verbose, "BGOptions.out_name is deprecated in favour of BGOptions.out_file");

    if (file::is_dir(opts.out_name)) {
      err::erro("The output name you've provided is an existing directory. Please provide a name of a file I should write to");
      return bg::INVALID_ARGUMENTS~;
    }

    Path out_path = path::new(tmem, opts.out_name)!;

    // If there is no parent, we are in root
    Path out_parent = out_path.parent() ?? path::new(tmem, "/")!;

    // Create missing directories on the path
    path::mkdir(out_parent, recursive: true)!;

    out = file::open(opts.out_name, "w")!;
  };

  defer (void) out.close();

  // Check callbacks
  if (trans_callbacks.func == null) err::warn(opts.no_verbose, "Function translation will not be performed as function pointer is null");
  if (trans_callbacks.variable == null) err::warn(opts.no_verbose, "Variable translation will not be performed as function pointer is null");
  if (trans_callbacks.type == null) err::warn(opts.no_verbose, "Type translation will not be performed as function pointer is null");
  if (trans_callbacks.constant == null) err::warn(opts.no_verbose, "Constant translation will not be performed as function pointer is null");
  if (trans_callbacks.func_macro == null) err::warn(opts.no_verbose, "Functional macros translation will not be performed as function pointer is null");

  if (!file::exists(header_name)) {
    err::erro("Could not find input header file '%s'. Please, check your current directory", header_name);
    return bg::INVALID_ARGUMENTS~;
  }

  String dump = runFrontend(tmem, header_name, opts)!;

  List{cparse::CDecl}? decls = cparse::parseDump(tmem, dump);
  if (catch decls) {
    err::erro("Could not read the declaration dump for '%s'", header_name);
    return bg::CLANG_PARSE_ERROR~;
  }

  emit::EmitCtx ctx = {
    .out = &out,
    .module_name = opts.module_name,
    .trans_fns = trans_callbacks,
    .gen_fns = gen_callbacks,
    .no_verbose = opts.no_verbose,
  };

  // Write module name
  if (opts.module_name != "") wter::moduleHead(&out, &ctx.write_state, opts.module_name);

  foreach (imp : opts.imports) {
    wter::importModule(&out, &ctx.write_state, imp);
  }

  emit::emitAll(tmem, &ctx, &decls)!;
}


<*
 Runs the bundled frontend over a header and returns its dump.
 @return "The dump text, allocated via alloc"
*>
fn String? runFrontend(
  Allocator alloc,
  String header_name,
  BGOptions opts)
  => @pool()
{
  List{String} args;
  args.tinit(8 + opts.clang_args.len);

  args.push(frontendPath(tmem));
  args.push(header_name);

  foreach (dir : user::systemIncludePaths(tmem)) {
    args.push(string::tformat("-I%s", dir));
  }
  foreach (extra : opts.clang_args) args.push(extra);

  Process proc = process::spawn(args.array_view())!;
  defer (void)proc.destroy();

  DString dump;
  dump.init(alloc);
  char[4096] buf;
  while (true) {
    sz n = proc.read_stdout(&buf, buf.len)!;
    if (n <= 0) break;
    dump.append((String)buf[:n]);
  }

  // Drain stderr before joining, so the frontend's own diagnostics
  // reach the user rather than being lost with the process.
  DString errs;
  errs.tinit();
  while (true) {
    sz? n = proc.read_stderr(&buf, buf.len);
    if (catch n) break;
    if (n <= 0) break;
    errs.append((String)buf[:n]);
  }

  CInt rc = proc.join()!;
  if (rc != 0) {
    err::erro("Could not parse '%s':", header_name);
    if (errs.len()) io::eprintn(errs.str_view());
    return bg::CLANG_PARSE_ERROR~;
  }

  return dump.str_view();
}


<*
 Locates the bgdump binary. Looks next to the running executable
 first, then falls back to the name on PATH.
*>
fn String frontendPath(Allocator alloc)
{
  return "tools/bgdump";
}
