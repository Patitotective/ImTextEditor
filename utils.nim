import std/[monotimes, strutils, unicode, times]
import nimgl/imgui

proc `+`*(vec1, vec2: ImVec2): ImVec2 = 
  ImVec2(x: vec1.x + vec2.x, y: vec1.y + vec2.y)

proc `-`*(vec1, vec2: ImVec2): ImVec2 = 
  ImVec2(x: vec1.x - vec2.x, y: vec1.y - vec2.y)

proc `*`*(vec1, vec2: ImVec2): ImVec2 = 
  ImVec2(x: vec1.x * vec2.x, y: vec1.y * vec2.y)

proc `/`*(vec1, vec2: ImVec2): ImVec2 = 
  ImVec2(x: vec1.x / vec2.x, y: vec1.y / vec2.y)

proc `+`*(vec: ImVec2, val: float32): ImVec2 = 
  ImVec2(x: vec.x + val, y: vec.y + val)

proc `-`*(vec: ImVec2, val: float32): ImVec2 = 
  ImVec2(x: vec.x - val, y: vec.y - val)

proc `*`*(vec: ImVec2, val: float32): ImVec2 = 
  ImVec2(x: vec.x * val, y: vec.y * val)

proc `/`*(vec: ImVec2, val: float32): ImVec2 = 
  ImVec2(x: vec.x / val, y: vec.y / val)

proc `+=`*(vec1: var ImVec2, vec2: ImVec2) = 
  vec1.x += vec2.x
  vec1.y += vec2.y

proc `-=`*(vec1: var ImVec2, vec2: ImVec2) = 
  vec1.x -= vec2.x
  vec1.y -= vec2.y

proc `*=`*(vec1: var ImVec2, vec2: ImVec2) = 
  vec1.x *= vec2.x
  vec1.y *= vec2.y

proc `/=`*(vec1: var ImVec2, vec2: ImVec2) = 
  vec1.x /= vec2.x
  vec1.y /= vec2.y

proc igVec2*(x, y: float32): ImVec2 = ImVec2(x: x, y: y)

proc igVec4*(x, y, z, w: float32): ImVec4 = ImVec4(x: x, y: y, z: z, w: w)

proc igColorConvertU32ToFloat4*(color: uint32): ImVec4 = 
  igColorConvertU32ToFloat4NonUDT(result.addr, color)

proc igGetCursorScreenPos*(): ImVec2 = 
  igGetCursorScreenPosNonUDT(result.addr)

proc igGetWindowContentRegionMax*(): ImVec2 = 
  igGetWindowContentRegionMaxNonUDT(result.addr)

proc igGetMousePos*(): ImVec2 = 
  igGetMousePosNonUDT(result.addr)

proc makeFlags*[T: enum](flags: varargs[T]): T =
  ## Mix multiple flags of a specific enum
  var res = 0
  for x in flags:
    res = res or int(x)

  result = T res

proc calcTextSizeA*(
  self: ptr ImFont, 
  size: float32, 
  max_width: float32, 
  wrap_width: float32, 
  text_begin: cstring, 
  text_end: cstring = nil,
  remaining: ptr cstring = nil
): ImVec2 = 
  calcTextSizeANonUDT(
    result.addr, 
    self,  
    size, 
    max_width, 
    wrap_width, 
    text_begin, 
    text_end,
    remaining
  )

proc isAlphaNum*(rune: string): bool = 
  for i in rune:
    if not isAlpha($i) or i.isAlphaNumeric(): # FIXME
      return false

proc isUTF8*(rune: string): bool = 
  rune.len != rune.runeAt(0).size
  # bitand(c[0].ord, 0xC0) == 0x80 # FIXME

proc getDuration*(): Duration = 
  initDuration(nanoseconds = getMonoTime().ticks)
