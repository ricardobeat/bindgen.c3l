<*
 Locates the platform's C headers.

 The frontend carries its own stddef/stdarg/stdbool and friends, but a
 real header will include <stdint.h>, <string.h> and the rest, which
 belong to the platform. These are the directories the OS ships; no
 compiler needs to be installed to read them.
*>
module bgimpl::user;
import bgimpl;
import std::collections::list, std::io, std::os::env;


<*
 Directories to search for platform C headers, most specific first.
 Only directories that exist are returned.
 @return "List of paths, allocated via alloc"
*>
fn String[] systemIncludePaths(Allocator alloc)
{
  List{String} out;
  out.init(alloc, 4);

  // An explicit override always wins.
  if (try String sdk = env::get_var(alloc, "BINDGEN_SYSROOT")) {
    addIfDir(&out, string::format(alloc, "%s/usr/include", sdk));
  }

  $if env::DARWIN:
    // The SDK ships with the OS; its path is stable across versions.
    addIfDir(&out, "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include");
    addIfDir(&out, "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include");
  $endif

  addIfDir(&out, "/usr/local/include");
  $if env::LINUX:
    addIfDir(&out, "/usr/include/x86_64-linux-gnu");
    addIfDir(&out, "/usr/include/aarch64-linux-gnu");
  $endif
  addIfDir(&out, "/usr/include");

  return out.to_array(alloc);
}


<*
 Pushes path onto out when it names an existing directory.
*>
fn void addIfDir(List{String}* out, String path) @local
{
  if (file::is_dir(path)) out.push(path);
}
