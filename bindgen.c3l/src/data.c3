<*
 All data types are defined here
*>
module bgimpl;
import bindgen::bg,
       std::io, 
       std::collections::map, 
       std::collections::list;


<*
 NORMAL - regular field
 BIT - bit field
 STRUCT - inlined struct
 UNION - inlined union
 ENUM - inlined enum
*>
enum CFieldKind : char
{
  NORMAL,
  BIT,
  STRUCT,
  UNION,
  ENUM,
}


<*
 NORMAL - regular field
 BITSTRUCT - inlined bitstruct
 STRUCT - inlined struct
 UNION - inlined union
*>
enum C3FieldKind : char
{
  NORMAL,
  BITSTRUCT,
  STRUCT,
  UNION
}


<*
 NAME - 'struct' or 'MyType'
 POINTER - *
 SIZED_ARRAY - [10]
 UNSIZED_ARRAY  - []
*>
enum CTypeTokenKind : char
{
  NAME,
  POINTER,
  SIZED_ARRAY,  
  UNSIZED_ARRAY,
}


<*
 Represents the C3 declaration kind,
 written to out file
*>
enum WriteKind
{
  ALIAS, TYPEDEF,
  FUNC, CONST, 
  UNION, ENUM,
  MACRO, MODULE,
  IMPORT, STRUCT,
  VAR, BITSTRUCT,
}


<*
 Represents attributes for C3 declarations
 has_arg - whether an attr
*>
enum WriteAttrKind : char (String str, bool has_arg)
{
  PRIVATE { "@private", false },
  FEAT    { "@feat",    true },
}




<*
 Represents variable declaration meaning:
 <type> <name>;
*>
struct VarDecl
{
  String type;
  String name;
}


<*
 Represents bit fields meaning:
 <type> <name> : <width>;
*>
struct CBitField
{
  String  type;
  String  name;
  usz     width;
}


<*
 Represents anonymous structure meaning:

 name : "Optional, can be zero string"
*>
struct CInlinedRecord
{
  String  name;
  CFields fields;
}


<* 
 kinds.len == sum of *.len 
*>
struct CFields
{
  List{CFieldKind}      kinds;
  List{VarDecl}         norm;
  List{CBitField}       bit;
  List{CInlinedRecord}  structs;
  List{CInlinedRecord}  unions;
}


<*
 name : "Optional, can be zero string"
*>
struct C3InlinedRecord
{
  C3Fields  fields;
  String    name;
}


<*
 under_type : "Underlying type of a bitstruct (bitstruct : under_type { ... })"
*>
struct C3InlinedBitstruct
{
  List{C3BitstructField}  fields;
  String                  under_type;
}


<*
 from : "Number of starting bit"
 to : "Number of ending bit"
*>
struct C3BitstructField
{
  String  type;
  String  name;
  usz     from;
  usz     to;
}


<* 
  kinds.len == sum of *.len 
*>
struct C3Fields
{
  List{C3FieldKind}         kinds;
  List{VarDecl}             norm;
  List{C3InlinedBitstruct}  bit;
  List{C3InlinedRecord}     structs;
  List{C3InlinedRecord}     unions;
}


<*
 strs : "Strings, which are unknown at compile time"
*>
struct CTypeTokens
{
  List{CTypeTokenKind} kinds;
  List{String}         strs;
}















<*
 Writing state, passed to the writers
*>
struct WriteState
{
  WriteKind kind;
}


<*
 Write attributes represent additional attributes
 for any declaration. There are two types of attributes:
 - String: an attribute has an argument. The attribute is
           enabled if it's value is not equal to ""
 - bool:   an attribute doesn't have value and is enabled
           if the bool is true.
*>
struct WriteAttrs (Printable)
{
  String if_condition @tag("attr", "@feat");
  bool   private      @tag("attr", "@private");
}

