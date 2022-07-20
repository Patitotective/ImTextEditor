import std/[strformat, sequtils, strutils, unicode, bitops, times, math, re]
import nimgl/imgui

import imtexteditor/[langdefs, utils]

export langdefs, utils

var hasEcho = false

proc getLineLength*(self: TextEditor, lineNo: int): int = 
  if lineNo >= self.lines.len:
    return 0
  
  result = self.lines[lineNo].len

proc getText*(self: TextEditor, startCoord, endCoord: Coord): string = 
  var lstart = startCoord.line
  var istart = startCoord.col
  let lend = endCoord.line
  let iend = endCoord.col

  while istart < iend or lstart < lend:
    if hasEcho: echo "getText"
    if lstart >= self.lines.len:
      break

    let line = self.lines[lstart]
    if istart < line.len:
      result.add(line[istart].rune)
    else:
      istart = 0
      result.add('\n')
      inc lstart

    inc istart

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
      result.col = self.getLineLength(result.line)
  else:
    result.col = if self.lines.len == 0: 0 else: min(result.col, self.getLineLength(result.line))

proc getCursorCoord*(self: TextEditor): Coord = 
  self.sanitizeCoord(self.state.cursorPos)

proc getTotalLines*(self: TextEditor): int = 
  self.lines.len

proc advance(self: TextEditor, coord: var Coord) = 
  if coord.line < self.lines.len:
    let line = self.lines[coord.line]
    var cindex = coord.col

    if cindex + 1 < line.len:
      inc cindex
    else:
      inc coord.line
      cindex = 0

    coord.col = cindex

proc removeLines*(self: var TextEditor, startL, endL: int) = 
  assert not self.readOnly
  assert endL >= startL
  assert self.lines.len > (endL - startL)

  let endL = min(self.lines.high, endL)

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

proc removeLine*(self: var TextEditor, index: int) =  # FIXME
  self.removeLines(index, index)

proc deleteRange*(self: var TextEditor, startCoord, endCoord: Coord) = 
  assert not self.readOnly

  if startCoord >= endCoord:
    return

  let istart = startCoord.col
  let iend = endCoord.col

  if startCoord.line == endCoord.line:
    # Delete until the end of the line if the requested column is greater than the line length
    if endCoord.col >= self.getLineLength(startCoord.line):
      self.lines[startCoord.line].delete(istart..^1)
    else:
      self.lines[startCoord.line].delete(istart..iend)

  else:
    self.lines[startCoord.line].delete(istart..^1)
    if iend < self.lines[endCoord.line].len:
      self.lines[endCoord.line].delete(0..iend)

    self.lines[startCoord.line].add(self.lines[endCoord.line])
    self.removeLines(startCoord.line + 1, endCoord.line + 1)

  self.textChanged = true

proc insertLine*(self: var TextEditor, index: int) = 
  assert not self.readOnly

  self.lines.insert(Line.default, index)

  for e, (line, str) in self.errorMarkers: 
    self.errorMarkers[e] = ((if line >= index: line + 1 else: line), str)

  for e, line in self.breakpoints:
    self.breakpoints[e] = if line >= index: line + 1 else: e

proc insertTextAt*(self: var TextEditor, where: Coord, value: string): Coord  = 
  ## Returns the end coord of value

  assert not self.readOnly

  var line = where.line
  var cindex = where.col
  for rune in value.runes:
    assert self.lines.len > 0

    if rune == Rune('\r'):
      continue
    elif rune == Rune('\n'):
      self.insertLine(line + 1)
  
      if cindex < self.getLineLength(line): # If the new line is not at the end of the line split it
        self.lines[line + 1].insert(self.lines[line][cindex..^1], 0)
        self.lines[line].delete(cindex..^1)

      cindex = 0
      inc line
    
    else:
      self.lines[line].insert(glyph(rune, PaletteIndex.Default), cindex)
      inc cindex

  self.textChanged = true
  result.col = cindex
  result.line = line

proc addUndo*(self: var TextEditor, rec: UndoRecord) = 
  assert not self.readOnly

  echo &"Adding {rec} to {self.undoIndex + 1}"
  self.undoBuffer.add(rec)
  inc self.undoIndex

proc screenPosToCoord*(self: TextEditor, pos: ImVec2): Coord = 
  let origin = igGetCursorScreenPos()
  let local = pos - origin

  let lineNo = max(0, int floor(local.y / self.charAdvance.y))
  var columnCoord = 0

  if lineNo >= 0 and lineNo < self.lines.len:
    let line = self.lines[lineNo]

    var columnX = 0f

    for columnIndex in 0..line.high:
      var columnWidth = 0f

      if line[columnIndex].rune == Rune('\t'):
        let spaceSize = igGetFont().calcTextSizeA(igGetFontSize(), float.high, -1f, " ").x
        let oldX = columnX
        let newColumnX = (1f + floor((1f + columnX) / (self.tabSize.float32 * spaceSize))) * (self.tabSize.float32 * spaceSize)
        columnWidth = newColumnX - oldX
        if self.textStart + columnX + columnWidth * 0.5f > local.x:
          break

        columnX = newColumnX
        columnCoord = (columnCoord div self.tabSize) * self.tabSize + self.tabSize
      
      else:
        columnWidth = igGetFont().calcTextSizeA(igGetFontSize(), float.high, -1f, cstring $line[columnIndex].rune).x

        if self.textStart + columnX + columnWidth * 0.5f > local.x:
          break

        columnX += columnWidth
        inc columnCoord

  result = self.sanitizeCoord(coord(lineNo, columnCoord))

proc findWordStart*(self: TextEditor, at: Coord): Coord = 
  if at.line >= self.lines.len:
    return at

  let line = self.lines[at.line]
  var cindex = at.col

  if cindex >= line.len:
    return at

  while cindex > 0 and line[cindex].rune.isWhiteSpace():
    if hasEcho: echo "findWordStart whitespace"
    dec cindex

  let cstart = line[cindex].colorIndex
  while cindex > 0:
    if hasEcho: echo "findWordStart"
    let glyph = line[cindex - 1]

    if (self.colorizerEnabled and cstart != glyph.colorIndex) or glyph.rune.isWhiteSpace() or (not self.colorizerEnabled and not glyph.rune.isAlphaNum()):
      break

    dec cindex

  result = coord(at.line, cindex)

proc findWordEnd*(self: TextEditor, at: Coord): Coord = 
  if at.line >= self.lines.len:
    return at

  let line = self.lines[at.line]
  var cindex = at.col

  if cindex >= line.len:
    return at

  while cindex < line.len and line[cindex].rune.isWhiteSpace():
    if hasEcho: echo "findWordEnd whitespace"
    inc cindex

  let cstart = 
    if cindex < line.len and self.colorizerEnabled:
      line[cindex].colorIndex
    else:
      PaletteIndex.Default

  while cindex < line.len:
    if hasEcho: echo "findWordEnd"
    let glyph = line[cindex]

    if (self.colorizerEnabled and cstart != glyph.colorIndex) or glyph.rune.isWhiteSpace() or (not self.colorizerEnabled and not glyph.rune.isAlphaNum()):
      break

    inc cindex

  result = coord(at.line, cindex)

proc isOnWordBoundary*(self: TextEditor, at: Coord): bool = 
  if at.line >= self.lines.len or at.col == 0 or at.col >= self.getLineLength(at.line):
    return true

  let line = self.lines[at.line]
  var cindex = at.col

  if self.colorizerEnabled:
    return line[cindex].colorIndex != line[cindex - 1].colorIndex

  result = line[cindex].rune.isWhiteSpace() != line[cindex - 1].rune.isWhiteSpace()

proc getWordAt*(self: TextEditor, at: Coord): string = 
  let istart = self.findWordStart(at).col
  let iend = self.findWordEnd(at).col

  for col in istart..<iend:
    result.add(self.lines[at.line][col].rune)

proc getWordUnderCursor(self: TextEditor): string = 
  self.getWordAt(self.getCursorCoord())

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

proc textDistancetoLStart*(self: TextEditor, fromCoord: Coord): float = 
  let line = self.lines[fromCoord.line]
  let spaceSize = igGetFont().calcTextSizeA(igGetFontSize(), float.high, -1f, " ").x
  let colIndex = fromCoord.col
  
  var it = 0
  while it < line.len and it < colIndex:
    if hasEcho: echo "textDistancetoLStart"
    let rune = line[it].rune
    if rune == Rune('\t'):
      result = (1f + floor((1f + result) / (float(self.tabSize) * spaceSize))) * (float(self.tabSize) * spaceSize)
      inc it

    else:
      result += igGetFont().calcTextSizeA(igGetFontSize(), float.high, -1f, cstring $rune).x
      inc it

proc hasSelection*(self: TextEditor): bool = 
  self.state.selectionEnd > self.state.selectionStart

proc ensureCursorVisible*(self: var TextEditor) = 
  if not self.withinRender:
    self.scrollToCursor = true
    return

  let scrollX = igGetScrollX()
  let scrollY = igGetScrollY()

  # let height = igGetWindowHeight()
  # let width = igGetWindowWidth()
  let avail = igGetContentRegionAvail()

  let top = int floor(scrollY / self.charAdvance.y)
  let bottom = int floor((scrollY + avail.y) / self.charAdvance.y)
  let left = int floor((scrollX) / self.charAdvance.x)
  let right = int floor((scrollX + avail.x) / self.charAdvance.x)
 
  let pos = self.getCursorCoord()
 
  if hasEcho: echo &"{left-1=} {right-4=}\n"

  if pos.line < top:
    if hasEcho: echo "top"
    igSetScrollY(max(0f, float(pos.line) * self.charAdvance.y))

  if pos.line > bottom - 1:
    if hasEcho: echo "bottom"
    igSetScrollY(max(0f, float(pos.line + 1) * self.charAdvance.y - avail.y))

  if pos.col < left-1:
    if hasEcho: echo "left"
    igSetScrollX(max(0f, float(pos.col+1) * self.charAdvance.x))

  if pos.col > right - 4:
    if hasEcho: echo "right"
    igSetScrollX(max(0f, float(pos.col+4) * self.charAdvance.x - avail.x))

  # Ensure the cursor is visible and not blinking
  let timeEnd = getDuration()
  if timeEnd - self.startTime < self.blinkDur:
    self.startTime = timeEnd - self.blinkDur

proc handleKeyboardInputs*(self: var TextEditor)

proc handleMouseInputs*(self: var TextEditor)

proc colorize*(self: var TextEditor, fromL = 0, lines = -1) = # FIXME How c++ deals when no arguments are passed 
  let toL = if lines < 0: self.lines.len else: min(self.lines.len, fromL + lines)
  echo &"{fromL=} {lines=} {toL=}"
  self.colorRangeMin = max(0, min(self.colorRangeMin, fromL))
  self.colorRangeMax = max(self.colorRangeMin, max(self.colorRangeMax, toL))
  self.checkComments = true

proc colorizeRange*(self: var TextEditor, fromL, toL: int) = # FIXME
  # echo &"colorizeRange from {fromL} to {toL}"
  if self.lines.len == 0 or fromL >= toL:
    return

  let endLine = clamp(toL, 0, self.lines.len)
  for i in fromL..<endLine:
    let line = self.lines[i]
    # echo &"Colorize line {i} \"{line}\""

    if line.len == 0:
      continue

    var buffer: string
    for j in 0..line.high:
      buffer.add(line[j].rune)
      self.lines[i][j].colorIndex = PaletteIndex.Default # FIXME

    var cindex = 0
    while cindex < buffer.len: # FIXME
      if hasEcho: echo "colorizeRange"
      var (hasTokenizeResult, tokenSlice, tokenCol) = (false, 0..0, PaletteIndex.Default)
      if not self.languageDef.tokenize.isNil:
        var (hasTokenizeResult, tokenSlice, tokenCol) = self.languageDef.tokenize(buffer, cindex)
      # if hasTokenizeResult:
        # echo &"\t{hasTokenizeResult=} {tokenSlice=} {tokenCol=}"
        # echo &"\t\t{buffer[0..<tokenSlice.a]}_{buffer[tokenSlice]}_{(if tokenSlice.b < buffer.len: buffer[tokenSlice.b+1..^1] else: \"\")}"

      if not hasTokenizeResult:
        for (pattern, color) in self.languageDef.regexList:
          if (let (first, last) = buffer.findBounds(pattern, cindex); first >= 0):
            tokenCol = color
            hasTokenizeResult = true
            tokenSlice = first..last
            echo &"{color} at {tokenSlice} {buffer[tokenSlice]}"
            break

      if not hasTokenizeResult:
        inc cindex
      else:
        var id: string
        if tokenCol == PaletteIndex.Identifier:
          id = buffer[tokenSlice]

          if not self.languageDef.caseSensitive:
            id = id.toLowerAscii()

          if not line[cindex].preprocessor:
            if self.languageDef.keywords.find(id) >= 0:
              echo &"Keyword {id}"
              tokenCol = PaletteIndex.Keyword
            elif self.languageDef.identifiers.filterIt(it.str == id).len != 0:
              echo &"Known identifier {id}"
              tokenCol = PaletteIndex.KnownIdentifier
            elif self.languageDef.preprocIdentifiers.filterIt(it.str == id).len != 0:
              echo &"Preproc identifier {id}"
              tokenCol = PaletteIndex.PreprocIdentifier
          else:
            if self.languageDef.preprocIdentifiers.filterIt(it.str == id).len != 0:
              echo &"Preproc identifier {id}"
              tokenCol = PaletteIndex.PreprocIdentifier       

        for j in tokenSlice.a..tokenSlice.b:
          self.lines[i][j].colorIndex = tokenCol

        cindex = tokenSlice.b+1

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
      if hasEcho: echo "colorizeInternal"
      let line = self.lines[currentLine]

      if currentIndex == 0 or not concatenate:
        withinSingleLineComment = false
        withinPreproc = false
        firstChar = true

      concatenate = false

      if line.len != 0:
        let glyph = line[currentIndex]
        let rune = glyph.rune
        # echo glyph

        if rune != Rune(self.languageDef.preprocChar) and not rune.isWhiteSpace():
          firstChar = false

        if currentIndex == line.high and line[line.high].rune == Rune('\\'):
          concatenate = true

        var inComment = commentStartLine < currentLine or (commentStartLine == currentLine and commentStartIndex <= currentIndex)

        if withinString:
          self.lines[currentLine][currentIndex].multiLineComment = inComment

          if rune == Rune('\"'):
            if currentIndex < line.high and line[currentIndex + 1].rune == Rune('\"'):
              currentIndex += 1
              if currentIndex < line.len:
                self.lines[currentLine][currentIndex].multiLineComment = inComment

            else:
              withinString = false
         
          elif rune == Rune('\\'):
            inc currentIndex
            if currentIndex < line.len:
              self.lines[currentLine][currentIndex].multiLineComment = inComment
       
        else:
          if firstChar and rune == Rune(self.languageDef.preprocChar):
            withinPreproc = true

          if rune == Rune('\"'):
            withinString = true
            self.lines[currentLine][currentIndex].multiLineComment = inComment

          else:
            let startStr = self.languageDef.commentStart
            let singleStartStr = self.languageDef.singleLineComment

            if (singleStartStr.len > 0 and 
              currentIndex + singleStartStr.len < line.len and 
              ($line)[currentIndex..currentIndex + singleStartStr.len] == singleStartStr
            ):
              if currentIndex + startStr.len > line.len:
                withinSingleLineComment = true
              elif ($line)[currentIndex..currentIndex + startStr.len] == startStr:
                withinSingleLineComment = true

            if (startStr.len != 0 and 
              not withinSingleLineComment and
              currentIndex + startStr.len < line.len and
              ($line)[currentIndex..currentIndex + startStr.len] == startStr
            ):
              commentStartLine = currentLine
              commentStartIndex = currentIndex
           
            # inComment = inComment = (commentStartLine < currentLine || (commentStartLine == currentLine && commentStartIndex <= currentIndex))
            inComment = commentStartLine < currentLine or (commentStartLine == currentLine and commentStartIndex <= currentIndex)

            self.lines[currentLine][currentIndex].multiLineComment = inComment
            self.lines[currentLine][currentIndex].comment = withinSingleLineComment

            let endStr = self.languageDef.commentEnd

            if (currentIndex + 1 < line.len and
              currentIndex + 1 >= endStr.len and
              ($line)[currentIndex + 1 - endStr.len..currentIndex + 1] == endStr
            ):
              commentStartIndex = endIndex
              commentStartLine = endLine
       
        self.lines[currentLine][currentIndex].preprocessor = withinPreproc
        inc currentIndex
        if currentIndex >= line.len:
          currentIndex = 0
          inc currentLine     
      else:
        currentIndex = 0
        inc currentLine
   
    self.checkComments = false

  if self.colorRangeMin < self.colorRangeMax:
    let increment = if self.languageDef.tokenize.isNil: 10 else: 10000
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
      if hasEcho: echo "render"
      let lineStartScreenPos = igVec2(cursorScreenPos.x, cursorScreenPos.y + lineNo.float32 * self.charAdvance.y)
      let textScreenPos = igVec2(lineStartScreenPos.x + self.textStart, lineStartScreenPos.y)

      let line = self.lines[lineNo]
      longest = max(self.textStart + self.textDistancetoLStart(coord(lineNo, self.getLineLength(lineNo))), longest)
      var columnNo = 0
      let lineStartCoord = coord(lineNo, 0)
      let lineEndCoord = coord(lineNo, self.getLineLength(lineNo))

      # Draw selection for the current line
      var sstart = -1f
      var ssend = -1f

      assert self.state.selectionStart <= self.state.selectionEnd

      if self.state.selectionStart <= lineEndCoord:
        sstart = if self.state.selectionStart > lineStartCoord: self.textDistancetoLStart(self.state.selectionStart) else: 0f
      if self.state.selectionEnd > lineStartCoord:
        ssend = self.textDistancetoLStart(if self.state.selectionEnd < lineEndCoord: self.state.selectionEnd else: lineEndCoord)

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
            let cindex = self.state.cursorPos.col
            let cx = self.textDistancetoLStart(self.state.cursorPos)

            if self.overwrite and cindex < line.len:
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
      var prevColor = if line.len == 0: self.palette[ord PaletteIndex.Default] else: self.getGlyphColor(line[0])
      var bufferOffset: ImVec2
      var i = 0
      while i < line.len:
        if hasEcho: echo "Render colorized text"
        let glyph = line[i]
        let color = self.getGlyphColor(glyph)

        if (color != prevColor or glyph.rune.ord == '\t'.ord or glyph.rune.ord == ' '.ord) and self.lineBuffer.len != 0:
          let newOffset = textScreenPos + bufferOffset
          drawList.addText(newOffset, prevColor, cstring self.lineBuffer)
          let textSize = igGetFont().calcTextSizeA(igGetFontSize(), float.high, -1f, cstring self.lineBuffer)
          bufferOffset.x += textSize.x
          self.lineBuffer.setLen(0)
       
        prevColor = color

        if glyph.rune == Rune('\t'):
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

            drawList.addLine(p1, p2, self.palette[ord PaletteIndex.WhiteSpaceTab])
            drawList.addLine(p2, p3, self.palette[ord PaletteIndex.WhiteSpaceTab])
            drawList.addLine(p2, p4, self.palette[ord PaletteIndex.WhiteSpaceTab])
         
        elif glyph.rune == Rune(' '):
          if self.showWhitespaces:
            let s = igGetFontSize()
            let x = textScreenPos.x + bufferOffset.x + spaceSize * 0.5f
            let y = textScreenPos.y + bufferOffset.y + s * 0.5f
            drawList.addCircleFilled(igVec2(x, y), 1.5f, self.palette[ord PaletteIndex.WhiteSpace], 4)
         
          bufferOffset.x += spaceSize
          inc i

        else:
          self.lineBuffer.add(line[i].rune)
          inc i

        inc columnNo
     
      if self.lineBuffer.len != 0:
        # if hasEcho: echo "Drawing: ", self.lineBuffer
        let newOffset = textScreenPos + bufferOffset
        drawList.addText(newOffset, prevColor, cstring self.lineBuffer)
        self.lineBuffer.setLen(0)

      inc lineNo

    # Draw a tooltip on known identifiers/preprocessor symbols
    if igIsMousePosValid() and igIsWindowHovered():
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

  igPushStyleColor(ImGuiCol.ChildBg, self.palette[ord PaletteIndex.Background])
  igPushStyleVar(ImGuiStyleVar.ItemSpacing, igVec2(0f, 0f))
  if not self.ignoreImGuiChild:
    igBeginChild(cstring title, size, border, makeFlags(ImGuiWindowFlags.HorizontalScrollbar, ImGuiWindowFlags.NoMove, ImGuiWindowFlags.NoNavInputs))

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
  self.lines.setLen(0)
  self.lines.add(Line.default)
  
  for rune in text.runes:
    if $rune == "\r": discard # Ignore the carriage return character
    elif $rune == "\n":
      self.lines.add(Line.default)
    else:
      self.lines[^1].add(glyph(rune, PaletteIndex.Default) )

  self.textChanged = true
  self.scrollToTop = true

  self.undoBuffer.setLen(0)
  self.undoIndex = 0

  self.colorize()

proc setTextlines*(self: var TextEditor, lines: seq[string]) = 
  self.lines.setLen(0)

  if lines.len == 0:
    self.lines.add(Line.default)
 
  else:
    for line in lines:
      self.lines.add(Line.default)
      for rune in line.runes:
        self.lines[^1].add(glyph(rune, PaletteIndex.Default) )

  self.textChanged = true
  self.scrollToTop = true

  self.undoBuffer.setLen(0)
  self.undoIndex = 0

  self.colorize()

proc setCursorCoord*(self: var TextEditor, pos: Coord) = 
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
  let oldSelstart = self.state.selectionStart
  let oldSelend = self.state.selectionEnd

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
    self.state.selectionEnd = coord(lineNo, self.getLineLength(lineNo))

  if self.state.selectionStart != oldSelstart or self.state.selectionEnd != oldSelend:
    self.cursorPosChanged = true

proc deselect*(self: var TextEditor) = 
  self.setSelection(self.getCursorCoord(), self.getCursorCoord())

proc insertText*(self: var TextEditor, value: string) = 
  let pos = self.getCursorCoord()
  let start = min(pos, self.state.selectionStart)
  var totalLines = pos.line - start.line

  self.setCursorCoord(self.insertTextAt(pos, value))
  self.deselect()
  self.colorize(start.line, (totalLines + (pos.line - self.getCursorCoord().line)) + 2)

proc deleteSelection*(self: var TextEditor) = 
  assert self.state.selectionEnd >= self.state.selectionStart

  if self.state.selectionEnd == self.state.selectionStart:
    return

  self.deleteRange(self.state.selectionStart, self.state.selectionEnd)

  self.setSelection(self.state.selectionStart, self.state.selectionStart)
  self.setCursorCoord(self.state.selectionStart)
  self.colorize(self.state.selectionStart.line, 1)

proc enterCharacter*(self: var TextEditor, rune: Rune, shift: bool) = # FIXME ImWchar
  assert not self.readOnly

  var u: UndoRecord
  u.before = self.state

  if self.hasSelection():
    if $rune == "\t" and self.state.selectionStart.line != self.state.selectionEnd.line:
      var startCoord = self.state.selectionStart
      var endCoord = self.state.selectionEnd
      let originalend = endCoord

      if startCoord > endCoord:
        swap(startCoord, endCoord)

      startCoord.col = 0
      #      endCoord.col = endCoord.line < self.lines.len ? self.lines[endCoord.line].len : 0
      if endCoord.col == 0 and endCoord.line > 0:
        dec endCoord.line
      if endCoord.line >= self.lines.len:
        endCoord.line = self.lines.high # FIXME
      endCoord.col = self.getLineLength(endCoord.line)

      #if (endCoord.col >= getLineLength(endCoord.line)):
      #  endCoord.col = getLineLength(endCoord.line) - 1

      u.removedStart = startCoord
      u.removedEnd = endCoord
      u.removed = self.getText(startCoord, endCoord)

      var modified = false

      for i in startCoord.line..endCoord.line:
        let line = self.lines[i]
        if shift:
          if line.len != 0:
            if $line[0].rune == "\t":
              self.lines[i].delete(0)
              modified = true
           
          else:
            for j in 0..<self.tabSize: # FIXME
              if line.len > 0 and line[0].rune == Rune(' '):
                self.lines[i].delete(0)
                modified = true
        else:
          self.lines[i].insert(glyph("\t", PaletteIndex.Background), 0)
          modified = true

      if modified:
        startCoord = coord(startCoord.line, 0)        
        var rangeEnd: Coord

        if originalend.col != 0:
          endCoord = coord(endCoord.line, self.getLineLength(endCoord.line))
          rangeEnd = endCoord
          u.added = self.getText(startCoord, endCoord)
        else:
          endCoord = coord(originalend.line, 0)
          rangeEnd = coord(endCoord.line - 1, self.getLineLength(endCoord.line - 1))
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
  let coord = self.getCursorCoord()
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
    let cindex = coord.col
    
    self.lines[coord.line + 1].add(line[cindex..^1])
    
    if self.lines[coord.line].len > 0 and cindex < self.lines[coord.line].len:
      self.lines[coord.line].delete(cindex..self.lines[coord.line].high)

    self.setCursorCoord(coord(coord.line + 1, whitespaceSize))
    
    u.added = $rune
  else:
    var buf = $rune

    if buf.runeLen > 0:
      let line = self.lines[coord.line]
      var cindex = coord.col

      if self.overwrite and cindex < line.len:
        u.removedStart = self.state.cursorPos
        u.removedEnd = coord(coord.line, cindex + 1)

        u.removed.add(line[cindex].rune)
        self.lines[coord.line].delete(cindex)

      for p in buf.runes:
        self.lines[coord.line].insert(glyph(p, PaletteIndex.Default), cindex)
        inc cindex

      u.added = buf

      self.setCursorCoord(coord(coord.line, cindex))

    else:
      return
 
  self.textChanged = true

  u.addedEnd = self.getCursorCoord()
  u.after = self.state

  self.addUndo(u)

  self.colorize(coord.line - 1, 3)
  self.ensureCursorVisible()

proc moveUp*(self: var TextEditor, amount: int = 1, select: bool) = 
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

proc moveDown*(self: var TextEditor, amount: int = 1, select: bool) = 
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

proc moveLeft*(self: var TextEditor, amount: int = 1, select, wordMode: bool) = 
  if self.lines.len == 0:
    return

  let oldPos = self.state.cursorPos
  self.state.cursorPos = self.getCursorCoord()
  
  var line = self.state.cursorPos.line
  var cindex = self.state.cursorPos.col

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

    self.state.cursorPos = coord(line, cindex)

    if wordMode:
      self.state.cursorPos = self.findWordStart(self.state.cursorPos)
      cindex = self.state.cursorPos.col

  self.state.cursorPos = coord(line, cindex)

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

proc moveRight*(self: var TextEditor, amount: int = 1, select, wordMode: bool) = 
  let oldPos = self.state.cursorPos

  if self.lines.len == 0 or oldPos.line >= self.lines.len:
    return

  var cindex = self.state.cursorPos.col
  for i in countdown(amount, 1):
    let lindex = self.state.cursorPos.line
    let line = self.lines[lindex]

    if cindex >= line.len:
      if self.state.cursorPos.line < self.lines.high:
        self.state.cursorPos.line = clamp(self.state.cursorPos.line + 1, 0, self.lines.high)
        self.state.cursorPos.col = 0
      else:
        return
   
    else:
      inc cindex
      self.state.cursorPos = coord(lindex, cindex)
      if wordMode:
        self.state.cursorPos = self.findWordEnd(self.state.cursorPos) 

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
  self.setCursorCoord(coord(0, 0))

  if self.state.cursorPos != oldPos:
    if select:
      self.interactiveEnd = oldPos
      self.interactiveStart = self.state.cursorPos
    else:
      self.interactiveStart = self.state.cursorPos
      self.interactiveEnd = self.interactiveStart

    self.setSelection(self.interactiveStart, self.interactiveEnd)

proc moveBottom*(self: var TextEditor, select: bool) = 
  let oldPos = self.getCursorCoord()
  let newPos = coord(self.lines.high, 0)
  self.setCursorCoord(newPos)

  if select:
    self.interactiveStart = oldPos
    self.interactiveEnd = newPos
  else:
    self.interactiveStart = self.state.cursorPos
    self.interactiveEnd = self.interactiveStart

  self.setSelection(self.interactiveStart, self.interactiveEnd)

proc moveHome*(self: var TextEditor, select: bool) = 
  let oldPos = self.state.cursorPos
  self.setCursorCoord(coord(self.state.cursorPos.line, 0))

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
  self.setCursorCoord(coord(self.state.cursorPos.line, self.getLineLength(oldPos.line)))

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

proc delete*(self: var TextEditor, wordMode = false) = # Delete next character
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
    let pos = self.getCursorCoord()
    self.setCursorCoord(pos)
    let line = self.lines[pos.line]

    if pos.col == self.getLineLength(pos.line):
      if pos.line == self.lines.high:
        return

      u.removed = "\n"
      u.removedStart = self.getCursorCoord()
      u.removedEnd = u.removedStart
      self.advance(u.removedEnd)

      let nextline = self.lines[pos.line + 1]
      self.lines[pos.line].add(nextline)
      self.removeLine(pos.line + 1)
   
    else:
      let cindex = pos.col

      u.removedStart = pos

      if wordMode:
        let endCoord = self.findWordEnd(pos)
        u.removedEnd = endCoord

        u.removed = self.getText(u.removedStart, u.removedEnd)
        self.deleteRange(pos, endCoord)
      else:
        u.removedEnd = pos
        inc u.removedEnd.col

        u.removed = self.getText(u.removedStart, u.removedEnd)

        self.lines[pos.line].delete(cindex)

    self.textChanged = true

    self.colorize(pos.line, 1)

  u.after = self.state
  self.addUndo(u)

proc backspace*(self: var TextEditor, wordMode = false) =  # Delete previous character
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
    let pos = self.getCursorCoord()
    self.setCursorCoord(pos)

    if self.state.cursorPos.col == 0:
      if self.state.cursorPos.line == 0:
        return

      u.removed = "\n"
      u.removedStart = coord(pos.line - 1, self.getLineLength(pos.line - 1))
      u.removedEnd = u.removedStart
      self.advance(u.removedEnd)

      let line = self.lines[self.state.cursorPos.line]
      var prevline = self.lines[self.state.cursorPos.line - 1]
      let prevSize = self.getLineLength(self.state.cursorPos.line - 1)
      prevline.add(line)

      for e, (line, error) in self.errorMarkers:
        self.errorMarkers[e] = ((if line - 1 == self.state.cursorPos.line: line - 1 else: line), error)

      self.removeLine(self.state.cursorPos.line)
      dec self.state.cursorPos.line
      self.state.cursorPos.col = prevSize

    else:
      u.removedEnd = pos
      dec u.removedEnd.col

      if wordMode:
        let startCoord = self.findWordStart(u.removedEnd)
  
        u.removedStart = startCoord
        self.state.cursorPos = startCoord
        u.removed = self.getText(u.removedStart, u.removedEnd)

        self.deleteRange(startCoord, u.removedEnd)
      else:
        u.removedStart = u.removedEnd
        dec u.removedStart.col
        dec self.state.cursorPos.col

        u.removed = $self.lines[pos.line][u.removedEnd.col]
        self.lines[pos.line].delete(u.removedEnd.col)

    self.textChanged = true

    self.ensureCursorVisible()
    self.colorize(self.state.cursorPos.line, 1)
 
  u.after = self.state
  self.addUndo(u)

proc selectWordUnderCursor*(self: var TextEditor) = 
  let c = self.getCursorCoord()
  self.setSelection(self.findWordStart(c), self.findWordEnd(c))

proc selectAll*(self: var TextEditor) = 
  self.setSelection(coord(0, 0), coord(self.lines.len, 0))
  self.setCursorCoord(self.state.selectionEnd)

proc copy*(self: TextEditor) = 
  if self.hasSelection():
    igSetClipboardText(cstring self.getSelectedText())
  else:
    if self.lines.len != 0:
      igSetClipboardText(cstring $self.lines[self.getCursorCoord().line])

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
    u.addedStart = self.getCursorCoord()

    self.insertText($clipText)

    u.addedEnd = self.getCursorCoord()
    u.after = self.state
    self.addUndo(u)

proc getCurrentLineText*(self: TextEditor): string = 
  let lineLength = self.getLineLength(self.state.cursorPos.line)
  self.getText(coord(self.state.cursorPos.line, 0), coord(self.state.cursorPos.line, lineLength))

proc processInputs*(self: TextEditor) = discard # FIXME

proc `languageDef=`*(self: var TextEditor, def: LanguageDef) = 
  self.languageDef = def
  self.colorize()

proc `tabSize=`*(self: var TextEditor, value: range[0..32]) = 
  self.tabSize = value

proc setPalette*(self: var TextEditor, palette: Palette) = 
  self.paletteBase = palette

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
  not self.readOnly and self.undoIndex >= 0 # FIXME self.undoIndex >= 0 (?)

proc canRedo*(self: TextEditor): bool = 
  not self.readOnly and self.undoIndex in 0..self.undoBuffer.high

proc undo*(self: var TextEditor, steps: int = 1) = 
  for i in countdown(steps, 1):
    if self.canUndo():
      echo &"undo {self.undoIndex}"
      self.undoBuffer[self.undoIndex].undo(self)
      dec self.undoIndex

proc redo*(self: var TextEditor, steps: int = 1) = 
  for i in countdown(steps-1, 0):
    if self.canRedo():
      self.undoBuffer[self.undoIndex].redo(self)
      inc self.undoIndex

proc handleKeyboardInputs*(self: var TextEditor) = 
  let io = igGetIO()
  let shift = io.keyshift
  let ctrl = if io.configMacOSXBehaviors: io.keySuper else: io.keyCtrl
  let alt = if io.configMacOSXBehaviors: io.keyCtrl else: io.keyAlt

  if igIsWindowFocused() and igIsWindowHovered():
    igSetMouseCursor(ImGuiMouseCursor.TextInput)

    io.wantCaptureKeyboard = true
    io.wantTextInput = true

    if not self.readOnly and ctrl and not shift and not alt and igIsKeyPressedMap(ImGuiKey.Z):
      self.undo()
    elif not self.readOnly and not ctrl and not shift and alt and igIsKeyPressedMap(ImGuiKey.Backspace):
      self.undo()
    elif not self.readOnly and ctrl and not shift and not alt and igIsKeyPressedMap(ImGuiKey.Y):
      self.redo()
    elif not ctrl and not alt and igIsKeyPressedMap(ImGuiKey.UpArrow):
      self.moveUp(select = shift)
    elif not ctrl and not alt and igIsKeyPressedMap(ImGuiKey.DownArrow):
      self.moveDown(select = shift)
    elif not alt and igIsKeyPressedMap(ImGuiKey.LeftArrow):
      self.moveLeft(select = shift, wordMode = ctrl)
    elif not alt and igIsKeyPressedMap(ImGuiKey.RightArrow):
      self.moveRight(select = shift, wordMode = ctrl)
    elif not alt and igIsKeyPressedMap(ImGuiKey.PageUp):
      self.moveUp(amount = self.getPageSize() - 4, select = shift)
    elif not alt and igIsKeyPressedMap(ImGuiKey.PageDown):
      self.moveDown(amount = self.getPageSize() - 4, select =shift)
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
    elif not self.readOnly and not shift and not alt and igIsKeyPressedMap(ImGuiKey.Backspace):
      self.backspace(ctrl)
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
        if hasEcho: echo "Detected ", rune
        if rune.ord != 0 and (rune.ord == '\n'.ord or rune.ord >= 32):
          if hasEcho: echo "Enter ", rune
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
        self.setCursorCoord(self.state.selectionEnd)

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
        self.setCursorCoord(self.state.selectionEnd)

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

      self.ensureCursorVisible()
   
    # ouse left button dragging (=> update selection)
    elif igIsMouseDragging(ImGuiMouseButton.Left) and igIsMouseDown(ImGuiMouseButton.Left):
      io.wantCaptureMouse = true
      self.interactiveEnd = self.screenPosToCoord(igGetMousePos())
      self.state.cursorPos = self.screenPosToCoord(igGetMousePos())
      if hasEcho: echo "dragging from ", self.interactiveStart, " to ", self.interactiveEnd

      self.setSelection(self.interactiveStart, self.interactiveEnd, self.selectionMode)
