import std/strformat
import nimgl/[opengl, glfw]
import nimgl/imgui, nimgl/imgui/[impl_opengl, impl_glfw]

import src/imtexteditor

proc main() =
  doAssert glfwInit()

  glfwWindowHint(GLFWContextVersionMajor, 3)
  glfwWindowHint(GLFWContextVersionMinor, 3)
  glfwWindowHint(GLFWOpenglForwardCompat, GLFW_TRUE)
  glfwWindowHint(GLFWOpenglProfile, GLFW_OPENGL_CORE_PROFILE)
  glfwWindowHint(GLFWResizable, GLFW_TRUE)

  var w: GLFWWindow = glfwCreateWindow(700, 720)
  if w == nil:
    quit(-1)

  w.makeContextCurrent()


  doAssert glInit()

  let context = igCreateContext()
  let io = igGetIO()
  io.fonts.addFontDefault()

  doAssert igGlfwInitForOpenGL(w, true)
  doAssert igOpenGL3Init()

  let editorFont = io.fonts.addFontFromFileTTF("assets/UbuntuMono-Regular.ttf", 13)
  var lastClipboard = ""
  var editor = initTextEditor(
    # palette = getMonokaiPalette(), 
    languageDef = langDefTest(), 
    breakpoints = @[24, 27], 
    errorMarkers = @[(6, "Example error here:\nInclude file not found: \"TextEditor.h\""), (41, "Another example error")], 
  )

  
  while not w.windowShouldClose:
    glfwPollEvents()

    igOpenGL3NewFrame()
    igGlfwNewFrame()
    igNewFrame()

    let cpos = editor.getCursorCoord()
    if igBegin("Text Editor Demo", flags = ImGuiWindowFlags.MenuBar):
      if igBeginMenuBar():
        if igBeginMenu("File"):
          if igMenuItem("Save"):
            let textToSave = editor.getText();
            echo "Save: ", textToSave
          if igMenuItem("Quit", "Alt-F4"):
            w.setWindowShouldClose(true)

          igEndMenu()

        if igBeginMenu("Edit"):
          var ro = editor.readOnly
          if igMenuItem("Read-only mode", nil, ro.addr):
            editor.readOnly = ro

          igSeparator()

          if igMenuItem("Undo", "ALT-Backspace", enabled = not ro and editor.canUndo()):
            editor.undo(1)
          if igMenuItem("Redo", "Ctrl-Y", enabled = not ro and editor.canRedo()):
            editor.redo(1)

          igSeparator()

          if igMenuItem("Copy", "Ctrl-C", enabled = editor.hasSelection()):
            editor.copy()
          if igMenuItem("Cut", "Ctrl-X", enabled = not ro and editor.hasSelection()):
            editor.cut()
          if igMenuItem("Delete", "Del", enabled = not ro and editor.hasSelection()):
            editor.delete()
          if igMenuItem("Paste", "Ctrl-V", enabled = not ro and not igGetClipboardText().isNil):
            editor.paste()

          igSeparator()

          if igMenuItem("Select all"):
            editor.setSelection(coord(0, 0), coord(editor.getTotalLines(), 0))

          igEndMenu()

        if igBeginMenu("View"):
          if igMenuItem("Dark palette"):
            editor.setPalette(getDarkPalette())
          if igMenuItem("Light palette"):
            editor.setPalette(getLightPalette())
          if igMenuItem("Retro blue palette"):
            editor.setPalette(getRetroBluePalette())
          if igMenuItem("Monokai palette"):
            editor.setPalette(getMonokaiPalette())

          igEndMenu()
        igEndMenuBar()

    igText("Application average %.3f ms/frame (%.1f FPS)", 1000f / igGetIO().framerate, igGetIO().framerate)
    igText(cstring &"{cpos.line + 1}:{cpos.col + 1} | {editor.languageDef.name} | file.nim")
    
    editorFont.igPushFont()
    editor.render("TextEditor", igVec2(600, 600), true)
    igPopFont()

    igEnd()
    # End simple window

    # GLFW clipboard -> ImGui clipboard
    if not w.getClipboardString().isNil and $w.getClipboardString() != lastClipboard:
      igsetClipboardText(w.getClipboardString())
      lastClipboard = $w.getClipboardString()

    # ImGui clipboard -> GLFW clipboard
    if not igGetClipboardText().isNil and $igGetClipboardText() != lastClipboard:
      w.setClipboardString(igGetClipboardText())
      lastClipboard = $igGetClipboardText()

    igRender()

    glClearColor(0.45f, 0.55f, 0.60f, 1.00f)
    glClear(GL_COLOR_BUFFER_BIT)

    igOpenGL3RenderDrawData(igGetDrawData())

    w.swapBuffers()

  igOpenGL3Shutdown()
  igGlfwShutdown()
  context.igDestroyContext()

  w.destroyWindow()
  glfwTerminate()

main()
