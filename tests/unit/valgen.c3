
module bgimpl::valgen @test;
import bindgen::bg,
       std::io;


fn void test_apply()
{
  BGGenFn genfn = fn (name, alloc) => name.to_upper_copy(alloc);
  String res1 = apply(tmem, "name", genfn);
  assert( res1 == "NAME" );

  BGModuleWrapFn wrapfn = fn (name, alloc) => { 
    .if_condition = name.to_upper_copy(alloc),
    .imports = name[..2].copy(alloc),
  };
  BGModuleWrap res2 = apply(tmem, "name", wrapfn);
  assert( res2.if_condition == "NAME" );
  assert( res2.imports == "nam" );
  
  String res3 = apply(tmem, "name", (BGGenFn)null);
  assert( res3 == "" );
  
  BGModuleWrap res4 = apply(tmem, "name", (BGModuleWrapFn)null);
  assert( res4.if_condition == "" );
  assert( res4.imports == "" );
}


fn void test_get_write_attrs()
{
  BGGenCallbacks callbacks = { .if_condition = null, };
  WriteAttrs attrs = getWriteAttrs(tmem, "name", callbacks);
  assert( attrs.if_condition == "" );

  callbacks = { .if_condition = fn (name, alloc) => name == "name" ? "HELLO" : "NO", };
  attrs = getWriteAttrs(tmem, "name", callbacks);
  assert( attrs.if_condition == "HELLO" );

  attrs = getWriteAttrs(tmem, "other_name", callbacks);
  assert( attrs.if_condition == "NO" );
}


fn void test_module_wrap()
{
  DString out;
  out.tinit();

  WriteState state;
  BGGenCallbacks gen_fns;
  BGModuleWrap prev;

  const EXPECTED_1 = "";
  moduleWrap(&out, &state, "hello", gen_fns, &prev, "name");
  assert( out.str_view() == EXPECTED_1 );
  out.clear();

  const EXPECTED_2 = "";
  gen_fns.module_wrap = fn (name, alloc) => name == "name" ? {} : { .if_condition = "false" };
  moduleWrap(&out, &state, "hello", gen_fns, &prev, "name");
  assert( out.str_view() == EXPECTED_2 );
  out.clear();

  const EXPECTED_3 = "\nmodule hello @feat(true);\nimport vulkan;\nimport opengl;\n";
  gen_fns.module_wrap = fn (name, alloc) => {
    .if_condition = "true",
    .imports = " vulkan ; opengl ",
  };
  moduleWrap(&out, &state, "hello", gen_fns, &prev, "name");
  assert( out.str_view() == EXPECTED_3 );
  out.clear();

  // Repeating the same wrap must not emit a second module header.
  const EXPECTED_4 = "\nmodule hello;\nimport vulkan;\n";
  gen_fns.module_wrap = fn (name, alloc) => {
    .imports = "vulkan",
  };
  moduleWrap(&out, &state, "hello", gen_fns, &prev, "name");
  moduleWrap(&out, &state, "hello", gen_fns, &prev, "name");
  assert( out.str_view() == EXPECTED_4 );
  out.clear();
}
