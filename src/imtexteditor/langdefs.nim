import std/[strutils, re]

import utils

proc peek(input: string, index: int): char = 
  if index < input.len:
    result = input[index]

proc tokenizeCStyleString(input: string, start: int): int = 
  result = start
  if input.peek(result) == '"':
    inc result

    for c in input[result..^1]:
      if c == '"' and input.peek(result - 1) != '\\':
        inc result
        break

      inc result

  else:
    result = -1

proc tokenizeCStyleCharacterLiteral(input: string, start: int): int = 
  result = start

  if input.peek(result) == '\'':
    inc result

    # Handle escape characters
    if input.peek(result) == '\\':
      inc result

    if result < input.len:
      inc result

    # Handle end of character literal
    if input.peek(result) != '\'':
      result = -1
  else:
    result = -1

proc tokenizeCStyleIdentifier(input: string, start: int): int = 
  result = start

  if input.peek(result) in IdentStartChars:
    inc result

    while input.peek(result) in IdentChars:
      inc result
  else:
    return -1

proc tokenizeCStyleNumber(input: string, start: int): int = 
  result = start

  let startsWithNumber = input.peek(result) in Digits

  if input.peek(result) notin {'+', '-'} and not startsWithNumber:
    return -1

  inc result

  var hasNumber = startsWithNumber

  while input.peek(result) in Digits:
    hasNumber = true

    inc result

  if not hasNumber:
    return -1

  var isFloat, isHex, isBinary = false

  case input.peek(result)
  of '.':
    isFloat = true

    inc result

    while input.peek(result) in Digits:
      inc result
  of 'x', 'X': # Hex formatted integer of the type 0xef80
    isHex = true

    inc result

    while input.peek(result) in HexDigits:
      inc result
  of 'b', 'B': # Binary formatted integer of the type 0b01011101
    isBinary = true

    inc result

    while input.peek(result) in {'0', '1'}:
      inc result
  else: discard

  if not isHex and not isBinary:
    # Floating point exponent
    if input.peek(result) in {'e', 'E'}:
      isFloat = true

      inc result

      if input.peek(result) in {'+', '-'}:
        inc result

      var hasDigits = false

      while input.peek(result) in Digits:
        hasDigits = true
        inc result

      if not hasDigits:
        return -1

    # Single precision floating point type
    if input.peek(result) == 'f':
      inc result

  if not isFloat:
    # Integer size type
    while input.peek(result) in {'u', 'U', 'l', 'L'}:
      inc result

proc tokenizeCStylePunctuation(input: string, start: int): int = 
  result = start

  case input.peek(result):
  of '[', ']', '{', '}', '!', '%', '^', '&', '*', '(', ')', '-', '+', '=', '~', '|', '<', '>', '?', ':', '/', ';', ',', '.':
    inc result
  else:
    result = -1

proc langDefCpp*(): LanguageDef = 
  result.name = "C++"

  result.commentStart = "/*"
  result.commentEnd = "*/"

  result.singleLineComment = "//"

  result.caseSensitive = true
  result.autoIndentation = true

  result.keywords = @[
    "alignas", "alignof", "and", "and_eq", "asm", "atomic_cancel", "atomic_commit", "atomic_noexcept", "auto", "bitand", "bitor", "bool", "break", "case", "catch", "char", "char16_t", "char32_t", "class",
    "compl", "concept", "const", "constexpr", "const_cast", "continue", "decltype", "default", "delete", "do", "double", "dynamic_cast", "else", "enum", "explicit", "export", "extern", "false", "float",
    "for", "friend", "goto", "if", "import", "inline", "int", "long", "module", "mutable", "namespace", "new", "noexcept", "not", "not_eq", "nullptr", "operator", "or", "or_eq", "private", "protected", "public",
    "register", "reinterpret_cast", "requires", "return", "short", "signed", "sizeof", "static", "static_assert", "static_cast", "struct", "switch", "synchronized", "template", "this", "thread_local",
    "throw", "true", "try", "typedef", "typeid", "typename", "union", "unsigned", "using", "virtual", "void", "volatile", "wchar_t", "while", "xor", "xor_eq"
  ]
  
  const identifiers = [
    "abort", "abs", "acos", "asin", "atan", "atexit", "atof", "atoi", "atol", "ceil", "clock", "cosh", "ctime", "div", "exit", "fabs", "floor", "fmod", "getchar", "getenv", "isalnum", "isalpha", "isdigit", "isgraph",
    "ispunct", "isspace", "isupper", "kbhit", "log10", "log2", "log", "memcmp", "modf", "pow", "printf", "sprintf", "snprintf", "putchar", "putenv", "puts", "rand", "remove", "rename", "sinh", "sqrt", "srand", "strcat", "strcmp", "strerror", "time", "tolower", "toupper",
    "std", "string", "vector", "map", "unordered_map", "set", "unordered_set", "min", "max"
  ]

  for iden in identifiers:
    result.identifiers.add((iden, Identifier(declaration: "Built-in function")))  

  result.tokenize = proc(input: string, start: int): tuple[ok: bool, token: Slice[int], col: PaletteIndex] = 
    if start > input.high:
      return

    result.token = start..start
    while input.peek(result.token.b) in Whitespace:
      inc result.token.b

    if result.token.b == input.len:
      dec result.token.b # Because slices are inclusive
      result.col = PaletteIndex.Default
      result.ok = true

    elif (let index = input.tokenizeCStyleString(result.token.b); index >= 0):
      echo index
      result.col = PaletteIndex.String
      result.token = result.token.b..<index
      result.ok = true

    elif (let index = input.tokenizeCStyleCharacterLiteral(result.token.b); index >= 0):
      result.col = PaletteIndex.CharLiteral
      result.token = result.token.b..<index
      result.ok = true

    elif (let index = input.tokenizeCStyleIdentifier(result.token.b); index >= 0):
      result.col = PaletteIndex.Identifier
      result.token = result.token.b..<index
      result.ok = true

    elif (let index = input.tokenizeCStyleNumber(result.token.b); index >= 0):
      result.col = PaletteIndex.Number
      result.token = result.token.b..<index
      result.ok = true

    elif (let index = input.tokenizeCStylePunctuation(result.token.b); index >= 0):
      result.col = PaletteIndex.Punctuation
      result.token = result.token.b..<index
      result.ok = true

proc langDefHLSL*(): LanguageDef = 
  result.name = "HLSL"

  result.commentStart = "/*"
  result.commentEnd = "*/"
  result.singleLineComment = "#"

  result.caseSensitive = true
  result.autoIndentation = true

  result.keywords = @[
    "AppendStructuredBuffer", "asm", "asm_fragment", "BlendState", "bool", "break", "Buffer", "ByteAddressBuffer", "case", "cbuffer", "centroid", "class", "column_major", "compile", "compile_fragment",
    "CompileShader", "const", "continue", "ComputeShader", "ConsumeStructuredBuffer", "default", "DepthStencilState", "DepthStencilView", "discard", "do", "double", "DomainShader", "dword", "else",
    "export", "extern", "false", "float", "for", "fxgroup", "GeometryShader", "groupshared", "half", "Hullshader", "if", "in", "inline", "inout", "InputPatch", "int", "interface", "line", "lineadj",
    "linear", "LineStream", "matrix", "min16float", "min10float", "min16int", "min12int", "min16uint", "namespace", "nointerpolation", "noperspective", "NULL", "out", "OutputPatch", "packoffset",
    "pass", "pixelfragment", "PixelShader", "point", "PointStream", "precise", "RasterizerState", "RenderTargetView", "return", "register", "row_major", "RWBuffer", "RWByteAddressBuffer", "RWStructuredBuffer",
    "RWTexture1D", "RWTexture1DArray", "RWTexture2D", "RWTexture2DArray", "RWTexture3D", "sample", "sampler", "SamplerState", "SamplerComparisonState", "shared", "snorm", "stateblock", "stateblock_state",
    "static", "string", "struct", "switch", "StructuredBuffer", "tbuffer", "technique", "technique10", "technique11", "texture", "Texture1D", "Texture1DArray", "Texture2D", "Texture2DArray", "Texture2DMS",
    "Texture2DMSArray", "Texture3D", "TextureCube", "TextureCubeArray", "true", "typedef", "triangle", "triangleadj", "TriangleStream", "uint", "uniform", "unorm", "unsigned", "vector", "vertexfragment",
    "VertexShader", "void", "volatile", "while",
    "bool1","bool2","bool3","bool4","double1","double2","double3","double4", "float1", "float2", "float3", "float4", "int1", "int2", "int3", "int4", "in", "out", "inout",
    "uint1", "uint2", "uint3", "uint4", "dword1", "dword2", "dword3", "dword4", "half1", "half2", "half3", "half4",
    "float1x1","float2x1","float3x1","float4x1","float1x2","float2x2","float3x2","float4x2",
    "float1x3","float2x3","float3x3","float4x3","float1x4","float2x4","float3x4","float4x4",
    "half1x1","half2x1","half3x1","half4x1","half1x2","half2x2","half3x2","half4x2",
    "half1x3","half2x3","half3x3","half4x3","half1x4","half2x4","half3x4","half4x4",
  ]

  const identifiers = [
    "abort", "abs", "acos", "all", "AllMemoryBarrier", "AllMemoryBarrierWithGroupSync", "any", "asdouble", "asfloat", "asin", "asint", "asint", "asuint",
    "asuint", "atan", "atan2", "ceil", "CheckAccessFullyMapped", "clamp", "clip", "cos", "cosh", "countbits", "cross", "D3DCOLORtoUBYTE4", "ddx",
    "ddx_coarse", "ddx_fine", "ddy", "ddy_coarse", "ddy_fine", "degrees", "determinant", "DeviceMemoryBarrier", "DeviceMemoryBarrierWithGroupSync",
    "distance", "dot", "dst", "errorf", "EvaluateAttributeAtCentroid", "EvaluateAttributeAtSample", "EvaluateAttributeSnapped", "exp", "exp2",
    "f16tof32", "f32tof16", "faceforward", "firstbithigh", "firstbitlow", "floor", "fma", "fmod", "frac", "frexp", "fwidth", "GetRenderTargetSampleCount",
    "GetRenderTargetSamplePosition", "GroupMemoryBarrier", "GroupMemoryBarrierWithGroupSync", "InterlockedAdd", "InterlockedAnd", "InterlockedCompareExchange",
    "InterlockedCompareStore", "InterlockedExchange", "InterlockedMax", "InterlockedMin", "InterlockedOr", "InterlockedXor", "isfinite", "isinf", "isnan",
    "ldexp", "length", "lerp", "lit", "log", "log10", "log2", "mad", "max", "min", "modf", "msad4", "mul", "noise", "normalize", "pow", "printf",
    "Process2DQuadTessFactorsAvg", "Process2DQuadTessFactorsMax", "Process2DQuadTessFactorsMin", "ProcessIsolineTessFactors", "ProcessQuadTessFactorsAvg",
    "ProcessQuadTessFactorsMax", "ProcessQuadTessFactorsMin", "ProcessTriTessFactorsAvg", "ProcessTriTessFactorsMax", "ProcessTriTessFactorsMin",
    "radians", "rcp", "reflect", "refract", "reversebits", "round", "rsqrt", "saturate", "sign", "sin", "sincos", "sinh", "smoothstep", "sqrt", "step",
    "tan", "tanh", "tex1D", "tex1D", "tex1Dbias", "tex1Dgrad", "tex1Dlod", "tex1Dproj", "tex2D", "tex2D", "tex2Dbias", "tex2Dgrad", "tex2Dlod", "tex2Dproj",
    "tex3D", "tex3D", "tex3Dbias", "tex3Dgrad", "tex3Dlod", "tex3Dproj", "texCUBE", "texCUBE", "texCUBEbias", "texCUBEgrad", "texCUBElod", "texCUBEproj", "transpose", "trunc"
  ]

  for iden in identifiers:
    result.identifiers.add((iden, Identifier(declaration: "Built-in function")))  

  result.regexList = @[
    ("[ \\t]*#[ \\t]*[a-zA-Z_]+".re(), PaletteIndex.Preprocessor), 
    ("L?\\\"(\\\\.|[^\\\"])*\\\"".re(), PaletteIndex.String), 
    ("\\'\\\\?[^\\']\\'".re(), PaletteIndex.CharLiteral), 
    ("[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?[fF]?".re(), PaletteIndex.Number), 
    ("[+-]?[0-9]+[Uu]?[lL]?[lL]?".re(), PaletteIndex.Number), 
    ("0[0-7]+[Uu]?[lL]?[lL]?".re(), PaletteIndex.Number), 
    ("0[xX][0-9a-fA-F]+[uU]?[lL]?[lL]?".re(), PaletteIndex.Number), 
    ("[a-zA-Z_][a-zA-Z0-9_]*".re(), PaletteIndex.Identifier), 
    ("[\\[\\]\\\\\\!\\%\\^\\&\\*\\(\\)\\-\\+\\=\\~\\|\\<\\>\\?\\/\\\\,\\.]".re(), PaletteIndex.Punctuation), 
  ]

proc langDefGLSL*(): LanguageDef = 
  result.name = "GLSL"

  result.commentStart = "/*"
  result.commentEnd = "*/"
  result.singleLineComment = "#"

  result.caseSensitive = true
  result.autoIndentation = true

  result.keywords = @[
    "auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else", "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long", "register", "restrict", "return", "short",
    "signed", "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned", "void", "volatile", "while", "_Alignas", "_Alignof", "_Atomic", "_Bool", "_Complex", "_Generic", "_Imaginary",
    "_Noreturn", "_Static_assert", "_Thread_local"
  ]

  const identifiers = [
    "abort", "abs", "acos", "asin", "atan", "atexit", "atof", "atoi", "atol", "ceil", "clock", "cosh", "ctime", "div", "exit", "fabs", "floor", "fmod", "getchar", "getenv", "isalnum", "isalpha", "isdigit", "isgraph",
    "ispunct", "isspace", "isupper", "kbhit", "log10", "log2", "log", "memcmp", "modf", "pow", "putchar", "putenv", "puts", "rand", "remove", "rename", "sinh", "sqrt", "srand", "strcat", "strcmp", "strerror", "time", "tolower", "toupper"
  ]

  for iden in identifiers:
    result.identifiers.add((iden, Identifier(declaration: "Built-in function")))  

  result.regexList = @[
    ("[ \\t]*#[ \\t]*[a-zA-Z_]+".re(), PaletteIndex.Preprocessor), 
    ("L?\\\"(\\\\.|[^\\\"])*\\\"".re(), PaletteIndex.String), 
    ("\\'\\\\?[^\\']\\'".re(), PaletteIndex.CharLiteral), 
    ("[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?[fF]?".re(), PaletteIndex.Number), 
    ("[+-]?[0-9]+[Uu]?[lL]?[lL]?".re(), PaletteIndex.Number), 
    ("0[0-7]+[Uu]?[lL]?[lL]?".re(), PaletteIndex.Number), 
    ("0[xX][0-9a-fA-F]+[uU]?[lL]?[lL]?".re(), PaletteIndex.Number), 
    ("[a-zA-Z_][a-zA-Z0-9_]*".re(), PaletteIndex.Identifier), 
    ("[\\[\\]\\\\\\!\\%\\^\\&\\*\\(\\)\\-\\+\\=\\~\\|\\<\\>\\?\\/\\\\,\\.]".re(), PaletteIndex.Punctuation), 
  ]

proc langDefC*(): LanguageDef = 
  result.name = "C"

  result.commentStart = "/*"
  result.commentEnd = "*/"
  result.singleLineComment = "//"

  result.caseSensitive = true
  result.autoIndentation = true

  result.keywords = @[
    "auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else", "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long", "register", "restrict", "return", "short",
    "signed", "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned", "void", "volatile", "while", "_Alignas", "_Alignof", "_Atomic", "_Bool", "_Complex", "_Generic", "_Imaginary",
    "_Noreturn", "_Static_assert", "_Thread_local"
  ]

  const identifiers = [
    "abort", "abs", "acos", "asin", "atan", "atexit", "atof", "atoi", "atol", "ceil", "clock", "cosh", "ctime", "div", "exit", "fabs", "floor", "fmod", "getchar", "getenv", "isalnum", "isalpha", "isdigit", "isgraph",
    "ispunct", "isspace", "isupper", "kbhit", "log10", "log2", "log", "memcmp", "modf", "pow", "putchar", "putenv", "puts", "rand", "remove", "rename", "sinh", "sqrt", "srand", "strcat", "strcmp", "strerror", "time", "tolower", "toupper"
  ]

  for iden in identifiers:
    result.identifiers.add((iden, Identifier(declaration: "Built-in function")))
  
  result.tokenize = proc(input: string, start: int): tuple[ok: bool, token: Slice[int], col: PaletteIndex] = 
    if start > input.high:
      return

    result.token = start..start
    while input.peek(result.token.b) in Whitespace:
      inc result.token.b

    if result.token.b == input.len:
      dec result.token.b # Because slices are inclusive
      result.col = PaletteIndex.Default
      result.ok = true

    elif (let index = input.tokenizeCStyleString(result.token.b); index >= 0):
      echo index
      result.col = PaletteIndex.String
      result.token = result.token.b..<index
      result.ok = true

    elif (let index = input.tokenizeCStyleCharacterLiteral(result.token.b); index >= 0):
      result.col = PaletteIndex.CharLiteral
      result.token = result.token.b..<index
      result.ok = true

    elif (let index = input.tokenizeCStyleIdentifier(result.token.b); index >= 0):
      result.col = PaletteIndex.Identifier
      result.token = result.token.b..<index
      result.ok = true

    elif (let index = input.tokenizeCStyleNumber(result.token.b); index >= 0):
      result.col = PaletteIndex.Number
      result.token = result.token.b..<index
      result.ok = true

    elif (let index = input.tokenizeCStylePunctuation(result.token.b); index >= 0):
      result.col = PaletteIndex.Punctuation
      result.token = result.token.b..<index
      result.ok = true

proc langDefSQL*(): LanguageDef = 
  result.name = "SQL"

  result.commentStart = "/*"
  result.commentEnd = "*/"
  result.singleLineComment = "#"

  result.caseSensitive = false
  result.autoIndentation = false

  result.keywords = @[
    "ADD", "EXCEPT", "PERCENT", "ALL", "EXEC", "PLAN", "ALTER", "EXECUTE", "PRECISION", "AND", "EXISTS", "PRIMARY", "ANY", "EXIT", "PRINT", "AS", "FETCH", "PROC", "ASC", "FILE", "PROCEDURE",
    "AUTHORIZATION", "FILLFACTOR", "PUBLIC", "BACKUP", "FOR", "RAISERROR", "BEGIN", "FOREIGN", "READ", "BETWEEN", "FREETEXT", "READTEXT", "BREAK", "FREETEXTTABLE", "RECONFIGURE",
    "BROWSE", "FROM", "REFERENCES", "BULK", "FULL", "REPLICATION", "BY", "FUNCTION", "RESTORE", "CASCADE", "GOTO", "RESTRICT", "CASE", "GRANT", "RETURN", "CHECK", "GROUP", "REVOKE",
    "CHECKPOINT", "HAVING", "RIGHT", "CLOSE", "HOLDLOCK", "ROLLBACK", "CLUSTERED", "IDENTITY", "ROWCOUNT", "COALESCE", "IDENTITY_INSERT", "ROWGUIDCOL", "COLLATE", "IDENTITYCOL", "RULE",
    "COLUMN", "IF", "SAVE", "COMMIT", "IN", "SCHEMA", "COMPUTE", "INDEX", "SELECT", "CONSTRAINT", "INNER", "SESSION_USER", "CONTAINS", "INSERT", "SET", "CONTAINSTABLE", "INTERSECT", "SETUSER",
    "CONTINUE", "INTO", "SHUTDOWN", "CONVERT", "IS", "SOME", "CREATE", "JOIN", "STATISTICS", "CROSS", "KEY", "SYSTEM_USER", "CURRENT", "KILL", "TABLE", "CURRENT_DATE", "LEFT", "TEXTSIZE",
    "CURRENT_TIME", "LIKE", "THEN", "CURRENT_TIMESTAMP", "LINENO", "TO", "CURRENT_USER", "LOAD", "TOP", "CURSOR", "NATIONAL", "TRAN", "DATABASE", "NOCHECK", "TRANSACTION",
    "DBCC", "NONCLUSTERED", "TRIGGER", "DEALLOCATE", "NOT", "TRUNCATE", "DECLARE", "NULL", "TSEQUAL", "DEFAULT", "NULLIF", "UNION", "DELETE", "OF", "UNIQUE", "DENY", "OFF", "UPDATE",
    "DESC", "OFFSETS", "UPDATETEXT", "DISK", "ON", "USE", "DISTINCT", "OPEN", "USER", "DISTRIBUTED", "OPENDATASOURCE", "VALUES", "DOUBLE", "OPENQUERY", "VARYING","DROP", "OPENROWSET", "VIEW",
    "DUMMY", "OPENXML", "WAITFOR", "DUMP", "OPTION", "WHEN", "ELSE", "OR", "WHERE", "END", "ORDER", "WHILE", "ERRLVL", "OUTER", "WITH", "ESCAPE", "OVER", "WRITETEXT"
  ]

  const identifiers = [
    "ABS",  "ACOS",  "ADD_MONTHS",  "ASCII",  "ASCIISTR",  "ASIN",  "ATAN",  "ATAN2",  "AVG",  "BFILENAME",  "BIN_TO_NUM",  "BITAND",  "CARDINALITY",  "CASE",  "CAST",  "CEIL",
    "CHARTOROWID",  "CHR",  "COALESCE",  "COMPOSE",  "CONCAT",  "CONVERT",  "CORR",  "COS",  "COSH",  "COUNT",  "COVAR_POP",  "COVAR_SAMP",  "CUME_DIST",  "CURRENT_DATE",
    "CURRENT_TIMESTAMP",  "DBTIMEZONE",  "DECODE",  "DECOMPOSE",  "DENSE_RANK",  "DUMP",  "EMPTY_BLOB",  "EMPTY_CLOB",  "EXP",  "EXTRACT",  "FIRST_VALUE",  "FLOOR",  "FROM_TZ",  "GREATEST",
    "GROUP_ID",  "HEXTORAW",  "INITCAP",  "INSTR",  "INSTR2",  "INSTR4",  "INSTRB",  "INSTRC",  "LAG",  "LAST_DAY",  "LAST_VALUE",  "LEAD",  "LEAST",  "LENGTH",  "LENGTH2",  "LENGTH4",
    "LENGTHB",  "LENGTHC",  "LISTAGG",  "LN",  "LNNVL",  "LOCALTIMESTAMP",  "LOG",  "LOWER",  "LPAD",  "LTRIM",  "MAX",  "MEDIAN",  "MIN",  "MOD",  "MONTHS_BETWEEN",  "NANVL",  "NCHR",
    "NEW_TIME",  "NEXT_DAY",  "NTH_VALUE",  "NULLIF",  "NUMTODSINTERVAL",  "NUMTOYMINTERVAL",  "NVL",  "NVL2",  "POWER",  "RANK",  "RAWTOHEX",  "REGEXP_COUNT",  "REGEXP_INSTR",
    "REGEXP_REPLACE",  "REGEXP_SUBSTR",  "REMAINDER",  "REPLACE",  "ROUND",  "ROWNUM",  "RPAD",  "RTRIM",  "SESSIONTIMEZONE",  "SIGN",  "SIN",  "SINH",
    "SOUNDEX",  "SQRT",  "STDDEV",  "SUBSTR",  "SUM",  "SYS_CONTEXT",  "SYSDATE",  "SYSTIMESTAMP",  "TAN",  "TANH",  "TO_CHAR",  "TO_CLOB",  "TO_DATE",  "TO_DSINTERVAL",  "TO_LOB",
    "TO_MULTI_BYTE",  "TO_NCLOB",  "TO_NUMBER",  "TO_SINGLE_BYTE",  "TO_TIMESTAMP",  "TO_TIMESTAMP_TZ",  "TO_YMINTERVAL",  "TRANSLATE",  "TRIM",  "TRUNC", "TZ_OFFSET",  "UID",  "UPPER",
    "USER",  "USERENV",  "VAR_POP",  "VAR_SAMP",  "VARIANCE",  "VSIZE "
  ]

  for iden in identifiers:
    result.identifiers.add((iden, Identifier(declaration: "Built-in function")))

  result.regexList = @[
    ("L?\\\"(\\\\.|[^\\\"])*\\\"".re(), PaletteIndex.String), 
    ("\\\'[^\\\']*\\\'".re(), PaletteIndex.String), 
    ("[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?[fF]?".re(), PaletteIndex.Number), 
    ("[+-]?[0-9]+[Uu]?[lL]?[lL]?".re(), PaletteIndex.Number), 
    ("0[0-7]+[Uu]?[lL]?[lL]?".re(), PaletteIndex.Number), 
    ("0[xX][0-9a-fA-F]+[uU]?[lL]?[lL]?".re(), PaletteIndex.Number), 
    ("[a-zA-Z_][a-zA-Z0-9_]*".re(), PaletteIndex.Identifier), 
    ("[\\[\\]\\\\\\!\\%\\^\\&\\*\\(\\)\\-\\+\\=\\~\\|\\<\\>\\?\\/\\\\,\\.]".re(), PaletteIndex.Punctuation), 
  ]

proc langDefAngelScript*(): LanguageDef = 
  result.name = "AngelScript"

  result.commentStart = "/*"
  result.commentEnd = "*/"
  result.singleLineComment = "#"

  result.caseSensitive = true
  result.autoIndentation = true

  result.keywords = @[
    "and", "abstract", "auto", "bool", "break", "case", "cast", "class", "const", "continue", "default", "do", "double", "else", "enum", "false", "final", "float", "for",
    "from", "funcdef", "function", "get", "if", "import", "in", "inout", "int", "interface", "int8", "int16", "int32", "int64", "is", "mixin", "namespace", "not",
    "null", "or", "out", "override", "private", "protected", "return", "set", "shared", "super", "switch", "this ", "true", "typedef", "uint", "uint8", "uint16", "uint32",
    "uint64", "void", "while", "xor"
  ]

  const identifiers = [
    "cos", "sin", "tab", "acos", "asin", "atan", "atan2", "cosh", "sinh", "tanh", "log", "log10", "pow", "sqrt", "abs", "ceil", "floor", "fraction", "closeTo", "fpFromIEEE", "fpToIEEE",
    "complex", "opEquals", "opAddAssign", "opSubAssign", "opMulAssign", "opDivAssign", "opAdd", "opSub", "opMul", "opDiv"
  ]

  for iden in identifiers:
    result.identifiers.add((iden, Identifier(declaration: "Built-in function")))

  result.regexList = @[
    ("L?\\\"(\\\\.|[^\\\"])*\\\"".re(), PaletteIndex.String), 
    ("\\'\\\\?[^\\']\\'".re(), PaletteIndex.String), 
    ("[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?[fF]?".re(), PaletteIndex.Number), 
    ("[+-]?[0-9]+[Uu]?[lL]?[lL]?".re(), PaletteIndex.Number), 
    ("0[0-7]+[Uu]?[lL]?[lL]?".re(), PaletteIndex.Number), 
    ("0[xX][0-9a-fA-F]+[uU]?[lL]?[lL]?".re(), PaletteIndex.Number), 
    ("[a-zA-Z_][a-zA-Z0-9_]*".re(), PaletteIndex.Identifier), 
    ("[\\[\\]\\\\\\!\\%\\^\\&\\*\\(\\)\\-\\+\\=\\~\\|\\<\\>\\?\\/\\\\,\\.]".re(), PaletteIndex.Punctuation), 
  ]

proc langDefLua*(): LanguageDef = 
  result.name = "Lua"

  result.commentStart = "--[["
  result.commentEnd = "]]"
  result.singleLineComment = "--"

  result.caseSensitive = true
  result.autoIndentation = false

  result.keywords = @[
    "and", "break", "do", "", "else", "elseif", "end", "false", "for", "function", "if", "in", "", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"
  ]


  const identifiers = [
    "assert", "collectgarbage", "dofile", "error", "getmetatable", "ipairs", "loadfile", "load", "loadstring",  "next",  "pairs",  "pcall",  "print",  "rawequal",  "rawlen",  "rawget",  "rawset",
    "select",  "setmetatable",  "tonumber",  "tostring",  "type",  "xpcall",  "_G",  "_VERSION","arshift", "band", "bnot", "bor", "bxor", "btest", "extract", "lrotate", "lshift", "replace",
    "rrotate", "rshift", "create", "resume", "running", "status", "wrap", "yield", "isyieldable", "debug","getuservalue", "gethook", "getinfo", "getlocal", "getregistry", "getmetatable",
    "getupvalue", "upvaluejoin", "upvalueid", "setuservalue", "sethook", "setlocal", "setmetatable", "setupvalue", "traceback", "close", "flush", "input", "lines", "open", "output", "popen",
    "read", "tmpfile", "type", "write", "close", "flush", "lines", "read", "seek", "setvbuf", "write", "__gc", "__tostring", "abs", "acos", "asin", "atan", "ceil", "cos", "deg", "exp", "tointeger",
    "floor", "fmod", "ult", "log", "max", "min", "modf", "rad", "random", "randomseed", "sin", "sqrt", "string", "tan", "type", "atan2", "cosh", "sinh", "tanh",
    "pow", "frexp", "ldexp", "log10", "pi", "huge", "maxinteger", "mininteger", "loadlib", "searchpath", "seeall", "preload", "cpath", "path", "searchers", "loaded", "module", "require", "clock",
    "date", "difftime", "execute", "exit", "getenv", "remove", "rename", "setlocale", "time", "tmpname", "byte", "char", "dump", "find", "format", "gmatch", "gsub", "len", "lower", "match", "rep",
    "reverse", "sub", "upper", "pack", "packsize", "unpack", "concat", "maxn", "insert", "pack", "unpack", "remove", "move", "sort", "offset", "codepoint", "char", "len", "codes", "charpattern",
    "coroutine", "table", "io", "os", "string", "utf8", "bit32", "math", "debug", "package"
  ]

  for iden in identifiers:
    result.identifiers.add((iden, Identifier(declaration: "Built-in function")))

  result.regexList = @[
    ("L?\\\"(\\\\.|[^\\\"])*\\\"".re(), PaletteIndex.String), 
    ("\\\'[^\\\']*\\\'".re(), PaletteIndex.String), 
    ("0[xX][0-9a-fA-F]+[uU]?[lL]?[lL]?".re(), PaletteIndex.Number), 
    ("[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?[fF]?".re(), PaletteIndex.Number), 
    ("[+-]?[0-9]+[Uu]?[lL]?[lL]?".re(), PaletteIndex.Number), 
    ("[a-zA-Z_][a-zA-Z0-9_]*".re(), PaletteIndex.Identifier), 
    ("[\\[\\]\\\\\\!\\%\\^\\&\\*\\(\\)\\-\\+\\=\\~\\|\\<\\>\\?\\/\\\\,\\.]".re(), PaletteIndex.Punctuation), 
  ]

# let buffer = "print(\"Hello World!\")"

# for (pattern, col) in langDefLua().regexList:
  # let (first, last) = buffer.findBounds(pattern)
  # if first >= 0:
    # echo col, " at ", first, "..", last, ": ", buffer[first..last]
    # break
