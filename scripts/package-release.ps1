[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$MudletPackage,
    [string]$Executable = (Join-Path $PSScriptRoot "..\target\release\LamentMapper.exe"),
    [string]$PrismDll = (Join-Path $PSScriptRoot "..\deps\prism\prism.dll"),
    [string]$SoundPack = (Join-Path $PSScriptRoot "..\sounds.pack"),
    [string]$Guide = (Join-Path $PSScriptRoot "..\dist\README.html"),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "..\dist")
)

$ErrorActionPreference = "Stop"
$output = [IO.Path]::GetFullPath($OutputDirectory)
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$stage = Join-Path $output "LamentMapper"
$zip = Join-Path $output "LamentMapper-windows-x64.zip"

$required = @{
    "LamentMapper.exe" = [IO.Path]::GetFullPath($Executable)
    "prism.dll" = [IO.Path]::GetFullPath($PrismDll)
    "sounds.pack" = [IO.Path]::GetFullPath($SoundPack)
    "README.html" = [IO.Path]::GetFullPath($Guide)
    "Accessible Lament Map.mpackage" = [IO.Path]::GetFullPath($MudletPackage)
    "LICENSE.txt" = Join-Path $repository "LICENSE"
    "THIRD_PARTY_NOTICES.txt" = Join-Path $repository "THIRD_PARTY_NOTICES.md"
    "PRISM-LICENSE.txt" = Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($PrismDll))) "PRISM-LICENSE.txt"
    "PRISM-NOTICE.txt" = Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($PrismDll))) "PRISM-NOTICE.txt"
}
foreach ($entry in $required.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) {
        throw "Required release file is missing: $($entry.Value)"
    }
}

New-Item -ItemType Directory -Force -Path $output | Out-Null
if (Test-Path -LiteralPath $stage) {
    $resolvedStage = [IO.Path]::GetFullPath($stage)
    if (-not $resolvedStage.StartsWith($output, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe staging path: $resolvedStage"
    }
    Remove-Item -LiteralPath $resolvedStage -Recurse -Force
}
New-Item -ItemType Directory -Path $stage | Out-Null
foreach ($entry in $required.GetEnumerator()) {
    Copy-Item -LiteralPath $entry.Value -Destination (Join-Path $stage $entry.Key)
}

$checksumLines = Get-ChildItem -LiteralPath $stage -File |
    Sort-Object Name |
    ForEach-Object {
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $($_.Name)"
    }
[IO.File]::WriteAllLines((Join-Path $stage "SHA256SUMS.txt"), $checksumLines, [Text.UTF8Encoding]::new($false))
if (Test-Path -LiteralPath $zip) {
    Remove-Item -LiteralPath $zip -Force
}
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip -CompressionLevel Optimal
Write-Host "Created $zip"

if (Test-Path -LiteralPath (Join-Path $stage "config.toml")) {
    throw "Generated configuration must not be shipped."
}
