import std/[monotimes, sequtils, strutils, unicode, bitops, tables, math, re]
import nimgl/imgui

type
  PaletteIndex* .pure. = enum
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
    MultiLineComment,
    Background,
    Cursor,
    Selection,
    ErrorMarker,
    Breakpoint,
    LineNumber,
    CurrentLineFill,
    CurrentLineFillInactive,
    CurrentLineEdge

  SelectionMode* .pure. = enum
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

  Identifiers* = Table[string, Identifier]
  Keywords* = seq[string]
  ErrorMarkers* = OrderedTable[int, string]
  Breakpoints* = seq[int]
  Palette* = array[PaletteIndex.high, uint32] # FIXME

  Glyph* = object
    c*: string
    colorIndex*: PaletteIndex
    comment*: bool
    multiLineComment*: bool
    preprocessor*: bool

  Line* = seq[Glyph]
  Lines* = seq[Line]

  TokenRegexString* = (string, PaletteIndex) # FIXME
  TokenRegexStrings* = seq[TokenRegexString]
  TokenizeCallback = proc(inBegin, inEnd: string, outBegin, outEnd: var string, paletteIndex: PaletteIndex): bool # FIXME

  LanguageDef* = object
    name*: string
    keywords*: Keywords
    identifiers*, preprocIdentifiers*: Identifiers
    commentStart*, commentEnd*, singleLineComment*: string
    preprocChar*: char
    autoIndentation*, caseSensitive*: bool

    tokenize*: TokenizeCallback
    tokenRegexStrings*: TokenRegexStrings

  RegexList* = seq[(Regex, PaletteIndex)]

  EditorState* = object
    selectionStart*, selectionEnd*, cursorPosition*: Coord

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

    tabSize*: int
    overwrite*: bool
    readOnly*: bool
    withinRender*: bool
    scrollToCursor*: bool
    scrollToTop*: bool
    textChanged*: bool
    colorizerEnabled*: bool
    textStart*: float # position (in pixels) where a code line starts relative to the left of the TextEditor.
    leftMargin*: int
    cursorPositionChanged*: bool
    colorRangeMin*, colorRangeMax*: int
    selectionMode*: SelectionMode
    handleKeyboardInputs*: bool
    handleMouseInputs*: bool
    ignoreImGuiChild*: bool
    showWhitespaces*: bool

    paletteBase*: Palette
    palette*: Palette
    languageDef*: LanguageDef
    regexList*: RegexList

    checkComments*: bool
    breakpoints*: Breakpoints
    rrrorMarkers*: ErrorMarkers
    charAdvance*: ImVec2
    interactiveStart*, interactiveEnd*: Coord
    lineBuffer*: string
    startTime*: MonoTime

    lastClick*: float

proc isAlphaNum*(c: Rune): bool = 
  c.isAlpha() or c in Digits

proc calcTextSizeA(
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

proc coord*(line, col: Positive): Coord = 
  Coord(line: line, col: col)

proc `<`*(coord1, coord2: Coord): bool = 
  coord1.line < coord2.line and coord1.col < coord2.col

proc `<=`*(coord1, coord2: Coord): bool = 
  coord1.line <= coord2.line and coord1.col <= coord2.col

proc glyph*(c: char, colorIndex: PaletteIndex): Glyph = 
  Glyph(c: c, colorIndex: colorIndex, comment: false, multiLineComment: false, preprocessor: false)

proc languageDef*(
  name: string, 
  keywords: Keywords, 
  identifiers, preprocIdentifiers: Identifiers, 
  preprocChar: char, 
  autoIndentation, caseSensitive: bool, 
  tokenize: TokenizeCallback, 
  tokenRegexStrings: TokenRegexStrings
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
    tokenRegexStrings: tokenRegexStrings
  )

proc initTextEditor*(
  lineSpacing: float = 1f, 
  lines: Lines, 
  state: EditorState, 
  undoBuffer: UndoBuffer, 
  undoIndex: int = 0, 
  tabSize: int = 2,
  overwrite: bool = false, 
  readOnly: bool = false, 
  withinRender: bool = false, 
  scrollToCursor: bool = false, 
  scrollToTop: bool = false, 
  textChanged: bool = false, 
  colorizerEnabled: bool = true, 
  textStart: float = 20f, 
  leftMargin: int = 10, 
  cursorPositionChanged: bool = false, 
  colorRangeMin, colorRangeMax: int = 0, 
  selectionMode: SelectionMode = SelectionMode.Normal, 
  handleKeyboardInputs: bool = true, 
  handleMouseInputs: bool = true, 
  ignoreImGuiChild: bool = false, 
  showWhitespaces: bool = true, 
  paletteBase: Palette, 
  palette: Palette, 
  languageDef: LanguageDef, 
  regexList: RegexList, 
  checkComments: bool = true, 
  breakpoints: Breakpoints, 
  rrrorMarkers: ErrorMarkers, 
  charAdvance: ImVec2, 
  interactiveStart, interactiveEnd: Coord, 
  lineBuffer: string, 
  startTime: MonoTime = getMonoTime(), 
  lastClick: float = -1f, 
): TextEditor = 
  TextEditor(
    lineSpacing: lineSpacing, 
    lines: lines, 
    state: state, 
    undoBuffer: undoBuffer, 
    undoIndex: undoIndex, 
    tabSize: tabSize, 
    overwrite: overwrite, 
    readOnly: readOnly, 
    withinRender: withinRender, 
    scrollToCursor: scrollToCursor, 
    scrollToTop: scrollToTop, 
    textChanged: textChanged, 
    colorizerEnabled: colorizerEnabled, 
    textStart: textStart, 
    leftMargin: leftMargin, 
    cursorPositionChanged: cursorPositionChanged, 
    colorRangeMin: colorRangeMin, colorRangeMax: colorRangeMax, 
    selectionMode: selectionMode, 
    handleKeyboardInputs: handleKeyboardInputs, 
    handleMouseInputs: handleMouseInputs, 
    ignoreImGuiChild: ignoreImGuiChild, 
    showWhitespaces: showWhitespaces, 
    paletteBase: paletteBase, 
    palette: palette, 
    languageDef: languageDef, 
    regexList: regexList, 
    checkComments: checkComments, 
    breakpoints: breakpoints, 
    rrrorMarkers: rrrorMarkers, 
    charAdvance: charAdvance, 
    interactiveStart: interactiveStart, interactiveEnd: interactiveEnd, 
    lineBuffer: lineBuffer, 
    startTime: startTime, 
    lastClick: lastClick, 
  )

# proc equals*[InputIt1, InputIt2, BinaryPredicate](first1: InputIt1, last1: InputIt1, first2: InputIt2, last2: InputIt2, p: BinaryPredicate): bool = # TODO

proc `languageDef=`*(self: var TextEditor, def: LanguageDef) = 
  self.languageDef = def
  self.regexList.reset()

  for r in def.tokenRegexStrings:
    self.regexList.add (re(r[0]), r[1])

  self.colorize()

proc getText*(self: var TextEditor, startCoord, endCoord: Coord): string
  var lStart = startCoord.line
  let lEnd = endCoord.line
  var iStart = self.getCharacterIndex(startCoord)
  let iEnd = self.getCharacterIndex(endCoord)
  # var s = 0

  # for i in lStart..lEnd:
  #   s += self.lines[i].len

  # result.reserve(s + s / 8)

  while iStart < iEnd or lStart < lEnd:
    if lStart >= self.lines.len:
      break

    let line = self.lines[lStart]
    if iStart < line.len:
      result.add line[iStart].c
      inc iStart
    else:
      iStart = 0
      inc lStart
      result.add '\n'

proc sanitizeCoord*(self: TextEditor, coord: Coord): Coord = 
  result = coord

  if result.line >= self.lines.len:
    if self.lines.len == 0:
      result.line = 0
      result.col = 0
    else:
      result.line = self.lines.high
      result.col = self.getLineMaxColumn(result.line)
  else:
    result.col = if self.lines.len == 0: 0 else: min(column, self.getLineMaxColumn(result.line))

proc getActualCursorCoordinates*(self: TextEditor): Coord = 
  self.state.cursorPosition.sanitizeCoord()

# static int UTF8CharLength(TextEditor::Char c) #TODO

# static inline int ImTextCharToUtf8(char* buf, int buf_size, unsigned int c) # TODO

proc advance(self: var TextEditor, coord: var Coord) = 
  if coord.line < self.lines.len
    let line = self.lines[coord.line]
    var cindex = self.getCharacterIndex(coord)

    if cindex < line.len: # FIXME
      let delta = line[cindex].c.runeLen
      cindex = min(cindex + delta, line.high)
    else:
      inc coord.line
      cindex = 0

    coord.col = getCharacterColumn(coord.line, cindex)

proc deleteRange(self: var TextEditor, startCoord, endCoord: Coord) = 
  # FIXME Check if begin/end are the same as 0/high
  assert endCoord >= startCoord
  assert not self.readOnly

  # echo "DstartCoord.line.startCoord.col-endCoord.line.endCoord.col"

  if startCoord == endCoord:
    return

  let iStart = self.getCharacterIndex(startCoord)
  let iEnd = self.getCharacterIndex(endCoord)

  if startCoord.line == endCoord.line:
    let line = self.lines[startCoord.line]
    let n = self.getLineMaxColumn(startCoord.line)
    
    if endCoord.column >= n:
      line.delete(iStart..line.high)
    else:
      line.delete(iStart..iEnd)

  else:
    var firstLine = self.lines[startCoord.line]
    var lastLine = self.lines[endCoord.line]

    firstLine.delete(start..firstLine.high)
    lastLine.delete(0..iEnd)

    if startCoord.line < endCoord.line:
      firstLine.add(lastLine)
      self.removeLine(startCoord.line + 1, endCoord.line + 1)

  self.textChanged = true

proc insertTextAt(self: var TextEditor, where: var Coord, value: string): int = # FIXME
  assert not self.readOnly

  var cindex = self.getCharacterIndex(where)
  
  while value != '\0':
    assert self.lines.len > 0

    if value == '\r':
      inc value
    elif value == '\n':
      if cindex < self.lines[where.line].len:
        var newLine = self.insertLine(where.line + 1)
        var line = self.lines[where.line]
        
        newLine.insert(line[cindex..^1], 0)
        line.delete(cindex..^1)

      else:
        self.insertLine(where.line + 1)

      inc where.line
      where.col = 0
      cindex = 0
      inc result
      inc value
    
    else:
      var line = self.lines[where.line]
      var d = value.runeLen
      while d > 0 and value != '\0':
        line.insert(glyph(value, PaletteIndex.Default), cindex)
        inc cindex
        dec value

      inc where.col

    self.textChanged = true

proc addUndo*(self: var TextEditor, rec: UndoRecord) = 
  assert not self.readOnly

  #printf("AddUndo: (@%d.%d) +\'%s' [%d.%d .. %d.%d], -\'%s', [%d.%d .. %d.%d] (@%d.%d)\n",
  #  aValue.mBefore.mCursorPosition.line, aValue.mBefore.mCursorPosition.mColumn,
  #  aValue.mAdded.c_str(), aValue.mAddedStart.line, aValue.mAddedStart.mColumn, aValue.mAddedEnd.line, aValue.mAddedEnd.mColumn,
  #  aValue.mRemoved.c_str(), aValue.mRemovedStart.line, aValue.mRemovedStart.mColumn, aValue.mRemovedEnd.line, aValue.mRemovedEnd.mColumn,
  #  aValue.mAfter.mCursorPosition.line, aValue.mAfter.mCursorPosition.mColumn
  #  )

  self.undoBuffer.add rec
  inc self.undoIndex

proc screenPosToCoordinates*(self: TextEditor, pos: ImVec2): Coord = 
  let origin = igGetCursorScreenPos()
  let local = pos - origin # FIXME

  let lineNo = max(0, int floor(local.y / self.charAdvance.y))
  var columnCoord = 0

  if lineNo >= 0 and lineNo < self.lines.len:
    let line = self.lines[lineNo]

    var columnIndex = 0
    var columnX = 0f

    while columnIndex < line.len:
      var columnWidth = 0f

      if line[columnIndex].c == "\t":
        let spaceSize = igGetFont().calcTextSizeA(igGetFontlen, float.high, -1f, " ").x
        let oldX = columnX
        let newColumnX = (1f + floor((1f + columnX) / (self.tabSize * spaceSize))) * (self.tabSize * spaceSize)
        columnWidth = newColumnX - oldX
        if (self.textStart + columnX + columnWidth * 0f) > local.x: # FIXME
          break

        columnX = newColumnX
        columnCoord = (columnCoord / self.tabSize) * self.tabSize + self.tabSize
        inc columnIndex
      
      else:
        let buf = newString(7)
        let d = line[columnIndex].c.runeLen
        var i = 0

        while i < 6 and d > 0:
          buf[i] = line[columnIndex].c
          dec d
          inc i
          inc columnIndex

        buf[i] = '\0'
        columnWidth = igGetFont().calcTextSizeA(igGetFontlen, float.high, -1f, cstring buf).x
        if (self.textStart + columnX + columnWidth * 0.5f) > local.x:
          break

        columnX += columnWidth
        inc columnCoord

  result = self.sanitizeCoordinates(coord(lineNo, columnCoord))

proc findWordStart*(self: TextEditor, at: Coord): Coord = 
  if at.line >= self.lines.len:
    return at

  let line = self.lines[at.line]
  var cindex = self.getCharacterIndex(at)

  if cindex >= line.len:
    return at

  while cindex > 0 and line[cindex].c.isSpace()
    dec cindex

  let cstart = line[cindex].colorIndex
  while cindex > 0:
    let c = line[cindex].c

    if bitand(c, 0xC0) != 0x80: # not UTF code sequence 10xxxxxx # FIXME
      if c <= 32 and c.isSpace():
        inc cindex

      if cstart != line[size_t(cindex - 1)].colorIndex: # FIXME size_t(cindex - 1)
        break

    dec cindex

  result = coord(at.line, self.getCharacterColumn(at.line, cindex))

proc findWordEnd*(self: TextEditor, at: Coord): Coord = 
  if at.line >= self.lines.len:
    return at

  let line = self.lines[at.line]
  var cindex = self.getCharacterIndex(at)

  if cindex >= line.len:
    return at

  let prevspace = line[cindex].c.isSpace()
  let cstart = line[cindex].colorIndex
  while cindex < line.len:
    let c = line[cindex].c
    let d = c.runeLen
    if cstart != line[cindex].colorIndex:
      break

    if prevspace != c.isSpace():
      if c.isSpace():
        while cindex < line.len and line[cindex].c.isSpace():
          inc cindex
      break
    
    cindex += d

  result = coord(at.line, self.getCharacterColumn(at.line, cindex))

proc findNextWord*(self: TextEditor, at: Coord): Coord = 

  if at.line >= self.lines.len:
    return at

  var at = at
  # skip to the next non-word character
  var cindex = self.getCharacterIndex(at)
  var isword = false
  var skip = false

  let line = lines[at.line]

  if cindex < line.len:
    isword = line[cindex].c.isAlphaNum()
    skip = isword

  while not isword or skip:
    if at.line >= self.lines.len:
      let l = max(0, self.lines.high)
      return coord(l, self.getLineMaxColumn(l))

    if cindex < line.len:
      isword = line[cindex].c.isAlphaNum()

      if isword and not skip:
        return coord(at.line, self.getCharacterColumn(at.line, cindex))

      if not isword:
        skip = false

      inc cindex
    
    else:
      cindex = 0
      inc at.line
      skip = false
      isword = false
    
  result = at

proc getCharacterIndex*(self: TextEditor, at: Coord): int
  if at.line >= self.lines.len:
    return -1

  let line = self.lines[at.line]
  var c = 0
  var result = 0
  while result < line.len and c < at.col:
    if line[result].c == "\t"
      c = (c / self.tabSize) * self.tabSize + self.tabSize
    else:
      inc c

    result += line[result].c.runeLen

proc getCharacterColumn*(self: TextEditor, aLine: int, aIndex: int): int
  if aLine >= self.lines.len:
    return 0

  let line = self.lines[aLine]
  var result = 0
  var i = 0

  while i < aIndex and i < line.len:
    let c = line[i].c
    i += c.runeLen
    if c == "\t":
      result = (result / self.tabSize) * self.tabSize + self.tabSize
    else:
      inc result

proc getLineCharacterCount(self: TextEditor, aLine: int): int
  if aLine >= self.lines.len:
    return 0

  let line = self.lines[aLine]

  var i = 0
  while i < line.len:
    i += line[i].c.runeLen
    inc result

int TextEditor::GetLineMaxColumn(int aLine) const

  if (aLine >= self.lines.len)
    return 0
  auto& line = self.lines[aLine]
  int col = 0
  for (unsigned i = 0 i < line.len )
  
    auto c = line[i].c
    if (c == "\t")
      col = (col / self.tabSize) * self.tabSize + self.tabSize
    else
      col++
    i += UTF8CharLength(c)
  
  return col


