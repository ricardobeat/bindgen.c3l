module bgimpl::user_test @test;
import bgimpl::user;
import std::io;

fn void test_system_include_paths_exist()
{
  String[] paths = user::systemIncludePaths(tmem);
  // The platform must offer somewhere to find <stdint.h>; the tool
  // cannot bind any real header otherwise.
  assert( paths.len > 0, "no system include directory found" );
  foreach (p : paths) assert( file::is_dir(p) );
}

fn void test_system_include_paths_find_stdint()
{
  bool found;
  foreach (p : user::systemIncludePaths(tmem)) {
    if (file::exists(string::tformat("%s/stdint.h", p))) { found = true; break; }
  }
  assert( found, "stdint.h not found in any system include directory" );
}
