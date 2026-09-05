import bindgen;
import std::io, std::os;

fn void main(String[] args) {
  if (args.len < 3) {
    io::eprintn("usage: stress <header> <module> [out]");
    os::exit(2);
  }

  BGOptions opts = {
    .out_name = args.len > 3 ? args[3] : "",
    .module_name = args[2],
    .no_verbose = true,
  };

  BGTransCallbacks tcb = {
    .func       = &bgstr::mixed_to_camel,
    .type       = &bgstr::mixed_to_pascal,
    .variable   = &bgstr::mixed_to_snake,
    .constant   = &bgstr::mixed_to_screaming,
    .func_macro = &bgstr::mixed_to_snake,
  };

  bg::translate_header(args[1], opts, tcb, {})!!;
}
