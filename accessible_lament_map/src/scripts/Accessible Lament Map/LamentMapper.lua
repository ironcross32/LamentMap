-- LamentMapper Mudlet transport. All package state and functions live here.
local previousLamentMapper = rawget(_G, "lamentMapper")
if type(previousLamentMapper) == "table" then
  local function closePreviousResource(resource)
    if resource then
      pcall(function()
        resource.close()
      end)
    end
  end
  closePreviousResource(previousLamentMapper.process)
  closePreviousResource(previousLamentMapper.focusHelper)
  local previousOperation = previousLamentMapper.setupOperation
  if type(previousOperation) == "table" and previousOperation.archivePath then
    pcall(os.remove, tostring(previousOperation.archivePath):gsub("\\", "/"))
  end
  if type(previousLamentMapper.eventHandlers) == "table" then
    for _, handlerId in ipairs(previousLamentMapper.eventHandlers) do
      pcall(killAnonymousEventHandler, handlerId)
    end
  end
end

lamentMapper = {}

lamentMapper.packageName = "Accessible-Lament-Map"
lamentMapper.legacyPackageName = "Accessible Lament Map"
lamentMapper.packageVersion = "1.1.0"
lamentMapper.protocolVersion = 1
lamentMapper.maxMessageBytes = 1024 * 1024
lamentMapper.process = nil
lamentMapper.focusHelper = nil
lamentMapper.sequence = 0
lamentMapper.responseStart = nil
lamentMapper.lastObservedLine = nil
lamentMapper.eventHandlers = {}
lamentMapper.setupOperation = nil
lamentMapper.setupSequence = 0
lamentMapper.legacyRemovalInProgress = false
lamentMapper.DEBUG = false
lamentMapper.warnedMissing = false
lamentMapper.promptCount = 0
lamentMapper.mapsSent = 0
lamentMapper.lastCaptureStatus = "Waiting for a prompt boundary"
lamentMapper.warnedSurveyWithoutMap = false
lamentMapper.landmarkRemainders = {
  ["^"] = true,
  ['"'] = true,
  ["t"] = true,
  ["T"] = true,
  ["n"] = true,
  ["-"] = true,
  ["\\"] = true,
  ["M"] = true,
  ["f"] = true,
  ["s"] = true,
  ["."] = true,
  ["v"] = true,
  ["~"] = true,
  ["i"] = true,
  ["="] = true,
}
lamentMapper.validTokens = {
  ["  "] = true,
  ["^^"] = true,
  ['""'] = true,
  ["tt"] = true,
  ["TT"] = true,
  ["nn"] = true,
  ["V-"] = true,
  ["/\\"] = true,
  ["MM"] = true,
  ["sf"] = true,
  ["fs"] = true,
  ["ss"] = true,
  ["--"] = true,
  [".."] = true,
  [".n"] = true,
  [".v"] = true,
  ["~~"] = true,
  ["ii"] = true,
  ["=="] = true,
  ['x"'] = true,
  ["xt"] = true,
  ["xT"] = true,
  ["ft"] = true,
  ["FT"] = true,
  ["x^"] = true,
  ["x-"] = true,
  ["x~"] = true,
  ["##"] = true,
  ["@@"] = true,
}

function lamentMapper.trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

function lamentMapper.normalizePath(path)
  if type(path) ~= "string" then
    return nil
  end
  path = lamentMapper.trim(path):gsub('^"', ""):gsub('"$', ""):gsub("\\", "/")
  if path == "" then
    return nil
  end
  return path
end

function lamentMapper.joinPath(directory, name)
  directory = lamentMapper.normalizePath(tostring(directory or "")) or ""
  directory = directory:gsub("/+$", "")
  return directory .. "/" .. tostring(name or ""):gsub("^/+", "")
end

function lamentMapper.profilePath()
  return lamentMapper.joinPath(getMudletHomeDir(), "accessible-lament-map-executable.txt")
end

function lamentMapper.legacyProfilePath()
  return lamentMapper.joinPath(getMudletHomeDir(), "lamentmapper-executable.txt")
end

function lamentMapper.pathComparisonKey(path)
  path = lamentMapper.normalizePath(path)
  if not path then
    return nil
  end
  if not path:match("^%a:/$") and path ~= "/" and not path:match("^//[^/]+/[^/]+/$") then
    path = path:gsub("/+$", "")
  end
  return path:lower()
end

function lamentMapper.samePath(left, right)
  local leftKey = lamentMapper.pathComparisonKey(left)
  local rightKey = lamentMapper.pathComparisonKey(right)
  return leftKey ~= nil and leftKey == rightKey
end

function lamentMapper.normalizeExecutablePath(path)
  return lamentMapper.normalizePath(path)
end

function lamentMapper.validateExecutablePath(path)
  path = lamentMapper.normalizeExecutablePath(path)
  if not path then
    return false, "the path is empty"
  end
  if not path:lower():match("/lamentmapper%.exe$") then
    return false, "the file name must be LamentMapper.exe"
  end
  local handle, reason = io.open(path, "rb")
  if not handle then
    return false, tostring(reason or "the file is missing or unreadable")
  end
  handle:close()
  return true
end

function lamentMapper.isExecutablePath(path)
  return lamentMapper.validateExecutablePath(path)
end

function lamentMapper.readExecutablePath()
  local handle, reason = io.open(lamentMapper.profilePath(), "rb")
  if not handle then
    return nil, "absent", tostring(reason or "the path file is missing or unreadable")
  end
  local path = lamentMapper.normalizeExecutablePath(handle:read("*a") or "")
  handle:close()
  if not path then
    return nil, "invalid", "the saved path is empty"
  end
  local valid, validationReason = lamentMapper.validateExecutablePath(path)
  if not valid then
    return path, "invalid", validationReason
  end
  return path, "usable"
end

function lamentMapper.loadExecutablePath()
  local path, state, reason = lamentMapper.readExecutablePath()
  if state == "usable" then
    return path
  end
  return nil, state, reason, path
end

function lamentMapper.configuredExecutable()
  local path = lamentMapper.normalizeExecutablePath(lamentMapper.executablePath)
  if not path then
    local savedPath, state, reason = lamentMapper.readExecutablePath()
    lamentMapper.executablePath = savedPath
    return savedPath, state, reason
  end
  lamentMapper.executablePath = path
  local valid, reason = lamentMapper.validateExecutablePath(path)
  if not valid then
    return path, "invalid", reason
  end
  return path, "usable"
end

function lamentMapper.saveExecutablePath(path)
  path = lamentMapper.normalizeExecutablePath(path)
  if not path then
    return false, "the executable path is empty"
  end
  local handle, reason = io.open(lamentMapper.profilePath(), "wb")
  if not handle then
    return false, reason
  end
  handle:write(path, "\n")
  handle:close()
  return true
end

lamentMapper.releaseUrl = "https://github.com/ironcross32/LamentMap/releases/latest/download/LamentMapper-windows-x64.zip"
lamentMapper.requiredRuntimeFiles = {
  "LamentMapper.exe",
  "prism.dll",
  "sounds.pack",
  "README.html",
}

function lamentMapper.isReadableFile(path)
  path = lamentMapper.normalizePath(path)
  local handle = io.open(path, "rb")
  if not handle then
    return false
  end
  handle:close()
  return true
end

function lamentMapper.deletePathFiles()
  pcall(os.remove, lamentMapper.profilePath())
  pcall(os.remove, lamentMapper.legacyProfilePath())
end

function lamentMapper.createTemporaryArchive()
  local directories = {}
  local temporaryDirectory = os.getenv("TEMP")
  if type(temporaryDirectory) == "string" and lamentMapper.trim(temporaryDirectory) ~= "" then
    directories[#directories + 1] = lamentMapper.normalizePath(temporaryDirectory)
  end
  local profileDirectory = lamentMapper.normalizePath(getMudletHomeDir())
  if #directories == 0 or not lamentMapper.samePath(directories[1], profileDirectory) then
    directories[#directories + 1] = profileDirectory
  end

  local lastReason = "no writable temporary directory was available"
  for _, directory in ipairs(directories) do
    for _ = 1, 100 do
      lamentMapper.setupSequence = lamentMapper.setupSequence + 1
      local filename = "lamentmapper-" .. tostring(os.time()) .. "-"
          .. tostring(lamentMapper.setupSequence) .. ".zip"
      local path = lamentMapper.joinPath(directory, filename)
      local existing = io.open(path, "rb")
      if existing then
        existing:close()
      else
        local probe, reason = io.open(path, "wb")
        if probe then
          probe:close()
          os.remove(path)
          return path
        end
        lastReason = tostring(reason)
        break
      end
    end
  end
  return nil, lastReason
end

function lamentMapper.printManualRecovery()
  cecho("<yellow>Manual setup: download the latest LamentMapper Windows x64 release ZIP, extract it, then run 'lamentmapper setup manual' and select LamentMapper.exe.\n")
end

function lamentMapper.clearAutoSetup()
  local operation = lamentMapper.setupOperation
  lamentMapper.setupOperation = nil
  if operation and operation.archivePath then
    pcall(os.remove, lamentMapper.normalizePath(operation.archivePath))
  end
end

function lamentMapper.failAutoSetup(stage, reason)
  cecho("<red>LamentMapper automatic setup failed during " .. tostring(stage) .. ": "
      .. tostring(reason or "unknown error") .. "\n")
  lamentMapper.clearAutoSetup()
  lamentMapper.printManualRecovery()
  return false
end

function lamentMapper.setupManual()
  local selected = invokeFileDialog(true, "Select LamentMapper.exe")
  if not selected or selected == "" then
    cecho("<yellow>LamentMapper setup cancelled.\n")
    return false
  end
  selected = lamentMapper.normalizeExecutablePath(selected)
  if not lamentMapper.isExecutablePath(selected) then
    cecho("<red>Please select a file named LamentMapper.exe.\n")
    return false
  end
  local ok, reason = lamentMapper.saveExecutablePath(selected)
  if not ok then
    cecho("<red>Could not save the LamentMapper path: " .. tostring(reason) .. "\n")
    return false
  end
  lamentMapper.executablePath = selected
  lamentMapper.warnedMissing = false
  lamentMapper.closeProcess()
  cecho("<green>LamentMapper configured: " .. selected .. "\n")
  cecho("<cyan>LamentMapper will start when Mudlet receives a valid ASCII wilderness grid. Use 'survey leagues' or disable Lament's in-game screen-reader mode if automatic grids are hidden.\n")
  return true
end

function lamentMapper.setupAuto()
  if lamentMapper.setupOperation then
    cecho("<yellow>LamentMapper automatic setup is already in progress.\n")
    return false
  end
  if type(getOS) ~= "function" or getOS() ~= "windows" then
    cecho("<red>LamentMapper automatic setup is only available on Windows x64 because the application and release artifact are Windows-only.\n")
    lamentMapper.printManualRecovery()
    return false
  end
  if type(downloadFile) ~= "function" or type(unzipAsync) ~= "function" then
    cecho("<red>LamentMapper automatic setup requires Mudlet 4.6 or newer with downloadFile and unzipAsync support.\n")
    lamentMapper.printManualRecovery()
    return false
  end

  local parentDirectory = invokeFileDialog(
    false,
    "Select the parent folder that should contain the LamentMapper folder"
  )
  if not parentDirectory or parentDirectory == "" then
    cecho("<yellow>LamentMapper automatic setup cancelled.\n")
    return false
  end
  parentDirectory = lamentMapper.normalizePath(parentDirectory)
  local destination = lamentMapper.joinPath(parentDirectory, "LamentMapper")

  local archivePath, reason = lamentMapper.createTemporaryArchive()
  if not archivePath then
    return lamentMapper.failAutoSetup("temporary archive creation", reason)
  end

  lamentMapper.setupOperation = {
    archivePath = archivePath,
    destinationPath = destination,
    executablePath = lamentMapper.joinPath(destination, "LamentMapper.exe"),
    stage = "downloading",
  }
  cecho("<cyan>Downloading the latest LamentMapper Windows x64 release...\n")
  local ok, downloadReason = pcall(downloadFile, archivePath, lamentMapper.releaseUrl)
  if not ok then
    return lamentMapper.failAutoSetup("download startup", downloadReason)
  end
  return true
end

function lamentMapper.setup(mode)
  if mode == nil or mode == "" or mode == "manual" then
    return lamentMapper.setupManual()
  end
  if mode == "auto" then
    return lamentMapper.setupAuto()
  end
  cecho("<red>Unknown setup mode. Use 'lamentmapper setup auto' or 'lamentmapper setup manual'.\n")
  return false
end

function lamentMapper.onDownloadDone(_, filename)
  local operation = lamentMapper.setupOperation
  if not operation or operation.stage ~= "downloading"
      or not lamentMapper.samePath(filename, operation.archivePath) then
    return
  end
  operation.stage = "extracting"
  lamentMapper.closeProcess()
  cecho("<cyan>Download complete. Extracting LamentMapper into " .. operation.destinationPath .. "...\n")
  local ok, started, reason = pcall(unzipAsync, operation.archivePath, operation.destinationPath)
  if not ok then
    lamentMapper.failAutoSetup("extraction startup", started)
  elseif not started then
    lamentMapper.failAutoSetup("extraction startup", reason or "Mudlet could not start ZIP extraction")
  end
end

function lamentMapper.onDownloadError(_, reason, filename, _)
  local operation = lamentMapper.setupOperation
  if not operation or operation.stage ~= "downloading"
      or not lamentMapper.samePath(filename, operation.archivePath) then
    return
  end
  lamentMapper.failAutoSetup("download", reason)
end

function lamentMapper.onUnzipDone(_, archivePath, destinationPath)
  local operation = lamentMapper.setupOperation
  if not operation or operation.stage ~= "extracting"
      or not lamentMapper.samePath(archivePath, operation.archivePath)
      or not lamentMapper.samePath(destinationPath, operation.destinationPath) then
    return
  end

  local missing = {}
  for _, filename in ipairs(lamentMapper.requiredRuntimeFiles) do
    local path = lamentMapper.joinPath(operation.destinationPath, filename)
    if not lamentMapper.isReadableFile(path) then
      missing[#missing + 1] = filename
    end
  end
  if #missing > 0 then
    lamentMapper.failAutoSetup("extracted-file validation", "missing or unreadable: " .. table.concat(missing, ", "))
    return
  end

  local ok, reason = lamentMapper.saveExecutablePath(operation.executablePath)
  if not ok then
    lamentMapper.failAutoSetup("configuration save", reason)
    return
  end
  local executablePath = operation.executablePath
  lamentMapper.executablePath = executablePath
  lamentMapper.warnedMissing = false
  lamentMapper.clearAutoSetup()
  cecho("<green>LamentMapper extraction and setup are complete: " .. executablePath .. "\n")
  cecho("<green>You can start using LamentMapper now. It will open automatically when Mudlet receives the next valid ASCII wilderness grid.\n")
end

function lamentMapper.onUnzipError(_, archivePath, destinationPath)
  local operation = lamentMapper.setupOperation
  if not operation or operation.stage ~= "extracting"
      or not lamentMapper.samePath(archivePath, operation.archivePath)
      or not lamentMapper.samePath(destinationPath, operation.destinationPath) then
    return
  end
  lamentMapper.failAutoSetup("extraction", "Mudlet reported that ZIP extraction failed")
end

function lamentMapper.isProcessRunning()
  if not lamentMapper.process then
    return false
  end
  local ok, running = pcall(function()
    return lamentMapper.process.isRunning()
  end)
  return ok and running == true
end

function lamentMapper.closeProcess()
  local process = lamentMapper.process
  lamentMapper.process = nil
  if process then
    pcall(function()
      process.close()
    end)
  end
end

function lamentMapper.closeFocusHelper()
  local helper = lamentMapper.focusHelper
  lamentMapper.focusHelper = nil
  if helper then
    pcall(function()
      helper.close()
    end)
  end
end

function lamentMapper.onFocusHelperOutput(output)
  local message = lamentMapper.trim(tostring(output or ""))
  if message == "" then
    return
  end
  if message:sub(1, 3) == "OK:" then
    cecho("<green>" .. lamentMapper.trim(message:sub(4)) .. "\n")
  elseif message:sub(1, 6) == "ERROR:" then
    cecho("<red>" .. lamentMapper.trim(message:sub(7)) .. "\n")
  else
    cecho("<red>LamentMapper focus helper: " .. message .. "\n")
  end
end

function lamentMapper.reportExecutableProblem(path, state, reason)
  if state == "invalid" and path then
    cecho("<red>Configured LamentMapper executable is invalid or unreadable: " .. path
        .. " (" .. tostring(reason or "unknown reason") .. "). Run: lamentmapper setup auto"
        .. " (or 'lamentmapper setup manual' for an existing installation).\n")
  else
    cecho("<yellow>LamentMapper executable path is absent. Run: lamentmapper setup auto"
        .. " (or 'lamentmapper setup manual' for an existing installation).\n")
  end
end

function lamentMapper.focusMapper()
  if not lamentMapper.isProcessRunning() then
    cecho("<yellow>No LamentMapper window is available; the managed mapper is not running.\n")
    return false
  end
  local path, pathState, reason = lamentMapper.configuredExecutable()
  if pathState ~= "usable" then
    lamentMapper.reportExecutableProblem(path, pathState, reason)
    return false
  end
  local ok, helperOrReason = pcall(function()
    return spawn(lamentMapper.onFocusHelperOutput, path, "--focus-existing")
  end)
  if not ok or not helperOrReason then
    cecho("<red>Could not focus LamentMapper: " .. tostring(helperOrReason) .. "\n")
    return false
  end
  lamentMapper.focusHelper = helperOrReason
  return true
end

function lamentMapper.status()
  local path, pathState, reason = lamentMapper.configuredExecutable()
  local configured = "not configured (absent)"
  if pathState == "usable" then
    configured = path .. " (usable)"
  elseif pathState == "invalid" then
    configured = tostring(path or "not configured") .. " (invalid or unreadable: "
        .. tostring(reason or "unknown reason") .. ")"
  end
  local processState = lamentMapper.isProcessRunning() and "running" or "not running"
  local setupStage = lamentMapper.setupOperation and lamentMapper.setupOperation.stage or "not active"
  cecho("<cyan>Accessible Lament Map package: " .. lamentMapper.packageVersion .. "\n")
  cecho("<cyan>LamentMapper path: " .. configured .. "\n")
  cecho("<cyan>Automatic setup: " .. setupStage .. "\n")
  cecho("<cyan>Debug diagnostics: " .. (lamentMapper.DEBUG and "enabled" or "disabled") .. "\n")
  cecho("<cyan>LamentMapper managed process: " .. processState .. "\n")
  cecho("<cyan>Prompt boundaries observed: " .. tostring(lamentMapper.promptCount) .. "\n")
  cecho("<cyan>Maps transmitted: " .. tostring(lamentMapper.mapsSent) .. "\n")
  cecho("<cyan>Last capture result: " .. tostring(lamentMapper.lastCaptureStatus) .. "\n")
  if pathState == "usable" and processState ~= "running" then
    cecho("<yellow>Close any manually launched LamentMapper window. Mudlet must launch the application to provide its map stream.\n")
  end
end

function lamentMapper.toggleDebug()
  lamentMapper.DEBUG = not lamentMapper.DEBUG
  if lamentMapper.DEBUG then
    lamentMapper.warnedSurveyWithoutMap = false
  end
  cecho("<cyan>LamentMapper debug diagnostics "
      .. (lamentMapper.DEBUG and "enabled" or "disabled") .. ".\n")
  return lamentMapper.DEBUG
end

function lamentMapper.ensureProcess()
  if lamentMapper.isProcessRunning() then
    return true
  end
  lamentMapper.process = nil
  local path, pathState, reason = lamentMapper.configuredExecutable()
  if pathState ~= "usable" then
    if not lamentMapper.warnedMissing then
      lamentMapper.reportExecutableProblem(path, pathState, reason)
      lamentMapper.warnedMissing = true
    end
    return false
  end
  lamentMapper.warnedMissing = false
  local ok, processOrReason = pcall(function()
    return spawn(function(_) end, path)
  end)
  if not ok or not processOrReason then
    cecho("<red>Could not start LamentMapper: " .. tostring(processOrReason) .. "\n")
    return false
  end
  lamentMapper.process = processOrReason
  return true
end

function lamentMapper.countStars(line)
  local count = 0
  local position = 1
  while true do
    local found = line:find("*", position, true)
    if not found then
      break
    end
    count = count + 1
    position = found + 1
  end
  return count
end

function lamentMapper.isLandmarkToken(token)
  if #token ~= 2 then
    return false
  end
  local marker = token:sub(1, 1)
  local remainder = token:sub(2, 2)
  return (marker == "#" or marker == "@")
      and (remainder == marker or lamentMapper.landmarkRemainders[remainder] == true)
end

function lamentMapper.validateRows(rows)
  local size = #rows
  if size == 0 or size % 2 == 0 then
    return false, "row count " .. tostring(size) .. " is not a positive odd number"
  end
  local width = size * 2
  local starCount = 0
  for rowIndex, row in ipairs(rows) do
    if #row ~= width then
      return false, "row " .. tostring(rowIndex) .. " has width " .. tostring(#row)
          .. "; expected " .. tostring(width)
    end
    if row:find("[\128-\255]") then
      return false, "row " .. tostring(rowIndex) .. " contains non-ASCII text"
    end
    for column = 0, size - 1 do
      local token = row:sub(column * 2 + 1, column * 2 + 2)
      local stars = lamentMapper.countStars(token)
      starCount = starCount + stars
      local isCenter = rowIndex == math.floor(size / 2) + 1 and column == math.floor(size / 2)
      if isCenter then
        if stars ~= 1 or token:sub(2, 2) ~= "*" then
          return false, "center cell does not contain the player marker in its second character"
        end
      elseif stars ~= 0 then
        return false, "unexpected player marker at row " .. tostring(rowIndex)
            .. ", column " .. tostring(column + 1)
      elseif not lamentMapper.validTokens[token] and not lamentMapper.isLandmarkToken(token) then
        return false, "unknown token " .. string.format("%q", token) .. " at row "
            .. tostring(rowIndex) .. ", column " .. tostring(column + 1)
      end
    end
  end
  if starCount ~= 1 then
    return false, "map contains " .. tostring(starCount) .. " player markers"
  end
  return true
end

function lamentMapper.normalizeMapRow(row, width)
  if row:find("[\128-\255]") then
    return nil, "contains non-ASCII text"
  end
  if #row > width then
    local suffix = row:sub(width + 1)
    if suffix:find("[^ ]") then
      return nil, "contains non-space text after column " .. tostring(width)
    end
    row = row:sub(1, width)
  elseif #row < width then
    row = row .. string.rep(" ", width - #row)
  end
  return row
end

function lamentMapper.findMap(lines)
  local bestReason = "no line contained exactly one player marker"
  for candidateIndex, line in ipairs(lines) do
    if lamentMapper.countStars(line) == 1 and not line:find("[\128-\255]") then
      local starColumn = line:find("*", 1, true)
      local size = starColumn - 1
      if size <= 0 or size % 2 == 0 then
        bestReason = "player marker at character " .. tostring(starColumn)
            .. " does not imply a positive odd map size"
      else
        local width = size * 2
        local radius = math.floor(size / 2)
        local first = candidateIndex - radius
        local last = candidateIndex + radius
        if first < 1 or last > #lines then
          bestReason = "candidate " .. tostring(size) .. "x" .. tostring(size)
              .. " map is missing surrounding rows"
        else
          local rows = {}
          local sourceLengths = {}
          local normalizationReason = nil
          for index = first, last do
            local rawRow = lines[index]
            local normalized, reason = lamentMapper.normalizeMapRow(rawRow, width)
            if not normalized then
              normalizationReason = "row " .. tostring(index - first + 1) .. " " .. reason
              break
            end
            rows[#rows + 1] = normalized
            sourceLengths[#sourceLengths + 1] = math.min(#rawRow, width)
          end
          if normalizationReason then
            bestReason = normalizationReason
          else
            local valid, reason = lamentMapper.validateRows(rows)
            if valid then
              return rows, first, sourceLengths
            end
            bestReason = reason
          end
        end
      end
    end
  end
  return nil, nil, nil, bestReason
end

function lamentMapper.sameRgb(left, right)
  return left.r == right.r and left.g == right.g and left.b == right.b
end

function lamentMapper.readCharacterStyle(lineNumber, column)
  moveCursor("main", 0, lineNumber)
  selectSection(column, 1)
  local fr, fg, fb = getFgColor()
  local br, bg, bb = getBgColor()
  return {
    foreground = { r = fr, g = fg, b = fb },
    background = { r = br, g = bg, b = bb },
  }
end

function lamentMapper.captureStyles(rows, firstLineNumber, sourceLengths)
  local oldLine = getLineNumber("main")
  local oldColumn = getColumnNumber("main")
  local allRuns = {}
  for rowIndex, row in ipairs(rows) do
    local runs = {}
    local active = nil
    for column = 0, #row - 1 do
      local sourceLength = sourceLengths and sourceLengths[rowIndex] or #row
      local style
      if column < sourceLength then
        style = lamentMapper.readCharacterStyle(firstLineNumber + rowIndex - 1, column)
      else
        style = {
          foreground = { r = 255, g = 255, b = 255 },
          background = { r = 0, g = 0, b = 0 },
        }
      end
      if active and lamentMapper.sameRgb(active.foreground, style.foreground)
          and lamentMapper.sameRgb(active.background, style.background) then
        active.length = active.length + 1
      else
        active = {
          start = column,
          length = 1,
          foreground = style.foreground,
          background = style.background,
        }
        runs[#runs + 1] = active
      end
    end
    allRuns[#allRuns + 1] = runs
  end
  moveCursor("main", oldColumn, oldLine)
  return allRuns
end

function lamentMapper.sendPayload(payload)
  local lastReason = "unknown process write failure"
  for _ = 1, 2 do
    if not lamentMapper.ensureProcess() then
      return false, "the managed process could not be started"
    end
    local process = lamentMapper.process
    local ok, result = pcall(function()
      return process.send(payload)
    end)
    if ok and result ~= false then
      return true
    end
    lastReason = ok and "process.send returned false" or tostring(result)
    lamentMapper.closeProcess()
  end
  return false, lastReason
end

function lamentMapper.sendMap(rows, styles)
  if not lamentMapper.ensureProcess() then
    return false, "Valid map found, but the managed process could not be started"
  end
  lamentMapper.sequence = lamentMapper.sequence + 1
  local message = {
    protocol_version = lamentMapper.protocolVersion,
    type = "map",
    captured_at = os.time(),
    sequence = lamentMapper.sequence,
    rows = rows,
    styles = styles,
  }
  local ok, jsonOrReason = pcall(function()
    return yajl.to_string(message)
  end)
  if not ok then
    cecho("<red>Could not encode the Lament map: " .. tostring(jsonOrReason) .. "\n")
    return false, "Valid map found, but JSON encoding failed"
  end
  if #jsonOrReason > lamentMapper.maxMessageBytes then
    cecho("<red>LamentMapper discarded a map larger than 1 MiB.\n")
    return false, "Valid map exceeded the 1 MiB transport limit"
  end
  local sent, reason = lamentMapper.sendPayload(jsonOrReason .. "\n")
  if not sent then
    lamentMapper.closeProcess()
    cecho("<red>Could not send the map to LamentMapper after retrying: " .. tostring(reason) .. "\n")
    return false, "Valid map found, but sending to the managed process failed after retry"
  end
  lamentMapper.mapsSent = lamentMapper.mapsSent + 1
  return true, "Map transmitted successfully"
end

function lamentMapper.resetCapture()
  local last = getLastLineNumber("main")
  lamentMapper.responseStart = last + 1
  lamentMapper.lastObservedLine = last
end

function lamentMapper.onPrompt()
  lamentMapper.promptCount = lamentMapper.promptCount + 1
  local promptLine = getLastLineNumber("main")
  if not lamentMapper.responseStart then
    lamentMapper.resetCapture()
    return
  end
  if lamentMapper.lastObservedLine and promptLine < lamentMapper.lastObservedLine then
    lamentMapper.responseStart = promptLine + 1
    lamentMapper.lastObservedLine = promptLine
    return
  end
  local firstLine = lamentMapper.responseStart
  lamentMapper.responseStart = promptLine + 1
  lamentMapper.lastObservedLine = promptLine
  if promptLine <= firstLine then
    return
  end
  local lines = getLines("main", firstLine, promptLine - 1)
  if type(lines) ~= "table" or #lines == 0 then
    lamentMapper.lastCaptureStatus = "Prompt observed with no response lines"
    return
  end
  local rows, relativeFirst, sourceLengths, rejectionReason = lamentMapper.findMap(lines)
  if not rows then
    local sawSurveyText = false
    for _, responseLine in ipairs(lines) do
      if responseLine:find("Your current surroundings are", 1, true)
          or responseLine:find("You can see up to", 1, true) then
        sawSurveyText = true
        break
      end
    end
    if sawSurveyText then
      lamentMapper.lastCaptureStatus = "Wilderness map rejected: " .. tostring(rejectionReason)
      if lamentMapper.DEBUG and not lamentMapper.warnedSurveyWithoutMap then
        cecho("<yellow>LamentMapper saw wilderness survey output but rejected the grid: "
            .. tostring(rejectionReason) .. ". Run 'lamentmapper status' to repeat this diagnostic.\n")
        lamentMapper.warnedSurveyWithoutMap = true
      end
    else
      lamentMapper.lastCaptureStatus = "Prompt observed; no valid wilderness map in " .. tostring(#lines) .. " response lines"
    end
    return
  end
  lamentMapper.warnedSurveyWithoutMap = false
  local styles = lamentMapper.captureStyles(rows, firstLine + relativeFirst - 1, sourceLengths)
  local _, status = lamentMapper.sendMap(rows, styles)
  lamentMapper.lastCaptureStatus = status
end

function lamentMapper.onBufferShrink(_, consoleName)
  if consoleName == nil or consoleName == "main" then
    lamentMapper.resetCapture()
  end
end

function lamentMapper.isPackageInstalled(packageName)
  if type(getPackages) ~= "function" then
    return false
  end
  local ok, packages = pcall(getPackages)
  if not ok or type(packages) ~= "table" then
    return false
  end
  for key, value in pairs(packages) do
    if key == packageName or value == packageName then
      return true
    end
  end
  return false
end

function lamentMapper.removeLegacyPackage()
  if not lamentMapper.isPackageInstalled(lamentMapper.legacyPackageName) then
    return false
  end

  lamentMapper.deletePathFiles()
  lamentMapper.executablePath = nil
  lamentMapper.warnedMissing = false
  lamentMapper.legacyRemovalInProgress = true
  if type(uninstallPackage) ~= "function" then
    lamentMapper.legacyRemovalInProgress = false
    cecho("<red>Accessible Lament Map migration could not remove the legacy package because "
        .. "uninstallPackage is unavailable. Remove '" .. lamentMapper.legacyPackageName
        .. "' manually, then reinstall '" .. lamentMapper.packageName .. "'.\n")
    return true
  end

  local ok, result = pcall(uninstallPackage, lamentMapper.legacyPackageName)
  if not ok or result == false or lamentMapper.isPackageInstalled(lamentMapper.legacyPackageName) then
    lamentMapper.legacyRemovalInProgress = false
    cecho("<red>Accessible Lament Map migration could not remove the legacy package '"
        .. lamentMapper.legacyPackageName .. "': " .. tostring(result)
        .. ". Remove it manually; the new package remains installed.\n")
    return true
  end
  lamentMapper.legacyRemovalInProgress = false
  cecho("<green>Removed the legacy '" .. lamentMapper.legacyPackageName .. "' package.\n")
  return true
end

function lamentMapper.onInstall(_, packageName)
  if packageName == lamentMapper.packageName then
    lamentMapper.resetCapture()
    local migrated = lamentMapper.removeLegacyPackage()
    cecho("<green>Accessible Lament Map installed. Run: lamentmapper setup auto\n")
    cecho("<cyan>For an existing extracted copy, run: lamentmapper setup manual\n")
    if migrated then
      cecho("<yellow>The legacy installation path was discarded. Complete one fresh setup before using the mapper.\n")
    end
  end
end

function lamentMapper.unregisterHandlers()
  for _, handlerId in ipairs(lamentMapper.eventHandlers) do
    pcall(killAnonymousEventHandler, handlerId)
  end
  lamentMapper.eventHandlers = {}
end

function lamentMapper.cleanup()
  lamentMapper.closeProcess()
  lamentMapper.closeFocusHelper()
  lamentMapper.clearAutoSetup()
  lamentMapper.unregisterHandlers()
end

function lamentMapper.onUninstall(_, packageName)
  if packageName == lamentMapper.legacyPackageName then
    lamentMapper.legacyRemovalInProgress = false
    return
  end
  if packageName == lamentMapper.packageName then
    local mapper = lamentMapper
    mapper.cleanup()
    mapper.deletePathFiles()
    _G.lamentMapper = nil
  end
end

function lamentMapper.onExit()
  lamentMapper.cleanup()
end

function lamentMapper.registerHandler(eventName, callbackName)
  local ok, handlerIdOrReason = pcall(registerAnonymousEventHandler, eventName, callbackName)
  if not ok or not handlerIdOrReason then
    cecho("<red>LamentMapper could not register " .. eventName .. ": " .. tostring(handlerIdOrReason) .. "\n")
    return false
  end
  lamentMapper.eventHandlers[#lamentMapper.eventHandlers + 1] = handlerIdOrReason
  return true
end

function lamentMapper.initialize()
  lamentMapper.clearAutoSetup()
  lamentMapper.unregisterHandlers()
  pcall(os.remove, lamentMapper.legacyProfilePath())
  local path = lamentMapper.readExecutablePath()
  lamentMapper.executablePath = path
  lamentMapper.registerHandler("sysInstallPackage", "lamentMapper.onInstall")
  lamentMapper.registerHandler("sysUninstallPackage", "lamentMapper.onUninstall")
  lamentMapper.registerHandler("sysExitEvent", "lamentMapper.onExit")
  lamentMapper.registerHandler("sysBufferShrinkEvent", "lamentMapper.onBufferShrink")
  lamentMapper.registerHandler("sysDownloadDone", "lamentMapper.onDownloadDone")
  lamentMapper.registerHandler("sysDownloadError", "lamentMapper.onDownloadError")
  lamentMapper.registerHandler("sysUnzipDone", "lamentMapper.onUnzipDone")
  lamentMapper.registerHandler("sysUnzipError", "lamentMapper.onUnzipError")
  lamentMapper.resetCapture()
end

lamentMapper.initialize()
