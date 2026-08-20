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
  if type(previousLamentMapper.cancelAutomaticMovement) == "function" then
    pcall(previousLamentMapper.cancelAutomaticMovement, false)
  end
  closePreviousResource(previousLamentMapper.process)
  closePreviousResource(previousLamentMapper.focusHelper)
  local previousOperation = previousLamentMapper.setupOperation
  if type(previousOperation) == "table" and previousOperation.archivePath then
    pcall(os.remove, tostring(previousOperation.archivePath):gsub("\\", "/"))
  end
  local previousUpdate = previousLamentMapper.updateOperation
  if type(previousUpdate) == "table" then
    for _, field in ipairs({ "manifestPath", "packagePath" }) do
      local path = previousUpdate[field]
      if path then
        pcall(os.remove, tostring(path):gsub("\\", "/"))
      end
    end
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
lamentMapper.packageVersion = "1.2.0"
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
lamentMapper.updateOperation = nil
lamentMapper.updateSequence = 0
lamentMapper.offeredUpdate = nil
lamentMapper.automaticUpdateChecks = true
lamentMapper.lastSuccessfulUpdateCheck = nil
lamentMapper.legacyRemovalInProgress = false
lamentMapper.DEBUG = false
lamentMapper.enabled = true
lamentMapper.warnedMissing = false
lamentMapper.promptCount = 0
lamentMapper.mapsSent = 0
lamentMapper.lastCaptureStatus = "Waiting for a prompt boundary"
lamentMapper.warnedSurveyWithoutMap = false
lamentMapper.automaticSurvey = nil
lamentMapper.processOutputBuffer = ""
lamentMapper.processOutputOversized = false
lamentMapper.automaticMovement = nil
lamentMapper.movementDirections = {
  north = true,
  northeast = true,
  east = true,
  southeast = true,
  south = true,
  southwest = true,
  west = true,
  northwest = true,
}
lamentMapper.mapCharacters = {
  [" "] = true,
  ["^"] = true,
  ['"'] = true,
  ["t"] = true,
  ["T"] = true,
  ["n"] = true,
  ["V"] = true,
  ["-"] = true,
  ["/"] = true,
  ['\\'] = true,
  ["M"] = true,
  ["s"] = true,
  ["f"] = true,
  ["."] = true,
  ["v"] = true,
  ["~"] = true,
  ["i"] = true,
  ["="] = true,
  ["x"] = true,
  ["#"] = true,
  ["@"] = true,
  ["*"] = true,
}
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

function lamentMapper.updateSettingsPath()
  return lamentMapper.joinPath(getMudletHomeDir(), "accessible-lament-map-updates.txt")
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
lamentMapper.updateManifestUrl =
    "https://github.com/ironcross32/LamentMap/releases/latest/download/update-manifest.json"
lamentMapper.updateIntervalSeconds = 24 * 60 * 60
lamentMapper.maxManifestBytes = 64 * 1024
lamentMapper.maxPackageBytes = 64 * 1024 * 1024
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

function lamentMapper.deleteLegacyPathFile()
  pcall(os.remove, lamentMapper.legacyProfilePath())
end

function lamentMapper.parseSemVer(version)
  if type(version) ~= "string" then
    return nil
  end
  local major, minor, patch = version:match("^(%d+)%.(%d+)%.(%d+)$")
  if not major then
    return nil
  end
  for _, part in ipairs({ major, minor, patch }) do
    if #part > 1 and part:sub(1, 1) == "0" then
      return nil
    end
  end
  return { tonumber(major), tonumber(minor), tonumber(patch) }
end

function lamentMapper.compareSemVer(left, right)
  local leftParts = lamentMapper.parseSemVer(left)
  local rightParts = lamentMapper.parseSemVer(right)
  if not leftParts or not rightParts then
    return nil
  end
  for index = 1, 3 do
    if leftParts[index] < rightParts[index] then
      return -1
    elseif leftParts[index] > rightParts[index] then
      return 1
    end
  end
  return 0
end

function lamentMapper.updateCheckDue(now)
  if not lamentMapper.automaticUpdateChecks then
    return false
  end
  now = tonumber(now) or os.time()
  local last = tonumber(lamentMapper.lastSuccessfulUpdateCheck)
  return not last or now - last >= lamentMapper.updateIntervalSeconds
end

function lamentMapper.loadUpdateSettings()
  lamentMapper.automaticUpdateChecks = true
  lamentMapper.lastSuccessfulUpdateCheck = nil
  local handle = io.open(lamentMapper.updateSettingsPath(), "rb")
  if not handle then
    return
  end
  local text = handle:read("*a") or ""
  handle:close()
  local automatic = text:match("automatic_checks=(%a+)")
  local checked = text:match("last_successful_check=(%d+)")
  if automatic == "false" then
    lamentMapper.automaticUpdateChecks = false
  end
  lamentMapper.lastSuccessfulUpdateCheck = tonumber(checked)
end

function lamentMapper.saveUpdateSettings()
  local handle, reason = io.open(lamentMapper.updateSettingsPath(), "wb")
  if not handle then
    return false, reason
  end
  handle:write("automatic_checks=" .. tostring(lamentMapper.automaticUpdateChecks) .. "\n")
  if lamentMapper.lastSuccessfulUpdateCheck then
    handle:write("last_successful_check=" .. tostring(lamentMapper.lastSuccessfulUpdateCheck) .. "\n")
  end
  handle:close()
  return true
end

function lamentMapper.createTemporaryUpdateFile(suffix)
  for _ = 1, 100 do
    lamentMapper.updateSequence = lamentMapper.updateSequence + 1
    local path = lamentMapper.joinPath(
      getMudletHomeDir(),
      "accessible-lament-map-update-" .. tostring(os.time()) .. "-"
          .. tostring(lamentMapper.updateSequence) .. suffix
    )
    local existing = io.open(path, "rb")
    if existing then
      existing:close()
    else
      return path
    end
  end
  return nil, "could not allocate a unique temporary filename"
end

function lamentMapper.clearUpdateOperation()
  local operation = lamentMapper.updateOperation
  lamentMapper.updateOperation = nil
  if operation then
    for _, field in ipairs({ "manifestPath", "packagePath" }) do
      local path = operation[field]
      if path then
        pcall(os.remove, lamentMapper.normalizePath(path))
      end
    end
  end
end

function lamentMapper.printManualUpdateFallback(releaseUrl)
  cecho("<yellow>No files were changed. Download the package manually from "
      .. tostring(releaseUrl or "https://github.com/ironcross32/LamentMap/releases")
      .. " if the problem continues.\n")
end

function lamentMapper.failUpdate(stage, reason, releaseUrl)
  cecho("<red>Accessible Lament Map update failed during " .. tostring(stage) .. ": "
      .. tostring(reason or "unknown error") .. "\n")
  lamentMapper.clearUpdateOperation()
  lamentMapper.printManualUpdateFallback(releaseUrl)
  return false
end

local SHA256_MODULUS = 4294967296
local SHA256_MAX = 4294967295

local function shaBand(left, right)
  if type(bit32) == "table" then
    return bit32.band(left, right)
  elseif type(bit) == "table" then
    local value = bit.band(left, right)
    return value < 0 and value + SHA256_MODULUS or value
  end
  local result, place = 0, 1
  left, right = left % SHA256_MODULUS, right % SHA256_MODULUS
  for _ = 1, 32 do
    local a, b = left % 2, right % 2
    if a == 1 and b == 1 then
      result = result + place
    end
    left, right, place = math.floor(left / 2), math.floor(right / 2), place * 2
  end
  return result
end

local function shaBxor(left, right)
  if type(bit32) == "table" then
    return bit32.bxor(left, right)
  elseif type(bit) == "table" then
    local value = bit.bxor(left, right)
    return value < 0 and value + SHA256_MODULUS or value
  end
  local result, place = 0, 1
  left, right = left % SHA256_MODULUS, right % SHA256_MODULUS
  for _ = 1, 32 do
    local a, b = left % 2, right % 2
    if a ~= b then
      result = result + place
    end
    left, right, place = math.floor(left / 2), math.floor(right / 2), place * 2
  end
  return result
end

local function shaXor(...)
  local value = 0
  for index = 1, select("#", ...) do
    value = shaBxor(value, select(index, ...))
  end
  return value
end

local function shaRshift(value, count)
  return math.floor((value % SHA256_MODULUS) / 2 ^ count)
end

local function shaRotate(value, count)
  value = value % SHA256_MODULUS
  return (shaRshift(value, count) + (value * 2 ^ (32 - count)) % SHA256_MODULUS)
      % SHA256_MODULUS
end

function lamentMapper.sha256(data)
  if type(data) ~= "string" then
    return nil
  end
  local constants = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  }
  local hash = {
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  }
  local bitLength = #data * 8
  data = data .. string.char(0x80)
  data = data .. string.rep("\0", (56 - (#data % 64)) % 64)
  local high = math.floor(bitLength / SHA256_MODULUS)
  local low = bitLength % SHA256_MODULUS
  data = data .. string.char(
    shaRshift(high, 24) % 256, shaRshift(high, 16) % 256,
    shaRshift(high, 8) % 256, high % 256,
    shaRshift(low, 24) % 256, shaRshift(low, 16) % 256,
    shaRshift(low, 8) % 256, low % 256
  )
  for offset = 1, #data, 64 do
    local words = {}
    for index = 0, 15 do
      local position = offset + index * 4
      local a, b, c, d = data:byte(position, position + 3)
      words[index] = ((a * 256 + b) * 256 + c) * 256 + d
    end
    for index = 16, 63 do
      local s0 = shaXor(
        shaRotate(words[index - 15], 7),
        shaRotate(words[index - 15], 18),
        shaRshift(words[index - 15], 3)
      )
      local s1 = shaXor(
        shaRotate(words[index - 2], 17),
        shaRotate(words[index - 2], 19),
        shaRshift(words[index - 2], 10)
      )
      words[index] = (words[index - 16] + s0 + words[index - 7] + s1) % SHA256_MODULUS
    end
    local a, b, c, d, e, f, g, h =
        hash[1], hash[2], hash[3], hash[4], hash[5], hash[6], hash[7], hash[8]
    for index = 0, 63 do
      local sum1 = shaXor(shaRotate(e, 6), shaRotate(e, 11), shaRotate(e, 25))
      local choice = shaXor(shaBand(e, f), shaBand(SHA256_MAX - e, g))
      local temporary1 = (h + sum1 + choice + constants[index + 1] + words[index])
          % SHA256_MODULUS
      local sum0 = shaXor(shaRotate(a, 2), shaRotate(a, 13), shaRotate(a, 22))
      local majority = shaXor(shaBand(a, b), shaBand(a, c), shaBand(b, c))
      local temporary2 = (sum0 + majority) % SHA256_MODULUS
      h, g, f, e, d, c, b, a =
          g, f, e, (d + temporary1) % SHA256_MODULUS,
          c, b, a, (temporary1 + temporary2) % SHA256_MODULUS
    end
    hash[1] = (hash[1] + a) % SHA256_MODULUS
    hash[2] = (hash[2] + b) % SHA256_MODULUS
    hash[3] = (hash[3] + c) % SHA256_MODULUS
    hash[4] = (hash[4] + d) % SHA256_MODULUS
    hash[5] = (hash[5] + e) % SHA256_MODULUS
    hash[6] = (hash[6] + f) % SHA256_MODULUS
    hash[7] = (hash[7] + g) % SHA256_MODULUS
    hash[8] = (hash[8] + h) % SHA256_MODULUS
  end
  local parts = {}
  for index = 1, 8 do
    parts[index] = string.format("%08x", hash[index])
  end
  return table.concat(parts)
end

function lamentMapper.readVerifiedFile(path, expectedSize, expectedHash, maximumSize)
  local handle, reason = io.open(path, "rb")
  if not handle then
    return nil, tostring(reason or "downloaded file is unreadable")
  end
  local data = handle:read("*a") or ""
  handle:close()
  if #data > maximumSize then
    return nil, "download exceeds the size limit"
  end
  if expectedSize and #data ~= expectedSize then
    return nil, "download size does not match the manifest"
  end
  if expectedHash and lamentMapper.sha256(data) ~= expectedHash:lower() then
    return nil, "download SHA-256 does not match the manifest"
  end
  return data
end

function lamentMapper.validateUpdateManifest(manifest)
  if type(manifest) ~= "table" or manifest.schema_version ~= 1 then
    return nil, "unsupported or missing schema version"
  end
  if type(manifest.release_tag) ~= "string"
      or not lamentMapper.parseSemVer(manifest.release_tag:match("^v(.+)$")) then
    return nil, "release tag is not stable SemVer"
  end
  local expectedReleaseUrl =
      "https://github.com/ironcross32/LamentMap/releases/tag/" .. manifest.release_tag
  if manifest.release_url ~= expectedReleaseUrl then
    return nil, "release-notes URL is not pinned to the allowed repository"
  end
  local component = manifest.mudlet
  if type(component) ~= "table" or not lamentMapper.parseSemVer(component.version)
      or type(component.asset) ~= "table" then
    return nil, "Mudlet component metadata is malformed"
  end
  local expectedAssetUrl = "https://github.com/ironcross32/LamentMap/releases/download/"
      .. manifest.release_tag .. "/Accessible-Lament-Map.mpackage"
  local asset = component.asset
  if asset.url ~= expectedAssetUrl then
    return nil, "Mudlet asset URL is not pinned to the allowed repository and filename"
  end
  if type(asset.size) ~= "number" or asset.size < 1 or asset.size % 1 ~= 0
      or asset.size > lamentMapper.maxPackageBytes then
    return nil, "Mudlet asset size is invalid"
  end
  if type(asset.sha256) ~= "string" or not asset.sha256:match("^[0-9a-fA-F]+$")
      or #asset.sha256 ~= 64 then
    return nil, "Mudlet asset SHA-256 is invalid"
  end
  return {
    version = component.version,
    url = asset.url,
    size = asset.size,
    sha256 = asset.sha256:lower(),
    releaseUrl = manifest.release_url,
    releaseTag = manifest.release_tag,
  }
end

function lamentMapper.offerUpdate(update)
  lamentMapper.offeredUpdate = update
  cecho("<green>Accessible Lament Map " .. update.version .. " is available. ")
  if type(cechoLink) == "function" then
    cechoLink(
      "<green>[Install update]",
      [[lamentMapper.update("install")]],
      "Download, verify, and install Accessible Lament Map " .. update.version,
      true
    )
    cecho("\n")
  else
    cecho("Run: lamentmapper update install\n")
  end
  cecho("<cyan>Typed-command fallback: lamentmapper update install\n")
end

function lamentMapper.startUpdateCheck(manual)
  if lamentMapper.updateOperation then
    if manual then
      cecho("<yellow>An update operation is already in progress.\n")
    end
    return false
  end
  if type(downloadFile) ~= "function" or type(yajl) ~= "table"
      or type(yajl.to_value) ~= "function" then
    if manual then
      lamentMapper.printManualUpdateFallback()
    end
    return false
  end
  local path, reason = lamentMapper.createTemporaryUpdateFile(".json")
  if not path then
    return lamentMapper.failUpdate("temporary manifest creation", reason)
  end
  lamentMapper.updateOperation = {
    stage = "manifest",
    manifestPath = path,
    manual = manual == true,
  }
  if manual then
    cecho("<cyan>Checking GitHub Releases for Accessible Lament Map updates...\n")
  end
  local ok, downloadReason = pcall(downloadFile, path, lamentMapper.updateManifestUrl)
  if not ok then
    return lamentMapper.failUpdate("manifest download startup", downloadReason)
  end
  return true
end

function lamentMapper.installOfferedUpdate()
  if lamentMapper.updateOperation then
    cecho("<yellow>An update operation is already in progress.\n")
    return false
  end
  local offered = lamentMapper.offeredUpdate
  if not offered then
    cecho("<yellow>No package update is currently offered. Run: lamentmapper update check\n")
    return false
  end
  if lamentMapper.compareSemVer(offered.version, lamentMapper.packageVersion) ~= 1 then
    lamentMapper.offeredUpdate = nil
    return lamentMapper.failUpdate("eligibility check", "the offered version is not newer")
  end
  if type(downloadFile) ~= "function" or type(installPackage) ~= "function" then
    return lamentMapper.failUpdate("API check", "Mudlet downloadFile or installPackage is unavailable",
      offered.releaseUrl)
  end
  local path, reason = lamentMapper.createTemporaryUpdateFile(".mpackage")
  if not path then
    return lamentMapper.failUpdate("temporary package creation", reason, offered.releaseUrl)
  end
  lamentMapper.updateOperation = {
    stage = "package",
    packagePath = path,
    update = offered,
    manual = true,
  }
  cecho("<cyan>Downloading Accessible Lament Map " .. offered.version .. "...\n")
  local ok, downloadReason = pcall(downloadFile, path, offered.url)
  if not ok then
    return lamentMapper.failUpdate("package download startup", downloadReason, offered.releaseUrl)
  end
  return true
end

function lamentMapper.update(action)
  action = action or "check"
  if action == "check" or action == "" then
    return lamentMapper.startUpdateCheck(true)
  elseif action == "install" then
    return lamentMapper.installOfferedUpdate()
  elseif action == "on" or action == "off" then
    lamentMapper.automaticUpdateChecks = action == "on"
    local ok, reason = lamentMapper.saveUpdateSettings()
    if not ok then
      cecho("<red>Could not save the update preference: " .. tostring(reason) .. "\n")
      return false
    end
    cecho("<cyan>Automatic daily update checks "
        .. (lamentMapper.automaticUpdateChecks and "enabled" or "disabled") .. ".\n")
    if lamentMapper.automaticUpdateChecks and lamentMapper.updateCheckDue() then
      lamentMapper.startUpdateCheck(false)
    end
    return true
  elseif action == "status" then
    local offered = lamentMapper.offeredUpdate and lamentMapper.offeredUpdate.version or "none"
    local stage = lamentMapper.updateOperation and lamentMapper.updateOperation.stage or "idle"
    cecho("<cyan>Package update status: current " .. lamentMapper.packageVersion
        .. ", offered " .. offered .. ", state " .. stage .. ".\n")
    cecho("<cyan>Automatic daily checks: "
        .. (lamentMapper.automaticUpdateChecks and "enabled" or "disabled") .. ".\n")
    cecho("<cyan>Last successful check: "
        .. tostring(lamentMapper.lastSuccessfulUpdateCheck or "never") .. ".\n")
    return true
  end
  cecho("<red>Unknown update command. Use check, install, on, off, or status.\n")
  return false
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
  cecho("<cyan>LamentMapper will refresh automatically after Lament reports a completed wilderness room entry. Manual 'survey leagues' output remains visible.\n")
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
  local updateOperation = lamentMapper.updateOperation
  if updateOperation and updateOperation.stage == "manifest"
      and lamentMapper.samePath(filename, updateOperation.manifestPath) then
    local manual = updateOperation.manual
    local data, readReason = lamentMapper.readVerifiedFile(
      updateOperation.manifestPath, nil, nil, lamentMapper.maxManifestBytes
    )
    if not data then
      return lamentMapper.failUpdate("manifest validation", readReason)
    end
    local ok, manifestOrReason = pcall(yajl.to_value, data)
    if not ok then
      return lamentMapper.failUpdate("manifest parsing", manifestOrReason)
    end
    local update, validationReason = lamentMapper.validateUpdateManifest(manifestOrReason)
    if not update then
      return lamentMapper.failUpdate("manifest validation", validationReason)
    end
    local comparison = lamentMapper.compareSemVer(update.version, lamentMapper.packageVersion)
    if comparison == nil or comparison < 0 then
      return lamentMapper.failUpdate("version validation", "the release attempts a package downgrade",
        update.releaseUrl)
    end
    lamentMapper.lastSuccessfulUpdateCheck = os.time()
    lamentMapper.saveUpdateSettings()
    lamentMapper.clearUpdateOperation()
    if comparison > 0 then
      lamentMapper.offerUpdate(update)
    else
      lamentMapper.offeredUpdate = nil
      if manual then
        cecho("<green>Accessible Lament Map " .. lamentMapper.packageVersion .. " is current.\n")
      end
    end
    return
  elseif updateOperation and updateOperation.stage == "package"
      and lamentMapper.samePath(filename, updateOperation.packagePath) then
    local update = updateOperation.update
    local _, readReason = lamentMapper.readVerifiedFile(
      updateOperation.packagePath, update.size, update.sha256, lamentMapper.maxPackageBytes
    )
    if readReason then
      return lamentMapper.failUpdate("package verification", readReason, update.releaseUrl)
    end
    updateOperation.stage = "installing"
    local ok, result, installReason = pcall(installPackage, updateOperation.packagePath)
    if not ok or result == false or installReason ~= nil then
      local reason = not ok and result or installReason or "installPackage returned false"
      return lamentMapper.failUpdate("package installation", reason, update.releaseUrl)
    end
    return
  end
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
  local updateOperation = lamentMapper.updateOperation
  if updateOperation
      and ((updateOperation.stage == "manifest"
          and lamentMapper.samePath(filename, updateOperation.manifestPath))
        or (updateOperation.stage == "package"
          and lamentMapper.samePath(filename, updateOperation.packagePath))) then
    local releaseUrl = updateOperation.update and updateOperation.update.releaseUrl
    return lamentMapper.failUpdate("download", reason, releaseUrl)
  end
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
  cecho("<green>You can start using LamentMapper now. It will open automatically after the next completed wilderness room entry.\n")
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
  lamentMapper.cancelAutomaticMovement(false)
  lamentMapper.resetProcessOutput()
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
  cecho("<cyan>Map capture: " .. (lamentMapper.enabled and "enabled" or "disabled") .. "\n")
  cecho("<cyan>Debug diagnostics: " .. (lamentMapper.DEBUG and "enabled" or "disabled") .. "\n")
  cecho("<cyan>LamentMapper managed process: " .. processState .. "\n")
  cecho("<cyan>Prompt boundaries observed: " .. tostring(lamentMapper.promptCount) .. "\n")
  cecho("<cyan>Maps transmitted: " .. tostring(lamentMapper.mapsSent) .. "\n")
  cecho("<cyan>Last capture result: " .. tostring(lamentMapper.lastCaptureStatus) .. "\n")
  if lamentMapper.enabled and pathState == "usable" and processState ~= "running" then
    cecho("<yellow>Close any manually launched LamentMapper window. Mudlet must launch the application to provide its map stream.\n")
  end
end

function lamentMapper.toggle()
  lamentMapper.enabled = not lamentMapper.enabled
  if lamentMapper.enabled then
    lamentMapper.resetAutomaticSurvey()
    lamentMapper.resetCapture()
    cecho("<cyan>LamentMapper activity enabled; the mapper will open after the next valid map.\n")
  else
    lamentMapper.resetAutomaticSurvey()
    lamentMapper.responseStart = nil
    lamentMapper.lastObservedLine = nil
    lamentMapper.closeProcess()
    lamentMapper.closeFocusHelper()
    lamentMapper.lastCaptureStatus = "Map capture disabled"
    cecho("<cyan>LamentMapper activity disabled; map capture stopped and the mapper closed.\n")
  end
  return lamentMapper.enabled
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

function lamentMapper.resetProcessOutput()
  lamentMapper.processOutputBuffer = ""
  lamentMapper.processOutputOversized = false
end

function lamentMapper.reportProcessMessageError(reason)
  cecho("<red>LamentMapper ignored an invalid movement message: " .. tostring(reason) .. ".\n")
end

function lamentMapper.cancelAutomaticMovement(announce)
  local movement = lamentMapper.automaticMovement
  if movement and movement.timer then
    pcall(killTimer, movement.timer)
  end
  lamentMapper.automaticMovement = nil
  if announce then
    if movement then
      cecho("<cyan>Automatic movement canceled.\n")
    else
      cecho("<cyan>No automatic movement is active.\n")
    end
  end
  return movement ~= nil
end

function lamentMapper.scheduleAutomaticMovement()
  if not lamentMapper.enabled then
    return false
  end
  local movement = lamentMapper.automaticMovement
  if not movement or movement.timer or movement.awaitingFinalArrival
      or coroutine.status(movement.coroutine) == "dead" then
    return false
  end
  local delay = math.random(500, 1500) / 1000
  local ok, timerOrReason = pcall(tempTimer, delay, function()
    if lamentMapper.automaticMovement ~= movement then
      return
    end
    movement.timer = nil
    local resumed, finalDirectionSentOrReason = coroutine.resume(movement.coroutine)
    if not resumed then
      lamentMapper.automaticMovement = nil
      cecho("<red>Automatic movement stopped: " .. tostring(finalDirectionSentOrReason) .. ".\n")
    elseif finalDirectionSentOrReason then
      movement.awaitingFinalArrival = true
    elseif coroutine.status(movement.coroutine) == "dead" then
      lamentMapper.automaticMovement = nil
    end
  end)
  if not ok or timerOrReason == nil then
    lamentMapper.automaticMovement = nil
    cecho("<red>Automatic movement could not schedule its next step: "
        .. tostring(timerOrReason) .. ".\n")
    return false
  end
  movement.timer = timerOrReason
  return true
end

function lamentMapper.startAutomaticMovement(directions)
  if not lamentMapper.enabled then
    return false
  end
  if lamentMapper.automaticMovement then
    cecho("<yellow>An automatic movement route is already active; the new route was rejected.\n")
    return false
  end
  local route = {}
  for index, direction in ipairs(directions) do
    route[index] = direction
  end
  local movement = {}
  movement.coroutine = coroutine.create(function()
    for index, direction in ipairs(route) do
      send(direction, false)
      coroutine.yield(index == #route)
    end
  end)
  lamentMapper.automaticMovement = movement
  return lamentMapper.scheduleAutomaticMovement()
end

function lamentMapper.validateMovementDirections(directions)
  if type(directions) ~= "table" or #directions == 0 then
    return nil, "move directions must be a non-empty array"
  end
  local count = #directions
  for key, _ in pairs(directions) do
    if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > count then
      return nil, "move directions must be a contiguous array"
    end
  end
  local validated = {}
  for index = 1, count do
    local direction = directions[index]
    if type(direction) ~= "string" or not lamentMapper.movementDirections[direction] then
      return nil, "unsupported direction at index " .. tostring(index)
    end
    validated[index] = direction
  end
  return validated
end


function lamentMapper.handleProcessMessage(text)
  local ok, message = pcall(function()
    return yajl.to_value(text)
  end)
  if not ok or type(message) ~= "table" then
    lamentMapper.reportProcessMessageError("malformed JSON")
    return false
  end
  if message.protocol_version ~= lamentMapper.protocolVersion then
    lamentMapper.reportProcessMessageError("unsupported protocol version")
    return false
  end
  if message.type == "move" then
    local directions, reason = lamentMapper.validateMovementDirections(message.directions)
    if not directions then
      lamentMapper.reportProcessMessageError(reason)
      return false
    end
    return lamentMapper.startAutomaticMovement(directions)
  elseif message.type == "cancel_move" then
    lamentMapper.cancelAutomaticMovement(true)
    return true
  end
  lamentMapper.reportProcessMessageError("unsupported message type")
  return false
end

function lamentMapper.onProcessOutput(output)
  if not lamentMapper.enabled then
    return
  end
  local chunk = tostring(output or "")
  local position = 1
  while position <= #chunk do
    local newline = chunk:find("\n", position, true)
    local last = newline and newline - 1 or #chunk
    local part = chunk:sub(position, last)
    if not lamentMapper.processOutputOversized then
      if #lamentMapper.processOutputBuffer + #part > lamentMapper.maxMessageBytes then
        lamentMapper.processOutputBuffer = ""
        lamentMapper.processOutputOversized = true
        lamentMapper.reportProcessMessageError("message exceeds 1 MiB")
      else
        lamentMapper.processOutputBuffer = lamentMapper.processOutputBuffer .. part
      end
    end
    if not newline then
      break
    end
    if not lamentMapper.processOutputOversized then
      local lineText = lamentMapper.processOutputBuffer:gsub("\r$", "")
      lamentMapper.handleProcessMessage(lineText)
    end
    lamentMapper.resetProcessOutput()
    position = newline + 1
  end
end

function lamentMapper.ensureProcess()
  if not lamentMapper.enabled then
    return false
  end
  if lamentMapper.isProcessRunning() then
    return true
  end
  lamentMapper.closeProcess()
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
    return spawn(lamentMapper.onProcessOutput, path)
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

function lamentMapper.captureLineStyles(text)
  if #text == 0 then
    return {}
  end
  local oldLine = getLineNumber("main")
  local oldColumn = getColumnNumber("main")
  local lineNumber = oldLine
  local runs = {}
  local active = nil
  for column = 0, #text - 1 do
    local style = lamentMapper.readCharacterStyle(lineNumber, column)
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
  moveCursor("main", oldColumn, oldLine)
  return runs
end

function lamentMapper.alignLineStyles(runs, sourceLength, width)
  local aligned = {}
  local retainedLength = math.min(sourceLength, width)
  for _, run in ipairs(runs) do
    local first = math.max(run.start, 0)
    local last = math.min(run.start + run.length, retainedLength)
    if last > first then
      aligned[#aligned + 1] = {
        start = first,
        length = last - first,
        foreground = run.foreground,
        background = run.background,
      }
    end
  end

  if retainedLength < width then
    local paddingStyle = {
      foreground = { r = 255, g = 255, b = 255 },
      background = { r = 0, g = 0, b = 0 },
    }
    local previous = aligned[#aligned]
    if previous and previous.start + previous.length == retainedLength
        and lamentMapper.sameRgb(previous.foreground, paddingStyle.foreground)
        and lamentMapper.sameRgb(previous.background, paddingStyle.background) then
      previous.length = previous.length + width - retainedLength
    else
      aligned[#aligned + 1] = {
        start = retainedLength,
        length = width - retainedLength,
        foreground = paddingStyle.foreground,
        background = paddingStyle.background,
      }
    end
  end
  return aligned
end

function lamentMapper.isPotentialMapRow(text)
  if type(text) ~= "string" or #text > 512 then
    return false
  end
  local completeLength = #text - (#text % 2)
  for index = 1, completeLength, 2 do
    local token = text:sub(index, index + 1)
    local playerToken = token:sub(2, 2) == "*"
        and lamentMapper.mapCharacters[token:sub(1, 1)] == true
    if not playerToken and not lamentMapper.validTokens[token]
        and not lamentMapper.isLandmarkToken(token) then
      return false
    end
  end
  if completeLength < #text then
    local trailing = text:sub(#text, #text)
    if trailing == "*" or not lamentMapper.mapCharacters[trailing] then
      return false
    end
  end
  return true
end

function lamentMapper.isSurveyTerminator(text)
  return type(text) == "string" and text:find("You can see up to", 1, true) == 1
end

function lamentMapper.resetAutomaticSurvey()
  lamentMapper.automaticSurvey = nil
end

function lamentMapper.startAutomaticSurvey()
  if not lamentMapper.enabled then
    return false
  end
  lamentMapper.automaticSurvey = {
    candidates = {},
    complete = false,
    followUp = false,
  }
  local ok, reason = pcall(send, "survey leagues", false)
  if not ok then
    lamentMapper.resetAutomaticSurvey()
    lamentMapper.lastCaptureStatus = "Automatic survey command failed: " .. tostring(reason)
    if lamentMapper.DEBUG then
      cecho("<yellow>LamentMapper could not request an automatic wilderness survey: "
          .. tostring(reason) .. "\n")
    end
    return false
  end
  return true
end

function lamentMapper.onRoomEntry()
  if not lamentMapper.enabled then
    return false
  end
  local movement = lamentMapper.automaticMovement
  if movement and movement.awaitingFinalArrival then
    lamentMapper.automaticMovement = nil
    cecho("<green>Automatic movement complete.\n")
  else
    lamentMapper.scheduleAutomaticMovement()
  end
  if lamentMapper.automaticSurvey then
    lamentMapper.automaticSurvey.followUp = true
    return false
  end
  return lamentMapper.startAutomaticSurvey()
end

function lamentMapper.finishAutomaticSurvey()
  if not lamentMapper.enabled then
    lamentMapper.resetAutomaticSurvey()
    return false
  end
  local survey = lamentMapper.automaticSurvey
  if not survey or survey.complete then
    return false
  end
  survey.complete = true
  local lines = {}
  for _, candidate in ipairs(survey.candidates) do
    lines[#lines + 1] = candidate.text
  end
  local rows, relativeFirst, sourceLengths, rejectionReason = lamentMapper.findMap(lines)
  if not rows then
    lamentMapper.lastCaptureStatus = "Automatic wilderness map rejected: " .. tostring(rejectionReason)
    if lamentMapper.DEBUG then
      cecho("<yellow>LamentMapper rejected an automatic wilderness grid: "
          .. tostring(rejectionReason) .. ".\n")
    end
    return false
  end

  local styles = {}
  for rowIndex, row in ipairs(rows) do
    local candidate = survey.candidates[relativeFirst + rowIndex - 1]
    styles[#styles + 1] = lamentMapper.alignLineStyles(
      candidate.styles,
      sourceLengths[rowIndex],
      #row
    )
  end
  lamentMapper.warnedSurveyWithoutMap = false
  local sent, status = lamentMapper.sendMap(rows, styles)
  lamentMapper.lastCaptureStatus = status
  return sent
end

function lamentMapper.onAutomaticSurveyLine(text)
  if not lamentMapper.enabled then
    return false
  end
  local survey = lamentMapper.automaticSurvey
  if not survey or survey.complete then
    return false
  end
  text = tostring(text or "")
  if lamentMapper.isSurveyTerminator(text) then
    deleteLine()
    lamentMapper.finishAutomaticSurvey()
    return true
  end
  if not lamentMapper.isPotentialMapRow(text) then
    return false
  end
  survey.candidates[#survey.candidates + 1] = {
    text = text,
    styles = lamentMapper.captureLineStyles(text),
  }
  deleteLine()
  return true
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
  if not lamentMapper.enabled then
    return false, "Map capture is disabled"
  end
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
  if not lamentMapper.enabled then
    return
  end
  lamentMapper.promptCount = lamentMapper.promptCount + 1
  local promptLine = getLastLineNumber("main")
  if lamentMapper.automaticSurvey then
    local survey = lamentMapper.automaticSurvey
    local followUp = survey.followUp
    if not survey.complete then
      lamentMapper.lastCaptureStatus = "Automatic survey ended before its visibility sentence"
    end
    lamentMapper.responseStart = promptLine + 1
    lamentMapper.lastObservedLine = promptLine
    lamentMapper.resetAutomaticSurvey()
    if followUp then
      lamentMapper.startAutomaticSurvey()
    end
    return
  end
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
    lamentMapper.resetAutomaticSurvey()
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

  lamentMapper.deleteLegacyPathFile()
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
    local completedUpdate = lamentMapper.updateOperation
        and lamentMapper.updateOperation.stage == "installing"
    local installedVersion = completedUpdate
        and lamentMapper.updateOperation.update.version or nil
    if completedUpdate then
      lamentMapper.clearUpdateOperation()
      lamentMapper.offeredUpdate = nil
    end
    lamentMapper.cancelAutomaticMovement(false)
    lamentMapper.resetProcessOutput()
    lamentMapper.resetAutomaticSurvey()
    lamentMapper.resetCapture()
    lamentMapper.removeLegacyPackage()
    local path, pathState, reason = lamentMapper.configuredExecutable()
    if pathState == "usable" then
      lamentMapper.warnedMissing = false
      cecho("<green>Accessible Lament Map installed. Reusing the configured executable: " .. path .. "\n")
    else
      cecho("<green>Accessible Lament Map installed.\n")
      lamentMapper.reportExecutableProblem(path, pathState, reason)
    end
    if completedUpdate then
      cecho("<green>Accessible Lament Map " .. installedVersion .. " installed successfully.\n")
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
  lamentMapper.resetAutomaticSurvey()
  lamentMapper.closeProcess()
  lamentMapper.closeFocusHelper()
  lamentMapper.clearAutoSetup()
  lamentMapper.clearUpdateOperation()
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
  lamentMapper.cancelAutomaticMovement(false)
  lamentMapper.resetProcessOutput()
  lamentMapper.resetAutomaticSurvey()
  lamentMapper.clearAutoSetup()
  lamentMapper.clearUpdateOperation()
  lamentMapper.unregisterHandlers()
  lamentMapper.deleteLegacyPathFile()
  local path = lamentMapper.readExecutablePath()
  lamentMapper.executablePath = path
  lamentMapper.loadUpdateSettings()
  lamentMapper.registerHandler("sysInstallPackage", "lamentMapper.onInstall")
  lamentMapper.registerHandler("sysUninstallPackage", "lamentMapper.onUninstall")
  lamentMapper.registerHandler("sysExitEvent", "lamentMapper.onExit")
  lamentMapper.registerHandler("sysBufferShrinkEvent", "lamentMapper.onBufferShrink")
  lamentMapper.registerHandler("sysDownloadDone", "lamentMapper.onDownloadDone")
  lamentMapper.registerHandler("sysDownloadError", "lamentMapper.onDownloadError")
  lamentMapper.registerHandler("sysUnzipDone", "lamentMapper.onUnzipDone")
  lamentMapper.registerHandler("sysUnzipError", "lamentMapper.onUnzipError")
  lamentMapper.resetCapture()
  if lamentMapper.updateCheckDue() then
    lamentMapper.startUpdateCheck(false)
  end
end

lamentMapper.initialize()
