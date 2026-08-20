[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')][string]$ReleaseTag,
    [Parameter(Mandatory)][string]$MudletPackage,
    [Parameter(Mandatory)][string]$ApplicationArchive,
    [string]$OutputPath = (Join-Path $PSScriptRoot "..\dist\update-manifest.json"),
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$mfilePath = Join-Path $repository "accessible_lament_map\mfile"
$luaPath = Join-Path $repository "accessible_lament_map\src\scripts\Accessible Lament Map\LamentMapper.lua"
$cargoPath = Join-Path $repository "Cargo.toml"

$mfile = Get-Content -Raw -LiteralPath $mfilePath | ConvertFrom-Json
$mudletVersion = [string]$mfile.version
$lua = Get-Content -Raw -LiteralPath $luaPath
if ($lua -notmatch 'lamentMapper\.packageVersion\s*=\s*"(?<version>[^"]+)"') {
    throw "Could not find lamentMapper.packageVersion in $luaPath"
}
$luaVersion = $Matches.version
$cargo = Get-Content -Raw -LiteralPath $cargoPath
if ($cargo -notmatch '(?ms)^\[package\].*?^version\s*=\s*"(?<version>[^"]+)"') {
    throw "Could not find the Cargo package version in $cargoPath"
}
$applicationVersion = $Matches.version

$stableSemVer = '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
foreach ($component in @(
    @{ Name = "Muddler"; Version = $mudletVersion },
    @{ Name = "Lua package"; Version = $luaVersion },
    @{ Name = "Cargo package"; Version = $applicationVersion }
)) {
    if ($component.Version -cnotmatch $stableSemVer) {
        throw "$($component.Name) version is not stable three-part SemVer: $($component.Version)"
    }
}
if ($luaVersion -cne $mudletVersion) {
    throw "Lua package version $luaVersion does not match Muddler version $mudletVersion"
}

foreach ($asset in @($MudletPackage, $ApplicationArchive)) {
    if (-not (Test-Path -LiteralPath $asset -PathType Leaf)) {
        throw "Update asset is missing: $asset"
    }
}
if ([IO.Path]::GetFileName($MudletPackage) -cne "Accessible-Lament-Map.mpackage") {
    throw "Mudlet update asset must be named Accessible-Lament-Map.mpackage"
}
if ([IO.Path]::GetFileName($ApplicationArchive) -cne "LamentMapper-windows-x64.zip") {
    throw "Application update asset must be named LamentMapper-windows-x64.zip"
}

function Get-AssetMetadata {
    param([Parameter(Mandatory)][string]$Path)
    $file = Get-Item -LiteralPath $Path
    $name = $file.Name
    [ordered]@{
        url = "https://github.com/ironcross32/LamentMap/releases/download/$ReleaseTag/$name"
        size = $file.Length
        sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

$expected = [ordered]@{
    schema_version = 1
    release_tag = $ReleaseTag
    release_url = "https://github.com/ironcross32/LamentMap/releases/tag/$ReleaseTag"
    mudlet = [ordered]@{
        version = $mudletVersion
        asset = Get-AssetMetadata -Path $MudletPackage
    }
    application = [ordered]@{
        version = $applicationVersion
        asset = Get-AssetMetadata -Path $ApplicationArchive
    }
}

if ($ValidateOnly) {
    if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
        throw "Manifest is missing: $OutputPath"
    }
    $actual = Get-Content -Raw -LiteralPath $OutputPath | ConvertFrom-Json
    $expectedJson = $expected | ConvertTo-Json -Depth 8 -Compress
    $actualJson = $actual | ConvertTo-Json -Depth 8 -Compress
    if ($actualJson -cne $expectedJson) {
        throw "Manifest contents do not match source versions, pinned URLs, sizes, or checksums"
    }
    Write-Host "Validated $OutputPath"
    return
}

$parent = Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))
New-Item -ItemType Directory -Force -Path $parent | Out-Null
$json = $expected | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
Write-Host "Created $OutputPath"
