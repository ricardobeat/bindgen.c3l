module bgimpl::ctype_test @test;
import bgimpl::ctype, bindgen::bg;
import std::io;

fn void test_builtins()
{
  assert( ctype::translate(tmem, "void", null)!! == "void" );
  assert( ctype::translate(tmem, "int", null)!! == "CInt" );
  assert( ctype::translate(tmem, "unsigned int", null)!! == "CUInt" );
  assert( ctype::translate(tmem, "long", null)!! == "CLong" );
  assert( ctype::translate(tmem, "unsigned long", null)!! == "CULong" );
  assert( ctype::translate(tmem, "double", null)!! == "double" );
  assert( ctype::translate(tmem, "_Bool", null)!! == "bool" );
}

fn void test_pointers()
{
  assert( ctype::translate(tmem, "int*", null)!! == "CInt*" );
  assert( ctype::translate(tmem, "void*", null)!! == "void*" );
  assert( ctype::translate(tmem, "char**", null)!! == "CChar**" );
}

fn void test_arrays()
{
  assert( ctype::translate(tmem, "int[8]", null)!! == "CInt[8]" );
  assert( ctype::translate(tmem, "char[4096]", null)!! == "CChar[4096]" );
  // An unsized array decays to a pointer, as it does in C.
  assert( ctype::translate(tmem, "int[]", null)!! == "CInt*" );
}

fn void test_tagged_records()
{
  assert( ctype::translate(tmem, "struct Foo", null)!! == "Foo" );
  assert( ctype::translate(tmem, "union Bar", null)!! == "Bar" );
  assert( ctype::translate(tmem, "enum Baz", null)!! == "Baz" );
  assert( ctype::translate(tmem, "struct Foo*", null)!! == "Foo*" );
}

fn void test_function_types()
{
  assert( ctype::translate(tmem, "fn(void)()", null)!! == "fn void()" );
  assert( ctype::translate(tmem, "fn(int)(int)", null)!! == "fn CInt(CInt)" );
  assert( ctype::translate(tmem, "fn(int)(int,double)", null)!! ==
          "fn CInt(CInt, double)" );
  // A function pointer is the same thing in C3.
  assert( ctype::translate(tmem, "fn(int)(int,double)*", null)!! ==
          "fn CInt(CInt, double)" );
  assert( ctype::translate(tmem, "fn(void)(void*,int)", null)!! ==
          "fn void(void*, CInt)" );
}

fn void test_nested_function_types()
{
  // A callback taking a callback.
  assert( ctype::translate(tmem, "fn(void)(fn(int)(int)*,void*)", null)!! ==
          "fn void(fn CInt(CInt), void*)" );
}

fn void test_variadic_param()
{
  assert( ctype::translate(tmem, "fn(int)(char*,...)", null)!! ==
          "fn CInt(CChar*, ...)" );
}

fn void test_type_callback_applied()
{
  BGTransFn up = fn String(String s, Allocator a) => s.to_upper_copy(a);
  assert( ctype::translate(tmem, "struct foo", up)!! == "FOO" );
  assert( ctype::translate(tmem, "my_typedef", up)!! == "MY_TYPEDEF" );
  // Builtins are not routed through the callback.
  assert( ctype::translate(tmem, "int", up)!! == "CInt" );
}

fn void test_ignored_type_propagates()
{
  BGTransFn ignore = fn String(String s, Allocator a) => "";
  if (catch ctype::translate(tmem, "struct secret", ignore)) return;
  assert(false, "expected NAME_IGNORED");
}
