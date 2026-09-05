module bgimpl::cparse_test @test;
import bgimpl::cparse;
import std::collections::list, std::io;

fn void test_split_record()
{
  String[] f = cparse::splitRecord(tmem, "field\ta\tint\t0\t-1\t-1");
  assert( f.len == 6 );
  assert( f[0] == "field" );
  assert( f[2] == "int" );
  assert( f[5] == "-1" );
}

fn void test_struct_with_fields()
{
  String dump =
    "struct\tPoint\t8\t4\n"
    "field\tx\tint\t0\t-1\t-1\n"
    "field\ty\tint\t4\t-1\t-1\n"
    "end\n";

  List{cparse::CDecl} d = cparse::parseDump(tmem, dump)!!;
  assert( d.size == 1 );
  assert( d[0].kind == STRUCT );
  assert( d[0].name == "Point" );
  assert( d[0].fields.size == 2 );
  assert( d[0].fields[1].name == "y" );
  assert( d[0].fields[1].offset == 4 );
  assert( d[0].fields[1].bit_width == -1 );
}

fn void test_bitfields()
{
  String dump =
    "struct\tB\t4\t4\n"
    "field\ta\tint\t0\t0\t12\n"
    "field\tb\tint\t0\t12\t12\n"
    "end\n";

  List{cparse::CDecl} d = cparse::parseDump(tmem, dump)!!;
  assert( d[0].fields[0].bit_offset == 0 );
  assert( d[0].fields[0].bit_width == 12 );
  assert( d[0].fields[1].bit_offset == 12 );
}

fn void test_func_with_params()
{
  String dump =
    "func\tadd\tint\t0\n"
    "param\ta\tint\n"
    "param\tb\tint\n"
    "end\n"
    "func\tprintf\tint\t1\n"
    "param\tfmt\tchar*\n"
    "end\n";

  List{cparse::CDecl} d = cparse::parseDump(tmem, dump)!!;
  assert( d.size == 2 );
  assert( d[0].kind == FUNC );
  assert( d[0].type == "int" );
  assert( !d[0].variadic );
  assert( d[0].params.size == 2 );
  assert( d[1].variadic );
}

fn void test_typedef_econst_var()
{
  String dump =
    "typedef\tMyInt\tint\n"
    "econst\tRED\t0\n"
    "econst\tBLUE\t7\n"
    "var\tglobal_x\tunsigned long\n";

  List{cparse::CDecl} d = cparse::parseDump(tmem, dump)!!;
  assert( d.size == 4 );
  assert( d[0].kind == TYPEDEF && d[0].type == "int" );
  assert( d[2].kind == ECONST && d[2].value == 7 );
  assert( d[3].kind == VAR && d[3].type == "unsigned long" );
}

fn void test_macros()
{
  String dump =
    "macro\tMAX\t0\ta\tb\n"
    "mbody\t(\ta\t>\tb\t?\ta\t:\tb\t)\n"
    "macro\tVERSION\t1\n"
    "mbody\t42\n"
    "macro\tEMPTY\t1\n"
    "mbody\n";

  List{cparse::CDecl} d = cparse::parseDump(tmem, dump)!!;
  assert( d.size == 3 );
  assert( !d[0].objlike );
  assert( d[0].params.size == 2 );
  assert( d[0].tokens.size == 9 );
  assert( d[1].objlike && d[1].tokens.size == 1 && d[1].tokens[0] == "42" );
  assert( d[2].tokens.size == 0 );
}

fn void test_malformed()
{
  if (catch cparse::parseDump(tmem, "bogus\tx\n")) return;
  assert(false, "expected MALFORMED_RECORD");
}
