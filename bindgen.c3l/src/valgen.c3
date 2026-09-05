
module bgimpl::valgen;
import bindgen::bg, std::io,
       bgimpl;


<*
 Applies fun to a name for value generation.
 If function is null, returns the default value
 of return type.
 @require $Typeof(fun) == BGGenFn ||| $Typeof(fun) == BGModuleWrapFn
*>
macro apply(
  Allocator alloc, 
  String name,  
  fun)
{
  var $RetType = $Typefrom($Typeof(fun)::returns);
  if (fun == null) return ($RetType){};

  $RetType res = fun(name, alloc);
  return res;
}


<*
 Gets write attributes for the name. Uses allocator to allocate 
 strings, required by parameterized attributes. 
 See WriteAttrs docs for more info.
*>
fn WriteAttrs getWriteAttrs(
  Allocator alloc,
  String name, 
  BGGenCallbacks gen_fns)
{
  return {
    .if_condition = valgen::apply(alloc, name, gen_fns.if_condition),
  };
}


<*
 Writes a new module section for the name if needed
 to out, based on gen_fns.module_wrap (see BGModuleWrap docs).
 If two names in a row returned the same module wrap, new
 section is not written.
 @param [&inout] prev : "Last module wrap written, updated in place"
 @require module_name != "" : "Module name can't be empty"
*>
fn void moduleWrap(
  OutStream out,
  WriteState* state,
  String module_name,
  BGGenCallbacks gen_fns,
  BGModuleWrap* prev,
  String name)
  => @pool()
{
  BGModuleWrap curr = valgen::apply(tmem, name, gen_fns.module_wrap);

  if (!curr.equals(prev)) {
    WriteAttrs attrs = {
      .if_condition = curr.if_condition,
    };

    wter::moduleHead(out, state, module_name, attrs);

    if (curr.imports != "") {
      String[] imports_arr = curr.imports.tsplit(";", skip_empty: true);
      foreach (imp : imports_arr) {
        wter::importModule(out, state, imp.trim());
      }
    }

    *prev = curr;
  }
}

