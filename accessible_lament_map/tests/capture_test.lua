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
equal(lamentMapper.packageName, "Accessible-Lament-Map", "canonical package name")
equal(lamentMapper.DEBUG, false, "debug diagnostics default to disabled")
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
    "<green>You can start using LamentMapper now. It will open automatically when Mudlet receives the next valid ASCII wilderness grid.\n",
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
  lamentMapper.validateExecutablePath = function(_)
    return true
  end

  equal(lamentMapper.sendMap(validThree(), {}), true, "valid map launches configured executable")
  equal(spawnCount, 1, "valid map launch count")
  equal(spawnedPath, lamentMapper.executablePath, "valid map launched configured path")
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
  equal(removedPath, [[C:/Temp/lamentmapper-exit.zip]], "profile exit removes canonical temporary archive")
  os.remove = originalRemove
end
equal(#lamentMapper.eventHandlers, 0, "profile exit handler cleanup")

lamentMapper.initialize()
equal(#lamentMapper.eventHandlers, 8, "handlers restored after reinitialization")

do
  local oldTable = lamentMapper
  local originalRemove = os.remove
  local originalKill = killAnonymousEventHandler
  local processClosed = false
  local helperClosed = false
  local removed = {}
  local killed = {}

  oldTable.process = { close = function() processClosed = true end }
  oldTable.focusHelper = { close = function() helperClosed = true end }
  oldTable.setupOperation = {
    archivePath = [[C:\Temp\stale-setup.zip]],
    stage = "extracting",
  }
  oldTable.sequence = 99
  oldTable.promptCount = 88
  os.remove = function(path)
    removed[#removed + 1] = path
    return true
  end
  killAnonymousEventHandler = function(handlerId)
    killed[#killed + 1] = handlerId
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
  equal(lamentMapper.DEBUG, false, "script reload resets debug diagnostics")
  equal(#lamentMapper.eventHandlers, 8, "fresh table registers its own handlers")

  os.remove = originalRemove
  killAnonymousEventHandler = originalKill
end

do
  local originalGetPackages = getPackages
  local originalUninstallPackage = uninstallPackage
  local originalRemove = os.remove
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
  lamentMapper.executablePath = [[C:/Obsolete/LamentMapper.exe]]

  handlers.sysInstallPackage("sysInstallPackage", "Accessible-Lament-Map")
  equal(uninstalled, "Accessible Lament Map", "hyphenated install removes legacy package")
  equal(type(lamentMapper), "table", "legacy uninstall event leaves new package active")
  equal(lamentMapper.executablePath, nil, "migration discards obsolete executable path")
  equal(removed[1], "./accessible-lament-map-executable.txt", "migration deletes new path state")
  equal(removed[2], "./lamentmapper-executable.txt", "migration deletes legacy path state")
  equal(echoed[#echoed]:find("fresh setup", 1, true) ~= nil, true,
      "migration requires one fresh setup")

  packages = { "Accessible Lament Map", "Accessible-Lament-Map" }
  uninstallPackage = function(_)
    return false
  end
  handlers.sysInstallPackage("sysInstallPackage", "Accessible-Lament-Map")
  equal(echoed[#echoed - 3]:find("could not remove the legacy package", 1, true) ~= nil, true,
      "failed legacy removal emits a clear warning")

  getPackages = originalGetPackages
  uninstallPackage = originalUninstallPackage
  os.remove = originalRemove
end

do
  local originalRemove = os.remove
  local originalKill = killAnonymousEventHandler
  local processClosed = false
  local helperClosed = false
  local removed = {}
  local killed = {}

  lamentMapper.process = { close = function() processClosed = true end }
  lamentMapper.focusHelper = { close = function() helperClosed = true end }
  lamentMapper.setupOperation = {
    archivePath = [[C:\Temp\uninstall-setup.zip]],
    stage = "downloading",
  }
  os.remove = function(path)
    removed[path] = true
    return true
  end
  killAnonymousEventHandler = function(handlerId)
    killed[#killed + 1] = handlerId
  end

  handlers.sysUninstallPackage("sysUninstallPackage", "Accessible-Lament-Map")
  equal(processClosed, true, "uninstall closes the managed process")
  equal(helperClosed, true, "uninstall closes the focus helper")
  equal(#killed, 8, "uninstall unregisters every anonymous handler")
  equal(removed["C:/Temp/uninstall-setup.zip"], true, "uninstall removes setup archive")
  equal(removed["./accessible-lament-map-executable.txt"], true, "uninstall deletes new path file")
  equal(removed["./lamentmapper-executable.txt"], true, "uninstall deletes legacy path file")
  equal(lamentMapper, nil, "uninstall clears the global table")

  os.remove = originalRemove
  killAnonymousEventHandler = originalKill
end

print("Mudlet capture tests passed")
