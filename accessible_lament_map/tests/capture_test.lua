local handlerNumber = 0
local sent = {}
local handlers = {}
local echoed = {}

function getMudletHomeDir()
  return "."
end

function getLastLineNumber(_)
  return 0
end

local function resolveCallback(callback)
  if type(callback) == "function" then
    return callback
  end
  local value = _G
  for part in callback:gmatch("[^.]+") do
    value = value[part]
  end
  return value
end

function registerAnonymousEventHandler(eventName, callback)
  handlerNumber = handlerNumber + 1
  handlers[eventName] = function(...)
    return resolveCallback(callback)(...)
  end
  return handlerNumber
end

function killAnonymousEventHandler(_) end
function cecho(message)
  echoed[#echoed + 1] = message
end

dofile("accessible_lament_map/src/scripts/Accessible Lament Map/LamentMapper.lua")

local function equal(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  end
end

equal(lamentMapper.packageVersion, "1.0.6", "package diagnostic version")
equal(handlerNumber, 4, "registered lifecycle handlers")
equal(type(handlers.sysInstallPackage), "function", "install handler")
handlers.sysInstallPackage("sysInstallPackage", "Accessible Lament Map")
handlers.sysBufferShrinkEvent("sysBufferShrinkEvent", "main")
handlers.sysExitEvent("sysExitEvent")

do
  local closed = false
  lamentMapper.process = {
    isRunning = function()
      return true
    end,
    close = function()
      closed = true
    end,
  }
  equal(lamentMapper.isProcessRunning(), true, "documented process isRunning call")
  lamentMapper.closeProcess()
  equal(closed, true, "documented process close call")
end

local function validThree()
  return {
    '""""""',
    '"""*""',
    '""""""',
  }
end

do
  local lines = { ">You are fatigued.", validThree()[1], validThree()[2], validThree()[3], "100h>" }
  local rows, first = lamentMapper.findMap(lines)
  equal(first, 2, "fatigue-prefixed response first map row")
  equal(#rows, 3, "fatigue-prefixed response size")
end

do
  local rows = validThree()
  rows[1] = '??""""'
  local valid, reason = lamentMapper.validateRows(rows)
  equal(valid, false, "unknown token")
  equal(reason, 'unknown token "??" at row 1, column 1', "unknown-token diagnostic")
end

do
  local rows = validThree()
  rows[2] = '""*"""'
  equal(lamentMapper.validateRows(rows), false, "misplaced player")
end

do
  local rows = validThree()
  rows[3] = rows[3] .. " "
  equal(lamentMapper.validateRows(rows), false, "wrapped row")
end

do
  local lines = { "", '"""*', "" }
  local rows, first, sourceLengths = lamentMapper.findMap(lines)
  equal(first, 1, "trimmed map first row")
  equal(#rows, 3, "trimmed map size")
  equal(rows[1], "      ", "blank outer row restored")
  equal(rows[2], '"""*  ', "center-row trailing cells restored")
  equal(sourceLengths[1], 0, "blank source length retained for style capture")
  equal(sourceLengths[2], 4, "center source length retained for style capture")
end

do
  local lines = { "        ", '"""*    ', "       " }
  local rows = lamentMapper.findMap(lines)
  equal(rows[1], "      ", "console-padding suffix removed")
  equal(rows[2], '"""*  ', "padded center row normalized")
end

do
  local tokens = {
    "^^", "tt", "TT", "nn", "V-", "/\\", "MM", "sf",
    "ss", "--", "..", ".n", ".v", "~~", "ii", "==",
    'x"', "xt", "xT", "ft", "FT", "x^", "x-", "x~",
  }
  local rows = {}
  local tokenIndex = 1
  for row = 1, 5 do
    local cells = {}
    for column = 1, 5 do
      if row == 3 and column == 3 then
        cells[#cells + 1] = '"*'
      else
        cells[#cells + 1] = tokens[tokenIndex]
        tokenIndex = tokenIndex + 1
      end
    end
    rows[#rows + 1] = table.concat(cells)
  end
  equal(lamentMapper.validateRows(rows), true, "all terrain tokens")
end

do
  equal(lamentMapper.isLandmarkToken("#T"), true, "dense-forest landmark overlay")
  equal(lamentMapper.isLandmarkToken("@~"), true, "river landmark overlay")
  equal(lamentMapper.isLandmarkToken("##"), true, "complete hash landmark")
  equal(lamentMapper.isLandmarkToken("@@"), true, "complete at landmark")
  equal(lamentMapper.isLandmarkToken("#?"), false, "unknown landmark remainder")
  equal(lamentMapper.isLandmarkToken("T#"), false, "landmark must occupy first character")
end

do
  local rows = {
    "                          ",
    "                ----      ",
    "                ----      ",
    "          tt#T~~--        ",
    "      TTTTTT~~~~          ",
    '    TTTT""~~~~TT          ',
    '    TT""""~~T*TT          ',
    '    """"~~~~TTTT          ',
    '  """"""~~                ',
    '  """"~~                  ',
    "    ~~                    ",
    "                          ",
    "                          ",
  }
  local valid, reason = lamentMapper.validateRows(rows)
  equal(valid, true, "live riverbank landmark map")
  equal(reason, nil, "live riverbank landmark rejection reason")
  local captured, first = lamentMapper.findMap(rows)
  equal(first, 1, "live riverbank landmark first row")
  equal(#captured, 13, "live riverbank landmark captured size")
end

do
  yajl = { to_string = function(_) return "{}" end }
  lamentMapper.process = {
    send = function(value)
      sent[#sent + 1] = value
    end,
  }
  lamentMapper.isProcessRunning = function()
    return true
  end
  lamentMapper.ensureProcess = function()
    return true
  end
  local rows = validThree()
  local styles = {}
  for _ = 1, 3 do
    styles[#styles + 1] = {{
      start = 0,
      length = 6,
      foreground = { r = 255, g = 255, b = 255 },
      background = { r = 0, g = 0, b = 0 },
    }}
  end
  lamentMapper.sendMap(rows, styles)
  lamentMapper.sendMap(rows, styles)
  equal(#sent, 2, "identical maps from separate captures are both transmitted")
end

do
  local writes = 0
  local originalProcess = lamentMapper.process
  local originalEnsureProcess = lamentMapper.ensureProcess
  local originalCloseProcess = lamentMapper.closeProcess
  lamentMapper.process = {
    send = function(_)
      writes = writes + 1
      error("simulated closed pipe")
    end,
  }
  lamentMapper.ensureProcess = function()
    if not lamentMapper.process then
      lamentMapper.process = {
        send = function(value)
          writes = writes + 1
          sent[#sent + 1] = value
        end,
      }
    end
    return true
  end
  lamentMapper.closeProcess = function()
    lamentMapper.process = nil
  end
  local retried = lamentMapper.sendPayload("retry\n")
  equal(retried, true, "failed process write is retried once")
  equal(writes, 2, "process write retry count")
  lamentMapper.process = originalProcess
  lamentMapper.ensureProcess = originalEnsureProcess
  lamentMapper.closeProcess = originalCloseProcess
end

do
  local rows = {
    "                          ",
    "                          ",
    "                          ",
    "                          ",
    "                          ",
    "          TTTTTT          ",
    "          TTT*TT          ",
    "          ttTTTT          ",
    "        tt                ",
    "                          ",
    "                          ",
    "                          ",
    "                          ",
  }
  equal(lamentMapper.validateRows(rows), true, "captured 13x13 debug-log map")

  getLastLineNumber = function(_)
    return 14
  end
  getLines = function(_, first, last)
    local result = {}
    for lineNumber = first, last do
      result[#result + 1] = rows[lineNumber]
    end
    return result
  end
  lamentMapper.captureStyles = function(capturedRows, _)
    local styles = {}
    for _, row in ipairs(capturedRows) do
      styles[#styles + 1] = {{
        start = 0,
        length = #row,
        foreground = { r = 255, g = 255, b = 255 },
        background = { r = 0, g = 0, b = 0 },
      }}
    end
    return styles
  end
  lamentMapper.responseStart = 1
  lamentMapper.lastObservedLine = 0
  local before = #sent
  lamentMapper.onPrompt()
  equal(#sent, before + 1, "debug-log map transmitted at prompt")
  equal(lamentMapper.lastCaptureStatus, "Map transmitted successfully", "debug-log capture status")
end

do
  local response = {
    "Your current surroundings are heavily wooded forest, and you can see up to six leagues away from here.",
    "You see no points of interest nearby.",
  }
  getLastLineNumber = function(_)
    return 3
  end
  getLines = function(_, first, last)
    local result = {}
    for lineNumber = first, last do
      result[#result + 1] = response[lineNumber]
    end
    return result
  end
  lamentMapper.responseStart = 1
  lamentMapper.lastObservedLine = 0
  lamentMapper.warnedSurveyWithoutMap = false
  local before = #echoed
  lamentMapper.onPrompt()
  equal(
    lamentMapper.lastCaptureStatus,
    "Wilderness map rejected: no line contained exactly one player marker",
    "survey-without-grid status"
  )
  equal(#echoed, before + 1, "survey-without-grid warning")
end

do
  local originalProcess = lamentMapper.process
  local originalPath = lamentMapper.executablePath
  local originalLoadPath = lamentMapper.loadExecutablePath
  local originalIsProcessRunning = lamentMapper.isProcessRunning
  local originalSpawn = spawn
  local spawnCount = 0
  local callback = nil
  local helperClosed = false
  local spawnedPath = nil
  local spawnedArgument = nil

  spawn = function(readFunction, path, argument)
    spawnCount = spawnCount + 1
    callback = readFunction
    spawnedPath = path
    spawnedArgument = argument
    return {
      close = function()
        helperClosed = true
      end,
    }
  end
  lamentMapper.isProcessRunning = function()
    return true
  end
  lamentMapper.process = {
    isRunning = function()
      return true
    end,
  }
  lamentMapper.executablePath = [[C:\Apps\LamentMapper.exe]]
  equal(lamentMapper.focusMapper(), true, "running mapper starts focus helper")
  equal(spawnCount, 1, "focus helper spawn count")
  equal(spawnedPath, [[C:\Apps\LamentMapper.exe]], "focus helper executable")
  equal(spawnedArgument, "--focus-existing", "focus helper argument")
  callback("OK: LamentMapper window focused.\n")
  equal(echoed[#echoed], "<green>LamentMapper window focused.\n", "focus helper success output")
  callback("ERROR: LamentMapper window unavailable.\n")
  equal(echoed[#echoed], "<red>LamentMapper window unavailable.\n", "focus helper failure output")

  lamentMapper.isProcessRunning = function()
    return false
  end
  lamentMapper.process = nil
  equal(lamentMapper.focusMapper(), false, "stopped mapper is not launched by focus key")
  equal(spawnCount, 1, "stopped mapper does not spawn helper")
  equal(
    echoed[#echoed],
    "<yellow>No LamentMapper window is available; the managed mapper is not running.\n",
    "stopped mapper diagnostic"
  )

  lamentMapper.isProcessRunning = function()
    return true
  end
  lamentMapper.process = {
    isRunning = function()
      return true
    end,
  }
  lamentMapper.executablePath = nil
  lamentMapper.loadExecutablePath = function()
    return nil
  end
  equal(lamentMapper.focusMapper(), false, "missing focus helper configuration")
  equal(spawnCount, 1, "missing configuration does not spawn helper")
  equal(
    echoed[#echoed],
    "<yellow>LamentMapper is not configured. Run: lamentmapper setup\n",
    "missing configuration diagnostic"
  )

  lamentMapper.executablePath = [[C:\Apps\LamentMapper.exe]]
  spawn = function(_, _, _)
    error("simulated helper failure")
  end
  equal(lamentMapper.focusMapper(), false, "focus helper spawn failure")
  equal(
    echoed[#echoed]:find("simulated helper failure", 1, true) ~= nil,
    true,
    "focus helper spawn failure output includes reason"
  )

  lamentMapper.closeFocusHelper()
  equal(helperClosed, true, "focus helper cleanup")
  lamentMapper.process = originalProcess
  lamentMapper.executablePath = originalPath
  lamentMapper.loadExecutablePath = originalLoadPath
  lamentMapper.isProcessRunning = originalIsProcessRunning
  spawn = originalSpawn
end

handlers.sysUninstallPackage("sysUninstallPackage", "Accessible Lament Map")
equal(#lamentMapper.eventHandlers, 0, "uninstall handler cleanup")

print("Mudlet capture tests passed")
