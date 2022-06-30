import std/[strformat, sequtils, strutils, unicode, bitops, times, math, re]
import nimgl/imgui

import utils

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
    CurrentlineEdge

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

  TokenRegexString* = tuple[pattern: string, color: PaletteIndex] # FIXME
  TokenRegexStrings* = seq[TokenRegexString]
  TokenizeCallback = proc(str: string): tuple[ok: bool, token: string, start: int, col: PaletteIndex] # FIXME

  LanguageDef* = object
    name*: string
    keywords*: Keywords
    identifiers*, preprocIdentifiers*: Identifiers
    commentStart*, commentEnd*, singlelineComment*: string
    preprocChar*: char
    autoIndentation*, caseSensitive*: bool

    tokenize*: TokenizeCallback
    tokenRegexStrings*: TokenRegexStrings

  RegexList* = seq[(Regex, PaletteIndex)]

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
    regexList*: RegexList

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

proc coord*(line, col: range[0..int.high]): Coord = 
  Coord(line: line, col: col)

proc `<`*(coord1, coord2: Coord): bool = 
  coord1.line < coord2.line and coord1.col < coord2.col

proc `<=`*(coord1, coord2: Coord): bool = 
  coord1.line <= coord2.line and coord1.col <= coord2.col

proc glyph*(rune: Rune, colorIndex: PaletteIndex): Glyph = 
  Glyph(rune: rune, colorIndex: colorIndex, comment: false, multilineComment: false, preprocessor: false)

proc glyph*(rune: string, colorIndex: PaletteIndex): Glyph = 
  assert rune.runeLen == 1

  glyph(rune.runeAt(0), colorIndex)

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

proc getCharacterIndex*(self: TextEditor, at: Coord): int = 
  if at.line >= self.lines.len:
    return -1

  let line = self.lines[at.line]
  var c = 0
  while result < runeLen($line) and c < at.col:
    if $line[result].rune == "\t":
      c = (c div self.tabSize) * self.tabSize + self.tabSize
    else:
      inc c

    inc result

proc getCharacterColumn*(self: TextEditor, lineNo: int, index: int): int = 
  if lineNo >= self.lines.len:
    return 0

  let line = self.lines[lineNo]
  var i = 0

  while i < index and i < runeLen($line):
    let rune = line[i].rune
    inc i
    if $rune == "\t":
      result = (result div self.tabSize) * self.tabSize + self.tabSize
    else:
      inc result

proc getlineCharacterCount*(self: TextEditor, lineNo: int): int = 
  if lineNo >= self.lines.len:
    return 0

  let line = self.lines[lineNo]

  var i = 0
  while i < runeLen($line):
    inc i
    inc result

proc getLineMaxColumn*(self: TextEditor, lineNo: int): int = 
  if lineNo >= self.lines.len:
    return 0
  
  let line = self.lines[lineNo]

  var i = 0
  while i < runeLen($line):
    let rune = line[i].rune
    if $rune == "\t":
      result = (result div self.tabSize) * self.tabSize + self.tabSize
    else:
      inc result

    inc i

proc getText*(self: TextEditor, startCoord, endCoord: Coord): string = 
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
    if iStart < runeLen($line):
      result.add(line[iStart].rune)
      inc iStart
    else:
      iStart = 0
      inc lStart
      result.add('\n')

proc getText*(self: TextEditor): string = 
  self.getText(coord(0, 0), coord(self.lines.len, 0))

proc getTextLines*(self: TextEditor): seq[string] = 
  for line in self.lines:
    result.add("")
    for g in line:
      result[^1].add(g.rune)

proc getSelectedText*(self: TextEditor): string = 
  self.getText(self.state.selectionStart, self.state.selectionEnd)

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
    result.col = if self.lines.len == 0: 0 else: min(result.col, self.getLineMaxColumn(result.line))

proc getActualCursorCoord*(self: TextEditor): Coord = 
  self.sanitizeCoord(self.state.cursorPos)

proc getCursorPos*(self: TextEditor): Coord = 
  self.getActualCursorCoord()

proc getTotalLines*(self: TextEditor): int = 
  self.lines.len

# static int UTF8CharLength(TextEditorChar c) #TODO

# static inline int ImTextCharToUtf8(char* buf, int buf_size, unsigned int c) # TODO

proc advance(self: var TextEditor, coord: var Coord) = 
  if coord.line < self.lines.len:
    let line = self.lines[coord.line]
    var cindex = self.getCharacterIndex(coord)

    if cindex + 1 < runeLen($line):
      cindex = min(cindex + 1, line.high)
    else:
      inc coord.line
      cindex = 0

    coord.col = self.getCharacterColumn(coord.line, cindex)

proc removeline*(self: var TextEditor, startL, endL: int) = 
  assert not self.readOnly
  assert endL >= startL
  assert self.lines.len > (endL - startL)

  for e, (line, str) in self.errorMarkers.deepCopy(): # FIXME
    let errLn = if line >= startL: line - 1 else: line

    if errLn in startL..endL:
      self.errorMarkers.del(e)
    else:
      self.errorMarkers[e] = (errLn, str)

  for e, line in self.breakpoints:
    if line in startL..endL:
      self.breakpoints.del(e)
    else:
      self.breakpoints[e] = if line >= startL: line - 1 else: line

  self.lines.delete(startL..endL)

  assert self.lines.len != 0

  self.textChanged = true

proc removeline*(self: var TextEditor, index: int) =  # FIXME
  self.removeline(index, index)

proc deleteRange(self: var TextEditor, startCoord, endCoord: Coord) = 
  # FIXME Check if begin/end re the same s 0/high
  assert endCoord >= startCoord
  assert not self.readOnly

  # echo "DstartCoord.line.startCoord.col-endCoord.line.endCoord.col"

  if startCoord == endCoord:
    return

  let iStart = self.getCharacterIndex(startCoord)
  let iEnd = self.getCharacterIndex(endCoord)

  if startCoord.line == endCoord.line:
    var line = self.lines[startCoord.line]
    let n = self.getLineMaxColumn(startCoord.line)
    
    if endCoord.col >= n:
      line.delete(iStart..line.high)
    else:
      line.delete(iStart..iEnd)

  else:
    var firstline = self.lines[startCoord.line]
    var lastline = self.lines[endCoord.line]

    firstline.delete(iStart..firstline.high)
    lastline.delete(0..iEnd)

    if startCoord.line < endCoord.line:
      firstline.add(lastline)
      self.removeline(startCoord.line + 1, endCoord.line + 1)

  self.textChanged = true

proc insertLine*(self: var TextEditor, index: int) = 
  assert not self.readOnly

  self.lines.insert(Line.default, index)

  for e, (line, str) in self.errorMarkers.deepCopy(): # FIXME
    self.errorMarkers[e] = ((if line >= index: line + 1 else: line), str)

  for e, line in self.breakpoints:
    self.breakpoints[e] = if line >= index: line + 1 else: e

proc insertTextAt(self: var TextEditor, where: var Coord, value: string): int = # FIXME
  assert not self.readOnly

  var cindex = self.getCharacterIndex(where)
  
  for rune in value.runes:
    assert self.lines.len > 0

    if rune.ord == '\r'.ord:
      continue
    elif rune.ord == '\n'.ord:
      if cindex < self.lines[where.line].len:
        let line = self.lines[where.line]
        self.insertLine(where.line + 1)
        self.lines[where.line + 1].insert(line[cindex..line.high], 0) # New Line
        self.lines[where.line].delete(cindex..line.high)

      else:
        echo "Enter new line"
        self.insertLine(where.line + 1)

      inc where.line
      where.col = 0
      cindex = 0
      inc result
    
    else:
      self.lines[where.line].insert(glyph(rune, PaletteIndex.Default), cindex)
      inc cindex
      inc where.col

    self.textChanged = true

proc addUndo*(self: var TextEditor, rec: UndoRecord) = 
  assert not self.readOnly

  #printf("addUndo: (@%d.%d) +\'%s' [%d.%d .. %d.%d], -\'%s', [%d.%d .. %d.%d] (@%d.%d)\n",
  #  value.before.cursorPos.line, value.before.cursorPos.col,
  #  value.added.c_str(), value.addedStart.line, value.addedStart.col, value.addedEnd.line, value.addedEnd.col,
  #  value.removed.c_str(), value.removedStart.line, value.removedStart.col, value.removedEnd.line, value.removedEnd.col,
  #  value.after.cursorPos.line, value.after.cursorPos.col
  #  )

  self.undoBuffer.add(rec)
  inc self.undoIndex

proc screenPosToCoord*(self: TextEditor, pos: ImVec2): Coord = 
  let origin = igGetCursorScreenPos()
  let local = pos - origin

  let lineNo = max(0, int floor(local.y / self.charAdvance.y))
  var columnCoord = 0

  if lineNo >= 0 and lineNo < self.lines.len:
    let line = self.lines[lineNo]

    var columnIndex = 0
    var columnX = 0f

    while columnIndex < runeLen($line):
      var columnWidth = 0f

      if $line[columnIndex].rune == "\t":
        let spaceSize = igGetFont().calcTextSizeA(igGetFontSize(), float.high, -1f, " ").x
        let oldX = columnX
        let newColumnX = (1f + floor((1f + columnX) / (self.tabSize.float32 * spaceSize))) * (self.tabSize.float32 * spaceSize)
        columnWidth = newColumnX - oldX
        if self.textStart + columnX + columnWidth * 0.5f > local.x:
          break

        columnX = newColumnX
        columnCoord = (columnCoord div self.tabSize) * self.tabSize + self.tabSize
        inc columnIndex
      
      else:

        columnWidth = igGetFont().calcTextSizeA(igGetFontSize(), float.high, -1f, cstring $line[columnIndex].rune).x
        inc columnIndex

        if self.textStart + columnX + columnWidth * 0.5f > local.x:
          break

        columnX += columnWidth
        inc columnCoord

  result = self.sanitizeCoord(coord(lineNo, columnCoord))

proc findWordStart*(self: TextEditor, at: Coord): Coord = 
  if at.line >= self.lines.len:
    return at

  let line = self.lines[at.line]
  var cindex = self.getCharacterIndex(at)

  if cindex >= runeLen($line):
    return at

  while cindex > 0 and line[cindex].rune.isWhiteSpace():
    dec cindex

  let cstart = line[cindex].colorIndex
  while cindex > 0:
    let rune = line[cindex].rune

    if bitand(rune.size, 0xC0) != 0x80: # not UTF code sequence 10xxxxxx # FIXME
      if rune.size <= 32 and rune.isWhiteSpace():
        inc cindex

      if cstart != line[cindex - 1].colorIndex: # FIXME size_t(cindex - 1)
        break

    dec cindex

  result = coord(at.line, self.getCharacterColumn(at.line, cindex))

proc findWordEnd*(self: TextEditor, at: Coord): Coord = 
  if at.line >= self.lines.len:
    return at

  let line = self.lines[at.line]
  var cindex = self.getCharacterIndex(at)

  if cindex >= runeLen($line):
    return at

  let prevspace = isSpace($line[cindex].rune)
  let cstart = line[cindex].colorIndex
  while cindex < runeLen($line):
    let rune = line[cindex].rune
    if cstart != line[cindex].colorIndex:
      break

    if prevspace != isSpace($rune):
      if isSpace($rune):
        while cindex < runeLen($line) and isSpace($line[cindex].rune):
          inc cindex
      break
    
    inc cindex

  result = coord(at.line, self.getCharacterColumn(at.line, cindex))

proc findNextWord*(self: TextEditor, at: Coord): Coord = 
  if at.line >= self.lines.len:
    return at

  var at = at
  # skip to the next non-word character
  var cindex = self.getCharacterIndex(at)
  var isword = false
  var skip = false

  let line = self.lines[at.line]

  if cindex < runeLen($line):
    isword = isAlphaNum($line[cindex].rune)
    skip = isword

  while not isword or skip:
    if at.line >= self.lines.len:
      let l = max(0, self.lines.high)
      return coord(l, self.getLineMaxColumn(l))

    if cindex < runeLen($line):
      isword = isAlphaNum($line[cindex].rune)

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

proc findPrevWord*(self: TextEditor, at: Coord): Coord = 
  if at.line >= self.lines.len:
    return at

  var at = at
  # skip to the next non-word character
  var cindex = self.getCharacterIndex(at)
  var isword = false
  var skip = false

  let line = self.lines[at.line]

  if cindex > 0:
    isword = isAlphaNum($line[cindex].rune)
    skip = isword

  while not isword or skip:
    if at.line <= 0:
      return coord(0, self.getLineMaxColumn(0))

    if cindex > 0:
      isword = isAlphaNum($line[cindex].rune)

      if isword and not skip:
        return coord(at.line, self.getCharacterColumn(at.line, cindex))

      if not isword:
        skip = false

      dec cindex
    
    else:
      dec at.line
      cindex = self.getLineMaxColumn(at.line)
      skip = false
      isword = false
    
  result = at

proc isOnWordBoundary(self: TextEditor, at: Coord): bool = 
  if at.line >= self.lines.len or at.col == 0:
    return true

  let line = self.lines[at.line]
  var cindex = self.getCharacterIndex(at)
  if cindex >= runeLen($line):
    return true

  if self.colorizerEnabled:
    return line[cindex].colorIndex != line[cindex - 1].colorIndex

  result = isSpace($line[cindex].rune) != isSpace($line[cindex - 1].rune)

proc getWordAt*(self: TextEditor, at: Coord): string = 
  let istart = self.getCharacterIndex(self.findWordStart(at))
  let iend = self.getCharacterIndex(self.findWordEnd(at))

  for col in istart..<iend:
    result.add(self.lines[at.line][col].rune)

proc getWordUnderCursor(self: TextEditor): string = 
  self.getWordAt(self.getCursorPos())

proc getGlyphColor*(self: TextEditor, glyph: Glyph): uint32 = 
  if not self.colorizerEnabled:
    result = self.palette[ord PaletteIndex.Default]
  elif glyph.comment:
    result = self.palette[ord PaletteIndex.Comment]
  elif glyph.multilineComment:
    result = self.palette[ord PaletteIndex.MultilineComment]
  else:
    result = self.palette[ord glyph.colorIndex]
    if glyph.preprocessor:
      let ppcolor = self.palette[ord PaletteIndex.Preprocessor]
      let c0 = (bitand(ppcolor, 0xff) + bitand(result, 0xff)) div 2
      let c1 = (bitand(ppcolor.rotateRightBits(8), 0xff) + bitand(result.rotateRightBits(8), 0xff)) div 2
      let c2 = (bitand(ppcolor.rotateRightBits(16), 0xff) + bitand(result.rotateRightBits(16), 0xff)) div 2
      let c3 = (bitand(ppcolor.rotateRightBits(24), 0xff) + bitand(result.rotateRightBits(24), 0xff)) div 2
      result = bitor(bitor(c0, c1.rotateLeftBits(8)), bitor(c2.rotateLeftBits(16), c3.rotateLeftBits(24)))

proc textDistanceToLineStart*(self: TextEditor, fromCoord: Coord): float = 
  let line = self.lines[fromCoord.line]
  let spaceSize = igGetFont().calcTextSizeA(igGetFontSize(), float.high, -1f, " ").x
  let colIndex = self.getCharacterIndex(fromCoord)
  
  var it = 0
  while it < runeLen($line) and it < colIndex:
    let rune = line[it].rune
    if $rune == "\t":
      result = (1f + floor((1f + result) / (float(self.tabSize) * spaceSize))) * (float(self.tabSize) * spaceSize)
      inc it

    else:
      # var d = runeLen($line[it].rune)
      # var temp: string
      # var i = 0

      # while i < 6 and d > 0 and it < line.len:
      #   echo "Add ", line[it], " to temp"
      #   temp.add line[it].rune
      #   inc i
      #   inc it
      #   dec d

      let buf = 
        if it < line.len: 
          $line[it].rune
        else: ""

      if it < line.len:
        inc it

      result += igGetFont().calcTextSizeA(igGetFontSize(), float.high, -1f, cstring buf).x

proc hasSelection*(self: TextEditor): bool = 
  self.state.selectionEnd > self.state.selectionStart

proc ensureCursorVisible*(self: var TextEditor) = 
  if not self.withinRender:
    self.scrollToCursor = true
    return

  let scrollX = igGetScrollX()
  let scrollY = igGetScrollY()

  let height = igGetWindowHeight()
  let width = igGetWindowWidth()

  let top = 1 + int ceil(scrollY / self.charAdvance.y)
  let bottom = int ceil((scrollY + height) / self.charAdvance.y)

  let left = int ceil(scrollX / self.charAdvance.x)
  let right = int ceil((scrollX + width) / self.charAdvance.x)

  let pos = self.getActualCursorCoord()
  let length = self.textDistanceToLineStart(pos)

  if pos.line < top:
    igSetScrollY(max(0f, float(pos.line - 1) * self.charAdvance.y))
  if pos.line > bottom - 4:
    igSetScrollY(max(0f, float(pos.line + 4) * self.charAdvance.y - height))
  if length + self.textStart < left.float + 4:
    igSetScrollX(max(0f, length + self.textStart - 4))
  if length + self.textStart > right.float - 4:
    igSetScrollX(max(0f, length + self.textStart + 4 - width))

  # Ensure the cursor is visible and not blinking
  let timeEnd = getDuration()
  if timeEnd - self.startTime < self.blinkDur:
    self.startTime = timeEnd - self.blinkDur

proc handleKeyboardInputs*(self: var TextEditor)

proc handleMouseInputs*(self: var TextEditor)

proc colorize*(self: var TextEditor, froline = 0, lines = -1) = # FIXME How c++ deals when no arguments are passed 
  let toLine = if lines == -1: self.lines.len else: min(self.lines.len, froline + lines)
  self.colorRangeMin = min(self.colorRangeMin, froline)
  self.colorRangeMax = max(self.colorRangeMax, toLine)
  self.colorRangeMin = max(0, self.colorRangeMin)
  self.colorRangeMax = max(self.colorRangeMin, self.colorRangeMax)
  self.checkComments = true

proc colorizeRange*(self: var TextEditor, froline, toLine: int) = # FIXME
  if self.lines.len == 0 or froline >= toLine:
    return

  var buffer: string
  var matches: seq[string]
  var id: string

  let endLine = clamp(toLine, 0, self.lines.len)
  for i in froline..<endLine:
    let line = self.lines[i]

    if runeLen($line) == 0:
      continue

    for j in 0..line.high:
      buffer.add(line[j].rune)
      self.lines[i][j].colorIndex = PaletteIndex.Default # FIXME

    var cindex = 0

    while cindex < buffer.len: # FIXME
      var (hasTokenizeResult, token, tokenStart, tokenCol) = self.languageDef.tokenize(buffer[cindex..^1])

      if not hasTokenizeResult:
        # todo : remove
        #printf("using regex for %.*s\n", first + 10 < last ? 10 : int(last - first), first)

        for (pattern, color) in self.regexList:
          if (let tokenIdx = buffer[cindex..^1].find(pattern, matches); tokenIdx >= 0):
            hasTokenizeResult = true

            token = matches[0]
            tokenStart = tokenIdx
            tokenCol = color
            break

      if hasTokenizeResult:
        inc cindex
      else:
        if tokenCol == PaletteIndex.Identifier:
          id = token

          # todo : allmost all language definitions use lower case to specify keywords, so shouldn'at this use ::tolower ?
          if not self.languageDef.caseSensitive:
            id = id.toUpper()

          if not line[cindex].preprocessor:
            if self.languageDef.keywords.count(id) != 0:
              tokenCol = PaletteIndex.Keyword
            elif self.languageDef.identifiers.filterIt(it.str == id).len != 0:
              tokenCol = PaletteIndex.KnownIdentifier
            elif self.languageDef.preprocIdentifiers.filterIt(it.str == id).len != 0:
              tokenCol = PaletteIndex.PreprocIdentifier
          else:
            if self.languageDef.preprocIdentifiers.filterIt(it.str == id).len != 0:
              tokenCol = PaletteIndex.PreprocIdentifier       

        for j in 0..token.high:
          self.lines[i][tokenStart + j].colorIndex = tokenCol

        cindex = tokenStart + token.len

proc colorizeInternal*(self: var TextEditor) = 
  if self.lines.len == 0 or not self.colorizerEnabled:
    return

  if self.checkComments:
    let endLine = self.lines.len
    let endIndex = 0
    var commentStartLine = endLine
    var commentStartIndex = endIndex
    var withinString = false
    var withinSingleLineComment = false
    var withinPreproc = false
    var firstChar = true      # there is no other non-whitespace characters in the line before
    var concatenate = false   # '\' on the very end of the line
    var currentLine = 0
    var currentIndex = 0

    while currentLine < endLine or currentIndex < endIndex:
      let line = self.lines[currentLine]

      if currentIndex == 0 or not concatenate:
        withinSingleLineComment = false
        withinPreproc = false
        firstChar = true

      concatenate = false

      if runeLen($line) != 0:
        let glyph = line[currentIndex]
        let rune = $glyph.rune

        if rune != $self.languageDef.preprocChar and not rune.isSpace():
          firstChar = false

        if currentIndex == line.high and $line[line.high].rune == "\\":
          concatenate = true

        var inComment = commentStartLine < currentLine or (commentStartLine == currentLine and commentStartIndex <= currentIndex)

        if withinString:
          self.lines[currentLine][currentIndex].multiLineComment = inComment

          if $rune == "\"":
            if currentIndex < line.high and $line[currentIndex + 1].rune == "\"":
              currentIndex += 1
              if currentIndex < runeLen($line):
                self.lines[currentLine][currentIndex].multiLineComment = inComment

            else:
              withinString = false
         
          elif $rune == "\\":
            currentIndex += 1
            if currentIndex < runeLen($line):
              self.lines[currentLine][currentIndex].multiLineComment = inComment
       
        else:
          if firstChar and $rune == $self.languageDef.preprocChar:
            withinPreproc = true

          if $rune == "\"":
            withinString = true
            self.lines[currentLine][currentIndex].multiLineComment = inComment

          else:
            let pred = proc(a: char, b: Glyph): bool = a == ($b.rune)[0]
            let startStr = self.languageDef.commentStart
            let singleStartStr = self.languageDef.singleLineComment

            if (singleStartStr.len > 0 and 
              currentIndex + singleStartStr.len <= runeLen($line) and 
              ($line)[currentIndex..singleStartStr.len] == singleStartStr
            ):
              withinSingleLineComment = true
           
            elif (not withinSingleLineComment and
              currentIndex + startStr.len <= runeLen($line) and
              ($line)[currentIndex..startStr.len] == startStr
            ):
              commentStartLine = currentLine
              commentStartIndex = currentIndex
           
            # inComment = inComment = (commentStartLine < currentLine || (commentStartLine == currentLine && commentStartIndex <= currentIndex))
            inComment = commentStartLine < currentLine or (commentStartLine == currentLine and commentStartIndex <= currentIndex)

            self.lines[currentLine][currentIndex].multiLineComment = inComment
            self.lines[currentLine][currentIndex].comment = withinSingleLineComment

            let endStr = self.languageDef.commentEnd
            if (currentIndex + 1 >= endStr.len and
              ($line)[currentIndex + 1 - endStr.len..currentIndex + 1] == endStr
            ):
              commentStartIndex = endIndex
              commentStartLine = endLine
       
        self.lines[currentLine][currentIndex].preprocessor = withinPreproc
        inc currentIndex
        if currentIndex >= runeLen($line):
          currentIndex = 0
          inc currentLine     
      else:
        currentIndex = 0
        inc currentLine
   
    self.checkComments = false

  if self.colorRangeMin < self.colorRangeMax:
    let increment = 10000 # FIXME (mLanguageDefinition.mTokenize == nullptr) ? 10 : 10000
    let to = min(self.colorRangeMin + increment, self.colorRangeMax)
    self.colorizeRange(self.colorRangeMin, to)
    self.colorRangeMin = to

    if self.colorRangeMax == self.colorRangeMin:
      self.colorRangeMin = int.high
      self.colorRangeMax = 0
 
proc render*(self: var TextEditor) = 
  # Compute self.charAdvance regarding to scaled font size (Ctrl + ouse wheel)
  let fontSize = igGetFont().calcTextSizeA(igGetFontSize(), float.high, -1f, "#").x
  self.charAdvance = igVec2(fontSize, igGetTextlineHeightWithSpacing() * self.lineSpacing)

  # Update palette with the current alpha from style
  for col in PaletteIndex:
    var color = igColorConvertU32ToFloat4(self.paletteBase[ord col])
    color.w *= igGetStyle().alpha
    self.palette[ord col] = igColorConvertFloat4ToU32(color)
  
  assert self.lineBuffer.len == 0

  let contentSize = igGetWindowContentRegionMax()
  let drawList = igGetWindowDrawList()
  var longest = self.textStart

  if self.scrollToTop:
    self.scrollToTop = false
    igSetScrollY(0)

  let cursorScreenPos = igGetCursorScreenPos()
  let scrollX = igGetScrollX()
  let scrollY = igGetScrollY()

  var lineNo = int floor(scrollY / self.charAdvance.y)
  let globalLineMax = self.lines.len
  let lineMax = clamp(lineNo + int floor((scrollY + contentSize.y) / self.charAdvance.y), 0, self.lines.high)

  # Deduce self.textStart by evaluating self.lines size (global lineMax) plus two spaces s text width
  self.textStart = igGetFont().calcTextSizeA(igGetFontSize(), float.high, -1f, cstring &" {globalLineMax} ").x + self.leftMargin.float32

  if self.lines.len != 0:
    let spaceSize = igGetFont().calcTextSizeA(igGetFontSize(), float.high, -1f, cstring " ").x

    while lineNo <= lineMax:
      let lineStartScreenPos = igVec2(cursorScreenPos.x, cursorScreenPos.y + lineNo.float32 * self.charAdvance.y)
      let textScreenPos = igVec2(lineStartScreenPos.x + self.textStart, lineStartScreenPos.y)

      let line = self.lines[lineNo]
      longest = max(self.textStart + self.textDistanceToLineStart(coord(lineNo, self.getLineMaxColumn(lineNo))), longest)
      var columnNo = 0
      let lineStartCoord = coord(lineNo, 0)
      let lineEndCoord = coord(lineNo, self.getLineMaxColumn(lineNo))

      # Draw selection for the current line
      var sstart = -1f
      var ssend = -1f

      assert self.state.selectionStart <= self.state.selectionEnd

      if self.state.selectionStart <= lineEndCoord:
        sstart = if self.state.selectionStart > lineStartCoord: self.textDistanceToLineStart(self.state.selectionStart) else: 0f
      if self.state.selectionEnd > lineStartCoord:
        ssend = self.textDistanceToLineStart(if self.state.selectionEnd < lineEndCoord: self.state.selectionEnd else: lineEndCoord)

      if self.state.selectionEnd.line > lineNo:
        ssend += self.charAdvance.x

      if sstart != -1 and ssend != -1 and sstart < ssend:
        let vstart = igVec2(lineStartScreenPos.x + self.textStart + sstart, lineStartScreenPos.y)
        let vend = igVec2(lineStartScreenPos.x + self.textStart + ssend, lineStartScreenPos.y + self.charAdvance.y)
        drawList.addRectFilled(vstart, vend, self.palette[ord PaletteIndex.Selection])

      # Draw breakpoints
      let min = igVec2(lineStartScreenPos.x + scrollX, lineStartScreenPos.y)

      if self.breakpoints.count(lineNo + 1) != 0:
        let max = igVec2(lineStartScreenPos.x + contentSize.x + 2f * scrollX, lineStartScreenPos.y + self.charAdvance.y)
        drawList.addRectFilled(min, max, self.palette[ord PaletteIndex.Breakpoint])

      # Draw error markers
      let errors = self.errorMarkers.filterIt(it.line == lineNo + 1)
      if errors.len > 0:
        let max = igVec2(lineStartScreenPos.x + contentSize.x + 2f * scrollX, lineStartScreenPos.y + self.charAdvance.y)
        drawList.addRectFilled(min, max, self.palette[ord PaletteIndex.ErrorMarker])

        if igIsMouseHoveringRect(lineStartScreenPos, max):
          igBeginTooltip()

          igPushStyleColor(ImGuiCol.Text, igVec4(1f, 0.2f, 0.2f, 1f))
          igText(cstring &"Error at line {errors[0].line}:")
          igPopStyleColor()

          igSeparator()

          igPushStyleColor(ImGuiCol.Text, igVec4(1f, 1f, 0.2f, 1f))
          igText(cstring errors[0].error)
          igPopStyleColor()

          igEndTooltip()     

      # Draw line number (right ligned)
      let buf = &"{lineNo + 1}  "

      let lineNoWidth = igGetFont().calcTextSizeA(igGetFontSize(), float.high, -1f, cstring buf).x
      drawList.addText(igVec2(lineStartScreenPos.x + self.textStart - lineNoWidth, lineStartScreenPos.y), self.palette[ord PaletteIndex.LineNumber], cstring buf)

      if self.state.cursorPos.line == lineNo:
        let focused = igIsWindowFocused()

        # Highlight the current line (where the cursor is)
        if not self.hasSelection():
          let max = igVec2(min.x + contentSize.x + scrollX, min.y + self.charAdvance.y)
          drawList.addRectFilled(min, max, self.palette[ord(if focused: PaletteIndex.CurrentlineFill else: PaletteIndex.CurrentlineFillInactive)])
          drawList.addRect(min, max, self.palette[ord PaletteIndex.CurrentlineEdge], 1f)

        # Render the cursor
        if focused:
          let timeEnd = getDuration()
          let elapsed = timeEnd - self.startTime
          if elapsed > self.blinkDur:
            var width = 1f
            let cindex = self.getCharacterIndex(self.state.cursorPos)
            let cx = self.textDistanceToLineStart(self.state.cursorPos)

            if self.overwrite and cindex < runeLen($line):
              let rune = line[cindex].rune
              if $rune == "\t":
                let x = (1f + floor((1f + cx) / (self.tabSize.float * spaceSize))) * (self.tabSize.float * spaceSize)
                width = x - cx

              else:
                width = igGetFont().calcTextSizeA(igGetFontSize(), float.high, -1f, cstring $line[cindex].rune).x # FIXME

            let cstart = igVec2(textScreenPos.x + cx, lineStartScreenPos.y)
            let cend = igVec2(textScreenPos.x + cx + width, lineStartScreenPos.y + self.charAdvance.y)
            drawList.addRectFilled(cstart, cend, self.palette[ord PaletteIndex.Cursor])
            
            if elapsed > self.blinkDur * 2:
              self.startTime = timeEnd

      # Render colorized text
      var prevColor = if runeLen($line) == 0: self.palette[ord PaletteIndex.Default] else: self.getGlyphColor(line[0])
      var bufferOffset: ImVec2
      var i = 0
      while i < runeLen($line):
        let glyph = line[i]
        let color = self.getGlyphColor(glyph)

        if (color != prevColor or glyph.rune.ord == '\t'.ord or glyph.rune.ord == ' '.ord) and self.lineBuffer.len != 0:
          let newOffset = textScreenPos + bufferOffset
          drawList.addText(newOffset, prevColor, cstring self.lineBuffer)
          let textSize = igGetFont().calcTextSizeA(igGetFontSize(), float.high, -1f, cstring self.lineBuffer)
          bufferOffset.x += textSize.x
          self.lineBuffer.reset()
       
        prevColor = color

        if $glyph.rune == "\t":
          let oldX = bufferOffset.x
          bufferOffset.x = (1f + floor((1f + bufferOffset.x) / (self.tabSize.float * spaceSize))) * (self.tabSize.float * spaceSize)
          inc i

          if self.showWhitespaces:
            let s = igGetFontSize()
            let x1 = textScreenPos.x + oldX + 1f
            let x2 = textScreenPos.x + bufferOffset.x - 1f
            let y = textScreenPos.y + bufferOffset.y + s * 0.5f
            let p1 = igVec2(x1, y)
            let p2 = igVec2(x2, y)
            let p3 = igVec2(x2 - s * 0.2f, y - s * 0.2f)
            let p4 = igVec2(x2 - s * 0.2f, y + s * 0.2f)

            drawList.addLine(p1, p2, 0x90909090.uint32)
            drawList.addLine(p2, p3, 0x90909090.uint32)
            drawList.addLine(p2, p4, 0x90909090.uint32)
         
        elif $glyph.rune == " ":
          if self.showWhitespaces:
            let s = igGetFontSize()
            let x = textScreenPos.x + bufferOffset.x + spaceSize * 0.5f
            let y = textScreenPos.y + bufferOffset.y + s * 0.5f
            drawList.addCircleFilled(igVec2(x, y), 1.5f, 0x80808080.uint32, 4)
         
          bufferOffset.x += spaceSize
          inc i

        else:
          self.lineBuffer.add(line[i].rune)
          inc i

        inc columnNo
     
      if self.lineBuffer.len != 0:
        # echo "Drawing: ", self.lineBuffer
        let newOffset = textScreenPos + bufferOffset
        drawList.addText(newOffset, prevColor, cstring self.lineBuffer)
        self.lineBuffer.reset()

      inc lineNo

    # Draw a tooltip on known identifiers/preprocessor symbols
    if igIsMousePosValid():
      let id = self.getWordAt(self.screenPosToCoord(igGetMousePos()))
      if id.len != 0:
        let ids = self.languageDef.identifiers.filterIt(it.str == id)
        if ids.len > 0:
          igBeginTooltip()
          igTextUnformatted(cstring ids[0].id.declaration)
          igEndTooltip()
       
        else:
          let pis = self.languageDef.identifiers.filterIt(it.str == id)
          if pis.len > 0:
            igBeginTooltip()
            igTextUnformatted(cstring pis[0].id.declaration)
            igEndTooltip()

  igDummy(igVec2((longest + 2), self.lines.len.float * self.charAdvance.y))

  if self.scrollToCursor:
    self.ensureCursorVisible()
    igSetWindowFocus()
    self.scrollToCursor = false
 
proc render*(self: var TextEditor, title: string, size: ImVec2, border: bool) = 
  self.withinRender = true
  self.textChanged = false
  self.cursorPosChanged = false

  igPushStyleColor(ImGuiCol.ChildBg, igColorConvertU32ToFloat4(self.palette[ord PaletteIndex.Background]))
  igPushStyleVar(ImGuiStyleVar.ItemSpacing, igVec2(0f, 0f))
  if not self.ignoreImGuiChild:
    igBeginChild(cstring title, size, border, makeFlags(ImGuiWindowFlags.HorizontalScrollbar, ImGuiWindowFlags.NoMove))

  if self.hasKeyboardInputs:
    self.handleKeyboardInputs()
    igPushAllowKeyboardFocus(true)

  if self.hasMouseInputs:
    self.handleMouseInputs()

  self.colorizeInternal()
  self.render()

  if self.hasKeyboardInputs:
    igPopAllowKeyboardFocus()

  if not self.ignoreImGuiChild:
    igEndChild()

  igPopStyleVar()
  igPopStyleColor()

  self.withinRender = false

proc setText*(self: var TextEditor, text: string) = 
  self.lines.reset()
  self.lines.add(Line.default)
  
  for rune in text.runes:
    if $rune == "\r": discard # Ignore the carriage return character
    elif $rune == "\n":
      self.lines.add(Line.default)
    else:
      self.lines[^1].add(glyph(rune, PaletteIndex.Default) )

  self.textChanged = true
  self.scrollToTop = true

  self.undoBuffer.reset()
  self.undoIndex = 0

  self.colorize()

proc setTextlines*(self: var TextEditor, lines: seq[string]) = 
  self.lines.reset()

  if lines.len == 0:
    self.lines.add(Line.default)
 
  else:
    for line in lines:
      self.lines.add(Line.default)
      for rune in line.runes:
        self.lines[^1].add(glyph(rune, PaletteIndex.Default) )

  self.textChanged = true
  self.scrollToTop = true

  self.undoBuffer.reset()
  self.undoIndex = 0

  self.colorize()

proc setCursorPos*(self: var TextEditor, pos: Coord) = 
  if self.state.cursorPos != pos:
    self.state.cursorPos = pos
    self.cursorPosChanged = true
    self.ensureCursorVisible()

proc setSelectionStart*(self: var TextEditor, pos: Coord) = 
  self.state.selectionStart = self.sanitizeCoord(pos)
  if self.state.selectionStart > self.state.selectionEnd:
    swap(self.state.selectionStart, self.state.selectionEnd)

proc setSelectionEnd*(self: var TextEditor, pos: Coord) = 
  self.state.selectionEnd = self.sanitizeCoord(pos)
  if self.state.selectionStart > self.state.selectionEnd:
    swap(self.state.selectionStart, self.state.selectionEnd)

proc setSelection*(self: var TextEditor, startCoord, endCoord: Coord, mode: SelectionMode = SelectionMode.Normal) = 
  let oldSelStart = self.state.selectionStart
  let oldSelEnd = self.state.selectionEnd

  self.state.selectionStart = self.sanitizeCoord(startCoord)
  self.state.selectionEnd = self.sanitizeCoord(endCoord)

  if self.state.selectionStart > self.state.selectionEnd:
    swap(self.state.selectionStart, self.state.selectionEnd)

  case mode
  of SelectionMode.Normal: discard
  of SelectionMode.Word:
    self.state.selectionStart = self.findWordStart(self.state.selectionStart)
    if not self.isOnWordBoundary(self.state.selectionEnd):
      self.state.selectionEnd = self.findWordEnd(self.findWordStart(self.state.selectionEnd)) 
  of SelectionMode.Line:
    let lineNo = self.state.selectionEnd.line
    let lineSize = if lineNo < self.lines.len: self.lines[lineNo].len else: 0
    
    self.state.selectionStart = coord(self.state.selectionStart.line, 0)
    self.state.selectionEnd = coord(lineNo, self.getLineMaxColumn(lineNo))

  if self.state.selectionStart != oldSelStart or self.state.selectionEnd != oldSelEnd:
    self.cursorPosChanged = true

proc `tabSize=`*(self: var TextEditor, value: range[0..32]) = 
  self.tabSize = value

proc insertText*(self: var TextEditor, value: string) = 
  var pos = self.getActualCursorCoord()
  let start = min(pos, self.state.selectionStart)
  var totalLines = pos.line - start.line

  echo "Insert at ", pos
  totalLines += self.insertTextAt(pos, value)

  self.setSelection(pos, pos)
  self.setCursorPos(pos)
  self.colorize(start.line - 1, totalLines + 2)

proc deleteSelection*(self: var TextEditor) = 
  assert self.state.selectionEnd >= self.state.selectionStart

  if self.state.selectionEnd == self.state.selectionStart:
    return

  self.deleteRange(self.state.selectionStart, self.state.selectionEnd)

  self.setSelection(self.state.selectionStart, self.state.selectionStart)
  self.setCursorPos(self.state.selectionStart)
  self.colorize(self.state.selectionStart.line, 1)

proc enterCharacter*(self: var TextEditor, rune: Rune, shift: bool) = # FIXME ImWchar
  assert not self.readOnly

  var u: UndoRecord
  u.before = self.state

  if self.hasSelection():
    if $rune == "\t" and self.state.selectionStart.line != self.state.selectionEnd.line:
      var startCoord = self.state.selectionStart
      var endCoord = self.state.selectionEnd
      let originalEnd = endCoord

      if startCoord > endCoord:
        swap(startCoord, endCoord)

      startCoord.col = 0
      #      endCoord.col = endCoord.line < self.lines.len ? self.lines[endCoord.line].len : 0
      if endCoord.col == 0 and endCoord.line > 0:
        dec endCoord.line
      if endCoord.line >= self.lines.len:
        endCoord.line = self.lines.high # FIXME
      endCoord.col = self.getLineMaxColumn(endCoord.line)

      #if (endCoord.col >= getLineMaxColumn(endCoord.line)):
      #  endCoord.col = getLineMaxColumn(endCoord.line) - 1

      u.removedStart = startCoord
      u.removedEnd = endCoord
      u.removed = self.getText(startCoord, endCoord)

      var modified = false

      for i in startCoord.line..endCoord.line:
        let line = self.lines[i]
        if shift:
          if runeLen($line) != 0:
            if $line[0].rune == "\t":
              self.lines[i].delete(0)
              modified = true
           
          else:
            for j in 0..<self.tabSize: # FIXME
              if runeLen($line) > 0 and $line[0].rune == " ":
                self.lines[i].delete(0)
                modified = true
        else:
          self.lines[i].insert(glyph("\t", PaletteIndex.Background), 0)
          modified = true

      if modified:
        startCoord = coord(startCoord.line, self.getCharacterColumn(startCoord.line, 0))        
        var rangeEnd: Coord

        if originalEnd.col != 0:
          endCoord = coord(endCoord.line, self.getLineMaxColumn(endCoord.line))
          rangeEnd = endCoord
          u.added = self.getText(startCoord, endCoord)
        else:
          endCoord = coord(originalEnd.line, 0)
          rangeEnd = coord(endCoord.line - 1, self.getLineMaxColumn(endCoord.line - 1))
          u.added = self.getText(startCoord, rangeEnd)

        u.addedStart = startCoord
        u.addedEnd = rangeEnd
        u.after = self.state

        self.state.selectionStart = startCoord
        self.state.selectionEnd = endCoord
        self.addUndo(u)

        self.textChanged = true

        self.ensureCursorVisible()

      return
    # c == '\t'
    else:
      u.removed = self.getSelectedText()
      u.removedStart = self.state.selectionStart
      u.removedEnd = self.state.selectionEnd
      self.deleteSelection()
   
  # HasSelection
  let coord = self.getActualCursorCoord()
  u.addedStart = coord

  assert self.lines.len != 0

  if rune.ord == '\n'.ord:
    self.insertLine(coord.line + 1)
    let line = self.lines[coord.line]

    if self.languageDef.autoIndentation: # Indent with the same indentation as the previous line
      for i in 0..line.high:
        if isSpace($line[i].rune):
          self.lines[coord.line + 1].add(line[i])
        else:
          break

    let whitespaceSize = self.lines[coord.line + 1].len
    let cindex = self.getCharacterIndex(coord)
    
    self.lines[coord.line + 1].add(line[cindex..^1])
    
    if self.lines[coord.line].len > 0 and cindex < self.lines[coord.line].len:
      self.lines[coord.line].delete(cindex..self.lines[coord.line].high)

    self.setCursorPos(coord(coord.line + 1, self.getCharacterColumn(coord.line + 1, whitespaceSize)))
    
    u.added = $rune
  else:
    var buf = $rune

    if buf.runeLen > 0:
      let line = self.lines[coord.line]
      var cindex = self.getCharacterIndex(coord)

      if self.overwrite and cindex < runeLen($line):

        u.removedStart = self.state.cursorPos
        u.removedEnd = coord(coord.line, self.getCharacterColumn(coord.line, cindex + 1))

        u.removed.add(line[cindex].rune)
        self.lines[coord.line].delete(cindex)

      for p in buf.runes:
        self.lines[coord.line].insert(glyph(p, PaletteIndex.Default), cindex)
        inc cindex

      u.added = buf

      self.setCursorPos(coord(coord.line, self.getCharacterColumn(coord.line, cindex)))

    else:
      return
 

  self.textChanged = true

  u.addedEnd = self.getActualCursorCoord()
  u.after = self.state

  self.addUndo(u)

  self.colorize(coord.line - 1, 3)
  self.ensureCursorVisible()

proc moveUp*(self: var TextEditor, amount: int, select: bool) = 
  let oldPos = self.state.cursorPos
  self.state.cursorPos.line = max(0, self.state.cursorPos.line - amount)
  if oldPos != self.state.cursorPos:
    if select:
      if oldPos == self.interactiveStart:
        self.interactiveStart = self.state.cursorPos
      elif oldPos == self.interactiveEnd:
        self.interactiveEnd = self.state.cursorPos
      else:
        self.interactiveStart = self.state.cursorPos
        self.interactiveEnd = oldPos     
    else:
      self.interactiveStart = self.state.cursorPos
      self.interactiveEnd = self.interactiveStart

    self.setSelection(self.interactiveStart, self.interactiveEnd)
    self.ensureCursorVisible()

proc moveDown*(self: var TextEditor, amount: int, select: bool) = 
  assert self.state.cursorPos.col >= 0

  let oldPos = self.state.cursorPos
  self.state.cursorPos.line = clamp(self.state.cursorPos.line + amount, 0, self.lines.high)

  if self.state.cursorPos != oldPos:
    if select:
      if oldPos == self.interactiveEnd:
        self.interactiveEnd = self.state.cursorPos
      elif oldPos == self.interactiveStart:
        self.interactiveStart = self.state.cursorPos
      else:
        self.interactiveStart = oldPos
        self.interactiveEnd = self.state.cursorPos   
    else:
      self.interactiveStart = self.state.cursorPos
      self.interactiveEnd = self.interactiveStart

    self.setSelection(self.interactiveStart, self.interactiveEnd)

    self.ensureCursorVisible()

proc moveLeft*(self: var TextEditor, amount: int, select, wordMode: bool) = 
  if self.lines.len == 0:
    return

  let oldPos = self.state.cursorPos
  self.state.cursorPos = self.getActualCursorCoord()
  
  var line = self.state.cursorPos.line
  var cindex = self.getCharacterIndex(self.state.cursorPos)

  for i in countdown(amount, 1):
    if cindex == 0:
      if line > 0:
        dec line
        if self.lines.len > line:
          cindex = self.lines[line].len
        else:
          cindex = 0

    else:
      dec cindex
      # if cindex > 0: # What does this code do?
      #   if self.lines.len > line:
      #     while cindex > 0 and isUTF8($self.lines[line][cindex].rune):
      #       echo "Decreaseng ", cindex
      #       dec cindex

    self.state.cursorPos = coord(line, self.getCharacterColumn(line, cindex))

    if wordMode:
      self.state.cursorPos = self.findWordStart(self.state.cursorPos)
      cindex = self.getCharacterIndex(self.state.cursorPos)

  self.state.cursorPos = coord(line, self.getCharacterColumn(line, cindex))

  assert self.state.cursorPos.col >= 0

  if select:
    if oldPos == self.interactiveStart:
      self.interactiveStart = self.state.cursorPos
    elif oldPos == self.interactiveEnd:
      self.interactiveEnd = self.state.cursorPos
    else:
      self.interactiveStart = self.state.cursorPos
      self.interactiveEnd = oldPos

  else:
    self.interactiveStart = self.state.cursorPos
    self.interactiveEnd = self.interactiveStart
  
  self.setSelection(self.interactiveStart, self.interactiveEnd, if select and wordMode: SelectionMode.Word else: SelectionMode.Normal)
  self.ensureCursorVisible()

proc moveRight*(self: var TextEditor, amount: int, select, wordMode: bool) = 
  let oldPos = self.state.cursorPos

  if self.lines.len == 0 or oldPos.line >= self.lines.len:
    return

  var cindex = self.getCharacterIndex(self.state.cursorPos)
  for i in countdown(amount, 1):
    let lindex = self.state.cursorPos.line
    let line = self.lines[lindex]

    if cindex >= runeLen($line):
      if self.state.cursorPos.line < self.lines.high:
        self.state.cursorPos.line = clamp(self.state.cursorPos.line + 1, 0, self.lines.high)
        self.state.cursorPos.col = 0
      else:
        return
   
    else:
      inc cindex
      self.state.cursorPos = coord(lindex, self.getCharacterColumn(lindex, cindex))
      if wordMode:
        self.state.cursorPos = self.findNextWord(self.state.cursorPos) 

  if select:
    if oldPos == self.interactiveEnd:
      self.interactiveEnd = self.sanitizeCoord(self.state.cursorPos)
    elif oldPos == self.interactiveStart:
      self.interactiveStart = self.state.cursorPos
    else:
      self.interactiveStart = oldPos
      self.interactiveEnd = self.state.cursorPos
 
  else:
    self.interactiveStart = self.state.cursorPos
    self.interactiveEnd = self.interactiveStart

  self.setSelection(self.interactiveStart, self.interactiveEnd, if select and wordMode: SelectionMode.Word else: SelectionMode.Normal)
  self.ensureCursorVisible()

proc moveTop*(self: var TextEditor, select: bool) = 
  let oldPos = self.state.cursorPos
  self.setCursorPos(coord(0, 0))

  if self.state.cursorPos != oldPos:
    if select:
      self.interactiveEnd = oldPos
      self.interactiveStart = self.state.cursorPos
    else:
      self.interactiveStart = self.state.cursorPos
      self.interactiveEnd = self.interactiveStart

    self.setSelection(self.interactiveStart, self.interactiveEnd)

proc moveBottom*(self: var TextEditor, select: bool) = 
  let oldPos = self.getCursorPos()
  let newPos = coord(self.lines.high, 0)
  self.setCursorPos(newPos)

  if select:
    self.interactiveStart = oldPos
    self.interactiveEnd = newPos
  else:
    self.interactiveStart = self.state.cursorPos
    self.interactiveEnd = self.interactiveStart

  self.setSelection(self.interactiveStart, self.interactiveEnd)

proc moveHome*(self: var TextEditor, select: bool) = 
  let oldPos = self.state.cursorPos
  self.setCursorPos(coord(self.state.cursorPos.line, 0))

  if self.state.cursorPos != oldPos:
    if select:
      if oldPos == self.interactiveStart:
        self.interactiveStart = self.state.cursorPos
      elif oldPos == self.interactiveEnd:
        self.interactiveEnd = self.state.cursorPos
      else:
        self.interactiveStart = self.state.cursorPos
        self.interactiveEnd = oldPos

    else:
      self.interactiveStart = self.state.cursorPos
      self.interactiveEnd = self.interactiveStart

    self.setSelection(self.interactiveStart, self.interactiveEnd)

proc moveEnd*(self: var TextEditor, select: bool) = 
  let oldPos = self.state.cursorPos
  self.setCursorPos(coord(self.state.cursorPos.line, self.getLineMaxColumn(oldPos.line)))

  if self.state.cursorPos != oldPos:
    if select:
      if oldPos == self.interactiveEnd:
        self.interactiveEnd = self.state.cursorPos
      elif oldPos == self.interactiveStart:
        self.interactiveStart = self.state.cursorPos
      else:
        self.interactiveStart = oldPos
        self.interactiveEnd = self.state.cursorPos

    else:
      self.interactiveStart = self.state.cursorPos
      self.interactiveEnd = self.interactiveStart

    self.setSelection(self.interactiveStart, self.interactiveEnd) 

proc delete*(self: var TextEditor, wordMode: bool) = # Delete next character
  assert not self.readOnly

  if self.lines.len == 0:
    return

  var u: UndoRecord
  u.before = self.state

  if self.hasSelection():
    u.removed = self.getSelectedText()
    u.removedStart = self.state.selectionStart
    u.removedEnd = self.state.selectionEnd

    self.deleteSelection()
 
  else:
    let pos = self.getActualCursorCoord()
    self.setCursorPos(pos)
    let line = self.lines[pos.line]

    if pos.col == self.getLineMaxColumn(pos.line):
      if pos.line == self.lines.high:
        return

      u.removed = "\n"
      u.removedStart = self.getActualCursorCoord()
      u.removedEnd = u.removedStart
      self.advance(u.removedEnd)

      let nextline = self.lines[pos.line + 1]
      self.lines[pos.line].add(nextline)
      self.removeline(pos.line + 1)
   
    else:
      let cindex = self.getCharacterIndex(pos)
      u.removedStart = self.getActualCursorCoord()
      u.removedEnd = self.getActualCursorCoord()
      inc u.removedEnd.col
      u.removed = self.getText(u.removedStart, u.removedEnd)

      echo self.findNextWord(self.state.cursorPos)
      for i in 0..0:
        if cindex < runeLen($line):
          self.lines[pos.line].delete(cindex)

    self.textChanged = true

    self.colorize(pos.line, 1)

  u.after = self.state
  self.addUndo(u)

proc backspace*(self: var TextEditor) =  # Delete previous character
  assert not self.readOnly

  if self.lines.len == 0:
    return

  var u: UndoRecord
  u.before = self.state

  if self.hasSelection():
    u.removed = self.getSelectedText()
    u.removedStart = self.state.selectionStart
    u.removedEnd = self.state.selectionEnd

    self.deleteSelection()
 
  else:
    let pos = self.getActualCursorCoord()
    self.setCursorPos(pos)

    if self.state.cursorPos.col == 0:
      if self.state.cursorPos.line == 0:
        return

      u.removed = "\n"
      u.removedStart = coord(pos.line - 1, self.getLineMaxColumn(pos.line - 1))
      u.removedEnd = u.removedStart
      self.advance(u.removedEnd)

      let line = self.lines[self.state.cursorPos.line]
      var prevline = self.lines[self.state.cursorPos.line - 1]
      let prevSize = self.getLineMaxColumn(self.state.cursorPos.line - 1)
      prevline.add(line)

      for e, (line, error) in self.errorMarkers:
        self.errorMarkers[e] = ((if line - 1 == self.state.cursorPos.line: line - 1 else: line), error)

      self.removeLine(self.state.cursorPos.line)
      dec self.state.cursorPos.line
      self.state.cursorPos.col = prevSize

    else:
      let line = self.lines[self.state.cursorPos.line]
      var cindex = self.getCharacterIndex(pos) - 1
      var cend = cindex + 1

      while cindex > 0 and isUTF8($line[cindex].rune):
        dec cindex

      #if (cindex > 0 && UTF8CharLength(line[cindex].char) > 1)
      #  --cindex

      u.removedStart = self.getActualCursorCoord()
      u.removedEnd = u.removedStart

      dec u.removedStart.col
      dec self.state.cursorPos.col

      while cindex < runeLen($line) and cend > cindex:
        u.removed.add(line[cindex].rune)
        self.lines[self.state.cursorPos.line].delete(cindex)
        dec cend

    self.textChanged = true

    self.ensureCursorVisible()
    self.colorize(self.state.cursorPos.line, 1)
 
  u.after = self.state
  self.addUndo(u)

proc selectWordUnderCursor*(self: var TextEditor) = 
  let c = self.getCursorPos()
  self.setSelection(self.findWordStart(c), self.findWordEnd(c))

proc selectAll*(self: var TextEditor) = 
  self.setSelection(coord(0, 0), coord(self.lines.len, 0))

proc copy*(self: TextEditor) = 
  if self.hasSelection():
    igSetClipboardText(cstring self.getSelectedText())
 
  else:
    if self.lines.len != 0:
      var str: string
      let line = self.lines[self.getActualCursorCoord().line]
      for g in line:
        str.add(g.rune)

      igSetClipboardText(cstring str)

proc cut*(self: var TextEditor) = 
  if self.readOnly:
    self.copy()
  else:
    if self.hasSelection():
      var u: UndoRecord
      u.before = self.state
      u.removed = self.getSelectedText()
      u.removedStart = self.state.selectionStart
      u.removedEnd = self.state.selectionEnd

      self.copy()
      self.deleteSelection()

      u.after = self.state
      self.addUndo(u)

proc paste*(self: var TextEditor) = 
  if self.readOnly:
    return

  let clipText = igGetClipboardText()
  if not clipText.isNil and clipText.len > 0:
    var u: UndoRecord
    u.before = self.state

    if self.hasSelection():
      u.removed = self.getSelectedText()
      u.removedStart = self.state.selectionStart
      u.removedEnd = self.state.selectionEnd
      self.deleteSelection()

    u.added = $clipText
    u.addedStart = self.getActualCursorCoord()

    self.insertText($clipText)

    u.addedEnd = self.getActualCursorCoord()
    u.after = self.state
    self.addUndo(u)

proc getDarkPalette*(): Palette = 
  [
    0xff7f7f7f.uint32, # Default
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
  ]

proc getLightPalette*(): Palette = 
  [
    0xff7f7f7f.uint32, # None
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
    0x80600000.uint32, # Selection
    0xa00010ff.uint32, # ErrorMarker
    0x80f08000.uint32, # Breakpoint
    0xff505000.uint32, # Line number
    0x40000000.uint32, # Current line fill
    0x40808080.uint32, # Current line fill (inactive)
    0x40000000.uint32, # Current line edge
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
  ]

proc getCurrentLineText*(self: TextEditor): string = 
  let lineLength = self.getLineMaxColumn(self.state.cursorPos.line)
  self.getText(coord(self.state.cursorPos.line, 0), coord(self.state.cursorPos.line, lineLength))

proc processInputs*(self: TextEditor) = discard # FIXME

proc `languageDef=`*(self: var TextEditor, def: LanguageDef) = 
  self.languageDef = def
  self.regexList.reset()

  for r in def.tokenRegexStrings:
    self.regexList.add((re(r[0]), r[1]))

  self.colorize()

proc getPageSize*(self: TextEditor): int = 
  let height = igGetWindowHeight() - 20f
  result = int floor(height / self.charAdvance.y)

proc undo*(rec: UndoRecord, editor: var TextEditor) = 
  if rec.added.len != 0:
    editor.deleteRange(rec.addedStart, rec.addedEnd)
    editor.colorize(rec.addedStart.line - 1, rec.addedEnd.line - rec.addedStart.line + 2)

  if rec.removed.len != 0:
    var start = rec.removedStart
    discard editor.insertTextAt(start, rec.removed)
    editor.colorize(rec.removedStart.line - 1, rec.removedEnd.line - rec.removedStart.line + 2)

  editor.state = rec.before
  editor.ensureCursorVisible()

proc redo*(rec: UndoRecord, editor: var TextEditor) = 
  if rec.removed.len != 0:
    editor.deleteRange(rec.removedStart, rec.removedEnd)
    editor.colorize(rec.removedStart.line - 1, rec.removedEnd.line - rec.removedStart.line + 1)

  if rec.added.len != 0:
    var start = rec.addedStart
    discard editor.insertTextAt(start, rec.added)
    editor.colorize(rec.addedStart.line - 1, rec.addedEnd.line - rec.addedStart.line + 1)

  editor.state = rec.after
  editor.ensureCursorVisible()

proc canUndo*(self: TextEditor): bool =
  self.readOnly and self.undoIndex > 0 # FIXME self.undoIndex >= 0 (?)

proc canRedo*(self: TextEditor): bool = 
  self.readOnly and self.undoIndex < self.undoBuffer.len

proc undo*(self: var TextEditor, steps: int) = 
  for i in countdown(steps, 0):
    if self.canUndo():
      self.undoBuffer[self.undoIndex].undo(self)
      dec self.undoIndex

proc redo*(self: var TextEditor, steps: int) = 
  for i in countdown(steps, 0):
    self.undoBuffer[self.undoIndex].redo(self)
    inc self.undoIndex

proc handleKeyboardInputs*(self: var TextEditor) = 
  let io = igGetIO()
  let shift = io.keyshift
  let ctrl = if io.configMacOSXBehaviors: io.keySuper else: io.keyCtrl
  let alt = if io.configMacOSXBehaviors: io.keyCtrl else: io.keyAlt

  if igIsWindowFocused():
    if igIsWindowHovered():
      igSetMouseCursor(ImGuiMouseCursor.TextInput)
    #igCaptureKeyboardFromApp(true)

    io.wantCaptureKeyboard = true
    io.wantTextInput = true

    if not self.readOnly and ctrl and not shift and not alt and igIsKeyPressedMap(ImGuiKey.Z):
      self.undo(1)
    elif not self.readOnly and not ctrl and not shift and alt and igIsKeyPressedMap(ImGuiKey.Backspace):
      self.undo(1)
    elif not self.readOnly and ctrl and not shift and not alt and igIsKeyPressedMap(ImGuiKey.Y):
      self.redo(1)
    elif not ctrl and not alt and igIsKeyPressedMap(ImGuiKey.UpArrow):
      self.moveUp(1, shift)
    elif not ctrl and not alt and igIsKeyPressedMap(ImGuiKey.DownArrow):
      self.moveDown(1, shift)
    elif not alt and igIsKeyPressedMap(ImGuiKey.LeftArrow):
      self.moveLeft(1, shift, ctrl)
    elif not alt and igIsKeyPressedMap(ImGuiKey.RightArrow):
      self.moveRight(1, shift, ctrl)
    elif not alt and igIsKeyPressedMap(ImGuiKey.PageUp):
      self.moveUp(self.getPageSize() - 4, shift)
    elif not alt and igIsKeyPressedMap(ImGuiKey.PageDown):
      self.moveDown(self.getPageSize() - 4, shift)
    elif not alt and ctrl and igIsKeyPressedMap(ImGuiKey.Home):
      self.moveTop(shift)
    elif ctrl and not alt and igIsKeyPressedMap(ImGuiKey.End):
      self.moveBottom(shift)
    elif not ctrl and not alt and igIsKeyPressedMap(ImGuiKey.Home):
      self.moveHome(shift)
    elif not ctrl and not alt and igIsKeyPressedMap(ImGuiKey.End):
      self.moveEnd(shift)
    elif not self.readOnly and not shift and not alt and igIsKeyPressedMap(ImGuiKey.Delete):
      self.delete(ctrl)
    elif not self.readOnly and not ctrl and not shift and not alt and igIsKeyPressedMap(ImGuiKey.Backspace):
      self.backspace()
    elif not ctrl and not shift and not alt and igIsKeyPressedMap(ImGuiKey.Insert):
      self.overwrite = not self.overwrite # FIXME
    elif ctrl and not shift and not alt and igIsKeyPressedMap(ImGuiKey.Insert):
      self.copy()
    elif ctrl and not shift and not alt and igIsKeyPressedMap(ImGuiKey.C):
      self.copy()
    elif not self.readOnly and not ctrl and shift and not alt and igIsKeyPressedMap(ImGuiKey.Insert):
      self.paste()
    elif not self.readOnly and ctrl and not shift and not alt and igIsKeyPressedMap(ImGuiKey.V):
      self.paste()
    elif ctrl and not shift and not alt and igIsKeyPressedMap(ImGuiKey.X):
      self.cut()
    elif not ctrl and shift and not alt and igIsKeyPressedMap(ImGuiKey.Delete):
      self.cut()
    elif ctrl and not shift and not alt and igIsKeyPressedMap(ImGuiKey.A):
      self.selectAll()
    elif not self.readOnly and not ctrl and not shift and not alt and igIsKeyPressedMap(ImGuiKey.Enter):
      self.enterCharacter(runeAt("\n", 0), false)
    elif not self.readOnly and not ctrl and not alt and igIsKeyPressedMap(ImGuiKey.Tab):
      self.enterCharacter(runeAt("\t", 0), shift)

    if not self.readOnly and io.inputQueueCharacters.size != 0:
      for i in 0..<io.inputQueueCharacters.size:
        let rune = io.inputQueueCharacters.data[i].Rune
        echo "Detected ", rune
        if rune.ord != 0 and (rune.ord == '\n'.ord or rune.ord >= 32):
          echo "Enter ", rune
          self.enterCharacter(rune, shift)

      io.inputQueueCharacters.size = 0 

proc handleMouseInputs*(self: var TextEditor) = 
  let io = igGetIO()
  let shift = io.keyshift
  let ctrl = if io.configMacOSXBehaviors: io.keySuper else: io.keyCtrl
  let alt = if io.configMacOSXBehaviors: io.keyCtrl else: io.keyAlt

  if igIsWindowHovered():
    let click = (not shift and not alt) and igIsMouseClicked(ImGuiMouseButton.Left)
    let doubleClick = igIsMouseDoubleClicked(ImGuiMouseButton.Left)
    let time = igGetTime()
    let tripleClick = click and not doubleClick and (self.lastClick != -1f and (time - self.lastClick) < io.mouseDoubleClickTime)

    # Left ouse button triple click

    if tripleClick:
      if not ctrl:
        self.state.cursorPos = self.screenPosToCoord(igGetMousePos())
        self.interactiveStart = self.state.cursorPos
        self.interactiveEnd = self.state.cursorPos
        self.selectionMode = SelectionMode.Line
        self.setSelection(self.interactiveStart, self.interactiveEnd, self.selectionMode)

      self.lastClick = -1f

    # Left ouse button double click
    elif doubleClick:
      if not ctrl:
        self.state.cursorPos = self.screenPosToCoord(igGetMousePos())
        self.interactiveStart = self.state.cursorPos
        self.interactiveEnd = self.state.cursorPos
        if self.selectionMode == SelectionMode.Line:
          self.selectionMode = SelectionMode.Normal
        else:
          self.selectionMode = SelectionMode.Word

        self.setSelection(self.interactiveStart, self.interactiveEnd, self.selectionMode)

      self.lastClick = igGetTime()

    # Left ouse button click
    elif click:
      self.state.cursorPos = self.screenPosToCoord(igGetMousePos())
      self.interactiveStart = self.state.cursorPos
      self.interactiveEnd = self.state.cursorPos
      if ctrl:
        self.selectionMode = SelectionMode.Word
      else:
        self.selectionMode = SelectionMode.Normal

      self.setSelection(self.interactiveStart, self.interactiveEnd, self.selectionMode)
      self.lastClick = igGetTime()
   
    # ouse left button dragging (=> update selection)
    elif igIsMouseDragging(ImGuiMouseButton.Left) and igIsMouseDown(ImGuiMouseButton.Left):
      io.wantCaptureMouse = true
      self.interactiveEnd = self.screenPosToCoord(igGetMousePos())
      self.state.cursorPos = self.interactiveEnd

      self.setSelection(self.interactiveStart, self.interactiveEnd, self.selectionMode)

proc initTextEditor*(
  lineSpacing: float = 1f, 
  lines: Lines = @[Line.default], 
  state: EditorState = EditorState.default, 
  undoBuffer: UndoBuffer = UndoBuffer.default, 
  undoIndex: int = 0, 
  blinkMs: int = 800, 
  tabSize: int = 2,
  overwrite: bool = false, 
  readOnly: bool = false, 
  withinRender: bool = false, 
  scrollToCursor: bool = false, 
  scrollToTop: bool = false, 
  textChanged: bool = false, 
  colorizerEnabled: bool = false, 
  textStart: float = 20f, 
  leftMargin: int = 10, 
  cursorPosChanged: bool = false, 
  colorRangeMin, colorRangeMax: int = 0, 
  selectionMode: SelectionMode = SelectionMode.Normal, 
  hasKeyboardInputs: bool = true, 
  hasMouseInputs: bool = true, 
  ignoreImGuiChild: bool = false, 
  showWhitespaces: bool = true, 
  paletteBase: Palette = getDarkPalette(), 
  palette: Palette = Palette.default, 
  languageDef: LanguageDef = LanguageDef.default, 
  regexList: RegexList = RegexList.default, 
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
    colorizerEnabled: colorizerEnabled, 
    textStart: textStart, 
    leftMargin: leftMargin, 
    cursorPosChanged: cursorPosChanged, 
    colorRangeMin: colorRangeMin, colorRangeMax: colorRangeMax, 
    selectionMode: selectionMode, 
    hasKeyboardInputs: hasKeyboardInputs, 
    hasMouseInputs: hasMouseInputs, 
    ignoreImGuiChild: ignoreImGuiChild, 
    showWhitespaces: showWhitespaces, 
    paletteBase: paletteBase, 
    palette: palette, 
    languageDef: languageDef, 
    regexList: regexList, 
    checkComments: checkComments, 
    breakpoints: breakpoints, 
    errorMarkers: errorMarkers, 
    charAdvance: charAdvance, 
    interactiveStart: interactiveStart, interactiveEnd: interactiveEnd, 
    lineBuffer: lineBuffer, 
    startTime: startTime, 
    lastClick: lastClick, 
  )
