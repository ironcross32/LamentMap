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

equal(lamentMapper.packageVersion, "1.1.0", "package diagnostic version")
equal(handlerNumber, 8, "registered lifecycle and setup handlers")
equal(type(handlers.sysInstallPackage), "function", "install handler")
equal(type(handlers.sysDownloadDone), "function", "download completion handler")
equal(type(handlers.sysDownloadError), "function", "download error handler")
equal(type(handlers.sysUnzipDone), "function", "unzip completion handler")
equal(type(handlers.sysUnzipError), "function", "unzip error handler")
handlers.sysInstallPackage("sysInstallPackage", "Accessible Lament Map")
handlers.sysBufferShrinkEvent("sysBufferShrinkEvent", "main")

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

do
  local originalInvokeFileDialog = invokeFileDialog
  local originalIsExecutablePath = lamentMapper.isExecutablePath
  local originalSaveExecutablePath = lamentMapper.saveExecutablePath
  local originalCloseProcess = lamentMapper.closeProcess
  local selections = {
    [[C:\Bare\LamentMapper.exe]],
    [[C:\Manual\LamentMapper.exe]],
  }
  local selectionIndex = 0
  local saved = {}
  local closeCount = 0

  invokeFileDialog = function(fileOrFolder, _)
    equal(fileOrFolder, true, "manual setup opens a file picker")
    selectionIndex = selectionIndex + 1
    return selections[selectionIndex]
  end
  lamentMapper.isExecutablePath = function(_)
    return true
  end
  lamentMapper.saveExecutablePath = function(path)
    saved[#saved + 1] = path
    return true
  end
  lamentMapper.closeProcess = function()
    closeCount = closeCount + 1
  end

  equal(lamentMapper.setup(), true, "bare setup retains manual behavior")
  equal(lamentMapper.setup("manual"), true, "explicit manual setup behavior")
  equal(saved[1], selections[1], "bare setup saved path")
  equal(saved[2], selections[2], "manual setup saved path")
  equal(closeCount, 2, "manual setup closes managed process")

  invokeFileDialog = originalInvokeFileDialog
  lamentMapper.isExecutablePath = originalIsExecutablePath
  lamentMapper.saveExecutablePath = originalSaveExecutablePath
  lamentMapper.closeProcess = originalCloseProcess
end

do
  local originalSetup = lamentMapper.setup
  local dispatchedMode = "not called"
  lamentMapper.setup = function(mode)
    dispatchedMode = mode
  end

  matches = { "lamentmapper setup", nil }
  dofile("accessible_lament_map/src/aliases/Accessible Lament Map/LamentMapper_setup.lua")
  equal(dispatchedMode, nil, "bare alias dispatches manual default")

  matches = { "lamentmapper setup auto", "auto" }
  dofile("accessible_lament_map/src/aliases/Accessible Lament Map/LamentMapper_setup.lua")
  equal(dispatchedMode, "auto", "auto alias dispatch")

  matches = { "lamentmapper setup manual", "manual" }
  dofile("accessible_lament_map/src/aliases/Accessible Lament Map/LamentMapper_setup.lua")
  equal(dispatchedMode, "manual", "manual alias dispatch")
  lamentMapper.setup = originalSetup
end

do
  local originalGetenv = os.getenv
  local originalRemove = os.remove
  local originalOpen = io.open
  local removedPath = nil

  os.getenv = function(name)
    if name == "TEMP" then
      return [[C:\Unavailable]]
    end
    return originalGetenv(name)
  end
  io.open = function(path, mode)
    if mode == "rb" then
      return nil
    end
    if path:find([[C:\Unavailable\]], 1, true) == 1 then
      return nil, "simulated access denied"
    end
    return {
      close = function() end,
    }
  end
  os.remove = function(path)
    removedPath = path
    return true
  end

  local archivePath = lamentMapper.createTemporaryArchive()
  equal(archivePath:find([[.\lamentmapper-]], 1, true), 1, "profile directory temporary fallback")
  equal(removedPath, archivePath, "temporary probe removed")

  os.getenv = originalGetenv
  os.remove = originalRemove
  io.open = originalOpen
end

do
  local originalGetOS = getOS
  local originalDownloadFile = downloadFile
  local originalUnzipAsync = unzipAsync
  local originalInvokeFileDialog = invokeFileDialog
  local pickerCalls = 0

  invokeFileDialog = function(_, _)
    pickerCalls = pickerCalls + 1
    return ""
  end
  getOS = function()
    return "linux"
  end
  downloadFile = function(_, _) end
  unzipAsync = function(_, _)
    return true
  end
  equal(lamentMapper.setup("auto"), false, "automatic setup rejects non-Windows systems")
  equal(pickerCalls, 0, "unsupported system does not open picker")

  getOS = function()
    return "windows"
  end
  downloadFile = nil
  equal(lamentMapper.setup("auto"), false, "automatic setup requires download API")
  equal(echoed[#echoed - 1]:find("Mudlet 4.6", 1, true) ~= nil, true, "old Mudlet version diagnostic")

  downloadFile = function(_, _) end
  equal(lamentMapper.setup("auto"), false, "automatic setup handles folder-picker cancellation")
  equal(pickerCalls, 1, "automatic setup opens folder picker")

  lamentMapper.setupOperation = { stage = "downloading" }
  equal(lamentMapper.setup("auto"), false, "overlapping automatic setup rejected")
  equal(pickerCalls, 1, "overlapping setup does not open another picker")
  lamentMapper.setupOperation = nil

  getOS = originalGetOS
  downloadFile = originalDownloadFile
  unzipAsync = originalUnzipAsync
  invokeFileDialog = originalInvokeFileDialog
end

do
  local originalGetOS = getOS
  local originalDownloadFile = downloadFile
  local originalUnzipAsync = unzipAsync
  local originalInvokeFileDialog = invokeFileDialog
  local originalCreateTemporaryArchive = lamentMapper.createTemporaryArchive
  local originalCloseProcess = lamentMapper.closeProcess
  local originalIsReadableFile = lamentMapper.isReadableFile
  local originalSaveExecutablePath = lamentMapper.saveExecutablePath
  local originalRemove = os.remove
  local archivePath = [[C:\Temp\lamentmapper-success.zip]]
  local destinationPath = [[C:\Apps\LamentMapper]]
  local downloadedPath = nil
  local downloadedUrl = nil
  local unzipArchive = nil
  local unzipDestination = nil
  local closeCount = 0
  local savedPath = nil
  local removedPath = nil
  local readablePaths = {}

  getOS = function()
    return "windows"
  end
  invokeFileDialog = function(fileOrFolder, _)
    equal(fileOrFolder, false, "automatic setup opens a folder picker")
    return destinationPath
  end
  lamentMapper.createTemporaryArchive = function()
    return archivePath
  end
  downloadFile = function(path, url)
    downloadedPath = path
    downloadedUrl = url
  end
  unzipAsync = function(path, destination)
    unzipArchive = path
    unzipDestination = destination
    return true
  end
  lamentMapper.closeProcess = function()
    closeCount = closeCount + 1
  end
  lamentMapper.isReadableFile = function(path)
    readablePaths[#readablePaths + 1] = path
    return true
  end
  lamentMapper.saveExecutablePath = function(path)
    savedPath = path
    return true
  end
  os.remove = function(path)
    removedPath = path
    return true
  end
  lamentMapper.executablePath = [[C:\Existing\LamentMapper.exe]]
  lamentMapper.warnedMissing = true

  equal(lamentMapper.setup("auto"), true, "automatic setup starts")
  equal(downloadedPath, archivePath, "download target path")
  equal(downloadedUrl, lamentMapper.releaseUrl, "stable latest release URL")
  equal(savedPath, nil, "path not saved before validation")

  handlers.sysDownloadDone("sysDownloadDone", [[C:\Temp\unrelated.zip]])
  equal(unzipArchive, nil, "unrelated download completion ignored")
  handlers.sysDownloadDone("sysDownloadDone", archivePath)
  equal(closeCount, 1, "managed process closed before extraction")
  equal(unzipArchive, archivePath, "unzip archive path")
  equal(unzipDestination, destinationPath, "unzip destination path")

  handlers.sysUnzipDone("sysUnzipDone", archivePath, [[C:\Other]])
  equal(savedPath, nil, "unrelated unzip destination ignored")
  handlers.sysUnzipDone("sysUnzipDone", archivePath, destinationPath)

  local expectedExecutable = destinationPath .. [[\LamentMapper.exe]]
  equal(#readablePaths, 4, "all runtime files validated")
  for index, filename in ipairs(lamentMapper.requiredRuntimeFiles) do
    equal(readablePaths[index], destinationPath .. [[\]] .. filename, "validated runtime file " .. filename)
  end
  equal(savedPath, expectedExecutable, "inferred executable path saved after validation")
  equal(lamentMapper.executablePath, expectedExecutable, "automatic setup configured executable")
  equal(lamentMapper.warnedMissing, false, "automatic setup clears missing warning")
  equal(lamentMapper.setupOperation, nil, "successful setup clears operation")
  equal(removedPath, archivePath, "successful setup removes temporary archive")

  getOS = originalGetOS
  downloadFile = originalDownloadFile
  unzipAsync = originalUnzipAsync
  invokeFileDialog = originalInvokeFileDialog
  lamentMapper.createTemporaryArchive = originalCreateTemporaryArchive
  lamentMapper.closeProcess = originalCloseProcess
  lamentMapper.isReadableFile = originalIsReadableFile
  lamentMapper.saveExecutablePath = originalSaveExecutablePath
  os.remove = originalRemove
end

do
  local originalUnzipAsync = unzipAsync
  local originalCloseProcess = lamentMapper.closeProcess
  local originalIsReadableFile = lamentMapper.isReadableFile
  local originalSaveExecutablePath = lamentMapper.saveExecutablePath
  local originalRemove = os.remove
  local oldPath = [[C:\Existing\LamentMapper.exe]]
  local archivePath = [[C:\Temp\lamentmapper-failure.zip]]
  local destinationPath = [[C:\Apps\LamentMapper]]
  local saveCount = 0
  local removed = {}

  os.remove = function(path)
    removed[#removed + 1] = path
    return true
  end
  lamentMapper.saveExecutablePath = function(_)
    saveCount = saveCount + 1
    return true
  end
  lamentMapper.closeProcess = function() end
  lamentMapper.executablePath = oldPath

  lamentMapper.setupOperation = {
    archivePath = archivePath,
    destinationPath = destinationPath,
    executablePath = destinationPath .. [[\LamentMapper.exe]],
    stage = "downloading",
  }
  handlers.sysDownloadError("sysDownloadError", "unrelated failure", [[C:\Temp\other.zip]], "https://example.invalid")
  equal(lamentMapper.setupOperation.stage, "downloading", "unrelated download error ignored")
  handlers.sysDownloadError("sysDownloadError", "network unavailable", archivePath, lamentMapper.releaseUrl)
  equal(lamentMapper.setupOperation, nil, "download failure clears operation")
  equal(lamentMapper.executablePath, oldPath, "download failure preserves configured path")
  equal(saveCount, 0, "download failure does not save path")
  equal(echoed[#echoed]:find("setup manual", 1, true) ~= nil, true, "download failure prints manual recovery")

  lamentMapper.setupOperation = {
    archivePath = archivePath,
    destinationPath = destinationPath,
    executablePath = destinationPath .. [[\LamentMapper.exe]],
    stage = "downloading",
  }
  unzipAsync = function(_, _)
    return nil, "simulated synchronous rejection"
  end
  handlers.sysDownloadDone("sysDownloadDone", archivePath)
  equal(lamentMapper.setupOperation, nil, "synchronous unzip rejection clears operation")
  equal(echoed[#echoed - 1]:find("simulated synchronous rejection", 1, true) ~= nil, true,
      "synchronous unzip rejection diagnostic")

  lamentMapper.setupOperation = {
    archivePath = archivePath,
    destinationPath = destinationPath,
    executablePath = destinationPath .. [[\LamentMapper.exe]],
    stage = "extracting",
  }
  handlers.sysUnzipError("sysUnzipError", [[C:\Temp\other.zip]], destinationPath)
  equal(lamentMapper.setupOperation.stage, "extracting", "unrelated unzip error ignored")
  handlers.sysUnzipError("sysUnzipError", archivePath, destinationPath)
  equal(lamentMapper.setupOperation, nil, "asynchronous unzip failure clears operation")
  equal(lamentMapper.executablePath, oldPath, "unzip failure preserves configured path")

  lamentMapper.setupOperation = {
    archivePath = archivePath,
    destinationPath = destinationPath,
    executablePath = destinationPath .. [[\LamentMapper.exe]],
    stage = "extracting",
  }
  lamentMapper.isReadableFile = function(path)
    return not path:find("sounds.pack", 1, true) and not path:find("README.html", 1, true)
  end
  handlers.sysUnzipDone("sysUnzipDone", archivePath, destinationPath)
  equal(lamentMapper.setupOperation, nil, "incomplete extraction clears operation")
  equal(saveCount, 0, "incomplete extraction does not save path")
  equal(echoed[#echoed - 1]:find("sounds.pack, README.html", 1, true) ~= nil, true,
      "incomplete extraction lists missing files")
  equal(lamentMapper.executablePath, oldPath, "incomplete extraction preserves configured path")
  equal(#removed, 4, "temporary archive removed after every failure")

  unzipAsync = originalUnzipAsync
  lamentMapper.closeProcess = originalCloseProcess
  lamentMapper.isReadableFile = originalIsReadableFile
  lamentMapper.saveExecutablePath = originalSaveExecutablePath
  os.remove = originalRemove
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
  local originalYajl = yajl
  local originalSpawn = spawn
  local originalProcess = lamentMapper.process
  local originalPath = lamentMapper.executablePath
  local spawnCount = 0
  local spawnedPath = nil
  local sentPayload = nil

  yajl = { to_string = function(_) return "{}" end }
  spawn = function(_, path)
    spawnCount = spawnCount + 1
    spawnedPath = path
    return {
      isRunning = function()
        return true
      end,
      send = function(payload)
        sentPayload = payload
        return true
      end,
    }
  end
  lamentMapper.process = nil
  lamentMapper.executablePath = [[C:\Configured\LamentMapper.exe]]

  equal(lamentMapper.sendMap(validThree(), {}), true, "valid map launches configured executable")
  equal(spawnCount, 1, "valid map launch count")
  equal(spawnedPath, lamentMapper.executablePath, "valid map launched configured path")
  equal(sentPayload, "{}\n", "valid map sent after process launch")

  yajl = originalYajl
  spawn = originalSpawn
  lamentMapper.process = originalProcess
  lamentMapper.executablePath = originalPath
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
    "<yellow>LamentMapper is not configured. Run: lamentmapper setup auto (or 'lamentmapper setup manual' for an existing installation).\n",
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

do
  local originalRemove = os.remove
  local removedPath = nil
  lamentMapper.setupOperation = {
    archivePath = [[C:\Temp\lamentmapper-exit.zip]],
    stage = "downloading",
  }
  os.remove = function(path)
    removedPath = path
    return true
  end
  handlers.sysExitEvent("sysExitEvent")
  equal(removedPath, [[C:\Temp\lamentmapper-exit.zip]], "profile exit removes temporary archive")
  os.remove = originalRemove
end
equal(#lamentMapper.eventHandlers, 0, "profile exit handler cleanup")

lamentMapper.initialize()
equal(#lamentMapper.eventHandlers, 8, "handlers restored after reinitialization")
handlers.sysUninstallPackage("sysUninstallPackage", "Accessible Lament Map")
equal(#lamentMapper.eventHandlers, 0, "uninstall handler cleanup")

print("Mudlet capture tests passed")
