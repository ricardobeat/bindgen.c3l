module rt;
import bgimpl::cparse;
import std::collections::list, std::io;

fn int main(String[] args) {
  String dump = (String)file::load_temp(args[1])!!;
  List{cparse::CDecl} d = cparse::parseDump(tmem, dump)!!;
  int[8] counts;
  foreach (x : d) counts[x.kind.ordinal]++;
  io::printfn("decls=%d typedef=%d struct=%d union=%d enum=%d econst=%d func=%d var=%d macro=%d",
    d.size, counts[0], counts[1], counts[2], counts[3], counts[4], counts[5], counts[6], counts[7]);
  return 0;
}
