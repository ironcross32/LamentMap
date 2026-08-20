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

equal(lamentMapper.packageVersion, "1.2.0", "package diagnostic version")
equal(lamentMapper.packageName, "Accessible-Lament-Map", "canonical package name")
equal(lamentMapper.DEBUG, false, "debug diagnostics default to disabled")
equal(lamentMapper.enabled, true, "map capture defaults to enabled")
equal(handlerNumber, 8, "registered lifecycle and setup handlers")
equal(type(handlers.sysInstallPackage), "function", "install handler")
equal(type(handlers.sysDownloadDone), "function", "download completion handler")
equal(type(handlers.sysDownloadError), "function", "download error handler")
equal(type(handlers.sysUnzipDone), "function", "unzip completion handler")
equal(type(handlers.sysUnzipError), "function", "unzip error handler")
handlers.sysInstallPackage("sysInstallPackage", "Accessible-Lament-Map")
handlers.sysBufferShrinkEvent("sysBufferShrinkEvent", "main")

do
  local originalOpen = io.open
  local opened = {}
  local saved = nil

  equal(
    lamentMapper.profilePath(),
    "./accessible-lament-map-executable.txt",
    "package-scoped executable path file"
  )
  equal(lamentMapper.legacyProfilePath(), "./lamentmapper-executable.txt", "legacy path file")

  io.open = function(path, mode)
    opened[#opened + 1] = path
    if path == lamentMapper.profilePath() and mode == "rb" then
      return {
        read = function(_)
          return [[C:\Existing Install\LamentMapper.exe]]
        end,
        close = function(_) end,
      }
    end
    if path == [[C:/Existing Install/LamentMapper.exe]] and mode == "rb" then
      return { close = function(_) end }
    end
    if path == lamentMapper.profilePath() and mode == "wb" then
      return {
        write = function(_, pathValue, newline)
          saved = pathValue .. newline
        end,
        close = function(_) end,
      }
    end
    return nil, "unexpected path"
  end

  local loadedPath, loadedState = lamentMapper.readExecutablePath()
  equal(loadedPath, [[C:/Existing Install/LamentMapper.exe]], "legacy separators accepted from new state file")
  equal(loadedState, "usable", "canonicalized saved path is usable")
  equal(lamentMapper.saveExecutablePath([[D:\Mapper\LamentMapper.exe]]), true, "backslash path saves")
  equal(saved, "D:/Mapper/LamentMapper.exe\n", "saved executable uses forward slashes")
  for _, openedPath in ipairs(opened) do
    equal(openedPath ~= lamentMapper.legacyProfilePath(), true, "legacy state file is never imported")
  end

  io.open = originalOpen
end

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
  equal(saved[1], [[C:/Bare/LamentMapper.exe]], "bare setup saves a canonical path")
  equal(saved[2], [[C:/Manual/LamentMapper.exe]], "manual setup saves a canonical path")
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
  lamentMapper.DEBUG = false
  dofile("accessible_lament_map/src/aliases/Accessible Lament Map/LamentMapper_debug.lua")
  equal(lamentMapper.DEBUG, true, "debug alias enables rejection diagnostics")
  equal(echoed[#echoed], "<cyan>LamentMapper debug diagnostics enabled.\n", "debug enabled output")
  dofile("accessible_lament_map/src/aliases/Accessible Lament Map/LamentMapper_debug.lua")
  equal(lamentMapper.DEBUG, false, "debug alias disables rejection diagnostics")
  equal(echoed[#echoed], "<cyan>LamentMapper debug diagnostics disabled.\n", "debug disabled output")
end

do
  local originalGetLastLineNumber = getLastLineNumber
  local processClosed = false
  local helperClosed = false
  local promptCount = lamentMapper.promptCount

  lamentMapper.process = {
    close = function()
      processClosed = true
    end,
  }
  lamentMapper.focusHelper = {
    close = function()
      helperClosed = true
    end,
  }
  lamentMapper.automaticSurvey = { candidates = {} }
  lamentMapper.responseStart = 10
  lamentMapper.lastObservedLine = 20
  getLastLineNumber = function(_)
    error("disabled capture must not inspect the buffer")
  end

  dofile("accessible_lament_map/src/aliases/Accessible Lament Map/LamentMapper_toggle.lua")
  equal(lamentMapper.enabled, false, "toggle alias disables map capture")
  equal(processClosed, true, "disabling closes the managed mapper")
  equal(helperClosed, true, "disabling closes the focus helper")
  equal(lamentMapper.process, nil, "disabling clears the managed process")
  equal(lamentMapper.automaticSurvey, nil, "disabling clears an in-flight automatic survey")
  equal(lamentMapper.responseStart, nil, "disabling clears prompt capture state")
  equal(lamentMapper.lastObservedLine, nil, "disabling clears the observed buffer position")
  equal(lamentMapper.lastCaptureStatus, "Map capture disabled", "disabled capture status")
  equal(lamentMapper.onRoomEntry(), false, "disabled room entry does not start automatic capture")
  equal(lamentMapper.onAutomaticSurveyLine('"""*'), false, "disabled automatic line is ignored")
  lamentMapper.onPrompt()
  equal(lamentMapper.promptCount, promptCount, "disabled prompt does not run buffer capture")
  local sentWhileDisabled, disabledStatus = lamentMapper.sendMap({}, {})
  equal(sentWhileDisabled, false, "disabled direct map send is rejected")
  equal(disabledStatus, "Map capture is disabled", "disabled direct map status")
  equal(
    echoed[#echoed],
    "<cyan>LamentMapper activity disabled; map capture stopped and the mapper closed.\n",
    "disabled toggle output"
  )

  getLastLineNumber = function(_)
    return 17
  end
  dofile("accessible_lament_map/src/aliases/Accessible Lament Map/LamentMapper_toggle.lua")
  equal(lamentMapper.enabled, true, "second toggle reenables map capture")
  equal(lamentMapper.process, nil, "reenabling does not open the mapper")
  equal(lamentMapper.responseStart, 18, "reenabling starts with fresh prompt capture state")
  equal(
    echoed[#echoed],
    "<cyan>LamentMapper activity enabled; the mapper will open after the next valid map.\n",
    "enabled toggle output"
  )

  getLastLineNumber = originalGetLastLineNumber
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
    if path:find([[C:/Unavailable/]], 1, true) == 1 then
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
  equal(archivePath:find([[./lamentmapper-]], 1, true), 1, "profile directory temporary fallback")
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
  local archivePath = [[C:/Temp/lamentmapper-success.zip]]
  local parentPath = [[C:\Apps]]
  local destinationPath = [[C:/Apps/LamentMapper]]
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
    return parentPath
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
  equal(lamentMapper.setupOperation.destinationPath, destinationPath, "selected parent receives LamentMapper child")
  equal(savedPath, nil, "path not saved before validation")

  handlers.sysDownloadDone("sysDownloadDone", [[c:\temp\unrelated.zip]])
  equal(unzipArchive, nil, "unrelated download completion ignored")
  handlers.sysDownloadDone("sysDownloadDone", [[c:\TEMP\LAMENTMAPPER-SUCCESS.ZIP\]])
  equal(closeCount, 1, "managed process closed before extraction")
  equal(unzipArchive, archivePath, "unzip archive path")
  equal(unzipDestination, destinationPath, "unzip destination path")

  handlers.sysUnzipDone("sysUnzipDone", archivePath, [[C:\Other\]])
  equal(savedPath, nil, "unrelated unzip destination ignored")
  handlers.sysUnzipDone(
    "sysUnzipDone",
    [[c:\temp\LAMENTMAPPER-success.zip]],
    [[c:\APPS\lamentmapper\]]
  )

  local expectedExecutable = destinationPath .. [[/LamentMapper.exe]]
  equal(#readablePaths, 4, "all runtime files validated")
  for index, filename in ipairs(lamentMapper.requiredRuntimeFiles) do
    equal(readablePaths[index], destinationPath .. [[/]] .. filename, "validated runtime file " .. filename)
  end
  equal(savedPath, expectedExecutable, "inferred executable path saved after validation")
  equal(lamentMapper.executablePath, expectedExecutable, "automatic setup configured executable")
  equal(lamentMapper.warnedMissing, false, "automatic setup clears missing warning")
  equal(lamentMapper.setupOperation, nil, "successful setup clears operation")
  equal(removedPath, archivePath, "successful setup removes temporary archive")
  equal(
    echoed[#echoed - 1],
    "<green>LamentMapper extraction and setup are complete: " .. expectedExecutable .. "\n",
    "automatic setup announces extraction completion"
  )
  equal(
    echoed[#echoed],
    "<green>You can start using LamentMapper now. It will open automatically after the next completed wilderness room entry.\n",
    "automatic setup announces readiness"
  )

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
  local rows = {
    '        ""        ',
    '    fsfs""tt""    ',
    '  sf  tt""tttt==  ',
    '  ttttTT""tt""==  ',
    'TTtt----T*""==""""',
    '  tttt--TTfs==""  ',
    '  TTtt        tt  ',
    '                  ',
    '                  ',
  }
  local captured, first = lamentMapper.findMap(rows)
  equal(first, 1, "live swamp log first row")
  equal(#captured, 9, "live swamp log map captured")
  equal(lamentMapper.validateRows(captured), true, "live swamp log accepts sf and fs tokens")
  equal(captured[2]:sub(5, 6), "fs", "reversed swamp token retained")
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
  local aligned = lamentMapper.alignLineStyles({{
    start = 0,
    length = 8,
    foreground = { r = 7, g = 8, b = 9 },
    background = { r = 1, g = 2, b = 3 },
  }}, 8, 6)
  equal(#aligned, 1, "truncated automatic row retains one color run")
  equal(aligned[1].length, 6, "automatic row color run truncated to normalized width")
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
  local originalValidateExecutablePath = lamentMapper.validateExecutablePath
  local spawnCount = 0
  local spawnedPath = nil
  local spawnedCallback = nil
  local sentPayload = nil

  yajl = { to_string = function(_) return "{}" end }
  spawn = function(callback, path)
    spawnCount = spawnCount + 1
    spawnedCallback = callback
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
  lamentMapper.validateExecutablePath = function(_)
    return true
  end

  equal(lamentMapper.sendMap(validThree(), {}), true, "valid map launches configured executable")
  equal(spawnCount, 1, "valid map launch count")
  equal(spawnedPath, lamentMapper.executablePath, "valid map launched configured path")
  equal(spawnedCallback, lamentMapper.onProcessOutput, "managed process output callback")
  equal(sentPayload, "{}\n", "valid map sent after process launch")

  yajl = originalYajl
  spawn = originalSpawn
  lamentMapper.process = originalProcess
  lamentMapper.executablePath = originalPath
  lamentMapper.validateExecutablePath = originalValidateExecutablePath
end

do
  local originalOpen = io.open
  local originalPath = lamentMapper.executablePath
  local originalProcess = lamentMapper.process
  local originalOperation = lamentMapper.setupOperation

  io.open = function(path, mode)
    if path == [[C:/Valid/LamentMapper.exe]] and mode == "rb" then
      return { close = function(_) end }
    end
    if mode == "rb" then
      return nil, "simulated missing or unreadable file"
    end
    return originalOpen(path, mode)
  end
  lamentMapper.process = nil
  lamentMapper.executablePath = [[C:\Missing Folder\LamentMapper.exe]]
  lamentMapper.warnedMissing = false
  equal(lamentMapper.ensureProcess(), false, "missing configured executable is not launched")
  equal(
    echoed[#echoed]:find("C:/Missing Folder/LamentMapper.exe", 1, true) ~= nil,
    true,
    "missing executable diagnostic includes exact canonical path"
  )
  equal(
    echoed[#echoed]:find("simulated missing or unreadable file", 1, true) ~= nil,
    true,
    "missing executable diagnostic includes the read failure"
  )

  lamentMapper.setupOperation = { stage = "extracting" }
  local statusStart = #echoed
  lamentMapper.status()
  equal(echoed[statusStart + 2]:find("invalid or unreadable", 1, true) ~= nil, true,
      "status distinguishes an invalid executable")
  equal(echoed[statusStart + 3], "<cyan>Automatic setup: extracting\n", "status reports setup stage")
  equal(echoed[statusStart + 4], "<cyan>Map capture: enabled\n", "status reports capture activity")

  lamentMapper.executablePath = nil
  lamentMapper.setupOperation = nil
  lamentMapper.warnedMissing = false
  equal(lamentMapper.ensureProcess(), false, "absent executable path is not launched")
  equal(echoed[#echoed]:find("path is absent", 1, true) ~= nil, true,
      "absent executable path has a distinct diagnostic")
  statusStart = #echoed
  lamentMapper.status()
  equal(echoed[statusStart + 2]:find("not configured (absent)", 1, true) ~= nil, true,
      "status distinguishes an absent executable")

  lamentMapper.executablePath = [[C:\Valid\LamentMapper.exe]]
  statusStart = #echoed
  lamentMapper.status()
  equal(echoed[statusStart + 2]:find("C:/Valid/LamentMapper.exe (usable)", 1, true) ~= nil, true,
      "status distinguishes a usable executable")

  io.open = originalOpen
  lamentMapper.executablePath = originalPath
  lamentMapper.process = originalProcess
  lamentMapper.setupOperation = originalOperation
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
    "*** Your swamp lore skill improves. ***",
    "Your current surroundings are heavily wooded forest, and you can see up to six leagues away from here.",
    "You see no points of interest nearby.",
  }
  getLastLineNumber = function(_)
    return 4
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
  lamentMapper.DEBUG = false
  local before = #echoed
  lamentMapper.onPrompt()
  equal(
    lamentMapper.lastCaptureStatus,
    "Wilderness map rejected: no line contained exactly one player marker",
    "survey-without-grid status"
  )
  equal(#echoed, before, "survey rejection warning suppressed outside debug mode")

  lamentMapper.responseStart = 1
  lamentMapper.lastObservedLine = 0
  lamentMapper.warnedSurveyWithoutMap = false
  lamentMapper.DEBUG = true
  before = #echoed
  lamentMapper.onPrompt()
  equal(#echoed, before + 1, "survey rejection warning shown in debug mode")
  equal(echoed[#echoed]:find("rejected the grid", 1, true) ~= nil, true,
      "debug rejection warning is specific")
  lamentMapper.DEBUG = false
end

do
  local originalSend = send
  local originalDeleteLine = deleteLine
  local originalCaptureLineStyles = lamentMapper.captureLineStyles
  local originalCaptureStyles = lamentMapper.captureStyles
  local originalSendMap = lamentMapper.sendMap
  local originalGetLastLineNumber = getLastLineNumber
  local originalGetLines = getLines
  local originalLine = line
  local commands = {}
  local deleted = {}
  local events = {}
  local maps = {}
  local promptLine = 40

  send = function(command, echoCommand)
    commands[#commands + 1] = {
      command = command,
      echoCommand = echoCommand,
    }
  end
  deleteLine = function()
    deleted[#deleted + 1] = line
    events[#events + 1] = "delete:" .. tostring(line)
  end
  lamentMapper.captureLineStyles = function(text)
    events[#events + 1] = "capture:" .. text
    if #text == 0 then
      return {}
    end
    return {{
      start = 0,
      length = #text,
      foreground = { r = 12, g = 34, b = 56 },
      background = { r = 1, g = 2, b = 3 },
    }}
  end
  lamentMapper.captureStyles = function(rows, _, _)
    local styles = {}
    for _, row in ipairs(rows) do
      styles[#styles + 1] = {{
        start = 0,
        length = #row,
        foreground = { r = 90, g = 80, b = 70 },
        background = { r = 0, g = 0, b = 0 },
      }}
    end
    return styles
  end
  lamentMapper.sendMap = function(rows, styles)
    maps[#maps + 1] = {
      rows = rows,
      styles = styles,
    }
    return true, "Map transmitted successfully"
  end
  getLastLineNumber = function(_)
    return promptLine
  end

  local function receive(text)
    line = text
    if text:find("Your current surroundings are ", 1, true) == 1 then
      dofile("accessible_lament_map/src/triggers/Accessible Lament Map/LamentMapper_room_entry.lua")
    end
    dofile("accessible_lament_map/src/triggers/Accessible Lament Map/LamentMapper_automatic_survey_line.lua")
  end

  local departures = {
    "You begin walking north.",
    "You begin running south while carrying a fallen branch.",
    "You sprint east, dragging a corpse behind you.",
    "You limp west.",
    "You go northwest.",
    "You approach the old trail, then stop.",
    "You halt your movement.",
    "You stop dragging the fallen branch.",
  }
  for _, departure in ipairs(departures) do
    receive(departure)
  end
  equal(#commands, 0, "departure, pace, burden, go, approach, and halt lines do not survey early")

  receive("Your current surroundings are scrubland, and the border lies immediately behind you.")
  equal(#commands, 1, "instant border crossing surroundings line requests one survey")
  equal(commands[1].command, "survey leagues", "automatic survey command")
  equal(commands[1].echoCommand, false, "automatic survey command echo disabled")

  receive("")
  receive("A nightjar calls somewhere nearby.")
  receive("Mist")
  receive('"""*')
  receive("")
  receive("You can see up to six leagues away from here.")
  equal(#maps, 1, "automatic sparse grid produces exactly one map payload")
  equal(maps[1].rows[1], "      ", "automatic sparse outer row padded")
  equal(maps[1].rows[2], '"""*  ', "automatic sparse center row padded")
  equal(maps[1].styles[2][1].foreground.r, 12, "automatic grid foreground color retained")
  equal(maps[1].styles[2][1].background.b, 3, "automatic grid background color retained")
  equal(maps[1].styles[2][2].start, 4, "automatic sparse style padding aligned")
  equal(maps[1].styles[2][2].length, 2, "automatic sparse style padding width")
  equal(#deleted, 4, "automatic grid rows and visibility sentence gagged")
  equal(deleted[1], "", "automatic blank grid row gagged")
  equal(deleted[2], '"""*', "automatic center grid row gagged")
  equal(deleted[3], "", "automatic final grid row gagged")
  equal(deleted[4], "You can see up to six leagues away from here.", "automatic terminator gagged")
  equal(lamentMapper.isPotentialMapRow("Mist"), false, "map-like ambient word is not a recognized grid row")
  equal(events[1], "capture:", "automatic row captured before deletion")
  equal(events[2], "delete:", "automatic row deleted after capture")
  equal(lamentMapper.lastCaptureStatus, "Map transmitted successfully", "automatic capture status")

  local statusBeforePrompt = lamentMapper.lastCaptureStatus
  lamentMapper.onPrompt()
  equal(lamentMapper.automaticSurvey, nil, "prompt clears completed automatic survey state")
  equal(lamentMapper.lastCaptureStatus, statusBeforePrompt, "consumed prompt preserves automatic result")
  equal(#maps, 1, "consumed automatic prompt does not run ordinary capture")

  receive("Your current surroundings are open grassland.")
  receive("Your current surroundings are open grassland.")
  receive("Your current surroundings are open grassland.")
  equal(#commands, 2, "overlapping surroundings notifications do not send immediately")
  receive(validThree()[1])
  receive(validThree()[2])
  receive(validThree()[3])
  receive("You can see up to three leagues away from here.")
  equal(#maps, 2, "first coalesced automatic survey transmitted once")
  lamentMapper.onPrompt()
  equal(#commands, 3, "overlapping entries coalesce into one follow-up survey")
  equal(lamentMapper.automaticSurvey ~= nil, true, "follow-up survey starts after consumed prompt")

  receive(validThree()[1])
  receive('""**""')
  receive(validThree()[3])
  local deletedBeforeMalformedTerminator = #deleted
  receive("You can see up to three leagues away from here.")
  equal(#maps, 2, "malformed automatic grid is not transmitted")
  equal(#deleted, deletedBeforeMalformedTerminator + 1, "malformed automatic terminator still gagged")
  equal(
    lamentMapper.lastCaptureStatus:find("Automatic wilderness map rejected", 1, true) == 1,
    true,
    "malformed automatic grid has rejection status"
  )
  lamentMapper.onPrompt()
  equal(lamentMapper.automaticSurvey, nil, "prompt clears malformed completed survey")

  receive("Your current surroundings are dense forest.")
  receive(validThree()[1])
  lamentMapper.onPrompt()
  equal(lamentMapper.automaticSurvey, nil, "missing automatic terminator resets at prompt")
  equal(
    lamentMapper.lastCaptureStatus,
    "Automatic survey ended before its visibility sentence",
    "missing automatic terminator status"
  )

  receive("Your current surroundings are a riverbank.")
  equal(lamentMapper.automaticSurvey ~= nil, true, "automatic survey active before buffer shrink")
  handlers.sysBufferShrinkEvent("sysBufferShrinkEvent", "main")
  equal(lamentMapper.automaticSurvey, nil, "buffer shrink clears incomplete automatic survey")

  local manualRows = validThree()
  local deletedBeforeManual = #deleted
  for _, row in ipairs(manualRows) do
    receive(row)
  end
  receive("You can see up to three leagues away from here.")
  equal(#deleted, deletedBeforeManual, "manual survey output remains visible")
  getLines = function(_, first, last)
    local response = {
      manualRows[1],
      manualRows[2],
      manualRows[3],
      "You can see up to three leagues away from here.",
    }
    local result = {}
    for lineNumber = first, last do
      result[#result + 1] = response[lineNumber]
    end
    return result
  end
  promptLine = 5
  lamentMapper.responseStart = 1
  lamentMapper.lastObservedLine = 0
  lamentMapper.onPrompt()
  equal(#maps, 3, "manual survey remains prompt-captured")

  send = originalSend
  deleteLine = originalDeleteLine
  lamentMapper.captureLineStyles = originalCaptureLineStyles
  lamentMapper.captureStyles = originalCaptureStyles
  lamentMapper.sendMap = originalSendMap
  getLastLineNumber = originalGetLastLineNumber
  getLines = originalGetLines
  line = originalLine
  lamentMapper.resetAutomaticSurvey()
end

do
  local originalYajl = yajl
  local originalSend = send
  local originalTempTimer = tempTimer
  local originalKillTimer = killTimer
  local originalStartAutomaticSurvey = lamentMapper.startAutomaticSurvey
  local originalProcess = lamentMapper.process
  local timers = {}
  local delays = {}
  local killed = {}
  local commands = {}
  local nextTimer = 0
  local surveyRequests = 0
  local moveTwo = [[{"protocol_version":1,"type":"move","directions":["north","east"]}]]
  local moveSouth = [[{"protocol_version":1,"type":"move","directions":["south"]}]]
  local cancel = [[{"protocol_version":1,"type":"cancel_move"}]]
  local badDirection = [[{"protocol_version":1,"type":"move","directions":["up"]}]]
  local badVersion = [[{"protocol_version":2,"type":"cancel_move"}]]
  local badType = [[{"protocol_version":1,"type":"dance"}]]
  local decoded = {
    [moveTwo] = { protocol_version = 1, type = "move", directions = { "north", "east" } },
    [moveSouth] = { protocol_version = 1, type = "move", directions = { "south" } },
    [cancel] = { protocol_version = 1, type = "cancel_move" },
    [badDirection] = { protocol_version = 1, type = "move", directions = { "up" } },
    [badVersion] = { protocol_version = 2, type = "cancel_move" },
    [badType] = { protocol_version = 1, type = "dance" },
  }

  yajl = {
    to_value = function(text)
      if not decoded[text] then
        error("malformed JSON")
      end
      return decoded[text]
    end,
  }
  send = function(command, echoCommand)
    commands[#commands + 1] = { command = command, echoCommand = echoCommand }
  end
  tempTimer = function(delay, callback)
    nextTimer = nextTimer + 1
    delays[nextTimer] = delay
    timers[nextTimer] = callback
    return nextTimer
  end
  killTimer = function(timerId)
    killed[timerId] = true
    timers[timerId] = nil
  end
  local function fire(timerId)
    local callback = timers[timerId]
    timers[timerId] = nil
    if callback and not killed[timerId] then
      callback()
    end
  end
  lamentMapper.startAutomaticSurvey = function()
    surveyRequests = surveyRequests + 1
    lamentMapper.automaticSurvey = { candidates = {}, complete = false, followUp = false }
    return true
  end
  lamentMapper.resetAutomaticSurvey()
  lamentMapper.cancelAutomaticMovement(false)
  lamentMapper.resetProcessOutput()

  local split = 23
  lamentMapper.onProcessOutput(moveTwo:sub(1, split))
  equal(lamentMapper.automaticMovement, nil, "partial process output waits for newline")
  lamentMapper.onProcessOutput(moveTwo:sub(split + 1) .. "\n")
  equal(lamentMapper.automaticMovement ~= nil, true, "split movement message accepted")
  equal(#commands, 0, "accepted route waits for its initial timer")
  equal(delays[1] >= 0.5 and delays[1] <= 1.5, true, "initial movement delay is bounded")

  local beforeReject = #echoed
  lamentMapper.onProcessOutput(moveSouth .. "\n{" .. "\n")
  equal(#echoed, beforeReject + 2, "combined callback rejects active route and malformed line")
  equal(echoed[beforeReject + 1]:find("already active", 1, true) ~= nil, true,
      "active route rejection is reported in Mudlet")

  fire(1)
  equal(#commands, 1, "initial timer sends exactly one direction")
  equal(commands[1].command, "north", "first route direction")
  equal(commands[1].echoCommand, false, "automatic movement command echo disabled")
  equal(lamentMapper.automaticMovement.timer, nil, "route stalls without room confirmation")

  lamentMapper.onRoomEntry()
  equal(surveyRequests, 1, "room entry still starts automatic survey")
  equal(lamentMapper.automaticSurvey ~= nil, true, "room entry arms automatic map suppression")
  lamentMapper.resetAutomaticSurvey()
  equal(delays[2] >= 0.5 and delays[2] <= 1.5, true, "confirmed movement delay is bounded")
  equal(#commands, 1, "confirmation schedules rather than directly resuming")
  fire(2)
  equal(#commands, 2, "room confirmation permits one additional direction")
  equal(commands[2].command, "east", "second route direction")
  equal(lamentMapper.automaticMovement ~= nil, true, "final direction waits for destination confirmation")
  equal(lamentMapper.automaticMovement.awaitingFinalArrival, true, "final direction records pending arrival")
  equal(lamentMapper.scheduleAutomaticMovement(), false, "pending final arrival cannot schedule another command")

  local beforeComplete = #echoed
  lamentMapper.onRoomEntry()
  equal(lamentMapper.automaticMovement, nil, "destination confirmation clears movement state")
  equal(#commands, 2, "destination confirmation sends no extra direction")
  equal(surveyRequests, 2, "destination room still starts its automatic survey")
  equal(#echoed, beforeComplete + 1, "destination confirmation announces completion")
  equal(lamentMapper.automaticSurvey ~= nil, true, "destination map suppression remains armed")
  equal(echoed[#echoed], "<green>Automatic movement complete.\n", "movement completion status")

  lamentMapper.onProcessOutput(moveSouth .. "\n" .. cancel .. "\n")
  equal(killed[3], true, "Escape cancellation kills the pending timer")
  equal(lamentMapper.automaticMovement, nil, "Escape cancellation drops the coroutine")
  equal(echoed[#echoed], "<cyan>Automatic movement canceled.\n", "cancellation status")
  lamentMapper.onProcessOutput(cancel .. "\n")
  equal(echoed[#echoed], "<cyan>No automatic movement is active.\n", "idle cancellation status")

  local allDirections = {
    "north", "northeast", "east", "southeast",
    "south", "southwest", "west", "northwest",
  }
  local validated = lamentMapper.validateMovementDirections(allDirections)
  equal(#validated, 8, "all eight direction names are valid")
  local invalid = lamentMapper.validateMovementDirections({ "north", "up" })
  equal(invalid, nil, "unknown direction is rejected")

  local beforeInvalid = #echoed
  lamentMapper.onProcessOutput(badDirection .. "\n" .. badVersion .. "\n" .. badType .. "\n")
  equal(#echoed, beforeInvalid + 3, "invalid direction, version, and type are reported")
  lamentMapper.onProcessOutput(string.rep("x", lamentMapper.maxMessageBytes + 1)
      .. "\n" .. moveSouth .. "\n")
  equal(echoed[#echoed]:find("exceeds 1 MiB", 1, true) ~= nil, true,
      "oversized process message is rejected")
  equal(lamentMapper.automaticMovement ~= nil, true, "parser recovers after oversized line")

  lamentMapper.process = { close = function() end }
  local pendingTimer = lamentMapper.automaticMovement.timer
  lamentMapper.closeProcess()
  equal(killed[pendingTimer], true, "process shutdown kills movement timer")
  equal(lamentMapper.automaticMovement, nil, "process shutdown clears movement state")
  equal(lamentMapper.processOutputBuffer, "", "process shutdown clears partial output")

  yajl = originalYajl
  send = originalSend
  tempTimer = originalTempTimer
  killTimer = originalKillTimer
  lamentMapper.startAutomaticSurvey = originalStartAutomaticSurvey
  lamentMapper.process = originalProcess
  lamentMapper.resetAutomaticSurvey()
end

do
  local originalProcess = lamentMapper.process
  local originalPath = lamentMapper.executablePath
  local originalLoadPath = lamentMapper.loadExecutablePath
  local originalReadExecutablePath = lamentMapper.readExecutablePath
  local originalValidateExecutablePath = lamentMapper.validateExecutablePath
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
  lamentMapper.validateExecutablePath = function(_)
    return true
  end
  equal(lamentMapper.focusMapper(), true, "running mapper starts focus helper")
  equal(spawnCount, 1, "focus helper spawn count")
  equal(spawnedPath, [[C:/Apps/LamentMapper.exe]], "focus helper executable")
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
  lamentMapper.readExecutablePath = function()
    return nil, "absent", "not found"
  end
  equal(lamentMapper.focusMapper(), false, "missing focus helper configuration")
  equal(spawnCount, 1, "missing configuration does not spawn helper")
  equal(
    echoed[#echoed],
    "<yellow>LamentMapper executable path is absent. Run: lamentmapper setup auto (or 'lamentmapper setup manual' for an existing installation).\n",
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
  lamentMapper.readExecutablePath = originalReadExecutablePath
  lamentMapper.validateExecutablePath = originalValidateExecutablePath
  lamentMapper.isProcessRunning = originalIsProcessRunning
  spawn = originalSpawn
end

do
  equal(lamentMapper.compareSemVer("1.2.3", "1.2.2"), 1, "SemVer patch ordering")
  equal(lamentMapper.compareSemVer("1.2.3", "2.0.0"), -1, "SemVer major ordering")
  equal(lamentMapper.compareSemVer("1.2.3", "1.2.3"), 0, "SemVer equality")
  equal(lamentMapper.compareSemVer("1.02.3", "1.2.3"), nil, "SemVer rejects leading zeroes")
  equal(lamentMapper.compareSemVer("1.2.3-beta", "1.2.3"), nil, "SemVer rejects prereleases")

  lamentMapper.automaticUpdateChecks = true
  lamentMapper.lastSuccessfulUpdateCheck = 1000
  equal(lamentMapper.updateCheckDue(1000 + 24 * 60 * 60 - 1), false, "daily check waits 24 hours")
  equal(lamentMapper.updateCheckDue(1000 + 24 * 60 * 60), true, "daily check runs at 24 hours")
  lamentMapper.automaticUpdateChecks = false
  equal(lamentMapper.updateCheckDue(1000 + 48 * 60 * 60), false, "opt out suppresses checks")
  lamentMapper.automaticUpdateChecks = true

  equal(
    lamentMapper.sha256("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    "Lua 5.1 SHA-256 known vector"
  )

  local validManifest = {
    schema_version = 1,
    release_tag = "v9.8.7",
    release_url = "https://github.com/ironcross32/LamentMap/releases/tag/v9.8.7",
    mudlet = {
      version = "1.3.0",
      asset = {
        url = "https://github.com/ironcross32/LamentMap/releases/download/v9.8.7/Accessible-Lament-Map.mpackage",
        size = 7,
        sha256 = string.rep("a", 64),
      },
    },
  }
  local update = lamentMapper.validateUpdateManifest(validManifest)
  equal(update.version, "1.3.0", "valid manifest yields Mudlet update")
  validManifest.mudlet.asset.url = "https://example.invalid/Accessible-Lament-Map.mpackage"
  equal(lamentMapper.validateUpdateManifest(validManifest), nil, "foreign asset host rejected")
  validManifest.mudlet.asset.url =
      "https://github.com/ironcross32/LamentMap/releases/download/v9.8.7/wrong.mpackage"
  equal(lamentMapper.validateUpdateManifest(validManifest), nil, "unexpected asset name rejected")
  validManifest.mudlet.asset.url =
      "https://github.com/ironcross32/LamentMap/releases/download/v9.8.7/Accessible-Lament-Map.mpackage"
  validManifest.release_tag = "v9.8.7-beta"
  equal(lamentMapper.validateUpdateManifest(validManifest), nil, "prerelease tag rejected")
end

do
  local originalOpen = io.open
  local originalRemove = os.remove
  local originalInstallPackage = installPackage
  local packageData = "package"
  local packagePath = "./update-test.mpackage"
  local installedPath = nil
  local removed = {}

  io.open = function(path, mode)
    if lamentMapper.samePath(path, packagePath) and mode == "rb" then
      return {
        read = function() return packageData end,
        close = function() end,
      }
    end
    return nil, "unexpected file"
  end
  os.remove = function(path)
    removed[lamentMapper.normalizePath(path)] = true
    return true
  end
  installPackage = function(path)
    installedPath = path
    return true
  end

  lamentMapper.updateOperation = {
    stage = "package",
    packagePath = packagePath,
    update = {
      version = "1.3.0",
      size = #packageData,
      sha256 = lamentMapper.sha256(packageData),
      releaseUrl = "https://github.com/ironcross32/LamentMap/releases/tag/v9.8.7",
    },
  }
  handlers.sysDownloadDone("sysDownloadDone", "./unrelated.mpackage")
  equal(lamentMapper.updateOperation.stage, "package", "unrelated download event ignored by updater")
  handlers.sysDownloadDone("sysDownloadDone", packagePath)
  equal(installedPath, packagePath, "verified local package passed to installPackage")
  equal(lamentMapper.updateOperation.stage, "installing", "updater awaits package installation event")
  handlers.sysInstallPackage("sysInstallPackage", lamentMapper.packageName)
  equal(lamentMapper.updateOperation, nil, "successful installation clears updater state")
  equal(removed[packagePath], true, "successful installation removes temporary package")

  lamentMapper.updateOperation = {
    stage = "package",
    packagePath = packagePath,
    update = {
      version = "1.3.0",
      size = #packageData,
      sha256 = string.rep("0", 64),
      releaseUrl = "https://github.com/ironcross32/LamentMap/releases/tag/v9.8.7",
    },
  }
  installedPath = nil
  handlers.sysDownloadDone("sysDownloadDone", packagePath)
  equal(installedPath, nil, "hash mismatch never invokes installPackage")
  equal(lamentMapper.updateOperation, nil, "hash mismatch clears updater state")

  lamentMapper.updateOperation = {
    stage = "package",
    packagePath = packagePath,
    update = {
      version = "1.3.0",
      size = #packageData,
      sha256 = lamentMapper.sha256(packageData),
      releaseUrl = "https://github.com/ironcross32/LamentMap/releases/tag/v9.8.7",
    },
  }
  installPackage = function()
    return nil, "installation denied"
  end
  handlers.sysDownloadDone("sysDownloadDone", packagePath)
  equal(lamentMapper.updateOperation, nil, "installPackage error clears updater state")
  equal(echoed[#echoed - 1]:find("installation denied", 1, true) ~= nil, true,
      "installPackage error is reported")

  io.open = originalOpen
  os.remove = originalRemove
  installPackage = originalInstallPackage
end

do
  local originalRemove = os.remove
  local removed = {}
  lamentMapper.setupOperation = {
    archivePath = [[C:\Temp\lamentmapper-exit.zip]],
    stage = "downloading",
  }
  lamentMapper.updateOperation = {
    manifestPath = [[C:\Temp\uninstall-manifest.json]],
    packagePath = [[C:\Temp\uninstall-package.mpackage]],
    stage = "package",
  }
  os.remove = function(path)
    removed[lamentMapper.normalizePath(path)] = true
    return true
  end
  lamentMapper.automaticSurvey = { candidates = {} }
  lamentMapper.automaticMovement = {
    coroutine = coroutine.create(function() end),
  }
  handlers.sysExitEvent("sysExitEvent")
  equal(removed["C:/Temp/lamentmapper-exit.zip"], true,
      "profile exit removes canonical temporary archive")
  equal(removed["C:/Temp/uninstall-manifest.json"], true,
      "profile exit removes temporary update manifest")
  equal(removed["C:/Temp/uninstall-package.mpackage"], true,
      "profile exit removes temporary update package")
  equal(lamentMapper.automaticSurvey, nil, "profile exit clears automatic survey state")
  equal(lamentMapper.automaticMovement, nil, "profile exit clears automatic movement state")
  os.remove = originalRemove
end
equal(#lamentMapper.eventHandlers, 0, "profile exit handler cleanup")

lamentMapper.initialize()
equal(#lamentMapper.eventHandlers, 8, "handlers restored after reinitialization")

do
  local oldTable = lamentMapper
  local originalRemove = os.remove
  local originalKill = killAnonymousEventHandler
  local originalKillTimer = killTimer
  local processClosed = false
  local helperClosed = false
  local removed = {}
  local killed = {}
  local movementTimerKilled = false

  oldTable.process = { close = function() processClosed = true end }
  oldTable.focusHelper = { close = function() helperClosed = true end }
  oldTable.setupOperation = {
    archivePath = [[C:\Temp\stale-setup.zip]],
    stage = "extracting",
  }
  oldTable.sequence = 99
  oldTable.promptCount = 88
  oldTable.automaticSurvey = { candidates = { "stale" } }
  oldTable.automaticMovement = {
    coroutine = coroutine.create(function() coroutine.yield() end),
    timer = 777,
  }
  os.remove = function(path)
    removed[#removed + 1] = path
    return true
  end
  killAnonymousEventHandler = function(handlerId)
    killed[#killed + 1] = handlerId
  end
  killTimer = function(timerId)
    if timerId == 777 then
      movementTimerKilled = true
    end
  end

  dofile("accessible_lament_map/src/scripts/Accessible Lament Map/LamentMapper.lua")
  equal(lamentMapper ~= oldTable, true, "script reload creates a fresh global table")
  equal(processClosed, true, "script reload closes the old managed process")
  equal(helperClosed, true, "script reload closes the old focus helper")
  equal(removed[1], [[C:/Temp/stale-setup.zip]], "script reload removes stale setup archive")
  equal(removed[2], "./lamentmapper-executable.txt", "initialization removes legacy path file")
  equal(#killed, 8, "script reload unregisters every old anonymous handler")
  equal(lamentMapper.setupOperation, nil, "script reload discards stale setup state")
  equal(lamentMapper.sequence, 0, "script reload resets transport sequence")
  equal(lamentMapper.promptCount, 0, "script reload resets diagnostics")
  equal(lamentMapper.automaticSurvey, nil, "script reload discards stale automatic survey state")
  equal(movementTimerKilled, true, "script reload kills stale automatic movement timer")
  equal(lamentMapper.automaticMovement, nil, "script reload discards stale automatic movement state")
  equal(lamentMapper.DEBUG, false, "script reload resets debug diagnostics")
  equal(#lamentMapper.eventHandlers, 8, "fresh table registers its own handlers")

  os.remove = originalRemove
  killAnonymousEventHandler = originalKill
  killTimer = originalKillTimer
end

do
  local originalReadExecutablePath = lamentMapper.readExecutablePath
  local originalPath = lamentMapper.executablePath

  lamentMapper.executablePath = nil
  lamentMapper.readExecutablePath = function()
    return [[C:/Existing/LamentMapper.exe]], "usable"
  end
  handlers.sysInstallPackage("sysInstallPackage", "Accessible-Lament-Map")
  equal(lamentMapper.executablePath, [[C:/Existing/LamentMapper.exe]],
      "package update reuses a valid saved executable")
  equal(
    echoed[#echoed],
    "<green>Accessible Lament Map installed. Reusing the configured executable: "
        .. [[C:/Existing/LamentMapper.exe]] .. "\n",
    "package update announces saved executable reuse"
  )

  lamentMapper.executablePath = nil
  lamentMapper.readExecutablePath = function()
    return [[C:/Missing/LamentMapper.exe]], "invalid", "simulated missing file"
  end
  handlers.sysInstallPackage("sysInstallPackage", "Accessible-Lament-Map")
  equal(
    echoed[#echoed]:find("Configured LamentMapper executable is invalid or unreadable", 1, true) ~= nil,
    true,
    "package update rejects an invalid saved executable"
  )
  equal(echoed[#echoed]:find("lamentmapper setup auto", 1, true) ~= nil, true,
      "invalid saved executable receives setup guidance")

  lamentMapper.readExecutablePath = originalReadExecutablePath
  lamentMapper.executablePath = originalPath
end

do
  local originalGetPackages = getPackages
  local originalUninstallPackage = uninstallPackage
  local originalRemove = os.remove
  local originalValidateExecutablePath = lamentMapper.validateExecutablePath
  local packages = { "Accessible Lament Map", "Accessible-Lament-Map" }
  local uninstalled = nil
  local removed = {}

  getPackages = function()
    return packages
  end
  uninstallPackage = function(packageName)
    uninstalled = packageName
    handlers.sysUninstallPackage("sysUninstallPackage", packageName)
    packages = { "Accessible-Lament-Map" }
    return true
  end
  os.remove = function(path)
    removed[#removed + 1] = path
    return true
  end
  lamentMapper.executablePath = [[C:/Existing/LamentMapper.exe]]
  lamentMapper.validateExecutablePath = function(_)
    return true
  end

  handlers.sysInstallPackage("sysInstallPackage", "Accessible-Lament-Map")
  equal(uninstalled, "Accessible Lament Map", "hyphenated install removes legacy package")
  equal(type(lamentMapper), "table", "legacy uninstall event leaves new package active")
  equal(lamentMapper.executablePath, [[C:/Existing/LamentMapper.exe]],
      "migration preserves the canonical executable path")
  equal(removed[1], "./lamentmapper-executable.txt", "migration deletes only legacy path state")
  equal(removed[2], nil, "migration does not delete canonical path state")
  equal(echoed[#echoed]:find("Reusing the configured executable", 1, true) ~= nil, true,
      "migration announces canonical path reuse")

  packages = { "Accessible Lament Map", "Accessible-Lament-Map" }
  uninstallPackage = function(_)
    return false
  end
  handlers.sysInstallPackage("sysInstallPackage", "Accessible-Lament-Map")
  equal(echoed[#echoed - 1]:find("could not remove the legacy package", 1, true) ~= nil, true,
      "failed legacy removal emits a clear warning")

  getPackages = originalGetPackages
  uninstallPackage = originalUninstallPackage
  os.remove = originalRemove
  lamentMapper.validateExecutablePath = originalValidateExecutablePath
end

do
  local originalRemove = os.remove
  local originalKill = killAnonymousEventHandler
  local originalKillTimer = killTimer
  local processClosed = false
  local helperClosed = false
  local removed = {}
  local killed = {}
  local movementTimerKilled = false

  lamentMapper.process = { close = function() processClosed = true end }
  lamentMapper.focusHelper = { close = function() helperClosed = true end }
  lamentMapper.setupOperation = {
    archivePath = [[C:\Temp\uninstall-setup.zip]],
    stage = "downloading",
  }
  lamentMapper.updateOperation = {
    manifestPath = [[C:\Temp\uninstall-manifest.json]],
    packagePath = [[C:\Temp\uninstall-package.mpackage]],
    stage = "package",
  }
  lamentMapper.automaticMovement = {
    coroutine = coroutine.create(function() coroutine.yield() end),
    timer = 888,
  }
  os.remove = function(path)
    removed[path] = true
    return true
  end
  killAnonymousEventHandler = function(handlerId)
    killed[#killed + 1] = handlerId
  end
  killTimer = function(timerId)
    if timerId == 888 then
      movementTimerKilled = true
    end
  end

  handlers.sysUninstallPackage("sysUninstallPackage", "Accessible-Lament-Map")
  equal(processClosed, true, "uninstall closes the managed process")
  equal(helperClosed, true, "uninstall closes the focus helper")
  equal(movementTimerKilled, true, "uninstall kills automatic movement timer")
  equal(#killed, 8, "uninstall unregisters every anonymous handler")
  equal(removed["C:/Temp/uninstall-setup.zip"], true, "uninstall removes setup archive")
  equal(removed["C:/Temp/uninstall-manifest.json"], true, "uninstall removes update manifest")
  equal(removed["C:/Temp/uninstall-package.mpackage"], true, "uninstall removes update package")
  equal(removed["./accessible-lament-map-executable.txt"], nil,
      "uninstall preserves canonical executable path state")
  equal(removed["./lamentmapper-executable.txt"], nil, "uninstall leaves path records untouched")
  equal(lamentMapper, nil, "uninstall clears the global table")

  os.remove = originalRemove
  killAnonymousEventHandler = originalKill
  killTimer = originalKillTimer
end

print("Mudlet capture tests passed")
