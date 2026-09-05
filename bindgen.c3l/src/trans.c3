
module bgimpl::trans;
import bindgen::bg, bgimpl;
import std::io;


faultdef EMPTY_MACRO_VAL, NAME_IGNORED, NOT_BASIC_TYPE;


<*
 Applies function 'fun' to string 's' and allocate it via 'alloc'.
 @return? trans::NAME_IGNORED
*>
fn String? apply(
  String s, 
  BGTransFn fun, 
  Allocator alloc = mem) 
@inline 
{
  if (s.len == 0) return "";
  if (fun == null) return s.copy(alloc);

  String t = fun(s, alloc);
  if (t == "")
  {
    return trans::NAME_IGNORED~;
  }

  return t;
}










<*
 Converts C integer or floating-point literal epressions to C3 ones
*>
fn String literal(
  Allocator alloc,
  String str)
  => @pool()
{
  // If it's a string or empty literal
  if (str.len == 0 || str[0] == '"') return str;

  bool is_float = @ok(str.index_of_char('.'));
  DString res = dstring::temp(str);

  // --- Prefixes (octal)
  if (str.len >= 2 && str[0] == '0' && str[1].is_odigit()) {
    res.insert_at(1, 'o');
  }

  // --- Suffixes
  res.replace("LL", "L");
  res.replace("ll", "l");
  
  // C3 doesn't have 'L' or 'l' literals for float so substitute them with ""
  if (is_float) {
    res.replace("L", "");
    res.replace("l", "");
  }

  return res.copy_str(alloc);
}


<*
 Maps type String to it's common representation in C3.
 If type is not mappable, throws an error.
 @return? trans::NOT_BASIC_TYPE
*>
fn String? basicType(
  String type)
{
  switch (type) {
    case "void":          return "void";
    case "_Bool":         return "bool";
    case "ptrdiff_t":     return "sz";
    case "size_t":        return "usz";

    case "char":          return "CChar";
    case "short":         return "CShort";
    case "int":           return "CInt";
    case "long":          return "CLong";
    case "long long":     return "CLongLong";

    case "unsigned char":       return "char";
    case "unsigned short":      return "CUShort";
    case "unsigned":            return "CUInt";
    case "unsigned int":        return "CUInt";
    case "unsigned long":       return "CULong";
    case "unsigned long long":  return "CULongLong";
    
    case "signed char":       return "ichar";
    case "signed short":      return "CShort";
    case "signed":            return "CUInt";
    case "signed int":        return "CInt";
    case "signed long":       return "CLong";
    case "signed long long":  return "CLongLong";

    case "int8_t":        return "ichar";
    case "int16_t":       return "short";
    case "int32_t":       return "int";
    case "int64_t":       return "long";
    case "intptr_t":      return "iptr";

    case "uint8_t":       return "char";
    case "uint16_t":      return "ushort";
    case "uint32_t":      return "uint";
    case "uint64_t":      return "ulong";
    case "uintptr_t":     return "uptr";

    case "float":         return "float";
    case "double":        return "double";

    case "va_list":       return "void*";

    default:              return NOT_BASIC_TYPE~;
  }
}

