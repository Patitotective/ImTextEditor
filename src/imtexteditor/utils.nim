import std/[monotimes, sequtils, strutils, unicode, times, re]
import nimgl/imgui

type
  PaletteIndex* {.pure.} = enum # FIXME Conflicting names
    Default,
    Keyword,
    Number,
    String,
    CharLiteral,
    Punctuation,
    Preprocessor,
    Identifier,
    KnownIdentifier,
    PreprocIdentifier,
    Comment,
    MultilineComment,
    Background,
    Cursor,
    Selection,
    ErrorMarker,
    Breakpoint,
    LineNumber,
    CurrentlineFill,
    CurrentlineFillInactive,
    CurrentlineEdge, 
    WhiteSpace, 
    WhiteSpaceTab, 

  SelectionMode* {.pure.} = enum # FIXME Conflicting names
    Normal,
    Word,
    Line

  Breakpoint* = object
    line*: int
    enabled*: bool
    condition*: string

  Coord* = object
    line*, col*: int

  Identifier* = object
    location*: Coord
    declaration*: string

  Identifiers* = seq[tuple[str: string, id: Identifier]]
  Keywords* = seq[string]
  ErrorMarkers* = seq[tuple[line: int, error: string]]
  Breakpoints* = seq[int]
  Palette* = array[PaletteIndex.high.ord + 1, uint32] # FIXME

  Glyph* = object
    rune*: Rune
    colorIndex*: PaletteIndex
    comment*: bool
    multilineComment*: bool
    preprocessor*: bool

  Line* = seq[Glyph]
  Lines* = seq[Line]

  RegexList* = seq[tuple[pattern: Regex, color: PaletteIndex]]
  TokenizeCallback = proc(input: string, start: int): tuple[ok: bool, token: Slice[int], col: PaletteIndex] # FIXME

  LanguageDef* = object
    name*: string
    keywords*: Keywords
    identifiers*, preprocIdentifiers*: Identifiers
    commentStart*, commentEnd*, singlelineComment*: string
    preprocChar*: char
    autoIndentation*, caseSensitive*: bool

    tokenize*: TokenizeCallback
    regexList*: RegexList

  EditorState* = object
    selectionStart*, selectionEnd*, cursorPos*: Coord

  UndoRecord* = object
    added*, removed*: string
    addedStart*, addedEnd*, removedStart*, removedEnd*: Coord
    before*, after*: EditorState

  UndoBuffer* = seq[UndoRecord]

  TextEditor* = object
    lineSpacing*: float
    lines*: Lines
    state*: EditorState
    undoBuffer*: UndoBuffer
    undoIndex*: int
    blinkDur*: Duration

    tabSize*: int
    overwrite*: bool
    readOnly*: bool
    withinRender*: bool
    scrollToCursor*: bool
    scrollToTop*: bool
    textChanged*: bool
    colorizerEnabled*: bool
    textStart*: float # pos (in pixels) where a code line starts relative to the left of the TextEditor.
    leftMargin*: int
    cursorPosChanged*: bool
    colorRangeMin*, colorRangeMax*: int
    selectionMode*: SelectionMode
    hasKeyboardInputs*: bool
    hasMouseInputs*: bool
    ignoreImGuiChild*: bool
    showWhitespaces*: bool

    paletteBase*: Palette
    palette*: Palette
    languageDef*: LanguageDef

    checkComments*: bool
    breakpoints*: Breakpoints
    errorMarkers*: ErrorMarkers
    charAdvance*: ImVec2
    interactiveStart*, interactiveEnd*: Coord
    lineBuffer*: string
    startTime*: Duration

    lastClick*: float

proc `$`*(line: Line): string = 
  for glyph in line:
    result.add(glyph.rune)

proc `<`*(coord1, coord2: Coord): bool = 
  coord1.line < coord2.line or (coord1.line == coord2.line and coord1.col < coord2.col)

proc `<=`*(coord1, coord2: Coord): bool = 
  coord1 < coord2 or coord1 == coord2

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

proc glyph*(rune: Rune, colorIndex: PaletteIndex): Glyph = 
  Glyph(rune: rune, colorIndex: colorIndex, comment: false, multilineComment: false, preprocessor: false)

proc glyph*(rune: string, colorIndex: PaletteIndex): Glyph = 
  assert rune.runeLen == 1

  glyph(rune.runeAt(0), colorIndex)

proc coord*(line, col: range[0..int.high]): Coord = 
  Coord(line: line, col: col)

proc getDarkPalette*(): Palette = 
  [
    0xffb0b0b0.uint32, # Default
    0xffd69c56.uint32, # Keyword  
    0xff00ff00.uint32, # Number
    0xff7070e0.uint32, # String
    0xff70a0e0.uint32, # Char literal
    0xffffffff.uint32, # Punctuation
    0xff408080.uint32, # Preprocessor
    0xffaaaaaa.uint32, # Identifier
    0xff9bc64d.uint32, # Known identifier
    0xffc040a0.uint32, # Preproc identifier
    0xff206020.uint32, # Comment (single line)
    0xff406020.uint32, # Comment (ulti line)
    0xff101010.uint32, # Background
    0xffe0e0e0.uint32, # Cursor
    0x80a06020.uint32, # Selection
    0x800020ff.uint32, # ErrorMarker
    0x40f08000.uint32, # Breakpoint
    0xff707000.uint32, # Line number
    0x40000000.uint32, # Current line fill
    0x40808080.uint32, # Current line fill (inactive)
    0x40a0a0a0.uint32, # Current line edge
    0x38b0b0b0.uint32, # White Space
    0x30b0b0b0.uint32, # White Space Tab
  ]

proc getLightPalette*(): Palette = 
  [
    0xff404040.uint32, # None
    0xffff0c06.uint32, # Keyword  
    0xff008000.uint32, # Number
    0xff2020a0.uint32, # String
    0xff304070.uint32, # Char literal
    0xff000000.uint32, # Punctuation
    0xff406060.uint32, # Preprocessor
    0xff404040.uint32, # Identifier
    0xff606010.uint32, # Known identifier
    0xffc040a0.uint32, # Preproc identifier
    0xff205020.uint32, # Comment (single line)
    0xff405020.uint32, # Comment (ulti line)
    0xffffffff.uint32, # Background
    0xff000000.uint32, # Cursor
    0x40600000.uint32, # Selection
    0xa00010ff.uint32, # ErrorMarker
    0x80f08000.uint32, # Breakpoint
    0xff505000.uint32, # Line number
    0x40000000.uint32, # Current line fill
    0x40808080.uint32, # Current line fill (inactive)
    0x40000000.uint32, # Current line edge
    0x38404040.uint32, # White Space
    0x30404040.uint32, # White Space Tab
  ]

proc getRetroBluePalette*(): Palette = 
  [
    0xff00ffff.uint32, # None
    0xffffff00.uint32, # Keyword  
    0xff00ff00.uint32, # Number
    0xff808000.uint32, # String
    0xff808000.uint32, # Char literal
    0xffffffff.uint32, # Punctuation
    0xff008000.uint32, # Preprocessor
    0xff00ffff.uint32, # Identifier
    0xffffffff.uint32, # Known identifier
    0xffff00ff.uint32, # Preproc identifier
    0xff808080.uint32, # Comment (single line)
    0xff404040.uint32, # Comment (ulti line)
    0xff800000.uint32, # Background
    0xff0080ff.uint32, # Cursor
    0x80ffff00.uint32, # Selection
    0xa00000ff.uint32, # ErrorMarker
    0x80ff8000.uint32, # Breakpoint
    0xff808000.uint32, # Line number
    0x40000000.uint32, # Current line fill
    0x40808080.uint32, # Current line fill (inactive)
    0x40000000.uint32, # Current line edge
    0x3800ffff.uint32, # White Space
    0x3000ffff.uint32, # White Space Tab
  ]

proc getMonokaiPalette*(): Palette = 
  [
    0xf7f7f7ff.uint32, # Default
    0xac80ffff.uint32, # Keyword  
    0xac80ffff.uint32, # Number
    0xe7db74ff.uint32, # String
    0xe7db74ff.uint32, # Char literal
    0xf92472ff.uint32, # Punctuation
    0xf92472ff.uint32, # Preprocessor
    0xf7f7f7ff.uint32, # Identifier
    0x67d8efff.uint32, # Known identifier
    0xf92472ff.uint32, # Preproc identifier
    0x74705dff.uint32, # Comment (single line)
    0x74705dff.uint32, # Comment (multi line)
    0x262721ff.uint32, # Background
    0xf8f8f1e6.uint32, # Cursor
    0x80a06020.uint32, # Selection
    0xf83535ff.uint32, # ErrorMarker
    0x40f08000.uint32, # Breakpoint
    0xff707000.uint32, # Line number
    0x40000000.uint32, # Current line fill
    0x40808080.uint32, # Current line fill (inactive)
    0x40a0a0a0.uint32, # Current line edge
    0x38b0b0b0.uint32, # White Space
    0x30b0b0b0.uint32, # White Space Tab
  ]

proc getDuration*(): Duration = 
  initDuration(nanoseconds = getMonoTime().ticks)

proc languageDef*(
  name: string, 
  keywords: Keywords, 
  identifiers, preprocIdentifiers: Identifiers, 
  preprocChar: char, 
  autoIndentation, caseSensitive: bool, 
  tokenize: TokenizeCallback, 
  regexList: RegexList
): LanguageDef = 
  LanguageDef(
    name: name, 
    keywords: keywords, 
    identifiers: identifiers, 
    preprocIdentifiers: preprocIdentifiers, 
    preprocChar: preprocChar, 
    autoIndentation: autoIndentation, 
    caseSensitive: caseSensitive, 
    tokenize: tokenize, 
    regexList: regexList
  )

proc initTextEditor*(
  lineSpacing: float = 1f, 
  lines: Lines = @[Line.default], 
  state: EditorState = EditorState.default, 
  undoBuffer: UndoBuffer = UndoBuffer.default, 
  undoIndex: int = -1, 
  blinkMs: int = 800, 
  tabSize: int = 2,
  overwrite: bool = false, 
  readOnly: bool = false, 
  withinRender: bool = false, 
  scrollToCursor: bool = false, 
  scrollToTop: bool = false, 
  textChanged: bool = false, 
  textStart: float = 20f, 
  leftMargin: int = 10, 
  cursorPosChanged: bool = false, 
  colorRangeMin, colorRangeMax: int = 0, 
  selectionMode: SelectionMode = SelectionMode.Normal, 
  hasKeyboardInputs: bool = true, 
  hasMouseInputs: bool = true, 
  ignoreImGuiChild: bool = false, 
  showWhitespaces: bool = true, 
  palette: Palette = getDarkPalette(), # Actually paletteBase
  languageDef: LanguageDef = LanguageDef.default, 
  checkComments: bool = true, 
  breakpoints: Breakpoints = Breakpoints.default, 
  errorMarkers: ErrorMarkers = ErrorMarkers.default, 
  charAdvance: ImVec2 = ImVec2.default, 
  interactiveStart, interactiveEnd: Coord = Coord.default, 
  lineBuffer: string = string.default, 
  startTime: Duration = getDuration(), 
  lastClick: float = -1f, 
): TextEditor = 
  TextEditor(
    lineSpacing: lineSpacing, 
    lines: lines, 
    state: state, 
    undoBuffer: undoBuffer, 
    undoIndex: undoIndex, 
    blinkDur: initDuration(milliseconds = blinkMs), 
    tabSize: tabSize, 
    overwrite: overwrite, 
    readOnly: readOnly, 
    withinRender: withinRender, 
    scrollToCursor: scrollToCursor, 
    scrollToTop: scrollToTop, 
    textChanged: textChanged, 
    colorizerEnabled: languageDef != LanguageDef.default, 
    textStart: textStart, 
    leftMargin: leftMargin, 
    cursorPosChanged: cursorPosChanged, 
    colorRangeMin: colorRangeMin, colorRangeMax: colorRangeMax, 
    selectionMode: selectionMode, 
    hasKeyboardInputs: hasKeyboardInputs, 
    hasMouseInputs: hasMouseInputs, 
    ignoreImGuiChild: ignoreImGuiChild, 
    showWhitespaces: showWhitespaces, 
    paletteBase: palette, 
    languageDef: languageDef, 
    checkComments: checkComments, 
    breakpoints: breakpoints, 
    errorMarkers: errorMarkers, 
    charAdvance: charAdvance, 
    interactiveStart: interactiveStart, interactiveEnd: interactiveEnd, 
    lineBuffer: lineBuffer, 
    startTime: startTime, 
    lastClick: lastClick, 
  )

proc igColorConvertU32ToFloat4*(color: uint32): ImVec4 = 
  igColorConvertU32ToFloat4NonUDT(result.addr, color)

proc igGetCursorScreenPos*(): ImVec2 = 
  igGetCursorScreenPosNonUDT(result.addr)

proc igGetWindowContentRegionMax*(): ImVec2 = 
  igGetWindowContentRegionMaxNonUDT(result.addr)

proc igGetContentRegionAvail*(): ImVec2 = 
  igGetContentRegionAvailNonUDT(result.addr)

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

proc isAlphaNum*(rune: Rune): bool = 
  return rune.isAlpha() or rune.ord in '0'.ord .. '9'.ord

proc delete*[T](s: var seq[T], x: HSlice[int, BackwardsIndex]) = 
  if s.len - x.b.int >= 0:
    s.delete(x.a..s.len - x.b.int)
